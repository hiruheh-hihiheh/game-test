class_name Tiers
extends RefCounted
## Campaign replay tiers. The same 60 levels, tougher enemies, better loot.
## "loot" adds gear power to every drop, "luck" improves the rarity odds.

const LIST := [
	{"name": "NORMAL", "color": Color(0.25, 0.90, 1.0), "hp": 1.0, "bullet": 1.0, "fire": 1.0, "count": 1.0, "elite": 0.0, "loot": 0.0, "luck": 0.0, "xp": 1.0, "salvage": 1.0},
	{"name": "VETERAN", "color": Color(0.32, 1.0, 0.72), "hp": 1.5, "bullet": 1.1, "fire": 1.15, "count": 1.12, "elite": 0.0, "loot": 8.0, "luck": 0.6, "xp": 1.5, "salvage": 1.5},
	{"name": "ELITE", "color": Color(0.58, 0.44, 1.0), "hp": 2.1, "bullet": 1.2, "fire": 1.35, "count": 1.25, "elite": 0.12, "loot": 16.0, "luck": 1.4, "xp": 2.0, "salvage": 2.2},
	{"name": "NIGHTMARE", "color": Color(1.0, 0.27, 0.66), "hp": 2.9, "bullet": 1.32, "fire": 1.6, "count": 1.4, "elite": 0.25, "loot": 24.0, "luck": 2.2, "xp": 3.0, "salvage": 3.2},
	{"name": "STARFALL", "color": Color(1.0, 0.82, 0.32), "hp": 4.0, "bullet": 1.45, "fire": 1.9, "count": 1.55, "elite": 0.35, "loot": 32.0, "luck": 3.2, "xp": 4.0, "salvage": 4.5},
]
const MAX_TIER := 4

static func cfg(t: int) -> Dictionary:
	return LIST[clampi(t, 0, MAX_TIER)]

static func describe(t: int) -> String:
	var c: Dictionary = cfg(t)
	if t <= 0:
		return "The standard campaign."
	return "Enemies +%d%% health and fire %d%% faster. Gear drops are stronger. %.1fx salvage, %.1fx XP." % [int(round((float(c.hp) - 1.0) * 100.0)), int(round((float(c.fire) - 1.0) * 100.0)), float(c.salvage), float(c.xp)]
