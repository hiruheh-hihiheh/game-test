extends CloudSave.Backend
## Google Play Games Services (v2) Saved Games, through the godot-play-game-services plugin (v3.x).
##
## NOT VERIFIED AGAINST THE REAL PLUGIN OR A DEVICE. The plugin is not installed in this repository and no Android
## build has been made. This was written against the plugin's v3.4.0 source and is tested on desktop against a
## stand-in for the plugin (tools/fake_pgs), which copies the plugin's wrapper behaviour. See docs/CLOUD_SAVE.md.
##
## How the v3 plugin is built, and what this adapter does about it (all read from the v3.4.0 source):
##   * GodotPlayGameServices is the only autoload. Its initialize() must be called by the game, once. A second call
##     returns PLUGIN_NOT_FOUND, so it is called only while android_plugin is still empty.
##   * PlayGamesSignInClient, PlayGamesSnapshotsClient and PlayGamesPlayersClient are plain Nodes (class_name scripts),
##     not autoloads. Each connects to the native plugin in its own _ready() and only if android_plugin is already set.
##     So this adapter initializes first, then creates the three Nodes and adds them under the Cloud autoload, where
##     they stay for the whole session.
##   * The plugin makes no automatic sign-in check: is_authenticated() is called explicitly.
##   * The plugin passes automatic conflict policies to Google, but when Google still reports a conflict it emits
##     conflict_emitted and returns without ever emitting game_saved or game_loaded, and it has no call to resolve one.
##     A conflict therefore completes the pending request at once as a failure of kind "conflict" carrying both versions
##     (Cloud keeps them on the device). This adapter cannot resolve a Google-side conflict.
##   * game_saved(true) is emitted before commitAndClose finishes, and a failed open emits nothing. So a save is only
##     reported as done after the snapshot has been read back and matches what was written; silence is covered by Cloud's
##     timeout.
##   * game_loaded gives a null snapshot for "nothing there". load_game(name, true) is used, so a first-time player gets an
##     empty snapshot and null means error.
##
## No access tokens are read, stored or logged here. Google signs the player in through the Play Games app.

const AUTOLOAD_NAME := "GodotPlayGameServices"
const NATIVE_SINGLETON := "GodotPlayGameServices"
## GodotPlayGameServices.PlayGamesPluginError.OK
const PLUGIN_OK := 0
const CLIENT_SCRIPTS := {
	"sign_in": "res://addons/GodotPlayGameServices/scripts/sign_in/sign_in_client.gd",
	"snapshots": "res://addons/GodotPlayGameServices/scripts/snapshots/snapshots_client.gd",
	"players": "res://addons/GodotPlayGameServices/scripts/players/players_client.gd",
}

## Tests point these at stand-ins.
var scripts := CLIENT_SCRIPTS.duplicate()
var platform_name := ""
var native_present := Callable()
## Seconds to wait before reading a saved snapshot back, giving the plugin's commit time to land.
var verify_delay := 0.8

var _host: Node
var _main: Node
var _clients: Node
var _sign_in: Node
var _snapshots: Node
var _players: Node
var _wired := false
var _done := Callable()
var _phase := ""
var _name := ""
var _expected := PackedByteArray()
## Counts requests, so a delayed step belonging to an abandoned one can tell.
var _gen := 0

func label() -> String:
	return "Google Play Games"

func _platform() -> String:
	return platform_name if not platform_name.is_empty() else OS.get_name()

static func _find_main() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(AUTOLOAD_NAME)
	return null

## True only when the plugin is genuinely part of this build: Android, the plugin's autoload present, its client scripts
## present, and the native Android plugin registered. Anything less plays as a local guest.
func available() -> bool:
	if _platform() != "Android":
		return false
	var main := _find_main()
	if main == null or not main.has_method("initialize"):
		return false
	for key in scripts:
		if not ResourceLoader.exists(str(scripts[key])):
			return false
	if native_present.is_valid():
		return bool(native_present.call())
	return Engine.has_singleton(NATIVE_SINGLETON)

func start(host: Node) -> void:
	_host = host
	_main = _find_main()
	if _main == null or not _main.has_method("initialize"):
		set_auth(CloudSave.Auth.UNAVAILABLE, "The Google Play Games plugin is not part of this build.")
		return
	if _clients == null:
		# The plugin's own autoload first. Its client Nodes read android_plugin in _ready(), so they must not exist before this.
		if _main.get("android_plugin") == null:
			if int(_main.call("initialize")) != PLUGIN_OK:
				set_auth(CloudSave.Auth.UNAVAILABLE, "The Google Play Games plugin could not start.")
				return
		if not _create_clients():
			return
	set_auth(CloudSave.Auth.CHECKING)
	_sign_in.call("is_authenticated")

