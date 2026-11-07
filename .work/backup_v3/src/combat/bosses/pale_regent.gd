extends BossBase
## A towering ice crown that blinks around the arena and raises the dead.
## From the second phase it casts false images. Only the real one has a glowing heart.

const BODY := preload("res://assets/starfall/gen/boss_regent.png")
const SHARD := preload("res://assets/starfall/gen/boss_regent_shard.png")

var crown: Dictionary = {}
var heart: Dictionary = {}
var decoys: Array = []
var shards: Array = []
var blink_t := 0.0
var blink_to := Vector2.ZERO
var alpha := 1.0

func build() -> void:
	def = def.duplicate()
	def["half_width"] = 240.0
	for i in range(4):
		shards.append(add_part(SHARD, 90.0, Vector2.ZERO, 34.0, 0.0, {"hue": 0.0, "z": 1, "own_hp": 7.0 * float(g.scale_cfg.hp)}))
	heart = add_part(SHARD, 1.0, Vector2(0, 168), 58.0, 1.6, {"hue": 0.0, "weak": true})
	crown = add_part(BODY, 460.0, Vector2.ZERO, 190.0, 0.35, {"hue": 0.0, "rx": 210.0, "ry": 190.0})

func move(_dt: float) -> void:
	if blink_t > 0.0:
		return
	pos.y = home.y + sin(t * 1.0) * 14.0

func tick(dt: float) -> void:
	for i in range(shards.size()):
		var p: Dictionary = shards[i]
		var a := t * 1.1 + float(i) * TAU / float(shards.size())
		p.offset = Vector2(cos(a) * 280.0, sin(a) * 120.0 + 100.0)
		(p.sprite as Sprite2D).rotation = a
	if blink_t > 0.0:
		blink_t -= dt
		alpha = absf(blink_t - 0.4) / 0.4
		if blink_t < 0.4 and pos != blink_to:
			pos = blink_to
		(crown.sprite as Sprite2D).modulate.a = alpha
	else:
		(crown.sprite as Sprite2D).modulate.a = 1.0
	for d in decoys:
		if d.alive:
			(d.sprite as Sprite2D).modulate.a = 0.7 + sin(t * 3.0) * 0.1

func blink() -> void:
	blink_t = 0.8
	var margin := minf(240.0, float(g.W) * 0.33)
	blink_to = Vector2(randf_range(margin, float(g.W) - margin), home.y)
	Audio.play("ice", -2.0, 0.6)
	g.fx.sparks(pos, 26, Color(0.7, 0.95, 1.0), 300.0, 0.5, 13.0)

func rotation() -> Array:
	if stage == 0:
		return ["shards", "blink", "curtain_ice", "shards"]
	if stage == 1:
		return ["mirror", "shards", "frost", "blink", "raise"]
	return ["mirror", "curtain_ice", "raise", "blink", "frost", "strike"]

func special(name_: String) -> bool:
	match name_:
		"shards":
			var from: Vector2 = pos + Vector2(0, 120)
			var n := 7 + stage * 2
			var aim: float = ((g.player_pos as Vector2) - from).angle()
			for i in range(n):
				g.ebullet(from, aim + (float(i) - float(n - 1) * 0.5) * 0.15, speed(290.0), BulletField.SHARD, 22.0)
			Audio.play("ice", -5.0, 1.2)
			return true
		"curtain_ice":
			for row in range(3 + stage):
				g.after(float(row) * 0.8, curtain_row.bind(BulletField.SHARD))
			return true
		"frost":
			g.hazards.event("frost", 2.0)
			return true
		"raise":
			g.spawn_group({"kind": "revenant", "form": "line", "count": 3 + stage, "delay": 0.0, "mod": ""})
			return true
		"blink":
			blink()
			return true
		"mirror":
			_mirror()
			return true
	return false

func _mirror() -> void:
	blink()
	blink_to = Vector2(float(g.W) * 0.5, home.y)
	for d in decoys:
		if d.alive:
			kill_part(d, false)
	decoys.clear()
	var slots := [0.1, 0.9]
	for k in slots:
		var d := add_part(BODY, 400.0, Vector2.ZERO, 170.0, 0.0, {"hue": 0.0, "own_hp": 0.5, "rx": 170.0, "ry": 170.0})
		d.offset = Vector2(float(g.W) * float(k), home.y + 60.0) - pos
		d["decoy_at"] = Vector2(float(g.W) * float(k), home.y + 60.0)
		(d.sprite as Sprite2D).modulate = Color(0.75, 0.9, 1.0, 0.7)
		parts.erase(d)
		parts.push_front(d)
		decoys.append(d)
	Audio.play("ice", 0.0, 0.8)

func _sync_parts(dt: float) -> void:
	for d in decoys:
		if d.alive:
			d.offset = (d.decoy_at as Vector2) - pos
	super._sync_parts(dt)

func on_part_destroyed(part: Dictionary) -> void:
	if part in decoys:
		# Shooting a false image shatters it into a burst of ice.
		kill_part(part, false)
		g.fx.sparks(part.at, 26, Color(0.7, 0.95, 1.0), 320.0, 0.5, 13.0)
		Audio.play("ice", -2.0)
		for i in range(10):
			g.ebullet(part.at, float(i) * TAU / 10.0, speed(210.0), BulletField.SHARD, 18.0)
		return
	kill_part(part)
