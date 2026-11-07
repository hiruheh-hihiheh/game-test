extends Node
## Cloud save orchestrator. Autoloaded as "Cloud".
##
## The local save file stays the source of truth: the game never waits for the cloud, never reads progress from it
## while playing, and every cloud problem leaves local progress exactly as it was.
##
## To tell "this device changed" from "the cloud changed", a small file beside the save (starfall_save.cfg.cloud)
## remembers the fingerprints of the last state both sides agreed on. It holds no account data and no tokens.
##   cloud == this device              -> already in sync
##   fresh install, cloud has a save   -> restore it, silently
##   only this device changed          -> upload
##   only the cloud changed            -> restore it (this device's old save is kept as a backup file)
##   both changed, or an erased save   -> ask the player; nothing is overwritten until they choose
## Nothing is ever merged: a lower balance may be a real purchase.

signal changed
signal conflict_found
signal restored

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

var _fail_kind := ""
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
	conflict = {}
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
	return "SYNC ERROR"

## One honest line about the account. Google Play Games v2 signs the player in through the Play Games app and
## the game never receives a name or a picture, so none is shown.
func account_text() -> String:
	match backend.auth:
		CloudSave.Auth.UNAVAILABLE:
			if OS.get_name() == "Android":
				return "Google Play Games is not available in this build. Progress is saved on this device only."
			return "Cloud saves need the Android version with Google Play Games. Progress is saved on this device only."
		CloudSave.Auth.CHECKING:
			return "Checking your Google Play Games sign-in."
		CloudSave.Auth.SIGNED_OUT:
			return "Not signed in to Google Play Games. Progress is saved on this device only."
		CloudSave.Auth.ERROR:
			return "Could not check your Google Play Games sign-in."
	return "Signed in with Google Play Games. Google manages your player name and account."

func detail_text() -> String:
	match status():
		Status.CONFLICT:
			return "This device and your cloud save both changed. Choose which one to keep."
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
	return signed_in() and not busy and conflict.is_empty()

func can_connect() -> bool:
	return backend.available() and (backend.auth == CloudSave.Auth.SIGNED_OUT or backend.auth == CloudSave.Auth.ERROR)

# ---------- Actions ----------

func connect_account() -> void:
	if can_connect():
		backend.retry_auth()

## Hold during a flight so no sync work competes with combat. Release after it.
func hold(on: bool) -> void:
	held = on
	if not on and pending and signed_in() and conflict.is_empty():
		_schedule(2.0)

func sync_now() -> void:
	if not signed_in():
		return
	if busy:
		_again = true
		return
	if not conflict.is_empty():
		return
	_timer.stop()
	_last_attempt = Time.get_ticks_msec()
	busy = true
	_fail_kind = ""
	last_error = ""
	changed.emit()
	var tok := _begin()
	backend.load_snapshot(CloudSave.SNAPSHOT_NAME, func(r): _on_loaded(tok, r))

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
		_fail(str(r.get("kind", "error")), str(r.get("detail", "")))
		return
	var local := Save.to_dict()
	if not bool(r.get("found", false)):
		if CloudSave.has_progress(local):
			_upload(local)
		else:
			_finish_ok()
		return
	var dec := CloudSave.decode(r.get("bytes", PackedByteArray()))
	if not bool(dec.ok):
		if CloudSave.has_progress(local):
			_raise_conflict(local, {}, str(dec.error))
		else:
			_fail("error", str(dec.error) + ". It was not used.")
		return
	_decide(local, dec.data)

func _decide(local: Dictionary, cloud: Dictionary) -> void:
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
			_restore(cloud, ch)
		else:
			_raise_conflict(local, cloud, "")
		return
	var local_changed := lh != _base_local
	var cloud_changed := ch != _base_cloud
	if not local_changed and not cloud_changed:
		_finish_ok()
	elif not cloud_changed:
		if not local_has and CloudSave.has_progress(cloud):
			_raise_conflict(local, cloud, "")  # a save that was erased on this device is never pushed silently
		else:
			_upload(local)
	elif not local_changed:
		_restore(cloud, ch)
	else:
		_raise_conflict(local, cloud, "")

