extends Node
## Long-term progress. Autoloaded as "Meta".
## Combat reports what happened through count(); this decides what that earns.

signal unlocked_goal(title: String, detail: String)

const SECONDS_PER_DAY := 86400

func _ready() -> void:
	refresh_contracts()

func today() -> int:
	var now := int(Time.get_unix_time_from_system()) + int(Time.get_time_zone_from_system().bias) * 60
	return now / SECONDS_PER_DAY

func week() -> int:
	# Weeks roll over on Monday.
	return (today() + 3) / 7

func seconds_to_reset() -> int:
	var now := int(Time.get_unix_time_from_system()) + int(Time.get_time_zone_from_system().bias) * 60
	return SECONDS_PER_DAY - now % SECONDS_PER_DAY

func stat(key: String) -> int:
	return int(Save.stats.get(key, 0))

## Adds to a lifetime stat and to any contract watching it.
func count(key: String, amount := 1) -> void:
	Save.stats[key] = stat(key) + amount
	var list: Array = Save.contracts.get("list", [])
	for c in list:
		if str(c.stat) == key and not c.done:
			c.progress = int(c.progress) + amount
			if int(c.progress) >= int(c.goal):
				c.done = true
				unlocked_goal.emit("CONTRACT COMPLETE", "Collect your reward in Ops")
	_check_achievements(key)
	Save.mark_dirty()

## Records a high-water mark rather than a running total.
func peak(key: String, value: int) -> void:
	if value > stat(key):
		Save.stats[key] = value
		_check_achievements(key)
		Save.mark_dirty()

func unique(key: String, item: Variant) -> void:
	var seen_key := "seen_" + key
	var seen: Array = Save.stats.get(seen_key, [])
	if item in seen:
		return
	seen.append(item)
	Save.stats[seen_key] = seen
	peak(key, seen.size())

func _check_achievements(key: String) -> void:
	for a in Goals.ACHIEVEMENTS:
		if str(a.stat) == key and not Save.achievements.has(a.id) and stat(key) >= int(a.goal):
			Save.achievements[a.id] = today()
			Save.salvage += int(a.reward)
			Audio.play("unlock")
			unlocked_goal.emit(str(a.name), "+%d salvage" % int(a.reward))
			Telemetry.log_event("achievement", {"id": a.id})

func sync_collection_stats() -> void:
	peak("ships_owned", Save.owned_ships.size())
	peak("stars", Save.total_stars())
	peak("side", Save.side_cleared.size())
	var best := 1
	for id in Ships.ORDER:
		best = maxi(best, Save.ship_mastery(id))
	peak("best_mastery", best)

func discover(id: String) -> bool:
	if Save.codex.has(id):
		return false
	Save.codex[id] = true
	Save.mark_dirty()
	return true

# --- Contracts ---

func refresh_contracts() -> void:
	var day := today()
	if int(Save.contracts.get("day", -1)) == day:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 31 + 11
	var pool: Array = Goals.CONTRACTS.duplicate()
	var list: Array = []
	for i in range(3):
		var pick: Dictionary = pool[rng.randi() % pool.size()]
		pool.erase(pick)
		list.append({"id": pick.id, "text": pick.text % int(pick.goal), "stat": pick.stat, "goal": pick.goal, "reward": pick.reward, "progress": 0, "done": false, "claimed": false})
	Save.contracts = {"day": day, "list": list, "reroll": 1}
	Save.mark_dirty()

func claimable_contracts() -> int:
	var n := 0
	for c in Save.contracts.get("list", []):
		if c.done and not c.claimed:
			n += 1
	return n

func claim_contract(index: int) -> bool:
	var list: Array = Save.contracts.get("list", [])
	if index >= list.size():
		return false
	var c: Dictionary = list[index]
	if not c.done or c.claimed:
		return false
	c.claimed = true
	Save.salvage += int(c.reward)
	var all_done := true
	for other in list:
		if not other.claimed:
			all_done = false
	if all_done:
		Save.reroll_tokens += 1
		unlocked_goal.emit("ALL CONTRACTS DONE", "+1 module reroll token")
	Save.save_data()
	return true

func reroll_contract(index: int) -> bool:
	var list: Array = Save.contracts.get("list", [])
	if int(Save.contracts.get("reroll", 0)) <= 0 or index >= list.size() or list[index].done:
		return false
	var taken := []
	for c in list:
		taken.append(c.id)
	var pool: Array = []
	for pick in Goals.CONTRACTS:
		if not pick.id in taken:
			pool.append(pick)
	var pick: Dictionary = pool[randi() % pool.size()]
	list[index] = {"id": pick.id, "text": pick.text % int(pick.goal), "stat": pick.stat, "goal": pick.goal, "reward": pick.reward, "progress": 0, "done": false, "claimed": false}
	Save.contracts.reroll = 0
	Save.save_data()
	return true

# --- Rotating challenges ---

func daily_challenge() -> Dictionary:
	var day := today()
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 131 + 5
	var top := maxi(1, Save.unlocked)
	var level := rng.randi_range(1, top)
	while Levels.is_boss(level) and level > 1:
		level -= 1
	var dials: Array = Goals.DAILY_DIALS.duplicate()
	var a: String = dials[rng.randi() % dials.size()]
	dials.erase(a)
	var b: String = dials[rng.randi() % dials.size()]
	return {"day": day, "level": level, "mutators": [a, b], "best": int(Save.daily_best.get(day, 0)), "reward": 80 + level * 3}

func weekly_challenge() -> Dictionary:
	var wk := week()
	var rng := RandomNumberGenerator.new()
	rng.seed = wk * 977 + 3
	var beaten: int = maxi(1, Save.bosses_beaten.size())
	var sector := rng.randi_range(1, mini(beaten, Levels.SECTOR_COUNT))
	var dials: Array = Goals.DAILY_DIALS.duplicate()
	var a: String = dials[rng.randi() % dials.size()]
	return {"week": wk, "level": sector * Levels.LEVELS_PER_SECTOR, "mutators": [a], "best": int(Save.weekly_best.get(wk, 0)), "reward": 300, "sector": sector}

func season() -> Dictionary:
	var day := today()
	for s in Goals.SEASONS:
		if day >= int(s.start) and day < int(s.start) + int(s.days):
			return s
	return Goals.SEASONS[0]

func record_challenge(kind: String, score: int) -> bool:
	if kind == "daily":
		var day := today()
		var first := not Save.daily_best.has(day)
		Save.daily_best[day] = maxi(int(Save.daily_best.get(day, 0)), score)
		return first
	var wk := week()
	var first := not Save.weekly_best.has(wk)
	Save.weekly_best[wk] = maxi(int(Save.weekly_best.get(wk, 0)), score)
	return first
