class_name MenuMap
extends RefCounted
## Sector map, pre-flight briefing and loadout picker.

const ICON_BOSS := preload("res://assets/starfall/ui_icons/icon_boss.png")
const ICON_PLAY := preload("res://assets/starfall/ui_icons/icon_play.png")

var m
var level := 1
var mode := "campaign"
var dials: Array = []
var slot := 0
var tier := 0
var picker := DangerPicker.new()
var _picks := -1

func _init(hub) -> void:
	m = hub

func on_enter() -> void:
	tier = clampi(Save.map_tier, 0, Save.tier_unlocked)

func open_level(n: int) -> void:
	level = n
	mode = "side" if n >= Levels.SIDE_FIRST else "campaign"
	dials = []
	picker.reset(mode)
	_picks = (Levels.build(n).waves as Array).size()
	m.go("preflight")

func open_endless() -> void:
	mode = "endless"
	dials = []
	picker.reset("endless")
	_picks = -1

## The rules the contract cards check themselves against.
func _ctx() -> Dictionary:
	return {"mode": mode, "dials": dials, "picks": _picks}

func on_ui(id: String) -> void:
	if id.begins_with("level"):
		open_level(int(id.substr(5)))
	elif id.begins_with("danger_"):
		picker.on_ui(id, _ctx())
	elif id.begins_with("dial_"):
		var d := id.substr(5)
		if d in dials:
			dials.erase(d)
		else:
			var clash := Danger.dial_conflict(picker.chosen, d)
			if clash.is_empty():
				dials.append(d)
			else:
				picker.note = "%s dial conflicts with %s" % [str(Mutators.LIST[d].name), clash]
				Audio.play("ui_deny")
	elif id.begins_with("ship_"):
		var ship_id := id.substr(5)
		if ship_id in Save.owned_ships:
			Save.ship = ship_id
			Save.save_data()
	elif id.begins_with("slot"):
		slot = int(id.substr(4))
		m.go("loadout")
	elif id.begins_with("pick_"):
		_assign(id.substr(5))
	else:
		match id:
			"prev":
				Save.map_sector = maxi(1, Save.map_sector - 1)
				m._set_background()
				m.screen_t = 0.0
			"next":
				Save.map_sector = mini(Levels.SECTOR_COUNT, Save.map_sector + 1)
				m._set_background()
				m.screen_t = 0.0
			"tier":
				tier = (tier + 1) % (Save.tier_unlocked + 1)
				Save.map_tier = tier
				m.screen_t = 0.0
			"launch":
				var chosen := Danger.sanitize(picker.chosen, _ctx())
				if not chosen.is_empty():
					Danger.remember(chosen, mode)
				m.launch({"mode": mode, "level": level, "mutators": dials.duplicate(), "tier": tier if mode == "campaign" else 0, "danger": chosen})
			"clear_slot":
				_assign("")

func _assign(card: String) -> void:
	while Save.loadout.size() <= slot:
		Save.loadout.append("")
	if not card.is_empty():
		for i in range(Save.loadout.size()):
			if Save.loadout[i] == card:
				Save.loadout[i] = ""
	Save.loadout[slot] = card
	Save.save_data()
	m.back()

func paint(c: UILayer) -> void:
	match str(m.screen):
		"map":
			_paint_map(c)
		"preflight":
			_paint_preflight(c)
		"loadout":
			_paint_loadout(c)

func _node_pos(i: int, y0: float, y1: float) -> Vector2:
	# A steady S-curve: left, centre, right, centre, so no two nodes ever crowd.
	var k := float(i) / float(Levels.LEVELS_PER_SECTOR - 1)
	var span: float = minf(float(m.W) * 0.3, 210.0)
	var swing: float = [-1.0, 0.0, 1.0, 0.0][i % 4]
	return Vector2(float(m.W) * 0.5 + swing * span, lerpf(y0, y1, k))

