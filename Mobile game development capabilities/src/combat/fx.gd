class_name Fx
extends RefCounted
## Sparks, explosions, shockwaves, lightning, shield ripples and floating text.
## Sparks live in flat arrays and draw through one batch, so effects stay cheap on phones. Everything else is a short
## list of small dictionaries that expire on their own. Nothing here creates a Node, and every list has a hard cap.
##
## Explosions and impacts are data: TIERS and IMPACTS below describe each class of event, and explode() / impact()
## are the only code that turns them into effects. Reduced Flash and Reduced Motion are applied here, once.

const BOOM_S := preload("res://assets/starfall/effects/effect_explosion_small.png")
const BOOM_L := preload("res://assets/starfall/effects/effect_explosion_large.png")
const MAX_SPARKS := 480
## One batch draws the sparks and the flashes together.
const BATCH_CAPACITY := 480 + 40
const MAX_DEBRIS := 72
const MAX_FLASHES := 40
const MAX_RIPPLES := 24
const MAX_SCHEDULED := 48
const MAX_BOOMS := 60
const MAX_RINGS := 60
const MAX_BOLTS := 16
## Weapon impact effects allowed per second. A screen full of shots then costs the same as a busy one.
const IMPACT_RATE := 150.0
const IMPACT_BURST := 14.0

const PALETTES := {
	"fire": {"core": Color(1.0, 0.97, 0.86), "hot": Color(1.0, 0.8, 0.38), "mid": Color(1.0, 0.52, 0.16), "debris": Color(0.95, 0.6, 0.3)},
	"energy": {"core": Color(1.0, 0.92, 1.0), "hot": Color(1.0, 0.55, 0.9), "mid": Color(1.0, 0.27, 0.66), "debris": Color(0.8, 0.45, 1.0)},
	"ice": {"core": Color(0.95, 1.0, 1.0), "hot": Color(0.7, 0.95, 1.0), "mid": Color(0.3, 0.8, 1.0), "debris": Color(0.75, 0.92, 1.0)},
	"rock": {"core": Color(1.0, 0.95, 0.85), "hot": Color(1.0, 0.75, 0.45), "mid": Color(0.85, 0.5, 0.25), "debris": Color(0.66, 0.64, 0.7)},
}

## How big and how busy each class of explosion is. Sizes are multiples of the enemy's drawn size.
##   flash   the brief bright core, burst  the expanding energy texture, life  how long the burst lasts,
##   ring    [from, to, seconds, width, opacity] of the shockwave, sparks/debris  counts, speed  how fast they fly,
##   stages  extra bursts before the final one (heavy enemies), kick  screen shake.
const TIERS := {
	"small": {"flash": 0.8, "burst": 1.15, "life": 0.3, "ring": [0.3, 0.8, 0.22, 3.0, 0.55], "sparks": 9, "debris": 3, "speed": 230.0, "stages": 0, "kick": 2.4},
	"medium": {"flash": 0.9, "burst": 1.35, "life": 0.45, "ring": [0.35, 1.0, 0.32, 4.0, 0.7], "sparks": 16, "debris": 6, "speed": 300.0, "stages": 0, "kick": 5.0},
	"heavy": {"flash": 1.0, "burst": 1.5, "life": 0.62, "ring": [0.3, 1.05, 0.45, 5.0, 0.85], "sparks": 30, "debris": 10, "speed": 380.0, "stages": 2, "kick": 11.0},
	"part": {"flash": 0.9, "burst": 1.3, "life": 0.5, "ring": [0.3, 1.0, 0.34, 4.5, 0.8], "sparks": 20, "debris": 8, "speed": 330.0, "stages": 0, "kick": 7.0},
}

## What a weapon's hit looks like. color is the energy of the impact; flash/ring/boom are sizes in pixels at power 1.
const IMPACTS := {
	"pulse": {"color": Color(0.55, 0.95, 1.0), "flash": 36.0, "ring": [6.0, 34.0, 0.2, 2.6], "boom": 0.0, "sparks": 4, "speed": 210.0, "life": 0.2, "debris": 0},
	"twin": {"color": Color(0.7, 1.0, 0.9), "flash": 24.0, "ring": [], "boom": 0.0, "sparks": 3, "speed": 330.0, "life": 0.14, "debris": 0},
	"beam": {"color": Color(0.85, 0.7, 1.0), "flash": 20.0, "ring": [], "boom": 0.0, "sparks": 1, "speed": 260.0, "life": 0.12, "debris": 0},
	"missile": {"color": Color(1.0, 0.7, 0.3), "flash": 58.0, "ring": [10.0, 78.0, 0.26, 4.0], "boom": 80.0, "sparks": 8, "speed": 230.0, "life": 0.3, "debris": 3},
	"scatter": {"color": Color(1.0, 0.85, 0.4), "flash": 22.0, "ring": [], "boom": 0.0, "sparks": 3, "speed": 230.0, "life": 0.16, "debris": 0},
	"arc": {"color": Color(0.5, 0.9, 1.0), "flash": 26.0, "ring": [], "boom": 0.0, "sparks": 3, "speed": 300.0, "life": 0.15, "debris": 0},
}

