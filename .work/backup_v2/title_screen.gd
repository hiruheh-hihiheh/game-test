extends Node2D
## Title, sector map, hangar and settings.

const SHIP_ART := {
	"nova": preload("res://assets/starfall/ships/player_nova_01.png"),
	"interceptor": preload("res://assets/starfall/ships/player_interceptor_02.png"),
}
const SALVAGE_ART := preload("res://assets/starfall/environment/salvage_crystal_blue.png")
const ICON_BOSS := preload("res://assets/starfall/ui_icons/icon_boss.png")
const ICON_HOME := preload("res://assets/starfall/ui_icons/icon_home.png")
const ICON_PLAY := preload("res://assets/starfall/ui_icons/icon_play.png")
const ICON_SETTINGS := preload("res://assets/starfall/ui_icons/icon_settings.png")
const ICON_MODULES := preload("res://assets/starfall/ui_icons/icon_modules.png")
const ICON_WAVE := preload("res://assets/starfall/ui_icons/icon_wave_status.png")
const ICON_HULL := preload("res://assets/starfall/ui_icons/upgrade_hull_plating.png")
const ICON_BURN := preload("res://assets/starfall/ui_icons/upgrade_afterburner.png")
const ICON_BEAM := preload("res://assets/starfall/ui_icons/upgrade_tri_beam.png")
const SHOT_ART := preload("res://assets/starfall/projectiles/projectile_player_cyan.png")
const SHIELD_ART := preload("res://assets/starfall/effects/effect_shield_orb.png")
const HANGAR_ICONS := {
	"cannon": ICON_BEAM, "rapid": ICON_BURN, "shield": SHIELD_ART,
	"hull": ICON_HULL, "magnet": SALVAGE_ART, "reactor": ICON_WAVE,
}

var W := 720.0
var H := 1280.0
var top := 20.0
var bottom := 20.0
var t := 0.0
var screen := "title"
var screen_t := 0.0
var bg_scroll := 0.0
var bg_tex: Texture2D
var bg_sector := 0
var bg: DrawLayer
var ui: UILayer
var stars_bg: Array = []
var sparks: Array = []
var spark_accum := 0.0
var launching := 0.0
var confirm_reset := false
var add_mat: CanvasItemMaterial
var fx: DrawLayer

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	_measure()
	screen = Save.menu_screen
	Save.menu_screen = "title"
	add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for i in range(110):
		stars_bg.append({"pos": Vector2(randf_range(0.0, W), randf_range(0.0, H)), "depth": randf_range(0.2, 1.0), "twinkle": randf_range(0.0, TAU)})
	bg = DrawLayer.new()
	bg.painter = _paint_background
	add_child(bg)
	fx = DrawLayer.new()
	fx.painter = _paint_fx
	fx.material = add_mat
	add_child(fx)
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	ui = UILayer.new()
	ui.painter = _paint
	ui.pressed.connect(_on_ui)
	canvas.add_child(ui)
	_set_background()
	Audio.music("menu")

func _measure() -> void:
	var s := get_viewport_rect().size
	W = s.x
	H = s.y
	var safe := UI.safe_insets(s)
	top = safe.x + 20.0
	bottom = safe.y + 20.0

func _set_background() -> void:
	var sector := Save.map_sector if screen == "map" else 1
	if sector != bg_sector:
		bg_sector = sector
		bg_tex = load("res://assets/backgrounds/sector_%d.png" % sector)

func _process(delta: float) -> void:
	_measure()
	t += delta
	screen_t += delta
	bg_scroll += delta * 12.0
	for s in stars_bg:
		var depth: float = s.depth
		s.pos.y += delta * (14.0 + 120.0 * depth * depth + launching * 1500.0 * depth)
		if s.pos.y > H + 10.0:
			s.pos = Vector2(randf_range(0.0, W), -10.0)
	if launching > 0.0:
		launching += delta * 1.7
	if screen == "title":
		spark_accum += delta
		while spark_accum > 0.03:
			spark_accum -= 0.03
			sparks.append({"pos": _ship_pos() + Vector2(randf_range(-16.0, 16.0), 72.0), "vel": Vector2(randf_range(-20.0, 20.0), randf_range(130.0, 260.0)), "life": 0.32, "color": UI.ORANGE if randf() < 0.65 else Color(1.0, 0.9, 0.5)})
	for i in range(sparks.size() - 1, -1, -1):
		var s: Dictionary = sparks[i]
		s.life -= delta
		s.pos += s.vel * delta
		if float(s.life) <= 0.0:
			sparks.remove_at(i)
	bg.queue_redraw()
	fx.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back()
		elif event.keycode in [KEY_ENTER, KEY_SPACE] and screen == "title":
			_on_ui("play")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen == "title":
			get_tree().quit()
		else:
			_back()