func _paint_map(c: UILayer) -> void:
	var sector := Save.map_sector
	var info: Dictionary = Levels.SECTORS[sector - 1]
	var accent: Color = info.color
	var W: float = m.W
	var top: float = m.top
	c.button("back", Rect2(20, top, 84, 84), "", UI.WHITE, {"icon": m.ICON_HOME, "sound": "ui_back"})
	m.salvage_chip(c, W - 20.0, top + 14.0)
	if Save.tier_unlocked > 0:
		var tier_color: Color = Tiers.cfg(tier).color
		c.button("tier", Rect2(W - 190.0, top + 82.0, 170, 52), str(Tiers.cfg(tier).name), tier_color, {"size": 18, "primary": tier > 0})
	UI.glow_text(c, "SECTOR %d" % sector, Vector2(W * 0.5, top + 136.0), 44, UI.WHITE, accent)
	UI.outlined(c, str(info.name), Vector2(W * 0.5, top + 176.0), 29, accent, true, UI.CENTER)
	UI.outlined(c, "MECHANIC: " + str(info.mechanic), Vector2(W * 0.5, top + 208.0), 19, UI.TEXT_DIM, false, UI.CENTER)
	var first := (sector - 1) * Levels.LEVELS_PER_SECTOR + 1
	var y_bottom: float = float(m.H) - float(m.bottom) - 200.0
	var y_top: float = top + 290.0
	var pts: Array = []
	for i in range(Levels.LEVELS_PER_SECTOR):
		pts.append(_node_pos(i, y_bottom, y_top))
	for i in range(Levels.LEVELS_PER_SECTOR - 1):
		var done := first + i < Save.unlocked_at(tier)
		c.draw_line(pts[i], pts[i + 1], Color(accent, 0.85) if done else Color(1, 1, 1, 0.14), 5.0 if done else 3.0, true)
	if tier == 0:
		_paint_side_node(c, sector, first, pts, accent)
	for i in range(Levels.LEVELS_PER_SECTOR):
		_paint_node(c, first + i, pts[i], accent)
	var nav_y: float = float(m.H) - float(m.bottom) - 92.0
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	c.button("prev", Rect2(x, nav_y, 150, 84), "PREV", UI.CYAN, {"size": 24, "disabled": sector <= 1})
	c.button("next", Rect2(x + w - 150, nav_y, 150, 84), "NEXT", UI.CYAN, {"size": 24, "disabled": sector >= Levels.SECTOR_COUNT or (sector * Levels.LEVELS_PER_SECTOR + 1) > Save.unlocked_at(tier)})
	UI.star(c, Vector2(W * 0.5 - 52.0, nav_y + 38.0), 18.0, UI.GOLD)
	UI.outlined(c, "%d/30" % Save.sector_stars_at(tier, sector), Vector2(W * 0.5 - 26.0, nav_y + 49.0), 28, UI.WHITE, true)

func _paint_node(c: UILayer, n: int, pos: Vector2, accent: Color) -> void:
	var unlocked := Save.unlocked_at(tier)
	var locked := n > unlocked
	var boss := Levels.is_boss(n)
	var elite := Levels.is_elite(n)
	var current := n == unlocked
	var r := 56.0 if boss else (48.0 if elite else 42.0)
	var id := "level%d" % n
	c.hit_area(id, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), {"disabled": locked})
	c.draw_set_transform(pos, 0.0, Vector2.ONE * (1.0 - c.press_amount(id) * 0.08))
	if current:
		UI.glow(c, Vector2.ZERO, r * 2.1 * (1.0 + sin(float(m.t) * 4.0) * 0.12), Color(accent, 0.55))
	var fill: Color = accent.darkened(0.3) if current else (Color(accent.darkened(0.66), 0.97) if not locked else Color(0.05, 0.06, 0.1, 0.92))
	var edge: Color = Color(accent, 0.98) if not locked else Color(0.4, 0.44, 0.54, 0.5)
	UI.panel(c, Rect2(-r, -r, r * 2.0, r * 2.0), fill, edge, int(r * 0.42), 3)
	if boss:
		UI.icon(c, ICON_BOSS, Vector2.ZERO, r * 1.4, Color.WHITE if not locked else Color(1, 1, 1, 0.3))
	else:
		UI.text(c, str(n), Vector2(0, 11), 29, UI.WHITE if not locked else Color(0.5, 0.54, 0.62), true, UI.CENTER)
	var mask := Save.mask_at(tier, n)
	if mask > 0:
		for s in range(3):
			UI.star(c, Vector2((float(s) - 1.0) * 26.0, r + 14.0), 12.0, UI.GOLD if mask & (1 << s) else Color(0.2, 0.22, 0.3))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The Black Box side mission branches off after the sector's elite.
