class_name Hud
extends RefCounted
## Everything drawn over the battlefield: HUD, cards, results, pause and coaching.

const ICON_PAUSE := preload("res://assets/starfall/ui_icons/icon_pause.png")
const ICON_PLAY := preload("res://assets/starfall/ui_icons/icon_play.png")
const ICON_HOME := preload("res://assets/starfall/ui_icons/icon_home.png")
const ICON_MODULES := preload("res://assets/starfall/ui_icons/icon_modules.png")
const ICON_WAVE := preload("res://assets/starfall/ui_icons/icon_wave_status.png")
const ICON_HULL := preload("res://assets/starfall/ui_icons/upgrade_hull_plating.png")
const SALVAGE_ART := preload("res://assets/starfall/environment/salvage_crystal_blue.png")

var g
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var banner_color := UI.CYAN
var coaches: Array = []
var boss_card := {}
var boss_card_t := 0.0
var combo_flash := 0.0
var dark_tex: Texture2D

func _init(game) -> void:
	g = game

func update(dt: float) -> void:
	banner_t = maxf(0.0, banner_t - dt)
	boss_card_t = maxf(0.0, boss_card_t - dt)
	combo_flash = maxf(0.0, combo_flash - dt)
	if not coaches.is_empty():
		coaches[0].t -= dt
		if float(coaches[0].t) <= 0.0:
			coaches.remove_at(0)

func banner_show(title: String, sub: String, duration: float, color: Color) -> void:
	banner = title
	banner_sub = sub
	banner_t = duration
	banner_color = color

func coach(text: String, duration := 4.0) -> void:
	for c in coaches:
		if c.text == text:
			return
	coaches.append({"text": text, "t": duration})

func codex_toast(enemy_name: String) -> void:
	if g.phase != g.Phase.INTRO:
		g.fx.text("NEW CODEX ENTRY", Vector2(g.W * 0.5, g.top + 190.0), 22, UI.CYAN)
	Telemetry.breadcrumb("codex " + enemy_name)

func combo_milestone(n: int) -> void:
	combo_flash = 0.9
	Audio.play("combo", -3.0, 1.0 + float(n) * 0.002)
	g.fx.text("%d COMBO" % n, Vector2(g.W * 0.5, g.H * 0.4), 46, UI.GOLD)

func nova_ready_hint() -> void:
	if not Save.tutorial_seen("nova"):
		coach("NOVA READY! Tap the button to clear the screen", 5.0)
		g.time_scale = 0.5

func boss_intro(def: Dictionary) -> void:
	boss_card = def
	boss_card_t = 2.5
	if not Save.tutorial_seen("boss_" + str(def.name)):
		Save.mark_tutorial("boss_" + str(def.name))
		coach(str(def.tip), 6.0)

# ---------- Painting ----------

func paint(c: UILayer) -> void:
	var P = g.Phase
	var phase: int = g.phase
	if Mutators.flag(g.mutators, "blackout") and phase in [P.PLAYING, P.BOSS, P.WARNING]:
		_paint_blackout(c)
	if phase != P.UPGRADE and phase != P.CLEAR and phase != P.DEFEAT:
		_paint_hud(c)
	if g.hull == 1 and g.player_alive and phase != P.PAUSED:
		var a: float = 0.26 + sin(g.t * 5.0) * 0.12
		c.draw_texture_rect(UI.edge_tex(), Rect2(0, 0, 120, g.H), false, Color(UI.RED, a))
		c.draw_texture_rect(UI.edge_tex(), Rect2(g.W, 0, -120, g.H), false, Color(UI.RED, a))
	_paint_banner(c)
	if boss_card_t > 0.0:
		_paint_boss_card(c)
	_paint_tutorial(c)
	_paint_coach(c)
	match phase:
		P.UPGRADE:
			_paint_cards(c)
		P.CLEAR:
			if g.phase_t > 0.5:
				_paint_results(c)
		P.DEFEAT:
			_paint_results(c)
		P.PAUSED:
			_paint_pause(c)
		P.RESUME:
			UI.glow_text(c, "GET READY", Vector2(g.W * 0.5, g.H * 0.42), 52, UI.WHITE, UI.CYAN)
	if g.flash > 0.0:
		c.draw_rect(Rect2(0, 0, g.W, g.H), Color(g.flash_color, float(g.flash) * 0.42))

