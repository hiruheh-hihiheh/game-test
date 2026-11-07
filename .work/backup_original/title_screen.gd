extends Node2D

const BG = null
const UI_FONT = null
const MEDIUM_FONT = null
const BOLD_FONT = null
const TITLE_FONT = null
const PLAYER_ART = preload("res://assets/starfall/ships/player_nova_01.png")

const W := 720.0
const H := 1280.0
const LAUNCH_RECT := Rect2(64, 930, 592, 96)
const CYAN := Color(0.24, 0.92, 1.0)
const MINT := Color(0.30, 1.0, 0.78)
const ORANGE := Color(1.0, 0.55, 0.25)
const MAGENTA := Color(1.0, 0.28, 0.64)

var bg_sprite: Sprite2D
var stars: Array = []
var particles: Array = []
var t := 0.0
var starting := false
var best_score := 0
var launch_hover := false
var ship_art: Sprite2D

func _ready() -> void:
	randomize()
	for i in range(110):
		stars.append({"pos": Vector2(randf_range(0.0, W), randf_range(0.0, H)), "speed": randf_range(20.0, 100.0), "size": randf_range(0.7, 2.6), "alpha": randf_range(0.25, 0.9)})
	for i in range(18):
		particles.append({"pos": Vector2(randf_range(90.0, W - 90.0), randf_range(230.0, 720.0)), "vel": Vector2(randf_range(-14.0, 14.0), randf_range(-24.0, 24.0)), "life": randf_range(1.0, 3.0), "max": 3.0})
	ship_art = Sprite2D.new()
	ship_art.texture = PLAYER_ART
	ship_art.scale = Vector2(0.20, 0.20)
	ship_art.position = Vector2(W * 0.5, 555.0)
	ship_art.z_index = -2
	add_child(ship_art)
	var config := ConfigFile.new()
	if config.load("user://starfall_save.cfg") == OK:
		best_score = int(config.get_value("progress", "best_score", 0))
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()

func _process(delta: float) -> void:
	t += delta
	if bg_sprite:
		bg_sprite.position = Vector2(W * 0.5 + sin(t * 0.07) * 10.0, H * 0.5 + cos(t * 0.05) * 8.0)
	ship_art.position = Vector2(W * 0.5 + sin(t * 1.5) * 9.0, 555.0 + cos(t * 1.1) * 7.0)
	ship_art.rotation = sin(t * 0.8) * 0.025
	for s in stars:
		s.pos.y += s.speed * delta
		if s.pos.y > H + 24.0:
			s.pos.y = -24.0
			s.pos.x = randf_range(0.0, W)
	for p in particles:
		p.pos += p.vel * delta
		p.life -= delta
		if p.life <= 0.0:
			p.pos = Vector2(randf_range(90.0, W - 90.0), randf_range(230.0, 760.0))
			p.life = p.max
		launch_hover = LAUNCH_RECT.has_point(get_viewport().get_mouse_position())
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if starting:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE]:
			_start_game()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_start_game()
		return
	if event is InputEventScreenTouch and event.pressed:
		_start_game()

func _start_game() -> void:
	if starting:
		return
	starting = true
	get_tree().change_scene_to_file("res://game.tscn")