var spark_pos := PackedVector2Array()
var spark_vel := PackedVector2Array()
var spark_life := PackedFloat32Array()
var spark_max := PackedFloat32Array()
var spark_size := PackedFloat32Array()
var spark_color := PackedColorArray()
var spark_count := 0
var booms: Array = []
var rings: Array = []
var bolts: Array = []
var floaters: Array = []
var flashes: Array = []
var debris: Array = []
var ripples: Array = []
var density := 1.0
var _scheduled: Array = []
var _impact_tokens := IMPACT_BURST
## Counts what the last frame's effects asked for, so tests and the benchmark can see the budget working.
var impacts_drawn := 0
var impacts_skipped := 0
var flashes_made := 0

func _init() -> void:
	spark_pos.resize(MAX_SPARKS)
	spark_vel.resize(MAX_SPARKS)
	spark_life.resize(MAX_SPARKS)
	spark_max.resize(MAX_SPARKS)
	spark_size.resize(MAX_SPARKS)
	spark_color.resize(MAX_SPARKS)
	density = [0.35, 0.65, 1.0][clampi(int(Save.opt.particles), 0, 2)]

# ---------- Shared textures (so rings, flashes and debris each cost one draw call, however many there are) ----------

static var _ring_textures := {}
static var _chip: Texture2D

## A soft ring: transparent in the middle, a bright band near the edge. `thick` picks the band width.
static func ring_tex(thick: bool) -> Texture2D:
	if _ring_textures.has(thick):
		return _ring_textures[thick]
	var g := Gradient.new()
	var inner := 0.88 if thick else 0.95
	g.offsets = PackedFloat32Array([0.0, inner, (inner + 1.0) * 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	_ring_textures[thick] = t
	return t

## A small solid square, used for flying debris.
static func chip_tex() -> Texture2D:
	if _chip == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_chip = ImageTexture.create_from_image(img)
	return _chip

# ---------- Accessibility ----------

## Reduce Flash: the bright core and screen-brightening layers are smaller and dimmer, and staged flashes become plain bursts.
func gentle() -> bool:
	return bool(Save.opt.reduced_flash)

## Reduce Motion: fewer flying pieces, shorter waves, no staged sequences.
func calm() -> bool:
	return bool(Save.opt.reduced_motion)

# ---------- Primitives ----------

func spark(at: Vector2, vel: Vector2, life: float, color: Color, size: float) -> void:
	var i := spark_count
	if i >= MAX_SPARKS:
		i = randi() % MAX_SPARKS
	else:
		spark_count += 1
	spark_pos[i] = at
	spark_vel[i] = vel
	spark_life[i] = life
	spark_max[i] = life
	spark_size[i] = size
	spark_color[i] = color

func sparks(at: Vector2, count: int, color: Color, speed: float, life: float, size: float) -> void:
	var n := maxi(1, int(float(count) * density))
	for i in range(n):
		spark(at, Vector2.from_angle(randf() * TAU) * randf_range(speed * 0.25, speed), randf_range(life * 0.5, life), color, randf_range(size * 0.5, size))

func boom(at: Vector2, size: float, big: bool, life: float) -> void:
	if booms.size() >= MAX_BOOMS:
		booms.remove_at(0)
	booms.append({"pos": at, "size": size, "big": big, "life": life, "max": life, "rot": randf() * TAU})

func ring(at: Vector2, life: float, r0: float, r1: float, color: Color, width: float) -> void:
	if rings.size() >= MAX_RINGS:
		rings.remove_at(0)
	rings.append({"pos": at, "life": life, "max": life, "r0": r0, "r1": r1, "color": color, "width": width, "thick": width / maxf(maxf(r0, r1), 1.0) > 0.05})

func bolt(a: Vector2, b: Vector2, color: Color) -> void:
	if bolts.size() >= MAX_BOLTS:
		bolts.remove_at(0)  # same policy as every other list: the oldest goes first
	var pts := PackedVector2Array()
	var steps := 6
	for i in range(steps + 1):
		var k := float(i) / float(steps)
		var jitter := Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0)) if i > 0 and i < steps else Vector2.ZERO
		pts.append(a.lerp(b, k) + jitter)
	bolts.append({"pts": pts, "life": 0.16, "color": color})

