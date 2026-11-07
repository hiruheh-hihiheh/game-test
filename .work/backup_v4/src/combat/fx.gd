class_name Fx
extends RefCounted
## Sparks, explosions, shockwaves, lightning and floating text.
## Sparks live in flat arrays and draw through one batch, so effects stay cheap on phones.

const BOOM_S := preload("res://assets/starfall/effects/effect_explosion_small.png")
const BOOM_L := preload("res://assets/starfall/effects/effect_explosion_large.png")
const MAX_SPARKS := 480

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
var density := 1.0

func _init() -> void:
	spark_pos.resize(MAX_SPARKS)
	spark_vel.resize(MAX_SPARKS)
	spark_life.resize(MAX_SPARKS)
	spark_max.resize(MAX_SPARKS)
	spark_size.resize(MAX_SPARKS)
	spark_color.resize(MAX_SPARKS)
	density = [0.35, 0.65, 1.0][clampi(int(Save.opt.particles), 0, 2)]

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
	booms.append({"pos": at, "size": size, "big": big, "life": life, "max": life, "rot": randf() * TAU})

func ring(at: Vector2, life: float, r0: float, r1: float, color: Color, width: float) -> void:
	rings.append({"pos": at, "life": life, "max": life, "r0": r0, "r1": r1, "color": color, "width": width})

func bolt(a: Vector2, b: Vector2, color: Color) -> void:
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

func update(dt: float) -> void:
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
	for f in floaters:
		f.pos += Vector2(0, -70.0) * dt
	_tick(floaters, dt)

func _tick(list: Array, dt: float) -> void:
	for k in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[k]
		e.life -= dt
		if float(e.life) <= 0.0:
			list.remove_at(k)

func fill_spark_batch(batch: SpriteBatch) -> void:
	batch.begin()
	for i in range(spark_count):
		var a := spark_life[i] / spark_max[i]
		var c := spark_color[i]
		c.a = a
		batch.add(spark_pos[i], spark_size[i] * (1.0 + a), 0.0, c)
	batch.commit()

func paint_additive(c: CanvasItem) -> void:
	for r in rings:
		var k: float = 1.0 - float(r.life) / float(r.max)
		var ease_k := 1.0 - pow(1.0 - k, 3.0)
		c.draw_arc(r.pos, lerpf(float(r.r0), float(r.r1), ease_k), 0.0, TAU, 56, Color(r.color, (1.0 - k) * 0.9), float(r.width) * (1.0 - k * 0.7), true)
	for b in bolts:
		var a: float = float(b.life) / 0.16
		c.draw_polyline(b.pts, Color(b.color, a), 3.0)
		c.draw_polyline(b.pts, Color(1, 1, 1, a), 1.2)

func paint_top(c: CanvasItem) -> void:
	for b in booms:
		var k: float = 1.0 - float(b.life) / float(b.max)
		var size: float = float(b.size) * (0.55 + 0.6 * pow(k, 0.5))
		var tex: Texture2D = BOOM_L if b.big else BOOM_S
		c.draw_set_transform(b.pos, float(b.rot) + k * 0.4, Vector2.ONE)
		c.draw_texture_rect(tex, Rect2(-size * 0.5, -size * 0.5, size, size), false, Color(1, 1, 1, clampf((1.0 - k) * 1.5, 0.0, 1.0)))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func paint_text(c: CanvasItem) -> void:
	for f in floaters:
		var a := clampf(float(f.life) * 2.2, 0.0, 1.0)
		UI.outlined(c, str(f.text), f.pos, int(f.size), Color(f.color, a), true, UI.CENTER)
