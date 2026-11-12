class_name BossBase
extends RefCounted
## Shared boss behaviour: parts, armour, weak points, three stages, telegraphs and death.
## Each boss script only describes what makes it different.

const STAGE_AT := [0.67, 0.34]
## Seconds between a boss picking an attack and firing it. The warning rides on this clock.
const CHARGE := 0.55
## The attacks that get a second, lower warning tone on top of the charge sound.
const DANGEROUS := ["strike", "ring", "ram", "meltdown", "collapse"]
const STREAM_STEP := 0.41
const STREAM_GAP := 0.11

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
## What the charge in progress will do, prepared when it began. `attack()` fires exactly this, so the warning and the
## attack cannot disagree. `plan` is the same dictionary while the attack runs.
var intent: Dictionary = {}
var plan: Dictionary = {}
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
		CombatAudio.explosion("part")
		g.fx.explode_part(part.at, float(part.size))
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
		attack_t -= dt * (1.0 + float(stage) * 0.18) * lerpf(1.0, 1.1, float(g.scale_cfg.d)) * lerpf(1.0, float(g.fire_mult_enemy), 0.5)
		if attack_t <= 0.0 and charge <= 0.0:
			var list := rotation()
			pending = list[order % list.size()]
			order += 1
			charge = CHARGE
			attack_t = 2.9
			intent = prepare(pending)
			Audio.play("charge", -3.0)
			if pending in DANGEROUS:
				Audio.play("warning", -9.0, 1.5)
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

## Applies a hit. Returns false when the part stopped the shot cold. `wpn` is the weapon that hit, used only for how it looks and sounds.
func take_hit(part: Dictionary, damage: float, at: Vector2, wpn := "") -> bool:
	var mult: float = part.mult
	g.combo_keep()
	var power := clampf(damage / 1.1, 0.7, 2.0)
	if mult <= 0.0 and float(part.own_hp) <= 0.0:
		g.fx.impact(at, wpn if wpn != "" else "pulse", 0.8, "shield")
		CombatAudio.impact(wpn, "shield", 0.8)
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
			g.fx.impact(at, wpn if wpn != "" else "pulse", power * 1.4)
			g.fx.sparks(at, 3, UI.GOLD, 260.0, 0.26, 12.0)
			Audio.play("crit", -13.0, 1.2, 0.08)
		elif mult < 0.6:
			g.fx.impact(at, wpn if wpn != "" else "pulse", power * 0.7, "shield")
			CombatAudio.impact(wpn, "shield", power * 0.7)
		else:
			g.fx.impact(at, wpn if wpn != "" else "pulse", power)
			CombatAudio.impact(wpn, "hull", power)
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
	CombatAudio.explosion("boss_chain")
	g.fx.ring(pos, 0.6, 60.0, 420.0, UI.ORANGE, 8.0)
	g.fx.explode_part(pos, 280.0)
	var lines: Array = def.get("stage_lines", ["", ""])
	g.hud.banner_show("PHASE %d" % (stage + 1), str(lines[stage - 1]), 1.5, UI.ORANGE)
	g.field.clear_circle(g.player_pos, 300.0)
	attack_t = 1.4
	on_stage()
	if charge > 0.0:
		# Counts depend on the stage, so a charge already running is re-prepared for the new one.
		intent = prepare(pending)

func _begin_death() -> void:
	dying = 2.1
	boom_t = 0.0
	g.time_scale = 0.3
	g.field.clear()
	g.hazards.beams.clear()
	intent = {}
	charge = 0.0
	g.tg.clear()
	g.pending.clear()
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
		g.fx.boss_blast(at, randf_range(120.0, 220.0))
		CombatAudio.explosion("boss_chain")
		g.kick(7.0)
	if dying <= 0.0:
		_finish_death()

func _finish_death() -> void:
	CombatAudio.explosion("boss_final")
	g.do_flash(1.0, Color.WHITE)
	g.kick(20.0)
	g.fx.boss_finale(pos, 640.0)
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
	plan = _take(name_)
	if dying > 0.0 or special(name_):
		return
	var from := muzzle()
	Audio.play("enemy_shoot", -2.0, 0.7)
	match name_:
		"fan":
			for r in Telegraph.fan_rays(from, int(plan.n)):
				g.ebullet(r.at, r.ang, speed(245.0), BulletField.DART)
		"aimed":
			_aimed(from)
		"burst":
			var n := int(plan.n)
			var shots: Array = []
			for i in range(n):
				shots.append(i)
				g.after(float(i) * Telegraph.BURST_GAP, _aimed_now.bind(i))
			g.tg.add("burst", 0.0, float(n) * Telegraph.BURST_GAP, {"n": n, "list": shots})
		"ring":
			for r in Telegraph.ring_rays(from, int(plan.count), int(plan.gap)):
				g.ebullet(r.at, r.ang, speed(220.0), BulletField.ORB)
		"spiral":
			stream_t = 1.9 + float(stage) * 0.4
			stream_angle = float(plan.angle)
			stream_arms = int(plan.arms)
		"curtain":
			run_curtain(BulletField.DART)
		"strike":
			var xs: Array = plan.xs
			for i in range(xs.size()):
				# The first column goes where the ship is when it fires, the rest were chosen at the start of the charge.
				var x: float = float(g.player_pos.x) if i == 0 else float(xs[i])
				g.hazards.add_beam("col", x, 0.95 + float(i) * 0.25, 0.55, UI.MAGENTA, 34.0)
		"rocks":
			_group({"kind": "rocks", "form": "rain", "count": 4 + stage, "delay": 0.0}, "rock")
		"raiders":
			_group({"kind": "raider", "form": "dive", "count": 3 + stage, "delay": 0.0}, "raider")
		"mines":
			_group({"kind": "mine", "form": "scatter", "count": 2 + stage, "delay": 0.0}, "mine")

