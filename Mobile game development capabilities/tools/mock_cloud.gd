extends CloudSave.Backend
## A cloud service held in memory, for tests. It behaves like the Play Games backend: asynchronous (answers on a
## later frame), can be offline, fail, fall silent or report conflicts, knows who is signed in, and holds one snapshot
## per account.
##
## Script it with: set_auth(), set_account(), offline, fail_kind (the next call fails with it), fail_save (only the next
## save), silent (the next call never answers), conflict_next ("SAVE" or "LOAD": the next such call reports a conflict
## between conflict_blobs), identity_fail, identity_empty, hold (answers wait until release()), late_after_abort
## (abort() does not drop answers, to prove Cloud ignores them itself) and set_blob()/blob for what the cloud holds.

var exists := false
var blob := PackedByteArray()
var offline := false
var fail_kind := ""
## Fails only the next save, so a load can succeed first.
var fail_save := ""
var silent := false
var conflict_next := ""
var conflict_blobs: Array = []
var identity_fail := false
var identity_empty := false
## "", "all", "check", "load" or "save": answers to those calls wait until release().
var hold := ""
var late_after_abort := false
var delay_frames := 1
var loads := 0
var saves := 0
var checks := 0
var aborts := 0
var last_description := ""
var last_progress := 0
var last_name := ""
var _tree: SceneTree
var _gen := 0
var _held: Array = []
var _store := {}

func _init() -> void:
	account_id = "acct-A"

func label() -> String:
	return "Mock cloud"

func available() -> bool:
	return true

func start(host: Node) -> void:
	_tree = host.get_tree()

func retry_auth() -> void:
	set_auth(CloudSave.Auth.SIGNED_IN)

func abort() -> void:
	aborts += 1
	_gen += 1

func set_blob(bytes: PackedByteArray) -> void:
	blob = bytes
	exists = true

## Another Google account is now signed in. Each account has its own cloud save.
func set_account(id: String) -> void:
	_store[account_id] = [exists, blob]
	account_id = id
	var s: Array = _store.get(id, [false, PackedByteArray()])
	exists = s[0]
	blob = s[1]

## What an account holds in the cloud, wherever it is signed in.
func blob_of(id: String) -> PackedByteArray:
	if id == account_id:
		return blob
	return (_store.get(id, [false, PackedByteArray()]) as Array)[1]

func has_blob_of(id: String) -> bool:
	if id == account_id:
		return exists
	return bool((_store.get(id, [false, PackedByteArray()]) as Array)[0])

func release() -> void:
	var pending := _held.duplicate()
	_held.clear()
	for h in pending:
		var done: Callable = h[0]
		if done.is_valid() and (h[2] == _gen or late_after_abort):
			done.call(h[1])

func _deliver(done: Callable, result: Dictionary, kind := "") -> void:
	var gen := _gen
	if silent:
		silent = false
		return
	if hold == "all" or (hold != "" and hold == kind):
		_held.append([done, result, gen])
		return
	for i in range(delay_frames):
		await _tree.process_frame
	if gen != _gen and not late_after_abort:
		return
	if done.is_valid():
		done.call(result)

func _failure(kind: String, extra := {}) -> Dictionary:
	var r := {"ok": false, "found": false, "kind": kind, "detail": "scripted failure"}
	r.merge(extra)
	return r

func check_account(done: Callable) -> void:
	checks += 1
	if offline:
		_deliver(done, _failure("offline"), "check")
	elif identity_fail:
		_deliver(done, _failure("identity"), "check")
	else:
		_deliver(done, {"ok": not identity_empty, "account_id": "" if identity_empty else account_id, "kind": "identity", "detail": ""}, "check")

func _conflict_result(origin: String) -> Dictionary:
	var candidates: Array = []
	var roles := ["conflicting", "server"]
	for i in range(conflict_blobs.size()):
		candidates.append({"role": roles[mini(i, 1)], "bytes": conflict_blobs[i]})
	return _failure("conflict", {"origin": origin, "candidates": candidates})

func load_snapshot(snapshot_name: String, done: Callable) -> void:
	loads += 1
	last_name = snapshot_name
	if conflict_next == "LOAD":
		conflict_next = ""
		_deliver(done, _conflict_result("LOAD"), "load")
	elif offline:
		_deliver(done, _failure("offline"), "load")
	elif fail_kind != "":
		var k := fail_kind
		fail_kind = ""
		_deliver(done, _failure(k), "load")
	else:
		_deliver(done, {"ok": true, "found": exists and not blob.is_empty(), "bytes": blob, "kind": "", "detail": ""}, "load")

func save_snapshot(snapshot_name: String, description: String, bytes: PackedByteArray, progress: int, done: Callable) -> void:
	saves += 1
	last_name = snapshot_name
	last_description = description
	last_progress = progress
	if conflict_next == "SAVE":
		conflict_next = ""
		_deliver(done, _conflict_result("SAVE"), "save")
	elif fail_save != "":
		var k := fail_save
		fail_save = ""
		_deliver(done, _failure(k), "save")
	elif offline:
		_deliver(done, _failure("offline"), "save")
	elif fail_kind != "":
		var k2 := fail_kind
		fail_kind = ""
		_deliver(done, _failure(k2), "save")
	else:
		blob = bytes
		exists = true
		_deliver(done, {"ok": true, "kind": "", "detail": ""}, "save")
