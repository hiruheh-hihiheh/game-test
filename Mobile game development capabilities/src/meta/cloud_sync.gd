extends Node
## Cloud save orchestrator. Autoloaded as "Cloud".
##
## The local save file stays the source of truth: the game never waits for the cloud, never reads progress from it
## while playing, and every cloud problem leaves local progress exactly as it was.
##
## To tell "this device changed" from "the cloud changed", a small file beside the save (starfall_save.cfg.cloud)
## remembers the fingerprints of the last state both sides agreed on, and a one-way hash of the Google Play Games
## player id it belongs to. It holds no tokens and never the id itself.
##   cloud == this device              -> already in sync
##   fresh install, cloud has a save   -> restore it, silently
##   only this device changed          -> upload
##   only the cloud changed            -> restore it (this device's old save is kept as a backup file)
##   both changed, or an erased save   -> ask the player; nothing is overwritten until they choose
## Nothing is ever merged: a lower balance may be a real purchase.
##
## Accounts: before every sync the backend confirms which player is signed in. If that is not the player this device
## last synced with, nothing is uploaded or restored. The player sees both saves and chooses, and until then neither
## the local save nor the new account's cloud save is changed. If the identity cannot be confirmed, nothing syncs.

signal changed
signal conflict_found
signal restored
signal account_found

const Status = CloudSave.Status

const DEBOUNCE := 6.0
const TIMEOUT := 25.0
const RETRY_STEPS := [15.0, 30.0, 60.0, 120.0, 300.0]
const RESUME_GAP_MSEC := 60000

## Set false before add_child when a test builds its own instance.
var autostart := true
var backend: CloudSave.Backend = CloudSave.Backend.new()
var debounce := DEBOUNCE
var timeout := TIMEOUT
var busy := false
var held := false
var last_sync := 0
var pending := false
var last_error := ""
## {"local": summary, "cloud": summary, "cloud_data": Dictionary, "bad": text}. Empty when nothing needs a decision.
var conflict := {}
## Set while a different player is signed in than the one this device synced with:
## {"cloud": summary, "cloud_data": Dictionary, "bad": text, "empty": bool, "probed": bool, "suspended": bool}.
var account_change := {}
## Seconds to wait for Google Play Games to answer the sign-in check.
var auth_timeout := 20.0
## Why the last decision the player made was not carried out, in plain words ("" when nothing is wrong).
## Set when a backup copy could not be written: nothing was replaced, and the decision is still open.
var choice_error := ""

var _account := ""
var _pending_account := ""
var _auth_epoch := 0
var _fail_kind := ""
var _conflict_info := {}
var _synced_once := false
var _has_base := false
var _base_local := ""
var _base_cloud := ""
var _op := 0
var _again := false
var _retry_step := 0
var _applying := false
var _force_local := false
var _last_attempt := -RESUME_GAP_MSEC
var _timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_on_timer)
	Save.saved.connect(_on_saved)
	_load_state()
	cleanup_recovery_temps()
	if autostart:
		use(CloudSave.make_backend())

func _exit_tree() -> void:
	if Save.saved.is_connected(_on_saved):
		Save.saved.disconnect(_on_saved)

## Chooses the backend (tests pass a mock) and starts checking sign-in.
func use(b: CloudSave.Backend) -> void:
	if backend.auth_changed.is_connected(_on_auth):
		backend.auth_changed.disconnect(_on_auth)
	backend = b
	_op += 1
	busy = false
	backend.auth_changed.connect(_on_auth)
	_refresh_pending()
	backend.start(self)
	_on_auth()

## Forgets what was last synced (a new player, or a test). Does not touch the save itself.
func forget_state() -> void:
	_has_base = false
	_base_local = ""
	_base_cloud = ""
	last_sync = 0
	_synced_once = false
	_force_local = false
	_account = ""
	_pending_account = ""
	conflict = {}
	account_change = {}
	DirAccess.remove_absolute(_state_path())
	_refresh_pending()

# ---------- What the screens read ----------

func signed_in() -> bool:
	return backend.auth == CloudSave.Auth.SIGNED_IN