func text(value: String, at: Vector2, size: int, color: Color) -> void:
	if floaters.size() > 24:
		floaters.remove_at(0)
	floaters.append({"pos": at, "text": value, "size": size, "color": color, "life": 0.85})

## A very brief bright glow. Dimmer and smaller under Reduce Flash.
func flash(at: Vector2, size: float, color: Color, life := 0.09) -> void:
	if flashes.size() >= MAX_FLASHES:
		flashes.remove_at(0)
	flashes_made += 1
	var k := 0.5 if gentle() else 1.0
	flashes.append({"pos": at, "size": size * (0.7 if gentle() else 1.0), "color": Color(color, color.a * k), "life": life, "max": life})

## A flying piece of wreckage: shape 0 is a triangle, 1 a sliver, 2 a curved fragment of a shield.
func piece(at: Vector2, vel: Vector2, size: float, color: Color, life: float, shape := 0) -> void:
	if debris.size() >= MAX_DEBRIS:
		debris.remove_at(0)
	debris.append({"pos": at, "vel": vel, "rot": randf() * TAU, "spin": randf_range(-9.0, 9.0), "size": size, "color": color, "life": life, "max": life, "shape": shape})

func pieces(at: Vector2, count: int, speed: float, size: float, color: Color, life := 0.7) -> void:
	var n := int(float(count) * density * (0.5 if calm() else 1.0))
	for i in range(n):
		piece(at, Vector2.from_angle(randf() * TAU) * randf_range(speed * 0.3, speed), randf_range(size * 0.6, size), color.lerp(Color(0.4, 0.4, 0.45), randf() * 0.4), randf_range(life * 0.6, life), randi() % 2)

## Runs `fn` after `seconds` of real time (so staged explosions are not stretched by slow motion or hitstop).
func later(seconds: float, fn: Callable) -> void:
	if _scheduled.size() >= MAX_SCHEDULED:
		return
	_scheduled.append({"t": seconds, "fn": fn})

# ---------- Explosions ----------

## Which explosion tier and palette suits an enemy, from what is already known about it.
static func tier_for(heavy: bool, size: float) -> String:
	if heavy:
		return "heavy"
	return "medium" if size >= 100.0 else "small"

## A layered explosion: a brief bright flash, an expanding burst, a shockwave ring, sparks, debris, and a few embers that
## linger. `size` is the drawn size of what exploded. Every call varies a little, so no two look the same.
func explode(at: Vector2, tier: String, size: float, palette := "fire") -> void:
	var t: Dictionary = TIERS[tier]
	var pal: Dictionary = PALETTES.get(palette, PALETTES.fire)
	var s := maxf(size, 40.0)
	var v := randf_range(0.88, 1.14)
	_blast(at, s * v, t, pal, 1.0)
	var stages := 0 if calm() else int(t.stages)
	for i in range(stages):
		var off := Vector2.from_angle(randf() * TAU) * s * randf_range(0.2, 0.45)
		later(0.07 * float(i + 1) + randf() * 0.03, _stage_blast.bind(at + off, s * 0.55 * v, tier, palette))
	if stages > 0:
		later(0.07 * float(stages + 1) + 0.1, _final_blast.bind(at, s * v, palette))
	# Embers that linger after the blast.
	sparks(at, 3 + int(float(s) / 60.0), pal.mid, 90.0, 0.9, 6.0)

func _blast(at: Vector2, s: float, t: Dictionary, pal: Dictionary, weight: float, with_flash := true) -> void:
	if with_flash:
		flash(at, s * float(t.flash) * 1.2 * weight, pal.core, 0.07)
	boom(at, s * float(t.burst) * weight, s * float(t.burst) >= 150.0, float(t.life) * randf_range(0.9, 1.15))
	var rg: Array = t.ring
	var width := float(rg[3]) * randf_range(0.8, 1.25)
	ring(at, float(rg[2]) * (0.8 if calm() else 1.0), s * float(rg[0]), s * float(rg[1]) * weight, Color(pal.hot, float(rg[4])), width)
	sparks(at, int(t.sparks), pal.hot, float(t.speed) * weight, float(t.life) * 1.1, 11.0 + s * 0.04)
	pieces(at, int(float(t.debris) * weight), float(t.speed) * 0.8, 9.0 + s * 0.05, pal.debris, 0.8)

