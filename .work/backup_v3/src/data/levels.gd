class_name Levels
extends RefCounted
## The campaign. Every level is written by hand in a small wave language:
##   "kind form count [delay]"   a group, such as "fighter vee 4"
##   "!event amount [delay]"     a set piece, such as "!flare 3"
## Groups in a wave are separated by ";".

const LEVELS_PER_SECTOR := 10
const SECTOR_COUNT := 6
const LEVEL_COUNT := 60
const SIDE_FIRST := 101
const ENDLESS_UNLOCK := 8
const EXPEDITION_UNLOCK := 11

const SECTORS := [
	{"name": "DEBRIS BELT", "tag": "Where every salvager starts", "color": Color(0.25, 0.90, 1.0), "music": "sector_1", "mechanic": "COVER", "mechanic_desc": "Wrecks block shots from both sides. Use them, then break them for salvage.",
		"lore": "A shipping lane until the starfall. Now it is the richest graveyard in known space, and everyone with a cutting torch wants a piece."},
	{"name": "EMBER DRIFT", "tag": "The wreckage is still burning", "color": Color(1.0, 0.58, 0.20), "music": "sector_2", "mechanic": "HEAT", "mechanic_desc": "Ember clouds burn your shield but overcharge Nova. Fuel tanks explode. Vent flares sweep the lanes.",
		"lore": "Fuel from a thousand hulls ignited here and never stopped. Salvagers call it free energy, right up until it isn't."},
	{"name": "VIOLET NURSERY", "tag": "Something is hatching out here", "color": Color(1.0, 0.27, 0.66), "music": "sector_3", "mechanic": "HATCHING", "mechanic_desc": "Pods hatch into swarms when their timer ends. Pop them early for crystals.",
		"lore": "The dust glows because it is alive. Whatever fell with the stars took root, and it has started building nests."},
	{"name": "PALE GRAVEYARD", "tag": "Frozen fleets. Not all of them dead", "color": Color(0.55, 0.95, 0.95), "music": "sector_4", "mechanic": "REVIVAL", "mechanic_desc": "Revenants leave frozen husks. Shatter them or they rise again. Frost slows every shot.",
		"lore": "Two navies fought to the last ship and froze where they fell. Their automated systems were never told the war ended."},
	{"name": "CRIMSON FRONT", "tag": "You have entered a war zone", "color": Color(1.0, 0.27, 0.30), "music": "sector_5", "mechanic": "CROSSFIRE", "mechanic_desc": "Frigates cross the arena firing broadsides. Protect allied haulers for a big payout.",
		"lore": "The Crimson Fleet wants the Core and will burn anyone between them and it. That means you, and every hauler trying to run."},
	{"name": "SUNKEN CORE", "tag": "The source of the starfall", "color": Color(1.0, 0.82, 0.32), "music": "sector_6", "mechanic": "GRAVITY", "mechanic_desc": "Gravity wells bend every shot and drag your ship. Bend their fire back at them.",
		"lore": "Something at the centre pulled the stars down. It is still pulling. Your instruments disagree about which way is up."},
]

