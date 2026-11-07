extends BossBase
## The source of the starfall. A vast eye behind rotating armour rings.
## Shots only reach the pupil through the moving gaps. Time them, or bend them.

const EYE := preload("res://assets/starfall/gen/boss_core_eye.png")
const RING := preload("res://assets/starfall/gen/boss_core_ring.png")
const ART_ARC_RADIUS := 605.0
const ART_ARC_OFFSET := 444.0
const SEG_ARC := 0.54

var layers: Array = []
var eye: Dictionary = {}
var pupil: Dictionary = {}
var open_scale := 0.0

func build() -> void:
	def = def.duplicate()
	var w: float = float(g.W)
	var r_in: float = minf(w * 0.33, 236.0)
	var r_out: float = minf(w * 0.44, 316.0)
	_add_ring(r_in, 3, 0.5)
	_add_ring(r_out, 4, -0.34)
	# The whole eye is the target. The rings are the defence.
	pupil = add_part(EYE, 1.0, Vector2.ZERO, 150.0, 1.5, {"hue": 0.0, "weak": true})
	eye = add_part(EYE, 340.0, Vector2.ZERO, 1.0, 0.0, {"hue": 0.0})
	home.y = float(g.top) + 340.0

func _add_ring(radius: float, count: int, spin: float) -> void:
	var segs: Array = []
	var art_scale := radius / ART_ARC_RADIUS
	for i in range(count):
		var half := SEG_ARC * 0.5
		var p := add_part(RING, 512.0 * art_scale, Vector2.ZERO, 40.0, 0.0, {"hue": 0.0, "z": 2, "arc": {"r0": radius - 34.0, "r1": radius + 34.0, "angle": 0.0, "half": half}})
		segs.append(p)
	layers.append({"segs": segs, "radius": radius, "spin": spin, "angle": randf() * TAU, "scale": art_scale})

func move(_dt: float) -> void:
	pos.x = float(g.W) * 0.5
	pos.y = home.y + sin(t * 0.6) * 10.0

func _enter(dt: float) -> void:
	# The eye opens where it stands instead of flying in.
	pos = Vector2(float(g.W) * 0.5, home.y)
	open_scale = move_toward(open_scale, 1.0, dt * 0.55)
	(eye.sprite as Sprite2D).scale = Vector2.ONE * (340.0 / 512.0) * Vector2(1.0, open_scale)
	if open_scale >= 1.0:
		entering = false

func tick(dt: float) -> void:
	for layer in layers:
		layer.angle = float(layer.angle) + float(layer.spin) * dt * (1.0 + float(stage) * 0.35)
		var segs: Array = layer.segs
		for i in range(segs.size()):
			var p: Dictionary = segs[i]
			var a: float = float(layer.angle) + float(i) * TAU / float(segs.size())
			# The art's arc centre is far below the sprite, so offset it along the ring direction.
			var dir := Vector2.from_angle(a)
			p.offset = dir * (float(layer.scale) * ART_ARC_OFFSET)
			(p.sprite as Sprite2D).rotation = a + PI * 0.5
			p.arc.angle = a

func rotation() -> Array:
	if stage == 0:
		return ["ring", "strike", "wells", "spiral"]
	if stage == 1:
		return ["spiral", "spokes", "wells", "curtain", "strike"]
	return ["collapse", "spokes", "spiral", "mines", "ring", "strike"]

func muzzle() -> Vector2:
	return pos

func on_stage() -> void:
	g.hazards.add_well(Vector2(float(g.W) * 0.5, float(g.H) * 0.62), 0.5 + float(stage) * 0.2, 16.0)

func special(name_: String) -> bool:
	match name_:
		"wells":
			for i in range(1 + stage):
				g.hazards.add_well(Vector2(randf_range(120.0, float(g.W) - 120.0), randf_range(float(g.H) * 0.5, float(g.H) * 0.66)), 0.8, 9.0)
			return true
		"spokes":
			g.hazards.add_spokes(pos, 2 + stage, 0.38 + float(stage) * 0.08, 7.0)
			return true
		"collapse":
			# Every shot on screen falls toward the eye for a moment, then the eye fires back.
			g.hazards.add_well(pos, 2.2, 2.2)
			g.after(2.0, _rebound)
			return true
	return false

func _rebound() -> void:
	if dying > 0.0 or dead:
		return
	for i in range(28):
		g.ebullet(pos, float(i) * TAU / 28.0, speed(250.0), BulletField.ORB, 20.0)
	Audio.play("burst", -3.0, 1.3)
	g.kick(8.0)
