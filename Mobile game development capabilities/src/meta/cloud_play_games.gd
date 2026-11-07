extends CloudSave.Backend
## Google Play Games Services (v2) Saved Games, through the godot-play-game-services plugin.
##
## NOT VERIFIED ON A DEVICE. The plugin is not installed in this repository, so this adapter has only been
## read against the plugin's published API, never run against it. See docs/CLOUD_SAVE.md for the install steps
## and the checks to make on a phone. Everything here is looked up by name at run time, so the project still
## opens, exports and plays on desktop without the plugin.
##
## What the plugin offers, and how this adapter copes:
##   * game_saved(is_saved, ...) fires on success only        -> Cloud times every call out and treats silence as failure.
##   * game_loaded(snapshot) can be null                       -> loads with create_if_not_found, so null always means "error".
##   * it resolves snapshot conflicts itself                   -> progress_value is the write time, so the newest write wins,
##                                                                and Cloud re-checks after any reported conflict.
##   * the type of snapshot.content is not documented          -> the blob is plain JSON text, read back whatever the type.
##
## No access tokens are read, stored or logged here. Google signs the player in through the Play Games app.

const SIGN_IN_NODE := "PlayGamesSignInClient"
const SNAPSHOTS_NODE := "PlayGamesSnapshotsClient"

var _sign_in: Object
var _snapshots: Object
var _load_done := Callable()
var _save_done := Callable()
var _conflict_seen := false
var _wired := false

func label() -> String:
	return "Google Play Games"

static func _singleton(node_name: String) -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(node_name)
	return null

func available() -> bool:
	if OS.get_name() != "Android":
		return false
	var s := _singleton(SIGN_IN_NODE)
	var n := _singleton(SNAPSHOTS_NODE)
	return s != null and n != null and s.has_method("is_authenticated") and n.has_method("save_game") and n.has_method("load_game")

func start(_host: Node) -> void:
	_sign_in = _singleton(SIGN_IN_NODE)
	_snapshots = _singleton(SNAPSHOTS_NODE)
	if _sign_in == null or _snapshots == null:
		set_auth(CloudSave.Auth.UNAVAILABLE)
		return
	if not _wired:
		_wired = true
		_connect(_sign_in, "user_authenticated", _on_authenticated)
		_connect(_snapshots, "game_loaded", _on_loaded)
		_connect(_snapshots, "game_saved", _on_saved)
		_connect(_snapshots, "conflict_emitted", _on_conflict)
	set_auth(CloudSave.Auth.CHECKING)
	_sign_in.call("is_authenticated")

static func _connect(obj: Object, signal_name: String, handler: Callable) -> void:
	if obj.has_signal(signal_name) and not obj.is_connected(signal_name, handler):
		obj.connect(signal_name, handler)

func retry_auth() -> void:
	if _sign_in == null:
		return
	set_auth(CloudSave.Auth.CHECKING)
	# The player asked for this, so it may show Google's own sign-in screen.
	if _sign_in.has_method("sign_in"):
		_sign_in.call("sign_in")
	else:
		_sign_in.call("is_authenticated")

## Cloud gave up waiting. A late answer from the plugin is then ignored, and the next request may start.
func abort() -> void:
	_load_done = Callable()
	_save_done = Callable()

func _on_authenticated(signed_in: bool) -> void:
	set_auth(CloudSave.Auth.SIGNED_IN if signed_in else CloudSave.Auth.SIGNED_OUT)

# ---------- Snapshots ----------

## The blob from CloudSave.encode is UTF-8 JSON text already, so it is stored as it is.
static func _pack(bytes: PackedByteArray) -> PackedByteArray:
	return bytes

## Reads snapshot content whatever type the plugin hands back. Empty when it cannot be read.
static func _unpack(content) -> PackedByteArray:
	var raw := PackedByteArray()
	if content is PackedByteArray:
		raw = content
	elif content is Array:
		for v in content:
			raw.append(int(v) & 0xFF)
	elif content is String:
		raw = (content as String).to_utf8_buffer()
	return raw

func load_snapshot(snapshot_name: String, done: Callable) -> void:
	if _snapshots == null or auth != CloudSave.Auth.SIGNED_IN:
		done.call_deferred({"ok": false, "found": false, "kind": "auth", "detail": "not signed in"})
		return
	if _load_done.is_valid() or _save_done.is_valid():
		done.call_deferred({"ok": false, "found": false, "kind": "error", "detail": "another cloud request is running"})
		return
	_load_done = done
	_conflict_seen = false
	_snapshots.call("load_game", snapshot_name, true)

func _on_loaded(snapshot) -> void:
	if not _load_done.is_valid():
		return
	var done := _load_done
	_load_done = Callable()
	if snapshot == null:
		done.call({"ok": false, "found": false, "kind": "error", "detail": "the snapshot could not be opened"})
		return
	var bytes := _unpack(snapshot.get("content"))
	done.call({"ok": true, "found": not bytes.is_empty(), "bytes": bytes, "conflict": _conflict_seen, "kind": "", "detail": ""})

func save_snapshot(snapshot_name: String, description: String, bytes: PackedByteArray, progress: int, done: Callable) -> void:
	if _snapshots == null or auth != CloudSave.Auth.SIGNED_IN:
		done.call_deferred({"ok": false, "kind": "auth", "detail": "not signed in"})
		return
	if _load_done.is_valid() or _save_done.is_valid():
		done.call_deferred({"ok": false, "kind": "error", "detail": "another cloud request is running"})
		return
	_save_done = done
	_conflict_seen = false
	_snapshots.call("save_game", snapshot_name, description, _pack(bytes), 0, progress)

func _on_saved(is_saved: bool, _snapshot_name := "", _description := "") -> void:
	if not _save_done.is_valid():
		return
	var done := _save_done
	_save_done = Callable()
	if is_saved:
		done.call({"ok": true, "conflict": _conflict_seen, "kind": "", "detail": ""})
	else:
		done.call({"ok": false, "kind": "error", "detail": "the save was not accepted"})

func _on_conflict(_conflict) -> void:
	# The plugin settles the conflict itself. Cloud checks the outcome with a fresh load.
	_conflict_seen = true
