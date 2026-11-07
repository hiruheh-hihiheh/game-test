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
const BLUE := Color(0.30, 0.55, 1.0)
const GLASS := Color(0.035, 0.06, 0.14)

## Panel treatments. Every panel in the game is one of these, so a card on the title screen,
## in the Hangar and in Settings are made of the same parts.
enum Kind { INFO, CARD, SELECTED, PRIMARY, DISABLED, REWARD, WARNING }

## Draw flat single-layer panels, bars and chips instead of glass, and skip the purely decorative helpers
## (rule, shine, enter_veil). Used to isolate what the glass layers cost, never by the game. It does not
## undo layout changes such as the title pad, so a true before/after needs the old commit (see docs/GLASS_UI.md).
static var classic := false

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

## Compatibility wrapper: the old call, drawn as glass. The border colour is the accent, a thick border
## or a glow marks a selected or rewarded panel, and the fill the caller gives is kept as the glass tint.
static func panel(ci: CanvasItem, rect: Rect2, fill := PANEL, border := Color(CYAN, 0.42), chamfer := 16, width := 2, glow := 0) -> void:
	if classic:
		ci.draw_style_box(box(fill, border, chamfer, width, glow), rect)
		return
	var strong := width >= 3 or glow > 0
	var kind: int = Kind.SELECTED if strong else (Kind.CARD if border.a >= 0.5 else Kind.INFO)
	glass(ci, rect, kind, Color(border.r, border.g, border.b, 1.0), {"fill": fill, "chamfer": chamfer, "border_alpha": border.a, "glow": glow, "alpha": clampf(fill.a * 1.05, 0.0, 1.0)})

