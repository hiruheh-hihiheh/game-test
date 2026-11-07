class_name MenuOps
extends RefCounted
## Daily contracts, rotating challenges, achievements, codex and records.

var m
var tab := "today"
var open_entry := ""

func _init(hub) -> void:
	m = hub

func on_ui(id: String) -> void:
	if id.begins_with("tab_"):
		tab = id.substr(4)
		open_entry = ""
		m.ui.reset_scroll()
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
				m.launch({"mode": "daily", "level": d.level, "mutators": d.mutators, "reward": d.reward})
			"weekly":
				var d: Dictionary = Meta.weekly_challenge()
				m.launch({"mode": "weekly", "level": d.level, "mutators": d.mutators, "reward": d.reward})

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
	var tabs := [["today", "TODAY"], ["awards", "AWARDS"], ["codex", "CODEX"], ["records", "RECORDS"]]
	var tw := (w - 18.0) / 4.0
	for i in range(tabs.size()):
		var on: bool = tab == tabs[i][0]
		c.button("tab_" + str(tabs[i][0]), Rect2(x + float(i) * (tw + 6.0), float(m.top) + 186.0, tw, 62), str(tabs[i][1]), UI.MINT if on else UI.CYAN, {"primary": on, "size": 20})

func _section(c: UILayer, x: float, y: float, text: String) -> float:
	UI.outlined(c, text, Vector2(x + 4.0, y + 22.0), 21, UI.TEXT_DIM, true)
	return y + 36.0

func _paint_today(c: UILayer, x: float, y: float, w: float) -> float:
	var hours: int = Meta.seconds_to_reset() / 3600
	y = _section(c, x, y, "DAILY CONTRACTS  ·  %dh LEFT" % hours)
	var list: Array = Save.contracts.get("list", [])
	for i in range(list.size()):
		var con: Dictionary = list[i]
		var h := 106.0
		var r := Rect2(x, y, w, h - 10.0)
		var color: Color = UI.MINT if con.done else UI.CYAN
		UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.93), Color(color, 0.5), 14, 2)
		UI.text(c, str(con.text), r.position + Vector2(22, 38), 22, UI.WHITE, true)
		var ratio := float(con.progress) / float(con.goal)
		UI.bar(c, Rect2(r.position + Vector2(22, 56), Vector2(w - 230.0, 16)), ratio, color)
		UI.text(c, "%d/%d" % [mini(int(con.progress), int(con.goal)), con.goal], r.position + Vector2(22, 90 - 2), 16, UI.TEXT_DIM)
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
	return y

func _challenge_card(c: UILayer, x: float, y: float, w: float, id: String, title: String, data: Dictionary, color: Color) -> float:
	var h := 150.0
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
	c.button(id, Rect2(r.end.x - 176, r.position.y + 42.0, 160, 72), "FLY", color, {"primary": true, "size": 26})
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
