class_name Pilot
extends RefCounted
## Account level. Every flight earns XP, there is no level cap, and small permanent bonuses
## keep arriving up to level 100. Even a lost run moves it forward.

const BONUS_CAP := 100

static func need(level: int) -> int:
	return 100 + 25 * level

## {level, into, need}: where an XP total sits.
static func level_of(xp: int) -> Dictionary:
	var level := 1
	var left := xp
	while left >= need(level):
		left -= need(level)
		level += 1
	return {"level": level, "into": left, "need": need(level)}

static func level() -> int:
	return int(level_of(Save.pilot_xp).level)

static func dmg_bonus() -> float:
	return dmg_bonus_at(level())

static func shield_bonus() -> float:
	return shield_bonus_at(level())

## The permanent bonuses at any level. Combat uses these through dmg_bonus() and shield_bonus().
static func dmg_bonus_at(lv: int) -> float:
	return 1.0 + 0.003 * float(mini(lv, BONUS_CAP))

static func shield_bonus_at(lv: int) -> float:
	return 0.5 * float(mini(lv, BONUS_CAP))

# ---------- What a level pays ----------
# reward_for() is the one place these numbers live. grant() pays exactly this, and the profile page previews it.

## What reaching level `lv` pays: salvage, parts, and the rarity of a guaranteed gear drop (-1 for none).
static func reward_for(lv: int) -> Dictionary:
	var gear := -1
	if lv % 5 == 0:
		gear = Gear.EPIC if lv % 10 == 0 else Gear.RARE
	return {"level": lv, "salvage": 20 + 4 * lv, "parts": 5 + lv / 2, "gear": gear}

## How much the permanent bonuses grow on reaching level `lv`. Both stop growing after BONUS_CAP.
static func bonus_gain(lv: int) -> Dictionary:
	return {"dmg": dmg_bonus_at(lv) - dmg_bonus_at(lv - 1), "shield": shield_bonus_at(lv) - shield_bonus_at(lv - 1), "maxed": lv > BONUS_CAP}

## The next level above `after` that pays a guaranteed gear drop, with the rarity it pays.
static func next_gear_level(after: int, from_level := 0) -> Dictionary:
	var lv := maxi(after, from_level) + 1
	while lv % 5 != 0:
		lv += 1
	return {"level": lv, "rarity": int(reward_for(lv).gear)}

## XP needed from the start of level 1 to reach the start of level `lv`.
static func xp_at_level_start(lv: int) -> int:
	var total := 0
	for l in range(1, lv):
		total += need(l)
	return total

## Adds XP and pays out any levels it crosses. Returns rewards and gear for the results screen.
static func grant(xp: int) -> Dictionary:
	var before := level()
	Save.pilot_xp += maxi(0, xp)
	var after := level()
	var out := {"rewards": [], "items": [], "levels": after - before}
	if after <= before:
		return out
	var salvage := 0
	var parts := 0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for lv in range(before + 1, after + 1):
		var pay := reward_for(lv)
		salvage += int(pay.salvage)
		parts += int(pay.parts)
		if int(pay.gear) >= 0:
			var item := Gear.roll_item(rng, 1.0 + float(lv) * 0.5, float(lv) / 12.0, int(pay.gear))
			Save.add_gear(item)
			out.items.append(item)
	Save.salvage += salvage
	Save.parts += parts
	var title := "PILOT LEVEL %d" % after if after - before == 1 else "PILOT LEVEL %d  (+%d)" % [after, after - before]
	out.rewards.append({"title": title, "detail": "+%d salvage  +%d parts" % [salvage, parts]})
	Meta.peak("pilot_level", after)
	return out
