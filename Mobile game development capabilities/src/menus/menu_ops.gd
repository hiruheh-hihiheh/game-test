class_name MenuOps
extends RefCounted
## Daily contracts, rotating challenges, achievements, codex and records.

var m
var tab := "today"
var open_entry := ""
var danger_on := {"daily": false, "weekly": false}

func _init(hub) -> void:
	m = hub

func on_ui(id: String) -> void:
	if id.begins_with("tab_"):
		tab = id.substr(4)
		open_entry = ""
		m.ui.reset_scroll()
	elif id == "danger_daily" or id == "danger_weekly":
		var kind := id.substr(7)
		danger_on[kind] = not bool(danger_on[kind])
		Audio.play("ui_click")
	elif id == "supply_claim":
		var got := Rewards.claim_streak()
		if not got.is_empty():
			Audio.play("ui_buy")
			Fade.toast("DAILY SUPPLY", got)
	elif id == "vault_claim":
		var tier := Rewards.vault_claimed() + 1
		var got := Rewards.claim_vault()
		if not got.is_empty():
			Audio.play("unlock")
			Fade.toast("STAR VAULT %d" % (tier * Rewards.VAULT_STEP), got)
	elif id.begins_with("claim_"):
		if Meta.claim_contract(int(id.substr(6))):
			Audio.play("ui_buy")
	elif id.begins_with("swap_"):
		if not Meta.reroll_contract(int(id.substr(5))):
			Audio.play("ui_deny")
	elif id.begins_with("entry_"):
		var e := id.substr(6)
		open_entry = "" if open_entry == e else e
	else:
		match id:
			"daily":
				var d: Dictionary = Meta.daily_challenge()
				m.launch({"mode": "daily", "level": d.level, "mutators": d.mutators, "reward": d.reward, "danger": _danger_for("daily", d)})
			"weekly":
				var d: Dictionary = Meta.weekly_challenge()
				m.launch({"mode": "weekly", "level": d.level, "mutators": d.mutators, "reward": d.reward, "danger": _danger_for("weekly", d)})
			"rush":
				if rush_open():
					m.launch({"mode": "rush", "level": Save.unlocked, "mutators": []})

## The featured contract of today's or this week's challenge, if the player switched it on.
func featured_id(kind: String, data: Dictionary) -> String:
	return Danger.featured(int(data.day) if kind == "daily" else int(data.week), data.mutators, kind)

func _danger_for(kind: String, data: Dictionary) -> Array:
	if not bool(danger_on[kind]) or not Danger.unlocked():
		return []
	var id := featured_id(kind, data)
	return [id] if not id.is_empty() else []

func paint(c: UILayer) -> void:
	var W: float = m.W
	var top: float = float(m.top) + 262.0
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	var y := top - c.scroll
	match tab:
		"today":
			y = _paint_today(c, x, y, w)
		"awards":
			y = _paint_awards(c, x, y, w)
		"codex":
			y = _paint_codex(c, x, y, w)
		"records":
			y = _paint_records(c, x, y, w)
	c.scroll_max = maxf(0.0, y + c.scroll - float(m.H) + float(m.bottom) + 30.0)
	m.header(c, "OPS", UI.CYAN)
	c.draw_rect(Rect2(0, float(m.top) + 178.0, W, 76.0), Color(0.01, 0.01, 0.05, 0.86))
	c.cover(Rect2(0, float(m.top) + 178.0, W, 76.0))
	var tabs := [["today", "TODAY"], ["awards", "AWARDS"], ["codex", "CODEX"], ["records", "RECORDS"]]
	var tw := (w - 18.0) / 4.0
	for i in range(tabs.size()):
		var on: bool = tab == tabs[i][0]
		c.button("tab_" + str(tabs[i][0]), Rect2(x + float(i) * (tw + 6.0), float(m.top) + 186.0, tw, 62), str(tabs[i][1]), UI.MINT if on else UI.CYAN, {"selected": on, "size": 20})

func _section(c: UILayer, x: float, y: float, text: String) -> float:
	UI.outlined(c, text, Vector2(x + 4.0, y + 22.0), 21, UI.TEXT_DIM, true)
	return y + 36.0

