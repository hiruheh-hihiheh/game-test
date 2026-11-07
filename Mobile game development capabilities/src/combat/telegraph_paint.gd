class_name TelegraphPaint
extends RefCounted
## Draws attack warnings as thin targeting graphics: luminous lines, segmented rings, tightening brackets, scanning
## sweeps and small sigils. It only reads descriptors (see Telegraph) and never touches the game.
##
## Every warning has a different SHAPE, not just a different colour (aimed: bracket reticle; twin: ladder rails; fan:
## segmented arcs; lance: five sequential pips and a scope; bomb: wide lanes with chevrons; broadside: parallel
## strips; radial: rays with a rotating segmented ring; ring: a ring with a bracketed opening; spiral: curved arms;
## curtain: a row of pips with a bracketed opening; columns / rows: edge lines with a scan; spots: ringed zones).
##
## Three stages follow the descriptor's progress k: preparing (faint, geometry appears), locking (brackets tighten,
## lines brighten) and executing (full brightness, colour turns hot). Reduce Flash removes pulsing and halves glow;
## Reduce Motion stops spinning and sweeping. Colour blind swaps the palette for blue and yellow.
##
## Everything is built into capped arrays once per frame and drawn in two batched passes: a dark outline and faint
## fill underneath (so it reads on bright backgrounds), and the bright additive lines and glows on top.

const MAX_LINES := 640
const MAX_ARCS := 140
const MAX_GLOWS := 40
const MAX_POLYS := 24
const MAX_PLINES := 24
## Every stroke is cut into straight segments and drawn with one draw_multiline_colors call per width (and per pass),
## so ten warnings cost a handful of draw calls instead of one per arc. This caps the segments in a frame.
const MAX_SEGS := 1800
const INK := Color(0.01, 0.01, 0.04)

static var l_a := PackedVector2Array()
static var l_b := PackedVector2Array()
static var l_w := PackedFloat32Array()
static var l_c := PackedColorArray()
static var l_ink := PackedByteArray()
static var a_at := PackedVector2Array()
static var a_r := PackedFloat32Array()
static var a_0 := PackedFloat32Array()
static var a_1 := PackedFloat32Array()
static var a_w := PackedFloat32Array()
static var a_c := PackedColorArray()
static var g_at := PackedVector2Array()
static var g_r := PackedFloat32Array()
static var g_c := PackedColorArray()
static var polys: Array = []
static var poly_c := PackedColorArray()
static var plines: Array = []
static var pl_w := PackedFloat32Array()
static var pl_c := PackedColorArray()
## width bucket -> {"w", "p" points, "c" colours, "i" outline colours}. Kept between frames and emptied, not recreated.
static var b_ink := {}
static var b_free := {}
static var seg_count := 0
static var clock := 0.0
static var calm := false
static var gentle := false
static var cb := false
static var W := 720.0
static var H := 1280.0

static func stats() -> Dictionary:
	var buckets := 0
	for b in b_ink.values():
		buckets += 1 if (b.p as PackedVector2Array).size() > 0 else 0
	for b in b_free.values():
		buckets += 1 if (b.p as PackedVector2Array).size() > 0 else 0
	return {"lines": l_a.size(), "arcs": a_at.size(), "glows": g_at.size(), "polys": polys.size(), "plines": plines.size(), "segs": seg_count, "buckets": buckets}

static func build(shown: Array, t: float, w: float, h: float) -> void:
	l_a.clear()
	l_b.clear()
	l_w.clear()
	l_c.clear()
	l_ink.clear()
	a_at.clear()
	a_r.clear()
	a_0.clear()
	a_1.clear()
	a_w.clear()
	a_c.clear()
	g_at.clear()
	g_r.clear()
	g_c.clear()
	polys.clear()
	poly_c.clear()
	plines.clear()
	pl_w.clear()
	pl_c.clear()
	_empty(b_ink)
	_empty(b_free)
	seg_count = 0
	clock = t
	W = w
	H = h
	gentle = bool(Save.opt.reduced_flash)
	calm = bool(Save.opt.reduced_motion)
	cb = bool(Save.opt.colorblind)
	for d in shown:
		_emit(d)

# ---------- Passes ----------

## Packed arrays only change in place through a typed variable (a cast makes a copy), hence the locals.
static func _empty(store: Dictionary) -> void:
	for b in store.values():
		var p: PackedVector2Array = b.p
		var c: PackedColorArray = b.c
		var i: PackedColorArray = b.i
		p.clear()
		c.clear()
		i.clear()

## Beneath the sprites: dark outlines for contrast and faint fills.
static func paint_under(c: CanvasItem) -> void:
	for i in range(polys.size()):
		c.draw_colored_polygon(polys[i], poly_c[i])
	for b in b_ink.values():
		if (b.p as PackedVector2Array).size() > 0:
			c.draw_multiline_colors(b.p, b.i, float(b.w) + 3.0)

