class_name Gear
extends RefCounted
## Loot gear. Three slots per ship, five rarities, random affixes and legendary perks.
## An item is plain data, so it saves as-is, and a new affix or perk is one line.

enum { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]
const RARITY_COLORS := [Color(0.72, 0.78, 0.88), Color(0.45, 0.95, 0.55), Color(0.35, 0.70, 1.0), Color(0.82, 0.48, 1.0), Color(1.0, 0.78, 0.25)]
const RARITY_MULT := [1.0, 1.25, 1.55, 1.95, 2.45]
const AFFIX_COUNT := [1, 2, 2, 3, 3]
const LEVEL_CAP := [4, 6, 8, 10, 12]
const COST_MULT := [1.0, 1.5, 2.2, 3.2, 4.5]
const SCRAP_BASE := [3, 7, 15, 32, 80]
const MAX_ITEMS := 80
const SLOTS := ["weapon", "reactor", "plating"]
const SLOT_INFO := {
	"weapon": {"name": "WEAPON", "icon": "beam"},
	"reactor": {"name": "REACTOR", "icon": "wave"},
	"plating": {"name": "PLATING", "icon": "hull"},
}

# mode: mult multiplies (1 + v), rate speeds fire (1 / (1 + v)), add adds, hull is a whole number.
const AFFIXES := {
	"dmg_mult": {"label": "Damage", "base": 0.05, "mode": "mult", "fmt": "pct", "slot": "weapon"},
	"fire_mult": {"label": "Fire rate", "base": 0.04, "mode": "rate", "fmt": "pct", "slot": "weapon"},
	"crit": {"label": "Crit chance", "base": 0.03, "mode": "add", "fmt": "pct", "slot": "weapon"},
	"shot_speed": {"label": "Shot speed", "base": 0.05, "mode": "mult", "fmt": "pct", "slot": "weapon"},
	"nova_gain": {"label": "Nova charge", "base": 0.07, "mode": "mult", "fmt": "pct", "slot": "reactor"},
	"magnet": {"label": "Magnet range", "base": 25.0, "mode": "add", "fmt": "num", "slot": "reactor"},
	"salvage_mult": {"label": "Salvage", "base": 0.04, "mode": "mult", "fmt": "pct", "slot": "reactor"},
	"nova_start": {"label": "Nova at start", "base": 6.0, "mode": "add", "fmt": "pctpts", "slot": "reactor"},
	"shield_add": {"label": "Shield", "base": 8.0, "mode": "add", "fmt": "num", "slot": "plating"},
	"shield_regen": {"label": "Shield regen", "base": 1.2, "mode": "add", "fmt": "rate", "slot": "plating"},
	"iframes": {"label": "Hit immunity", "base": 0.05, "mode": "add", "fmt": "sec", "slot": "plating"},
	"hull_add": {"label": "Hull", "base": 1.0, "mode": "hull", "fmt": "num", "slot": "plating", "min_rarity": 3},
}

# Legendary perks. Each reuses a stat the card system already understands.
# "boss" is the sector whose boss is the best place to farm it.
const PERKS := {
	"wardens_lens": {"name": "WARDEN'S LENS", "slot": "weapon", "boss": 1, "desc": "Shots ricochet to a new target", "stats": {"ricochet": 1.0}},
	"bulwark_plate": {"name": "BULWARK PLATE", "slot": "plating", "boss": 1, "desc": "Shield hits blast nearby shots", "stats": {"spike": 1.0}},
	"tyrants_torch": {"name": "TYRANT'S TORCH", "slot": "weapon", "boss": 2, "desc": "Hits set enemies on fire", "stats": {"burn": 1.0}},
	"furnace_core": {"name": "FURNACE CORE", "slot": "reactor", "boss": 2, "desc": "Nova Burst fires twice", "stats": {"echo": 1.0}},
	"brood_heart": {"name": "BROOD HEART", "slot": "reactor", "boss": 3, "desc": "A wingman drone fights beside you", "stats": {"drones": 1.0}},
	"spore_launcher": {"name": "SPORE LAUNCHER", "slot": "weapon", "boss": 3, "desc": "Launches homing missiles", "stats": {"seekers": 1.0}},
	"frost_lance": {"name": "FROST LANCE", "slot": "weapon", "boss": 4, "desc": "Hits slow enemies", "stats": {"cryo": 1.0}},
	"crown_shard": {"name": "CROWN SHARD", "slot": "plating", "boss": 4, "desc": "Survive one fatal hit", "stats": {"phoenix": 1.0}},
	"admirals_cannon": {"name": "ADMIRAL'S CANNON", "slot": "weapon", "boss": 5, "desc": "Shots pierce one more target", "stats": {"pierce": 1.0}},
	"war_reactor": {"name": "WAR REACTOR", "slot": "reactor", "boss": 5, "desc": "Near misses charge Nova", "stats": {"graze": 1.0}},
	"starfall_prism": {"name": "STARFALL PRISM", "slot": "weapon", "boss": 6, "desc": "Shots split into twin beams", "stats": {"prism": 1.0}},
	"event_horizon": {"name": "EVENT HORIZON", "slot": "plating", "boss": 6, "desc": "Shield survives any single hit", "stats": {"bastion": 1.0}},
	"core_of_stars": {"name": "CORE OF STARS", "slot": "reactor", "boss": 6, "desc": "Nova Burst refunds a quarter of its charge", "stats": {"nova_refund": 25.0}},
}

