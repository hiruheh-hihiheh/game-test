extends BossBase
## A forge ship. Its armour shrugs off fire, except when the vents open to dump heat.
## Dodge the flame lanes, then punish the open vents.

const HULL := preload("res://assets/starfall/gen/boss_tyrant_hull.png")
const VENT := preload("res://assets/starfall/gen/boss_tyrant_vent.png")

var vents: Array = []
var vent_open := 0.0

func build() -> void:
	for side in [-1.0, 1.0]:
		vents.append(add_part(VENT, 120.0, Vector2(side * 158.0, 40.0), 60.0, 0.15, {"z": 1, "weak": false}))
	add_part(HULL, 470.0, Vector2.ZERO, 200.0, 0.4, {"rx": 118.0, "ry": 170.0})
	set_vents(false)

func set_vents(open: bool) -> void:
	for v in vents:
		v.mult = 2.6 if open else 0.2
		v.weak = open
		(v.sprite as Sprite2D).modulate = Color.WHITE if open else Color(0.42, 0.38, 0.4)
		(v.sprite as Sprite2D).scale = Vector2.ONE * ((130.0 if open else 104.0) / 512.0)

func rotation() -> Array:
	if stage == 0:
		return ["flame", "fan", "flame", "burst"]
	if stage == 1:
		return ["flame", "embers", "fan", "sweep"]
	return ["meltdown", "sweep", "flame", "cinders"]

func tick(dt: float) -> void:
	if vent_open > 0.0:
		vent_open -= dt
		if vent_open <= 0.0:
			set_vents(false)

func on_stage() -> void:
	vent_open = 4.0
	set_vents(true)

func special(name_: String) -> bool:
	match name_:
		"flame":
			Audio.play("flame")
			var n := 2 + stage
			var offset := randf_range(0.0, float(g.W) / float(n))
			for i in range(n):
				var x: float = fmod(offset + float(i) * float(g.W) / float(n), float(g.W) - 80.0) + 40.0
				g.hazards.add_beam("col", x, 0.9, 0.7, UI.ORANGE, 34.0, 64.0)
			# The vents vent after the flames: this is the window to hit them.
			g.after(1.5, _open_vents)
			return true
		"embers":
			g.hazards.event("ember", 2.0)
			return true
		"sweep":
			for i in range(1 + stage):
				var y: float = randf_range(float(g.H) * 0.5, float(g.H) - 260.0) if i > 0 else float(g.player_pos.y)
				g.hazards.add_beam("row", y, 1.1, 0.5, UI.ORANGE, 34.0)
			return true
		"cinders":
			g.spawn_group({"kind": "cinder", "form": "dive", "count": 3 + stage, "delay": 0.0})
			return true
		"meltdown":
			for i in range(16):
				g.ebullet(muzzle(), float(i) * TAU / 16.0, speed(230.0), BulletField.DART)
			g.after(0.5, _open_vents)
			return true
	return false

func _open_vents() -> void:
	if dying > 0.0 or dead:
		return
	vent_open = 4.2
	set_vents(true)
	Audio.play("flame", -4.0, 1.4)
	for v in vents:
		g.fx.sparks(v.at, 16, UI.ORANGE, 260.0, 0.5, 14.0)