func status() -> int:
	match backend.auth:
		CloudSave.Auth.UNAVAILABLE, CloudSave.Auth.SIGNED_OUT:
			return Status.GUEST
		CloudSave.Auth.CHECKING:
			return Status.CONNECTING
		CloudSave.Auth.ERROR:
			return Status.ERROR
	if not account_change.is_empty():
		return Status.ACCOUNT
	if not conflict.is_empty():
		return Status.CONFLICT
	if busy:
		# Signed in but nothing has gone through yet: still connecting the save, not a routine sync.
		return Status.SYNCING if _synced_once else Status.CONNECTED
	if _fail_kind == "offline" or _fail_kind == "timeout":
		return Status.OFFLINE
	if _fail_kind != "":
		return Status.ERROR
	if pending:
		return Status.PENDING
	return Status.SYNCED if _synced_once else Status.CONNECTED

func status_label() -> String:
	match status():
		Status.GUEST:
			return "LOCAL GUEST"
		Status.CONNECTING:
			return "CONNECTING"
		Status.CONNECTED:
			return "GOOGLE PLAY GAMES CONNECTED"
		Status.SYNCING:
			return "SYNCING"
		Status.SYNCED:
			return "CLOUD SYNCED"
		Status.PENDING:
			return "SYNC PENDING"
		Status.OFFLINE:
			return "OFFLINE"
		Status.CONFLICT:
			return "CHOOSE A SAVE"
		Status.ACCOUNT:
			return "SYNC PAUSED" if bool(account_change.get("suspended", false)) else "ACCOUNT CHANGED"
	return "SYNC ERROR"

## One honest line about the account. Google Play Games v2 signs the player in through the Play Games app and
## the game never receives a name or a picture, so none is shown.
func account_text() -> String:
	match backend.auth:
		CloudSave.Auth.UNAVAILABLE:
			if not backend.auth_detail.is_empty():
				return backend.auth_detail + " Progress is saved on this device only."
			if OS.get_name() == "Android":
				return "Google Play Games is not available in this build. Progress is saved on this device only."
			return "Cloud saves need the Android version with Google Play Games. Progress is saved on this device only."
		CloudSave.Auth.CHECKING:
			return "Checking your Google Play Games sign-in."
		CloudSave.Auth.SIGNED_OUT:
			return "Not signed in to Google Play Games. Progress is saved on this device only."
		CloudSave.Auth.ERROR:
			return backend.auth_detail if not backend.auth_detail.is_empty() else "Could not check your Google Play Games sign-in."
	return "Signed in with Google Play Games. Google manages your player name and account."

func detail_text() -> String:
	match status():
		Status.CONFLICT:
			return "This device and your cloud save both changed. Choose which one to keep."
		Status.ACCOUNT:
			if bool(account_change.get("suspended", false)):
				return "Cloud sync is paused because a different Google Play Games account is signed in. Nothing was changed."
			return "A different Google Play Games account is signed in than the one this device last synced with. Nothing was changed. Choose what to do."
		Status.OFFLINE, Status.ERROR:
			return last_error if not last_error.is_empty() else "Cloud sync did not finish. Your progress is safe on this device."
		Status.PENDING:
			return "Changes on this device are waiting to upload."
		Status.SYNCING:
			return "Talking to Google Play Games."
		Status.SYNCED:
			return "This device matches your cloud save."
		Status.CONNECTED:
			return "Checking your cloud save."
	return ""

func last_sync_text() -> String:
	if last_sync <= 0:
		return "NEVER SYNCED"
	var ago := int(Time.get_unix_time_from_system()) - last_sync
	if ago < 60:
		return "LAST SYNC JUST NOW"
	if ago < 3600:
		return "LAST SYNC %d MIN AGO" % (ago / 60)
	if ago < 86400:
		return "LAST SYNC %d H AGO" % (ago / 3600)
	return "LAST SYNC %d DAYS AGO" % (ago / 86400)

func unsynced() -> bool:
	return pending

## The Sync Now button works when signed in, nothing is running and no decision is waiting.
func can_sync() -> bool:
	return signed_in() and not busy and conflict.is_empty() and account_change.is_empty()

func can_connect() -> bool:
	return backend.available() and (backend.auth == CloudSave.Auth.SIGNED_OUT or backend.auth == CloudSave.Auth.ERROR)

