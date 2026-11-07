class_name Levels
extends RefCounted
## All game content as data: sectors, enemies, bosses, upgrades and 60 generated levels.
## A level is built from a fixed seed, so level 23 plays the same for everyone.

const LEVELS_PER_SECTOR := 10
const SECTOR_COUNT := 6
const LEVEL_COUNT := 60
const ENDLESS_UNLOCK := 11

const SECTORS := [
	{"name": "DEBRIS BELT", "tag": "Where every salvager starts", "color": Color(0.25, 0.90, 1.0), "music": "battle_a"},
	{"name": "EMBER DRIFT", "tag": "The wreckage is still burning", "color": Color(1.0, 0.58, 0.20), "music": "battle_b"},
	{"name": "VIOLET NURSERY", "tag": "Something is hatching out here", "color": Color(1.0, 0.27, 0.66), "music": "battle_a"},
	{"name": "PALE GRAVEYARD", "tag": "Frozen fleets. Not all of them dead", "color": Color(0.55, 0.95, 0.95), "music": "battle_b"},
	{"name": "CRIMSON FRONT", "tag": "You have entered a war zone", "color": Color(1.0, 0.27, 0.30), "music": "battle_a"},
	{"name": "SUNKEN CORE", "tag": "The source of the starfall", "color": Color(1.0, 0.82, 0.32), "music": "battle_b"},
]

const ENEMIES := {
	"rock_l": {"hp": 6.0, "r": 46.0, "size": 124.0, "art": "rock_l", "hue": 0.0, "score": 40, "drop": 0.35, "fire": 0.0},
	"rock_m": {"hp": 3.0, "r": 31.0, "size": 86.0, "art": "rock_m", "hue": 0.0, "score": 20, "drop": 0.2, "fire": 0.0},
	"rock_s": {"hp": 1.0, "r": 20.0, "size": 58.0, "art": "rock_s", "hue": 0.0, "score": 10, "drop": 0.1, "fire": 0.0},
	"fighter": {"hp": 3.0, "r": 34.0, "size": 112.0, "art": "fighter", "hue": 0.0, "score": 50, "drop": 0.3, "fire": 2.7},
	"raider": {"hp": 2.0, "r": 28.0, "size": 92.0, "art": "raider", "hue": 0.47, "score": 45, "drop": 0.25, "fire": 0.0},
	"weaver": {"hp": 3.0, "r": 32.0, "size": 104.0, "art": "fighter", "hue": 0.40, "score": 60, "drop": 0.3, "fire": 2.3},
	"mine": {"hp": 3.0, "r": 30.0, "size": 72.0, "art": "mine", "hue": 0.45, "score": 60, "drop": 0.3, "fire": 0.0},
	"gunship": {"hp": 18.0, "r": 66.0, "size": 212.0, "art": "fighter", "hue": 0.68, "score": 300, "drop": 1.0, "fire": 2.4},
	"elite": {"hp": 46.0, "r": 96.0, "size": 300.0, "art": "boss", "hue": 0.86, "score": 800, "drop": 1.0, "fire": 2.0},
}

# Spawn groups: cost feeds the wave budget, forms are the shapes they may fly in.
const GROUPS := {
	"rocks": {"min": 5, "max": 8, "cost": 1.0, "forms": ["rain"]},
	"fighter": {"min": 3, "max": 6, "cost": 1.6, "forms": ["line", "vee", "column"]},
	"raider": {"min": 3, "max": 6, "cost": 1.3, "forms": ["pincer", "dive"]},
	"weaver": {"min": 4, "max": 7, "cost": 1.6, "forms": ["sine"]},
	"mine": {"min": 2, "max": 4, "cost": 2.2, "forms": ["scatter"]},
	"gunship": {"min": 1, "max": 1, "cost": 7.0, "forms": ["hold"]},
}

const POOLS := [
	{"rocks": 6.0, "fighter": 3.0},
	{"rocks": 3.0, "fighter": 4.0, "raider": 3.0, "weaver": 1.5},
	{"weaver": 4.0, "mine": 3.0, "fighter": 2.0, "raider": 2.0, "rocks": 1.5},
	{"gunship": 1.2, "fighter": 3.0, "rocks": 3.0, "mine": 2.0, "weaver": 2.0},
	{"raider": 5.0, "gunship": 1.6, "weaver": 3.0, "fighter": 2.0, "mine": 1.0},
	{"gunship": 2.0, "raider": 3.0, "weaver": 3.0, "fighter": 3.0, "mine": 2.0, "rocks": 2.0},
]

const BOSSES := [
	{"name": "THE GRAVITY WARDEN", "hp": 170.0, "hue": 0.0, "patterns": ["fan", "burst", "rocks"]},
	{"name": "THE EMBER TYRANT", "hp": 340.0, "hue": 0.14, "patterns": ["fan", "ring", "burst", "raiders"]},
	{"name": "THE ORBITAL HYDRA", "hp": 560.0, "hue": 0.82, "patterns": ["spiral", "ring", "mines", "burst"]},
	{"name": "THE PALE REGENT", "hp": 700.0, "hue": 0.5, "patterns": ["curtain", "fan", "strike", "burst"]},
	{"name": "THE CRIMSON ADMIRAL", "hp": 800.0, "hue": 0.03, "patterns": ["strike", "spiral", "raiders", "curtain"]},
	{"name": "THE SUNKEN CORE", "hp": 1200.0, "hue": 0.3, "patterns": ["spiral", "curtain", "strike", "ring", "mines", "burst"]},
]

