extends BossBase
## Three serpent heads on living necks, guarding a sealed heart.
## Each head you sever is a phase. The heart only opens once they are all gone.

const HEAD := preload("res://assets/starfall/gen/boss_hydra_head.png")
const SEG := preload("res://assets/starfall/gen/boss_hydra_seg.png")
const CORE := preload("res://assets/starfall/gen/boss_hydra_core.png")
const NECK_SEGMENTS := 5

var heads: Array = []
var heart: Dictionary = {}

func build() -> void:
	def = def.duplicate()
	def["half_width"] = 180.0
	var head_hp := max_hp * 0.2
	for i in range(3):
		var neck: Array = []
		for k in range(NECK_SEGMENTS):
			neck.append(add_part(SEG, 72.0 - float(k) * 3.0, Vector2.ZERO, 26.0, 0.0, {"hue": 0.0}))
		var head := add_part(HEAD, 170.0, Vector2.ZERO, 70.0, 1.0, {"own_hp": head_hp, "hue": 0.0, "z": 2, "weak": true})
		heads.append({"head": head, "neck": neck, "phase": float(i) * TAU / 3.0, "side": float(i) - 1.0, "fire": 1.0 + float(i) * 0.8})
	heart = add_part(CORE, 300.0, Vector2.ZERO, 100.0, 0.0, {"hue": 0.0, "z": -1})
	(heart.sprite as Sprite2D).modulate = Color(0.45, 0.4, 0.5)

func move(_dt: float) -> void:
	pos.x = float(g.W) * 0.5 + sin(t * 0.35) * 60.0
	pos.y = home.y - 60.0 + sin(t * 0.9) * 12.0

func tick(dt: float) -> void:
	var alive := 0
	for h in heads:
		var head: Dictionary = h.head
		if not head.alive:
			continue
		alive += 1
		var reach := 240.0 + sin(t * 0.8 + float(h.phase)) * 60.0
		var tip := Vector2(float(h.side) * 225.0 + sin(t * 1.1 + float(h.phase)) * 70.0, reach)
		head.offset = tip
		(head.sprite as Sprite2D).rotation = -atan2(tip.x, tip.y) * 0.5
		var neck: Array = h.neck
		for k in range(neck.size()):
			var f := float(k + 1) / float(neck.size() + 1)
			var wiggle := sin(t * 2.2 + f * 5.0 + float(h.phase)) * 34.0 * sin(f * PI)
			(neck[k] as Dictionary).offset = tip * f + Vector2(wiggle, 0)
		if can_be_hit():
			h.fire = float(h.fire) - dt
			if float(h.fire) <= 0.0:
				h.fire = 2.7 - float(stage) * 0.35
				_spit(head)
	if alive == 0 and float(heart.mult) <= 0.0:
		_open_heart()

func _spit(head: Dictionary) -> void:
	var from: Vector2 = (head.at as Vector2) + Vector2(0, 70)
	var aim: float = ((g.player_pos as Vector2) - from).angle()
	for i in range(3):
		g.ebullet(from, aim + (float(i) - 1.0) * 0.2, speed(250.0), BulletField.SPORE, 22.0)
	Audio.play("hatch", -8.0, 1.0, 0.1)

func on_part_destroyed(part: Dictionary) -> void:
	for h in heads:
		if h.head == part:
			kill_part(part)
			for seg in h.neck:
				kill_part(seg, false)
				g.fx.sparks(seg.at, 6, UI.MAGENTA, 200.0, 0.4, 11.0)
			g.fx.ring(part.at, 0.5, 30.0, 260.0, UI.MAGENTA, 7.0)
			return
	kill_part(part)

func _open_heart() -> void:
	heart.mult = 1.3
	heart.weak = true
	(heart.sprite as Sprite2D).modulate = Color.WHITE
	g.hud.banner_show("THE HEART OPENS", "Strike it now", 1.6, UI.MAGENTA)
	Audio.play("hatch", 0.0, 0.6)
	g.do_flash(0.4, UI.MAGENTA)

func muzzle() -> Vector2:
	return pos

func rotation() -> Array:
	var alive := 0
	for h in heads:
		if h.head.alive:
			alive += 1
	if alive == 3:
		return ["brood", "ring"]
	if alive > 0:
		return ["ring", "brood", "mines", "spiral"]
	return ["spiral", "ring", "brood", "curtain_spore"]

func special(name_: String) -> bool:
	match name_:
		"brood":
			g.spawn_group({"kind": "swarm", "form": "swarm", "count": 6 + stage * 2, "delay": 0.0})
			return true
		"curtain_spore":
			for row in range(3):
				g.after(float(row) * 0.8, curtain_row.bind(BulletField.SPORE))
			return true
	return false
