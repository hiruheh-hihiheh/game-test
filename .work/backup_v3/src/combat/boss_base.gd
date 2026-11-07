class_name BossBase
extends RefCounted
## Shared boss behaviour: parts, armour, weak points, three stages, telegraphs and death.
## Each boss script only describes what makes it different.

const STAGE_AT := [0.67, 0.34]

var g
var def: Dictionary = {}
var pos := Vector2.ZERO
var hp := 100.0
var max_hp := 100.0
var stage := 0
var t := 0.0
var parts: Array = []
var attack_t := 1.8
var order := 0
var entering := true
var dying := 0.0
var boom_t := 0.0
var charge := 0.0
var pending := ""
var stream_t := 0.0
var stream_angle := 0.0
var stream_gap := 0.0
var stream_arms := 2
var home := Vector2.ZERO
var next_part_id := 1
var dead := false

func setup(game, definition: Dictionary, hp_scale: float) -> void:
	g = game
	def = definition
	max_hp = float(def.hp) * hp_scale
	hp = max_hp
	home = Vector2(g.W * 0.5, g.top + 270.0)
	pos = Vector2(g.W * 0.5, -300.0)
	build()

## Override: create parts.
func build() -> void:
	pass

## Override: the attack rotation for the current stage.
func rotation() -> Array:
	return ["fan"]

## Override: movement. The default is a slow sway.
func move(_dt: float) -> void:
	var sway: float = maxf(30.0, float(g.W) * 0.5 - float(def.get("half_width", 230.0)))
	pos.x = float(g.W) * 0.5 + sin(t * 0.7) * sway
	pos.y = home.y + sin(t * 1.4) * 18.0

## Override: anything else that happens every frame.
func tick(_dt: float) -> void:
	pass

## Override: react to a new stage.
func on_stage() -> void:
	pass

## Override: unique attacks. Return true when handled.
func special(_name: String) -> bool:
	return false

func add_part(tex: Texture2D, size: float, offset: Vector2, r: float, mult: float, opts: Dictionary = {}) -> Dictionary:
	var sp: Sprite2D = g.take_sprite()
	sp.texture = tex
	sp.scale = Vector2.ONE * (size / 512.0)
	sp.z_index = int(opts.get("z", 0))
	var hue: float = opts.get("hue", def.get("hue", 0.0))
	if hue != 0.0:
		sp.material = g.hue_mat(hue)
	var part := {
		"id": 1000000 + next_part_id, "sprite": sp, "offset": offset, "r": r, "mult": mult, "hue": hue, "alive": true,
		"own_hp": float(opts.get("own_hp", 0.0)), "weak": opts.get("weak", false), "flash": 0.0, "size": size,
		"at": pos + offset, "rx": float(opts.get("rx", r)), "ry": float(opts.get("ry", r)), "block": opts.get("block", false), "arc": opts.get("arc", {}),
	}
	next_part_id += 1
	parts.append(part)
	return part

func kill_part(part: Dictionary, explode := true) -> void:
	part.alive = false
	(part.sprite as Sprite2D).visible = false
	if explode:
		Audio.play("explode_m")
		g.fx.boom(part.at, float(part.size) * 1.3, true, 0.5)
		g.fx.sparks(part.at, 22, UI.ORANGE, 320.0, 0.6, 15.0)
		g.kick(9.0)

func can_be_hit() -> bool:
	return not entering and dying <= 0.0

func update(dt: float) -> void:
	if dying > 0.0:
		_update_death(dt)
		return
	t += dt
	if entering:
		_enter(dt)
	else:
		move(dt)
		attack_t -= dt * (1.0 + float(stage) * 0.18) * lerpf(1.0, 1.1, float(g.scale_cfg.d))
		if attack_t <= 0.0 and charge <= 0.0:
			var list := rotation()
			pending = list[order % list.size()]
			order += 1
			charge = 0.55
			attack_t = 2.9
			Audio.play("charge", -3.0)
		if charge > 0.0:
			charge -= dt
			if charge <= 0.0:
				attack(pending)
		_update_stream(dt)
		_contact_damage()
	tick(dt)
	_sync_parts(dt)

