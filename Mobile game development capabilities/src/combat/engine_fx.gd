class_name EngineFx
extends RefCounted
## The player ship's engine: a bright core, a softer glow, a tapering energy exhaust that lengthens with speed, particles
## that stream behind it, and a short fading trail when it moves fast. It reacts to how the ship is ACTUALLY moving
## (position change per frame), so it needs no new movement values and changes none.
##
## Ships differ only by PROFILES: nozzle positions, width, length and colours. One implementation draws them all.
## Reduce Flash steadies the flicker and caps the brightness; Reduce Motion removes the wobble, the trail and the bend.

const PROFILES := {
	"nova": {"nozzles": [Vector2(-13, 48), Vector2(13, 48)], "width": 1.0, "length": 1.0, "core": Color(0.88, 1.0, 1.0), "glow": Color(0.3, 0.8, 1.0), "rate": 1.0},
	"interceptor": {"nozzles": [Vector2(-8, 50), Vector2(8, 50)], "width": 0.7, "length": 1.35, "core": Color(0.85, 1.0, 0.95), "glow": Color(0.3, 1.0, 0.75), "rate": 1.1},
	"lancer": {"nozzles": [Vector2(-10, 50), Vector2(10, 50)], "width": 0.8, "length": 1.25, "core": Color(0.95, 0.9, 1.0), "glow": Color(0.62, 0.45, 1.0), "rate": 1.0},
	"warden": {"nozzles": [Vector2(-26, 50), Vector2(26, 50)], "width": 1.55, "length": 0.9, "core": Color(1.0, 0.95, 0.8), "glow": Color(1.0, 0.58, 0.2), "rate": 1.3},
	"magpie": {"nozzles": [Vector2(-14, 48), Vector2(14, 48)], "width": 1.1, "length": 1.0, "core": Color(1.0, 0.98, 0.82), "glow": Color(1.0, 0.8, 0.3), "rate": 1.0},
}
## Pixels per second that count as "full speed" for the exhaust. Faster just clamps higher, for the fly-off at the end of a level.
const REFERENCE_SPEED := 700.0
const BASE_LENGTH := 46.0
const BASE_WIDTH := 9.0
const TRAIL_SLOTS := 5
const TRAIL_GAP := 0.035
const TRAIL_LIFE := 0.2

var profile: Dictionary = PROFILES.nova
var speed_k := 0.0
var accel_k := 0.0
var lateral := 0.0
var _last := Vector2.INF
var _t := 0.0
var _accum := 0.0
var _trail_clock := 0.0
var _trail: Array = []

func set_ship(ship_id: String) -> void:
	profile = PROFILES.get(ship_id, PROFILES.nova)

## Follows the ship's real movement. Call once per frame.
func update_motion(dt: float, pos: Vector2, alive: bool) -> void:
	_t += dt
	if dt <= 0.0:
		return
	if _last == Vector2.INF or not alive:
		_last = pos
		speed_k = move_toward(speed_k, 0.0, dt * 4.0)
		accel_k = 0.0
		return
	var v := (pos - _last) / dt
	_last = pos
	var now := clampf(v.length() / REFERENCE_SPEED, 0.0, 1.8)
	var before := speed_k
	speed_k = lerpf(speed_k, now, 1.0 - exp(-dt * 9.0))
	accel_k = lerpf(accel_k, clampf((speed_k - before) / maxf(dt, 0.001) * 0.12, 0.0, 1.0), 1.0 - exp(-dt * 10.0))
	lateral = lerpf(lateral, clampf(v.x / REFERENCE_SPEED, -1.0, 1.0), 1.0 - exp(-dt * 8.0))
	# Afterimages only when moving fast, and only a few, so nothing lingers on screen.
	_trail_clock += dt
	for p in _trail:
		p.age += dt
	while not _trail.is_empty() and float(_trail[0].age) > TRAIL_LIFE:
		_trail.pop_front()
	if speed_k > 0.55 and _trail_clock >= TRAIL_GAP and not bool(Save.opt.reduced_motion):
		_trail_clock = 0.0
		if _trail.size() >= TRAIL_SLOTS:
			_trail.pop_front()
		_trail.append({"pos": pos, "age": 0.0})