# ---------- Actions ----------

func connect_account() -> void:
	if can_connect():
		backend.retry_auth()

## Hold during a flight so no sync work competes with combat. Release after it.
func hold(on: bool) -> void:
	held = on
	if not on and pending and signed_in() and conflict.is_empty() and account_change.is_empty():
		_schedule(2.0)

## `manual` is the player pressing a button. Only that may look again while an account decision is waiting.
func sync_now(manual := false) -> void:
	if not signed_in():
		return
	if busy:
		_again = true
		return
	if not conflict.is_empty():
		return
	if not account_change.is_empty() and not manual:
		return
	_timer.stop()
	_last_attempt = Time.get_ticks_msec()
	busy = true
	_fail_kind = ""
	last_error = ""
	changed.emit()
	# Who is signed in is confirmed before anything is read or written.
	var tok := _begin()
	backend.check_account(func(r): _on_account(tok, r))

func _on_account(tok: int, r: Dictionary) -> void:
	if not _accept(tok):
		return
	var id := str(r.get("account_id", ""))
	if not bool(r.get("ok", false)) or id.is_empty():
		var kind := str(r.get("kind", "identity"))
		_fail(kind if kind in ["offline", "timeout", "auth"] else "identity", str(r.get("detail", "")))
		return
	var hashed := CloudSave.account_hash(id)
	if _account.is_empty():
		# First sync with an account. Any older record cannot be tied to anyone, so it is not trusted.
		_bind_account(hashed)
	elif _account != hashed:
		_start_probe(hashed)
		return
	elif not account_change.is_empty():
		account_change = {}  # the bound account is back
	_load_step()

func _load_step() -> void:
	var tok := _begin()
	backend.load_snapshot(CloudSave.SNAPSHOT_NAME, func(r): _on_loaded(tok, r))

func _bind_account(hashed: String) -> void:
	_account = hashed
	_has_base = false
	_base_local = ""
	_base_cloud = ""
	_save_state()
	_refresh_pending()

func _begin() -> int:
	_op += 1
	var tok := _op
	if is_inside_tree():
		get_tree().create_timer(timeout, true).timeout.connect(_on_op_timeout.bind(tok))
	return tok

func _accept(tok: int) -> bool:
	if tok != _op or not busy:
		return false
	_op += 1
	return true

func _on_op_timeout(tok: int) -> void:
	if tok != _op or not busy:
		return
	_op += 1
	backend.abort()
	_fail("timeout", "Google Play Games did not answer in time.")

func _on_loaded(tok: int, r: Dictionary) -> void:
	if not _accept(tok):
		return
	if not bool(r.get("ok", false)):
		_fail_result(r)
		return
	var local := Save.to_dict()
	if not bool(r.get("found", false)):
		if CloudSave.has_progress(local):
			_upload(local)
		else:
			_finish_ok()
		return
	# The bytes exactly as the cloud sent them. They are kept as they are, readable or not, before anything replaces them.
	var raw: PackedByteArray = r.get("bytes", PackedByteArray())
	var dec := CloudSave.decode(raw)
	if not bool(dec.ok):
		if CloudSave.has_progress(local):
			_raise_conflict(local, {}, str(dec.error), raw)
		else:
			_fail("error", str(dec.error) + ". It was not used.")
		return
	_decide(local, dec.data, raw)

func _decide(local: Dictionary, cloud: Dictionary, raw: PackedByteArray) -> void:
	var lh := CloudSave.progress_hash(local)
	var ch := CloudSave.progress_hash(cloud)
	if lh == ch:
		_record(lh, ch)
		_finish_ok()
		return
	var local_has := CloudSave.has_progress(local)
	if _force_local and local_has:
		_upload(local)
		return
	if not _has_base:
		if not local_has:
			_restore_silently(cloud, ch)
		else:
			_raise_conflict(local, cloud, "", raw)
		return
	var local_changed := lh != _base_local
	var cloud_changed := ch != _base_cloud
	if not local_changed and not cloud_changed:
		_finish_ok()
	elif not cloud_changed:
		if not local_has and CloudSave.has_progress(cloud):
			_raise_conflict(local, cloud, "", raw)  # a save that was erased on this device is never pushed silently
		else:
			_upload(local)
	elif not local_changed:
		_restore_silently(cloud, ch)
	else:
		_raise_conflict(local, cloud, "", raw)

