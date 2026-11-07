class_name Cards
extends RefCounted
## Module cards: rarities, synergies and evolutions.
## "stats" is plain data. Combat reads the summed stats, so a new card rarely needs new code.

enum { COMMON, RARE, EPIC, EVOLVED }

const RARITY_NAMES := ["COMMON", "RARE", "EPIC", "EVOLVED"]
const RARITY_COLORS := [Color(0.62, 0.86, 1.0), Color(0.32, 1.0, 0.72), Color(0.82, 0.48, 1.0), Color(1.0, 0.82, 0.32)]
const RARITY_WEIGHTS := [62.0, 30.0, 12.0, 0.0]
# Stats that multiply instead of adding. Everything else stacks additively.
const MULTIPLY := ["dmg_mult", "fire_mult", "nova_gain", "salvage_mult", "shield_mult", "shot_speed"]

const ICONS := {
	"beam": preload("res://assets/starfall/ui_icons/upgrade_tri_beam.png"),
	"shot": preload("res://assets/starfall/projectiles/projectile_player_cyan.png"),
	"drone": preload("res://assets/starfall/ships/player_interceptor_02.png"),
	"crystal": preload("res://assets/starfall/environment/salvage_crystal_blue.png"),
	"hull": preload("res://assets/starfall/ui_icons/upgrade_hull_plating.png"),
	"burn": preload("res://assets/starfall/ui_icons/upgrade_afterburner.png"),
	"skull": preload("res://assets/starfall/ui_icons/icon_boss.png"),
	"wave": preload("res://assets/starfall/ui_icons/icon_wave_status.png"),
	"orb": preload("res://assets/starfall/effects/effect_shield_orb.png"),
	"blast": preload("res://assets/starfall/effects/effect_explosion_small.png"),
	"bigblast": preload("res://assets/starfall/effects/effect_explosion_large.png"),
	"laser": preload("res://assets/starfall/projectiles/projectile_laser_magenta.png"),
	"shard": preload("res://assets/starfall/gen/boss_regent_shard.png"),
	"modules": preload("res://assets/starfall/ui_icons/icon_modules.png"),
	"eye": preload("res://assets/starfall/gen/boss_core_eye.png"),
	"pod": preload("res://assets/starfall/gen/pod.png"),
}

