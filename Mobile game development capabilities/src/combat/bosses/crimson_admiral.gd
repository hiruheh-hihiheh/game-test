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

## Chosen when the charge begins, so the warning shows what the attack will really do. A y of -1 means "where the ship is when it fires".
func prepare_special(name_: String):
	var w := float(g.W)
	match name_:
		"broadside":
			var ys: Array = [-1.0]
			for i in range(1 + stage):
				ys.append(randf_range(float(g.H) * 0.48, float(g.H) - 250.0))
			return {"ys": ys}
		"launch":
			var n: int = Telegraph.group_count(g, {"kind": "raider", "count": 4 + stage})
			var ys: Array = []
			var markers: Array = []
			for i in range(n):
				var y := randf_range(190.0, 340.0)
				ys.append(y)
				markers.append({"pos": Vector2(30.0 if i % 2 == 0 else w - 30.0, y), "shape": "raider_side" if i % 2 == 0 else "raider_side_r", "delay": float(i) * float(Telegraph.STAGGER.pincer)})
			return {"ys": ys, "markers": markers}
		"barrage":
			var xs: Array = []
			for i in range(8):
				xs.append(randf_range(60.0, w - 60.0))
			return {"xs": xs}
		"ram":
			return {}
	return null

func describe_special(p: Dictionary, _k: float, d: Dictionary) -> bool:
	match str(p.name):
		"broadside":
			var ys: Array = []
			for i in range((p.ys as Array).size()):
				ys.append(float(g.player_pos.y) if i == 0 else float((p.ys as Array)[i]))
			d.style = "rows"
			d.hue = "danger"
			d.ys = ys
			d.hw = Hazards.WIDTH
			d.tracked = true
			return true
		"launch":
			d.style = "markers"
			d.markers = p.markers
			return true
		"barrage":
			d.style = "drops"
			d.xs = p.xs
			d.y0 = pos.y + 90.0
			return true
		"ram":
			d.style = "columns"
			d.hue = "danger"
			d.xs = [pos.x]
			d.hw = 130.0
			return true
	return false

## Each turret fires on its own timer, aimed at the ship at that moment: show it for the last 0.45 s of the wait.
func ambient() -> Array:
	var out: Array = []
	if not can_be_hit() or turret_fire <= 0.0 or turret_fire > 0.45:
		return out
	var k := 1.0 - turret_fire / 0.45
	for p in turrets:
		if p.alive:
			var ang := ((g.player_pos as Vector2) - (p.at as Vector2)).angle()
			out.append({"src": "boss", "kind": "turret", "style": "aimed", "hue": "warn", "k": k, "origin": p.at, "rays": [{"at": p.at, "ang": ang}],
				"len": clampf((p.at as Vector2).distance_to(g.player_pos) + 140.0, 260.0, 1500.0)})
	return out

func special(name_: String) -> bool:
	var p := plan_for(name_)
	match name_:
		"broadside":
			var ys: Array = p.ys
			for i in range(ys.size()):
				var y: float = float(g.player_pos.y) if i == 0 else float(ys[i])
				g.hazards.add_beam("row", y, 1.05 + float(i) * 0.2, 0.5, UI.RED, 34.0)
			return true
		"launch":
			_group({"kind": "raider", "form": "pincer", "count": 4 + stage, "delay": 0.0, "mod": ""}, "raider_side")
			return true
		"barrage":
			var xs: Array = p.xs
			for i in range(xs.size()):
				g.after(float(i) * Telegraph.SHELL_GAP, _shell.bind(float(xs[i])))
			g.tg.add("barrage", 0.0, float(xs.size()) * Telegraph.SHELL_GAP + 0.3, {"list": xs.duplicate()})
			return true
		"ram":
			# A telegraphed lane the width of the prow.
			g.hazards.add_beam("col", pos.x, 1.2, 0.7, UI.RED, 40.0, 130.0)
			return true
	return false

func _shell(x: float) -> void:
	g.tg.fired("barrage", x)
	if dying > 0.0 or dead:
		return
	g.ebullet(Vector2(x, pos.y + 90.0), PI * 0.5, speed(170.0), BulletField.HEAVY, 30.0)