func _upload(local: Dictionary) -> void:
	var lh := CloudSave.progress_hash(local)
	var tok := _begin()
	var pilot := Pilot.level_of(int(local.get("pilot_xp", 0)))
	var text := "Pilot level %d - %d salvage" % [int(pilot.level), int(local.get("salvage", 0))]
	# The write time is the progress value, so the newest write is the highest under any automatic policy.
	backend.save_snapshot(CloudSave.SNAPSHOT_NAME, text, CloudSave.encode(local), int(Time.get_unix_time_from_system()), func(r): _on_uploaded(tok, lh, r))

func _on_uploaded(tok: int, lh: String, r: Dictionary) -> void:
	if not _accept(tok):
		return
	if not bool(r.get("ok", false)):
		_fail_result(r)
		return
	_force_local = false
	_record(lh, lh)
	_finish_ok()

## Replaces this device's progress with `cloud`. Returns false, having changed nothing, when this device's own save
## could not be copied away first.
func _restore(cloud: Dictionary, ch: String, backup := true) -> bool:
	if backup and not _keep_copy_of_local():
		_backup_failed("this device's save")
		return false
	_force_local = false
	_applying = true
	Save.restore_progress(cloud)
	_applying = false
	_record(CloudSave.progress_hash(Save.to_dict()), ch)
	conflict = {}
	choice_error = ""
	restored.emit()
	_finish_ok()
	return true

## A restore nobody was asked about (a new install, or another device played). If the backup cannot be made it does not happen.
func _restore_silently(cloud: Dictionary, ch: String) -> void:
	if not _restore(cloud, ch):
		choice_error = ""
		_fail("backup", "")

func _backup_failed(what: String) -> void:
	choice_error = "Could not keep a copy of %s on this device, so nothing was replaced. Your saves are unchanged, and earlier recovery copies are untouched. Free some storage space and try again." % what

# ---------- Recovery copies ----------
#
# Every copy that makes a replacement recoverable goes in one folder beside the save, starfall_save.cfg.recovery/.
# Each operation gets the next generation number and its files are named <generation>_<kind>.<ext>:
#   cloud_save        a cloud save exactly as the cloud sent it, kept before this device's save replaced it
#   local_save_file   a copy of starfall_save.cfg, kept before a cloud save replaced the progress
#   local_progress    the same progress in the cloud blob format
#   google_version_N  a version Google reported in a snapshot conflict
# A recovery file is NEVER overwritten and never deleted by the game. A new file is written to a temporary name,
# read back and compared byte for byte, and only then renamed into place, so a failure at any step leaves every
# earlier recovery file as it was. Only unfinished temporary files (tmp_*.part) are ever removed.

func _recovery_dir() -> String:
	return Save.path + ".recovery"

func _ensure_recovery_dir() -> bool:
	var dir := _recovery_dir()
	if DirAccess.dir_exists_absolute(dir):
		return true
	if DirAccess.make_dir_recursive_absolute(dir) != OK or not DirAccess.dir_exists_absolute(dir):
		return false
	_write_readme()
	return true

func _write_readme() -> void:
	var text := "Starfall Salvage recovery copies\n\nEach number is one operation. The highest number is the newest.\nDo not delete anything here until you have recovered what you need.\n\ncloud_save        a cloud save, exactly as the cloud sent it, kept before this device's save replaced it\nlocal_save_file   a copy of this device's save file, kept before a cloud save replaced it\nlocal_progress    the same progress as a cloud blob (plain text)\ngoogle_version_N  a version Google reported in a snapshot conflict\n\ntmp_*.part files are unfinished writes and are safe to delete.\n"
	var tmp := _temp_path("readme")
	if _write_verified(tmp, text.to_utf8_buffer()) and not FileAccess.file_exists(_recovery_dir() + "/README.txt"):
		if not _promote(tmp, _recovery_dir() + "/README.txt"):
			_discard(tmp)
	else:
		_discard(tmp)