const NOUNS := {
	"weapon": ["Pulse Cannon", "Rail Driver", "Arc Projector", "Plasma Lance", "Ion Repeater"],
	"reactor": ["Fusion Cell", "Nova Core", "Flux Engine", "Quantum Pile", "Pulse Capacitor"],
	"plating": ["Hull Plate", "Aegis Shell", "Bulwark Frame", "Ablative Skin", "Ward Casing"],
}
const PREFIX := ["Salvaged", "Refurbished", "Tuned", "Prototype", ""]

## Chooses a rarity. Power and luck both push the odds up, and min_rarity is a floor.
static func roll_rarity(rng: RandomNumberGenerator, power: float, luck: float, min_rarity := 0) -> int:
	var weights := [
		maxf(18.0, 62.0 - power * 0.9),
		26.0,
		9.0 + power * 0.25 + luck * 1.5,
		3.0 + power * 0.12 + luck * 2.0,
		0.35 + power * 0.03 + luck * 1.0,
	]
	var total := 0.0
	for w in weights:
		total += float(w)
	var roll := rng.randf() * total
	var result: int = weights.size() - 1
	for i in range(weights.size()):
		roll -= float(weights[i])
		if roll <= 0.0:
			result = i
			break
	return maxi(result, min_rarity)

static func roll_item(rng: RandomNumberGenerator, power: float, luck := 0.0, min_rarity := 0, boss_sector := 0, slot := "") -> Dictionary:
	return generate(rng, power, roll_rarity(rng, power, luck, min_rarity), slot, boss_sector)

static func generate(rng: RandomNumberGenerator, power: float, rarity: int, slot := "", boss_sector := 0) -> Dictionary:
	if slot.is_empty():
		slot = SLOTS[rng.randi() % SLOTS.size()]
	var pool: Array = []
	for k in AFFIXES:
		var def: Dictionary = AFFIXES[k]
		if str(def.slot) == slot and rarity >= int(def.get("min_rarity", 0)):
			pool.append(k)
	var aff: Array = []
	var want: int = mini(int(AFFIX_COUNT[rarity]), pool.size())
	while aff.size() < want:
		var k: String = pool[rng.randi() % pool.size()]
		pool.erase(k)
		aff.append({"k": k, "r": snappedf(rng.randf(), 0.01)})
	var perk := ""
	if rarity == LEGENDARY:
		perk = _pick_perk(rng, slot, boss_sector)
	var item := {"uid": 0, "slot": slot, "rarity": rarity, "power": maxi(1, int(round(power))), "lvl": 0, "aff": aff, "perk": perk, "name": "", "new": true}
	var nouns: Array = NOUNS[slot]
	var noun: String = nouns[rng.randi() % nouns.size()]
	if perk.is_empty():
		item.name = ("%s %s" % [PREFIX[rarity], noun]).strip_edges()
	else:
		item.name = str(PERKS[perk].name)
	return item

