extends Node2D
## The menu hub: title screen, and the host for every other menu page.

const SALVAGE_ART := preload("res://assets/starfall/environment/salvage_crystal_blue.png")
const ICON_HOME := preload("res://assets/starfall/ui_icons/icon_home.png")
const ICON_SETTINGS := preload("res://assets/starfall/ui_icons/icon_settings.png")
const ICON_MODULES := preload("res://assets/starfall/ui_icons/icon_modules.png")
const ICON_WAVE := preload("res://assets/starfall/ui_icons/icon_wave_status.png")
const HUE_SHADER := preload("res://src/hue.gdshader")

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
var add_mat: CanvasItemMaterial
var fx: DrawLayer
var pages := {}
var materials := {}

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
	pages = {
		"map": MenuMap.new(self), "preflight": MenuMap.new(self), "hangar": MenuHangar.new(self),
		"ops": MenuOps.new(self), "expedition": MenuExpedition.new(self), "settings": MenuSettings.new(self),
	}
	pages.preflight = pages.map
	pages["loadout"] = pages.map
	_set_background()
	_focus_art(screen)
	if pages.has(screen) and pages[screen].has_method("on_enter"):
		pages[screen].on_enter()
	Meta.refresh_contracts()
	Meta.sync_collection_stats()
	Audio.music("menu")

func _measure() -> void:
	var s := get_viewport_rect().size
	W = s.x
	H = s.y
	var safe := UI.safe_insets(s)
	top = safe.x + 20.0
	bottom = safe.y + 20.0

func _set_background() -> void:
	var sector := Save.map_sector if screen in ["map", "preflight", "loadout"] else 1
	if sector != bg_sector:
		bg_sector = sector
		bg_tex = load("res://assets/backgrounds/sector_%d.png" % sector)

func hue_mat(hue: float) -> ShaderMaterial:
	if not materials.has(hue):
		var m := ShaderMaterial.new()
		m.shader = HUE_SHADER
		m.set_shader_parameter("hue", hue)
		materials[hue] = m
	return materials[hue]

## Pages that show no illustrations let go of the big ones. The title keeps the gear art warm.
func _focus_art(page: String) -> void:
	if page == "hangar":
		return # The Hangar chooses by tab.
	if page in ["preflight", "expedition", "ops"]:
		UIArt.focus(["danger"])
		return
	UIArt.focus([], ["loot"] if page == "title" else [])

func _process(delta: float) -> void:
	_measure()
	UIArt.pump()
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
			back()
		elif event.keycode in [KEY_ENTER, KEY_SPACE] and screen == "title":
			_on_ui("play")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen == "title":
			get_tree().quit()
		else:
			back()

func back() -> void:
	if screen == "title":
		return
	Audio.play("ui_back")
	var parent := "title"
	if screen == "preflight":
		parent = "map"
	elif screen == "loadout":
		parent = "preflight"
	go(parent)

func go(next: String) -> void:
	screen = next
	screen_t = 0.0
	ui.reset_scroll()
	_set_background()
	_focus_art(next)
	if pages.has(next) and pages[next].has_method("on_enter"):
		pages[next].on_enter()

func launch(session: Dictionary) -> void:
	if launching > 0.0:
		return
	Save.session = session
	launching = 0.01
	ui.input_enabled = false
	Audio.play("whoosh", 3.0)
	Audio.play("wave_start", -3.0, 1.4)
	Save.save_data()
	Fade.go("res://game.tscn")

func _on_ui(id: String) -> void:
	match id:
		"play":
			Save.map_sector = Levels.sector_of(Save.unlocked)
			go("map")
		"hangar":
			go("hangar")
		"ops":
			go("ops")
		"settings":
			go("settings")
		"expedition":
			go("expedition")
		"back":
			back()
		"endless":
			go("preflight")
			(pages.map as MenuMap).open_endless()
		_:
			if pages.has(screen):
				pages[screen].on_ui(id)

# ---------- Painting ----------