## The next unused generation number: one more than the highest in the folder.
func _next_generation() -> int:
	var top := 0
	var d := DirAccess.open(_recovery_dir())
	if d != null:
		for f in d.get_files():
			if f.length() > 7 and f.substr(0, 6).is_valid_int() and f[6] == "_":
				top = maxi(top, int(f.substr(0, 6)))
	return top + 1

func _temp_path(kind: String) -> String:
	return "%s/tmp_%s_%d_%d.part" % [_recovery_dir(), kind, Time.get_ticks_usec(), randi() % 1000000]

## Writes one new recovery file: to a temporary name first (from `bytes`, or by copying `source` when it is given),
## verified byte for byte, then renamed to <generation>_<kind>.<ext>. An existing file is never replaced. On any
## failure the temporary file is discarded and every earlier file is untouched.
func _recovery_put(gen: int, kind: String, ext: String, bytes: PackedByteArray, source := "") -> bool:
	if not _ensure_recovery_dir():
		return false
	var dest := "%s/%06d_%s.%s" % [_recovery_dir(), gen, kind, ext]
	if FileAccess.file_exists(dest):
		return false
	var tmp := _temp_path(kind)
	var ok: bool
	if source != "":
		ok = _copy_file(source, tmp)
		bytes = FileAccess.get_file_as_bytes(source) if ok else PackedByteArray()
	else:
		ok = _write_verified(tmp, bytes)
	if ok:
		ok = _promote(tmp, dest) and FileAccess.get_file_as_bytes(dest) == bytes
	if not ok:
		_discard(tmp)
	return ok

## A temporary file written, closed and read back. True only if it holds exactly `bytes`.
func _write_verified(file_path: String, bytes: PackedByteArray) -> bool:
	var f := _open_write(file_path)
	if f == null:
		return false
	var wrote := _store_bytes(f, file_path, bytes)
	f.close()
	return wrote and FileAccess.get_file_as_bytes(file_path) == bytes

## File access is in these small functions so tests can make each step fail.
func _open_write(file_path: String) -> FileAccess:
	return FileAccess.open(file_path, FileAccess.WRITE)

func _store_bytes(f: FileAccess, _file_path: String, bytes: PackedByteArray) -> bool:
	f.store_buffer(bytes)
	return f.get_error() == OK

func _copy_file(from: String, to: String) -> bool:
	return DirAccess.copy_absolute(from, to) == OK and FileAccess.get_file_as_bytes(to) == FileAccess.get_file_as_bytes(from)

func _promote(tmp: String, dest: String) -> bool:
	return DirAccess.rename_absolute(tmp, dest) == OK

func _discard(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)

## Removes unfinished temporary files (a crash mid-write leaves them). Recovery files are never touched.
func cleanup_recovery_temps() -> int:
	var n := 0
	var d := DirAccess.open(_recovery_dir())
	if d != null:
		for f in d.get_files():
			if f.begins_with("tmp_") and f.ends_with(".part"):
				if DirAccess.remove_absolute(_recovery_dir() + "/" + f) == OK:
					n += 1
	return n

## Every recovery file, oldest first. The last is the newest.
func recovery_files() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(_recovery_dir())
	if d != null:
		for f in d.get_files():
			if f.length() > 7 and f.substr(0, 6).is_valid_int() and f[6] == "_":
				out.append(_recovery_dir() + "/" + f)
	out.sort()
	return out

## Before this device's save is replaced: its save file is copied and its progress is also kept in the cloud blob
## format, as one new generation. True only if every file was written and verified.
func _keep_copy_of_local() -> bool:
	var gen := _next_generation()
	if FileAccess.file_exists(Save.path) and not _recovery_put(gen, "local_save_file", "cfg", PackedByteArray(), Save.path):
		return false
	return _recovery_put(gen, "local_progress", "blob", CloudSave.encode(Save.to_dict()))

## Before a cloud save is replaced: exactly the bytes the cloud sent, readable or not, as one new generation.
func _keep_copy_of_cloud(raw: PackedByteArray) -> bool:
	return _recovery_put(_next_generation(), "cloud_save", "blob", raw)