func _paint_side_node(c: UILayer, sector: int, first: int, pts: Array, accent: Color) -> void:
	var elite_level := first + 4
	if int(Save.star_mask.get(elite_level, 0)) == 0:
		return
	var n := Levels.SIDE_FIRST + sector - 1
	var from: Vector2 = pts[4]
	var side := 1.0 if from.x < float(m.W) * 0.5 else -1.0
	var pos := Vector2(from.x + side * 150.0, from.y)
	if absf(pos.x - float(m.W) * 0.5) < 60.0:
		pos.x += side * 90.0
	c.draw_dashed_line(from, pos, UI.GOLD, 3.0, 12.0)
	var done: bool = n in Save.side_cleared
	var id := "level%d" % n
	var r := 38.0
	c.hit_area(id, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0))
	var pts_d := PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0)])
	if not done:
		UI.glow(c, pos, r * 1.9, Color(UI.GOLD, 0.34))
	c.draw_colored_polygon(pts_d, Color(0.12, 0.09, 0.02, 0.96))
	var closed := pts_d.duplicate()
	closed.append(pts_d[0])
	c.draw_polyline(closed, UI.GOLD, 3.0, true)
	UI.text(c, "?" if not done else "OK", pos + Vector2(0, 11), 26, UI.GOLD, true, UI.CENTER)

func _paint_preflight(c: UILayer) -> void:
	var W: float = m.W
	var endless := mode == "endless"
	var y: float = float(m.top) + 190.0 - c.scroll
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	if not endless:
		var def := Levels.build(level)
		UI.text(c, str(def.name), Vector2(W * 0.5, y + 16.0), 28, UI.WHITE, true, UI.CENTER)
		y += 34.0
		var obj: String = Levels.objective_text(def.obj)
		var mask := Save.mask_at(tier if mode == "campaign" else 0, level)
		var labels := ["Clear the level", "Lose no hull", obj]
		for s in range(3):
			var on := mask & (1 << s) != 0
			UI.star(c, Vector2(x + 34.0, y + 12.0), 13.0, UI.GOLD if on else Color(0.3, 0.33, 0.42))
			UI.text(c, labels[s], Vector2(x + 58.0, y + 20.0), 21, UI.WHITE if on else UI.TEXT_DIM)
			y += 30.0
		var side_reward: String = def.side_reward
		if not side_reward.is_empty() and not Save.has_blueprint(side_reward):
			UI.text(c, "REWARD: " + str(Levels.BLUEPRINT_NAMES[side_reward]), Vector2(x + 24.0, y + 20.0), 20, UI.GOLD, true)
			y += 30.0
	if mode == "campaign" and tier > 0:
		var tier_color: Color = Tiers.cfg(tier).color
		UI.text(c, "TIER: " + str(Tiers.cfg(tier).name), Vector2(x + 4.0, y + 24.0), 21, tier_color, true)
		y += 30.0
		for line in UI.wrap_lines(Tiers.describe(tier), 18, w - 8.0):
			UI.text(c, line, Vector2(x + 4.0, y + 18.0), 18, UI.TEXT_DIM)
			y += 24.0
	if endless:
		UI.text(c, "Floors get harder the deeper you go.", Vector2(x + 4.0, y + 20.0), 20, UI.WHITE)
		UI.text(c, "Every 5th floor is a boss. Deeper floors drop better gear.", Vector2(x + 4.0, y + 48.0), 18, UI.TEXT_DIM)
		UI.text(c, "BEST FLOOR %d" % Save.endless_best_wave, Vector2(x + 4.0, y + 80.0), 22, UI.GOLD, true)
		y += 96.0
	y += 16.0
	y = _paint_ship_row(c, x, y, w)
	y = _paint_slots(c, x, y, w)
	y = picker.paint(c, x, y, w, _ctx())
	y = _paint_dials(c, x, y, w)
	var tag_h := 30.0 if not picker.chosen.is_empty() else 0.0
	var by: float = float(m.H) - float(m.bottom) - 108.0 - tag_h
	c.scroll_max = maxf(0.0, y + c.scroll - by + 12.0)
	m.header(c, "RIFT" if endless else ("LEVEL %d" % level if mode == "campaign" else "BLACK BOX"), UI.CYAN)
	c.draw_rect(Rect2(0, by - 10.0, W, float(m.H)), Color(0.01, 0.01, 0.05, 0.86))
	var mult := Mutators.multiplier(dials)
	var label := "LAUNCH" if mult <= 1.0 else "LAUNCH  x%.2f" % mult
	var launch_opts := {"primary": true, "icon": ICON_PLAY, "size": 34}
	if tag_h > 0.0:
		UI.fit_text(c, "DANGER: " + Danger.names(picker.chosen), Vector2(x + 8.0, by + 18.0), 18, 12, w - 16.0, UI.MAGENTA, true)
	c.button("launch", Rect2(x, by + tag_h, w, 100), label, UI.MINT, launch_opts)

