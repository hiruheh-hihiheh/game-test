class_name CloudSave
extends RefCounted
## The seam for Google Play Games saved games. The game only ever talks to this class.
## To go live: implement `Backend` in an Android plugin and pass it to `use()`.
## Conflicts are resolved by Save.merge_remote(), which keeps the best of each field,
## so a player can never lose progress by syncing with an older device.

class Backend:
	func is_signed_in() -> bool:
		return false
	func upload(_blob: String) -> void:
		pass
	func download() -> String:
		return ""

static var backend: Backend = Backend.new()

static func use(new_backend: Backend) -> void:
	backend = new_backend

static func push() -> void:
	if backend.is_signed_in():
		backend.upload(export_blob())

static func pull() -> void:
	if not backend.is_signed_in():
		return
	var blob := backend.download()
	if not blob.is_empty():
		import_blob(blob)

static func export_blob() -> String:
	return Marshalls.variant_to_base64(Save.to_dict())

static func import_blob(blob: String) -> bool:
	var data = Marshalls.base64_to_variant(blob)
	if not data is Dictionary:
		return false
	Save.merge_remote(data)
	return true