## Keeps every version Google reported, exactly, as one new recovery set. Older files, including those of an earlier
## conflict, are not touched. Returns {needed, saved, origin, generation, kept, lost}: only verified files count.
func _preserve_candidates(r: Dictionary) -> Dictionary:
	var gen := _next_generation()
	var kept: Array = []
	var lost: Array = []
	var n := 0
	for c in r.get("candidates", []):
		var bytes: PackedByteArray = c.get("bytes", PackedByteArray())
		if bytes.is_empty():
			continue
		n += 1
		if _recovery_put(gen, "google_version_%d" % n, "blob", bytes):
			kept.append(n)
		else:
			lost.append(n)
	return {"needed": n, "saved": kept.size(), "origin": str(r.get("origin", "")), "generation": gen, "kept": kept, "lost": lost}

## What the player is told about a conflict. It claims only what was actually written.
func _conflict_text(info: Dictionary) -> String:
	var needed := int(info.get("needed", 0))
	var saved := int(info.get("saved", 0))
	var origin := str(info.get("origin", ""))
	var when := "" if origin == "" else (" while saving" if origin == "SAVE" else " while loading")
	var head := "Google Play Games reported two different cloud versions of your save%s. This build cannot settle that, so nothing was changed." % when
	if needed == 0:
		return head + " No version was returned to keep. Your progress here is untouched."
	if saved == needed:
		var kept := "Both versions were" if needed == 2 else ("The version was" if needed == 1 else "All %d versions were" % needed)
		return head + " %s kept on this device (recovery set %d), and your progress here is untouched." % [kept, int(info.get("generation", 0))]
	var names := func(list: Array) -> String:
		var parts: Array = []
		for i in list:
			parts.append("version %d" % int(i))
		return ", ".join(parts) if not parts.is_empty() else "none"
	return head + " Could not keep a copy of %d of the %d versions on this device (kept: %s; not kept: %s). Earlier recovery copies and your progress here are untouched." % [needed - saved, needed, names.call(info.get("kept", [])), names.call(info.get("lost", []))]

func _raise_conflict(local: Dictionary, cloud: Dictionary, bad: String, raw: PackedByteArray) -> void:
	choice_error = ""
	conflict = {"local": CloudSave.summarize(local), "cloud": CloudSave.summarize(cloud) if not cloud.is_empty() else {}, "cloud_data": cloud, "bad": bad, "raw_bytes": raw}
	busy = false
	changed.emit()
	conflict_found.emit()

## The player chose this device's save. The cloud save it replaces, exactly as the cloud sent it, even if it was
## unreadable, is written to the recovery folder and verified first. If that fails, nothing is replaced.
func keep_local() -> void:
	if conflict.is_empty() or busy or not signed_in():
		return
	var raw: PackedByteArray = conflict.get("raw_bytes", PackedByteArray())
	if not raw.is_empty() and not _keep_copy_of_cloud(raw):
		_backup_failed("the cloud save")
		changed.emit()
		return
	choice_error = ""
	conflict = {}
	_force_local = true
	busy = true
	_fail_kind = ""
	_upload(Save.to_dict())
	changed.emit()

## The player chose the cloud save. This device's save is kept in files here first. If that fails, nothing is replaced.
func restore_cloud() -> void:
	if conflict.is_empty() or busy:
		return
	var cloud: Dictionary = conflict.cloud_data
	if cloud.is_empty():
		return  # an unreadable cloud save can never be restored
	busy = true
	if not _restore(cloud, CloudSave.progress_hash(cloud)):
		busy = false
		changed.emit()

# ---------- A different account is signed in ----------

## Reads the new account's cloud save, to show it. Nothing is written to either save. What it finds is kept exactly:
## the raw bytes of a snapshot, and any versions Google reports in a conflict.
func _start_probe(hashed: String) -> void:
	_pending_account = hashed
	choice_error = ""
	account_change = {"cloud": {}, "cloud_data": {}, "raw_bytes": PackedByteArray(), "bad": "", "empty": false, "probed": false, "suspended": false, "conflict": false, "replaceable": false}
	changed.emit()
	var tok := _begin()
	backend.load_snapshot(CloudSave.SNAPSHOT_NAME, func(r): _on_probe(tok, r))