func _stage_blast(at: Vector2, s: float, tier: String, palette: String) -> void:
	var pal: Dictionary = PALETTES.get(palette, PALETTES.fire)
	_blast(at, s, TIERS.medium, pal, 0.8, not gentle())  # under Reduce Flash a staged blast is a burst, not another flash

func _final_blast(at: Vector2, s: float, palette: String) -> void:
	var pal: Dictionary = PALETTES.get(palette, PALETTES.fire)
	_blast(at, s * 1.1, TIERS.heavy, pal, 1.0)
	ring(at, 0.5, s * 0.4, s * 1.3, Color(pal.core, 0.55), 2.5)

## A piece of a boss breaking off: a medium blast with extra wreckage.
func explode_part(at: Vector2, size: float) -> void:
	explode(at, "part", size, "fire")

## One of the many blasts around a dying boss. They vary in size and colour, so the sequence does not repeat.
func boss_blast(at: Vector2, size: float) -> void:
	var palette := "fire" if randf() < 0.7 else "energy"
	var pal: Dictionary = PALETTES[palette]
	_blast(at, size, TIERS.part, pal, randf_range(0.85, 1.15))

## The last blast of a boss: a large central explosion, three staggered shockwaves, wreckage thrown outwards, and embers.
func boss_finale(at: Vector2, size: float) -> void:
	var pal: Dictionary = PALETTES.fire
	flash(at, size * 1.1, pal.core, 0.12)
	boom(at, size * 1.15, true, 1.0)
	for i in range(1 if calm() else 3):
		later(0.12 * float(i), ring.bind(at, 0.8 + 0.2 * float(i), size * 0.12, size * (1.1 + 0.25 * float(i)), Color(pal.hot if i != 1 else Color.WHITE, 0.9), 11.0 - 3.0 * float(i)))
	sparks(at, 70, pal.hot, 560.0, 1.1, 20.0)
	pieces(at, 22, 520.0, 22.0, pal.debris, 1.1)
	later(0.18, sparks.bind(at, 28, pal.mid, 300.0, 1.0, 14.0))

# ---------- Weapon impacts ----------

## Whether another impact effect may be drawn now. Spends one of IMPACT_RATE tokens per second.
func _may_impact() -> bool:
	if _impact_tokens < 1.0:
		impacts_skipped += 1
		return false
	_impact_tokens -= 1.0
	impacts_drawn += 1
	return true

## A hit on an enemy. `weapon` is a ship weapon id (pulse, twin, beam, missile, scatter) or "arc"; `power` is 1 for a
## normal hit and larger for heavier ones (crits, big shots); `surface` is "hull" or "shield".
func impact(at: Vector2, weapon: String, power := 1.0, surface := "hull") -> void:
	if not _may_impact():
		return
	var p: Dictionary = IMPACTS.get(weapon, IMPACTS.pulse)
	var col: Color = p.color
	if surface == "shield":
		col = Color(0.45, 0.85, 1.0)
	var k := clampf(power, 0.6, 2.2)
	flash(at, float(p.flash) * k, col.lerp(Color.WHITE, 0.5), 0.08)
	var rg: Array = p.ring
	if not rg.is_empty() and not calm():
		ring(at, float(rg[2]), float(rg[0]), float(rg[1]) * k, Color(col, 0.85), float(rg[3]))
	if float(p.boom) > 0.0:
		boom(at, float(p.boom) * k, false, 0.22)
	sparks(at, int(float(p.sparks) * (0.6 + 0.4 * k)), col, float(p.speed) * (0.8 + 0.2 * k), float(p.life), 8.0 if weapon != "twin" else 6.0)
	if int(p.debris) > 0:
		pieces(at, int(p.debris), 220.0, 7.0, Color(0.9, 0.6, 0.3), 0.45)

# ---------- Shields ----------