## The shared glass panel. Layers: tinted translucent fill, a thin border, a top sheen, a soft shade at the
## bottom, an inner highlight, edge lighting in the accent colour, and brackets on emphasised kinds.
## Options: fill, chamfer, border_alpha, glow, lift (brighten), alpha (fade everything), pulse (0..1).
static func glass(ci: CanvasItem, rect: Rect2, kind: int = Kind.INFO, accent: Color = CYAN, o: Dictionary = {}) -> void:
	if classic:
		_flat_glass(ci, rect, kind, accent, o)
		return
	var chamfer: int = int(o.get("chamfer", 14))
	var fade: float = float(o.get("alpha", 1.0))
	var lift: float = float(o.get("lift", 0.0))
	var sel := kind == Kind.SELECTED
	var prim := kind == Kind.PRIMARY
	var dis := kind == Kind.DISABLED
	var warn := kind == Kind.WARNING
	var reward := kind == Kind.REWARD
	if reward and not o.has("accent_set"):
		accent = GOLD if accent == CYAN else accent
	if warn and accent == CYAN:
		accent = RED
	var border_a := 0.3
	var width := 1
	var glow_size := 0
	var sheen := 0.10
	var edge := 0.35
	var base: Color = o.get("fill", Color(GLASS, 0.92))
	match kind:
		Kind.CARD:
			border_a = 0.5
			sheen = 0.13
			edge = 0.55
		Kind.SELECTED:
			border_a = 0.95
			width = 2
			glow_size = 8
			sheen = 0.17
			edge = 0.95
			if not o.has("fill"):
				base = Color(GLASS, 0.92).lerp(Color(accent.darkened(0.6), 0.94), 0.6)
		Kind.PRIMARY:
			border_a = 0.95
			width = 2
			glow_size = 8
			sheen = 0.24
			edge = 1.0
			base = Color(accent.darkened(0.5), 0.96)
			if not o.has("fill"):
				base = Color(accent.darkened(0.5), 0.96)
		Kind.DISABLED:
			border_a = 0.2
			sheen = 0.03
			edge = 0.0
			accent = Color(0.5, 0.55, 0.66)
			base = Color(0.05, 0.07, 0.12, 0.7)
		Kind.REWARD, Kind.WARNING:
			border_a = 0.8
			width = 2
			glow_size = 6
			sheen = 0.16
			edge = 0.9
			if not o.has("fill"):
				base = Color(GLASS, 0.92).lerp(Color(accent.darkened(0.62), 0.94), 0.5)
	if o.has("border_alpha"):
		var given: float = float(o.border_alpha)
		border_a = maxf(given, 0.7) if sel else clampf(given * 0.9, 0.16, 0.6)
	if o.has("glow"):
		glow_size = int(o.glow)
	if lift > 0.0:
		base = base.lightened(lift)
		sheen += lift * 0.5
	base.a *= fade
	var border := Color(accent, border_a * fade)
	ci.draw_style_box(box(base, border, chamfer, width, glow_size if fade > 0.5 else 0), rect)
	if rect.size.y < 26.0 or rect.size.x < 40.0 or fade <= 0.02:
		return
	var cut := maxf(0.0, minf(float(chamfer), minf(rect.size.x, rect.size.y) * 0.5) - float(width))
	var x0 := rect.position.x + float(width)
	var x1 := rect.end.x - float(width)
	var y0 := rect.position.y + float(width)
	var y1 := rect.end.y - float(width)
	var hh := (y1 - y0) * (0.5 if prim else 0.4)
	var sheen_tint := Color(0.72, 0.92, 1.0).lerp(accent, 0.3)
	var top := Color(sheen_tint, sheen * fade)
	var clear := Color(sheen_tint, 0.0)
	# Depth is drawn as ONE gradient polygon (sheen at the top, a soft shade at the bottom) and every fine
	# line as ONE multi-line call. Each separate shape costs a draw call, and the menus have a lot of panels.
	var shaded := not dis and kind != Kind.INFO and rect.size.y >= 56.0
	var ct := minf(cut, hh - 1.0)
	if shaded and ct >= 1.0:
		var bh := (y1 - y0) * 0.3
		var shade := Color(0, 0, 0, 0.2 * fade)
		var none := Color(0, 0, 0, 0.0)
		var cb := minf(cut, bh - 1.0)
		if cb >= 1.0:
			ci.draw_polygon(PackedVector2Array([Vector2(x0 + ct, y0), Vector2(x1 - ct, y0), Vector2(x1, y0 + ct), Vector2(x1, y0 + hh), Vector2(x1, y1 - bh), Vector2(x1, y1 - cb), Vector2(x1 - cb, y1), Vector2(x0 + cb, y1), Vector2(x0, y1 - cb), Vector2(x0, y1 - bh), Vector2(x0, y0 + hh), Vector2(x0, y0 + ct)]), PackedColorArray([top, top, top, clear, none, shade, shade, shade, shade, none, clear, top]))
		else:
			ci.draw_polygon(PackedVector2Array([Vector2(x0 + ct, y0), Vector2(x1 - ct, y0), Vector2(x1, y0 + ct), Vector2(x1, y0 + hh), Vector2(x0, y0 + hh), Vector2(x0, y0 + ct)]), PackedColorArray([top, top, top, clear, clear, top]))
	elif ct < 1.0:
		ci.draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y0 + hh), Vector2(x0, y0 + hh)]), PackedColorArray([top, top, clear, clear]))
	else:
		ci.draw_polygon(PackedVector2Array([Vector2(x0 + ct, y0), Vector2(x1 - ct, y0), Vector2(x1, y0 + ct), Vector2(x1, y0 + hh), Vector2(x0, y0 + hh), Vector2(x0, y0 + ct)]), PackedColorArray([top, top, top, clear, clear, top]))
	var lines := PackedVector2Array()
	var line_colors := PackedColorArray()
	if not dis:
		if shaded:
			lines.append_array([Vector2(x0 + cut, y0 + 1.5), Vector2(x1 - cut, y0 + 1.5)])
			line_colors.append(Color(1, 1, 1, 0.09 * fade))
		var span := (x1 - x0 - cut * 2.0) * (1.0 if (sel or prim or reward or warn) else 0.42)
		lines.append_array([Vector2(x0 + cut, y0 - 0.5), Vector2(x0 + cut + span, y0 - 0.5)])
		line_colors.append(Color(accent, edge * fade * (0.55 + 0.45 * float(o.get("pulse", 1.0)))))
	if sel or prim or reward or warn:
		var arm := minf(14.0, rect.size.y * 0.3)
		var bracket := Color(accent.lightened(0.3), 0.85 * fade)
		var a1 := Vector2(x0 + 4.0, y0 + cut + arm)
		var a2 := Vector2(x0 + 4.0, y0 + cut + 3.0)
		var a3 := Vector2(x0 + cut + 3.0, y0 + 4.0)
		var a4 := Vector2(x0 + cut + arm, y0 + 4.0)
		var b1 := Vector2(x1 - 4.0, y1 - cut - arm)
		var b2 := Vector2(x1 - 4.0, y1 - cut - 3.0)
		var b3 := Vector2(x1 - cut - 3.0, y1 - 4.0)
		var b4 := Vector2(x1 - cut - arm, y1 - 4.0)
		lines.append_array([a1, a2, a2, a3, a3, a4, b1, b2, b2, b3, b3, b4])
		for k in range(6):
			line_colors.append(bracket)
	if not lines.is_empty():
		ci.draw_multiline_colors(lines, line_colors, 1.5)
	if warn:
		ci.draw_rect(Rect2(x0 + 2.0, y0 + rect.size.y * 0.25, 3.0, rect.size.y * 0.5), Color(accent, 0.85 * fade))

