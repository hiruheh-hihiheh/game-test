extends RefCounted
## Stands in for the native GodotPlayGameServices Android singleton, with the same signal names and argument shapes as
## the v3.4.0 Kotlin plugin (JSON strings for loaded data). Tests call the emit_* helpers to play Google's answers.

signal userAuthenticated(is_authenticated: bool)
signal gameSaved(is_saved: bool, save_data_name: String, save_data_description: String)
signal gameLoaded(json_data: String)
signal conflictEmitted(json_data: String)
signal currentPlayerLoaded(json_data: String)

var initialized := false
var calls: Array = []

func initialize() -> void:
	initialized = true

func isAuthenticated() -> void:
	calls.append(["isAuthenticated"])

func signIn() -> void:
	calls.append(["signIn"])

func loadCurrentPlayer(force_reload: bool) -> void:
	calls.append(["loadCurrentPlayer", force_reload])

func loadGame(file_name: String, create_if_not_found: bool) -> void:
	calls.append(["loadGame", file_name, create_if_not_found])

func saveGame(file_name: String, description: String, save_data: PackedByteArray, played_time_millis: int, progress_value: int) -> void:
	calls.append(["saveGame", file_name, description, save_data, played_time_millis, progress_value])

func count(name: String) -> int:
	var n := 0
	for c in calls:
		if c[0] == name:
			n += 1
	return n

func last(name: String) -> Array:
	for i in range(calls.size() - 1, -1, -1):
		if calls[i][0] == name:
			return calls[i]
	return []

# ---- Google's side ----

static func snapshot_dict(bytes: PackedByteArray, unique_name := "starfall_salvage_main") -> Dictionary:
	# The plugin sends the content through Gson, which writes a byte array as a JSON array of numbers.
	var content: Array = []
	for b in bytes:
		content.append(int(b))
	return {"content": content, "metadata": {"uniqueName": unique_name, "progressValue": 1}}

func emit_authenticated(ok: bool) -> void:
	userAuthenticated.emit(ok)

func emit_player(player_id: String) -> void:
	currentPlayerLoaded.emit(JSON.stringify({"playerId": player_id, "displayName": "Someone"}) if player_id != "" else "null")

func emit_loaded(bytes: PackedByteArray) -> void:
	gameLoaded.emit(JSON.stringify(snapshot_dict(bytes)))

func emit_loaded_null() -> void:
	gameLoaded.emit("null")

func emit_saved(ok := true) -> void:
	gameSaved.emit(ok, "starfall_salvage_main", "")

func emit_conflict(origin: String, mine: PackedByteArray, theirs: PackedByteArray) -> void:
	conflictEmitted.emit(JSON.stringify({"origin": origin, "conflictId": "c1", "conflictingSnapshot": snapshot_dict(mine), "serverSnapshot": snapshot_dict(theirs)}))