const SHIPS := {
	"nova": {"name": "NOVA", "desc": "Balanced and tough", "cost": 0, "hull": 0, "fire": 1.0, "shield": 1.0},
	"interceptor": {"name": "INTERCEPTOR", "desc": "Fires faster, less hull", "cost": 1500, "hull": -1, "fire": 0.82, "shield": 1.15},
}

const HANGAR := [
	{"id": "cannon", "name": "CANNON", "desc": "+15% shot damage", "max": 6, "base": 60},
	{"id": "rapid", "name": "RAPID FIRE", "desc": "Fire 7% faster", "max": 6, "base": 60},
	{"id": "shield", "name": "SHIELD CELL", "desc": "+20 shield", "max": 5, "base": 50},
	{"id": "hull", "name": "HULL FRAME", "desc": "+1 hull", "max": 3, "base": 160},
	{"id": "magnet", "name": "MAGNET", "desc": "Pull salvage from farther", "max": 4, "base": 40},
	{"id": "reactor", "name": "REACTOR", "desc": "Nova Burst charges faster", "max": 4, "base": 80},
]

static func sector_of(level: int) -> int:
	return clampi((level - 1) / LEVELS_PER_SECTOR + 1, 1, SECTOR_COUNT)

static func index_of(level: int) -> int:
	return (level - 1) % LEVELS_PER_SECTOR + 1

static func is_boss(level: int) -> bool:
	return index_of(level) == LEVELS_PER_SECTOR

static func is_elite(level: int) -> bool:
	return index_of(level) == 5

static func sector(level: int) -> Dictionary:
	return SECTORS[sector_of(level) - 1]

static func hangar_item(id: String) -> Dictionary:
	for item in HANGAR:
		if item.id == id:
			return item
	return {}

static func upgrade_cost(id: String, level: int) -> int:
	var base: float = hangar_item(id).base
	return int(round(base * pow(1.72, level) / 5.0)) * 5

static func difficulty(level: int) -> Dictionary:
	var d := float(level - 1) / float(LEVEL_COUNT - 1)
	return {
		"d": d,
		"hp": 1.0 + d * 2.7,
		"speed": 1.0 + d * 0.5,
		"fire": 1.0 + d * 1.05,
		"bullet": 1.0 + d * 0.5,
	}

static func build(level: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * level + 13
	var s := sector_of(level)
	var idx := index_of(level)
	var diff := difficulty(level)
	var boss := is_boss(level)
	var elite := is_elite(level)
	var wave_count := 1 if boss else 2 + idx / 4
	var waves: Array = []
	for w in range(wave_count):
		var budget := 8.0 + float(idx) * 1.0 + float(s) * 3.0 + float(w) * 1.5
		var groups := make_wave(rng, budget, s, idx, float(diff.d))
		waves.append(groups)
	if elite:
		waves[-1].append({"kind": "elite", "form": "hold", "count": 1 + (s / 3), "delay": 3.0})
	return {
		"level": level, "sector": s, "index": idx, "boss": boss, "elite": elite,
		"waves": waves, "scale": diff, "boss_def": BOSSES[s - 1] if boss else {},
		"reward": 20 + level * 5 / 2,
	}

static func make_wave(rng: RandomNumberGenerator, budget: float, sector_num: int, idx: int, d: float) -> Array:
	var pool: Dictionary = POOLS[sector_num - 1].duplicate()
	# Early levels of the first sector ease in with one enemy type at a time.
	if sector_num == 1 and idx <= 2:
		pool = {"rocks": 1.0}
	var groups: Array = []
	var left := budget
	var guard := 0
	while left > 0.0 and guard < 12:
		guard += 1
		var kind := _pick(rng, pool)
		var info: Dictionary = GROUPS[kind]
		var count := rng.randi_range(int(info.min), int(info.max))
		var forms: Array = info.forms
		var form: String = forms[rng.randi() % forms.size()]
		var spacing := lerpf(3.1, 2.1, d) + float(count) * 0.12
		groups.append({"kind": kind, "form": form, "count": count, "delay": spacing})
		left -= float(count) * float(info.cost)
		if kind == "gunship":
			pool.erase("gunship") # One heavy per wave keeps the screen readable.
	return groups

static func build_endless(wave: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * wave + 7
	var s := (wave - 1) / 5 % SECTOR_COUNT + 1
	var level := mini(wave * 2, LEVEL_COUNT)
	var diff := difficulty(level)
	diff.hp = float(diff.hp) * (1.0 + maxf(0.0, float(wave - 30)) * 0.05)
	var boss := wave % 5 == 0
	var groups: Array = [] if boss else make_wave(rng, 9.0 + float(wave) * 0.9, s, 5 + wave % 5, float(diff.d))
	return {"level": level, "sector": s, "index": wave, "boss": boss, "elite": false, "waves": [groups], "scale": diff, "boss_def": BOSSES[s - 1] if boss else {}, "reward": 8 + wave * 3}

static func _pick(rng: RandomNumberGenerator, pool: Dictionary) -> String:
	var total := 0.0
	for k in pool:
		total += float(pool[k])
	var roll := rng.randf() * total
	for k in pool:
		roll -= float(pool[k])
		if roll <= 0.0:
			return k
	return pool.keys()[0]
