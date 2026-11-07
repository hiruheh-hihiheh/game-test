extends BossBase
## An asteroid fortress. A ring of boulders shields the core: break them or shoot the gaps.

const CORE := preload("res://assets/starfall/gen/boss_warden_core.png")
const ROCK := preload("res://assets/starfall/environment/asteroid_large.png")

var ring: Array = []
var ring_angle := 0.0
var ring_radius := 230.0

func build() -> void:
	for i in range(8):
		ring.append(add_part(ROCK, 120.0, Vector2.ZERO, 54.0, 0.0, {"own_hp": 5.0 * float(g.scale_cfg.hp), "hue": 0.0, "z": 1}))
	add_part(CORE, 340.0, Vector2.ZERO, 120.0, 1.0, {"weak": true})

func move(dt: float) -> void:
	pos.x = float(g.W) * 0.5 + sin(t * 0.5) * maxf(30.0, float(g.W) * 0.5 - 300.0)
	pos.y = home.y + sin(t * 1.1) * 14.0

func tick(dt: float) -> void:
	ring_angle += dt * (0.55 + float(stage) * 0.25)
	for i in range(ring.size()):
		var p: Dictionary = ring[i]
		p.offset = Vector2.from_angle(ring_angle + float(i) * TAU / float(ring.size())) * ring_radius
		(p.sprite as Sprite2D).rotation += dt * 0.9
	if stage >= 1 and g.player_alive and can_be_hit():
		# The Warden pulls the ship toward it from the second phase on.
		var pull := Vector2(0, -1).lerp(((pos - (g.player_pos as Vector2)).normalized()), 0.5)
		g.player_target += pull * (24.0 + float(stage) * 16.0) * dt

func rotation() -> Array:
	if stage == 0:
		return ["fan", "throw", "burst"]
	if stage == 1:
		return ["throw", "ring", "fan", "throw"]
	return ["hurl", "spiral", "rocks", "ring"]

func on_stage() -> void:
	if stage == 2:
		g.hazards.add_well(pos + Vector2(0, 40), 0.5, 40.0)

func special(name_: String) -> bool:
	match name_:
		"throw":
			Audio.play("rock", 0.0, 0.7)
			for i in range(1 + stage):
				var aim: float = ((g.player_pos as Vector2) - pos).angle() + (float(i) - float(stage) * 0.5) * 0.34
				g.spawn_enemy({"kind": "rock_m", "pos": pos + Vector2.from_angle(aim) * 130.0, "move": "straight", "vel": Vector2.from_angle(aim) * 280.0 * float(g.scale_cfg.speed)})
			return true
		"hurl":
			# Whatever remains of the ring is flung at the player.
			for p in ring:
				if p.alive:
					var aim: float = ((g.player_pos as Vector2) - (p.at as Vector2)).angle()
					g.ebullet(p.at, aim, speed(250.0), BulletField.HEAVY, 30.0)
			return true
	return false
