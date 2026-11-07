class_name UI
extends RefCounted
## Shared look of the game: palette, type, panels, bars and small drawn shapes.

const FONT: Font = preload("res://assets/fonts/starfall-regular.ttf")
const BOLD: Font = preload("res://assets/fonts/starfall-bold.ttf")

const CYAN := Color(0.25, 0.90, 1.0)
const MINT := Color(0.32, 1.0, 0.72)
const ORANGE := Color(1.0, 0.58, 0.20)
const GOLD := Color(1.0, 0.82, 0.32)
const MAGENTA := Color(1.0, 0.27, 0.66)
const RED := Color(1.0, 0.27, 0.30)
const VIOLET := Color(0.58, 0.44, 1.0)
const WHITE := Color(0.95, 0.98, 1.0)
const TEXT_DIM := Color(0.66, 0.74, 0.88)
const PANEL := Color(0.035, 0.05, 0.12, 0.94)
const INK := Color(0.008, 0.006, 0.02)

const LEFT := 0
const CENTER := 1
const RIGHT := 2

static var _boxes := {}
static var _glow: Texture2D
static var _edge: Texture2D

## Viewport-space insets for notches and rounded corners.
static func safe_insets(view: Vector2) -> Vector2:
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.y <= 0 or safe.size.y <= 0:
		return Vector2.ZERO
	var k := view.y / float(screen.y)
	var top := clampf(float(safe.position.y) * k, 0.0, 120.0)
	var bottom := clampf(float(screen.y - safe.end.y) * k, 0.0, 120.0)
	return Vector2(top, bottom)

static func box(fill: Color, border: Color, chamfer: int, width: int, glow: int) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d|%d" % [fill.to_html(), border.to_html(), chamfer, width, glow]
	if _boxes.has(key):
		return _boxes[key]
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(chamfer)
	s.corner_detail = 1 # One segment per corner turns the rounding into a clean chamfer.
	s.anti_aliasing = true
	s.anti_aliasing_size = 1.0
	if glow > 0:
		s.shadow_color = Color(border, 0.34)
		s.shadow_size = glow
	if _boxes.size() > 400:
		_boxes.clear()
	_boxes[key] = s
	return s

static func panel(ci: CanvasItem, rect: Rect2, fill := PANEL, border := Color(CYAN, 0.42), chamfer := 16, width := 2, glow := 0) -> void:
	ci.draw_style_box(box(fill, border, chamfer, width, glow), rect)

static func text(ci: CanvasItem, value: String, pos: Vector2, size: int, color: Color, bold := false, align := LEFT) -> void:
	var font: Font = BOLD if bold else FONT
	var at := pos
	if align != LEFT:
		var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		at.x -= w * (0.5 if align == CENTER else 1.0)
	ci.draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

static func width_of(value: String, size: int, bold := false) -> float:
	var font: Font = BOLD if bold else FONT
	return font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Text with a dark outline so it stays readable over bright explosions.
static func outlined(ci: CanvasItem, value: String, pos: Vector2, size: int, color: Color, bold := true, align := LEFT, outline := Color(0, 0, 0, 0.8)) -> void:
	var o := maxf(1.5, float(size) * 0.05)
	for d in [Vector2(-o, 0), Vector2(o, 0), Vector2(0, -o), Vector2(0, o), Vector2(-o, -o), Vector2(o, o), Vector2(-o, o), Vector2(o, -o)]:
		text(ci, value, pos + d, size, Color(outline, outline.a * color.a), bold, align)
	text(ci, value, pos, size, color, bold, align)

## Large title text with a soft coloured bloom behind it.
static func glow_text(ci: CanvasItem, value: String, pos: Vector2, size: int, color: Color, glow: Color, align := CENTER) -> void:
	var w := width_of(value, size, true)
	var left := pos.x - (w * 0.5 if align == CENTER else (w if align == RIGHT else 0.0))
	var bloom := Rect2(left - size * 0.9, pos.y - size * 1.5, w + size * 1.8, size * 2.2)
	ci.draw_texture_rect(glow_tex(), bloom, false, Color(glow, 0.20 * color.a))
	for d in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
		text(ci, value, pos + d, size, Color(glow, 0.16 * color.a), true, align)
	outlined(ci, value, pos, size, color, true, align, Color(0.01, 0.01, 0.05, 0.9))

static func bar(ci: CanvasItem, rect: Rect2, ratio: float, color: Color) -> void:
	panel(ci, rect, Color(0.02, 0.03, 0.08, 0.86), Color(color, 0.3), 4, 1)
	var fill := clampf(ratio, 0.0, 1.0) * (rect.size.x - 4.0)
	if fill > 1.0:
		ci.draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(fill, rect.size.y - 4.0)), color)
		ci.draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(fill, maxf(1.0, (rect.size.y - 4.0) * 0.36))), Color(1, 1, 1, 0.26))

static func glow_tex() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_glow = t
	return _glow

## Horizontal fade from opaque (left) to clear (right), for screen-edge warnings.
static func edge_tex() -> Texture2D:
	if _edge == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 64
		t.height = 4
		_edge = t
	return _edge

static func glow(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	ci.draw_texture_rect(glow_tex(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)

## Draws a square sprite so it fits inside a box, keeping its proportions.
static func icon(ci: CanvasItem, tex: Texture2D, center: Vector2, size: float, tint := Color.WHITE) -> void:
	ci.draw_texture_rect(tex, Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size)), false, tint)

static func star(ci: CanvasItem, center: Vector2, radius: float, color: Color, spin := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var r := radius if i % 2 == 0 else radius * 0.46
		pts.append(center + Vector2.from_angle(-PI * 0.5 + spin + float(i) * TAU / 10.0) * r)
	ci.draw_colored_polygon(pts, color)

static func pips(ci: CanvasItem, left: Vector2, count: int, filled: int, color: Color, size := Vector2(20, 8), gap := 5.0) -> void:
	for i in range(count):
		var r := Rect2(left + Vector2(float(i) * (size.x + gap), 0), size)
		ci.draw_rect(r, color if i < filled else Color(color, 0.16))

## Word-wraps text into lines that fit a pixel width.
static func wrap_lines(value: String, size: int, width: float, bold := false) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in value.split(" "):
		var attempt := word if line.is_empty() else line + " " + word
		if width_of(attempt, size, bold) > width and not line.is_empty():
			lines.append(line)
			line = word
		else:
			line = attempt
	if not line.is_empty():
		lines.append(line)
	return lines