# obj is the level's bonus star: [type, amount]. Star 1 is clearing, star 2 is keeping every hull.
const CAMPAIGN := [
	# --- Sector 1: Debris Belt. Teaches movement, then cover. ---
	{"n": "First Light", "obj": ["crystals", 5], "w": ["rocks rain 4", "rocks rain 6"]},
	{"n": "Loose Change", "obj": ["crystals", 9], "w": ["rocks rain 5; fighter line 2", "fighter vee 3; rocks rain 5"]},
	{"n": "Cover Fire", "obj": ["wrecks", 2], "tip": "Wrecks stop enemy shots. Fly behind them, then break them for crystals.", "w": ["wreck drift 2; fighter line 3", "wreck drift 2; fighter vee 4"]},
	{"n": "Rockfall", "obj": ["combo", 12], "w": ["!storm 9; fighter line 2", "fighter column 4; rocks rain 6"]},
	{"n": "The Scrap Baron", "obj": ["time", 60], "elite": true, "w": ["fighter vee 4; rocks rain 4", "elite hold 1 shielded"]},
	{"n": "Scrapyard Run", "obj": ["crystals", 16], "w": ["wreck drift 3; raider dive 3", "!treasure 1; raider pincer 4; fighter line 3"]},
	{"n": "Thread the Needle", "obj": ["shield", 1], "w": ["wreck drift 4; fighter line 4", "weaver sine 4; rocks rain 5", "fighter vee 5; wreck drift 2"]},
	{"n": "Meteor Season", "obj": ["combo", 25], "w": ["!storm 13", "raider dive 5; rocks rain 6", "!storm 8; gunship hold 1"]},
	{"n": "Salvage Rights", "obj": ["wrecks", 4], "w": ["wreck drift 3; gunship hold 1", "wreck drift 3; fighter vee 5; raider pincer 4", "!treasure 1; weaver sine 5"]},
	{"n": "The Gravity Warden", "obj": ["time", 100], "boss": true, "w": ["rocks rain 6; fighter line 3"]},
	# --- Sector 2: Ember Drift. Heat as risk and reward. ---
	{"n": "Burning Lanes", "obj": ["crystals", 12], "tip": "Red bars mark a flare. Move out of the lane before it fires.", "w": ["fighter line 3; !flare 1", "cinder dive 3; !flare 2"]},
	{"n": "Free Energy", "obj": ["ember", 4], "tip": "Ember clouds burn your shield but overcharge Nova. Dip in, get out.", "w": ["!ember 2; fighter vee 4", "!ember 2; weaver sine 4"]},
	{"n": "Handle With Care", "obj": ["tanks", 3], "tip": "Fuel tanks explode. Shoot them when enemies are close.", "w": ["tank drift 3; fighter line 4", "tank drift 3; raider pincer 4"]},
	{"n": "Backdraft", "obj": ["combo", 18], "w": ["cinder dive 4; !flare 2", "tank drift 2; cinder pincer 4; !flare 2"]},
	{"n": "The Foreman", "obj": ["time", 65], "elite": true, "w": ["tank drift 3; weaver sine 4", "elite hold 1 swift; !ember 2"]},
	{"n": "Chain Reaction", "obj": ["tanks", 5], "w": ["tank drift 4; fighter vee 5", "tank drift 3; gunship hold 1", "!treasure 1; cinder dive 5"]},
	{"n": "Solar Wind", "obj": ["ember", 7], "w": ["!ember 3; raider dive 4; !flare 2", "!row 2; fighter vee 5", "!ember 2; !flare 3; weaver sine 5"]},
	{"n": "Slag Run", "obj": ["shield", 1], "w": ["cinder pincer 5; tank drift 2", "gunship hold 1; !flare 2", "cinder dive 6; !row 2"]},
	{"n": "Heatstroke", "obj": ["combo", 30], "w": ["!storm 8; !flare 2", "raider pincer 6; tank drift 3", "gunship hold 2; !ember 2"]},
	{"n": "The Ember Tyrant", "obj": ["time", 110], "boss": true, "w": ["cinder dive 4; tank drift 2"]},
	# --- Sector 3: Violet Nursery. Priority targets and swarms. ---
	{"n": "Soft Tissue", "obj": ["nohatch", 1], "tip": "Pods hatch when their ring closes. Pop them first for crystals.", "w": ["pod scatter 2; fighter line 3", "pod scatter 3; weaver sine 4"]},
	{"n": "Swarm Season", "obj": ["combo", 25], "w": ["swarm swarm 8; weaver sine 4", "pod scatter 3; swarm swarm 8"]},
	{"n": "Nest Mother", "obj": ["time", 55], "tip": "Brood Mothers birth swarmlets until you kill them. Focus them down.", "w": ["brood hold 1; fighter line 3", "pod scatter 3; raider dive 4"]},
	{"n": "Spawning Ground", "obj": ["nohatch", 1], "w": ["pod scatter 4; mine scatter 2", "swarm swarm 10; pod scatter 3"]},
	{"n": "The Matriarch", "obj": ["time", 70], "elite": true, "w": ["pod scatter 3; weaver sine 5", "elite hold 1 regen; swarm swarm 8"]},
	{"n": "Minefield Garden", "obj": ["nohatch", 1], "w": ["mine scatter 4; pod scatter 3", "!treasure 1; weaver sine 6; mine scatter 3", "brood hold 1; mine scatter 2"]},
	{"n": "Overgrowth", "obj": ["crystals", 26], "w": ["brood hold 1; pod scatter 2", "brood hold 2", "swarm swarm 12; pod scatter 4"]},
	{"n": "Pollen Storm", "obj": ["shield", 1], "w": ["!storm 8; swarm swarm 8", "weaver sine 6; pod scatter 4", "mine scatter 4; raider pincer 6"]},
	{"n": "Hatchery", "obj": ["combo", 45], "w": ["pod scatter 5; swarm swarm 10", "brood hold 2; pod scatter 3", "swarm swarm 14; gunship hold 1"]},
	{"n": "The Orbital Hydra", "obj": ["time", 120], "boss": true, "w": ["pod scatter 3; swarm swarm 8"]},
	# --- Sector 4: Pale Graveyard. Finish what you start. ---
	{"n": "Do Not Disturb", "obj": ["husks", 2], "tip": "Revenants leave a frozen husk. Shatter it or they get back up.", "w": ["revenant line 3", "revenant vee 4; rocks rain 4"]},
	{"n": "Deep Freeze", "obj": ["crystals", 14], "tip": "Frost slows every shot inside it, yours and theirs.", "w": ["!frost 2; fighter vee 4", "!frost 2; revenant line 4"]},
	{"n": "Standing Watch", "obj": ["shield", 1], "tip": "Sentinels aim long bursts. When the barrel flashes, move.", "w": ["sentinel hold 2; wreck drift 2", "sentinel hold 2; revenant line 3"]},
	{"n": "Graveshift", "obj": ["husks", 5], "w": ["revenant column 5; !frost 1", "sentinel hold 2; revenant vee 5"]},
	{"n": "The Quartermaster", "obj": ["time", 75], "elite": true, "w": ["sentinel hold 2; weaver sine 5", "elite hold 1 volatile; revenant line 3"]},
	{"n": "Ice Shelf", "obj": ["crystals", 26], "w": ["wreck drift 4; sentinel hold 2", "!frost 3; gunship hold 1", "!treasure 1; revenant vee 5; wreck drift 2"]},
	{"n": "They Keep Coming", "obj": ["husks", 9], "w": ["revenant line 5", "revenant vee 6; raider dive 4", "revenant column 6; revenant line 4"]},
	{"n": "Cold Open", "obj": ["combo", 35], "w": ["!ambush raider 6; !frost 2", "gunship hold 2; revenant line 4", "!ambush fighter 6; sentinel hold 2"]},
	{"n": "Dead Calm", "obj": ["shield", 1], "w": ["sentinel hold 3; !frost 2", "gunship hold 1; sentinel hold 2", "revenant vee 6; mine scatter 4"]},
	{"n": "The Pale Regent", "obj": ["time", 120], "boss": true, "w": ["revenant vee 4; sentinel hold 1"]},
	# --- Sector 5: Crimson Front. A war you are caught inside. ---
	{"n": "Wrong Neighbourhood", "obj": ["combo", 25], "tip": "Red bars across the screen are broadsides. Dodge up or down.", "w": ["bomber line 2; raider dive 4", "!row 2; fighter vee 5; raider pincer 4"]},
	{"n": "Evacuation", "obj": ["escort", 1], "tip": "Keep the hauler alive. It blocks shots, and each hit costs it dearly.", "w": ["!escort 1; fighter vee 5; raider dive 4", "bomber line 2; fighter line 4"]},
	{"n": "Crossing Fire", "obj": ["shield", 1], "tip": "Frigates cross the arena. Stay out of their firing lanes.", "w": ["frigate side 1; raider dive 4", "frigate side 1; bomber line 2"]},
	{"n": "Carpet Bombing", "obj": ["crystals", 22], "w": ["bomber vee 3; raider pincer 5", "bomber line 3; !row 2", "!treasure 1; bomber vee 4"]},
	{"n": "Commodore Vex", "obj": ["time", 75], "elite": true, "w": ["frigate side 1; fighter vee 5", "elite hold 2 shielded"]},
	{"n": "Last Convoy", "obj": ["escort", 1], "w": ["!escort 1; raider pincer 6; bomber line 2", "fighter vee 6; gunship hold 1", "raider dive 6; bomber line 2"]},
	{"n": "Broadside", "obj": ["combo", 45], "w": ["frigate side 2; raider dive 4", "!row 3; bomber vee 3", "frigate side 2; gunship hold 1"]},
	{"n": "No Man's Sky", "obj": ["shield", 1], "w": ["!ambush raider 8; bomber line 2", "gunship hold 2; frigate side 1", "!row 3; fighter vee 6; mine scatter 3"]},
	{"n": "Fall Back", "obj": ["escort", 1], "w": ["!escort 1; frigate side 1; raider dive 5", "bomber vee 4; gunship hold 1", "frigate side 2; weaver sine 6"]},
	{"n": "The Crimson Admiral", "obj": ["time", 130], "boss": true, "w": ["bomber line 2; raider dive 4"]},
	# --- Sector 6: Sunken Core. Everything you learned, under strange gravity. ---
	{"n": "Downhill", "obj": ["crystals", 20], "tip": "Gravity wells bend every shot and pull your ship. Stay on the outside of the curve.", "w": ["!well 1; fighter vee 5", "!well 1; weaver sine 5"]},
	{"n": "Phase Shift", "obj": ["combo", 30], "tip": "Wraiths can only be hit while they are solid.", "w": ["wraith line 3; raider dive 4", "wraith vee 4; !well 1"]},
	{"n": "Event Horizon", "obj": ["shield", 1], "w": ["!well 2; wraith line 3", "!spokes 1; fighter vee 5", "!well 1; gunship hold 1"]},
	{"n": "The Long Way Down", "obj": ["crystals", 34], "w": ["!spokes 1; rocks rain 8", "wraith vee 5; mine scatter 3", "!treasure 1; !well 2; raider pincer 6"]},
	{"n": "The Herald", "obj": ["time", 80], "elite": true, "w": ["wraith vee 5; !well 1", "elite hold 2 regen; !spokes 1"]},
	{"n": "Every Fleet", "obj": ["combo", 50], "w": ["brood hold 1; frigate side 1", "sentinel hold 2; revenant vee 5", "gunship hold 2; cinder pincer 5"]},
	{"n": "Inversion", "obj": ["shield", 1], "w": ["!well 2; !spokes 1", "wraith vee 6; !well 1", "!row 3; !flare 3; gunship hold 1"]},
	{"n": "Terminal Velocity", "obj": ["time", 80], "w": ["!storm 10; !well 1", "raider pincer 8; wraith line 4", "frigate side 2; !spokes 1"]},
	{"n": "The Last Lock", "obj": ["combo", 60], "w": ["elite hold 1 swift; wraith line 4", "elite hold 1 volatile; !well 1", "gunship hold 2; !spokes 1; revenant vee 5"]},
	{"n": "The Sunken Core", "obj": ["time", 150], "boss": true, "w": ["wraith vee 4; !well 1"]},
]