# "unlock": "" means available from the start, otherwise a blueprint id.
const LIST := {
	# Common: reliable and always useful.
	"spread": {"name": "TRI-BEAM", "desc": "Fire one more shot", "rarity": COMMON, "icon": "beam", "max": 4, "tags": ["shots"], "stats": {"lanes": 1.0}, "unlock": ""},
	"overclock": {"name": "OVERCLOCK", "desc": "Fire 15% faster", "rarity": COMMON, "icon": "wave", "max": 4, "tags": ["shots"], "stats": {"fire_mult": 0.85}, "unlock": ""},
	"plating": {"name": "HULL PLATING", "desc": "+30 shield and refill it now", "rarity": COMMON, "icon": "hull", "max": 4, "tags": ["defense"], "stats": {"shield_add": 30.0}, "unlock": ""},
	"magnet": {"name": "SALVAGE MAGNET", "desc": "Pull crystals from much farther away", "rarity": COMMON, "icon": "crystal", "max": 3, "tags": ["economy"], "stats": {"magnet": 110.0}, "unlock": ""},
	"critical": {"name": "CRIT MATRIX", "desc": "+12% chance of double damage", "rarity": COMMON, "icon": "skull", "max": 4, "tags": ["crit"], "stats": {"crit": 0.12}, "unlock": ""},
	"afterburner": {"name": "AFTERBURNER", "desc": "Shots fly faster and hit 12% harder", "rarity": COMMON, "icon": "burn", "max": 3, "tags": ["shots"], "stats": {"shot_speed": 1.25, "dmg_mult": 1.12}, "unlock": ""},
	"reactor": {"name": "REACTOR CELL", "desc": "Nova Burst charges 30% faster", "rarity": COMMON, "icon": "orb", "max": 3, "tags": ["nova"], "stats": {"nova_gain": 1.3}, "unlock": ""},
	"repair": {"name": "FIELD REPAIR", "desc": "Restore one hull right now", "rarity": COMMON, "icon": "hull", "max": 9, "tags": ["defense"], "stats": {}, "unlock": "", "instant": "repair"},
	# Rare: these change how you play.
	"pierce": {"name": "PHASE ROUNDS", "desc": "Shots pass through one more target", "rarity": RARE, "icon": "shot", "max": 3, "tags": ["shots"], "stats": {"pierce": 1.0}, "unlock": ""},
	"drone": {"name": "ORBITAL DRONE", "desc": "A wingman fires beside you", "rarity": RARE, "icon": "drone", "max": 3, "tags": ["drones"], "stats": {"drones": 1.0}, "unlock": ""},
	"seeker": {"name": "SEEKER PODS", "desc": "Launch a homing missile every 1.6s", "rarity": RARE, "icon": "laser", "max": 3, "tags": ["missiles"], "stats": {"seekers": 1.0}, "unlock": "bp_seeker"},
	"arc": {"name": "CHAIN ARC", "desc": "Hits have a 22% chance to arc lightning", "rarity": RARE, "icon": "wave", "max": 3, "tags": ["status"], "stats": {"arc": 0.22}, "unlock": "bp_arc"},
	"burn": {"name": "INCENDIARY", "desc": "Hits set enemies on fire", "rarity": RARE, "icon": "burn", "max": 3, "tags": ["status"], "stats": {"burn": 1.0}, "unlock": "bp_burn"},
	"cryo": {"name": "CRYO ROUNDS", "desc": "Hits slow enemies and their shots", "rarity": RARE, "icon": "shard", "max": 2, "tags": ["status"], "stats": {"cryo": 1.0}, "unlock": "bp_cryo"},
	"ricochet": {"name": "RICOCHET", "desc": "Shots bounce to a new target once", "rarity": RARE, "icon": "shot", "max": 2, "tags": ["shots"], "stats": {"ricochet": 1.0}, "unlock": ""},
	"graze": {"name": "GRAZE BATTERY", "desc": "Near misses charge Nova Burst", "rarity": RARE, "icon": "orb", "max": 2, "tags": ["nova", "risk"], "stats": {"graze": 1.0}, "unlock": ""},
	"spike": {"name": "REACTIVE SHIELD", "desc": "Shield hits blast every shot nearby", "rarity": RARE, "icon": "hull", "max": 2, "tags": ["defense"], "stats": {"spike": 1.0}, "unlock": "bp_spike"},
	# Epic: strong, and many have a price.
	"glass": {"name": "GLASS REACTOR", "desc": "+60% damage, but one less hull", "rarity": EPIC, "icon": "blast", "max": 2, "tags": ["risk"], "stats": {"dmg_mult": 1.6, "hull_add": -1.0}, "unlock": ""},
	"greed": {"name": "GREED PROTOCOL", "desc": "Double salvage, but 40% less shield", "rarity": EPIC, "icon": "crystal", "max": 1, "tags": ["economy", "risk"], "stats": {"salvage_mult": 2.0, "shield_mult": 0.6}, "unlock": ""},
	"echo": {"name": "NOVA ECHO", "desc": "Nova Burst fires a second time", "rarity": EPIC, "icon": "bigblast", "max": 1, "tags": ["nova"], "stats": {"echo": 1.0}, "unlock": "bp_echo"},
	"phoenix": {"name": "SECOND WIND", "desc": "Survive one fatal hit with full shield", "rarity": EPIC, "icon": "orb", "max": 1, "tags": ["defense"], "stats": {"phoenix": 1.0}, "unlock": "bp_phoenix"},
	"redline": {"name": "REDLINE", "desc": "Up to +90% damage as your shield drops", "rarity": EPIC, "icon": "skull", "max": 1, "tags": ["risk"], "stats": {"redline": 0.9}, "unlock": ""},
	# Evolved: never rolled randomly. They appear when their parts are held.
	"prism": {"name": "PRISM LANCE", "desc": "Shots split into two beams on every hit", "rarity": EVOLVED, "icon": "beam", "max": 1, "tags": ["shots"], "stats": {"prism": 1.0}, "unlock": "", "needs": ["spread", "pierce"]},
	"hunter": {"name": "HUNTER WING", "desc": "Drones launch seeker missiles", "rarity": EVOLVED, "icon": "drone", "max": 1, "tags": ["drones", "missiles"], "stats": {"hunter": 1.0}, "unlock": "", "needs": ["drone", "seeker"]},
	"aegis_wing": {"name": "AEGIS WING", "desc": "Drones shoot down shots that get close", "rarity": EVOLVED, "icon": "orb", "max": 1, "tags": ["drones", "defense"], "stats": {"aegis_wing": 1.0}, "unlock": "", "needs": ["drone", "plating"]},
	"tesla": {"name": "TESLA STORM", "desc": "Every critical hit arcs to four enemies", "rarity": EVOLVED, "icon": "wave", "max": 1, "tags": ["crit", "status"], "stats": {"tesla": 1.0}, "unlock": "", "needs": ["arc", "critical"]},
	"midas": {"name": "MIDAS ENGINE", "desc": "Each crystal adds 1% damage for this level", "rarity": EVOLVED, "icon": "crystal", "max": 1, "tags": ["economy"], "stats": {"midas": 1.0}, "unlock": "", "needs": ["magnet", "greed"]},
	"inferno": {"name": "INFERNO", "desc": "Burning enemies explode when destroyed", "rarity": EVOLVED, "icon": "bigblast", "max": 1, "tags": ["status"], "stats": {"inferno": 1.0}, "unlock": "", "needs": ["burn", "overclock"]},
	"zero": {"name": "ABSOLUTE ZERO", "desc": "Cryo hits freeze enemies solid", "rarity": EVOLVED, "icon": "shard", "max": 1, "tags": ["status"], "stats": {"zero": 1.0}, "unlock": "", "needs": ["cryo", "pierce"]},
	"supernova": {"name": "SUPERNOVA", "desc": "Nova Burst refunds half its charge", "rarity": EVOLVED, "icon": "bigblast", "max": 1, "tags": ["nova"], "stats": {"nova_refund": 50.0}, "unlock": "", "needs": ["reactor", "echo"]},
	"bastion": {"name": "BASTION", "desc": "Your shield can no longer be broken in one hit", "rarity": EVOLVED, "icon": "hull", "max": 1, "tags": ["defense"], "stats": {"bastion": 1.0}, "unlock": "", "needs": ["spike", "plating"]},
	"daredevil": {"name": "DAREDEVIL", "desc": "Near misses deal damage to every enemy", "rarity": EVOLVED, "icon": "skull", "max": 1, "tags": ["risk"], "stats": {"daredevil": 1.0}, "unlock": "", "needs": ["graze", "redline"]},
}