func _paint_blackout(c: UILayer) -> void:
	if dark_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.1), Color(0, 0, 0, 1)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 256
		tex.height = 256
		dark_tex = tex
	var r := 460.0
	var p: Vector2 = g.player_pos
	var box := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
	c.draw_texture_rect(dark_tex, box, false)
	c.draw_rect(Rect2(0, 0, g.W, box.position.y), Color.BLACK)
	c.draw_rect(Rect2(0, box.end.y, g.W, g.H), Color.BLACK)
	c.draw_rect(Rect2(0, box.position.y, box.position.x, r * 2.0), Color.BLACK)
	c.draw_rect(Rect2(box.end.x, box.position.y, g.W, r * 2.0), Color.BLACK)

func _paint_hud(c: UILayer) -> void:
	var W: float = g.W
	var top: float = g.top
	for i in range(int(g.max_hull)):
		var alive: bool = i < int(g.hull)
		UI.icon(c, ICON_HULL, Vector2(40.0 + float(i) * 44.0, top + 24.0), 44.0, Color.WHITE if alive else Color(0.3, 0.34, 0.44, 0.5))
	UI.bar(c, Rect2(20, top + 52.0, 232, 18), float(g.shield) / float(g.max_shield), UI.CYAN)
	var line_y := top + 96.0
	if float(g.shield) <= 0.0:
		UI.text(c, "SHIELD DOWN", Vector2(26, line_y), 18, Color(UI.RED, 0.7 + sin(g.t * 9.0) * 0.3), true)
	elif int(g.combo) >= 2:
		var size := 26 + mini(int(g.combo), 30) / 3
		UI.outlined(c, "COMBO %d" % int(g.combo), Vector2(22, top + 100.0), size, UI.GOLD, true)
		c.draw_rect(Rect2(22, top + 108.0, 180.0 * clampf(float(g.combo_timer) / 2.8, 0.0, 1.0), 4), UI.GOLD)
	UI.outlined(c, str(int(g.shown_score)), Vector2(W * 0.5, top + 42.0), 42, UI.WHITE, true, UI.CENTER)
	UI.outlined(c, _flight_label(), Vector2(W * 0.5, top + 72.0), 20, UI.TEXT_DIM, false, UI.CENTER)
	c.button("pause", Rect2(W - 92, top - 2.0, 74, 74), "", UI.WHITE, {"icon": ICON_PAUSE, "instant": true})
	UI.icon(c, SALVAGE_ART, Vector2(W - 42, top + 96.0), 36.0)
	UI.outlined(c, str(int(g.run_salvage)), Vector2(W - 64, top + 106.0), 26, UI.MINT, true, UI.RIGHT)
	var prog: String = g.objective_progress()
	if not prog.is_empty() and g.boss == null:
		var col: Color = UI.MINT if g.objective_done() else UI.TEXT_DIM
		UI.star(c, Vector2(W * 0.5 - 40.0, top + 96.0), 10.0, col)
		UI.outlined(c, prog, Vector2(W * 0.5 - 24.0, top + 103.0), 20, col, false)
	if g.boss != null:
		_paint_boss_bar(c)
	_paint_build_tray(c)
	_paint_nova(c)

func _flight_label() -> String:
	if g.mode == "endless":
		return "WAVE %d" % int(g.endless_wave)
	var total: int = (g.level.waves as Array).size()
	var base: String = "LEVEL %d" % int(g.level_num) if g.mode == "campaign" else str(g.level.name)
	return base + ("  ·  %d/%d" % [int(g.wave_index) + 1, total] if total > 1 else "")

func _paint_build_tray(c: UILayer) -> void:
	var y: float = g.H - 46.0 - float(g.inset.y)
	var x := 32.0 if str(Save.opt.nova_side) == "right" else float(g.W) - 32.0
	var dir := 1.0 if str(Save.opt.nova_side) == "right" else -1.0
	for id in g.held:
		var def: Dictionary = Cards.LIST[id]
		UI.panel(c, Rect2(x - 20.0, y - 20.0, 40, 40), Color(0.02, 0.03, 0.08, 0.7), Color(Cards.RARITY_COLORS[int(def.rarity)], 0.7), 8, 2)
		UI.icon(c, Cards.ICONS[def.icon], Vector2(x, y), 32.0)
		x += 46.0 * dir