## The seven-day supply run: one pip per day, the next reward spelled out, and a claim button when it is ready.
func _paint_supply(c: UILayer, x: float, y: float, w: float) -> float:
	var st := Rewards.streak()
	var ready: bool = st.ready
	var day := int(st.day)
	var r := Rect2(x, y, w, 132.0)
	var color: Color = UI.GOLD if ready else UI.CYAN
	UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.93), Color(color, 0.55), 14, 2)
	UI.text(c, "DAILY SUPPLY", r.position + Vector2(22, 34), 22, UI.WHITE, true)
	UI.text(c, "DAY %d OF 7" % day, r.position + Vector2(210, 34), 18, color, true)
	var days := Rewards.STREAK.size()
	var pw := (w - 230.0 - 6.0 * float(days - 1)) / float(days)
	for i in range(days):
		var got: bool = i < day - 1 or (i == day - 1 and not ready)
		var pr := Rect2(r.position.x + 22.0 + float(i) * (pw + 6.0), r.position.y + 50.0, pw, 26.0)
		c.draw_rect(pr, Color(UI.MINT, 0.85) if got else (Color(UI.GOLD, 0.35) if i == day - 1 else Color(0.2, 0.25, 0.36, 0.8)))
		if Rewards.STREAK[i].has("gear"):
			UI.star(c, pr.get_center(), 8.0, UI.WHITE if got else UI.GOLD)
	var next: Dictionary = Rewards.STREAK[(day - 1) if ready else (day % days)]
	var line := ("Today: " if ready else "Tomorrow: ") + Rewards.describe(next)
	UI.fit_text(c, line, r.position + Vector2(22, 108), 19, 14, w - 230.0, UI.WHITE if ready else UI.TEXT_DIM)
	var br := Rect2(r.end.x - 176, r.position.y + 34.0, 160, 66)
	if ready:
		c.button("supply_claim", br, "CLAIM", UI.GOLD, {"size": 24, "primary": true, "sound": ""})
	else:
		c.button("supply_done", br, "%dh" % (Meta.seconds_to_reset() / 3600 + 1), UI.CYAN, {"size": 22, "disabled": true})
	return y + 144.0

## A reward for every ten stars. Shows how far the next one is, so chasing a missing star always pays.
func _paint_vault(c: UILayer, x: float, y: float, w: float) -> float:
	var stars := Save.total_stars()
	var claimed := Rewards.vault_claimed()
	var ready := Rewards.vault_ready() > 0
	var done := claimed >= Rewards.vault_tiers()
	var tier := mini(claimed + 1, Rewards.vault_tiers())
	var need := tier * Rewards.VAULT_STEP
	var r := Rect2(x, y, w, 132.0)
	var color: Color = UI.GOLD if ready else UI.CYAN
	UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.93), Color(color, 0.55), 14, 2)
	UI.star(c, r.position + Vector2(36, 28), 13.0, UI.GOLD)
	UI.text(c, "STAR VAULT", r.position + Vector2(58, 34), 22, UI.WHITE, true)
	UI.text(c, "%d / %d" % [mini(stars, need), need] if not done else "COMPLETE", r.position + Vector2(210, 34), 18, color, true)
	var from := (tier - 1) * Rewards.VAULT_STEP
	UI.bar(c, Rect2(r.position + Vector2(22, 54), Vector2(w - 230.0, 18)), 1.0 if done else clampf(float(stars - from) / float(Rewards.VAULT_STEP), 0.0, 1.0), color)
	var line := "Every star is collected" if done else ("Reward: " + Rewards.describe(Rewards.vault_reward(tier)))
	UI.fit_text(c, line, r.position + Vector2(22, 108), 19, 14, w - 230.0, UI.WHITE if ready else UI.TEXT_DIM)
	var br := Rect2(r.end.x - 176, r.position.y + 34.0, 160, 66)
	if ready:
		c.button("vault_claim", br, "CLAIM", UI.GOLD, {"size": 24, "primary": true, "sound": ""})
	elif not done:
		c.button("vault_wait", br, "%d MORE" % (need - stars), UI.CYAN, {"size": 20, "disabled": true})
	return y + 144.0

