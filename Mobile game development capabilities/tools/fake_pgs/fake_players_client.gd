extends Node
## Mirrors PlayGamesPlayersClient (v3.4.0), including that a null player arrives as an empty player.

signal current_player_loaded(current_player)

var wired := false

class Player extends RefCounted:
	var player_id: String
	func _init(dictionary: Dictionary) -> void:
		if dictionary.has("playerId"): player_id = dictionary.playerId

func _gps() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GodotPlayGameServices")

func _ready() -> void:
	var gps := _gps()
	if gps and gps.android_plugin:
		wired = true
		gps.android_plugin.currentPlayerLoaded.connect(func(json: String):
			var parsed = JSON.parse_string(json)
			current_player_loaded.emit(Player.new(parsed if parsed is Dictionary else {}))
		)

func load_current_player(force_reload: bool) -> void:
	var gps := _gps()
	if gps and gps.android_plugin:
		gps.android_plugin.loadCurrentPlayer(force_reload)