# Side missions branch off the map after a sector's elite. Hard rules, a blueprint for the win.
const SIDE := {
	101: {"n": "Black Box: Dead Reckoning", "sector": 1, "reward": "bp_seeker", "mutators": ["brittle"], "w": ["wreck drift 3; rocks rain 6", "fighter vee 5; wreck drift 2"], "obj": ["crystals", 12]},
	102: {"n": "Black Box: Controlled Burn", "sector": 2, "reward": "bp_burn", "mutators": ["noregen"], "w": ["tank drift 4; fighter vee 5", "!ember 2; !flare 3; cinder dive 5"], "obj": ["tanks", 4]},
	103: {"n": "Black Box: Sample Return", "sector": 3, "reward": "bp_arc", "mutators": ["swarm"], "w": ["pod scatter 4; swarm swarm 10", "brood hold 2; pod scatter 3"], "obj": ["nohatch", 1]},
	104: {"n": "Black Box: Cold Storage", "sector": 4, "reward": "bp_cryo", "mutators": ["frenzy"], "w": ["revenant vee 5; sentinel hold 2", "!frost 3; revenant column 6"], "obj": ["husks", 5]},
	105: {"n": "Black Box: Mutiny", "sector": 5, "reward": "bp_spike", "mutators": ["elites"], "w": ["bomber vee 3; raider pincer 6", "!escort 1; frigate side 1; fighter vee 5"], "obj": ["escort", 1]},
	106: {"n": "Black Box: Null Point", "sector": 6, "reward": "bp_phoenix", "mutators": ["blackout"], "w": ["wraith vee 5; !well 2", "!spokes 1; gunship hold 2"], "obj": ["shield", 1]},
}