func _paint_today(c: UILayer, x: float, y: float, w: float) -> float:
	y = _section(c, x, y, "REWARDS")
	y = _paint_supply(c, x, y, w)
	y = _paint_vault(c, x, y, w)
	y += 8.0
	var hours: int = Meta.seconds_to_reset() / 3600
	y = _section(c, x, y, "DAILY CONTRACTS  ·  %dh LEFT" % hours)
	var list: Array = Save.contracts.get("list", [])
	for i in range(list.size()):
		var con: Dictionary = list[i]
		var h := 106.0
		var r := Rect2(x, y, w, h - 10.0)
		var color: Color = UI.MINT if con.done else UI.CYAN
		UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.93), Color(color, 0.5), 14, 2)
		UI.fit_text(c, str(con.text), r.position + Vector2(22, 38), 22, 15, w - 230.0, UI.WHITE, true)
		var ratio := float(con.progress) / float(con.goal)
		UI.bar(c, Rect2(r.position + Vector2(22, 56), Vector2(w - 230.0, 16)), ratio, color)
		UI.text(c, "%d/%d" % [mini(int(con.progress), int(con.goal)), con.goal], r.position + Vector2(22, 90 - 2), 16, UI.TEXT_DIM)
		UI.enter_veil(c, r, float(m.screen_t), mini(i, 6))
		var br := Rect2(r.end.x - 176, r.position.y + 16.0, 160, 62)
		if con.claimed:
			c.button("done%d" % i, br, "DONE", UI.MINT, {"size": 20, "disabled": true})
		elif con.done:
			c.button("claim_%d" % i, br, "+%d" % int(con.reward), UI.GOLD, {"size": 24, "primary": true, "icon": m.SALVAGE_ART, "sound": ""})
		elif int(Save.contracts.get("reroll", 0)) > 0:
			c.button("swap_%d" % i, br, "SWAP", UI.CYAN, {"size": 20})
		y += h
	y += 12.0
	y = _section(c, x, y, "CHALLENGES")
	var daily: Dictionary = Meta.daily_challenge()
	y = _challenge_card(c, x, y, w, "daily", "DAILY ANOMALY", daily, UI.MAGENTA)
	var weekly: Dictionary = Meta.weekly_challenge()
	y = _challenge_card(c, x, y, w, "weekly", "WEEKLY BOSS", weekly, UI.RED)
	y = _paint_rush(c, x, y, w)
	return y

func rush_open() -> bool:
	return Save.bosses_beaten.size() >= Bosses.RUSH_UNLOCK

## Boss Rush: every boss in one flight, always available once three sector bosses have fallen.
func _paint_rush(c: UILayer, x: float, y: float, w: float) -> float:
	var open := rush_open()
	var total: int = Bosses.RUSH_ORDER.size()
	var r := Rect2(x, y, w, 150.0)
	var color: Color = UI.GOLD if open else Color(0.45, 0.5, 0.62)
	UI.panel(c, r, Color(color.darkened(0.82), 0.95), Color(color, 0.8), 16, 2)
	UI.text(c, "BOSS RUSH", r.position + Vector2(22, 38), 25, UI.WHITE, true)
	UI.fit_text(c, "All %d bosses in one flight, two of them found nowhere else." % total, r.position + Vector2(22, 68), 19, 14, w - 220.0, UI.TEXT_DIM)
	UI.fit_text(c, "A module and a hull repair after every boss.", r.position + Vector2(22, 96), 18, 13, w - 220.0, UI.ORANGE, true)
	var best: int = Meta.stat("rush_best")
	var line := "BEST %d / %d" % [best, total] if best > 0 else "First clear: Legendary gear"
	if not open:
		line = "Opens after %d sector bosses (%d so far)" % [Bosses.RUSH_UNLOCK, Save.bosses_beaten.size()]
	UI.fit_text(c, line, r.position + Vector2(22, 130), 18, 13, w - 220.0, UI.GOLD if open else UI.TEXT_DIM)
	UI.enter_veil(c, r, float(m.screen_t), 5)
	c.button("rush", Rect2(r.end.x - 176, r.position.y + 42.0, 160, 72), "FLY" if open else "LOCKED", color, {"primary": open, "size": 26 if open else 20, "disabled": not open})
	return y + 162.0