func _back() -> void:
	if screen != "title":
		Audio.play("ui_back")
		_go("title")

func _go(next: String) -> void:
	screen = next
	screen_t = 0.0
	confirm_reset = false
	_set_background()

func _launch() -> void:
	if launching > 0.0:
		return
	launching = 0.01
	ui.input_enabled = false
	Audio.play("whoosh", 3.0)
	Audio.play("wave_start", -3.0, 1.4)
	Fade.go("res://game.tscn")

func _on_ui(id: String) -> void:
	if id.begins_with("level"):
		Save.play_level = int(id.substr(5))
		Save.play_endless = false
		_launch()
		return
	if id.begins_with("buy_"):
		if Save.buy_upgrade(id.substr(4)):
			Audio.play("ui_buy")
			Save.vibrate(30)
		else:
			Audio.play("ui_deny")
		return
	if id.begins_with("ship_"):
		var ship_id := id.substr(5)
		if ship_id in Save.owned_ships:
			Save.ship = ship_id
			Save.save_data()
			Audio.play("ui_click")
		elif Save.buy_ship(ship_id):
			Audio.play("ui_buy")
		else:
			Audio.play("ui_deny")
		return
	match id:
		"play":
			Save.play_level = Save.unlocked
			Save.play_endless = false
			Save.map_sector = Levels.sector_of(Save.unlocked)
			_go("map")
		"map":
			_go("map")
		"hangar":
			_go("hangar")
		"settings":
			_go("settings")
		"back":
			_go("title")
		"endless":
			Save.play_endless = true
			Save.play_level = 1
			_launch()
		"prev":
			Save.map_sector = maxi(1, Save.map_sector - 1)
			screen_t = 0.0
			_set_background()
		"next":
			Save.map_sector = mini(Levels.SECTOR_COUNT, Save.map_sector + 1)
			screen_t = 0.0
			_set_background()
		"music_down":
			Save.music_volume = clampf(snappedf(Save.music_volume - 0.1, 0.1), 0.0, 1.0)
			_settings_changed()
		"music_up":
			Save.music_volume = clampf(snappedf(Save.music_volume + 0.1, 0.1), 0.0, 1.0)
			_settings_changed()
		"sound_down":
			Save.sfx_volume = clampf(snappedf(Save.sfx_volume - 0.1, 0.1), 0.0, 1.0)
			_settings_changed()
		"sound_up":
			Save.sfx_volume = clampf(snappedf(Save.sfx_volume + 0.1, 0.1), 0.0, 1.0)
			_settings_changed()
		"vibration":
			Save.vibration = not Save.vibration
			Save.save_data()
			Save.vibrate(40)
		"shake":
			Save.screen_shake = not Save.screen_shake
			Save.save_data()
		"reset":
			if confirm_reset:
				_reset_progress()
			else:
				confirm_reset = true

func _settings_changed() -> void:
	Audio.apply_volumes()
	Save.save_data()

func _reset_progress() -> void:
	confirm_reset = false
	Save.salvage = 0
	Save.best_score = 0
	Save.endless_best_wave = 0
	Save.unlocked = 1
	Save.stars = {}
	Save.upgrades = {}
	Save.ship = "nova"
	Save.owned_ships = ["nova"]
	Save.tutorial_done = false
	Save.map_sector = 1
	Save.save_data()
	Audio.play("ui_deny")

# ---------- Painting ----------

