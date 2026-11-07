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

## Chosen when the charge begins, so the warning shows what the attack will really do. A y of -1 means "where the ship is when it fires".
func prepare_special(name_: String):
	var w := float(g.W)
	match name_:
		"flame":
			var n := 2 + stage
			var offset := randf_range(0.0, w / float(n))
			var xs: Array = []
			for i in range(n):
				xs.append(fmod(offset + float(i) * w / float(n), w - 80.0) + 40.0)
			return {"xs": xs}
		"embers":
			return {"spots": [g.hazards.roll_spot("ember"), g.hazards.roll_spot("ember")]}
		"sweep":
			var ys: Array = [-1.0]
			for i in range(stage):
				ys.append(randf_range(float(g.H) * 0.5, float(g.H) - 260.0))
			return {"ys": ys}
		"cinders":
			var p := {}
			_roll_group(p, 3 + stage, "dive", 70.0, "cinder")
			return p
		"meltdown":
			return {}
	return null

func describe_special(p: Dictionary, _k: float, d: Dictionary) -> bool:
	match str(p.name):
		"flame":
			d.style = "columns"
			d.hue = "ember"
			d.xs = p.xs
			d.hw = 64.0
			return true
		"embers":
			d.style = "spots"
			d.hue = "ember"
			d.spots = [{"pos": (p.spots as Array)[0], "r": 120.0, "shape": "ember"}, {"pos": (p.spots as Array)[1], "r": 120.0, "shape": "ember"}]
			return true
		"sweep":
			var ys: Array = []
			for i in range((p.ys as Array).size()):
				ys.append(float(g.player_pos.y) if i == 0 else float((p.ys as Array)[i]))
			d.style = "rows"
			d.hue = "ember"
			d.ys = ys
			d.hw = Hazards.WIDTH
			d.tracked = true
			return true
		"cinders":
			d.style = "markers"
			d.markers = p.markers
			return true
		"meltdown":
			d.style = "radial"
			d.hue = "danger"
			d.rays = Telegraph.radial_rays(muzzle(), 16)
			d.rl = 260.0
			d.centre = muzzle()
			return true
	return false

func special(name_: String) -> bool:
	var p := plan_for(name_)
	match name_:
		"flame":
			Audio.play("flame")
			for x in p.xs:
				g.hazards.add_beam("col", float(x), 0.9, 0.7, UI.ORANGE, 34.0, 64.0)
			# The vents vent after the flames: this is the window to hit them.
			g.after(1.5, _open_vents)
			return true
		"embers":
			for spot in p.spots:
				g.hazards.add_zone("ember", spot, 120.0, 11.0)
			return true
		"sweep":
			var ys: Array = p.ys
			for i in range(ys.size()):
				var y: float = float(g.player_pos.y) if i == 0 else float(ys[i])
				g.hazards.add_beam("row", y, 1.1, 0.5, UI.ORANGE, 34.0)
			return true
		"cinders":
			_group({"kind": "cinder", "form": "dive", "count": 3 + stage, "delay": 0.0}, "cinder")
			return true
		"meltdown":
			for r in Telegraph.radial_rays(muzzle(), 16):
				g.ebullet(r.at, r.ang, speed(230.0), BulletField.DART)
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
