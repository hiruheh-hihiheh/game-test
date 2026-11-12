extends BossBase
## Rift Lord. Two bodies circling each other: a bright sun and a dark moon.
## Only the lit twin can be hurt, and they trade places, so the fight is about being under the right one.

const SUN := preload("res://assets/starfall/gen/boss_eclipse_sun.png")
const MOON := preload("res://assets/starfall/gen/boss_eclipse_moon.png")
const ORBIT := 165.0

var sun: Dictionary = {}
var moon: Dictionary = {}
var lit: Dictionary = {}
var angle := 0.0
var swap_t := 6.0

func build() -> void:
	def = def.duplicate()
	def["half_width"] = 260.0
	sun = add_part(SUN, 210.0, Vector2(-ORBIT, 0), 78.0, 1.3, {"hue": 0.0, "z": 1, "weak": true})
	moon = add_part(MOON, 210.0, Vector2(ORBIT, 0), 82.0, 0.0, {"hue": 0.0, "z": 1})
	lit = sun
	_light(sun)

## Makes `twin` the one that can be hurt. The other turns to armour.
func _light(twin: Dictionary) -> void:
	lit = twin
	for p in [sun, moon]:
		var on: bool = is_same(p, twin)
		p.mult = 1.3 if on else 0.0
		p.weak = on
		(p.sprite as Sprite2D).modulate = Color.WHITE if on else Color(0.5, 0.5, 0.62)

func dark() -> Dictionary:
	return moon if is_same(lit, sun) else sun

func move(_dt: float) -> void:
	pos.x = float(g.W) * 0.5 + sin(t * 0.45) * 40.0
	pos.y = home.y + sin(t * 0.9) * 12.0

func tick(dt: float) -> void:
	angle += dt * (0.5 + float(stage) * 0.2)
	var off := Vector2(cos(angle) * ORBIT, sin(angle) * 70.0)
	sun.offset = off
	moon.offset = -off
	(sun.sprite as Sprite2D).rotation += dt * 0.5
	(moon.sprite as Sprite2D).rotation -= dt * 0.3
	if can_be_hit() and charge <= 0.0:
		swap_t -= dt
		if swap_t <= 0.0:
			swap_t = 6.0 - float(stage) * 1.0
			_light(dark())
			Audio.play("ice", -6.0, 1.4)
			g.fx.ring(lit.at, 0.4, 30.0, 190.0, UI.GOLD, 5.0)
			g.fx.sparks(lit.at, 14, UI.GOLD, 240.0, 0.4, 12.0)

## Shots leave from the lit twin, so its side of the arena is the dangerous one.
func muzzle() -> Vector2:
	return (lit.at as Vector2) + Vector2(0, 40)

func rotation() -> Array:
	if stage == 0:
		return ["aimed", "fan", "crossfire"]
	if stage == 1:
		return ["ring", "crossfire", "burst", "eclipse"]
	return ["spiral", "eclipse", "ring", "crossfire", "strike"]

## Both twins fire three aimed shots at the ship.
func cross_rays() -> Array:
	var out: Array = []
	for p in [sun, moon]:
		var from: Vector2 = (p.at as Vector2) + Vector2(0, 40)
		out.append_array(Telegraph.aimed_rays(from, ((g.player_pos as Vector2) - from).angle()))
	return out

## Each twin throws a ring of shots, the two rings turned against each other so their gaps do not line up.
func eclipse_rays() -> Array:
	var n := 10 + stage * 2
	var out: Array = Telegraph.radial_rays(sun.at, n, 0.0)
	out.append_array(Telegraph.radial_rays(moon.at, n, PI / float(n)))
	return out

func prepare_special(name_: String):
	if name_ in ["crossfire", "eclipse"]:
		return {}
	return null

func describe_special(p: Dictionary, _k: float, d: Dictionary) -> bool:
	match str(p.name):
		"crossfire":
			d.style = "volley"
			d.rays = cross_rays()
			d.len = clampf(pos.distance_to(g.player_pos) + 100.0, 300.0, 1500.0)
			return true
		"eclipse":
			d.style = "volley"
			d.hue = "danger"
			d.rays = eclipse_rays()
			d.len = 230.0
			return true
	return false

func special(name_: String) -> bool:
	match name_:
		"crossfire":
			for r in cross_rays():
				g.ebullet(r.at, r.ang, speed(290.0), BulletField.ORB)
			Audio.play("enemy_shoot", -2.0, 0.8)
			return true
		"eclipse":
			for r in eclipse_rays():
				g.ebullet(r.at, r.ang, speed(210.0), BulletField.DART)
			Audio.play("burst", -4.0, 1.2)
			return true
	return false