## A ripple on a shield bubble centred on `anchor.pos` (a dictionary with a "pos", such as an enemy), at the point
## `from` the hit came from. Stronger hits make a wider, brighter ripple.
func ripple(anchor: Dictionary, radius: float, from: Vector2, power: float, color: Color) -> void:
	if ripples.size() >= MAX_RIPPLES:
		ripples.remove_at(0)
	var centre: Vector2 = anchor.pos
	var dir := from - centre
	var life := 0.22 if calm() else 0.36
	ripples.append({"anchor": anchor, "r": radius, "ang": dir.angle() if dir.length() > 1.0 else -PI * 0.5, "power": clampf(power, 0.5, 2.0), "color": color, "life": life, "max": life})

## A shield giving way: a bright burst, two rings, electrical arcs round the rim, and curved fragments flying outwards.
func shield_break(at: Vector2, radius: float, color: Color) -> void:
	flash(at, radius * 1.5, color.lerp(Color.WHITE, 0.6), 0.1)
	ring(at, 0.4, radius * 0.8, radius * 2.0, Color(color, 0.95), 6.0)
	ring(at, 0.55, radius * 0.5, radius * 2.6, Color(color.lerp(Color.WHITE, 0.5), 0.6), 2.5)
	sparks(at, 14, color, 300.0, 0.5, 9.0)
	for i in range(1 if calm() else 3):
		var a := randf() * TAU
		bolt(at + Vector2.from_angle(a) * radius, at + Vector2.from_angle(a + randf_range(0.5, 1.1)) * radius * 1.35, color)
	var n := 4 if calm() else 8
	for i in range(n):
		var a2 := float(i) * TAU / float(n) + randf_range(-0.25, 0.25)
		piece(at + Vector2.from_angle(a2) * radius, Vector2.from_angle(a2) * randf_range(140.0, 260.0), radius * 0.28, color, randf_range(0.35, 0.6), 2)

## A shield coming back: a ring that closes in, and a few motes drawn towards the ship.
func shield_recover(at: Vector2, radius: float, color: Color) -> void:
	ring(at, 0.45, radius * 1.5, radius * 0.95, Color(color, 0.55), 3.0)
	if calm():
		return
	for i in range(maxi(3, int(8.0 * density))):
		var a := randf() * TAU
		var from := at + Vector2.from_angle(a) * radius * 1.3
		spark(from, (at - from).normalized() * randf_range(120.0, 190.0), randf_range(0.25, 0.4), color, randf_range(5.0, 8.0))

# ---------- Update ----------

func update(dt: float) -> void:
	_impact_tokens = minf(IMPACT_BURST, _impact_tokens + IMPACT_RATE * dt)
	var damp := 1.0 - minf(0.9, dt * 3.2)
	var i := spark_count - 1
	while i >= 0:
		spark_life[i] -= dt
		if spark_life[i] <= 0.0:
			spark_count -= 1
			if i < spark_count:
				var last := spark_count
				spark_pos[i] = spark_pos[last]
				spark_vel[i] = spark_vel[last]
				spark_life[i] = spark_life[last]
				spark_max[i] = spark_max[last]
				spark_size[i] = spark_size[last]
				spark_color[i] = spark_color[last]
		else:
			spark_pos[i] += spark_vel[i] * dt
			spark_vel[i] *= damp
		i -= 1
	_tick(booms, dt)
	_tick(rings, dt)
	_tick(bolts, dt)
	_tick(flashes, dt)
	_tick(ripples, dt)
	for p in debris:
		p.pos += (p.vel as Vector2) * dt
		p.vel = (p.vel as Vector2) * (1.0 - minf(0.9, dt * 2.2))
		p.rot += float(p.spin) * dt
	_tick(debris, dt)
	for f in floaters:
		f.pos += Vector2(0, -70.0) * dt
	_tick(floaters, dt)
	for k in range(_scheduled.size() - 1, -1, -1):
		var e: Dictionary = _scheduled[k]
		e.t -= dt
		if float(e.t) <= 0.0:
			_scheduled.remove_at(k)
			var fn: Callable = e.fn
			if fn.is_valid():
				fn.call()

func _tick(list: Array, dt: float) -> void:
	for k in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[k]
		e.life -= dt
		if float(e.life) <= 0.0:
			list.remove_at(k)

## Everything still alive, for tests and the benchmark.
func live_count() -> int:
	return spark_count + booms.size() + rings.size() + bolts.size() + flashes.size() + debris.size() + ripples.size() + _scheduled.size()