func _paint_boss_bar(c: UILayer) -> void:
	var y: float = float(g.top) + 134.0
	var w: float = g.W
	var r := Rect2(40, y, w - 80, 22)
	var boss = g.boss
	UI.outlined(c, str(boss.def.name), Vector2(w * 0.5, y - 8.0), 22, Color(1.0, 0.8, 0.86), true, UI.CENTER)
	UI.bar(c, r, float(boss.hp) / float(boss.max_hp), UI.MAGENTA)
	for k in BossBase.STAGE_AT:
		var x: float = r.position.x + r.size.x * float(k)
		c.draw_line(Vector2(x, y), Vector2(x, y + 22.0), Color(1, 1, 1, 0.65), 2.0)

func nova_center() -> Vector2:
	var left := str(Save.opt.nova_side) == "left"
	return Vector2(92.0 if left else float(g.W) - 92.0, float(g.H) - 104.0 - float(g.inset.y))

func _paint_nova(c: UILayer) -> void:
	var center := nova_center()
	var ready: bool = float(g.energy) >= 100.0
	var r := 64.0
	if ready:
		c.hit_area("burst", Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), {"instant": true, "sound": ""})
		UI.glow(c, center, r * 1.8 + sin(g.t * 6.0) * 10.0, Color(UI.CYAN, 0.5))
	c.draw_circle(center, r, Color(0.02, 0.05, 0.12, 0.82))
	c.draw_arc(center, r - 4.0, 0.0, TAU, 48, Color(UI.CYAN, 0.2), 6.0, true)
	c.draw_arc(center, r - 4.0, -PI * 0.5, -PI * 0.5 + TAU * float(g.energy) / 100.0, 48, UI.MINT if ready else UI.CYAN, 7.0, true)
	UI.icon(c, ICON_WAVE, center + Vector2(0, -12), 70.0, Color.WHITE if ready else Color(1, 1, 1, 0.45))
	UI.text(c, "NOVA" if ready else "%d%%" % int(g.energy), center + Vector2(0, 34), 20, UI.WHITE if ready else UI.TEXT_DIM, true, UI.CENTER)

func _paint_banner(c: UILayer) -> void:
	if banner_t <= 0.0:
		return
	var a := clampf(banner_t * 3.5, 0.0, 1.0)
	var y: float = float(g.H) * 0.34
	var w: float = 600.0 * a * a
	var mid: float = float(g.W) * 0.5
	c.draw_rect(Rect2(mid - w * 0.5, y - 92.0, w, 3), Color(banner_color, a * 0.9))
	c.draw_rect(Rect2(mid - w * 0.5, y + (38.0 if not banner_sub.is_empty() else 18.0), w, 3), Color(banner_color, a * 0.9))
	var size := 66 if banner.length() < 14 else 46
	UI.glow_text(c, banner, Vector2(mid, y - 14.0), size, Color(1, 1, 1, a), banner_color)
	if not banner_sub.is_empty():
		UI.outlined(c, banner_sub, Vector2(mid, y + 24.0), 25, Color(banner_color, a), false, UI.CENTER)

func _paint_boss_card(c: UILayer) -> void:
	var a := clampf(boss_card_t * 2.5, 0.0, 1.0) * clampf((2.5 - boss_card_t) * 4.0, 0.0, 1.0)
	var w: float = g.W
	var y: float = float(g.H) * 0.56
	c.draw_rect(Rect2(0, y - 92.0, w, 178.0), Color(0.0, 0.0, 0.02, 0.76 * a))
	c.draw_rect(Rect2(0, y - 92.0, w, 3), Color(UI.RED, a))
	c.draw_rect(Rect2(0, y + 84.0, w, 3), Color(UI.RED, a))
	UI.outlined(c, str(boss_card.epithet).to_upper(), Vector2(w * 0.5, y - 50.0), 22, Color(UI.ORANGE, a), false, UI.CENTER)
	UI.glow_text(c, str(boss_card.name), Vector2(w * 0.5, y + 6.0), 44, Color(1, 1, 1, a), UI.RED)
	UI.outlined(c, "\"%s\"" % str(boss_card.taunt), Vector2(w * 0.5, y + 56.0), 24, Color(UI.WHITE, a), false, UI.CENTER)

