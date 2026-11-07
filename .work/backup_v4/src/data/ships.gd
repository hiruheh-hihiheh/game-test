class_name Ships
extends RefCounted
## Five ships that play differently, not five stat blocks.

const ART := {
	"nova": preload("res://assets/starfall/ships/player_nova_01.png"),
	"interceptor": preload("res://assets/starfall/ships/player_interceptor_02.png"),
	"lancer": preload("res://assets/starfall/gen/ship_lancer.png"),
	"warden": preload("res://assets/starfall/gen/ship_warden.png"),
	"magpie": preload("res://assets/starfall/gen/ship_magpie.png"),
}

const ORDER := ["nova", "interceptor", "lancer", "warden", "magpie"]

# weapon: pulse, twin, beam, missile, scatter. "blueprint" names what must be found first.
const LIST := {
	"nova": {
		"name": "NOVA", "role": "ALL-ROUNDER", "weapon": "pulse", "hull": 3, "shield": 60.0, "speed": 1.0,
		"hitbox": 15.0, "nova_gain": 1.25, "cost": 0, "blueprint": "",
		"weapon_desc": "Steady pulse cannon",
		"trait": "CAPACITOR", "trait_desc": "Nova Burst charges 25% faster",
	},
	"interceptor": {
		"name": "INTERCEPTOR", "role": "RISK TAKER", "weapon": "twin", "hull": 2, "shield": 50.0, "speed": 1.2,
		"hitbox": 11.0, "nova_gain": 1.0, "cost": 300, "blueprint": "bp_interceptor",
		"weapon_desc": "Rapid twin guns",
		"trait": "SLIPSTREAM", "trait_desc": "Near misses charge Nova and boost your fire rate",
	},
	"lancer": {
		"name": "LANCER", "role": "SNIPER", "weapon": "beam", "hull": 3, "shield": 45.0, "speed": 0.95,
		"hitbox": 13.0, "nova_gain": 1.0, "cost": 600, "blueprint": "bp_lancer",
		"weapon_desc": "Continuous piercing beam",
		"trait": "STEADY AIM", "trait_desc": "Hold still and the beam ramps up to 2.4x damage",
	},
	"warden": {
		"name": "WARDEN", "role": "TANK", "weapon": "missile", "hull": 4, "shield": 100.0, "speed": 0.85,
		"hitbox": 19.0, "nova_gain": 1.0, "cost": 900, "blueprint": "bp_warden",
		"weapon_desc": "Homing missile salvos",
		"trait": "BULWARK", "trait_desc": "Shield hits blast nearby shots. Shield refills sooner",
	},
	"magpie": {
		"name": "MAGPIE", "role": "SCAVENGER", "weapon": "scatter", "hull": 3, "shield": 55.0, "speed": 1.1,
		"hitbox": 14.0, "nova_gain": 1.0, "cost": 1200, "blueprint": "bp_magpie",
		"weapon_desc": "Close-range scatter gun",
		"trait": "FINDERS KEEPERS", "trait_desc": "Crystals pay 50% more. Every 10 grants a damage surge",
	},
}

# Permanent weapon balance. Damage is per projectile.
const WEAPONS := {
	"pulse": {"interval": 0.24, "damage": 1.1, "speed": 900.0, "size": 82.0},
	"twin": {"interval": 0.14, "damage": 0.58, "speed": 1050.0, "size": 64.0},
	"beam": {"interval": 0.10, "damage": 0.34, "speed": 0.0, "size": 0.0},
	"missile": {"interval": 0.72, "damage": 1.05, "speed": 520.0, "size": 70.0},
	"scatter": {"interval": 0.42, "damage": 0.85, "speed": 980.0, "size": 58.0},
}

const NOVA_MODES := {
	"pulse": {"name": "NOVA PULSE", "desc": "Clears every shot and damages everything on screen", "blueprint": ""},
	"singularity": {"name": "SINGULARITY", "desc": "A black hole drags in shots and enemies, then detonates", "blueprint": "bp_singularity"},
	"overdrive": {"name": "OVERDRIVE", "desc": "6 seconds of triple fire rate and a shield that cannot break", "blueprint": "bp_overdrive"},
	"aegis": {"name": "AEGIS", "desc": "5 seconds of a mirror field that sends shots back", "blueprint": "bp_aegis"},
}

# Paints are hue shifts earned through mastery. id -> hue and display name.
const PAINTS := {
	"stock": {"name": "STOCK", "hue": 0.0},
	"ember": {"name": "EMBER", "hue": 0.55},
	"verdant": {"name": "VERDANT", "hue": 0.8},
	"royal": {"name": "ROYAL", "hue": 0.2},
	"crimson": {"name": "CRIMSON", "hue": 0.42},
	"core": {"name": "CORE GOLD", "hue": 0.62, "blueprint": "paint_core"},
}

# Mastery level -> reward. Earned by flying that ship; each ship tracks its own.
const MASTERY := {
	2: {"type": "stat", "stat": "dmg_mult", "value": 1.05, "text": "+5% damage"},
	3: {"type": "paint", "paint": "ember", "text": "Ember paint"},
	4: {"type": "stat", "stat": "shield_add", "value": 10.0, "text": "+10 shield"},
	5: {"type": "stat", "stat": "nova_gain", "value": 1.1, "text": "+10% Nova charge"},
	6: {"type": "paint", "paint": "verdant", "text": "Verdant paint"},
	7: {"type": "stat", "stat": "dmg_mult", "value": 1.05, "text": "+5% damage"},
	8: {"type": "paint", "paint": "royal", "text": "Royal paint"},
	9: {"type": "stat", "stat": "salvage_mult", "value": 1.1, "text": "+10% salvage"},
	10: {"type": "paint", "paint": "crimson", "text": "Crimson paint"},
}
const MAX_MASTERY := 10

static func xp_for(level: int) -> int:
	return 300 * level * level

static func mastery_level(xp: int) -> int:
	var lvl := 1
	while lvl < MAX_MASTERY and xp >= xp_for(lvl):
		lvl += 1
	return lvl