static func _pick_perk(rng: RandomNumberGenerator, slot: String, boss_sector: int) -> String:
	var matching: Array = []
	var boss_pool: Array = []
	for id in PERKS:
		var p: Dictionary = PERKS[id]
		if str(p.slot) != slot:
			continue
		matching.append(id)
		if boss_sector > 0 and int(p.boss) == boss_sector:
			boss_pool.append(id)
	if not boss_pool.is_empty() and rng.randf() < 0.65:
		return boss_pool[rng.randi() % boss_pool.size()]
	return matching[rng.randi() % matching.size()]

# ---------- Numbers ----------

static func affix_value(item: Dictionary, a: Dictionary) -> float:
	var def: Dictionary = AFFIXES[a.k]
	if str(def.mode) == "hull":
		return 1.0 + (1.0 if int(item.rarity) >= LEGENDARY and int(item.lvl) >= 8 else 0.0)
	var power_scale := 1.0 + 0.025 * float(int(item.power) - 1)
	return float(def.base) * (0.6 + 0.4 * float(a.r)) * float(RARITY_MULT[int(item.rarity)]) * power_scale * (1.0 + 0.1 * float(int(item.lvl)))

static func apply_to(item: Dictionary, s: Dictionary) -> void:
	for a in item.aff:
		var def: Dictionary = AFFIXES[a.k]
		var v := affix_value(item, a)
		var key: String = a.k
		match str(def.mode):
			"mult":
				s[key] = float(s.get(key, 1.0)) * (1.0 + v)
			"rate":
				s[key] = float(s.get(key, 1.0)) / (1.0 + v)
			"hull":
				s["hull_add"] = float(s.get("hull_add", 0.0)) + v
			_:
				s[key] = float(s.get(key, 0.0)) + v
	var perk: String = item.get("perk", "")
	if not perk.is_empty() and PERKS.has(perk):
		var stats: Dictionary = PERKS[perk].stats
		for key in stats:
			s[key] = float(s.get(key, 0.0)) + float(stats[key])

static func apply_equipped(ship_id: String, s: Dictionary) -> void:
	for slot in SLOTS:
		var item: Dictionary = Save.equipped_item(ship_id, slot)
		if not item.is_empty():
			apply_to(item, s)

## A single number for comparing two items of the same slot.
static func rating(item: Dictionary) -> int:
	var total := 0.0
	for a in item.aff:
		var def: Dictionary = AFFIXES[a.k]
		total += affix_value(item, a) / float(def.base) * 10.0
	if not str(item.get("perk", "")).is_empty():
		total += 40.0
	return int(round(total))

static func affix_text(item: Dictionary, a: Dictionary) -> String:
	var def: Dictionary = AFFIXES[a.k]
	var v := affix_value(item, a)
	match str(def.fmt):
		"pct":
			return ("+%.1f%% %s" if v < 0.1 else "+%d%% %s") % [v * 100.0 if v < 0.1 else round(v * 100.0), def.label]
		"num":
			return "+%d %s" % [int(round(v)), def.label]
		"pctpts":
			return "+%d%% %s" % [int(round(v)), def.label]
		"rate":
			return "+%.1f/s %s" % [v, def.label]
		"sec":
			return "+%.2f sec %s" % [v, def.label]
	return str(def.label)

static func lines(item: Dictionary) -> Array:
	var out: Array = []
	for a in item.aff:
		out.append(affix_text(item, a))
	return out

static func perk_text(item: Dictionary) -> String:
	var perk: String = item.get("perk", "")
	if perk.is_empty() or not PERKS.has(perk):
		return ""
	return str(PERKS[perk].desc)

# ---------- Upgrading and scrapping ----------

static func level_cap(item: Dictionary) -> int:
	return int(LEVEL_CAP[int(item.rarity)])

static func upgrade_cost(item: Dictionary) -> int:
	if int(item.lvl) >= level_cap(item):
		return -1
	return int(round(2.5 * float(COST_MULT[int(item.rarity)]) * pow(float(int(item.lvl) + 1), 1.4)))

static func invested(item: Dictionary) -> int:
	var total := 0
	var probe := item.duplicate()
	for l in range(int(item.lvl)):
		probe.lvl = l
		total += upgrade_cost(probe)
	return total

static func scrap_value(item: Dictionary) -> int:
	return int(SCRAP_BASE[int(item.rarity)]) + int(0.6 * float(invested(item)))