func _paint_coach(c: UILayer) -> void:
	if coaches.is_empty():
		return
	var entry: Dictionary = coaches[0]
	var a := clampf(float(entry.t) * 3.0, 0.0, 1.0)
	var w: float = minf(float(g.W) - 60.0, 640.0)
	var lines := UI.wrap_lines(str(entry.text), 24, w - 50.0)
	var h := 26.0 + float(lines.size()) * 32.0
	var y: float = float(g.H) * 0.67
	var x: float = (float(g.W) - w) * 0.5
	UI.panel(c, Rect2(x, y, w, h), Color(0.02, 0.04, 0.1, 0.88 * a), Color(UI.CYAN, 0.8 * a), 12, 2)
	for i in range(lines.size()):
		UI.text(c, lines[i], Vector2(float(g.W) * 0.5, y + 36.0 + float(i) * 32.0), 24, Color(UI.WHITE, a), false, UI.CENTER)

func _paint_tutorial(c: UILayer) -> void:
	if Save.tutorial_seen("move") or g.mode != "campaign":
		return
	if float(g.touch_moved) > 500.0:
		Save.mark_tutorial("move")
		return
	if g.phase != g.Phase.PLAYING:
		return
	var W: float = g.W
	var y: float = float(g.H) * 0.5 - 60.0
	var hand := Vector2(W * 0.5 + sin(g.t * 2.4) * 150.0, y + 60.0)
	c.draw_line(Vector2(W * 0.5 - 170.0, y + 60.0), Vector2(W * 0.5 + 170.0, y + 60.0), Color(UI.CYAN, 0.35), 3.0)
	UI.glow(c, hand, 56.0, Color(UI.CYAN, 0.5))
	c.draw_circle(hand, 22.0, Color(1, 1, 1, 0.85))
	UI.outlined(c, "DRAG ANYWHERE TO MOVE", Vector2(W * 0.5, y), 30, UI.WHITE, true, UI.CENTER)
	UI.outlined(c, "Your ship fires by itself", Vector2(W * 0.5, y + 118.0), 22, UI.TEXT_DIM, false, UI.CENTER)

## Elite marks use shapes as well as colour, so they read for colour-blind players.
func paint_mod_mark(c: CanvasItem, e: Dictionary) -> void:
	var mod: Dictionary = Enemies.MODS[e.mod]
	var col: Color = mod.color
	var at: Vector2 = e.pos
	var r: float = float(e.r) + 12.0
	match str(mod.mark):
		"ring":
			if float(e.eshield) > 0.0:
				c.draw_arc(at, r, 0.0, TAU, 40, col, 5.0, true)
		"chevron":
			for side in [-1.0, 1.0]:
				var x: Vector2 = at + Vector2(float(side) * (r + 4.0), 0)
				c.draw_polyline(PackedVector2Array([x + Vector2(-float(side) * 14.0, -12), x, x + Vector2(-float(side) * 14.0, 12)]), col, 4.0)
		"cross":
			var top: Vector2 = at + Vector2(0, -r - 8.0)
			c.draw_line(top + Vector2(-10, 0), top + Vector2(10, 0), col, 5.0)
			c.draw_line(top + Vector2(0, -10), top + Vector2(0, 10), col, 5.0)
		"spikes":
			for i in range(8):
				var d := Vector2.from_angle(float(i) * TAU / 8.0 + float(g.t))
				c.draw_line(at + d * r, at + d * (r + 12.0), col, 4.0)