func _on_probe(tok: int, r: Dictionary) -> void:
	if not _accept(tok):
		return
	busy = false
	if not bool(r.get("ok", false)):
		if str(r.get("kind", "")) == "conflict":
			# Both versions are kept. This account cannot be replaced or restored from while Google holds two.
			var info := _preserve_candidates(r)
			account_change.conflict = true
			account_change.probed = true
			account_change.bad = _conflict_text(info)
		else:
			account_change.bad = "This account's cloud save could not be read right now."
		last_error = account_change.bad
	elif not bool(r.get("found", false)):
		account_change.empty = true
		account_change.probed = true
		account_change.replaceable = true
	else:
		var raw: PackedByteArray = r.get("bytes", PackedByteArray())
		account_change.raw_bytes = raw
		var dec := CloudSave.decode(raw)
		if bool(dec.ok):
			account_change.cloud = CloudSave.summarize(dec.data)
			account_change.cloud_data = dec.data
		else:
			account_change.bad = str(dec.error)
		account_change.probed = true
		account_change.replaceable = true
	changed.emit()
	account_found.emit()

func _can_choose_account() -> bool:
	return not account_change.is_empty() and bool(account_change.probed) and not busy and signed_in() and not _pending_account.is_empty()

## The player chose to carry this device's save over to the new account. What that account had in the cloud, exactly as
## it was, even if unreadable, is written to the recovery folder and verified first. If that fails, nothing is replaced and
## the decision stays open. An empty save is never carried over a save that has progress.
func account_use_local() -> void:
	if not _can_choose_account() or not bool(account_change.get("replaceable", false)):
		return
	var local := Save.to_dict()
	if not CloudSave.has_progress(local):
		return
	var raw: PackedByteArray = account_change.get("raw_bytes", PackedByteArray())
	if not raw.is_empty() and not _keep_copy_of_cloud(raw):
		_backup_failed("the new account's cloud save")
		changed.emit()
		return
	choice_error = ""
	_bind_account(_pending_account)
	account_change = {}
	_force_local = true
	busy = true
	_fail_kind = ""
	_upload(local)
	changed.emit()

## The player chose the new account's cloud save. This device's save is kept in files here first. If that fails,
## nothing is replaced, the account is not bound, and the decision stays open.
func account_use_cloud() -> void:
	if not _can_choose_account():
		return
	var cloud: Dictionary = account_change.cloud_data
	if cloud.is_empty():
		return
	if not _keep_copy_of_local():
		_backup_failed("this device's save")
		changed.emit()
		return
	choice_error = ""
	_bind_account(_pending_account)
	account_change = {}
	busy = true
	_restore(cloud, CloudSave.progress_hash(cloud), false)

## Pause cloud sync for now. Both saves stay exactly as they are.
func account_pause() -> void:
	if not account_change.is_empty():
		account_change.suspended = true
		changed.emit()

func account_review() -> void:
	if not account_change.is_empty():
		account_change.suspended = false
		changed.emit()

# ---------- Results and scheduling ----------

func _finish_ok() -> void:
	busy = false
	_fail_kind = ""
	last_error = ""
	_synced_once = true
	_retry_step = 0
	# A round trip that worked, even one with nothing to move, confirms the cloud and this device agree.
	last_sync = int(Time.get_unix_time_from_system())
	if _has_base:
		_save_state()
	_refresh_pending()
	changed.emit()
	if _again:
		_again = false
		sync_now()
	elif pending and conflict.is_empty():
		_schedule(debounce)

## A failed backend request. A conflict keeps every version Google reported, as files, before failing.
func _fail_result(r: Dictionary) -> void:
	var kind := str(r.get("kind", "error"))
	if kind == "conflict":
		_conflict_info = _preserve_candidates(r)
		_fail("conflict", str(r.get("origin", "")))
	else:
		_fail(kind, str(r.get("detail", "")))

