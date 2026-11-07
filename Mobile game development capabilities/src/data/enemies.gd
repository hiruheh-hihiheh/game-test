class_name Enemies
extends RefCounted
## Every enemy as data: stats, art, attack and codex text.

const ART := {
	"rock_l": preload("res://assets/starfall/environment/asteroid_large.png"),
	"rock_m": preload("res://assets/starfall/environment/asteroid_medium.png"),
	"rock_s": preload("res://assets/starfall/environment/asteroid_small.png"),
	"fighter": preload("res://assets/starfall/ships/enemy_fighter_01.png"),
	"raider": preload("res://assets/starfall/ships/player_interceptor_02.png"),
	"boss": preload("res://assets/starfall/ships/boss_ship_01.png"),
	"mine": preload("res://assets/starfall/effects/effect_shield_orb.png"),
	"wreck_a": preload("res://assets/starfall/gen/wreck_a.png"),
	"wreck_b": preload("res://assets/starfall/gen/wreck_b.png"),
	"tank": preload("res://assets/starfall/gen/fuel_tank.png"),
	"cinder": preload("res://assets/starfall/gen/cinder.png"),
	"pod": preload("res://assets/starfall/gen/pod.png"),
	"swarmlet": preload("res://assets/starfall/gen/swarmlet.png"),
	"brood": preload("res://assets/starfall/gen/brood.png"),
	"sentinel": preload("res://assets/starfall/gen/sentinel.png"),
	"revenant": preload("res://assets/starfall/gen/revenant.png"),
	"bomber": preload("res://assets/starfall/gen/bomber.png"),
	"frigate": preload("res://assets/starfall/gen/frigate.png"),
	"wraith": preload("res://assets/starfall/gen/wraith.png"),
	"dread": preload("res://assets/starfall/gen/elite_dread.png"),
	"hauler": preload("res://assets/starfall/gen/ally_hauler.png"),
}