## Above the sprites, additive: the bright lines and glows.
static func paint_add(c: CanvasItem) -> void:
	for b in b_free.values():
		if (b.p as PackedVector2Array).size() > 0:
			c.draw_multiline_colors(b.p, b.c, float(b.w))
	for b in b_ink.values():
		if (b.p as PackedVector2Array).size() > 0:
			c.draw_multiline_colors(b.p, b.c, float(b.w))
	for i in range(g_at.size()):
		UI.glow(c, g_at[i], g_r[i], g_c[i])

static func _steps(r: float, span: float) -> int:
	return clampi(int(absf(span) * r / 22.0) + 2, 3, 24)

# ---------- Colour ----------

static func _hue(name: String, k: float) -> Color:
	match name:
		"danger":
			return Color(1.0, 1.0, 1.0) if cb else Color(1.0, 0.28, 0.2).lerp(Color(1.0, 0.45, 0.25), k)
		"ember":
			return Color(1.0, 0.85, 0.4) if cb else Color(1.0, 0.5, 0.12)
		"ion":
			return Color(0.5, 0.8, 1.0) if cb else Color(0.3, 0.92, 1.0)
		"warp":
			return Color(0.7, 0.55, 1.0) if cb else Color(1.0, 0.3, 0.68)
		"arc":
			return Color(0.6, 0.6, 1.0) if cb else Color(0.62, 0.48, 1.0)
		"safe":
			return Color(0.3, 0.55, 1.0) if cb else Color(0.32, 1.0, 0.72)
	# Preparing is amber and turns hotter as the attack gets closer.
	var a := Color(1.0, 0.9, 0.25) if cb else Color(1.0, 0.72, 0.22)
	var b := Color(1.0, 1.0, 0.7) if cb else Color(1.0, 0.42, 0.14)
	return a.lerp(b, k)

## How visible a warning is: faint while preparing, full when about to fire.
static func _vis(k: float) -> float:
	return lerpf(0.5, 1.0, smoothstep(0.0, 1.0, k))

static func _pulse(k: float) -> float:
	if gentle:
		return 1.0
	return 0.88 + 0.12 * sin(clock * (9.0 + 22.0 * k))

# ---------- Primitives ----------

## Fine lines are drawn a quarter thicker so they still read on a phone; wide fills are left as they are.
const FINE := 1.25

static func _line(a: Vector2, b: Vector2, col: Color, w := 1.5, ink := true) -> void:
	if l_a.size() >= MAX_LINES:
		return
	if w < 6.0:
		w *= FINE
	l_a.append(a)
	l_b.append(b)
	l_w.append(w)
	l_c.append(col)
	l_ink.append(1 if ink else 0)
	_seg(w, col, ink, a, b)

static func _arc(at: Vector2, r: float, a0: float, a1: float, col: Color, w := 1.5) -> void:
	if a_at.size() >= MAX_ARCS:
		return
	w *= FINE
	a_at.append(at)
	a_r.append(r)
	a_0.append(a0)
	a_1.append(a1)
	a_w.append(w)
	a_c.append(col)
	var n := _steps(r, a1 - a0)
	var prev := at + Vector2.from_angle(a0) * r
	for i in range(1, n + 1):
		var q := at + Vector2.from_angle(a0 + (a1 - a0) * float(i) / float(n)) * r
		_seg(w, col, true, prev, q)
		prev = q

## One straight piece of a stroke, filed under its width so every width is a single draw call.
static func _seg(w: float, col: Color, ink: bool, a: Vector2, b: Vector2) -> void:
	if seg_count >= MAX_SEGS:
		return
	seg_count += 1
	var key := maxi(1, int(round(w)))
	var store: Dictionary = b_ink if ink else b_free
	if not store.has(key):
		store[key] = {"w": float(key), "p": PackedVector2Array(), "c": PackedColorArray(), "i": PackedColorArray()}
	var bucket: Dictionary = store[key]
	var pts: PackedVector2Array = bucket.p
	var cols: PackedColorArray = bucket.c
	pts.append(a)
	pts.append(b)
	cols.append(col)
	if ink:
		var inks: PackedColorArray = bucket.i
		inks.append(Color(INK, minf(0.6, col.a * 0.75)))

static func _glow(at: Vector2, r: float, col: Color) -> void:
	if g_at.size() >= MAX_GLOWS:
		return
	g_at.append(at)
	g_r.append(r)
	g_c.append(Color(col, col.a * (0.5 if gentle else 1.0)))

static func _poly(pts: PackedVector2Array, col: Color) -> void:
	if polys.size() >= MAX_POLYS:
		return
	polys.append(pts)
	poly_c.append(col)