func _paint_cards(c: UILayer) -> void:
	var W: float = g.W
	var H: float = g.H
	var phase_t: float = g.phase_t
	var a := clampf(phase_t * 5.0, 0.0, 1.0)
	c.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.01, 0.04, 0.84 * a))
	var options: Array = g.card_options
	var count := options.size()
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	var h := 174.0 if count >= 4 else 196.0
	var gap := 18.0
	var total := float(count) * h + float(count - 1) * gap
	var y0 := H * 0.5 - total * 0.5 + 34.0
	UI.glow_text(c, "MODULE BAY", Vector2(W * 0.5, y0 - 62.0), 50, Color(1, 1, 1, a), UI.CYAN)
	UI.text(c, "Pick one upgrade for this flight", Vector2(W * 0.5, y0 - 24.0), 22, Color(UI.MINT, a), false, UI.CENTER)
	for i in range(count):
		_paint_card(c, i, options[i], x, y0 + float(i) * (h + gap), w, h)
	var by := y0 + total + 22.0
	if int(g.rerolls) > 0:
		c.button("reroll", Rect2(W * 0.5 - 130.0, by, 260, 70), "REROLL (%d)" % int(g.rerolls), UI.GOLD, {"size": 24, "sound": ""})

func _paint_card(c: UILayer, i: int, id: String, x: float, y: float, w: float, h: float) -> void:
	var def: Dictionary = Cards.LIST[id]
	var rarity: int = def.rarity
	var color: Color = Cards.RARITY_COLORS[rarity]
	var delay := float(i) * 0.09
	var k := clampf((float(g.phase_t) - delay) * 4.5, 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 3.0)
	var rect := Rect2(x + (1.0 - k) * float(g.W) * (1.0 if i % 2 == 0 else -1.0), y, w, h)
	var card_id := "card%d" % i
	c.hit_area(card_id, rect, {"sound": ""})
	var picked: bool = g.card_picked == i
	var fade := 0.28 if int(g.card_picked) >= 0 and not picked else 1.0
	var scale_by := 1.0 - c.press_amount(card_id) * 0.03 + (0.03 if picked else 0.0)
	c.draw_set_transform(rect.get_center(), 0.0, Vector2(scale_by, scale_by))
	var r := Rect2(-rect.size * 0.5, rect.size)
	var fill := Color(color.darkened(0.8), 0.98 * fade)
	if picked:
		fill = color.darkened(0.45)
	UI.panel(c, r, fill, Color(color, 0.95 * fade), 18, 3 if rarity < Cards.EVOLVED else 5, 16 if picked or rarity >= Cards.EPIC else 0)
	var icon_at := r.position + Vector2(92, h * 0.5)
	UI.glow(c, icon_at, 92.0, Color(color, 0.3 * fade))
	UI.icon(c, Cards.ICONS[def.icon], icon_at, 118.0, Color(1, 1, 1, fade))
	var tx := r.position.x + 176.0
	UI.text(c, Cards.RARITY_NAMES[rarity], Vector2(tx, r.position.y + 32.0), 17, Color(color, fade), true)
	UI.text(c, str(def.name), Vector2(tx, r.position.y + 68.0), 30, Color(UI.WHITE, fade), true)
	var lines := UI.wrap_lines(str(def.desc), 21, w - 196.0)
	for l in range(mini(lines.size(), 2)):
		UI.text(c, lines[l], Vector2(tx, r.position.y + 100.0 + float(l) * 27.0), 21, Color(UI.TEXT_DIM, fade))
	var syn := Cards.synergy_for(id, g.held)
	var chip_y := r.position.y + h - 26.0
	if rarity == Cards.EVOLVED:
		UI.text(c, "EVOLUTION UNLOCKED", Vector2(tx, chip_y + 6.0), 18, Color(UI.GOLD, fade), true)
	elif not syn.is_empty():
		var other: String = Cards.LIST[syn.other].name
		var evo: String = Cards.LIST[syn.evo].name
		var text: String = ("EVOLVES INTO %s" % evo) if syn.ready else ("PAIRS WITH %s" % other)
		UI.text(c, text, Vector2(tx, chip_y + 6.0), 18, Color(UI.GOLD if syn.ready else UI.MINT, fade), true)
	else:
		UI.pips(c, Vector2(tx, chip_y - 4.0), mini(int(def.max), 6), int(g.held.get(id, 0)), Color(color, fade))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _paint_results(c: UILayer) -> void:
	var win: bool = g.result_win
	var W: float = g.W
	var H: float = g.H
	var k := clampf((float(g.phase_t) - (0.5 if win else 0.0)) * 3.5, 0.0, 1.0)
	c.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.01, 0.04, 0.86 * k))
	var w := minf(W - 48.0, 672.0)
	var x := (W - w) * 0.5
	var color: Color = UI.MINT if win else UI.RED
	var offset := (1.0 - k) * 60.0
	var y := float(g.top) + maxf(50.0, H * 0.1)
	var title := "LEVEL CLEAR" if win else "SIGNAL LOST"
	if win and g.level_num == Levels.LEVEL_COUNT and g.mode == "campaign":
		title = "YOU WON"
	UI.glow_text(c, title, Vector2(W * 0.5, y + offset), 60, Color(1, 1, 1, k), color)
	y += 44.0
	UI.text(c, str(g.level.get("name", "")), Vector2(W * 0.5, y + offset), 23, Color(color, k), false, UI.CENTER)
	y += 26.0
	var panel_h := 330.0 if g.mode in ["campaign", "side"] and win else 214.0
	var panel := Rect2(x, y + offset, w, panel_h)
	UI.panel(c, panel, Color(0.03, 0.05, 0.12, 0.97 * k), Color(color, 0.7 * k), 20, 2, 12)
	var row := panel.position.y + 42.0
	if g.mode in ["campaign", "side"] and win:
		row = _paint_star_rows(c, x, row, w, k)
	row = _stat_row(c, x, row, w, "SCORE", str(g.score), UI.WHITE, k)
	if float(g.score_mult) > 1.0:
		UI.text(c, "x%.2f DIALS" % float(g.score_mult), Vector2(x + 150.0, row - 46.0), 19, Color(UI.GOLD, k), false)
	row = _stat_row(c, x, row, w, "SALVAGE", "+%d" % int(g.run_salvage), UI.MINT, k)
	row = _stat_row(c, x, row, w, "BEST COMBO", str(g.best_combo), UI.GOLD, k)
	if g.mode == "endless":
		_stat_row(c, x, row, w, "WAVE", str(g.endless_wave), UI.GOLD, k)
	var ry := panel.end.y + 18.0
	for r in g.rewards:
		_paint_reward(c, Rect2(x, ry, w, 66), r, k)
		ry += 74.0
	if k < 1.0:
		return
	_result_buttons(c, x, maxf(ry + 8.0, panel.end.y + 26.0), w, win)

