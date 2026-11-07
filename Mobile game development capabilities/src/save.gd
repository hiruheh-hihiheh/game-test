extends Node
## Player progress and settings. Autoloaded as "Save".
## Saves are written to a temp file and swapped in, with the previous save kept as a backup,
## so a crash or a dead battery mid-write can never destroy a player's progress.

## Emitted after every successful write of the save file. Cloud sync listens to it.
signal saved

const VERSION := 2
const PATH := "user://starfall_save.cfg"
const TEST_PREFIX := "user://starfall_test_save"

const PROGRESS_KEYS := [
	"salvage", "best_score", "endless_best_wave", "unlocked", "star_mask", "level_best", "upgrades",
	"ship", "owned_ships", "blueprints", "nova_mode", "loadout", "mastery", "paints", "tutorial",
	"stats", "side_cleared", "bosses_beaten", "achievements", "codex", "contracts", "expedition",
	"weekly_best", "daily_best", "reroll_tokens", "expedition_wins", "seen_unlocks",
	"gear", "gear_uid", "equipped", "parts", "pilot_xp", "tier_data", "tier_unlocked", "rift_claimed", "danger",
]
const DEFAULT_OPT := {
	"music_volume": 0.8, "sfx_volume": 1.0, "haptics": 1.0, "shake": 1.0, "reduced_flash": false, "reduced_motion": false,
	"particles": 2, "nova_side": "right", "nova_double_tap": false, "sensitivity": 1.3, "ui_scale": 1.0, "colorblind": false,
	"bullet_outline": false, "bullet_size": 1.0, "fps": 60, "telemetry": false, "show_hitbox": true,
}

var path := PATH
var migrated_from := 0
## True under "-- --test". Tests use a save file of their own, named after the process,
## so two test runs at once cannot delete each other's files.
var test_mode := false
## Where the last load came from: "main", "backup" or "none" (a fresh start).
var load_source := "none"
var _defaults := {}

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
var gear: Array = []
var gear_uid := 1
var equipped := {}
var parts := 0
var pilot_xp := 0
var tier_data := {}
var tier_unlocked := 0
var rift_claimed: Array = []
## Danger Contracts: {"done": {id: count}, "last": {mode: [ids]}}
var danger := {}

var opt := DEFAULT_OPT.duplicate()

# Session only: what the game scene should load next.
var session := {"mode": "campaign", "level": 1, "mutators": []}
var map_sector := 1
var map_tier := 0
var menu_screen := "title"
var pending_rewards: Array = []
var _dirty := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_defaults = _copy(to_dict())
	if "--test" in OS.get_cmdline_user_args():
		test_mode = true
		_remove_stale_test_files()
		path = "%s_%d.cfg" % [TEST_PREFIX, OS.get_process_id()]
		remove_files(path)
	load_data()
	apply_display()

func _exit_tree() -> void:
	if test_mode:
		remove_files(path)

## Deletes a save file with its backup and temp copy.
func remove_files(p: String) -> void:
	for f in [p, p + ".bak", p + ".tmp", p + ".cloud", p + ".before_cloud", p + ".cloudconflict"]:
		DirAccess.remove_absolute(f)

## Test saves left behind by runs that crashed. A file whose process is still running is left alone.
func _remove_stale_test_files() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var prefix := TEST_PREFIX.get_file()
	for f in dir.get_files():
		if not f.begins_with(prefix):
			continue
		var pid := 0
		var stem := f
		for suffix in [".bak", ".tmp", ".cloud", ".before_cloud", ".cloudconflict"]:
			stem = stem.trim_suffix(suffix)
		var bits := stem.get_basename().split("_")
		if bits.size() > 3:
			pid = int(bits[bits.size() - 1])
		if pid > 0 and OS.is_process_running(pid):
			continue
		DirAccess.remove_absolute("user://" + f)

static func _copy(v):
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v

