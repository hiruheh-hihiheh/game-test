class_name Danger
extends RefCounted
## Danger Contracts: optional, player-chosen risks that pay more. They never run on their own,
## never take anything away on a loss, and work in every mode (campaign, boss, Black Box, Rift,
## Expedition elite and boss nodes, daily and weekly). All rules live here, so each screen and the
## game only ask questions of this file.
##
## A contract has one effect on the run (fx) and one payout (reward). A loss pays nothing extra
## and costs nothing extra. Payouts are capped, and two contracts never share a group.

const MAX_PICKS := 2
const UNLOCK_LEVEL := 10          # the first boss must be beaten
const DOUBLE_BONUS := 1.15        # two contracts pay a little more than the sum
const RIFT_MIN_FLOORS := 3        # a Rift run pays its contracts once it has cleared this many floors
# The most one run can ever add. Dials and tiers have their own bonuses on top of these.
const CAPS := {"salvage": 0.6, "parts": 1.0, "xp": 0.6, "luck": 4.0}
const MAX_ROLLS := 2
# Danger never pushes enemy shots past these on its own (a tier or dial that already did is left alone).
const BULLET_CEILING := 2.0
const FIRE_CEILING := 2.6

const GROUPS := {
	"self": "your ship",
	"pressure": "enemy pressure",
	"elite": "elite enemies",
	"pace": "pace",
	"nova": "Nova",
	"cards": "modules",
}

# fx keys: hull_add, bullet, fire, pace, elite (minimum elite chance), nova_off, regen, cards_minus, no_reroll
# reward keys: salvage, parts, xp (fractions added), luck (gear rarity odds), rolls (extra gear drops on a win)
# art is a UIArt key. Several reuse existing illustrations until dedicated art is made.
const LIST := {
	"fragile": {
		"name": "FRAGILE HULL", "group": "self", "heat": 2, "art": "hull",
		"desc": "One less hull, never below 1", "fx": {"hull_add": -1},
		"reward": {"luck": 2.0, "rolls": [{"min": Gear.RARE}]},
		"bad_dials": ["brittle"], "not_modes": ["expedition"],
	},
	"hostiles": {
		"name": "OVERCLOCKED HOSTILES", "group": "pressure", "heat": 2, "art": "rapid",
		"desc": "Enemy shots 15% faster, 20% more often", "fx": {"bullet": 1.15, "fire": 1.2},
		"reward": {"parts": 0.6, "xp": 0.25},
		"bad_dials": ["swift", "frenzy"],
	},
	"elite_signal": {
		"name": "ELITE SIGNAL", "group": "elite", "heat": 2, "art": "ops",
		"desc": "A quarter of enemies are elites", "fx": {"elite": 0.25},
		"reward": {"xp": 0.2, "rolls": [{"min": Gear.RARE, "luck": 2.0, "boss": true}]},
		"bad_dials": ["elites"],
	},
	"rush": {
		"name": "SALVAGE RUSH", "group": "pace", "heat": 1, "art": "salvor",
		"desc": "Waves arrive 30% sooner", "fx": {"pace": 1.3},
		"reward": {"salvage": 0.25},
	},
	"silence": {
		"name": "NOVA SILENCE", "group": "nova", "heat": 3, "art": "core",
		"desc": "Nova Burst is sealed for the whole run", "fx": {"nova_off": true},
		"reward": {"xp": 0.2, "rolls": [{"min": Gear.EPIC, "luck": 1.0}]},
	},
	"cold": {
		"name": "COLD REACTOR", "group": "self", "heat": 1, "art": "shield",
		"desc": "Your shield refills at half speed", "fx": {"regen": 0.5},
		"reward": {"salvage": 0.15, "parts": 0.4},
		"bad_dials": ["noregen"],
	},
	"lean": {
		"name": "LEAN LOADOUT", "group": "cards", "heat": 2, "art": "slot",
		"desc": "One fewer module to pick from, no rerolls", "fx": {"cards_minus": 1, "no_reroll": true},
		"reward": {"xp": 0.3, "rolls": [{"min": Gear.RARE}]},
		"needs_picks": true,
	},
}
const ORDER := ["fragile", "hostiles", "elite_signal", "rush", "silence", "cold", "lean"]