func _paint_background(c: DrawLayer) -> void:
	var th := W * 2.0
	var y := fmod(bg_scroll, th) - th
	var tint := Color(0.8, 0.8, 0.86) if screen == "title" else Color(0.42, 0.42, 0.52)
	while y < H:
		c.draw_texture_rect(bg_tex, Rect2(0, y, W, th), false, tint)
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
	return Vector2(W * 0.5 + sin(t * 0.9) * 10.0, H * 0.43 + sin(t * 1.3) * 12.0 - launching * launching * 900.0)

func _paint(c: UILayer) -> void:
	if screen == "title":
		_paint_title(c)
	elif pages.has(screen):
		pages[screen].paint(c)
	var fade := 1.0 - clampf(screen_t * 7.0, 0.0, 1.0)
	if fade > 0.0:
		c.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.01, 0.04, fade))

func salvage_chip(c: UILayer, right: float, y: float) -> void:
	var value := str(Save.salvage)
	var w := UI.width_of(value, 28, true) + 74.0
	var r := Rect2(right - w, y, w, 56)
	UI.panel(c, r, Color(0.02, 0.04, 0.1, 0.84), Color(UI.MINT, 0.5), 12, 2)
	UI.icon(c, SALVAGE_ART, r.position + Vector2(32, 28), 40.0)
	UI.text(c, value, r.position + Vector2(58, 39), 28, UI.WHITE, true)

## Page header: home button, salvage and title, with a strip that hides scrolled content.
func header(c: UILayer, title: String, accent: Color) -> float:
	c.draw_rect(Rect2(0, 0, W, top + 176.0), Color(0.01, 0.01, 0.05, 0.86))
	c.draw_rect(Rect2(0, top + 176.0, W, 2), Color(accent, 0.4))
	c.button("back", Rect2(20, top, 84, 84), "", UI.WHITE, {"icon": ICON_HOME, "sound": "ui_back"})
	salvage_chip(c, W - 20.0, top + 14.0)
	UI.glow_text(c, title, Vector2(W * 0.5, top + 146.0), 46, UI.WHITE, accent)
	return top + 190.0

func pilot_chip(c: UILayer, x: float, y: float) -> void:
	var info: Dictionary = Pilot.level_of(Save.pilot_xp)
	var r := Rect2(x, y, 190, 56)
	UI.panel(c, r, Color(0.02, 0.04, 0.1, 0.84), Color(UI.CYAN, 0.5), 12, 2)
	UIArt.draw(c, "rank", r.position + Vector2(27, 20), 26.0, {"animate": false})
	UI.text(c, "PILOT %d" % int(info.level), r.position + Vector2(48, 25), 20, UI.WHITE, true)
	UI.bar(c, Rect2(r.position + Vector2(14, 34), Vector2(162, 12)), float(info.into) / float(info.need), UI.CYAN)

## A count pill tucked inside the top-right corner of a card, clear of the border, the seam and the art.
func badge(c: UILayer, card: Rect2, count: int) -> void:
	if count <= 0:
		return
	var label := str(count) if count < 100 else "99+"
	var w := maxf(34.0, UI.width_of(label, 20, true) + 20.0)
	var r := Rect2(card.end.x - 14.0 - w, card.position.y + 12.0, w, 30.0)
	UI.panel(c, r, Color(0.78, 0.1, 0.2, 1.0), Color(1.0, 0.72, 0.74, 0.95), 15, 2)
	UI.text(c, label, r.get_center() + Vector2(0, 7), 20, UI.WHITE, true, UI.CENTER)

func _cheapest_upgrade_ready() -> bool:
	if Save.unlocked < 3:
		return false
	for item in Hangar.LIST:
		var lvl := Save.upgrade_level(item.id)
		if lvl < int(item.max) and Save.total_stars() >= Hangar.stars_needed(item.id) and Save.salvage >= Hangar.cost(item.id, lvl):
			return true
	return false

