extends "res://src/meta/cloud_sync.gd"
## Test only: the Cloud orchestrator with file operations that can be made to fail or be interfered with, to prove
## nothing is replaced and no recovery file is harmed. The *_for properties match a part of the path: temporary files
## carry the recovery kind in their name (tmp_cloud_save_...), and final files are named <generation>_<kind>.<ext>.

var fail_open_for := ""
var fail_store_for := ""
## Writes only the first half of the data and reports success, as a full disk might.
var short_write_for := ""
var fail_copy := false
## The temporary file was written and verified but could not be moved into place.
var fail_promote_for := ""
## Leaves temporary files behind on failure, as a crash would.
var keep_temp_on_failure := false
## Something else creates a file at the exact destination after staging, before promotion.
var sentinel_for := ""
var sentinel_bytes := "SENTINEL: a file that is not ours".to_utf8_buffer()
## The promoted file no longer reads back correctly, as a failing disk might do.
var corrupt_after_promote_for := ""
## _next_generation() answers this number for the next `force_calls` calls, as a second process racing for the same
## generation would see.
var force_generation := -1
var force_calls := 1
## Names temporary files after a process id, so a "crashed" writer can be someone who is no longer running.
var fake_pid := 0

func _open_write(file_path: String) -> FileAccess:
	if fail_open_for != "" and fail_open_for in file_path:
		return null
	return super(file_path)

func _store_bytes(f: FileAccess, file_path: String, bytes: PackedByteArray) -> bool:
	if fail_store_for != "" and fail_store_for in file_path:
		f.store_buffer(bytes.slice(0, bytes.size() / 3))  # fails part-way
		return false
	if short_write_for != "" and short_write_for in file_path:
		f.store_buffer(bytes.slice(0, bytes.size() / 2))
		return true
	return super(f, file_path, bytes)

func _copy_file(from: String, to: String) -> bool:
	if fail_copy:
		return false
	return super(from, to)

func _promote(tmp: String, dest: String) -> bool:
	if fail_promote_for != "" and fail_promote_for in dest:
		return false
	return super(tmp, dest)

func _discard(file_path: String) -> void:
	if keep_temp_on_failure:
		return
	super(file_path)

func _after_staged(dest: String) -> void:
	if sentinel_for != "" and sentinel_for in dest and not FileAccess.file_exists(dest):
		var f := FileAccess.open(dest, FileAccess.WRITE)
		f.store_buffer(sentinel_bytes)
		f.close()

func _after_promoted(dest: String) -> void:
	if corrupt_after_promote_for != "" and corrupt_after_promote_for in dest:
		var bytes := FileAccess.get_file_as_bytes(dest)
		var f := FileAccess.open(dest, FileAccess.WRITE)
		f.store_buffer(bytes.slice(0, bytes.size() / 2))
		f.close()

func _next_generation() -> int:
	if force_generation >= 0 and force_calls > 0:
		force_calls -= 1
		return force_generation
	return super()

func _process_id() -> int:
	return fake_pid if fake_pid > 0 else super()