## How long and how bright the exhaust is right now (0.55 calm to about 1.8 flat out).
func intensity() -> float:
	var calm := bool(Save.opt.reduced_motion)
	return 0.55 + (0.5 if calm else 0.95) * minf(speed_k, 1.4) + (0.0 if calm else 0.35) * accel_k

## Streams particles out of each nozzle: more, and faster, the faster the ship goes.
func emit(dt: float, fx: Fx, pos: Vector2, alive: bool) -> void:
	if not alive:
		return
	var k := intensity()
	var gap := 0.03 / (fx.density * float(profile.rate) * (0.6 + 0.5 * k))
	_accum += dt
	var calm := bool(Save.opt.reduced_motion)
	while _accum > gap:
		_accum -= gap
		var n: Vector2 = (profile.nozzles as Array)[randi() % (profile.nozzles as Array).size()]
		var at := pos + n + Vector2(randf_range(-3.0, 3.0), 0.0)
		var spread := 8.0 if calm else 18.0 * float(profile.width)
		var vel := Vector2(randf_range(-spread, spread) - lateral * 60.0, randf_range(150.0, 230.0) * (0.8 + 0.5 * k))
		var col: Color = (profile.core as Color) if randf() < 0.35 else (profile.glow as Color)
		fx.spark(at, vel, randf_range(0.14, 0.26) * (0.8 + 0.3 * k), col, randf_range(4.0, 8.0) * float(profile.width) ** 0.5)

## Paints the exhaust and the trail into the additive layer.
func paint(c: CanvasItem, pos: Vector2, bank: float) -> void:
	var gentle := bool(Save.opt.reduced_flash)
	var calm := bool(Save.opt.reduced_motion)
	var k := intensity()
	var cap := 0.75 if gentle else 1.0
	var glow: Color = profile.glow
	var core: Color = profile.core
	for p in _trail:
		var a := (1.0 - float(p.age) / TRAIL_LIFE) * 0.16 * cap
		UI.glow(c, (p.pos as Vector2) + Vector2(0, 30), 34.0 * float(profile.width), Color(glow, a))
	var wobble := 1.0 if calm else 1.0 + (0.05 if gentle else 0.12) * sin(_t * 41.0) + (0.0 if gentle else 0.06) * sin(_t * 67.0)
	for n in (profile.nozzles as Array):
		var base := pos + (n as Vector2)
		var length := BASE_LENGTH * float(profile.length) * k * wobble
		var width := BASE_WIDTH * float(profile.width) * (1.0 - 0.15 * minf(speed_k, 1.0))
		var bend := 0.0 if calm else -lateral * 14.0 - bank * 20.0
		var tip := base + Vector2(bend, length)
		var mid := base + Vector2(bend * 0.4, length * 0.5)
		# Softer outer glow, a wider flame, a narrow bright flame, and a core at the nozzle.
		UI.glow(c, base + Vector2(0, length * 0.35), width * 2.6, Color(glow, 0.32 * cap))
		c.draw_colored_polygon(PackedVector2Array([base + Vector2(-width, 0), base + Vector2(width, 0), mid + Vector2(width * 0.55, 0), tip, mid + Vector2(-width * 0.55, 0)]), Color(glow, 0.55 * cap))
		c.draw_colored_polygon(PackedVector2Array([base + Vector2(-width * 0.5, 0), base + Vector2(width * 0.5, 0), mid + Vector2(width * 0.2, 0), base + Vector2(bend * 0.7, length * 0.78), mid + Vector2(-width * 0.2, 0)]), Color(core, 0.85 * cap))
		UI.glow(c, base + Vector2(0, 3), width * 1.5, Color(core, 0.8 * cap))