func _paint_background(c: DrawLayer) -> void:
	var th := W * 2.0
	var y := fmod(bg_scroll, th) - th
	while y < H:
		c.draw_texture_rect(bg_tex, Rect2(0, y, W, th), false, Color(0.5, 0.5, 0.6) if screen != "title" else Color(0.8, 0.8, 0.86))
		y += th
	for s in stars_bg:
		var depth: float = s.depth
		var a := (0.25 + depth * 0.65) * (0.72 + 0.28 * sin(t * 2.0 + float(s.twinkle)))
		var col := Color(0.76, 0.9, 1.0, a)
		var pos: Vector2 = s.pos
		if launching > 0.0:
			c.draw_line(pos, pos - Vector2(0, launching * 120.0 * depth), col, 1.0 + depth)
		else:
			c.draw_rect(Rect2(pos, Vector2.ONE * (1.0 + depth * 1.8)), col)

func _paint_fx(c: DrawLayer) -> void:
	for s in sparks:
		var a: float = float(s.life) / 0.32
		var size := 8.0 + a * 13.0
		c.draw_texture_rect(UI.glow_tex(), Rect2((s.pos as Vector2) - Vector2(size, size), Vector2(size, size) * 2.0), false, Color(s.color, a))

func _ship_pos() -> Vector2:
	return Vector2(W * 0.5 + sin(t * 0.9) * 10.0, H * 0.47 + sin(t * 1.3) * 12.0 - launching * launching * 900.0)

func _paint(c: UILayer) -> void:
	match screen:
		"title":
			_paint_title(c)
		"map":
			_paint_map(c)
		"hangar":
			_paint_hangar(c)
		"settings":
			_paint_settings(c)
	var fade := 1.0 - clampf(screen_t * 7.0, 0.0, 1.0)
	if fade > 0.0:
		c.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.01, 0.04, fade))

func _salvage_chip(c: UILayer, right: float, y: float) -> void:
	var value := str(Save.salvage)
	var w := UI.width_of(value, 28, true) + 74.0
	var r := Rect2(right - w, y, w, 56)
	UI.panel(c, r, Color(0.02, 0.04, 0.1, 0.84), Color(UI.MINT, 0.5), 12, 2)
	UI.icon(c, SALVAGE_ART, r.position + Vector2(32, 28), 40.0)
	UI.text(c, value, r.position + Vector2(58, 39), 28, UI.WHITE, true)

func _paint_title(c: UILayer) -> void:
	var enter := 1.0 - pow(1.0 - clampf(screen_t * 4.0, 0.0, 1.0), 3.0)
	var ship := _ship_pos()
	var title_y := H * 0.15
	UI.glow_text(c, "STARFALL", Vector2(W * 0.5, title_y + (1.0 - enter) * -50.0), 96, UI.WHITE, UI.CYAN)
	UI.glow_text(c, "SALVAGE", Vector2(W * 0.5, title_y + 88.0 + (1.0 - enter) * -50.0), 74, UI.ORANGE, UI.ORANGE)
	UI.outlined(c, "SHOOT. SURVIVE. SALVAGE.", Vector2(W * 0.5, title_y + 136.0), 23, UI.MINT, false, UI.CENTER)

	# Holographic rings turning around the ship.
	var radius := 190.0
	for i in range(3):
		var spin := t * (0.35 + float(i) * 0.14) * (1.0 if i % 2 == 0 else -1.0)
		var r := radius - float(i) * 34.0
		var col: Color = [UI.CYAN, UI.MAGENTA, UI.MINT][i]
		for k in range(3):
			var a := spin + float(k) * TAU / 3.0
			c.draw_arc(ship, r, a, a + 1.2, 28, Color(col, 0.5), 3.0, true)
	UI.glow(c, ship, 230.0, Color(UI.CYAN, 0.17))
	c.draw_set_transform(ship, sin(t * 0.8) * 0.04, Vector2.ONE)
	c.draw_texture_rect(SHIP_ART.get(Save.ship, SHIP_ART.nova), Rect2(-120, -120, 240, 240), false)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var w := minf(W - 72.0, 620.0)
	var x := (W - w) * 0.5
	var y := H - bottom - 330.0 + (1.0 - enter) * 120.0
	var label := "LEVEL %d" % Save.unlocked
	c.button("play", Rect2(x, y, w, 128), "PLAY", UI.MINT, {"primary": true, "size": 50, "sub": label, "sound": "ui_click"})
	y += 148.0
	var half := (w - 20.0) * 0.5
	c.button("hangar", Rect2(x, y, half, 96), "HANGAR", UI.CYAN, {"icon": ICON_MODULES, "size": 26})
	var endless_open := Save.unlocked >= Levels.ENDLESS_UNLOCK
	var sub := "Best wave %d" % Save.endless_best_wave if endless_open and Save.endless_best_wave > 0 else ("" if endless_open else "Reach level %d" % Levels.ENDLESS_UNLOCK)
	c.button("endless", Rect2(x + half + 20.0, y, half, 96), "ENDLESS", UI.GOLD, {"size": 26, "sub": sub, "disabled": not endless_open})
	y += 112.0
	UI.star(c, Vector2(x + 20.0, y + 13.0), 15.0, UI.GOLD)
	UI.outlined(c, "%d / %d" % [Save.total_stars(), Levels.LEVEL_COUNT * 3], Vector2(x + 44.0, y + 23.0), 22, UI.WHITE, false)
	if Save.best_score > 0:
		UI.outlined(c, "BEST %d" % Save.best_score, Vector2(x + w, y + 23.0), 22, UI.TEXT_DIM, false, UI.RIGHT)
	c.button("settings", Rect2(W - 104, top, 84, 84), "", UI.WHITE, {"icon": ICON_SETTINGS})
	_salvage_chip(c, W - 124.0, top + 14.0)