# ---------- Availability ----------

static func has(id: String) -> bool:
	return LIST.has(id)

static func unlocked() -> bool:
	return Save.unlocked > UNLOCK_LEVEL

## Why `id` cannot be added to `chosen` right now, or "" when it can.
## ctx: mode, dials (Array of Dial ids active), picks (how many module picks the run has, -1 if open-ended).
static func blocked_reason(chosen: Array, id: String, ctx: Dictionary) -> String:
	if not LIST.has(id):
		return "Unknown contract"
	var def: Dictionary = LIST[id]
	if id in chosen:
		return ""
	if chosen.size() >= MAX_PICKS:
		return "Pick at most %d contracts" % MAX_PICKS
	for other in chosen:
		if str(LIST[other].group) == str(def.group):
			return "Only one %s contract: %s" % [str(GROUPS[def.group]), str(LIST[other].name)]
	for d in def.get("bad_dials", []):
		if d in ctx.get("dials", []):
			return "Conflicts with the %s dial" % str(Mutators.LIST[d].name)
	if str(ctx.get("mode", "")) in def.get("not_modes", []):
		return "Not offered in %s" % str(ctx.get("mode", "this mode"))
	if bool(def.get("needs_picks", false)):
		var picks := int(ctx.get("picks", -1))
		if picks >= 0 and picks < 2:
			return "This level has no module picks"
	return ""

## Errors in a selection, in plain words. Empty when it is fine.
static func validate(chosen: Array, ctx: Dictionary) -> Array:
	var errors: Array = []
	var built: Array = []
	for id in chosen:
		if id in built:
			errors.append("%s picked twice" % str(id))
			continue
		var why := blocked_reason(built, str(id), ctx)
		if not why.is_empty():
			errors.append("%s: %s" % [str(id), why])
			continue
		built.append(str(id))
	return errors

## The valid part of a selection, in order. Anything unknown, doubled or conflicting is dropped.
static func sanitize(chosen: Array, ctx: Dictionary) -> Array:
	var built: Array = []
	for id in chosen:
		if str(id) in built:
			continue
		if blocked_reason(built, str(id), ctx).is_empty() and LIST.has(str(id)):
			built.append(str(id))
	return built

## The contract that stops a dial being switched on, or "" when there is none.
static func dial_conflict(chosen: Array, dial: String) -> String:
	for id in chosen:
		if dial in LIST[id].get("bad_dials", []):
			return str(LIST[id].name)
	return ""

# ---------- Effects ----------

static func fx_sum(chosen: Array, key: String) -> float:
	var total := 0.0
	for id in chosen:
		if LIST.has(id):
			total += float(LIST[id].fx.get(key, 0.0))
	return total

static func fx_product(chosen: Array, key: String) -> float:
	var total := 1.0
	for id in chosen:
		if LIST.has(id) and LIST[id].fx.has(key):
			total *= float(LIST[id].fx[key])
	return total

static func fx_max(chosen: Array, key: String) -> float:
	var best := 0.0
	for id in chosen:
		if LIST.has(id):
			best = maxf(best, float(LIST[id].fx.get(key, 0.0)))
	return best

static func fx_flag(chosen: Array, key: String) -> bool:
	for id in chosen:
		if LIST.has(id) and bool(LIST[id].fx.get(key, false)):
			return true
	return false

# ---------- Rewards ----------

## What a completed run pays. Two contracts pay 15% more of the percentage rewards, and
## everything is capped. Gear rolls are extra drops on a win: {min, luck, boss}.
static func rewards(chosen: Array) -> Dictionary:
	var out := {"salvage": 0.0, "parts": 0.0, "xp": 0.0, "luck": 0.0, "rolls": []}
	var n := 0
	for id in chosen:
		if not LIST.has(id):
			continue
		n += 1
		var r: Dictionary = LIST[id].reward
		for k in ["salvage", "parts", "xp", "luck"]:
			out[k] = float(out[k]) + float(r.get(k, 0.0))
		for roll in r.get("rolls", []):
			if (out.rolls as Array).size() < MAX_ROLLS:
				(out.rolls as Array).append(roll)
	if n >= 2:
		for k in ["salvage", "parts", "xp"]:
			out[k] = float(out[k]) * DOUBLE_BONUS
	for k in CAPS:
		out[k] = minf(float(out[k]), float(CAPS[k]))
	return out

