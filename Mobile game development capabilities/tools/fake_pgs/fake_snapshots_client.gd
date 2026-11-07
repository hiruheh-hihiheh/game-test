extends Node
## Mirrors PlayGamesSnapshotsClient (v3.4.0): the same signals, the same JSON handling, the same typed content
## assignment, and the same calls into the native plugin.

signal game_saved(is_saved: bool, save_data_name: String, save_data_description: String)
signal game_loaded(snapshot)
signal conflict_emitted(conflict)

var wired := false

class Snapshot extends RefCounted:
	var content: PackedByteArray
	func _init(dictionary: Dictionary) -> void:
		if dictionary.has("content"): content = dictionary.content

class Conflict extends RefCounted:
	var origin: String
	var conflict_id: String
	var conflicting_snapshot: Snapshot
	var server_snapshot: Snapshot
	func _init(dictionary: Dictionary) -> void:
		if dictionary.has("origin"): origin = dictionary.origin
		if dictionary.has("conflictId"): conflict_id = dictionary.conflictId
		if dictionary.has("conflictingSnapshot"): conflicting_snapshot = Snapshot.new(dictionary.conflictingSnapshot)
		if dictionary.has("serverSnapshot"): server_snapshot = Snapshot.new(dictionary.serverSnapshot)

func _gps() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GodotPlayGameServices")

static func _parse(json: String) -> Dictionary:
	var parsed = JSON.parse_string(json)
	return parsed if parsed is Dictionary else {}

func _ready() -> void:
	var gps := _gps()
	if gps and gps.android_plugin:
		wired = true
		gps.android_plugin.gameSaved.connect(func(is_saved: bool, n: String, d: String):
			game_saved.emit(is_saved, n, d)
		)
		gps.android_plugin.gameLoaded.connect(func(json: String):
			var d := _parse(json)
			if d.is_empty():
				game_loaded.emit(null)
			else:
				game_loaded.emit(Snapshot.new(d))
		)
		gps.android_plugin.conflictEmitted.connect(func(json: String):
			conflict_emitted.emit(Conflict.new(_parse(json)))
		)

func save_game(file_name: String, description: String, save_data: PackedByteArray, played_time_millis: int = 0, progress_value: int = 0) -> void:
	var gps := _gps()
	if gps and gps.android_plugin:
		gps.android_plugin.saveGame(file_name, description, save_data, played_time_millis, progress_value)

func load_game(file_name: String, create_if_not_found := false) -> void:
	var gps := _gps()
	if gps and gps.android_plugin:
		gps.android_plugin.loadGame(file_name, create_if_not_found)
