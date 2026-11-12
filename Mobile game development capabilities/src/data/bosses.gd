class_name Bosses
extends RefCounted
## Boss identity. Behaviour lives in src/combat/bosses, personality lives here.

const LIST := [
	{"name": "THE GRAVITY WARDEN", "epithet": "Keeper of the Belt", "hp": 100.0, "hue": 0.0, "half_width": 300.0,
		"taunt": "Nothing leaves my orbit.", "tip": "Shots stop at the boulders. Break them or use the gaps.",
		"stage_lines": ["The pull is getting stronger", "It is tearing itself apart"],
		"death_title": "ORBIT BROKEN", "death_line": "The Belt is free",
		"lore": "A mining station that survived the starfall by swallowing everything near it. Its builders are somewhere inside the ring."},
	{"name": "THE EMBER TYRANT", "epithet": "Foreman of the Drift", "hp": 200.0, "hue": 0.0, "half_width": 240.0,
		"taunt": "Burn clean, little scavenger.", "tip": "Its armour is thick. Dodge the flames, then hit the open vents.",
		"stage_lines": ["The furnace is running hot", "Meltdown imminent"],
		"death_title": "FURNACE COLD", "death_line": "The fires finally go out",
		"lore": "A forge ship that never stopped working. It reclaims every wreck in the Drift and melts it down to make more of itself."},
	{"name": "THE ORBITAL HYDRA", "epithet": "Mother of the Nursery", "hp": 300.0, "hue": 0.0, "half_width": 180.0,
		"taunt": "Feed. Grow. Feed.", "tip": "Sever the heads. The heart stays sealed until they fall.",
		"stage_lines": ["One head down", "Only the heart remains"],
		"death_title": "THE NEST FALLS", "death_line": "Nothing else hatches today",
		"lore": "The first thing that fell with the stars and lived. Everything in the Nursery is a part of it, or a meal."},
	{"name": "THE PALE REGENT", "epithet": "Sovereign of the Dead Fleet", "hp": 430.0, "hue": 0.0, "half_width": 240.0,
		"taunt": "Kneel with the others.", "tip": "Later it casts false images. Only the real crown has a gold ring.",
		"stage_lines": ["Which one is real?", "The dead answer its call"],
		"death_title": "THE CROWN SHATTERS", "death_line": "The fleet can finally sleep",
		"lore": "The last flagship froze with its command AI still running. It has held a coronation for itself every day for a century."},
	{"name": "THE CRIMSON ADMIRAL", "epithet": "Scourge of the Front", "hp": 520.0, "hue": 0.0, "half_width": 200.0,
		"taunt": "You are out of your depth, salvager.", "tip": "Destroy two turrets to expose the bridge.",
		"stage_lines": ["All hands, battle stations", "Ramming speed"],
		"death_title": "FLAGSHIP DOWN", "death_line": "The Crimson Fleet breaks",
		"lore": "Admiral Sarn wants the Core for the fleet. Having burned half the sector to reach it, the fleet can no longer say what for."},
	{"name": "THE SUNKEN CORE", "epithet": "Source of the Starfall", "hp": 760.0, "hue": 0.0, "half_width": 320.0,
		"taunt": "COME CLOSER.", "tip": "Armour rings block your shots. Fire through the moving gaps.",
		"stage_lines": ["The rings are accelerating", "Everything is falling inward"],
		"death_title": "THE STARS ARE FREE", "death_line": "It is finally over",
		"lore": "It isn't a planet or a ship. It reached up and pulled the stars down, and nobody knows what it wanted them for."},
	# --- Rift Lords: met only in the Rift (every 15th floor) and in Boss Rush ---
	{"name": "THE TWIN ECLIPSE", "epithet": "Rift Lord", "hp": 480.0, "hue": 0.0, "half_width": 260.0,
		"taunt": "One of us is always watching.", "tip": "Only the bright twin can be hurt. They trade places.",
		"stage_lines": ["The orbit tightens", "Total eclipse"],
		"death_title": "ECLIPSE BROKEN", "death_line": "Both lights go out together",
		"lore": "A binary star that the Rift taught to hunt. The sun burns, the moon shields, and neither has ever been seen alone."},
	{"name": "THE VOID LANCER", "epithet": "Rift Lord", "hp": 560.0, "hue": 0.0, "half_width": 150.0,
		"taunt": "Run. I like it when they run.", "tip": "Its guard plate drops only while it attacks. Stay under it and shoot back.",
		"stage_lines": ["It has your scent", "No more warning shots"],
		"death_title": "HUNT ENDED", "death_line": "The Rift loses its hunter",
		"lore": "Nobody built it for the Rift. It followed something in, a long time ago, and has been following things ever since."},
]
## The bosses of the six sectors come first in LIST; the Rift Lords follow.
const SECTOR_BOSSES := 6
## Boss Rush fights every boss in this order.
const RUSH_ORDER := [1, 2, 3, 7, 4, 5, 8, 6]
## Boss Rush opens once this many sector bosses have fallen.
const RUSH_UNLOCK := 3