static func heat(chosen: Array) -> int:
	var total := 0
	for id in chosen:
		if LIST.has(id):
			total += int(LIST[id].heat)
	return total

## Short reward lines for one contract, for its card.
static func reward_lines(id: String) -> Array:
	return _lines(rewards([id]))

## Reward lines for a whole selection, for the launch summary and the results screen.
static func summary_lines(chosen: Array) -> Array:
	return _lines(rewards(chosen))

static func _lines(r: Dictionary) -> Array:
	var out: Array = []
	if float(r.salvage) > 0.0:
		out.append("+%d%% salvage" % int(round(float(r.salvage) * 100.0)))
	if float(r.parts) > 0.0:
		out.append("+%d%% parts" % int(round(float(r.parts) * 100.0)))
	if float(r.xp) > 0.0:
		out.append("+%d%% pilot XP" % int(round(float(r.xp) * 100.0)))
	if float(r.luck) > 0.0:
		out.append("better gear odds")
	for roll in r.rolls:
		var name_: String = Gear.RARITY_NAMES[int(roll.min)]
		out.append(("boss cache: %s+ gear" if bool(roll.get("boss", false)) else "bonus gear: %s+") % name_.capitalize())
	return out

static func names(chosen: Array) -> String:
	var out: Array = []
	for id in chosen:
		if LIST.has(id):
			out.append(str(LIST[id].name))
	return " + ".join(out)

# ---------- Daily and weekly ----------

## The contract a daily or weekly challenge features. The same for every player on that day, and never
## in conflict with the challenge's own dials, so everyone faces identical conditions.
static func featured(seed_value: int, dials: Array, mode: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var start := rng.randi() % ORDER.size()
	for i in range(ORDER.size()):
		var id: String = ORDER[(start + i) % ORDER.size()]
		if blocked_reason([], id, {"mode": mode, "dials": dials, "picks": 2}).is_empty():
			return id
	return ""

# ---------- Progress ----------

static func done_count(id: String) -> int:
	return int((Save.danger.get("done", {}) as Dictionary).get(id, 0))

static func total_done() -> int:
	var total := 0
	for k in (Save.danger.get("done", {}) as Dictionary):
		total += int(Save.danger.done[k])
	return total

## Banks a completed contract run: counts, achievements and the selection to offer again.
static func record_win(chosen: Array, context: String) -> void:
	if chosen.is_empty():
		return
	if not Save.danger.has("done"):
		Save.danger["done"] = {}
	for id in chosen:
		Save.danger.done[id] = done_count(id) + 1
		Meta.unique("danger_unique", id)
	Meta.count("danger_clear")
	if chosen.size() >= 2:
		Meta.count("danger_double")
	remember(chosen, context)

static func remember(chosen: Array, context: String) -> void:
	if not Save.danger.has("last"):
		Save.danger["last"] = {}
	Save.danger.last[context] = chosen.duplicate()
	Save.mark_dirty()

static func recall(context: String) -> Array:
	return ((Save.danger.get("last", {}) as Dictionary).get(context, []) as Array).duplicate()

## Drops anything unknown from a loaded save.
static func repair(d: Dictionary) -> Dictionary:
	var out := {"done": {}, "last": {}}
	for id in (d.get("done", {}) as Dictionary):
		if LIST.has(str(id)):
			out.done[str(id)] = maxi(0, int(d.done[id]))
	for context in (d.get("last", {}) as Dictionary):
		var ids: Array = []
		for id in d.last[context]:
			if LIST.has(str(id)) and not str(id) in ids:
				ids.append(str(id))
		out.last[str(context)] = ids.slice(0, MAX_PICKS)
	return out
