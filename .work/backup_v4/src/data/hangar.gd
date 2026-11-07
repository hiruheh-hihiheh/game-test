class_name Hangar
extends RefCounted
## Permanent upgrades. "kind": gear adds numbers, tech unlocks new options.

const LIST := [
	{"id": "cannon", "kind": "gear", "name": "CANNON", "desc": "+15% shot damage", "max": 6, "base": 50, "icon": "beam"},
	{"id": "rapid", "kind": "gear", "name": "RAPID FIRE", "desc": "Fire 7% faster", "max": 6, "base": 50, "icon": "burn"},
	{"id": "shield", "kind": "gear", "name": "SHIELD CELL", "desc": "+20 shield", "max": 5, "base": 45, "icon": "orb"},
	{"id": "hull", "kind": "gear", "name": "HULL FRAME", "desc": "+1 hull", "max": 3, "base": 140, "icon": "hull"},
	{"id": "magnet", "kind": "gear", "name": "MAGNET", "desc": "Pull salvage from farther", "max": 4, "base": 35, "icon": "crystal"},
	{"id": "core", "kind": "gear", "name": "NOVA CORE", "desc": "Nova Burst charges faster", "max": 4, "base": 70, "icon": "wave"},
	{"id": "slot", "kind": "tech", "name": "LOADOUT SLOT", "desc": "Bring one more module into every level", "max": 2, "base": 300, "icon": "modules", "stars": [12, 45]},
	{"id": "reroll", "kind": "tech", "name": "REROLL BAY", "desc": "+1 module reroll per level", "max": 2, "base": 220, "icon": "wave", "stars": [6, 30]},
	{"id": "lucky", "kind": "tech", "name": "RARE SCANNER", "desc": "Rare and epic modules appear more often", "max": 2, "base": 260, "icon": "pod", "stars": [20, 60]},
	{"id": "extra_card", "kind": "tech", "name": "FOURTH OPTION", "desc": "See four modules instead of three", "max": 1, "base": 900, "icon": "modules", "stars": [70]},
	{"id": "emergency", "kind": "tech", "name": "EMERGENCY CELL", "desc": "Refill your shield once per level at zero", "max": 1, "base": 500, "icon": "orb", "stars": [35]},
	{"id": "salvor", "kind": "tech", "name": "SALVOR CONTRACT", "desc": "+20% salvage from every run", "max": 2, "base": 350, "icon": "crystal", "stars": [25, 80]},
	# The Overclock Lab never ends: tiny permanent boosts that soak up spare salvage forever.
	{"id": "ov_dmg", "kind": "lab", "name": "OVERCLOCK: DAMAGE", "desc": "+0.5% damage per level", "max": 9999, "base": 400, "icon": "beam"},
	{"id": "ov_shield", "kind": "lab", "name": "OVERCLOCK: SHIELD", "desc": "+1 shield per level", "max": 9999, "base": 400, "icon": "orb"},
	{"id": "ov_salvage", "kind": "lab", "name": "OVERCLOCK: SALVAGE", "desc": "+0.5% salvage per level", "max": 9999, "base": 400, "icon": "crystal"},
]

static func item(id: String) -> Dictionary:
	for it in LIST:
		if it.id == id:
			return it
	return {}

static func cost(id: String, level: int) -> int:
	var it := item(id)
	var growth := 1.68
	if str(it.kind) == "tech":
		growth = 2.0
	elif str(it.kind) == "lab":
		growth = 1.1
	return int(round(float(it.base) * pow(growth, level) / 5.0)) * 5

## The lab opens once every standard upgrade is maxed.
static func lab_open() -> bool:
	for it in LIST:
		if str(it.kind) == "gear" and Save.upgrade_level(it.id) < int(it.max):
			return false
	return true

## Stars required to buy the next level of a tech item. Gear has no star gate.
static func stars_needed(id: String) -> int:
	var it := item(id)
	if not it.has("stars"):
		return 0
	var gates: Array = it.stars
	return int(gates[mini(Save.upgrade_level(id), gates.size() - 1)])