func fill_spark_batch(batch: SpriteBatch) -> void:
	batch.begin()
	for i in range(spark_count):
		var a := spark_life[i] / spark_max[i]
		var c := spark_color[i]
		c.a = a
		batch.add(spark_pos[i], spark_size[i] * (1.0 + a), 0.0, c)
	for f in flashes:
		var k: float = 1.0 - float(f.life) / float(f.max)
		batch.add(f.pos, float(f.size) * 2.0 * (0.55 + 0.6 * k), 0.0, Color(f.color, float((f.color as Color).a) * (1.0 - k * k)))
	batch.commit()

## Shockwave rings, drawn as scaled ring textures: two draw calls for all of them.
func fill_ring_batches(thin: SpriteBatch, thick: SpriteBatch) -> void:
	thin.begin()
	thick.begin()
	for r in rings:
		var k: float = 1.0 - float(r.life) / float(r.max)
		var ease_k := 1.0 - pow(1.0 - k, 3.0)
		var radius := lerpf(float(r.r0), float(r.r1), ease_k)
		var col := Color(r.color, (r.color as Color).a * (1.0 - k) * 0.95)
		(thick if bool(r.thick) else thin).add(r.pos, radius * 2.0, 0.0, col)
	thin.commit()
	thick.commit()

## Flying wreckage (triangles and slivers) as small rotated squares: one draw call for all of it.
func fill_debris_batch(batch: SpriteBatch) -> void:
	batch.begin()
	for p in debris:
		if int(p.shape) == 2:
			continue
		var fade := clampf(float(p.life) / float(p.max) * 2.2, 0.0, 1.0)
		batch.add(p.pos, float(p.size) * (1.0 if int(p.shape) == 0 else 0.7), float(p.rot), Color(p.color, fade))
	batch.commit()

func paint_additive(c: CanvasItem) -> void:
	for b in bolts:
		var a: float = float(b.life) / 0.16
		c.draw_polyline(b.pts, Color(b.color, a), 3.0)
		c.draw_polyline(b.pts, Color(1, 1, 1, a), 1.2)
	for rp in ripples:
		_paint_ripple(c, rp)

## The disturbance on a shield: a bright arc where the hit landed that widens and fades, and a thin ring spreading from it.
func _paint_ripple(c: CanvasItem, rp: Dictionary) -> void:
	var anchor: Dictionary = rp.anchor
	var centre: Vector2 = anchor.get("pos", Vector2.ZERO)
	var k: float = 1.0 - float(rp.life) / float(rp.max)
	var p: float = rp.power
	var col: Color = rp.color
	var half := (0.35 + 0.35 * p) * (0.7 + 0.8 * k)
	var radius: float = float(rp.r) * (1.0 + 0.06 * k)
	var a := (1.0 - k) * minf(1.0, 0.5 + 0.35 * p)
	c.draw_arc(centre, radius, float(rp.ang) - half, float(rp.ang) + half, 18, Color(col, a * 0.9), 5.0 + 2.5 * p, true)
	c.draw_arc(centre, radius, float(rp.ang) - half * 0.45, float(rp.ang) + half * 0.45, 10, Color(1, 1, 1, a), 2.0, true)
	if not calm():
		c.draw_arc(centre, radius * (0.82 + 0.3 * k), 0.0, TAU, 40, Color(col, a * 0.3), 1.5, true)

func paint_top(c: CanvasItem) -> void:
	for b in booms:
		var k: float = 1.0 - float(b.life) / float(b.max)
		var size: float = float(b.size) * (0.55 + 0.6 * pow(k, 0.5))
		var tex: Texture2D = BOOM_L if b.big else BOOM_S
		c.draw_set_transform(b.pos, float(b.rot) + k * 0.4, Vector2.ONE)
		c.draw_texture_rect(tex, Rect2(-size * 0.5, -size * 0.5, size, size), false, Color(1, 1, 1, clampf((1.0 - k) * 1.5, 0.0, 1.0)))
	# Curved shield fragments are the only debris drawn by hand (a few at a time). The rest is in fill_debris_batch.
	for p in debris:
		if int(p.shape) != 2:
			continue
		var fade := clampf(float(p.life) / float(p.max) * 2.2, 0.0, 1.0)
		c.draw_set_transform(p.pos, float(p.rot), Vector2.ONE)
		c.draw_arc(Vector2.ZERO, float(p.size), -0.5, 0.5, 6, Color(p.color, fade), 3.0, true)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func paint_text(c: CanvasItem) -> void:
	for f in floaters:
		var a := clampf(float(f.life) * 2.2, 0.0, 1.0)
		UI.outlined(c, str(f.text), f.pos, int(f.size), Color(f.color, a), true, UI.CENTER)
