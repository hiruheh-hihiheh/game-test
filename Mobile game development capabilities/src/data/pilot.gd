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
	return 1.0 + 0.003 * float(mini(level(), BONUS_CAP))

static func shield_bonus() -> float:
	return 0.5 * float(mini(level(), BONUS_CAP))

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
		salvage += 20 + 4 * lv
		parts += 5 + lv / 2
		if lv % 5 == 0:
			var item := Gear.roll_item(rng, 1.0 + float(lv) * 0.5, float(lv) / 12.0, Gear.EPIC if lv % 10 == 0 else Gear.RARE)
			Save.add_gear(item)
			out.items.append(item)
	Save.salvage += salvage
	Save.parts += parts
	var title := "PILOT LEVEL %d" % after if after - before == 1 else "PILOT LEVEL %d  (+%d)" % [after, after - before]
	out.rewards.append({"title": title, "detail": "+%d salvage  +%d parts" % [salvage, parts]})
	Meta.peak("pilot_level", after)
	return out