func _enter(dt: float) -> void:
	pos.y = move_toward(pos.y, home.y, dt * 240.0)
	if pos.y >= home.y:
		entering = false

func _sync_parts(dt: float) -> void:
	for p in parts:
		var sp: Sprite2D = p.sprite
		if not p.alive:
			continue
		p.at = pos + (p.offset as Vector2)
		sp.position = p.at
		if float(p.flash) > 0.0:
			p.flash -= dt
			if float(p.flash) <= 0.0:
				sp.material = g.hue_mat(float(p.hue)) if float(p.hue) != 0.0 else null

func _contact_damage() -> void:
	for p in parts:
		if not p.alive or not (p.arc as Dictionary).is_empty():
			continue
		var d: float = (g.player_pos as Vector2).distance_to(p.at)
		if d < float(p.r) * 0.85:
			g.hurt_player(36.0)
			return

func _inside(p: Dictionary, at: Vector2) -> bool:
	var arc: Dictionary = p.arc
	if not arc.is_empty():
		var to: Vector2 = at - pos
		var d := to.length()
		if d < float(arc.r0) or d > float(arc.r1):
			return false
		return absf(wrapf(to.angle() - float(arc.angle), -PI, PI)) < float(arc.half)
	var off: Vector2 = at - (p.at as Vector2)
	var ex: float = off.x / float(p.rx)
	var ey: float = off.y / float(p.ry)
	return ex * ex + ey * ey < 1.0

## Finds the part a shot at this point touches. Blocking parts sit first in the list.
func hit_part(at: Vector2) -> Dictionary:
	for p in parts:
		if p.alive and _inside(p, at):
			return p
	return {}

func beam_part(x: float, width: float, from_y: float) -> Dictionary:
	var best := {}
	var best_y := -1e9
	for p in parts:
		if not p.alive:
			continue
		var low: float
		if not (p.arc as Dictionary).is_empty():
			# Walk down the column to find where the beam meets this ring segment.
			low = -1e9
			var y := from_y
			while y > 0.0:
				if _inside(p, Vector2(x, y)):
					low = y
					break
				y -= 30.0
			if low < -1e8:
				continue
		else:
			if absf(float(p.at.x) - x) > float(p.rx) + width:
				continue
			low = float(p.at.y) + float(p.ry) * 0.6
		if low > best_y and low < from_y:
			best_y = low
			best = p
	if best.is_empty():
		return {}
	return {"part": best, "y": best_y}

## Applies a hit. Returns false when the part stopped the shot cold.
func take_hit(part: Dictionary, damage: float, at: Vector2) -> bool:
	var mult: float = part.mult
	if mult <= 0.0 and float(part.own_hp) <= 0.0:
		g.fx.sparks(at, 2, Color(0.75, 0.8, 0.9), 200.0, 0.18, 8.0)
		Audio.play("clank", -10.0, 1.0, 0.12)
		return false
	var sp: Sprite2D = part.sprite
	sp.material = g.hue_mat(0.0, true)
	part.flash = 0.05
	if float(part.own_hp) > 0.0:
		part.own_hp = float(part.own_hp) - damage
		if float(part.own_hp) <= 0.0:
			on_part_destroyed(part)
	if mult > 0.0:
		var dealt := damage * mult
		_apply(dealt)
		g.score += int(2.0 * mult)
		g.add_energy(0.14)
		if bool(part.weak):
			g.fx.sparks(at, 4, UI.GOLD, 260.0, 0.26, 12.0)
			Audio.play("crit", -13.0, 1.2, 0.08)
		elif mult < 0.6:
			g.fx.sparks(at, 1, Color(0.75, 0.8, 0.9), 160.0, 0.16, 7.0)
			Audio.play("clank", -14.0, 1.0, 0.12)
		else:
			g.fx.sparks(at, 2, UI.ORANGE, 220.0, 0.22, 10.0)
			Audio.play("hit", -13.0, 0.8, 0.1)
	return true