# What each boss hands over the first time it falls.
const BOSS_REWARDS := {
	1: {"blueprints": ["bp_interceptor"], "cards": []},
	2: {"blueprints": ["bp_lancer", "bp_singularity"], "cards": []},
	3: {"blueprints": ["bp_warden", "bp_echo"], "cards": []},
	4: {"blueprints": ["bp_magpie", "bp_overdrive"], "cards": []},
	5: {"blueprints": ["bp_aegis"], "cards": []},
	6: {"blueprints": ["paint_core"], "cards": []},
}

const BLUEPRINT_NAMES := {
	"bp_interceptor": "INTERCEPTOR ship", "bp_lancer": "LANCER ship", "bp_warden": "WARDEN ship", "bp_magpie": "MAGPIE ship",
	"bp_singularity": "SINGULARITY Nova", "bp_overdrive": "OVERDRIVE Nova", "bp_aegis": "AEGIS Nova",
	"bp_seeker": "SEEKER PODS module", "bp_burn": "INCENDIARY module", "bp_arc": "CHAIN ARC module", "bp_cryo": "CRYO ROUNDS module",
	"bp_spike": "REACTIVE SHIELD module", "bp_phoenix": "SECOND WIND module", "bp_echo": "NOVA ECHO module", "paint_core": "CORE GOLD paint",
}

