extends Node
## Player progress and settings. Autoloaded as "Save".
## Saves are written to a temp file and swapped in, with the previous save kept as a backup,
## so a crash or a dead battery mid-write can never destroy a player's progress.

const VERSION := 2
const PATH := "user://starfall_save.cfg"
const TEST_PATH := "user://starfall_test_save.cfg"

const PROGRESS_KEYS := [
	"salvage", "best_score", "endless_best_wave", "unlocked", "star_mask", "level_best", "upgrades",
	"ship", "owned_ships", "blueprints", "nova_mode", "loadout", "mastery", "paints", "tutorial",
	"stats", "side_cleared", "bosses_beaten", "achievements", "codex", "contracts", "expedition",
	"weekly_best", "daily_best", "reroll_tokens", "expedition_wins", "seen_unlocks",
]
const DEFAULT_OPT := {
	"music_volume": 0.8, "sfx_volume": 1.0, "haptics": 1.0, "shake": 1.0, "reduced_flash": false, "reduced_motion": false,
	"particles": 2, "nova_side": "right", "nova_double_tap": false, "sensitivity": 1.3, "ui_scale": 1.0, "colorblind": false,
	"bullet_outline": false, "bullet_size": 1.0, "fps": 60, "telemetry": false, "show_hitbox": true,
}

var path := PATH
var migrated_from := 0

# Progress
var salvage := 0
var best_score := 0
var endless_best_wave := 0
var unlocked := 1
var star_mask := {}
var level_best := {}
var upgrades := {}
var ship := "nova"
var owned_ships: Array = ["nova"]
var blueprints: Array = []
var nova_mode := "pulse"
var loadout: Array = []
var mastery := {}
var paints := {}
var tutorial := {}
var stats := {}
var side_cleared: Array = []
var bosses_beaten: Array = []
var achievements := {}
var codex := {}
var contracts := {}
var expedition := {}
var weekly_best := {}
var daily_best := {}
var reroll_tokens := 0
var expedition_wins := 0
var seen_unlocks: Array = []

var opt := DEFAULT_OPT.duplicate()

# Session only: what the game scene should load next.
var session := {"mode": "campaign", "level": 1, "mutators": []}
var map_sector := 1
var menu_screen := "title"
var pending_rewards: Array = []
var _dirty := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--test" in OS.get_cmdline_user_args():
		path = TEST_PATH
		for f in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
			DirAccess.remove_absolute(f)
	load_data()
	apply_display()

func apply_display() -> void:
	Engine.max_fps = int(opt.fps)
	var w := get_window()
	if w:
		w.content_scale_factor = float(opt.ui_scale)

func to_dict() -> Dictionary:
	var d := {"version": VERSION, "saved_at": int(Time.get_unix_time_from_system())}
	for k in PROGRESS_KEYS:
		d[k] = get(k)
	return d

func from_dict(d: Dictionary) -> void:
	for k in PROGRESS_KEYS:
		if d.has(k):
			set(k, d[k])
	unlocked = clampi(unlocked, 1, Levels.LEVEL_COUNT)
	if not ship in Ships.LIST:
		ship = "nova"
	if not ship in owned_ships:
		owned_ships.append(ship)
	map_sector = Levels.sector_of(unlocked)

func load_data() -> void:
	for candidate in [path, path + ".bak"]:
		var c := ConfigFile.new()
		if c.load(candidate) == OK:
			_read(c)
			return

func _read(c: ConfigFile) -> void:
	var loaded_version := int(c.get_value("meta", "version", 1))
	if loaded_version < 2:
		_migrate_v1(c)
		migrated_from = loaded_version
	else:
		from_dict(c.get_value("progress", "data", {}))
	var loaded_opt: Dictionary = c.get_value("settings", "data", {})
	for k in loaded_opt:
		if DEFAULT_OPT.has(k):
			opt[k] = loaded_opt[k]

func _migrate_v1(c: ConfigFile) -> void:
	salvage = int(c.get_value("progress", "salvage", 0))
	best_score = int(c.get_value("progress", "best_score", 0))
	endless_best_wave = int(c.get_value("progress", "endless_best_wave", 0))
	unlocked = clampi(int(c.get_value("progress", "unlocked", 1)), 1, Levels.LEVEL_COUNT)
	upgrades = c.get_value("progress", "upgrades", {})
	ship = str(c.get_value("progress", "ship", "nova"))
	owned_ships = c.get_value("progress", "owned_ships", ["nova"])
	tutorial = {"move": true, "card": true} if bool(c.get_value("progress", "tutorial_done", false)) else {}
	var old_stars: Dictionary = c.get_value("progress", "stars", {})
	for level in old_stars:
		# The old 2 and 3 star ratings both meant a clear; 3 meant no hull lost.
		star_mask[int(level)] = 3 if int(old_stars[level]) >= 3 else 1
	opt.music_volume = float(c.get_value("settings", "music_volume", 0.8))
	opt.sfx_volume = float(c.get_value("settings", "sfx_volume", 1.0))
	opt.haptics = 1.0 if bool(c.get_value("settings", "vibration", true)) else 0.0
	opt.shake = 1.0 if bool(c.get_value("settings", "screen_shake", true)) else 0.0
	# Old saves keep what they already beat.
	for s in range(1, Levels.SECTOR_COUNT + 1):
		if unlocked > s * Levels.LEVELS_PER_SECTOR:
			bosses_beaten.append(s)
			for bp in Levels.BOSS_REWARDS[s].blueprints:
				if not bp in blueprints:
					blueprints.append(bp)
	map_sector = Levels.sector_of(unlocked)