func _upload(local: Dictionary) -> void:
	var lh := CloudSave.progress_hash(local)
	var tok := _begin()
	var pilot := Pilot.level_of(int(local.get("pilot_xp", 0)))
	var text := "Pilot level %d - %d salvage" % [int(pilot.level), int(local.get("salvage", 0))]
	# The write time is the progress value: the newest write wins, even where Google settles a conflict itself.
	backend.save_snapshot(CloudSave.SNAPSHOT_NAME, text, CloudSave.encode(local), int(Time.get_unix_time_from_system()), func(r): _on_uploaded(tok, lh, r))

func _on_uploaded(tok: int, lh: String, r: Dictionary) -> void:
	if not _accept(tok):
		return
	if not bool(r.get("ok", false)):
		_fail(str(r.get("kind", "error")), str(r.get("detail", "")))
		return
	_force_local = false
	if bool(r.get("conflict", false)):
		# Google settled a conflict by itself. Look again before believing the upload won.
		_again = true
	else:
		_record(lh, lh)
	_finish_ok()

func _restore(cloud: Dictionary, ch: String) -> void:
	_keep_copy_of_local()
	_applying = true
	Save.restore_progress(cloud)
	_applying = false
	_record(CloudSave.progress_hash(Save.to_dict()), ch)
	conflict = {}
	restored.emit()
	_finish_ok()

## Before a restore the save file is copied to .before_cloud and the old progress is also kept in the cloud format.
func _keep_copy_of_local() -> void:
	if FileAccess.file_exists(Save.path):
		DirAccess.copy_absolute(Save.path, Save.path + ".before_cloud")
	_write_blob(Save.path + ".cloudconflict", CloudSave.encode(Save.to_dict()))

func _write_blob(file_path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()

func _raise_conflict(local: Dictionary, cloud: Dictionary, bad: String) -> void:
	conflict = {"local": CloudSave.summarize(local), "cloud": CloudSave.summarize(cloud) if not cloud.is_empty() else {}, "cloud_data": cloud, "bad": bad}
	busy = false
	changed.emit()
	conflict_found.emit()

## The player chose this device's save. The cloud save it replaces is kept in a file here first.
func keep_local() -> void:
	if conflict.is_empty() or busy or not signed_in():
		return
	var cloud: Dictionary = conflict.cloud_data
	if not cloud.is_empty():
		_write_blob(Save.path + ".cloudconflict", CloudSave.encode(cloud))
	conflict = {}
	_force_local = true
	busy = true
	_fail_kind = ""
	_upload(Save.to_dict())
	changed.emit()

## The player chose the cloud save. This device's save is kept in a file here first.
func restore_cloud() -> void:
	if conflict.is_empty() or busy:
		return
	var cloud: Dictionary = conflict.cloud_data
	if cloud.is_empty():
		return  # an unreadable cloud save can never be restored
	busy = true
	_restore(cloud, CloudSave.progress_hash(cloud))

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
		_:
			last_error = ("Cloud sync failed. " + detail).strip_edges() + " Your progress is safe on this device."
	_refresh_pending()
	changed.emit()
	if signed_in():
		_schedule(float(RETRY_STEPS[mini(_retry_step, RETRY_STEPS.size() - 1)]))
		_retry_step += 1

func _schedule(seconds: float) -> void:
	if _timer == null or not is_inside_tree():
		return
	_timer.start(maxf(seconds, 0.05))

func _on_timer() -> void:
	if not signed_in() or busy or not conflict.is_empty():
		return
	if held:
		_schedule(5.0)
		return
	sync_now()

func _on_auth() -> void:
	if signed_in():
		changed.emit()
		if not busy:
			sync_now()
	else:
		busy = false
		_op += 1
		changed.emit()

func _on_saved() -> void:
	if _applying:
		return
	_refresh_pending()
	changed.emit()
	if pending and signed_in() and conflict.is_empty() and busy == false and _timer.is_stopped():
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
		if pending and not busy and conflict.is_empty():
			sync_now()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		var now := Time.get_ticks_msec()
		if not busy and conflict.is_empty() and not held and now - _last_attempt > RESUME_GAP_MSEC:
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
	c.save(_state_path())