## Starts a group using the entry positions chosen when the charge began, and keeps a marker for each one that has not arrived yet.
func _group(cfg: Dictionary, shape: String) -> void:
	cfg["xs"] = plan.get("xs", [])
	cfg["ys"] = plan.get("ys", [])
	g.spawn_group(cfg)
	if not Telegraph.summons_arrive:
		return
	var gap: float = float(Telegraph.STAGGER.get(str(cfg.form), 0.0))
	var members: Array = plan.markers
	for i in range(members.size()):
		if gap * float(i) > 0.0:
			g.tg.add("marker", 0.0, gap * float(i), {"pos": (members[i] as Dictionary).pos, "shape": str((members[i] as Dictionary).get("shape", shape))})

func _aimed_now(i := -1) -> void:
	g.tg.fired("burst", i)
	if dying <= 0.0 and not dead:
		_aimed(muzzle())

func _aimed(from: Vector2) -> void:
	var aim: float = ((g.player_pos as Vector2) - from).angle()
	for r in Telegraph.aimed_rays(from, aim):
		g.ebullet(r.at, r.ang, speed(305.0), BulletField.ORB)

## `gap` is the x of the opening; leave it out and one is chosen now.
func curtain_row(kind := BulletField.DART, gap := -1.0) -> void:
	if dying > 0.0 or dead:
		return
	if gap < 0.0:
		gap = randf_range(110.0, float(g.W) - 110.0)
	g.tg.fired("curtain_row", gap)
	for x in Telegraph.curtain_xs(gap, float(g.W)):
		g.ebullet(Vector2(float(x), pos.y + 30.0), PI * 0.5, speed(205.0), kind, 20.0)

## Rows of shots with an opening each, one every 0.8 s. Every row's opening was chosen when the charge began, and every
## row after the first shows its own warning for the 0.55 s before it falls.
func run_curtain(kind: int) -> void:
	var gaps: Array = plan.gaps
	var hue := "ion" if kind == BulletField.SHARD else ("warp" if kind == BulletField.SPORE else "warn")
	for row in range(gaps.size()):
		var at := float(row) * Telegraph.CURTAIN_GAP
		g.after(at, curtain_row.bind(kind, float(gaps[row])))
		if row > 0:
			g.tg.add("curtain_row", maxf(0.0, at - Telegraph.CURTAIN_WARN), at, {"gap": float(gaps[row]), "hue": hue, "list": [float(gaps[row])]})

func _update_stream(dt: float) -> void:
	if stream_t <= 0.0:
		return
	stream_t -= dt
	stream_gap -= dt
	if stream_gap <= 0.0:
		stream_gap = STREAM_GAP
		stream_angle += STREAM_STEP
		for arm in range(stream_arms):
			g.ebullet(muzzle(), stream_angle + float(arm) * TAU / float(stream_arms), speed(215.0), BulletField.ORB, 20.0)

# ---------- Telegraphs ----------

## Everything random about an attack is decided here, when the charge begins, and kept in the returned plan.
func prepare(name_: String) -> Dictionary:
	var p = prepare_special(name_)
	if p == null:
		p = {}
		var w := float(g.W)
		match name_:
			"fan":
				p.n = 9 + stage * 2
			"burst":
				p.n = 4 + stage
			"ring":
				p.count = 20 + stage * 4
				p.gap = randi() % int(p.count)
			"spiral":
				p.angle = randf() * TAU
				p.arms = 2 + stage
			"curtain", "curtain_ice":
				p.gaps = roll_gaps(3 + stage)
			"curtain_spore":
				p.gaps = roll_gaps(3)
			"strike":
				var xs: Array = [-1.0]
				for i in range(stage):
					xs.append(randf_range(60.0, w - 60.0))
				p.xs = xs
			"rocks":
				_roll_group(p, 4 + stage, "rain", 50.0, "rock")
			"raiders":
				_roll_group(p, 3 + stage, "dive", 70.0, "raider")
			"mines":
				_roll_group(p, 2 + stage, "scatter", 80.0, "mine")
	p.name = name_
	p.stage = stage
	return p