func _challenge_card(c: UILayer, x: float, y: float, w: float, id: String, title: String, data: Dictionary, color: Color) -> float:
	var feat := featured_id(id, data) if Danger.unlocked() else ""
	var h := 150.0 + (92.0 if not feat.is_empty() else 0.0)
	var r := Rect2(x, y, w, h)
	UI.panel(c, r, Color(color.darkened(0.82), 0.95), Color(color, 0.8), 16, 2)
	UI.text(c, title, r.position + Vector2(22, 38), 25, UI.WHITE, true)
	UI.text(c, str(Levels.level_name(int(data.level))), r.position + Vector2(22, 68), 20, UI.TEXT_DIM)
	var names: Array = []
	for d in data.mutators:
		names.append(str(Mutators.LIST[d].name))
	UI.text(c, " + ".join(names), r.position + Vector2(22, 98), 18, UI.ORANGE, true)
	var best := int(data.best)
	UI.text(c, "BEST %d" % best if best > 0 else "First clear: +%d" % int(data.reward), r.position + Vector2(22, 130), 18, UI.GOLD)
	UI.enter_veil(c, r, float(m.screen_t), 3 if id == "daily" else 4)
	c.button(id, Rect2(r.end.x - 176, r.position.y + 42.0, 160, 72), "FLY", color, {"primary": true, "size": 26})
	if not feat.is_empty():
		# One optional extra, the same for everyone today: switch it on to fly it.
		var on := bool(danger_on[id])
		var def: Dictionary = Danger.LIST[feat]
		var row := Rect2(r.position.x + 12.0, r.position.y + 150.0, w - 24.0, 82.0)
		c.hit_area("danger_" + id, row)
		UI.panel(c, row, Color(UI.MAGENTA.darkened(0.7), 0.96) if on else Color(0.03, 0.05, 0.12, 0.9), Color(UI.MAGENTA, 0.95 if on else 0.4), 10, 3 if on else 2)
		UIArt.draw(c, str(def.art), row.position + Vector2(42, 41), 58.0, {"animate": on})
		UI.fit_text(c, "DANGER: " + str(def.name), row.position + Vector2(86, 28), 19, 14, row.size.x - 190.0, UI.WHITE, true)
		UI.fit_text(c, str(def.desc), row.position + Vector2(86, 50), 15, 12, row.size.x - 104.0, UI.TEXT_DIM)
		UI.fit_text(c, " · ".join(Danger.reward_lines(feat)), row.position + Vector2(86, 71), 16, 12, row.size.x - 104.0, UI.GOLD, true)
		UI.text(c, "ON" if on else "ADD", row.position + Vector2(row.size.x - 16.0, 28), 20, UI.MAGENTA if on else UI.CYAN, true, UI.RIGHT)
	return y + h + 12.0

func _paint_awards(c: UILayer, x: float, y: float, w: float) -> float:
	var done := Save.achievements.size()
	y = _section(c, x, y, "%d / %d EARNED" % [done, Goals.ACHIEVEMENTS.size()])
	for a in Goals.ACHIEVEMENTS:
		var earned: bool = Save.achievements.has(a.id)
		var h := 96.0
		var visible: bool = y > -h and y < float(m.H)
		if visible:
			var r := Rect2(x, y, w, h - 8.0)
			var color: Color = UI.GOLD if earned else UI.CYAN
			UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.92), Color(color, 0.7 if earned else 0.22), 12, 2)
			UI.star(c, r.position + Vector2(44, r.size.y * 0.5), 24.0, UI.GOLD if earned else Color(0.2, 0.24, 0.34))
			UI.text(c, str(a.name), r.position + Vector2(84, 36), 22, UI.WHITE if earned else UI.TEXT_DIM, true)
			UI.text(c, str(a.desc), r.position + Vector2(84, 66), 18, UI.TEXT_DIM)
			if not earned:
				var have := mini(Meta.stat(str(a.stat)), int(a.goal))
				UI.text(c, "%d/%d" % [have, a.goal], r.position + Vector2(w - 18.0, 34), 17, UI.CYAN, false, UI.RIGHT)
			UI.text(c, "+%d" % int(a.reward), r.position + Vector2(w - 18.0, 66), 17, UI.MINT, true, UI.RIGHT)
		y += h
	return y

