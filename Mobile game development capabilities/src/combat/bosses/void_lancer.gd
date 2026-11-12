extends BossBase
## Rift Lord. A hunting ship that follows you across the arena behind a guard plate.
## The plate stops everything, and it only drops while the Lancer charges an attack and for a moment after it fires,
## so the way to hurt it is to stay under it while it is shooting at you.

const HULL := preload("res://assets/starfall/gen/boss_lancer.png")
const PLATE := preload("res://assets/starfall/gen/boss_lancer_plate.png")
## How long the plate stays down after an attack.
const OPEN_AFTER := 1.1

var plate: Dictionary = {}
var hull: Dictionary = {}
var open_t := 0.0
var vx := 0.0

func build() -> void:
	def = def.duplicate()
	def["half_width"] = 150.0
	# The plate is first in the list, so a shot meets it before the hull.
	plate = add_part(PLATE, 300.0, Vector2(0, 118), 60.0, 0.0, {"hue": 0.0, "z": 2, "rx": 150.0, "ry": 46.0})
	hull = add_part(HULL, 330.0, Vector2.ZERO, 110.0, 1.0, {"hue": 0.0, "rx": 96.0, "ry": 150.0, "weak": true})

func guard_up() -> bool:
	return bool(plate.alive)

func _set_guard(up: bool) -> void:
	if up == guard_up():
		return
	plate.alive = up
	(plate.sprite as Sprite2D).visible = up
	if up:
		Audio.play("clank", -6.0, 0.8)
	else:
		Audio.play("shield_break", -10.0, 1.3)
		g.fx.ring(pos + Vector2(0, 118), 0.3, 40.0, 170.0, UI.MINT, 4.0)

## It hunts: it slides toward the ship's column instead of swaying, faster in each phase.
func move(dt: float) -> void:
	var margin := 150.0
	var want: float = clampf(float(g.player_pos.x), margin, float(g.W) - margin)
	var top_speed := 150.0 + float(stage) * 50.0
	vx = move_toward(vx, clampf((want - pos.x) * 2.0, -top_speed, top_speed), dt * 420.0)
	pos.x += vx * dt
	pos.y = home.y - 30.0 + sin(t * 1.3) * 10.0
	(hull.sprite as Sprite2D).rotation = -vx * 0.0009

func tick(dt: float) -> void:
	if open_t > 0.0:
		open_t -= dt
	_set_guard(charge <= 0.0 and open_t <= 0.0)

func attack(name_: String) -> void:
	super.attack(name_)
	open_t = OPEN_AFTER

func muzzle() -> Vector2:
	return pos + Vector2(0, 150)

func rotation() -> Array:
	if stage == 0:
		return ["lance", "fan", "aimed"]
	if stage == 1:
		return ["lance", "burst", "wings", "raiders"]
	return ["wings", "lance", "strike", "burst", "lance"]

## The wing guns: two parallel streams straight down, either side of the hull.
func wing_rays() -> Array:
	var out: Array = []
	for side in [-1.0, 1.0]:
		for i in range(3 + stage):
			out.append({"at": pos + Vector2(float(side) * (70.0 + float(i) * 34.0), 60.0), "ang": PI * 0.5 + float(side) * 0.06 * float(i)})
	return out

func prepare_special(name_: String):
	if name_ in ["lance", "wings"]:
		return {}
	return null

func describe_special(p: Dictionary, _k: float, d: Dictionary) -> bool:
	match str(p.name):
		"lance":
			# The spinal cannon fires down the Lancer's own column, where it is when the charge ends.
			d.style = "columns"
			d.hue = "ion"
			d.xs = [pos.x]
			d.hw = 46.0
			return true
		"wings":
			d.style = "volley"
			d.rays = wing_rays()
			d.len = 620.0
			return true
	return false

func special(name_: String) -> bool:
	match name_:
		"lance":
			g.hazards.add_beam("col", pos.x, 0.5, 0.45, UI.MINT, 36.0, 46.0)
			return true
		"wings":
			for r in wing_rays():
				g.ebullet(r.at, r.ang, speed(260.0), BulletField.DART)
			Audio.play("enemy_shoot", -2.0, 0.9)
			return true
	return false