func _paint_star_rows(c: UILayer, x: float, y: float, w: float, k: float) -> float:
	var labels := ["Level cleared", "No hull lost", Levels.objective_text(g.level.get("obj", []))]
	var row := y
	var shown := 0
	for bit in range(3):
		var earned: bool = int(g.result_mask) & (1 << bit) != 0
		var lit := earned
		if earned:
			shown += 1
			lit = shown <= int(g.stars_shown)
		var at := Vector2(x + 52.0, row - 8.0)
		if lit:
			UI.glow(c, at, 44.0, Color(UI.GOLD, 0.5))
		UI.star(c, at, 22.0, UI.GOLD if lit else Color(0.2, 0.24, 0.34, k))
		UI.text(c, labels[bit], Vector2(x + 86.0, row), 22, Color(UI.WHITE if earned else UI.TEXT_DIM, k), false)
		row += 42.0
	return row + 18.0

func _stat_row(c: UILayer, x: float, y: float, w: float, label: String, value: String, color: Color, k: float) -> float:
	UI.text(c, label, Vector2(x + 36.0, y), 22, Color(UI.TEXT_DIM, k), true)
	UI.text(c, value, Vector2(x + w - 36.0, y), 30, Color(color, k), true, UI.RIGHT)
	return y + 46.0

func _paint_reward(c: UILayer, r: Rect2, reward: Dictionary, k: float) -> void:
	UI.panel(c, r, Color(0.1, 0.08, 0.02, 0.96 * k), Color(UI.GOLD, 0.9 * k), 14, 3, 10)
	UI.text(c, str(reward.title), r.position + Vector2(26, 28), 19, Color(UI.GOLD, k), true)
	UI.text(c, str(reward.detail), r.position + Vector2(26, 54), 23, Color(UI.WHITE, k), false)

