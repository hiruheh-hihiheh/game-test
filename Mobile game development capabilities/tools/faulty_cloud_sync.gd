extends "res://src/meta/cloud_sync.gd"
## Test only: the Cloud orchestrator with file operations that can be made to fail, to prove nothing is replaced when a
## backup cannot be written. The *_for properties match the end of a path.

var fail_open_for := ""
var fail_store_for := ""
## Writes only the first half of the data and reports success, as a full disk might.
var short_write_for := ""
var fail_copy := false

func _open_write(file_path: String) -> FileAccess:
	if fail_open_for != "" and file_path.ends_with(fail_open_for):
		return null
	return super(file_path)

func _store_bytes(f: FileAccess, file_path: String, bytes: PackedByteArray) -> bool:
	if fail_store_for != "" and file_path.ends_with(fail_store_for):
		return false
	if short_write_for != "" and file_path.ends_with(short_write_for):
		f.store_buffer(bytes.slice(0, bytes.size() / 2))
		return true
	return super(f, file_path, bytes)

func _copy_file(from: String, to: String) -> bool:
	if fail_copy:
		return false
	return super(from, to)