## Override: a part with its own health just broke.
func on_part_destroyed(part: Dictionary) -> void:
	kill_part(part)

func nova_hit(damage: float) -> void:
	_apply(damage)
	g.fx.sparks(pos, 12, UI.CYAN, 300.0, 0.4, 12.0)

func _apply(damage: float) -> void:
	if dying > 0.0:
		return
	hp -= damage
	var ratio := hp / max_hp
	var next := 2 if ratio < STAGE_AT[1] else (1 if ratio < STAGE_AT[0] else 0)
	if next > stage:
		stage = next
		_stage_up()
	if hp <= 0.0:
		_begin_death()

func _stage_up() -> void:
	g.kick(10.0)
	g.do_flash(0.3, UI.ORANGE)
	Audio.play("explode_m")
	g.fx.ring(pos, 0.6, 60.0, 420.0, UI.ORANGE, 8.0)
	g.fx.boom(pos, 280.0, true, 0.5)
	var lines: Array = def.get("stage_lines", ["", ""])
	g.hud.banner_show("PHASE %d" % (stage + 1), str(lines[stage - 1]), 1.5, UI.ORANGE)
	g.field.clear_circle(g.player_pos, 300.0)
	attack_t = 1.4
	on_stage()

func _begin_death() -> void:
	dying = 2.1
	boom_t = 0.0
	g.time_scale = 0.3
	g.field.clear()
	g.hazards.beams.clear()
	for e in g.enemies:
		if not e.ally:
			g._kill_enemy(e, true)
	Audio.stop_music(0.4)
	Save.haptic(120)
	g.hud.banner_show(str(def.death_title), str(def.death_line), 2.2, UI.GOLD)

func _update_death(dt: float) -> void:
	var real: float = dt / maxf(0.05, float(g.time_scale))
	dying -= real
	boom_t -= real
	for p in parts:
		if p.alive:
			(p.sprite as Sprite2D).position = (p.at as Vector2) + Vector2(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0))
	if boom_t <= 0.0:
		boom_t = 0.16
		var at: Vector2 = pos + Vector2(randf_range(-230.0, 230.0), randf_range(-120.0, 120.0))
		g.fx.boom(at, randf_range(120.0, 220.0), true, 0.5)
		g.fx.sparks(at, 14, UI.ORANGE, 300.0, 0.5, 14.0)
		Audio.play("explode_m", -2.0, 1.0, 0.15)
		g.kick(7.0)
	if dying <= 0.0:
		_finish_death()

func _finish_death() -> void:
	Audio.play("explode_l")
	g.do_flash(1.0, Color.WHITE)
	g.kick(20.0)
	g.fx.boom(pos, 640.0, true, 1.0)
	g.fx.ring(pos, 0.9, 80.0, 900.0, UI.ORANGE, 12.0)
	g.fx.ring(pos, 1.1, 40.0, 700.0, Color.WHITE, 6.0)
	g.fx.sparks(pos, 90, UI.ORANGE, 560.0, 1.1, 22.0)
	for p in parts:
		if (p.sprite as Sprite2D) != null:
			g.give_sprite(p.sprite)
			p.alive = false
	dead = true
	g.on_boss_destroyed()

## Where homing shots should go: the part that takes the most damage right now.
func aim_point() -> Vector2:
	var best: float = 0.0
	var at := pos
	for p in parts:
		if not p.alive or not (p.arc as Dictionary).is_empty():
			continue
		var value: float = maxf(float(p.mult), 0.3 if float(p.own_hp) > 0.0 else 0.0)
		if value > best:
			best = value
			at = p.at
	return at