func _paint_title(c: UILayer) -> void:
	var enter := 1.0 - pow(1.0 - clampf(screen_t * 4.0, 0.0, 1.0), 3.0)
	var ship := _ship_pos()
	var title_y := top + H * 0.12
	UI.glow_text(c, "STARFALL", Vector2(W * 0.5, title_y + (1.0 - enter) * -50.0), 92, UI.WHITE, UI.CYAN)
	UI.glow_text(c, "SALVAGE", Vector2(W * 0.5, title_y + 84.0 + (1.0 - enter) * -50.0), 70, UI.ORANGE, UI.ORANGE)
	var radius := 176.0
	for i in range(3):
		var spin := t * (0.35 + float(i) * 0.14) * (1.0 if i % 2 == 0 else -1.0)
		var r := radius - float(i) * 32.0
		var col: Color = [UI.CYAN, UI.MAGENTA, UI.MINT][i]
		for k in range(3):
			var a := spin + float(k) * TAU / 3.0
			c.draw_arc(ship, r, a, a + 1.2, 28, Color(col, 0.5), 3.0, true)
	UI.glow(c, ship, 220.0, Color(UI.CYAN, 0.17))
	c.draw_set_transform(ship, sin(t * 0.8) * 0.04, Vector2.ONE)
	c.draw_texture_rect(Ships.ART.get(Save.ship, Ships.ART.nova), Rect2(-112, -112, 224, 224), false)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var w := minf(W - 64.0, 630.0)
	var x := (W - w) * 0.5
	var y := H - bottom - 430.0 + (1.0 - enter) * 120.0
	var half := (w - 18.0) * 0.5
	c.button("play", Rect2(x, y, w, 122), "PLAY", UI.MINT, {"primary": true, "size": 48, "sub": "LEVEL %d" % Save.unlocked})
	y += 138.0
	c.button("hangar", Rect2(x, y, half, 94), "HANGAR", UI.CYAN, {"art": "hangar", "art_size": 60, "size": 25})
	badge(c, Rect2(x, y, half, 94), (1 if _cheapest_upgrade_ready() else 0) + Save.new_gear_count())
	c.button("ops", Rect2(x + half + 18.0, y, half, 94), "OPS", UI.CYAN, {"art": "ops", "art_size": 60, "size": 25})
	badge(c, Rect2(x + half + 18.0, y, half, 94), Meta.claimable_contracts())
	y += 110.0
	var exp_open := Save.unlocked >= Levels.EXPEDITION_UNLOCK
	var end_open := Save.unlocked >= Levels.ENDLESS_UNLOCK
	var exp_sub := ("Run in progress" if Expedition.active() else "Roguelite runs") if exp_open else "Reach level %d" % Levels.EXPEDITION_UNLOCK
	var end_sub := ("Best floor %d" % Save.endless_best_wave if Save.endless_best_wave > 0 else "Climb the floors") if end_open else "Reach level %d" % Levels.ENDLESS_UNLOCK
	c.button("expedition", Rect2(x, y, half, 94), "EXPEDITION", UI.MAGENTA, {"art": "expedition", "art_size": 60, "size": 23, "sub": exp_sub, "disabled": not exp_open})
	c.button("endless", Rect2(x + half + 18.0, y, half, 94), "RIFT", UI.GOLD, {"art": "rift", "art_size": 60, "size": 23, "sub": end_sub, "disabled": not end_open})
	y += 112.0
	UI.star(c, Vector2(x + 20.0, y + 13.0), 15.0, UI.GOLD)
	UI.outlined(c, "%d / %d" % [Save.total_stars(), Levels.LEVEL_COUNT * 3], Vector2(x + 44.0, y + 23.0), 22, UI.WHITE, false)
	UI.outlined(c, str(Meta.season().name), Vector2(x + w, y + 23.0), 20, UI.TEXT_DIM, false, UI.RIGHT)
	c.button("settings", Rect2(W - 104, top, 84, 84), "", UI.WHITE, {"icon": ICON_SETTINGS})
	salvage_chip(c, W - 124.0, top + 14.0)
	pilot_chip(c, 20.0, top + 14.0)
