extends CloudSave.Backend
## A cloud service held in memory, for tests. It behaves like the Play Games backend: asynchronous (answers on a
## later frame), can be offline, can fail or fall silent, and holds one snapshot.
##
## Script it with: signed_in, offline, fail_kind (the next call fails with it), silent (the next call never answers),
## conflict_flag (the next save reports a conflict), and set_blob()/blob for what the cloud holds.

var exists := false
var blob := PackedByteArray()
var offline := false
var fail_kind := ""
## Fails only the next save, so a load can succeed first.
var fail_save := ""
var silent := false
var conflict_flag := false
var delay_frames := 1
var loads := 0
var saves := 0
var last_description := ""
var last_progress := 0
var last_name := ""
var _tree: SceneTree

func label() -> String:
	return "Mock cloud"

func available() -> bool:
	return true

func start(host: Node) -> void:
	_tree = host.get_tree()

func retry_auth() -> void:
	set_auth(CloudSave.Auth.SIGNED_IN)

func set_blob(bytes: PackedByteArray) -> void:
	blob = bytes
	exists = true

func _answer(done: Callable, result: Dictionary) -> void:
	if silent:
		silent = false
		return
	for i in range(delay_frames):
		await _tree.process_frame
	if not done.is_valid():
		return
	if offline:
		done.call({"ok": false, "found": false, "kind": "offline", "detail": "no connection"})
	elif fail_kind != "":
		var k := fail_kind
		fail_kind = ""
		done.call({"ok": false, "found": false, "kind": k, "detail": "scripted failure"})
	else:
		done.call(result)

func load_snapshot(snapshot_name: String, done: Callable) -> void:
	loads += 1
	last_name = snapshot_name
	_answer(done, {"ok": true, "found": exists and not blob.is_empty(), "bytes": blob, "kind": "", "detail": ""})

func save_snapshot(snapshot_name: String, description: String, bytes: PackedByteArray, progress: int, done: Callable) -> void:
	saves += 1
	last_name = snapshot_name
	last_description = description
	last_progress = progress
	if fail_save != "":
		var k := fail_save
		fail_save = ""
		for i in range(delay_frames):
			await _tree.process_frame
		if done.is_valid():
			done.call({"ok": false, "kind": k, "detail": "scripted failure"})
		return
	if silent or offline or fail_kind != "":
		_answer(done, {})
		return
	blob = bytes
	exists = true
	var flagged := conflict_flag
	conflict_flag = false
	_answer(done, {"ok": true, "conflict": flagged, "kind": "", "detail": ""})
