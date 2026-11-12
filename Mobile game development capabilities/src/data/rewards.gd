class_name Rewards
extends RefCounted
## Two reasons to come back and to replay: the Daily Supply (a seven-day streak) and the Star Vault (a reward every ten
## stars). Nothing here can be bought and nothing expires: a missed day only restarts the week at day 1.
##
## State lives in Save.stats so old saves need no migration: "streak_day" (the day of the last claim), "streak_count"
## (claims in a row) and "star_vault" (how many vault tiers have been claimed).

## Day 1 to 7, then round again. `gear` is a guaranteed rarity.
const STREAK := [
	{"salvage": 40}, {"parts": 8}, {"salvage": 70}, {"token": 1}, {"parts": 15}, {"salvage": 120}, {"salvage": 60, "gear": Gear.EPIC},
]
const VAULT_STEP := 10

# ---------- Shared ----------

## Pays a reward and returns what was paid as text, for a toast. `items` collects any gear that dropped.
static func pay(r: Dictionary, power: float, items: Array = []) -> String:
	var parts: Array = []
	if r.has("salvage"):
		Save.salvage += int(r.salvage)
		parts.append("+%d salvage" % int(r.salvage))
	if r.has("parts"):
		Save.parts += int(r.parts)
		parts.append("+%d parts" % int(r.parts))
	if r.has("token"):
		Save.reroll_tokens += int(r.token)
		parts.append("+%d reroll token" % int(r.token))
	if r.has("gear"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var item := Gear.roll_item(rng, power, 0.5, int(r.gear))
		Save.add_gear(item)
		items.append(item)
		parts.append("%s gear" % str(Gear.RARITY_NAMES[int(item.rarity)]).capitalize())
	return "  ".join(parts)

static func describe(r: Dictionary) -> String:
	var parts: Array = []
	if r.has("salvage"):
		parts.append("%d salvage" % int(r.salvage))
	if r.has("parts"):
		parts.append("%d parts" % int(r.parts))
	if r.has("token"):
		parts.append("%d reroll token" % int(r.token))
	if r.has("gear"):
		parts.append("%s gear" % str(Gear.RARITY_NAMES[int(r.gear)]).capitalize())
	return " + ".join(parts)

## Gear from these rewards is as strong as the furthest level the player has reached.
static func gear_power() -> float:
	return 1.0 + float(Save.unlocked) * 0.45

# ---------- Daily Supply ----------

## {"ready": can claim today, "day": which day of the week the next claim is (1..7), "count": claims in a row so far}
static func streak() -> Dictionary:
	var today: int = Meta.today()
	var last := int(Save.stats.get("streak_day", -1))
	var count := int(Save.stats.get("streak_count", 0))
	if last == today:
		return {"ready": false, "day": (count - 1) % STREAK.size() + 1, "count": count}
	if last != today - 1:
		count = 0
	return {"ready": true, "day": count % STREAK.size() + 1, "count": count}

static func claim_streak(items: Array = []) -> String:
	var st := streak()
	if not bool(st.ready):
		return ""
	var count := int(st.count) + 1
	Save.stats["streak_day"] = Meta.today()
	Save.stats["streak_count"] = count
	Meta.peak("streak_best", count)
	var text := pay(STREAK[int(st.day) - 1], gear_power(), items)
	Save.save_data()
	return text

# ---------- Star Vault ----------

static func vault_tiers() -> int:
	return Levels.LEVEL_COUNT * 3 / VAULT_STEP

## What tier `tier` (1-based) pays. Every third tier adds a guaranteed gear drop, and the last is Legendary.
static func vault_reward(tier: int) -> Dictionary:
	var r := {"salvage": 30 + 10 * tier, "parts": 4 + tier}
	if tier == vault_tiers():
		r["gear"] = Gear.LEGENDARY
	elif tier % 3 == 0:
		r["gear"] = Gear.EPIC if tier >= 9 else Gear.RARE
	return r

static func vault_claimed() -> int:
	return clampi(int(Save.stats.get("star_vault", 0)), 0, vault_tiers())

## How many tiers are earned and not yet claimed.
static func vault_ready() -> int:
	return clampi(Save.total_stars() / VAULT_STEP, 0, vault_tiers()) - vault_claimed()

## Claims the next earned tier. Returns "" when there is none.
static func claim_vault(items: Array = []) -> String:
	if vault_ready() <= 0:
		return ""
	var tier := vault_claimed() + 1
	Save.stats["star_vault"] = tier
	var text := pay(vault_reward(tier), gear_power(), items)
	Save.save_data()
	return text

## Everything waiting to be collected, for the badge on the title screen.
static func waiting() -> int:
	return (1 if bool(streak().ready) else 0) + maxi(0, vault_ready())