const POOLS := [
	{"rocks": 6.0, "fighter": 3.0, "wreck": 1.5, "raider": 1.5},
	{"fighter": 4.0, "cinder": 3.0, "tank": 2.5, "raider": 2.0, "weaver": 1.5},
	{"weaver": 3.0, "pod": 3.0, "swarm": 3.0, "mine": 2.0, "fighter": 1.5},
	{"revenant": 4.0, "sentinel": 2.0, "gunship": 1.0, "rocks": 2.0, "fighter": 2.0},
	{"raider": 4.0, "bomber": 2.5, "gunship": 1.2, "fighter": 2.0, "frigate": 0.8},
	{"wraith": 3.0, "raider": 2.0, "gunship": 1.2, "revenant": 1.5, "weaver": 2.0, "mine": 1.5},
]

const GROUPS := {
	"rocks": {"min": 5, "max": 8, "cost": 1.0, "forms": ["rain"]},
	"wreck": {"min": 2, "max": 3, "cost": 1.5, "forms": ["drift"]},
	"fighter": {"min": 3, "max": 6, "cost": 1.6, "forms": ["line", "vee", "column"]},
	"raider": {"min": 3, "max": 6, "cost": 1.3, "forms": ["pincer", "dive"]},
	"weaver": {"min": 4, "max": 7, "cost": 1.6, "forms": ["sine"]},
	"mine": {"min": 2, "max": 4, "cost": 2.2, "forms": ["scatter"]},
	"gunship": {"min": 1, "max": 1, "cost": 7.0, "forms": ["hold"]},
	"cinder": {"min": 3, "max": 5, "cost": 1.5, "forms": ["dive", "pincer"]},
	"tank": {"min": 2, "max": 4, "cost": 1.2, "forms": ["drift"]},
	"pod": {"min": 2, "max": 4, "cost": 2.0, "forms": ["scatter"]},
	"swarm": {"min": 8, "max": 12, "cost": 0.5, "forms": ["swarm"]},
	"revenant": {"min": 3, "max": 6, "cost": 2.0, "forms": ["line", "vee", "column"]},
	"sentinel": {"min": 2, "max": 2, "cost": 3.0, "forms": ["hold"]},
	"bomber": {"min": 2, "max": 3, "cost": 3.0, "forms": ["line", "vee"]},
	"frigate": {"min": 1, "max": 1, "cost": 8.0, "forms": ["side"]},
	"wraith": {"min": 3, "max": 5, "cost": 2.2, "forms": ["line", "vee"]},
}