func _header(c: UILayer, title: String, accent: Color) -> void:
	c.button("back", Rect2(20, top, 84, 84), "", UI.WHITE, {"icon": ICON_HOME, "sound": "ui_back"})
	_salvage_chip(c, W - 20.0, top + 14.0)
	UI.glow_text(c, title, Vector2(W * 0.5, top + 142.0), 50, UI.WHITE, accent)

func _node_pos(i: int, y0: float, y1: float) -> Vector2:
	# A steady S-curve: left, centre, right, centre, so no two nodes ever crowd.
	var k := float(i) / float(Levels.LEVELS_PER_SECTOR - 1)
	var span := minf(W * 0.3, 210.0)
	var swing: float = [-1.0, 0.0, 1.0, 0.0][i % 4]
	return Vector2(W * 0.5 + swing * span, lerpf(y0, y1, k))

func _paint_map(c: UILayer) -> void:
	var sector := Save.map_sector
	var info: Dictionary = Levels.SECTORS[sector - 1]
	var accent: Color = info.color
	_header(c, "SECTOR %d" % sector, accent)
	UI.outlined(c, str(info.name), Vector2(W * 0.5, top + 186.0), 30, accent, true, UI.CENTER)
	UI.outlined(c, str(info.tag), Vector2(W * 0.5, top + 222.0), 20, UI.TEXT_DIM, false, UI.CENTER)
	var first := (sector - 1) * Levels.LEVELS_PER_SECTOR + 1
	var y_bottom := H - bottom - 210.0
	var y_top := top + 310.0
	var positions: Array = []
	for i in range(Levels.LEVELS_PER_SECTOR):
		positions.append(_node_pos(i, y_bottom, y_top))
	for i in range(Levels.LEVELS_PER_SECTOR - 1):
		var done := first + i < Save.unlocked
		c.draw_line(positions[i], positions[i + 1], Color(accent, 0.85) if done else Color(1, 1, 1, 0.14), 5.0 if done else 3.0, true)
	var sector_locked := first > Save.unlocked
	for i in range(Levels.LEVELS_PER_SECTOR):
		var n := first + i
		var pos: Vector2 = positions[i]
		var locked := n > Save.unlocked
		var boss := Levels.is_boss(n)
		var elite := Levels.is_elite(n)
		var current := n == Save.unlocked
		var r := 58.0 if boss else (50.0 if elite else 44.0)
		var rect := Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0)
		var id := "level%d" % n
		c.hit_area(id, rect, {"disabled": locked})
		var press := c.press_amount(id)
		c.draw_set_transform(pos, 0.0, Vector2.ONE * (1.0 - press * 0.08))
		if current:
			var pulse := 1.0 + sin(t * 4.0) * 0.12
			UI.glow(c, Vector2.ZERO, r * 2.1 * pulse, Color(accent, 0.55))
		var fill := Color(accent.darkened(0.66), 0.97) if not locked else Color(0.05, 0.06, 0.1, 0.92)
		var edge := Color(accent, 0.98) if not locked else Color(0.4, 0.44, 0.54, 0.5)
		if current:
			fill = accent.darkened(0.3)
		UI.panel(c, Rect2(-r, -r, r * 2.0, r * 2.0), fill, edge, int(r * 0.42), 3)
		if boss:
			UI.icon(c, ICON_BOSS, Vector2.ZERO, r * 1.4, Color.WHITE if not locked else Color(1, 1, 1, 0.3))
		else:
			UI.text(c, str(n), Vector2(0, 11), 31, UI.WHITE if not locked else Color(0.5, 0.54, 0.62), true, UI.CENTER)
		var earned := Save.stars_for(n)
		if earned > 0:
			for s in range(3):
				UI.star(c, Vector2((float(s) - 1.0) * 26.0, r + 15.0), 12.0, UI.GOLD if s < earned else Color(0.2, 0.22, 0.3))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var nav_y := H - bottom - 92.0
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	c.button("prev", Rect2(x, nav_y, 150, 84), "PREV", UI.CYAN, {"size": 24, "disabled": sector <= 1})
	c.button("next", Rect2(x + w - 150, nav_y, 150, 84), "NEXT", UI.CYAN, {"size": 24, "disabled": sector >= Levels.SECTOR_COUNT or (sector * Levels.LEVELS_PER_SECTOR + 1) > Save.unlocked})
	UI.star(c, Vector2(W * 0.5 - 52.0, nav_y + 38.0), 18.0, UI.GOLD)
	UI.outlined(c, "%d/30" % Save.sector_stars(sector), Vector2(W * 0.5 - 26.0, nav_y + 49.0), 28, UI.WHITE, true)
	if sector_locked:
		UI.outlined(c, "LOCKED", Vector2(W * 0.5, H * 0.5), 44, UI.RED, true, UI.CENTER)

