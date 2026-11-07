class_name Mutators
extends RefCounted
## Optional dials. Each one makes a level harder and pays a bonus on score and salvage.

const LIST := {
	"swift": {"name": "OVERDRIVE FIRE", "desc": "Enemy shots are 25% faster", "bonus": 0.25, "bullet": 1.25},
	"swarm": {"name": "SWARM", "desc": "40% more enemies", "bonus": 0.35, "count": 1.4},
	"armor": {"name": "HARDENED", "desc": "Enemies have 40% more health", "bonus": 0.3, "hp": 1.4},
	"frenzy": {"name": "FRENZY", "desc": "Enemies fire 40% more often", "bonus": 0.3, "fire": 1.4},
	"noregen": {"name": "DRY CELLS", "desc": "Your shield never refills", "bonus": 0.4, "noregen": true},
	"brittle": {"name": "BRITTLE", "desc": "You have one hull", "bonus": 0.75, "hull_cap": 1},
	"elites": {"name": "ELITE INVASION", "desc": "Some enemies gain elite powers", "bonus": 0.4, "elites": 0.25},
	"blackout": {"name": "BLACKOUT", "desc": "Only your ship's area is lit", "bonus": 0.35, "blackout": true},
}

const ORDER := ["swift", "swarm", "armor", "frenzy", "noregen", "elites", "blackout", "brittle"]

static func multiplier(ids: Array) -> float:
	var total := 1.0
	for id in ids:
		if LIST.has(id):
			total += float(LIST[id].bonus)
	return total

static func value(ids: Array, key: String, fallback: float) -> float:
	var out := fallback
	for id in ids:
		if LIST.has(id) and LIST[id].has(key):
			out *= float(LIST[id][key])
	return out

static func flag(ids: Array, key: String) -> bool:
	for id in ids:
		if LIST.has(id) and LIST[id].has(key):
			return true
	return false