static func _pline(pts: PackedVector2Array, col: Color, w: float) -> void:
	if plines.size() >= MAX_PLINES:
		return
	plines.append(pts)
	pl_w.append(w)
	pl_c.append(col)
	for i in range(pts.size() - 1):
		_seg(w, col, true, pts[i], pts[i + 1])

static func _col(c: Color, a: float) -> Color:
	return Color(c, clampf(a, 0.0, 1.0))

## Four corner brackets that tighten as the attack locks.
static func _brackets(at: Vector2, r: float, col: Color, w := 2.0) -> void:
	var rot := 0.0 if calm else clock * 0.7
	for i in range(4):
		var base := rot + float(i) * PI * 0.5 + PI * 0.25 - 0.34
		_arc(at, r, base, base + 0.68, col, w)
	_line(at + Vector2(-3, 0), at + Vector2(3, 0), col, 1.5, false)
	_line(at + Vector2(0, -3), at + Vector2(0, 3), col, 1.5, false)

## A circular scope: full ring with four ticks.
static func _scope(at: Vector2, r: float, col: Color, w := 1.6) -> void:
	_arc(at, r, 0.0, TAU, col, w)
	for i in range(4):
		var dir := Vector2.from_angle(float(i) * PI * 0.5)
		_line(at + dir * (r - 5.0), at + dir * (r + 8.0), col, w, false)

static func _chevron(at: Vector2, ang: float, size: float, col: Color, w := 2.0) -> void:
	_line(at, at + Vector2.from_angle(ang + PI * 0.82) * size, col, w)
	_line(at, at + Vector2.from_angle(ang - PI * 0.82) * size, col, w)

static func _diamond(at: Vector2, r: float, col: Color, w := 1.6) -> void:
	var p := [at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]
	for i in range(4):
		_line(p[i], p[(i + 1) % 4], col, w, false)

## A bright dash that runs along a line. With Reduce Motion it stays put and only creeps with progress.
static func _sweep(a: Vector2, dir: Vector2, length: float, k: float, col: Color, phase := 0.0, seg := 54.0) -> void:
	var s: float
	if calm:
		s = length * (0.3 + 0.5 * k)
	else:
		s = fposmod(clock * (380.0 + 420.0 * k) + phase * length, length)
	var e := minf(s + seg, length)
	_line(a + dir * s, a + dir * e, _col(col, 0.95 * _vis(k)), 3.0, false)
	_glow(a + dir * e, 14.0, _col(col, 0.4))

# ---------- Dispatcher ----------

static func _emit(d: Dictionary) -> void:
	var k: float = clampf(float(d.k), 0.0, 1.0)
	var hue := str(d.get("hue", "warn"))
	var col := _hue(hue, k)
	var wm := 1.35 if hue == "danger" else 1.0
	match str(d.style):
		"aimed":
			_aimed(d, k, col, wm)
		"twin":
			_twin(d, k, col, wm)
		"fan":
			_fan(d, k, col, wm)
		"lance":
			_lance(d, k, col, wm)
		"bomb":
			_bomb(d, k, col, wm)
		"broadside":
			_broadside(d, k, col, wm)
		"radial":
			_radial(d, k, col, wm)
		"ring_gap":
			_ring_gap(d, k, col, wm)
		"spiral":
			_spiral(d, k, col)
		"curtain":
			_curtain(d, k, col)
		"columns":
			_columns(d, k, col, wm)
		"rows":
			_rows(d, k, col, wm)
		"drops":
			_drops(d, k, col)
		"spots":
			_spots(d, k, col)
		"markers":
			_markers(d, k, col)
		"hub":
			_hub(d, k, col)
		"burst":
			_burst(d, k, col)
		"volley":
			_volley(d, k, col)
	if str(d.style) not in ["markers", "spots", "columns", "rows", "drops", "curtain"]:
		_origin(d, k, col)

## A small pulsing ring where the attack starts.
static func _origin(d: Dictionary, k: float, col: Color) -> void:
	var at: Vector2 = d.origin
	var vis := _vis(k)
	_arc(at, 11.0 + 9.0 * (1.0 - k) * _pulse(k), 0.0, TAU, _col(col, vis * 0.8), 1.6)
	_glow(at, 30.0 + 34.0 * k, _col(col, (0.16 + 0.3 * k) * _pulse(k)))

# ---------- Enemy and boss styles ----------