func _draw() -> void:
	# Deep-violet base with a warm sector glow behind the ship silhouette.
	draw_rect(Rect2(0, 0, W, H), Color(0.012, 0.008, 0.04))
	for i in range(9):
		var y := float(i) * H / 9.0
		var c := Color(0.02 + i * 0.002, 0.012 + i * 0.002, 0.07 + i * 0.006, 1.0)
		draw_rect(Rect2(0, y, W, H / 9.0 + 2.0), c)
	for s in stars:
		var c := Color(0.55, 0.86, 1.0, s.alpha)
		draw_circle(s.pos, s.size, c)
		if s.size > 1.8:
			draw_line(s.pos, s.pos + Vector2(0, s.size * 7.0), Color(c, c.a * 0.28), 1.0)
	for p in particles:
		var a := clampf(p.life / p.max, 0.0, 1.0)
		draw_circle(p.pos, 8.0, Color(MAGENTA, a * 0.035))
		draw_circle(p.pos, 1.8, Color(1.0, 0.55, 0.86, a * 0.7))

	# Top navigation chrome.
	draw_line(Vector2(42, 50), Vector2(W - 42, 50), Color(CYAN, 0.23), 1.0)
	draw_line(Vector2(42, 58), Vector2(220, 58), Color(ORANGE, 0.8), 2.0)
	_text("STARFALL // SALVAGE RUN", Vector2(46, 38), 14, Color(CYAN, 0.76), BOLD_FONT)
	_text("OFFLINE ARCADE BUILD", Vector2(W - 250, 38), 13, Color(0.72, 0.74, 0.88), UI_FONT)

	# Main lockup.
	_text("STARFALL", Vector2(0, 178), 68, Color(0.94, 0.98, 1.0), TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("SALVAGE", Vector2(0, 250), 68, ORANGE, TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("DODGE THE FALL. BUILD THE SHIP.", Vector2(0, 306), 17, Color(MINT, 0.92), BOLD_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("One-thumb space survival with upgrade cards between waves.", Vector2(0, 338), 16, Color(0.70, 0.72, 0.86), UI_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)

	# Central ship emblem: an original vector mark that reads clearly on small screens.
	var ship_center := Vector2(W * 0.5, 555.0 + sin(t * 1.5) * 9.0)
	for r in range(5, 0, -1):
		draw_circle(ship_center, 70.0 + r * 16.0, Color(CYAN, 0.015 * r))
	draw_arc(ship_center, 118.0 + sin(t) * 3.0, t * 0.4, t * 0.4 + 1.6, 24, Color(CYAN, 0.42), 2.0)
	draw_arc(ship_center, 145.0, -t * 0.25, -t * 0.25 + 1.0, 18, Color(ORANGE, 0.34), 2.0)
	for r in range(4, 0, -1):
		draw_circle(ship_center + Vector2(0, 32), 8.0 + r * 4.0 + sin(t * 7.0) * 2.0, Color(ORANGE, 0.018 * r))
	_text("PILOT // NOVA-07", Vector2(0, 720), 14, Color(CYAN, 0.8), BOLD_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("The ship fires automatically. You choose the build.", Vector2(0, 752), 15, Color(0.72, 0.74, 0.86), UI_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)

	# Three promise chips.
	_chip(Rect2(48, 790, 194, 84), "01", "WAVES", "falling threats", CYAN)
	_chip(Rect2(263, 790, 194, 84), "02", "CARDS", "build your run", MINT)
	_chip(Rect2(478, 790, 194, 84), "03", "BOSSES", "break the sector", ORANGE)

	# Launch panel.
	var launch := LAUNCH_RECT
	var panel_color := Color(0.05, 0.13, 0.20, 0.95) if not launch_hover else Color(0.10, 0.22, 0.26, 0.98)
	draw_rect(launch, panel_color)
	draw_rect(Rect2(launch.position, Vector2(6, launch.size.y)), CYAN)
	draw_line(launch.position + Vector2(26, 18), launch.position + Vector2(launch.size.x - 26, 18), Color(CYAN, 0.24), 1.0)
	_text("START RUN", Vector2(94, 989), 28, Color(0.95, 1.0, 1.0), BOLD_FONT)
	_text("DRAG TO STEER  /  AUTO-FIRE  /  PICK 3 UPGRADES", Vector2(96, 1015), 13, Color(CYAN, 0.80), UI_FONT)
	_text("TAP", Vector2(560, 991), 15, ORANGE, BOLD_FONT)
	_text("ENTER", Vector2(555, 1016), 12, Color(1.0, 0.78, 0.56), UI_FONT)

	# Footer / best score.
	draw_line(Vector2(48, 1090), Vector2(W - 48, 1090), Color(0.26, 0.32, 0.50, 0.6), 1.0)
	_text("BEST SALVAGE SCORE", Vector2(50, 1122), 12, Color(0.56, 0.62, 0.82), BOLD_FONT)
	_text("%06d" % best_score, Vector2(50, 1166), 34, Color(1.0, 0.82, 0.42), TITLE_FONT)
	_text("SECTOR 01 READY", Vector2(W - 220, 1122), 12, Color(MINT, 0.8), BOLD_FONT)
	_text("NO SIGNALS. NO MERCY.", Vector2(W - 300, 1160), 14, Color(0.68, 0.70, 0.84), UI_FONT)
	_brackets(Rect2(26, 26, W - 52, H - 52), 18.0, Color(CYAN, 0.32))

func _chip(rect: Rect2, index: String, title: String, detail: String, color: Color) -> void:
	draw_rect(rect, Color(color, 0.08))
	draw_rect(Rect2(rect.position, Vector2(4, rect.size.y)), Color(color, 0.88))
	_text(index, rect.position + Vector2(18, 25), 12, Color(color, 0.9), BOLD_FONT)
	_text(title, rect.position + Vector2(18, 51), 18, Color(0.94, 0.97, 1.0), BOLD_FONT)
	_text(detail, rect.position + Vector2(18, 72), 12, Color(0.62, 0.68, 0.82), UI_FONT)

func _draw_ship(center: Vector2, scale := 1.0) -> void:
	var flame := PackedVector2Array([center + Vector2(-34, 22) * scale, center + Vector2(-62, 34 + sin(t * 8.0) * 6.0) * scale, center + Vector2(-34, 36) * scale])
	draw_colored_polygon(flame, Color(ORANGE, 0.9))
	var glow := PackedVector2Array([center + Vector2(-33, 16) * scale, center + Vector2(-49, 27) * scale, center + Vector2(-33, 30) * scale])
	draw_colored_polygon(glow, Color(1.0, 0.92, 0.44, 0.9))
	var hull := PackedVector2Array([
		center + Vector2(-38, -18) * scale,
		center + Vector2(12, -30) * scale,
		center + Vector2(54, 0) * scale,
		center + Vector2(12, 30) * scale,
		center + Vector2(-38, 18) * scale,
		center + Vector2(-20, 0) * scale
	])
	draw_colored_polygon(hull, Color(0.18, 0.34, 0.52))
	draw_polyline(PackedVector2Array([hull[0], hull[1], hull[2], hull[3], hull[4], hull[5], hull[0]]), Color(CYAN, 0.95), 2.0)
	var wing := PackedVector2Array([center + Vector2(-6, -11) * scale, center + Vector2(20, -54) * scale, center + Vector2(37, -3) * scale])
	draw_colored_polygon(wing, Color(0.25, 0.72, 0.84, 0.9))
	var wing2 := PackedVector2Array([center + Vector2(-6, 11) * scale, center + Vector2(20, 54) * scale, center + Vector2(37, 3) * scale])
	draw_colored_polygon(wing2, Color(0.20, 0.60, 0.76, 0.9))
	draw_circle(center + Vector2(27, 0) * scale, 9.0 * scale, Color(1.0, 0.92, 0.55))
	draw_circle(center + Vector2(27, 0) * scale, 4.0 * scale, Color(1.0, 1.0, 1.0))

func _brackets(rect: Rect2, size: float, color: Color) -> void:
	var x := rect.position.x
	var y := rect.position.y
	var r := rect.end.x
	var b := rect.end.y
	draw_line(Vector2(x, y + size), Vector2(x, y), color, 2.0)
	draw_line(Vector2(x, y), Vector2(x + size, y), color, 2.0)
	draw_line(Vector2(r - size, y), Vector2(r, y), color, 2.0)
	draw_line(Vector2(r, y), Vector2(r, y + size), color, 2.0)
	draw_line(Vector2(x, b - size), Vector2(x, b), color, 2.0)
	draw_line(Vector2(x, b), Vector2(x + size, b), color, 2.0)
	draw_line(Vector2(r - size, b), Vector2(r, b), color, 2.0)
	draw_line(Vector2(r, b - size), Vector2(r, b), color, 2.0)

func _text(value: String, pos: Vector2, size: int, color: Color, font: Font = UI_FONT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var resolved_font: Font = font if font != null else ThemeDB.fallback_font
	draw_string(resolved_font, pos, value, align, width, size, color)