## What `classic` draws instead of glass: one flat style box, like the panels before the redesign.
static func _flat_glass(ci: CanvasItem, rect: Rect2, kind: int, accent: Color, o: Dictionary) -> void:
	var fill: Color = o.get("fill", PANEL)
	var width := 2
	var alpha := 0.42
	match kind:
		Kind.PRIMARY:
			fill = accent.darkened(0.42)
			alpha = 0.95
			width = 3
		Kind.SELECTED, Kind.REWARD, Kind.WARNING:
			if not o.has("fill"):
				fill = Color(accent.darkened(0.72), 0.97)
			alpha = 0.95
			width = 3
		Kind.CARD:
			if not o.has("fill"):
				fill = Color(accent.darkened(0.72), 0.97)
			alpha = 0.5
		Kind.DISABLED:
			fill = Color(Color(0.42, 0.46, 0.56).darkened(0.72), 0.97)
			alpha = 0.4
	if o.has("border_alpha"):
		alpha = float(o.border_alpha)
	ci.draw_style_box(box(fill, Color(accent, alpha), int(o.get("chamfer", 14)), width, int(o.get("glow", 0))), rect)

# ---------- Motion and light helpers ----------

## Reduce motion turns off every ambient animation.
static func motion_ok() -> bool:
	return not bool(Save.opt.get("reduced_motion", false))

## Reduce flashes also turns off pulses and sweeps of light.
static func flash_ok() -> bool:
	return motion_ok() and not bool(Save.opt.get("reduced_flash", false))

static func clock() -> float:
	return float(Time.get_ticks_msec()) * 0.001

static func ease_out(k: float) -> float:
	var v := clampf(k, 0.0, 1.0)
	return 1.0 - pow(1.0 - v, 3.0)

## A slow 0..1 breathing value for illuminated elements. A steady 0.6 when flashes are reduced.
static func breathe(period := 2.8, phase := 0.0) -> float:
	if not flash_ok():
		return 0.6
	return 0.5 + 0.5 * sin((clock() / period + phase) * TAU)

## Fades a card in from the dark, staggered by its position. age is seconds since the screen opened.
static func enter_veil(ci: CanvasItem, rect: Rect2, age: float, index: int) -> void:
	if classic or not motion_ok():
		return
	var k := clampf((age - 0.03 - float(index) * 0.045) / 0.24, 0.0, 1.0)
	if k >= 1.0:
		return
	var left := 1.0 - ease_out(k)
	ci.draw_rect(rect.grow(2.0), Color(0.008, 0.01, 0.03, left * 0.96))

## One soft band of light that crosses a card once, for rewards and unlocks. progress runs 0 to 1.
static func shine(ci: CanvasItem, rect: Rect2, progress: float, accent: Color = WHITE) -> void:
	if classic or progress <= 0.0 or progress >= 1.0 or not flash_ok():
		return
	var half := 34.0
	var cx := rect.position.x - half + (rect.size.x + half * 2.0) * progress
	var x0 := rect.position.x + 2.0
	var x1 := rect.end.x - 2.0
	var y0 := rect.position.y + 2.0
	var y1 := rect.end.y - 2.0
	var fade := sin(progress * PI)
	var mid := Color(accent, 0.26 * fade)
	var none := Color(accent, 0.0)
	var a := clampf(cx - half, x0, x1)
	var b := clampf(cx, x0, x1)
	var c := clampf(cx + half, x0, x1)
	if b - a > 1.0:
		ci.draw_polygon(PackedVector2Array([Vector2(a, y0), Vector2(b, y0), Vector2(b, y1), Vector2(a, y1)]), PackedColorArray([none, mid, mid, none]))
	if c - b > 1.0:
		ci.draw_polygon(PackedVector2Array([Vector2(b, y0), Vector2(c, y0), Vector2(c, y1), Vector2(b, y1)]), PackedColorArray([mid, none, none, mid]))