func _fail(kind: String, detail: String) -> void:
	busy = false
	_again = false
	_fail_kind = kind
	match kind:
		"offline":
			last_error = "No connection. Your progress is safe on this device and will upload when you are back online."
		"timeout":
			last_error = "Google Play Games did not answer in time. Your progress is safe on this device."
		"auth":
			last_error = "Google Play Games sign-in is needed. Your progress is safe on this device."
		"identity":
			last_error = "Could not confirm which Google Play Games account is signed in, so nothing was synced. Your progress is safe on this device."
		"backup":
			last_error = "Could not keep a copy of this device's save, so the cloud save was not restored. Nothing was changed, and your progress is safe on this device."
		"conflict":
			last_error = _conflict_text(_conflict_info)
		_:
			last_error = ("Cloud sync failed. " + detail).strip_edges() + " Your progress is safe on this device."
	_refresh_pending()
	changed.emit()
	# A conflict does not clear by itself, so only the player's own Sync Now tries it again.
	if signed_in() and kind != "conflict":
		_schedule(float(RETRY_STEPS[mini(_retry_step, RETRY_STEPS.size() - 1)]))
		_retry_step += 1

func _schedule(seconds: float) -> void:
	if _timer == null or not is_inside_tree():
		return
	_timer.start(maxf(seconds, 0.05))

func _on_timer() -> void:
	if not signed_in() or busy or not conflict.is_empty() or not account_change.is_empty():
		return
	if held:
		_schedule(5.0)
		return
	sync_now()

## Any change of sign-in state starts a new session. Nothing from the old one may finish, or decide, anything:
## the running request is abandoned (late answers are ignored by token and the backend drops its callbacks),
## scheduled work is cancelled, and pending decisions are forgotten because they described another session.
func _on_auth() -> void:
	_end_session()
	_auth_epoch += 1
	if backend.auth == CloudSave.Auth.CHECKING and is_inside_tree():
		get_tree().create_timer(auth_timeout, true).timeout.connect(_on_auth_timeout.bind(_auth_epoch))
	changed.emit()
	if signed_in():
		sync_now()

func _end_session() -> void:
	_op += 1
	backend.abort()
	busy = false
	_again = false
	_force_local = false
	_fail_kind = ""
	last_error = ""
	_retry_step = 0
	conflict = {}
	account_change = {}
	choice_error = ""
	if _timer != null:
		_timer.stop()

func _on_auth_timeout(epoch: int) -> void:
	if epoch == _auth_epoch and backend.auth == CloudSave.Auth.CHECKING:
		backend.set_auth(CloudSave.Auth.ERROR, "Google Play Games did not answer the sign-in check. Progress is saved on this device.")

func _on_saved() -> void:
	if _applying:
		return
	_refresh_pending()
	changed.emit()
	if pending and signed_in() and conflict.is_empty() and account_change.is_empty() and busy == false and _timer.is_stopped():
		_schedule(debounce)

func _refresh_pending() -> void:
	var local := Save.to_dict()
	if _has_base:
		pending = CloudSave.progress_hash(local) != _base_local
	else:
		pending = CloudSave.has_progress(local)

func _notification(what: int) -> void:
	if not signed_in():
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		# Going to the background may end the process: upload now rather than after the debounce.
		if pending and not busy and conflict.is_empty() and account_change.is_empty():
			sync_now()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		var now := Time.get_ticks_msec()
		if not busy and conflict.is_empty() and account_change.is_empty() and not held and now - _last_attempt > RESUME_GAP_MSEC:
			sync_now()

# ---------- What was last synced ----------

func _state_path() -> String:
	return Save.path + ".cloud"

func _load_state() -> void:
	var c := ConfigFile.new()
	if c.load(_state_path()) != OK:
		return
	_base_local = str(c.get_value("sync", "base_local", ""))
	_base_cloud = str(c.get_value("sync", "base_cloud", ""))
	last_sync = int(c.get_value("sync", "last_sync", 0))
	_account = str(c.get_value("sync", "account", ""))
	_has_base = not _base_local.is_empty() and not _base_cloud.is_empty()

func _record(lh: String, ch: String) -> void:
	_base_local = lh
	_base_cloud = ch
	_has_base = true
	last_sync = int(Time.get_unix_time_from_system())
	_save_state()

func _save_state() -> void:
	var c := ConfigFile.new()
	c.set_value("sync", "base_local", _base_local)
	c.set_value("sync", "base_cloud", _base_cloud)
	c.set_value("sync", "last_sync", last_sync)
	c.set_value("sync", "account", _account)
	c.save(_state_path())