static func _aimed(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var rays: Array = d.rays
	var length: float = float(d.get("len", 700.0))
	var vis := _vis(k)
	var mid := rays.size() / 2
	var big := bool(d.get("heavy", false))
	for i in range(rays.size()):
		var r: Dictionary = rays[i]
		var a: Vector2 = r.at
		var dir := Vector2.from_angle(float(r.ang))
		if i == mid:
			_line(a, a + dir * length, _col(col, vis * 0.78), (1.7 + 1.5 * k) * wm)
			if big:
				_line(a, a + dir * length, _col(col, 0.06), 22.0, false)
			_sweep(a, dir, length, k, col)
			# The reticle stays 90 px short of the ship (the line runs 140 past it), so it never sits on the ship.
			var at := a + dir * clampf(length - 230.0, 90.0, length)
			_brackets(at, lerpf(30.0, 13.0, smoothstep(0.1, 0.9, k)) * (1.4 if big else 1.0), _col(col, vis), 2.2 * wm)
		else:
			_line(a, a + dir * length * 0.8, _col(col, vis * 0.34), 0.9)

static func _twin(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var rays: Array = d.rays
	var length: float = float(d.get("len", 600.0))
	var vis := _vis(k)
	for i in range(rays.size()):
		var r: Dictionary = rays[i]
		var a: Vector2 = r.at
		var dir := Vector2.from_angle(float(r.ang))
		_line(a, a + dir * length, _col(col, vis * 0.6), (1.2 + 1.2 * k) * wm)
		_line(a, a + dir * length, _col(col, 0.07), 18.0, false)
		# Ladder rungs make two rails, unlike every other warning.
		var n := int(length / 96.0)
		for j in range(1, n + 1):
			var p := a + dir * (float(j) * 96.0)
			_line(p - dir.orthogonal() * 7.0, p + dir.orthogonal() * 7.0, _col(col, vis * 0.5), 1.4, false)
		_diamond(a, 5.0, _col(col, vis), 1.6)
		_sweep(a, dir, length, k, col, float(i) * 0.5)

static func _fan(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var rays: Array = d.rays
	var length: float = minf(float(d.get("len", 560.0)), 640.0)
	var vis := _vis(k)
	var n := rays.size()
	var o: Vector2 = (rays[0] as Dictionary).at
	var first := float((rays[0] as Dictionary).ang)
	var last := float((rays[n - 1] as Dictionary).ang)
	var tight := lerpf(1.08, 1.0, smoothstep(0.1, 0.9, k))
	for i in range(n):
		var r: Dictionary = rays[i]
		var dir := Vector2.from_angle(float(r.ang))
		var edge := i == 0 or i == n - 1
		_line(o, o + dir * (length if edge else length * 0.72), _col(col, vis * (0.75 if edge else 0.38)), (1.5 + 1.2 * k) * wm if edge else 0.9)
	# Segmented arcs between neighbouring shots, plus a lighter outer one.
	var r1 := length * 0.54 * tight
	for i in range(n - 1):
		var a0 := float((rays[i] as Dictionary).ang)
		var a1 := float((rays[i + 1] as Dictionary).ang)
		_arc(o, r1, a0 + 0.015, a1 - 0.015, _col(col, vis * 0.7), 1.6 * wm)
	var r2 := length * 0.82 * tight
	var segs := 6
	for i in range(segs):
		var a0 := lerpf(first, last, float(i) / float(segs)) + 0.01
		var a1 := lerpf(first, last, (float(i) + 0.7) / float(segs))
		_arc(o, r2, a0, a1, _col(col, vis * 0.45), 1.2)
	# A faint wedge shows the whole danger area.
	var pts := PackedVector2Array([o])
	for i in range(9):
		pts.append(o + Vector2.from_angle(lerpf(first, last, float(i) / 8.0)) * r2)
	_poly(pts, _col(col, 0.07 * vis))

static func _lance(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var r: Dictionary = (d.rays as Array)[0]
	var a: Vector2 = r.at
	var dir := Vector2.from_angle(float(r.ang))
	var length: float = float(d.get("len", 700.0))
	var vis := _vis(k)
	_line(a, a + dir * length, _col(col, vis * 0.6), (1.0 + 0.9 * k) * wm)
	# Five pips light one after another: five shots are coming, one behind the other.
	for i in range(5):
		var p := a + dir * (80.0 + float(i) * 58.0)
		var lit := k >= float(i + 1) / 6.0
		_diamond(p, 6.0 if lit else 3.5, _col(col, 1.0 if lit else 0.3), 1.8 if lit else 1.2)
		if lit:
			_glow(p, 14.0, _col(col, 0.35))
	_scope(a + dir * maxf(length - 230.0, 120.0), lerpf(22.0, 11.0, smoothstep(0.1, 0.9, k)), _col(col, vis), 1.8 * wm)

static func _bomb(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var rays: Array = d.rays
	var length: float = float(d.get("len", 620.0))
	var vis := _vis(k)
	for r in rays:
		var a: Vector2 = (r as Dictionary).at
		var ang := float((r as Dictionary).ang)
		var dir := Vector2.from_angle(ang)
		# A wide lane: the bombs are big.
		_line(a, a + dir * length, _col(col, vis * 0.6), (2.4 + 1.2 * k) * wm)
		_line(a, a + dir * length, _col(col, 0.08), 34.0, false)
		for j in range(3):
			_chevron(a + dir * (120.0 + float(j) * 140.0), ang, 11.0, _col(col, vis * (0.5 + 0.15 * float(j))), 2.2 * wm)
		var end := a + dir * length
		_arc(end, lerpf(26.0, 19.0, k), 0.0, TAU, _col(col, vis * 0.8), 2.4 * wm)
		_line(end + Vector2(-8, 0), end + Vector2(8, 0), _col(col, vis), 2.0, false)
		_line(end + Vector2(0, -8), end + Vector2(0, 8), _col(col, vis), 2.0, false)
	_sweep((rays[1] as Dictionary).at, Vector2.from_angle(float((rays[1] as Dictionary).ang)), length, k, col)

static func _broadside(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var rays: Array = d.rays
	var length: float = float(d.get("len", 600.0))
	var vis := _vis(k)
	for i in range(rays.size()):
		var a: Vector2 = (rays[i] as Dictionary).at
		var dir := Vector2.from_angle(float((rays[i] as Dictionary).ang))
		_line(a, a + dir * length, _col(col, vis * 0.55), (1.2 + 1.0 * k) * wm)
		_line(a, a + dir * length, _col(col, 0.06), 18.0, false)
		_line(a + dir * length + Vector2(-7, 0), a + dir * length + Vector2(7, 0), _col(col, vis * 0.7), 1.6, false)
		_line(a + Vector2(-4, -2), a + Vector2(4, -2), _col(col, vis), 2.2, false)
		# Each strip charges downward in turn.
		_sweep(a, dir, length, k, col, float(i) * 0.18, 40.0)

## Rays with a ring of segments that tightens and turns: unmistakably not a single aimed line.
static func _radial(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var rays: Array = d.rays
	var rl: float = float(d.get("rl", 230.0))
	var o: Vector2 = d.get("centre", d.origin)
	var vis := _vis(k)
	var n := rays.size()
	for r in rays:
		var dir := Vector2.from_angle(float((r as Dictionary).ang))
		_line(o + dir * 24.0, o + dir * rl, _col(col, vis * 0.5), (1.0 + 0.9 * k) * wm)
		_line(o + dir * rl, o + dir * (rl + 9.0), _col(col, vis * 0.8), 1.8 * wm, false)
	var ring_r := lerpf(rl * 0.95, rl * 0.58, smoothstep(0.1, 0.9, k))
	var spin := 0.0 if calm else clock * 0.9
	var step := TAU / float(n)
	var base := float((rays[0] as Dictionary).ang) + step * 0.5 + spin
	for i in range(n):
		var a0 := base + float(i) * step
		_arc(o, ring_r, a0 + step * 0.12, a0 + step * 0.78, _col(col, vis * 0.85), 1.8 * wm)
	_line(o + Vector2(-9, -9), o + Vector2(9, 9), _col(col, vis), 2.0, false)
	_line(o + Vector2(-9, 9), o + Vector2(9, -9), _col(col, vis), 2.0, false)

static func _ring_gap(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var o: Vector2 = d.origin
	var rays: Array = d.rays
	var step: float = float(d.step)
	var vis := _vis(k)
	var ring_r := lerpf(300.0, 175.0, smoothstep(0.1, 0.9, k))
	var count := int(round(TAU / step))
	var gap_i := int(round(float(d.gap_ang) / step - 0.5))
	var start := float(gap_i + 2) * step
	_arc(o, ring_r, start, start + float(count - 3) * step, _col(col, vis * 0.6), 1.4 * wm)
	for r in rays:
		var dir := Vector2.from_angle(float((r as Dictionary).ang))
		_line(o + dir * (ring_r - 9.0), o + dir * (ring_r + 9.0), _col(col, vis * 0.85), 2.0 * wm)
	# The opening: two edges, chevrons pointing out through it, and a bracketed arc across it.
	var safe := _hue("safe", k)
	for e in [float(d.edge_a), float(d.edge_b)]:
		var dir := Vector2.from_angle(e)
		_line(o + dir * (ring_r - 28.0), o + dir * (ring_r + 560.0), _col(safe, 0.55 + 0.4 * vis), 2.4)
	var mid := float(d.gap_ang)
	var md := Vector2.from_angle(mid)
	# A faint wedge fills the safe corridor so it is obvious where to fly.
	var wedge := PackedVector2Array()
	var span := 3.0 * step
	for j in range(7):
		wedge.append(o + Vector2.from_angle(float(d.edge_a) + span * float(j) / 6.0) * (ring_r + 560.0))
	wedge.append(o + Vector2.from_angle(float(d.edge_b)) * (ring_r - 28.0))
	wedge.append(o + Vector2.from_angle(float(d.edge_a)) * (ring_r - 28.0))
	_poly(wedge, _col(safe, 0.12 * vis))
	for j in range(3):
		_chevron(o + md * (ring_r + 70.0 + float(j) * 80.0), mid, 15.0, _col(safe, 0.75 + 0.2 * vis), 3.0)
	_arc(o, ring_r, float(d.edge_a) + step * 0.2, float(d.edge_b) - step * 0.2 + (TAU if float(d.edge_b) < float(d.edge_a) else 0.0), _col(safe, 0.55), 1.2)

static func _spiral(d: Dictionary, k: float, col: Color) -> void:
	var o: Vector2 = d.origin
	var arms: int = int(d.arms)
	var kk: float = float(d.kk)
	var a0: float = float(d.a0)
	var vis := _vis(k)
	# The arms swing into their firing position, clockwise, which is also the way the stream will turn.
	var rot := 0.0 if calm else -(1.0 - k) * 1.1
	for arm in range(arms):
		var pts := PackedVector2Array()
		for j in range(25):
			var r := 36.0 + float(j) * 11.0
			pts.append(o + Vector2.from_angle(a0 + float(arm) * TAU / float(arms) - r * kk + rot) * r)
		_pline(pts, _col(col, vis * 0.8), 2.4)
		var end_ang := a0 + float(arm) * TAU / float(arms) - 300.0 * kk + rot
		_chevron(o + Vector2.from_angle(end_ang) * 300.0, end_ang + PI * 0.5, 11.0, _col(col, vis * 0.9), 2.4)

static func _curtain(d: Dictionary, k: float, col: Color) -> void:
	var y: float = float(d.y)
	var vis := _vis(k)
	var xs: Array = d.xs
	var l: float = float(d.open_l)
	var r: float = float(d.open_r)
	var tick := 6.0 + 10.0 * k
	for x in xs:
		_line(Vector2(float(x), y - 4.0), Vector2(float(x), y + tick), _col(col, vis), 3.0)
	_line(Vector2(0, y + 5.0), Vector2(l, y + 5.0), _col(col, vis * 0.5), 1.4)
	_line(Vector2(r, y + 5.0), Vector2(float(d.width), y + 5.0), _col(col, vis * 0.5), 1.4)
	var safe := _hue("safe", k)
	for x in [l, r]:
		_line(Vector2(x, y - 10.0), Vector2(x, y + 380.0), _col(safe, 0.45 + 0.45 * vis), 2.0)
	_line(Vector2(l, y - 10.0), Vector2(r, y - 10.0), _col(safe, 0.8), 2.0)
	_poly(PackedVector2Array([Vector2(l, y - 10.0), Vector2(r, y - 10.0), Vector2(r, y + 380.0), Vector2(l, y + 380.0)]), _col(safe, 0.08 * vis))
	var cx := (l + r) * 0.5
	for j in range(2):
		_chevron(Vector2(cx, y + 50.0 + float(j) * 60.0), PI * 0.5, 12.0, _col(safe, 0.8), 2.8)
	_glow(Vector2(cx, y + 20.0), 40.0, _col(safe, 0.12 * vis))

static func _columns(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var xs: Array = d.xs
	var hw: float = float(d.get("hw", 58.0))
	var vis := _vis(k)
	for i in range(xs.size()):
		var x: float = float(xs[i])
		_line(Vector2(x - hw, 0.0), Vector2(x - hw, H), _col(col, vis * 0.6), (1.2 + 1.2 * k) * wm)
		_line(Vector2(x + hw, 0.0), Vector2(x + hw, H), _col(col, vis * 0.6), (1.2 + 1.2 * k) * wm)
		_poly(PackedVector2Array([Vector2(x - hw, 0), Vector2(x + hw, 0), Vector2(x + hw, H), Vector2(x - hw, H)]), _col(col, 0.05 * vis))
		_chevron(Vector2(x, 70.0), PI * 0.5, 10.0, _col(col, vis), 2.2)
		_chevron(Vector2(x, 100.0), PI * 0.5, 10.0, _col(col, vis * 0.6), 2.0)
		_sweep(Vector2(x, 0.0), Vector2.DOWN, H, k, col, float(i) * 0.31, 90.0)
		if i == 0 and bool(d.get("tracked", false)):
			_brackets(Vector2(x, float(d.get("track_y", 760.0))), lerpf(34.0, 18.0, smoothstep(0.1, 0.9, k)), _col(col, vis), 2.0 * wm)

static func _rows(d: Dictionary, k: float, col: Color, wm: float) -> void:
	var ys: Array = d.ys
	var hw: float = float(d.get("hw", 58.0))
	var vis := _vis(k)
	for i in range(ys.size()):
		var y: float = float(ys[i])
		_line(Vector2(0.0, y - hw), Vector2(W, y - hw), _col(col, vis * 0.6), (1.2 + 1.2 * k) * wm)
		_line(Vector2(0.0, y + hw), Vector2(W, y + hw), _col(col, vis * 0.6), (1.2 + 1.2 * k) * wm)
		_poly(PackedVector2Array([Vector2(0, y - hw), Vector2(W, y - hw), Vector2(W, y + hw), Vector2(0, y + hw)]), _col(col, 0.05 * vis))
		for x in [20.0, W - 20.0]:
			_line(Vector2(x, y - hw - 8.0), Vector2(x, y + hw + 8.0), _col(col, vis), 2.2)
		_chevron(Vector2(46.0, y), 0.0, 10.0, _col(col, vis), 2.2)
		_chevron(Vector2(W - 46.0, y), PI, 10.0, _col(col, vis), 2.2)
		_sweep(Vector2(0.0, y), Vector2.RIGHT, W, k, col, float(i) * 0.27, 90.0)

static func _drops(d: Dictionary, k: float, col: Color) -> void:
	var y0: float = float(d.y0)
	var vis := _vis(k)
	for x in d.xs:
		var at := Vector2(float(x), y0)
		_chevron(at + Vector2(0, 10), PI * 0.5, 9.0, _col(col, vis), 2.0)
		_line(at + Vector2(0, 24), at + Vector2(0, 120), _col(col, vis * 0.45), 1.0)
		_line(at + Vector2(-5, 120), at + Vector2(5, 120), _col(col, vis * 0.7), 1.4, false)

static func _spots(d: Dictionary, k: float, col: Color) -> void:
	var vis := _vis(k)
	for s in d.spots:
		var at: Vector2 = s.pos
		var r: float = float(s.r)
		var rr := lerpf(r * 1.18, r, smoothstep(0.1, 0.9, k))
		_arc(at, rr, 0.0, TAU, _col(col, vis * 0.7), 1.8)
		match str(s.shape):
			"ember":
				for i in range(10):
					var dir := Vector2.from_angle(float(i) * TAU / 10.0)
					_line(at + dir * rr, at + dir * (rr + 13.0), _col(col, vis), 2.0)
			"frost":
				for i in range(6):
					var dir := Vector2.from_angle(float(i) * TAU / 6.0 + 0.2)
					var p := at + dir * rr
					_line(p - dir.orthogonal() * 10.0, p + dir.orthogonal() * 10.0, _col(col, vis), 2.2)
			_:
				for i in range(3):
					var a0 := float(i) * 1.7 + (0.0 if calm else clock * 1.4)
					_arc(at, r * (0.35 + 0.22 * float(i)), a0, a0 + 2.8, _col(col, vis * 0.6), 1.6)
		_glow(at, r * 0.9, _col(col, 0.08 + 0.1 * k))

static func _markers(d: Dictionary, k: float, col: Color) -> void:
	var vis := _vis(k)
	for m in d.markers:
		_marker(str(m.shape), m.pos, col, vis, k)

## Each kind of arrival has its own small outline, so rocks, raiders and mines are told apart by shape.
static func _marker(shape: String, at: Vector2, col: Color, vis: float, k: float) -> void:
	var s := 16.0 + 4.0 * (1.0 - k) * _pulse(k)
	var c := _col(col, vis)
	if shape not in ["raider_side", "raider_side_r", "sigil", "swarm"]:
		# A small arrow below says "coming from above".
		_chevron(at + Vector2(0, s + 14.0), PI * 0.5, 8.0, _col(col, vis * 0.8), 2.0)
	match shape:
		"rock":
			for i in range(6):
				var a := float(i) * TAU / 6.0 + 0.3
				_line(at + Vector2.from_angle(a) * s, at + Vector2.from_angle(a + TAU / 6.0) * s, c, 1.8)
		"raider":
			_line(at + Vector2(0, s), at + Vector2(-s, -s * 0.8), c, 1.8)
			_line(at + Vector2(0, s), at + Vector2(s, -s * 0.8), c, 1.8)
			_line(at + Vector2(-s, -s * 0.8), at + Vector2(s, -s * 0.8), c, 1.8)
		"raider_side", "raider_side_r":
			var sx := 1.0 if shape == "raider_side" else -1.0
			_line(at + Vector2(sx * s, 0), at + Vector2(-sx * s * 0.8, -s), c, 1.8)
			_line(at + Vector2(sx * s, 0), at + Vector2(-sx * s * 0.8, s), c, 1.8)
			_line(at + Vector2(-sx * s * 0.8, -s), at + Vector2(-sx * s * 0.8, s), c, 1.8)
		"mine":
			_arc(at, s * 0.75, 0.0, TAU, c, 1.8)
			for i in range(8):
				var dir := Vector2.from_angle(float(i) * TAU / 8.0)
				_line(at + dir * s * 0.75, at + dir * s * 1.25, c, 1.8)
		"cinder":
			_diamond(at, s * 0.9, c, 1.8)
			_line(at + Vector2(0, -s * 0.9), at + Vector2(0, -s * 1.7), _col(col, vis * 0.6), 1.6)
		"swarm":
			for p in [Vector2(-8, 0), Vector2(8, -4), Vector2(0, 8)]:
				_arc(at + p, 4.0, 0.0, TAU, c, 1.6)
			_line(at + Vector2(-110, 14), at + Vector2(110, 14), _col(col, vis * 0.5), 1.2)
			_line(at + Vector2(-110, 8), at + Vector2(-110, 20), c, 1.6, false)
			_line(at + Vector2(110, 8), at + Vector2(110, 20), c, 1.6, false)
		"revenant":
			_chevron(at, PI * 0.5, s, c, 2.0)
			_chevron(at + Vector2(0, s * 0.9), PI * 0.5, s, _col(col, vis * 0.6), 1.8)
		_:
			# The summoning sigil of an enemy that is about to spawn swarmlets.
			_arc(at, 9.0 + 5.0 * (1.0 - k) * _pulse(k), 0.0, TAU, c, 1.8)
			_arc(at, 17.0, 0.0, TAU, _col(col, vis * 0.5), 1.2)
			for i in range(4):
				var dir := Vector2.from_angle(float(i) * PI * 0.5 + PI * 0.25)
				_line(at + dir * 17.0, at + dir * 23.0, c, 1.6, false)
	_glow(at, 22.0, _col(col, 0.12 + 0.15 * k))

static func _hub(d: Dictionary, k: float, col: Color) -> void:
	var o: Vector2 = d.origin
	var arms: int = int(d.arms)
	var dir_sign: float = float(d.dir)
	var vis := _vis(k)
	for i in range(arms):
		var ang := float(d.a0) + float(i) * TAU / float(arms)
		var dir := Vector2.from_angle(ang)
		_line(o + dir * 60.0, o + dir * 360.0, _col(col, vis * 0.55), 1.4)
		_line(o + dir * 60.0, o + dir * 360.0, _col(col, 0.06), 20.0, false)
	# An arc with a chevron at its end shows which way the arms will turn.
	var a0 := float(d.a0)
	var a1 := a0 + dir_sign * 1.1
	_arc(o, 90.0, minf(a0, a1), maxf(a0, a1), _col(col, vis * 0.8), 2.0)
	_chevron(o + Vector2.from_angle(a1) * 90.0, a1 + dir_sign * PI * 0.5, 9.0, _col(col, vis), 2.2)

static func _burst(d: Dictionary, k: float, col: Color) -> void:
	var rays: Array = d.rays
	var length: float = float(d.get("len", 700.0))
	var vis := _vis(k)
	var n: int = int(d.n)
	var left: int = int(d.get("left", n))
	var a: Vector2 = (rays[1] as Dictionary).at
	var dir := Vector2.from_angle(float((rays[1] as Dictionary).ang))
	_line(a, a + dir * length, _col(col, vis * 0.55), 1.2 + 1.0 * k)
	for side in [0, 2]:
		var sd := Vector2.from_angle(float((rays[side] as Dictionary).ang))
		_line(a, a + sd * length * 0.7, _col(col, vis * 0.3), 0.9)
	# One chevron per shot, lighting in order: several aimed volleys follow one another.
	var running := left < n
	for i in range(left):
		var lit := true if running else k >= float(i + 1) / float(n + 1)
		var p := a + dir * (100.0 + float(i) * 46.0)
		_chevron(p, float((rays[1] as Dictionary).ang), 8.0 if lit else 6.0, _col(col, 1.0 if lit else 0.3), 2.2 if lit else 1.4)
		if lit:
			_glow(p, 12.0, _col(col, 0.3))
	_brackets(a + dir * clampf(length - 230.0, 100.0, length), lerpf(28.0, 14.0, smoothstep(0.1, 0.9, k)), _col(col, vis), 2.0)

static func _volley(d: Dictionary, k: float, col: Color) -> void:
	var length: float = float(d.get("len", 520.0))
	var vis := _vis(k)
	for r in d.rays:
		var a: Vector2 = (r as Dictionary).at
		var dir := Vector2.from_angle(float((r as Dictionary).ang))
		_line(a, a + dir * length, _col(col, vis * 0.45), 1.1)
		_diamond(a, 5.0, _col(col, vis), 1.6)