const OBJECTIVE_TEXT := {
	"crystals": "Collect %d crystals",
	"combo": "Reach a combo of %d",
	"time": "Finish within %d seconds",
	"wrecks": "Break %d wrecks",
	"ember": "Absorb %d seconds of ember",
	"tanks": "Blow up %d fuel tanks",
	"nohatch": "Let no pods hatch",
	"husks": "Shatter %d husks",
	"shield": "Never let your shield hit zero",
	"escort": "Keep the hauler above half health",
}

static func sector_of(level: int) -> int:
	if level >= SIDE_FIRST:
		return int(SIDE[level].sector)
	return clampi((level - 1) / LEVELS_PER_SECTOR + 1, 1, SECTOR_COUNT)

static func index_of(level: int) -> int:
	return (level - 1) % LEVELS_PER_SECTOR + 1

static func is_boss(level: int) -> bool:
	return level <= LEVEL_COUNT and bool(CAMPAIGN[level - 1].get("boss", false))

static func is_elite(level: int) -> bool:
	return level <= LEVEL_COUNT and bool(CAMPAIGN[level - 1].get("elite", false))

static func sector(level: int) -> Dictionary:
	return SECTORS[sector_of(level) - 1]

static func level_name(level: int) -> String:
	if level >= SIDE_FIRST:
		return str(SIDE[level].n)
	return str(CAMPAIGN[level - 1].n)

static func objective_text(obj: Array) -> String:
	if obj.is_empty():
		return ""
	var text: String = OBJECTIVE_TEXT[obj[0]]
	return text % int(obj[1]) if "%d" in text else text

static func difficulty(level: int) -> Dictionary:
	var d := float(level - 1) / float(LEVEL_COUNT - 1)
	return {"d": d, "hp": 1.0 + d * 3.6, "speed": 1.0 + d * 0.45, "fire": 1.0 + d * 1.3, "bullet": 1.0 + d * 0.5}

## Parses "fighter vee 4 2.5; !flare 2" into spawn groups.
static func parse_wave(text: String) -> Array:
	var groups: Array = []
	for raw in text.split(";"):
		var parts: PackedStringArray = raw.strip_edges().split(" ", false)
		if parts.is_empty():
			continue
		if parts[0].begins_with("!"):
			var ev := parts[0].substr(1)
			var g := {"event": ev, "delay": 2.2}
			if ev == "ambush":
				g["kind"] = parts[1]
				g["count"] = int(parts[2])
			else:
				g["amount"] = float(parts[1])
				if ev == "storm":
					g["delay"] = float(parts[1]) + 0.6
			groups.append(g)
			continue
		var g := {"kind": parts[0], "form": parts[1], "count": int(parts[2]), "delay": 2.6, "mod": ""}
		if parts.size() > 3:
			if parts[3].is_valid_float():
				g["delay"] = float(parts[3])
			else:
				g["mod"] = parts[3]
		g["delay"] = float(g.delay) + float(g.count) * 0.1
		groups.append(g)
	return groups