# shot: what it fires. flags: cover (stops shots), volatile (explodes), heavy (big hit reactions).
const DB := {
	"rock_l": {"name": "BOULDER", "hp": 6.0, "r": 46.0, "size": 124.0, "art": "rock_l", "hue": 0.0, "score": 40, "drop": 0.35, "fire": 0.0, "shot": "", "lore": "Core-rich rock. It breaks into smaller rocks, so don't stand underneath."},
	"rock_m": {"name": "ROCK", "hp": 3.0, "r": 31.0, "size": 86.0, "art": "rock_m", "hue": 0.0, "score": 20, "drop": 0.2, "fire": 0.0, "shot": "", "lore": "Everything out here used to be part of something bigger."},
	"rock_s": {"name": "PEBBLE", "hp": 1.0, "r": 20.0, "size": 58.0, "art": "rock_s", "hue": 0.0, "score": 10, "drop": 0.1, "fire": 0.0, "shot": "", "lore": "At these speeds, a pebble is a shell."},
	"wreck": {"name": "DRIFTING WRECK", "hp": 14.0, "r": 58.0, "size": 150.0, "art": "wreck_a", "hue": 0.0, "score": 90, "drop": 1.0, "fire": 0.0, "shot": "", "cover": true, "lore": "Old hulls block fire from both sides. Hide behind them, then crack them open for the salvage inside."},
	"fighter": {"name": "SCAV FIGHTER", "hp": 3.0, "r": 34.0, "size": 112.0, "art": "fighter", "hue": 0.0, "score": 50, "drop": 0.3, "fire": 2.7, "shot": "aimed", "lore": "Pirate salvagers. They watch you for a moment before they fire, so watch them back."},
	"raider": {"name": "RAIDER", "hp": 2.0, "r": 28.0, "size": 92.0, "art": "raider", "hue": 0.47, "score": 45, "drop": 0.25, "fire": 0.0, "shot": "", "lore": "No guns, all engine. Raiders pick a line and commit to it."},
	"weaver": {"name": "WEAVER", "hp": 3.0, "r": 32.0, "size": 104.0, "art": "fighter", "hue": 0.40, "score": 60, "drop": 0.3, "fire": 2.3, "shot": "twin", "lore": "Flies in a long snake and drops twin bolts straight down."},
	"mine": {"name": "PROXIMITY MINE", "hp": 3.0, "r": 30.0, "size": 72.0, "art": "mine", "hue": 0.45, "score": 60, "drop": 0.3, "fire": 0.0, "shot": "", "lore": "Bursts when it dies or when you get close. Kill it from far away."},
	"gunship": {"name": "GUNSHIP", "hp": 18.0, "r": 66.0, "size": 212.0, "art": "fighter", "hue": 0.68, "score": 300, "drop": 1.0, "fire": 2.4, "shot": "fan", "heavy": true, "lore": "Holds high and fills the lane with fans of fire."},
	"tank": {"name": "FUEL TANK", "hp": 2.0, "r": 40.0, "size": 110.0, "art": "tank", "hue": 0.0, "score": 30, "drop": 0.3, "fire": 0.0, "shot": "", "volatile": true, "lore": "Unstable. The blast hurts anything nearby, including whoever is flying past. Time your shot."},
	"cinder": {"name": "CINDER", "hp": 2.0, "r": 26.0, "size": 90.0, "art": "cinder", "hue": 0.0, "score": 50, "drop": 0.25, "fire": 0.0, "shot": "", "lore": "A burning hunter. Slow to turn, so sidestep at the last second."},
	"pod": {"name": "BROOD POD", "hp": 3.0, "r": 42.0, "size": 110.0, "art": "pod", "hue": 0.0, "score": 60, "drop": 0.6, "fire": 0.0, "shot": "", "lore": "Hatches into a swarm when its timer runs out. Pop it first and you take the crystals inside."},
	"swarmlet": {"name": "SWARMLET", "hp": 0.8, "r": 18.0, "size": 58.0, "art": "swarmlet", "hue": 0.0, "score": 15, "drop": 0.08, "fire": 0.0, "shot": "", "lore": "Weak alone. They are never alone."},
	"brood": {"name": "BROOD MOTHER", "hp": 16.0, "r": 70.0, "size": 200.0, "art": "brood", "hue": 0.0, "score": 280, "drop": 1.0, "fire": 3.6, "shot": "spawn", "heavy": true, "lore": "A flying nest that keeps birthing swarmlets until you kill it."},
	"sentinel": {"name": "SENTINEL", "hp": 8.0, "r": 50.0, "size": 130.0, "art": "sentinel", "hue": 0.0, "score": 120, "drop": 0.5, "fire": 3.0, "shot": "lance", "lore": "Sat dormant for a century. Its barrel tracks you, then it fires a long aimed burst."},
	"revenant": {"name": "REVENANT", "hp": 4.0, "r": 34.0, "size": 112.0, "art": "revenant", "hue": 0.0, "score": 70, "drop": 0.3, "fire": 2.8, "shot": "aimed", "revive": true, "lore": "Leaves a frozen husk when it falls. Shatter the husk, or it gets back up."},
	"husk": {"name": "FROZEN HUSK", "hp": 2.0, "r": 34.0, "size": 112.0, "art": "revenant", "hue": 0.5, "score": 40, "drop": 0.5, "fire": 0.0, "shot": "", "lore": "A dead ship that isn't finished. One more hit puts it down for good."},
	"bomber": {"name": "BOMBER", "hp": 7.0, "r": 54.0, "size": 150.0, "art": "bomber", "hue": 0.0, "score": 130, "drop": 0.5, "fire": 2.4, "shot": "bomb", "lore": "Crimson fleet heavy. Carpets a lane with slow, wide bombs."},
	"frigate": {"name": "CRIMSON FRIGATE", "hp": 26.0, "r": 76.0, "size": 260.0, "art": "frigate", "hue": 0.0, "score": 400, "drop": 1.0, "fire": 1.5, "shot": "broadside", "heavy": true, "lore": "Crosses the battlefield firing broadsides. It isn't here for you. You're just in the way."},
	"wraith": {"name": "WRAITH", "hp": 5.0, "r": 34.0, "size": 110.0, "art": "wraith", "hue": 0.0, "score": 110, "drop": 0.4, "fire": 2.6, "shot": "aimed", "phase": true, "lore": "Slips out of phase and cannot be hit. Shoot it the moment it turns solid."},
	"elite": {"name": "DREADNOUGHT", "hp": 42.0, "r": 92.0, "size": 290.0, "art": "dread", "hue": 0.0, "score": 800, "drop": 1.0, "fire": 2.1, "shot": "elite", "heavy": true, "lore": "A sector champion. Each one flies with its own modification."},
	"treasure": {"name": "GOLD COURIER", "hp": 9.0, "r": 40.0, "size": 96.0, "art": "fighter", "hue": 0.86, "score": 500, "drop": 1.0, "fire": 0.0, "shot": "", "treasure": true, "lore": "Running from something with a hold full of crystal. Catch it before it jumps away."},
	"ally": {"name": "SALVAGE HAULER", "hp": 40.0, "r": 76.0, "size": 180.0, "art": "hauler", "hue": 0.0, "score": 0, "drop": 0.0, "fire": 0.0, "shot": "", "ally": true, "cover": true, "lore": "Friendly crews trying to get out alive. Keep shots off them and they'll pay you for it."},
}

# Elite modifiers. Each has a shape as well as a colour, so it reads without colour vision.
const MODS := {
	"shielded": {"name": "SHIELDED", "desc": "Blocks hits until its shield breaks", "color": Color(0.4, 0.8, 1.0), "mark": "ring"},
	"swift": {"name": "SWIFT", "desc": "Moves and fires faster", "color": Color(1.0, 0.9, 0.3), "mark": "chevron"},
	"regen": {"name": "REGENERATING", "desc": "Heals when you stop hitting it", "color": Color(0.4, 1.0, 0.6), "mark": "cross"},
	"volatile": {"name": "VOLATILE", "desc": "Explodes into shots when destroyed", "color": Color(1.0, 0.4, 0.3), "mark": "spikes"},
}

const ELITE_ORDER := ["shielded", "swift", "regen", "volatile"]