func _paint_hangar(c: UILayer) -> void:
	_header(c, "HANGAR", UI.CYAN)
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	var y := top + 170.0
	var half := (w - 16.0) * 0.5
	var i := 0
	for ship_id in ["nova", "interceptor"]:
		var info: Dictionary = Levels.SHIPS[ship_id]
		var r := Rect2(x + float(i) * (half + 16.0), y, half, 198)
		var selected: bool = Save.ship == ship_id
		var owned: bool = ship_id in Save.owned_ships
		var color: Color = UI.MINT if selected else UI.CYAN
		c.hit_area("ship_" + ship_id, r, {"sound": ""})
		UI.panel(c, r, Color(color.darkened(0.8), 0.96), Color(color, 0.95 if selected else 0.4), 16, 3 if selected else 2, 10 if selected else 0)
		UI.glow(c, r.position + Vector2(half * 0.5, 72), 92.0, Color(color, 0.25))
		UI.icon(c, SHIP_ART[ship_id], r.position + Vector2(half * 0.5, 72), 124.0, Color.WHITE if owned else Color(0.5, 0.5, 0.6, 0.8))
		UI.text(c, str(info.name), r.position + Vector2(half * 0.5, 156), 22, UI.WHITE, true, UI.CENTER)
		if selected:
			UI.text(c, "SELECTED", r.position + Vector2(half * 0.5, 184), 18, UI.MINT, true, UI.CENTER)
		elif owned:
			UI.text(c, "TAP TO USE", r.position + Vector2(half * 0.5, 184), 18, UI.CYAN, false, UI.CENTER)
		else:
			UI.text(c, "%d SALVAGE" % int(info.cost), r.position + Vector2(half * 0.5, 184), 18, UI.GOLD if Save.salvage >= int(info.cost) else UI.TEXT_DIM, true, UI.CENTER)
		i += 1
	y += 214.0
	var available := H - bottom - y
	var row_h := minf(116.0, (available - 10.0) / float(Levels.HANGAR.size()))
	for item in Levels.HANGAR:
		var id: String = item.id
		var lvl := Save.upgrade_level(id)
		var maxed: bool = lvl >= int(item.max)
		var r := Rect2(x, y, w, row_h - 10.0)
		UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.92), Color(UI.CYAN, 0.28), 14, 2)
		UI.icon(c, HANGAR_ICONS[id], r.position + Vector2(56, r.size.y * 0.5), minf(78.0, r.size.y - 16.0))
		UI.text(c, str(item.name), r.position + Vector2(112, 36), 25, UI.WHITE, true)
		UI.text(c, str(item.desc), r.position + Vector2(112, 64), 18, UI.TEXT_DIM)
		UI.pips(c, r.position + Vector2(112, r.size.y - 22.0), int(item.max), lvl, UI.MINT, Vector2(26, 8), 5.0)
		var br := Rect2(r.end.x - 168, r.position.y + 12.0, 156, r.size.y - 24.0)
		if maxed:
			c.button("maxed_" + id, br, "MAX", UI.MINT, {"size": 24, "disabled": true})
		else:
			var cost := Levels.upgrade_cost(id, lvl)
			c.button("buy_" + id, br, str(cost), UI.GOLD if Save.salvage >= cost else Color(0.5, 0.54, 0.64), {"icon": SALVAGE_ART, "size": 24, "sound": ""})
		y += row_h