func _paint_ship_row(c: UILayer, x: float, y: float, w: float) -> float:
	UI.text(c, "SHIP", Vector2(x + 4.0, y + 16.0), 19, UI.TEXT_DIM, true)
	y += 26.0
	var owned: Array = []
	for id in Ships.ORDER:
		if id in Save.owned_ships:
			owned.append(id)
	var gap := 12.0
	var cell := minf(120.0, (w - gap * 4.0) / 5.0)
	for i in range(owned.size()):
		var id: String = owned[i]
		var r := Rect2(x + float(i) * (cell + gap), y, cell, cell)
		var on: bool = Save.ship == id
		c.hit_area("ship_" + id, r)
		UI.panel(c, r, Color(UI.MINT.darkened(0.78), 0.96) if on else Color(0.03, 0.05, 0.12, 0.9), Color(UI.MINT, 0.95) if on else Color(UI.CYAN, 0.3), 12, 3 if on else 2)
		UI.icon(c, Ships.ART[id], r.get_center(), cell * 0.86)
	y += cell + 8.0
	var ship: Dictionary = Ships.LIST[Save.ship]
	UI.text(c, str(ship.name) + "  ·  " + str(ship.role), Vector2(x + 4.0, y + 18.0), 20, UI.MINT, true)
	return y + 34.0

func _paint_slots(c: UILayer, x: float, y: float, w: float) -> float:
	UI.text(c, "LOADOUT MODULES", Vector2(x + 4.0, y + 16.0), 19, UI.TEXT_DIM, true)
	y += 26.0
	var slots := Save.loadout_slots()
	var cell := 96.0
	for i in range(3):
		var r := Rect2(x + float(i) * (cell + 14.0), y, cell, cell)
		if i >= slots:
			UI.panel(c, r, Color(0.02, 0.03, 0.07, 0.7), Color(0.4, 0.44, 0.54, 0.3), 12, 2)
			UI.text(c, "LOCKED", r.get_center() + Vector2(0, 7), 15, Color(0.5, 0.54, 0.62), true, UI.CENTER)
			continue
		var card: String = Save.loadout[i] if i < Save.loadout.size() else ""
		c.hit_area("slot%d" % i, r)
		if Cards.LIST.has(card):
			var def: Dictionary = Cards.LIST[card]
			UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.95), Cards.RARITY_COLORS[int(def.rarity)], 12, 3)
			UI.icon(c, Cards.ICONS[def.icon], r.get_center(), 74.0)
		else:
			UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.8), Color(UI.CYAN, 0.5), 12, 2)
			UI.text(c, "+", r.get_center() + Vector2(0, 16), 44, UI.CYAN, true, UI.CENTER)
	return y + cell + 12.0