## A fading rule, for dividing a page into groups.
static func rule(ci: CanvasItem, from: Vector2, to: Vector2, accent: Color, alpha := 0.55) -> void:
	if classic:
		return
	var mid := from.lerp(to, 0.5)
	ci.draw_polyline_colors(PackedVector2Array([from, mid, to]), PackedColorArray([Color(accent, 0.0), Color(accent, alpha), Color(accent, 0.0)]), 1.5)

## A small glass label, for counts and tags. Returns its rectangle.
static func chip(ci: CanvasItem, pos: Vector2, value: String, size: int, accent: Color, align := LEFT) -> Rect2:
	var w := width_of(value, size, true) + float(size) * 1.1
	var h := float(size) * 1.75
	var x := pos.x - (w * 0.5 if align == CENTER else (w if align == RIGHT else 0.0))
	var r := Rect2(x, pos.y - h * 0.5, w, h)
	if not classic:
		glass(ci, r, Kind.CARD, accent, {"chamfer": int(h * 0.3)})
	text(ci, value, Vector2(x + w * 0.5, pos.y + float(size) * 0.36), size, WHITE, true, CENTER)
	return r

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

## The largest font size from `size` down to `min_size` at which the text fits `max_w`.
static func fit_size(value: String, size: int, min_size: int, max_w: float, bold := false) -> int:
	var s := size
	while s > min_size and width_of(value, s, bold) > max_w:
		s -= 1
	return s

## Cuts text to fit, ending in "..." when something had to go.
static func ellipsize(value: String, size: int, max_w: float, bold := false) -> String:
	if width_of(value, size, bold) <= max_w:
		return value
	var out := value
	while out.length() > 1 and width_of(out + "...", size, bold) > max_w:
		out = out.substr(0, out.length() - 1)
	return out.strip_edges() + "..."

## Draws text that must stay inside a width: it shrinks first, and is cut only at the smallest size.
## Returns the width it used.
static func fit_text(ci: CanvasItem, value: String, pos: Vector2, size: int, min_size: int, max_w: float, color: Color, bold := false) -> float:
	var s := fit_size(value, size, min_size, max_w, bold)
	var shown := ellipsize(value, s, max_w, bold)
	text(ci, shown, pos, s, color, bold)
	return width_of(shown, s, bold)

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

## A thin glass gauge: dark track, a gradient fill with a bright leading edge, a sheen and quarter ticks.
static func bar(ci: CanvasItem, rect: Rect2, ratio: float, color: Color) -> void:
	if classic:
		panel(ci, rect, Color(0.02, 0.03, 0.08, 0.86), Color(color, 0.3), 4, 1)
		var f := clampf(ratio, 0.0, 1.0) * (rect.size.x - 4.0)
		if f > 1.0:
			ci.draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(f, rect.size.y - 4.0)), color)
			ci.draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(f, maxf(1.0, (rect.size.y - 4.0) * 0.36))), Color(1, 1, 1, 0.26))
		return
	ci.draw_style_box(box(Color(0.012, 0.02, 0.05, 0.84), Color(color, 0.34), 4, 1, 0), rect)
	var inner := Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4))
	var fill := clampf(ratio, 0.0, 1.0) * inner.size.x
	if fill > 1.0:
		var left := color.darkened(0.38)
		var right := color.lightened(0.08)
		var a := inner.position
		var b := inner.position + Vector2(fill, 0)
		var c := inner.position + Vector2(fill, inner.size.y)
		var d := inner.position + Vector2(0, inner.size.y)
		ci.draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([left, right, right, left]))
		ci.draw_rect(Rect2(inner.position, Vector2(fill, maxf(1.0, inner.size.y * 0.4))), Color(1, 1, 1, 0.2))
		if fill < inner.size.x - 2.0:
			ci.draw_rect(Rect2(inner.position.x + fill - 2.0, inner.position.y, 2.0, inner.size.y), Color(color.lightened(0.55), 0.95))
	if rect.size.y >= 12.0 and rect.size.x >= 120.0:
		var ticks := PackedVector2Array()
		for q in [0.25, 0.5, 0.75]:
			var tx: float = inner.position.x + inner.size.x * float(q)
			ticks.append_array([Vector2(tx, inner.position.y), Vector2(tx, inner.end.y)])
		ci.draw_multiline(ticks, Color(0, 0, 0, 0.3), 1.0)

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