func _setting_volume(c: UILayer, y: float, x: float, w: float, label: String, id: String, value: float) -> void:
	var r := Rect2(x, y, w, 128)
	UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.92), Color(UI.CYAN, 0.28), 14, 2)
	UI.text(c, label, r.position + Vector2(24, 44), 26, UI.WHITE, true)
	UI.text(c, "OFF" if value <= 0.0 else "%d%%" % int(round(value * 100.0)), r.position + Vector2(w - 24, 44), 24, UI.CYAN, true, UI.RIGHT)
	c.button(id + "_down", Rect2(x + 20, y + 58, 76, 60), "-", UI.CYAN, {"size": 34})
	c.button(id + "_up", Rect2(x + w - 96, y + 58, 76, 60), "+", UI.CYAN, {"size": 34})
	UI.pips(c, Vector2(x + 112, y + 78), 10, int(round(value * 10.0)), UI.CYAN, Vector2((w - 224.0 - 45.0) / 10.0, 22), 5.0)

func _setting_toggle(c: UILayer, y: float, x: float, w: float, label: String, id: String, on: bool) -> void:
	var r := Rect2(x, y, w, 96)
	UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.92), Color(UI.CYAN, 0.28), 14, 2)
	UI.text(c, label, r.position + Vector2(24, 58), 26, UI.WHITE, true)
	c.button(id, Rect2(r.end.x - 158, y + 14, 140, 68), "ON" if on else "OFF", UI.MINT if on else Color(0.5, 0.54, 0.64), {"primary": on, "size": 26})

func _paint_settings(c: UILayer) -> void:
	_header(c, "SETTINGS", UI.CYAN)
	var w := minf(W - 40.0, 660.0)
	var x := (W - w) * 0.5
	var y := top + 182.0
	_setting_volume(c, y, x, w, "MUSIC", "music", Save.music_volume)
	y += 142.0
	_setting_volume(c, y, x, w, "SOUND", "sound", Save.sfx_volume)
	y += 142.0
	_setting_toggle(c, y, x, w, "VIBRATION", "vibration", Save.vibration)
	y += 110.0
	_setting_toggle(c, y, x, w, "SCREEN SHAKE", "shake", Save.screen_shake)
	y += 134.0
	c.button("reset", Rect2(x, y, w, 88), "TAP AGAIN TO ERASE EVERYTHING" if confirm_reset else "RESET PROGRESS", UI.RED, {"size": 24})
