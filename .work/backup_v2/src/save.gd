extends Node
## Player progress and settings. Autoloaded as "Save".

const PATH := "user://starfall_save.cfg"
const TEST_PATH := "user://starfall_test_save.cfg"

var path := PATH

# Progress
var salvage := 0
var best_score := 0
var endless_best_wave := 0
var unlocked := 1
var stars := {}
var upgrades := {}
var ship := "nova"
var owned_ships: Array = ["nova"]
var tutorial_done := false

# Settings
var music_volume := 0.8
var sfx_volume := 1.0
var vibration := true
var screen_shake := true

# Session only: what the game scene should load next.
var play_level := 1
var play_endless := false
var map_sector := 1
var menu_screen := "title"

func _ready() -> void:
	if "--test" in OS.get_cmdline_user_args():
		path = TEST_PATH
		DirAccess.remove_absolute(TEST_PATH)
	load_data()

func load_data() -> void:
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return
	salvage = int(c.get_value("progress", "salvage", 0))
	best_score = int(c.get_value("progress", "best_score", 0))
	endless_best_wave = int(c.get_value("progress", "endless_best_wave", 0))
	unlocked = clampi(int(c.get_value("progress", "unlocked", 1)), 1, Levels.LEVEL_COUNT)
	stars = c.get_value("progress", "stars", {})
	upgrades = c.get_value("progress", "upgrades", {})
	ship = str(c.get_value("progress", "ship", "nova"))
	owned_ships = c.get_value("progress", "owned_ships", ["nova"])
	tutorial_done = bool(c.get_value("progress", "tutorial_done", false))
	music_volume = float(c.get_value("settings", "music_volume", 0.8))
	sfx_volume = float(c.get_value("settings", "sfx_volume", 1.0))
	vibration = bool(c.get_value("settings", "vibration", true))
	screen_shake = bool(c.get_value("settings", "screen_shake", true))
	map_sector = Levels.sector_of(unlocked)

func save_data() -> void:
	var c := ConfigFile.new()
	c.set_value("progress", "salvage", salvage)
	c.set_value("progress", "best_score", best_score)
	c.set_value("progress", "endless_best_wave", endless_best_wave)
	c.set_value("progress", "unlocked", unlocked)
	c.set_value("progress", "stars", stars)
	c.set_value("progress", "upgrades", upgrades)
	c.set_value("progress", "ship", ship)
	c.set_value("progress", "owned_ships", owned_ships)
	c.set_value("progress", "tutorial_done", tutorial_done)
	c.set_value("settings", "music_volume", music_volume)
	c.set_value("settings", "sfx_volume", sfx_volume)
	c.set_value("settings", "vibration", vibration)
	c.set_value("settings", "screen_shake", screen_shake)
	c.save(path)

func stars_for(level: int) -> int:
	return int(stars.get(level, 0))

func total_stars() -> int:
	var total := 0
	for v in stars.values():
		total += int(v)
	return total

func sector_stars(sector: int) -> int:
	var total := 0
	var first := (sector - 1) * Levels.LEVELS_PER_SECTOR + 1
	for n in range(first, first + Levels.LEVELS_PER_SECTOR):
		total += stars_for(n)
	return total

func record_level(level: int, earned_stars: int, score: int) -> void:
	stars[level] = maxi(stars_for(level), earned_stars)
	unlocked = maxi(unlocked, mini(level + 1, Levels.LEVEL_COUNT))
	best_score = maxi(best_score, score)
	save_data()

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

func buy_upgrade(id: String) -> bool:
	var info: Dictionary = Levels.hangar_item(id)
	var lvl := upgrade_level(id)
	if lvl >= int(info.max):
		return false
	var cost := Levels.upgrade_cost(id, lvl)
	if salvage < cost:
		return false
	salvage -= cost
	upgrades[id] = lvl + 1
	save_data()
	return true

func buy_ship(id: String) -> bool:
	if id in owned_ships:
		return false
	var cost := int(Levels.SHIPS[id].cost)
	if salvage < cost:
		return false
	salvage -= cost
	owned_ships.append(id)
	ship = id
	save_data()
	return true

func vibrate(ms: int) -> void:
	if vibration:
		Input.vibrate_handheld(ms)