func _result_buttons(c: UILayer, x: float, y: float, w: float, win: bool) -> void:
	var half := (w - 20.0) * 0.5
	var mode: String = g.mode
	if win and mode == "campaign" and g.level_num < Levels.LEVEL_COUNT:
		c.button("next", Rect2(x, y, w, 96), "NEXT LEVEL", UI.MINT, {"primary": true, "icon": ICON_PLAY, "size": 32})
		c.button("retry", Rect2(x, y + 112.0, half, 80), "REPLAY", UI.CYAN, {"size": 25})
		c.button("hangar", Rect2(x + half + 20.0, y + 112.0, half, 80), "HANGAR", UI.CYAN, {"size": 25})
	elif win:
		c.button("map", Rect2(x, y, w, 96), "CONTINUE", UI.MINT, {"primary": true, "size": 32})
	else:
		var retry_mode: bool = mode != "expedition"
		if retry_mode:
			c.button("retry", Rect2(x, y, w, 96), "TRY AGAIN", UI.ORANGE, {"primary": true, "icon": ICON_PLAY, "size": 32})
			c.button("hangar", Rect2(x, y + 112.0, half, 80), "HANGAR", UI.CYAN, {"size": 25})
			c.button("map", Rect2(x + half + 20.0, y + 112.0, half, 80), "MAP" if mode == "campaign" else "MENU", UI.CYAN, {"size": 25})
		else:
			c.button("map", Rect2(x, y, w, 96), "END EXPEDITION", UI.ORANGE, {"primary": true, "size": 30})

func _paint_pause(c: UILayer) -> void:
	var W: float = g.W
	var H: float = g.H
	c.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.01, 0.04, 0.86))
	var w := minf(W - 80.0, 580.0)
	var x := (W - w) * 0.5
	var y := H * 0.5 - 390.0
	UI.glow_text(c, "PAUSED", Vector2(W * 0.5, y), 62, UI.WHITE, UI.CYAN)
	UI.text(c, _flight_label(), Vector2(W * 0.5, y + 38.0), 23, UI.MINT, false, UI.CENTER)
	var obj: String = Levels.objective_text(g.level.get("obj", []))
	if not obj.is_empty():
		UI.star(c, Vector2(W * 0.5 - UI.width_of(obj, 21) * 0.5 - 20.0, y + 68.0), 11.0, UI.GOLD)
		UI.text(c, obj, Vector2(W * 0.5, y + 76.0), 21, UI.TEXT_DIM, false, UI.CENTER)
	y += 104.0
	c.button("resume", Rect2(x, y, w, 104), "RESUME", UI.MINT, {"primary": true, "icon": ICON_PLAY, "size": 36})
	y += 120.0
	if g.mode != "expedition":
		c.button("retry", Rect2(x, y, w, 84), "RESTART", UI.CYAN, {"size": 27})
		y += 100.0
	var half := (w - 18.0) * 0.5
	var music_on: bool = float(Save.opt.music_volume) > 0.0
	var sound_on: bool = float(Save.opt.sfx_volume) > 0.0
	c.button("music", Rect2(x, y, half, 80), "MUSIC ON" if music_on else "MUSIC OFF", UI.CYAN if music_on else Color(0.5, 0.54, 0.64), {"size": 22})
	c.button("sound", Rect2(x + half + 18.0, y, half, 80), "SOUND ON" if sound_on else "SOUND OFF", UI.CYAN if sound_on else Color(0.5, 0.54, 0.64), {"size": 22})
	y += 96.0
	c.button("map", Rect2(x, y, w, 84), "QUIT FLIGHT", UI.RED, {"icon": ICON_HOME, "size": 27, "sound": "ui_back"})
	y += 106.0
	if not (g.held as Dictionary).is_empty():
		UI.text(c, "YOUR BUILD", Vector2(W * 0.5, y), 19, UI.TEXT_DIM, true, UI.CENTER)
		var ids: Array = g.held.keys()
		var bx: float = W * 0.5 - float(ids.size() - 1) * 26.0
		for i in range(ids.size()):
			var def: Dictionary = Cards.LIST[ids[i]]
			UI.icon(c, Cards.ICONS[def.icon], Vector2(bx + float(i) * 52.0, y + 36.0), 46.0)
