extends BossBase
## A capital ship that fills the top of the arena. Strip its gun turrets to expose the bridge.

const HULL := preload("res://assets/starfall/gen/boss_admiral.png")
const TURRET := preload("res://assets/starfall/gen/boss_admiral_turret.png")

var turrets: Array = []
var bridge: Dictionary = {}
var turret_fire := 1.5

func build() -> void:
	def = def.duplicate()
	var w: float = float(g.W)
	var span: float = minf(w * 0.42, 280.0)
	var slots := [Vector2(-span, 60), Vector2(-span * 0.5, 120), Vector2(span * 0.5, 120), Vector2(span, 60)]
	for s in slots:
		turrets.append(add_part(TURRET, 96.0, s, 46.0, 0.5, {"own_hp": max_hp * 0.14, "z": 2, "hue": 0.0}))
	bridge = add_part(TURRET, 1.0, Vector2(0, 40), 82.0, 0.0, {"hue": 0.0, "z": 2})
	add_part(HULL, minf(w * 1.05, 760.0), Vector2.ZERO, 200.0, 0.0, {"rx": minf(w * 0.5, 350.0), "ry": 92.0, "hue": 0.0})
	home.y = float(g.top) + 280.0

func move(_dt: float) -> void:
	pos.x = float(g.W) * 0.5 + sin(t * 0.4) * 30.0
	pos.y = home.y + sin(t * 0.8) * 8.0 + (70.0 if stage == 2 else 0.0)

func tick(dt: float) -> void:
	turret_fire -= dt
	var alive := 0
	for p in turrets:
		if p.alive:
			alive += 1
			(p.sprite as Sprite2D).rotation = lerp_angle((p.sprite as Sprite2D).rotation, ((g.player_pos as Vector2) - (p.at as Vector2)).angle() - PI * 0.5, dt * 3.0)
	if turret_fire <= 0.0 and can_be_hit():
		turret_fire = 2.8 - float(stage) * 0.3
		for p in turrets:
			if p.alive:
				var aim: float = ((g.player_pos as Vector2) - (p.at as Vector2)).angle()
				g.ebullet(p.at, aim, speed(280.0), BulletField.ORB)
		Audio.play("enemy_shoot", -8.0, 0.9)
	if alive <= 2 and float(bridge.mult) <= 0.0:
		bridge.mult = 1.5
		bridge.weak = true
		g.hud.banner_show("BRIDGE EXPOSED", "Hit the gold ring", 1.5, UI.GOLD)
		Audio.play("warning", -8.0, 1.5)

func on_part_destroyed(part: Dictionary) -> void:
	kill_part(part)
	g.fx.ring(part.at, 0.4, 20.0, 180.0, UI.ORANGE, 6.0)

func rotation() -> Array:
	if stage == 0:
		return ["broadside", "fan", "launch"]
	if stage == 1:
		return ["broadside", "barrage", "launch", "strike"]
	return ["barrage", "broadside", "ram", "strike", "launch"]

func special(name_: String) -> bool:
	match name_:
		"broadside":
			var n := 2 + stage
			for i in range(n):
				var y: float = float(g.player_pos.y) if i == 0 else randf_range(float(g.H) * 0.48, float(g.H) - 250.0)
				g.hazards.add_beam("row", y, 1.05 + float(i) * 0.2, 0.5, UI.RED, 34.0)
			return true
		"launch":
			g.spawn_group({"kind": "raider", "form": "pincer", "count": 4 + stage, "delay": 0.0, "mod": ""})
			return true
		"barrage":
			for i in range(8):
				g.after(float(i) * 0.16, _shell)
			return true
		"ram":
			# A telegraphed lane the width of the prow.
			g.hazards.add_beam("col", pos.x, 1.2, 0.7, UI.RED, 40.0, 130.0)
			return true
	return false

func _shell() -> void:
	if dying > 0.0 or dead:
		return
	var x: float = randf_range(60.0, float(g.W) - 60.0)
	g.ebullet(Vector2(x, pos.y + 90.0), PI * 0.5, speed(170.0), BulletField.HEAVY, 30.0)