## Puts every persisted progress value back to a brand new player's. Settings and
## session-only state (the map's sector and tier) are separate: see reset_settings and reset_view.
func reset_progress() -> void:
	for k in PROGRESS_KEYS:
		if _defaults.has(k):
			set(k, _copy(_defaults[k]))
	migrated_from = 0

## Puts every setting back to its default. Done in place, so anything holding `opt` still sees it.
func reset_settings() -> void:
	opt.clear()
	opt.merge(DEFAULT_OPT.duplicate(true))

## The map screen's remembered position. It is not saved.
func reset_view() -> void:
	map_sector = 1
	map_tier = 0

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
	_repair()

## Loads the save, or the backup when the main file is missing, unreadable or empty.
## Starts from a clean slate first, so an old save never inherits leftovers from memory.
## Returns where the data came from.
func load_data() -> String:
	var names := ["main", "backup"]
	var i := 0
	for candidate in [path, path + ".bak"]:
		var c := ConfigFile.new()
		if c.load(candidate) == OK and _looks_valid(c):
			_reset_all()
			_read(c)
			load_source = names[i]
			return load_source
		i += 1
	_reset_all()
	load_source = "none"
	return load_source

## Every load starts from a new player's state, so nothing leaks in from a save loaded before it.
## Only the settings a file actually holds are merged back in afterwards.
func _reset_all() -> void:
	reset_progress()
	reset_settings()
	reset_view()

## A file that parses but holds no progress must not hide a good backup.
func _looks_valid(c: ConfigFile) -> bool:
	if int(c.get_value("meta", "version", 1)) < 2:
		return c.has_section("progress")
	var d = c.get_value("progress", "data", null)
	return d is Dictionary and (d as Dictionary).has("unlocked")

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
	_repair()

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
	saved.emit()

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

func record_level(level: int, mask: int, score: int, tier := 0) -> void:
	if tier <= 0:
		star_mask[level] = int(star_mask.get(level, 0)) | mask
		if level <= Levels.LEVEL_COUNT:
			unlocked = maxi(unlocked, mini(level + 1, Levels.LEVEL_COUNT))
		level_best[level] = maxi(int(level_best.get(level, 0)), score)
	else:
		var d: Dictionary = tier_data.get(tier, {"unlocked": 1, "stars": {}})
		var stars_d: Dictionary = d.stars
		stars_d[level] = int(stars_d.get(level, 0)) | mask
		if level <= Levels.LEVEL_COUNT:
			d.unlocked = maxi(int(d.unlocked), mini(level + 1, Levels.LEVEL_COUNT))
		tier_data[tier] = d
	best_score = maxi(best_score, score)

# --- Tiers: the same 60 levels replayed harder ---

func unlocked_at(tier: int) -> int:
	if tier <= 0:
		return unlocked
	return int((tier_data.get(tier, {}) as Dictionary).get("unlocked", 1))

func mask_at(tier: int, level: int) -> int:
	if tier <= 0:
		return int(star_mask.get(level, 0))
	return int(((tier_data.get(tier, {}) as Dictionary).get("stars", {}) as Dictionary).get(level, 0))

func stars_at(tier: int, level: int) -> int:
	var m := mask_at(tier, level)
	return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1)

func sector_stars_at(tier: int, sector: int) -> int:
	var total := 0
	var first := (sector - 1) * Levels.LEVELS_PER_SECTOR + 1
	for n in range(first, first + Levels.LEVELS_PER_SECTOR):
		total += stars_at(tier, n)
	return total

func unlock_tier_after(tier: int) -> bool:
	if tier >= Tiers.MAX_TIER or tier_unlocked > tier:
		return false
	tier_unlocked = tier + 1
	Meta.peak("tier_unlocked", tier_unlocked)
	return true

# --- Gear inventory ---

func gear_by_uid(uid: int) -> Dictionary:
	for it in gear:
		if int(it.uid) == uid:
			return it
	return {}