static func unlocked(id: String, blueprints: Array) -> bool:
	var need: String = LIST[id].unlock
	return need.is_empty() or need in blueprints

## Evolutions the held cards qualify for right now.
static func evolutions_ready(held: Dictionary) -> Array:
	var out: Array = []
	for id in LIST:
		var c: Dictionary = LIST[id]
		if int(c.rarity) != EVOLVED or held.has(id):
			continue
		var ok := true
		for need in c.needs:
			if not held.has(need):
				ok = false
		if ok:
			out.append(id)
	return out

## Finds the evolution this card would complete or start, for the card's synergy hint.
static func synergy_for(id: String, held: Dictionary) -> Dictionary:
	var partial := {}
	for evo in LIST:
		var c: Dictionary = LIST[evo]
		if int(c.rarity) != EVOLVED or held.has(evo) or not id in c.needs:
			continue
		var other := ""
		for need in c.needs:
			if need != id:
				other = need
		if held.has(other):
			return {"evo": evo, "other": other, "ready": true}
		if partial.is_empty():
			partial = {"evo": evo, "other": other, "ready": false}
	return partial

## Rolls a choice of cards. Evolutions come first, then a pool biased toward the current build.
static func offer(held: Dictionary, blueprints: Array, rng: RandomNumberGenerator, count: int, hull_missing: bool, rarity_boost := 0.0) -> Array:
	var picks: Array = []
	for evo in evolutions_ready(held):
		if picks.size() < mini(1, count):
			picks.append(evo)
	var pool: Array = []
	var weights: Array = []
	for id in LIST:
		var c: Dictionary = LIST[id]
		if int(c.rarity) == EVOLVED or id in picks or not unlocked(id, blueprints):
			continue
		if int(held.get(id, 0)) >= int(c.max):
			continue
		if id == "repair" and not hull_missing:
			continue
		var w: float = RARITY_WEIGHTS[int(c.rarity)]
		if int(c.rarity) > COMMON:
			w *= 1.0 + rarity_boost
		var syn := synergy_for(id, held)
		if not syn.is_empty():
			w *= 3.0 if syn.ready else 1.5
		for tag in c.tags:
			for h in held:
				if tag in LIST[h].tags:
					w *= 1.15
		pool.append(id)
		weights.append(w)
	while picks.size() < count and not pool.is_empty():
		var total := 0.0
		for w in weights:
			total += float(w)
		var roll := rng.randf() * total
		for i in range(pool.size()):
			roll -= float(weights[i])
			if roll <= 0.0 or i == pool.size() - 1:
				picks.append(pool[i])
				pool.remove_at(i)
				weights.remove_at(i)
				break
	return picks

## Sums the stats of a build into a single dictionary.
static func sum_stats(held: Dictionary, into: Dictionary) -> void:
	for id in held:
		if not LIST.has(id):
			continue
		var c: Dictionary = LIST[id]
		for key in c.stats:
			for i in range(int(held[id])):
				if key in MULTIPLY:
					into[key] = float(into.get(key, 1.0)) * float(c.stats[key])
				else:
					into[key] = float(into.get(key, 0.0)) + float(c.stats[key])