func muzzle() -> Vector2:
	return pos + Vector2(0, 90)

func speed(base: float) -> float:
	return base * lerpf(1.0, float(g.scale_cfg.bullet), 0.6) * float(g.bullet_mult)

## Attack library shared by every boss.
func attack(name_: String) -> void:
	if dying > 0.0 or special(name_):
		return
	var from := muzzle()
	Audio.play("enemy_shoot", -2.0, 0.7)
	match name_:
		"fan":
			var n := 9 + stage * 2
			for i in range(n):
				g.ebullet(from, PI * 0.5 + (float(i) - float(n - 1) * 0.5) * 0.17, speed(245.0), BulletField.DART)
		"aimed":
			_aimed(from)
		"burst":
			for i in range(4 + stage):
				g.after(float(i) * 0.26, _aimed_now)
		"ring":
			var count := 20 + stage * 4
			var gap := randi() % count
			for i in range(count):
				if i == gap or i == (gap + 1) % count:
					continue
				g.ebullet(from, float(i) * TAU / float(count), speed(220.0), BulletField.ORB)
		"spiral":
			stream_t = 1.9 + float(stage) * 0.4
			stream_angle = randf() * TAU
			stream_arms = 2 + stage
		"curtain":
			for row in range(3 + stage):
				g.after(float(row) * 0.8, curtain_row)
		"strike":
			for i in range(1 + stage):
				var x: float = randf_range(60.0, g.W - 60.0) if i > 0 else float(g.player_pos.x)
				g.hazards.add_beam("col", x, 0.95 + float(i) * 0.25, 0.55, UI.MAGENTA, 34.0)
		"rocks":
			g.spawn_group({"kind": "rocks", "form": "rain", "count": 4 + stage, "delay": 0.0})
		"raiders":
			g.spawn_group({"kind": "raider", "form": "dive", "count": 3 + stage, "delay": 0.0})
		"mines":
			g.spawn_group({"kind": "mine", "form": "scatter", "count": 2 + stage, "delay": 0.0})

func _aimed_now() -> void:
	if dying <= 0.0 and not dead:
		_aimed(muzzle())

func _aimed(from: Vector2) -> void:
	var aim: float = ((g.player_pos as Vector2) - from).angle()
	for i in range(3):
		g.ebullet(from, aim + (float(i) - 1.0) * 0.12, speed(305.0), BulletField.ORB)

func curtain_row(kind := BulletField.DART) -> void:
	if dying > 0.0 or dead:
		return
	var gap := randf_range(110.0, float(g.W) - 110.0)
	var x := 30.0
	while x < float(g.W):
		if absf(x - gap) > 118.0:
			g.ebullet(Vector2(x, pos.y + 30.0), PI * 0.5, speed(205.0), kind, 20.0)
		x += 58.0

func _update_stream(dt: float) -> void:
	if stream_t <= 0.0:
		return
	stream_t -= dt
	stream_gap -= dt
	if stream_gap <= 0.0:
		stream_gap = 0.11
		stream_angle += 0.41
		for arm in range(stream_arms):
			g.ebullet(muzzle(), stream_angle + float(arm) * TAU / float(stream_arms), speed(215.0), BulletField.ORB, 20.0)

func paint_add(c: CanvasItem) -> void:
	if charge > 0.0:
		var k: float = 1.0 - charge / 0.55
		UI.glow(c, muzzle(), 40.0 + k * 90.0, Color(1.0, 0.5, 0.3, 0.55 + k * 0.4))
	for p in parts:
		if p.alive and bool(p.weak):
			var pulse: float = 0.8 + 0.2 * sin(t * 6.0)
			c.draw_arc(p.at, float(p.r) + 10.0 * pulse, 0.0, TAU, 32, Color(UI.GOLD, 0.8), 3.0, true)
			UI.glow(c, p.at, float(p.r) * 1.5, Color(UI.GOLD, 0.2))