static func build(level: int) -> Dictionary:
	var def: Dictionary = SIDE[level] if level >= SIDE_FIRST else CAMPAIGN[level - 1]
	var s := sector_of(level)
	var scale_level := level if level <= LEVEL_COUNT else (s - 1) * LEVELS_PER_SECTOR + 6
	var waves: Array = []
	for text in def.w:
		waves.append(parse_wave(text))
	return {
		"level": level, "name": def.n, "sector": s, "boss": def.get("boss", false), "elite": def.get("elite", false),
		"waves": waves, "scale": difficulty(scale_level), "boss_id": s if def.get("boss", false) else 0,
		"reward": 18 + level * 2 if level <= LEVEL_COUNT else 120, "obj": def.obj, "tip": def.get("tip", ""),
		"mutators": def.get("mutators", []), "side_reward": def.get("reward", ""),
	}

## Procedural waves, used by Endless and Expedition.
static func make_wave(rng: RandomNumberGenerator, budget: float, sector_num: int, d: float, allow_heavy := true) -> Array:
	var pool: Dictionary = POOLS[sector_num - 1].duplicate()
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
		groups.append({"kind": kind, "form": form, "count": count, "delay": lerpf(3.0, 2.0, d) + float(count) * 0.1, "mod": ""})
		left -= float(count) * float(info.cost)
		if kind in ["gunship", "frigate"] or not allow_heavy:
			pool.erase("gunship")
			pool.erase("frigate")
	return groups

static func add_sector_event(groups: Array, rng: RandomNumberGenerator, sector_num: int) -> void:
	var events: Array = [["storm", 8.0], ["flare", 2.0], ["ember", 2.0], ["frost", 2.0], ["row", 2.0], ["well", 1.0]]
	var pick: Array = events[sector_num - 1] if rng.randf() < 0.75 else events[rng.randi() % 6]
	groups.insert(rng.randi() % (groups.size() + 1), {"event": pick[0], "amount": pick[1], "delay": 2.2})

static func build_endless(wave: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * wave + 7
	var s := (wave - 1) / 5 % SECTOR_COUNT + 1
	var diff := difficulty(mini(wave * 2, LEVEL_COUNT))
	diff.hp = float(diff.hp) * (1.0 + maxf(0.0, float(wave - 30)) * 0.05)
	var boss := wave % 5 == 0
	var groups: Array = []
	if not boss:
		groups = make_wave(rng, 8.0 + float(wave) * 0.8, s, float(diff.d))
		if wave > 2:
			add_sector_event(groups, rng, s)
	return {"level": mini(wave * 2, LEVEL_COUNT), "name": "Endless", "sector": s, "boss": boss, "elite": false, "waves": [groups], "scale": diff, "boss_id": s if boss else 0, "reward": 8 + wave * 3, "obj": [], "tip": "", "mutators": [], "side_reward": ""}

## A single Expedition node. tier grows with each layer of the run.
static func build_node(seed_value: int, sector_num: int, tier: int, node_type: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var scale_level := clampi((sector_num - 1) * LEVELS_PER_SECTOR + 2 + tier, 1, LEVEL_COUNT)
	var diff := difficulty(scale_level)
	var waves: Array = []
	var boss := node_type == "boss"
	for w in range(1 if boss else 2):
		var groups := make_wave(rng, 7.0 + float(tier) * 1.2 + float(sector_num) * 1.6, sector_num, float(diff.d))
		add_sector_event(groups, rng, sector_num)
		waves.append(groups)
	var elite := node_type == "elite"
	if elite:
		var mods: Array = Enemies.ELITE_ORDER
		waves[-1].append({"kind": "elite", "form": "hold", "count": 1, "delay": 3.0, "mod": mods[rng.randi() % mods.size()]})
	return {"level": scale_level, "name": node_type.capitalize(), "sector": sector_num, "boss": boss, "elite": elite, "waves": waves, "scale": diff, "boss_id": sector_num if boss else 0, "reward": 16 + tier * 6 + sector_num * 6, "obj": [], "tip": "", "mutators": [], "side_reward": ""}

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