func _paint_codex(c: UILayer, x: float, y: float, w: float) -> float:
	y = _section(c, x, y, "SECTORS")
	for i in range(Levels.SECTORS.size()):
		var info: Dictionary = Levels.SECTORS[i]
		var known := Save.unlocked > i * Levels.LEVELS_PER_SECTOR
		y = _entry(c, x, y, w, "sector%d" % i, str(info.name) if known else "UNCHARTED", str(info.lore) if known else "", known, null, info.color)
	y = _section(c, x, y + 8.0, "BOSSES")
	for i in range(Bosses.LIST.size()):
		var def: Dictionary = Bosses.LIST[i]
		var known := Save.codex.has("boss_%d" % (i + 1))
		y = _entry(c, x, y, w, "boss%d" % i, str(def.name) if known else "UNKNOWN SIGNAL", str(def.lore) + " " + str(def.tip) if known else "", known, null, UI.RED)
	y = _section(c, x, y + 8.0, "ENEMIES")
	for id in Enemies.DB:
		var e: Dictionary = Enemies.DB[id]
		var known := Save.codex.has("enemy_" + id)
		y = _entry(c, x, y, w, id, str(e.name) if known else "UNKNOWN", str(e.lore) if known else "", known, Enemies.ART[e.art], UI.CYAN)
	return y

func _entry(c: UILayer, x: float, y: float, w: float, id: String, title: String, body: String, known: bool, tex, color: Color) -> float:
	var is_open := open_entry == id and known
	var lines := UI.wrap_lines(body, 19, w - 44.0) if is_open else PackedStringArray()
	var h := 70.0 + float(lines.size()) * 26.0
	if y > -h and y < float(m.H):
		var r := Rect2(x, y, w, h - 6.0)
		if known:
			c.hit_area("entry_" + id, r)
		UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.92), Color(color, 0.5 if known else 0.15), 12, 2)
		var tx := 22.0
		if tex != null and known:
			UI.icon(c, tex, r.position + Vector2(40, 32), 54.0)
			tx = 80.0
		UI.text(c, title, r.position + Vector2(tx, 42), 22, UI.WHITE if known else Color(0.45, 0.48, 0.56), true)
		for l in range(lines.size()):
			UI.text(c, lines[l], r.position + Vector2(22, 84.0 + float(l) * 26.0), 19, UI.TEXT_DIM)
	return y + h

func _paint_records(c: UILayer, x: float, y: float, w: float) -> float:
	var rows := [
		["Best score", str(Save.best_score)], ["Best combo", str(Meta.stat("best_combo"))], ["Best Rift floor", str(Save.endless_best_wave)], ["Pilot level", str(Pilot.level())], ["Gear found", str(Meta.stat("gear_found"))], ["Legendaries found", str(Meta.stat("legendary"))], ["Highest tier", str(Tiers.cfg(Save.tier_unlocked).name)],
		["Expeditions won", str(Save.expedition_wins)], ["Stars", "%d / 180" % Save.total_stars()], ["Enemies destroyed", str(Meta.stat("kill"))],
		["Crystals collected", str(Meta.stat("crystal"))], ["Bosses defeated", str(Meta.stat("boss"))], ["Shots grazed", str(Meta.stat("graze"))],
		["Novas fired", str(Meta.stat("nova"))], ["Modules evolved", str(Meta.stat("evolve"))], ["Evolutions discovered", "%d / 10" % Meta.stat("evolve_unique")],
	]
	for row in rows:
		var r := Rect2(x, y, w, 62)
		UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.9), Color(UI.CYAN, 0.2), 10, 1)
		UI.text(c, str(row[0]), r.position + Vector2(20, 40), 21, UI.TEXT_DIM)
		UI.text(c, str(row[1]), r.position + Vector2(w - 20.0, 41), 24, UI.WHITE, true, UI.RIGHT)
		y += 70.0
	return y