func roll_gaps(rows: int) -> Array:
	var out: Array = []
	for i in range(rows):
		out.append(randf_range(110.0, float(g.W) - 110.0))
	return out

## Picks where each member of a group enters, and the markers that will show it.
func _roll_group(p: Dictionary, count: int, form: String, margin: float, shape: String) -> void:
	var n: int = Telegraph.group_count(g, {"kind": "rocks" if shape == "rock" else shape, "count": count})
	var xs: Array = []
	var markers: Array = []
	for i in range(n):
		var x := randf_range(margin, float(g.W) - margin)
		xs.append(x)
		markers.append({"pos": Vector2(x, float(g.top) + Telegraph.MARKER_Y), "shape": shape, "delay": float(i) * float(Telegraph.STAGGER[form])})
	p.xs = xs
	p.markers = markers

## Override: prepare a boss-specific attack. Return null when `name_` is not one of yours, otherwise a dictionary
## (empty if nothing about it is random).
func prepare_special(_name: String):
	return null

## Override: describe the warning for one of your attacks into `d` (see `describe`). Return true when handled.
func describe_special(_p: Dictionary, _k: float, _d: Dictionary) -> bool:
	return false

## Override: warnings for attacks that run on their own timers rather than through a charge.
func ambient() -> Array:
	return []

## The warning for a prepared attack `k` of the way through its charge: the real geometry, as a descriptor.
func describe(p: Dictionary, k: float) -> Dictionary:
	var from := muzzle()
	var player: Vector2 = g.player_pos
	var aim := (player - from).angle()
	var reach := clampf(from.distance_to(player) + 140.0, 260.0, 1500.0)
	var d := {"src": "boss", "kind": str(p.name), "hue": "warn", "k": k, "origin": from, "plan": p}
	if describe_special(p, k, d):
		return {} if str(d.get("style", "")) == "markers" and not Telegraph.summons_arrive else d
	var w := float(g.W)
	match str(p.name):
		"fan":
			d.style = "fan"
			d.rays = Telegraph.fan_rays(from, int(p.n))
			d.len = 560.0
		"aimed":
			d.style = "aimed"
			d.rays = Telegraph.aimed_rays(from, aim)
			d.len = reach
		"burst":
			d.style = "burst"
			d.rays = Telegraph.aimed_rays(from, aim)
			d.len = reach
			d.n = int(p.n)
			d.left = int(p.n)
		"ring":
			var count := int(p.count)
			var gap := int(p.gap)
			var step := TAU / float(count)
			d.style = "ring_gap"
			d.hue = "danger"
			d.rays = Telegraph.ring_rays(from, count, gap)
			d.step = step
			d.gap_ang = (float(gap) + 0.5) * step
			d.edge_a = float((gap - 1 + count) % count) * step
			d.edge_b = float((gap + 2) % count) * step
		"spiral":
			d.style = "spiral"
			d.hue = "arc"
			d.arms = int(p.arms)
			d.a0 = float(p.angle) + STREAM_STEP
			d.kk = STREAM_STEP / (STREAM_GAP * speed(215.0))
		"curtain", "curtain_ice", "curtain_spore":
			var hue := "ion" if str(p.name) == "curtain_ice" else ("warp" if str(p.name) == "curtain_spore" else "warn")
			d = Telegraph.curtain_desc(pos.y + 30.0, float((p.gaps as Array)[0]), w, k, hue)
			d.kind = str(p.name)
			d.rows = (p.gaps as Array).size()
		"strike":
			var cols: Array = []
			for i in range((p.xs as Array).size()):
				cols.append(player.x if i == 0 else float((p.xs as Array)[i]))
			d.style = "columns"
			d.hue = "warp"
			d.xs = cols
			d.hw = Hazards.WIDTH
			d.tracked = true
			d.track_y = player.y - 190.0
		"rocks", "raiders", "mines":
			d.style = "markers"
			d.markers = p.markers
		_:
			return {}
	if str(d.get("style", "")) == "markers" and not Telegraph.summons_arrive:
		return {}
	return d

func paint_add(c: CanvasItem) -> void:
	for p in parts:
		if p.alive and bool(p.weak):
			var pulse: float = 0.8 + 0.2 * sin(t * 6.0)
			c.draw_arc(p.at, float(p.r) + 10.0 * pulse, 0.0, TAU, 32, Color(UI.GOLD, 0.8), 3.0, true)
			UI.glow(c, p.at, float(p.r) * 1.5, Color(UI.GOLD, 0.2))

## The plan the running attack was prepared with. Falls back to a fresh one when an attack is called directly.
func _take(name_: String) -> Dictionary:
	var p := intent
	intent = {}
	if str(p.get("name", "")) == name_ and int(p.get("stage", -1)) == stage:
		return p
	return prepare(name_)

## For `special()`: the plan of the attack being run.
func plan_for(name_: String) -> Dictionary:
	if str(plan.get("name", "")) != name_ or int(plan.get("stage", -1)) != stage:
		plan = prepare(name_)
	return plan