## Adds loot. A full inventory turns the new item into parts instead. Returns whether it was kept.
func add_gear(item: Dictionary) -> bool:
	if gear.size() >= Gear.MAX_ITEMS:
		parts += Gear.scrap_value(item)
		item["scrapped"] = true
		return false
	item["uid"] = gear_uid
	gear_uid += 1
	gear.append(item)
	mark_dirty()
	return true

func equipped_uid(ship_id: String, slot: String) -> int:
	return int((equipped.get(ship_id, {}) as Dictionary).get(slot, 0))

func equipped_item(ship_id: String, slot: String) -> Dictionary:
	var uid := equipped_uid(ship_id, slot)
	return gear_by_uid(uid) if uid > 0 else {}

## Which ship an item is on, or "" when it is in the bag.
func equipped_on(uid: int) -> String:
	for ship_key in equipped:
		for slot in (equipped[ship_key] as Dictionary):
			if int(equipped[ship_key][slot]) == uid:
				return str(ship_key)
	return ""

func equip(ship_id: String, uid: int) -> bool:
	var item := gear_by_uid(uid)
	if item.is_empty():
		return false
	var prior := equipped_on(uid)
	if not prior.is_empty():
		(equipped[prior] as Dictionary).erase(str(item.slot))
	var slots: Dictionary = equipped.get(ship_id, {})
	slots[str(item.slot)] = uid
	equipped[ship_id] = slots
	mark_dirty()
	return true

func unequip(ship_id: String, slot: String) -> void:
	(equipped.get(ship_id, {}) as Dictionary).erase(slot)
	mark_dirty()

func upgrade_gear(uid: int) -> bool:
	var item := gear_by_uid(uid)
	if item.is_empty():
		return false
	var cost := Gear.upgrade_cost(item)
	if cost < 0 or parts < cost:
		return false
	parts -= cost
	item["lvl"] = int(item.lvl) + 1
	mark_dirty()
	return true

## Returns the parts gained, or -1 when the item is equipped or missing.
func scrap_gear(uid: int) -> int:
	var item := gear_by_uid(uid)
	if item.is_empty() or not equipped_on(uid).is_empty():
		return -1
	var value := Gear.scrap_value(item)
	parts += value
	gear.erase(item)
	mark_dirty()
	return value

func new_gear_count() -> int:
	var n := 0
	for it in gear:
		if bool(it.get("new", false)):
			n += 1
	return n

## Keeps old and hand-edited saves consistent.
func _repair() -> void:
	danger = Danger.repair(danger)
	var top := 0
	var seen := {}
	for it in gear:
		it["uid"] = int(it.get("uid", 0))
		top = maxi(top, int(it.uid))
		seen[int(it.uid)] = true
		if not it.has("aff"):
			it["aff"] = []
		if not it.has("lvl"):
			it["lvl"] = 0
		if not it.has("perk"):
			it["perk"] = ""
	gear_uid = maxi(gear_uid, top + 1)
	for ship_key in equipped.keys():
		for slot in (equipped[ship_key] as Dictionary).keys():
			if not seen.has(int(equipped[ship_key][slot])):
				(equipped[ship_key] as Dictionary).erase(slot)
	# Anyone who already beat a tier has earned the next one.
	if int(star_mask.get(Levels.LEVEL_COUNT, 0)) > 0:
		tier_unlocked = maxi(tier_unlocked, 1)
	for t in tier_data:
		if int(((tier_data[t] as Dictionary).get("stars", {}) as Dictionary).get(Levels.LEVEL_COUNT, 0)) > 0:
			tier_unlocked = maxi(tier_unlocked, mini(int(t) + 1, Tiers.MAX_TIER))

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
	if str(info.kind) == "lab" and not Hangar.lab_open():
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

## Replaces ALL progress with a payload that CloudSave.validate_progress has already accepted: a cloud restore.
## Nothing is merged and no value is "kept if higher", because a lower balance may be a real purchase.
## Settings stay as they are on this device. The caller backs up the old save first (see Cloud).
func restore_progress(payload: Dictionary) -> void:
	reset_progress()
	from_dict(_copy(payload))
	save_data()