func _create_clients() -> bool:
	var root := Node.new()
	root.name = "PlayGamesClients"
	var made := {}
	for key in scripts:
		var script = load(str(scripts[key]))
		var node = script.new() if script != null else null
		if not node is Node:
			root.free()
			for other in made.values():
				if is_instance_valid(other):
					other.free()
			set_auth(CloudSave.Auth.UNAVAILABLE, "The Google Play Games plugin files could not be loaded.")
			return false
		node.name = str(key)
		made[key] = node
		root.add_child(node)
	_sign_in = made["sign_in"]
	_snapshots = made["snapshots"]
	_players = made["players"]
	var ok: bool = _sign_in.has_signal("user_authenticated") and _sign_in.has_method("is_authenticated") and _sign_in.has_method("sign_in")
	ok = ok and _snapshots.has_signal("game_saved") and _snapshots.has_signal("game_loaded") and _snapshots.has_signal("conflict_emitted")
	ok = ok and _snapshots.has_method("save_game") and _snapshots.has_method("load_game")
	ok = ok and _players.has_signal("current_player_loaded") and _players.has_method("load_current_player")
	if not ok:
		root.free()
		_sign_in = null
		_snapshots = null
		_players = null
		set_auth(CloudSave.Auth.UNAVAILABLE, "This version of the Google Play Games plugin is not compatible.")
		return false
	_clients = root
	# The Cloud autoload lives for the whole session, so the clients do too.
	_host.add_child(_clients)
	_wired = true
	_sign_in.connect("user_authenticated", _on_authenticated)
	_snapshots.connect("game_saved", _on_saved)
	_snapshots.connect("game_loaded", _on_loaded)
	_snapshots.connect("conflict_emitted", _on_conflict)
	_players.connect("current_player_loaded", _on_player)
	return true

func retry_auth() -> void:
	if _sign_in == null:
		return
	set_auth(CloudSave.Auth.CHECKING)
	# The player asked for this, so it may show Google's own sign-in screen.
	_sign_in.call("sign_in")

func _on_authenticated(signed_in: bool) -> void:
	set_auth(CloudSave.Auth.SIGNED_IN if signed_in else CloudSave.Auth.SIGNED_OUT)

# ---------- One request at a time, each answered exactly once ----------

func _begin(phase: String, done: Callable) -> bool:
	if _done.is_valid():
		done.call_deferred({"ok": false, "found": false, "kind": "error", "detail": "another cloud request is running"})
		return false
	_gen += 1
	_done = done
	_phase = phase
	return true

func _complete(result: Dictionary) -> void:
	var done := _done
	_done = Callable()
	_phase = ""
	_expected = PackedByteArray()
	if done.is_valid():
		done.call(result)

func _fail(kind: String, detail: String) -> void:
	_complete({"ok": false, "found": false, "kind": kind, "detail": detail})

## Cloud gave up waiting, or the account changed. A late answer from the plugin is then ignored.
func abort() -> void:
	_gen += 1
	_done = Callable()
	_phase = ""
	_expected = PackedByteArray()

func _not_ready(done: Callable) -> bool:
	if _snapshots == null or auth != CloudSave.Auth.SIGNED_IN:
		done.call_deferred({"ok": false, "found": false, "kind": "auth", "detail": "not signed in"})
		return true
	return false

# ---------- Who is signed in ----------

func check_account(done: Callable) -> void:
	if _players == null or auth != CloudSave.Auth.SIGNED_IN:
		done.call_deferred({"ok": false, "account_id": "", "kind": "auth", "detail": "not signed in"})
		return
	if _begin("player", done):
		# Force a reload: a cached player could be the previous account's.
		_players.call("load_current_player", true)

func _on_player(player) -> void:
	if _phase != "player":
		return
	var id := ""
	if player != null:
		id = str(player.get("player_id"))
	account_id = id
	_complete({"ok": not id.is_empty(), "account_id": id, "kind": "identity", "detail": "the player id was not available" if id.is_empty() else ""})

# ---------- Snapshots ----------

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
	if _not_ready(done):
		return
	if _begin("load", done):
		_name = snapshot_name
		_snapshots.call("load_game", snapshot_name, true)

func save_snapshot(snapshot_name: String, description: String, bytes: PackedByteArray, progress: int, done: Callable) -> void:
	if _not_ready(done):
		return
	if _begin("save", done):
		_name = snapshot_name
		_expected = bytes
		# The blob from CloudSave.encode is UTF-8 JSON text already, so it is stored as it is.
		_snapshots.call("save_game", snapshot_name, description, bytes, 0, progress)

func _on_saved(is_saved: bool, _snapshot_name := "", _description := "") -> void:
	if _phase != "save":
		return
	if not is_saved:
		_fail("error", "the save was not accepted")
		return
	# The plugin says "saved" before the commit finishes. Read it back before believing it.
	_phase = "verify"
	var gen := _gen
	if verify_delay > 0.0 and _host != null and _host.is_inside_tree():
		await _host.get_tree().create_timer(verify_delay, true).timeout
	if gen != _gen or _phase != "verify":
		return  # aborted or answered while waiting
	_snapshots.call("load_game", _name, true)

func _on_loaded(snapshot) -> void:
	match _phase:
		"load":
			if snapshot == null:
				_fail("error", "the snapshot could not be opened")
				return
			var bytes := _unpack(snapshot.get("content"))
			_complete({"ok": true, "found": not bytes.is_empty(), "bytes": bytes, "kind": "", "detail": ""})
		"verify":
			if snapshot == null:
				_fail("unverified", "the saved snapshot could not be read back")
			elif _unpack(snapshot.get("content")) == _expected:
				_complete({"ok": true, "kind": "", "detail": ""})
			else:
				_fail("unverified", "the cloud did not hold what was saved")

func _on_conflict(conflict) -> void:
	if not _done.is_valid() or conflict == null:
		return
	var origin := str(conflict.get("origin"))
	var candidates: Array = []
	var mine = conflict.get("conflicting_snapshot")
	var theirs = conflict.get("server_snapshot")
	if mine != null:
		candidates.append({"role": "conflicting", "bytes": _unpack(mine.get("content"))})
	if theirs != null:
		candidates.append({"role": "server", "bytes": _unpack(theirs.get("content"))})
	_complete({"ok": false, "found": false, "kind": "conflict", "origin": origin, "candidates": candidates, "detail": "Google reported two versions of the cloud save"})
