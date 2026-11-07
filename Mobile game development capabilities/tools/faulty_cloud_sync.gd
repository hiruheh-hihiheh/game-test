extends "res://src/meta/cloud_sync.gd"
## Test only: the Cloud orchestrator with file operations that can be made to fail, to prove nothing is replaced and no
## recovery file is harmed when a backup cannot be written. The *_for properties match a part of the path: the
## temporary files carry the recovery kind in their name (tmp_cloud_save_..., tmp_local_progress_...), and the final
## files are named <generation>_<kind>.<ext>.

var fail_open_for := ""
var fail_store_for := ""
## Writes only the first half of the data and reports success, as a full disk might.
var short_write_for := ""
var fail_copy := false
## The temporary file was written and verified but could not be moved into place.
var fail_promote_for := ""
## Leaves temporary files behind on failure, as a crash would.
var keep_temp_on_failure := false

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