func _paint_dials(c: UILayer, x: float, y: float, w: float) -> float:
	var cleared := mode == "endless" or Save.mask_at(tier if mode == "campaign" else 0, level) > 0 or mode == "side"
	if not cleared:
		UI.text(c, "HAZARD DIALS unlock after you clear this level", Vector2(x + 4.0, y + 18.0), 19, UI.TEXT_DIM)
		return y + 34.0
	UI.text(c, "HAZARD DIALS  (harder, pays more)", Vector2(x + 4.0, y + 16.0), 19, UI.TEXT_DIM, true)
	y += 26.0
	var cols := 2
	var gap := 10.0
	var cw := (w - gap) * 0.5
	var ch := 80.0
	for i in range(Mutators.ORDER.size()):
		var id: String = Mutators.ORDER[i]
		var def: Dictionary = Mutators.LIST[id]
		var r := Rect2(x + float(i % cols) * (cw + gap), y + float(i / cols) * (ch + 8.0), cw, ch)
		var on := id in dials
		var clash := "" if on else Danger.dial_conflict(picker.chosen, id)
		c.hit_area("dial_" + id, r)
		UI.panel(c, r, Color(UI.ORANGE.darkened(0.7), 0.96) if on else Color(0.03, 0.05, 0.12, 0.9), Color(UI.ORANGE, 0.95) if on else Color(UI.CYAN, 0.25), 10, 3 if on else 2)
		UI.text(c, str(def.name), r.position + Vector2(14, 30), 19, UI.WHITE, true)
		if clash.is_empty():
			UI.text(c, "+%d%%" % int(float(def.bonus) * 100.0), r.position + Vector2(cw - 14.0, 30), 19, UI.GOLD, true, UI.RIGHT)
		else:
			UI.text(c, "CONTRACT", r.position + Vector2(cw - 14.0, 30), 15, UI.ORANGE, true, UI.RIGHT)
		var lines := UI.wrap_lines(str(def.desc), 17, cw - 26.0)
		UI.text(c, lines[0], r.position + Vector2(14, 60), 17, UI.TEXT_DIM)
	return y + ceilf(float(Mutators.ORDER.size()) / 2.0) * (ch + 8.0)

func _paint_loadout(c: UILayer) -> void:
	var W: float = m.W
	var content_top: float = float(m.top) + 190.0
	var y: float = content_top - c.scroll
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	var h := 92.0
	c.button("clear_slot", Rect2(x, y, w, 70), "EMPTY SLOT", Color(0.6, 0.64, 0.74), {"size": 22})
	y += 84.0
	var evolved := Cards.EVOLVED
	for id in Cards.LIST:
		var def: Dictionary = Cards.LIST[id]
		if int(def.rarity) == evolved or not Cards.unlocked(id, Save.blueprints) or id == "repair":
			continue
		var r := Rect2(x, y, w, h - 8.0)
		var color: Color = Cards.RARITY_COLORS[int(def.rarity)]
		c.hit_area("pick_" + id, r)
		UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.94), Color(color, 0.6), 12, 2)
		UI.icon(c, Cards.ICONS[def.icon], r.position + Vector2(48, 42), 66.0)
		UI.text(c, str(def.name), r.position + Vector2(96, 36), 23, UI.WHITE, true)
		UI.text(c, str(def.desc), r.position + Vector2(96, 66), 18, UI.TEXT_DIM)
		y += h
	c.scroll_max = maxf(0.0, y + c.scroll - float(m.H) + 40.0)
	m.header(c, "LOADOUT", UI.CYAN)