func save_data() -> void:
	var c := ConfigFile.new()
	c.set_value("meta", "version", VERSION)
	c.set_value("progress", "data", to_dict())
	c.set_value("settings", "data", opt)
	var tmp := path + ".tmp"
	if c.save(tmp) != OK:
		return
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak")
	DirAccess.rename_absolute(tmp, path)
	_dirty = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _dirty:
			save_data()

func mark_dirty() -> void:
	_dirty = true

# --- Stars ---

func stars_for(level: int) -> int:
	var m := int(star_mask.get(level, 0))
	return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1)

func total_stars() -> int:
	var total := 0
	for level in star_mask:
		total += stars_for(int(level))
	return total

func sector_stars(sector: int) -> int:
	var total := 0
	var first := (sector - 1) * Levels.LEVELS_PER_SECTOR + 1
	for n in range(first, first + Levels.LEVELS_PER_SECTOR):
		total += stars_for(n)
	return total

func record_level(level: int, mask: int, score: int) -> void:
	star_mask[level] = int(star_mask.get(level, 0)) | mask
	if level <= Levels.LEVEL_COUNT:
		unlocked = maxi(unlocked, mini(level + 1, Levels.LEVEL_COUNT))
	level_best[level] = maxi(int(level_best.get(level, 0)), score)
	best_score = maxi(best_score, score)

# --- Economy ---

func has_blueprint(id: String) -> bool:
	return id.is_empty() or id in blueprints

func add_blueprint(id: String) -> bool:
	if id.is_empty() or id in blueprints:
		return false
	blueprints.append(id)
	return true

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

func buy_upgrade(id: String) -> bool:
	var info: Dictionary = Hangar.item(id)
	var lvl := upgrade_level(id)
	if lvl >= int(info.max) or total_stars() < Hangar.stars_needed(id):
		return false
	var cost := Hangar.cost(id, lvl)
	if salvage < cost:
		return false
	salvage -= cost
	upgrades[id] = lvl + 1
	save_data()
	return true

func ship_available(id: String) -> bool:
	return has_blueprint(str(Ships.LIST[id].blueprint))

func buy_ship(id: String) -> bool:
	if id in owned_ships or not ship_available(id):
		return false
	var cost := int(Ships.LIST[id].cost)
	if salvage < cost:
		return false
	salvage -= cost
	owned_ships.append(id)
	ship = id
	save_data()
	return true

func ship_xp(id: String) -> int:
	return int(mastery.get(id, 0))

func ship_mastery(id: String) -> int:
	return Ships.mastery_level(ship_xp(id))

func paint_of(id: String) -> String:
	return str(paints.get(id, "stock"))

func loadout_slots() -> int:
	return 1 + upgrade_level("slot")

func tutorial_seen(key: String) -> bool:
	return bool(tutorial.get(key, false))

func mark_tutorial(key: String) -> void:
	tutorial[key] = true
	mark_dirty()

func haptic(ms: int) -> void:
	var k := float(opt.haptics)
	if k > 0.0:
		Input.vibrate_handheld(int(float(ms) * k))

## Combines this save with one from another device, keeping the best of each field.
func merge_remote(remote: Dictionary) -> void:
	salvage = maxi(salvage, int(remote.get("salvage", 0)))
	best_score = maxi(best_score, int(remote.get("best_score", 0)))
	unlocked = maxi(unlocked, int(remote.get("unlocked", 1)))
	endless_best_wave = maxi(endless_best_wave, int(remote.get("endless_best_wave", 0)))
	for key in ["blueprints", "owned_ships", "side_cleared", "bosses_beaten", "seen_unlocks"]:
		var mine: Array = get(key)
		for item in remote.get(key, []):
			if not item in mine:
				mine.append(item)
	var remote_stars: Dictionary = remote.get("star_mask", {})
	for level in remote_stars:
		star_mask[level] = int(star_mask.get(level, 0)) | int(remote_stars[level])
	for key in ["upgrades", "mastery", "level_best", "stats", "achievements"]:
		var mine: Dictionary = get(key)
		var theirs: Dictionary = remote.get(key, {})
		for k in theirs:
			if theirs[k] is int or theirs[k] is float:
				mine[k] = maxf(float(mine.get(k, 0)), float(theirs[k]))
			else:
				mine[k] = theirs[k]
	save_data()
