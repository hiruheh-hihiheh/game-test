class_name Hazards
extends RefCounted
## Sector set pieces: flares, broadside lanes, ember and frost zones, gravity wells, spokes.
## Everything dangerous is telegraphed first, so damage from these always feels earned.

const WIDTH := 58.0

var g
var beams: Array = []
var zones: Array = []
var wells: Array = []
var spokes: Array = []
var warnings: Array = []

func _init(game) -> void:
	g = game

func event(name_: String, amount: float) -> void:
	var n := int(amount)
	match name_:
		"flare":
			for i in range(n):
				var x: float = randf_range(60.0, g.W - 60.0) if i > 0 else float(g.player_pos.x)
				add_beam("col", x, 0.95 + float(i) * 0.3, 0.55, UI.ORANGE, 34.0)
		"row":
			for i in range(n):
				var y: float = randf_range(g.H * 0.46, g.H - 240.0) if i > 0 else float(g.player_pos.y)
				add_beam("row", y, 1.05 + float(i) * 0.3, 0.5, UI.RED, 34.0)
		"ember":
			for i in range(n):
				add_zone("ember", roll_spot("ember"), 120.0, 11.0)
		"frost":
			for i in range(n):
				add_zone("frost", roll_spot("frost"), 170.0, 13.0)
		"well":
			for i in range(n):
				add_well(roll_spot("well"), 1.0, 12.0)
		"spokes":
			add_spokes(Vector2(g.W * 0.5, g.H * 0.46), 3, 0.5, 11.0)

## Where the next ember zone, frost zone or well would go. Bosses call this when a charge begins so the warning shows the real spot.
func roll_spot(kind: String) -> Vector2:
	match kind:
		"ember":
			return Vector2(randf_range(120.0, g.W - 120.0), randf_range(g.H * 0.48, g.H - 300.0))
		"frost":
			return Vector2(randf_range(120.0, g.W - 120.0), randf_range(g.top + 260.0, g.H - 340.0))
	return Vector2(randf_range(120.0, g.W - 120.0), randf_range(g.top + 300.0, g.H * 0.6))

func add_beam(axis: String, at: float, warn: float, live: float, color: Color, damage: float, width := WIDTH) -> void:
	beams.append({"axis": axis, "at": at, "warn": warn, "live": live, "t": 0.0, "color": color, "dmg": damage, "fired": false, "w": width})

func add_zone(kind: String, pos: Vector2, r: float, life: float) -> void:
	var z := {"kind": kind, "pos": pos, "r": r, "life": life, "age": 0.0}
	zones.append(z)
	if kind == "frost":
		g.field.frost.append(z)
	Audio.play("ice" if kind == "frost" else "flame", -8.0, 0.8)

func add_well(pos: Vector2, pull: float, life: float) -> void:
	var w := {"pos": pos, "pull": pull, "life": life, "age": 0.0, "eats": false}
	wells.append(w)
	g.field.wells.append(w)
	Audio.play("well", -3.0)

func add_singularity(pos: Vector2) -> void:
	var w := {"pos": pos, "pull": 3.5, "life": 3.0, "age": 0.0, "eats": true}
	wells.append(w)
	g.field.wells.append(w)

## `angle` and `dir` (1 or -1) are chosen at random unless the caller already chose them for its warning.
func add_spokes(center: Vector2, arms: int, speed: float, life: float, angle := -1.0, dir := 0.0) -> void:
	if dir == 0.0:
		dir = 1.0 if randf() < 0.5 else -1.0
	if angle < 0.0:
		angle = randf() * TAU
	spokes.append({"c": center, "arms": arms, "speed": speed * dir, "angle": angle, "t": 0.0, "warn": 1.4, "life": life})
	Audio.play("charge", -3.0)

func side_warning() -> void:
	warnings.append({"kind": "sides", "life": 0.9})

func lane_warning(y: float) -> void:
	warnings.append({"kind": "lane", "y": y, "life": 1.0})

func pull_player(dt: float) -> void:
	for w in wells:
		if w.eats:
			continue
		var to: Vector2 = (w.pos as Vector2) - (g.player_pos as Vector2)
		var d: float = maxf(to.length(), 60.0)
		g.player_target += to.normalized() * float(w.pull) * 190.0 * minf(1.0, 340.0 / d) * dt

func update(dt: float) -> void:
	_update_beams(dt)
	_update_zones(dt)
	_update_wells(dt)
	_update_spokes(dt)
	for i in range(warnings.size() - 1, -1, -1):
		warnings[i].life -= dt
		if float(warnings[i].life) <= 0.0:
			warnings.remove_at(i)

func _update_beams(dt: float) -> void:
	for i in range(beams.size() - 1, -1, -1):
		var b: Dictionary = beams[i]
		b.t += dt
		if float(b.t) < float(b.warn):
			continue
		if not b.fired:
			b.fired = true
			Audio.play("laser", -5.0)
			g.kick(6.0)
		if float(b.t) >= float(b.warn) + float(b.live):
			beams.remove_at(i)
			continue
		if g.player_alive:
			var p: float = g.player_pos.x if str(b.axis) == "col" else g.player_pos.y
			if absf(p - float(b.at)) < float(b.w):
				g.hurt_player(float(b.dmg))

func _update_zones(dt: float) -> void:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		z.life -= dt
		z.age += dt
		z.pos.y += 20.0 * dt
		if float(z.life) <= 0.0:
			zones.remove_at(i)
			g.field.frost.erase(z)
			continue
		if str(z.kind) == "ember" and g.player_alive and float(z.age) > 0.5:
			if (g.player_pos as Vector2).distance_to(z.pos) < float(z.r):
				g.tracker.ember = float(g.tracker.ember) + dt
				g.add_energy(dt * 9.0)
				if g.shield > 0.0:
					g.shield = maxf(0.0, g.shield - dt * 16.0)
					g.shield_idle = 0.0
				if randf() < dt * 22.0:
					g.fx.spark(g.player_pos, Vector2(randf_range(-40.0, 40.0), -80.0), 0.3, UI.ORANGE, 11.0)

func _update_wells(dt: float) -> void:
	for i in range(wells.size() - 1, -1, -1):
		var w: Dictionary = wells[i]
		w.life -= dt
		w.age += dt
		if w.eats:
			g.field.clear_circle(w.pos, 70.0)
			for e in g.enemies:
				if e.dead or e.ally or e.heavy or e.cover:
					continue
				var to: Vector2 = (w.pos as Vector2) - (e.pos as Vector2)
				if to.length() < 460.0:
					e.pos += to.normalized() * 240.0 * dt
		if float(w.life) <= 0.0:
			if w.eats:
				_detonate(w)
			wells.remove_at(i)
			g.field.wells.erase(w)

func _detonate(w: Dictionary) -> void:
	Audio.play("burst", 0.0, 1.1)
	g.do_flash(0.4, UI.VIOLET)
	g.fx.boom(w.pos, 520.0, true, 0.6)
	g.fx.ring(w.pos, 0.6, 40.0, 420.0, UI.VIOLET, 12.0)
	var damage: float = 14.0 * float(g.shot_power())
	for e in g.enemies:
		if not e.dead and not e.ally and (w.pos as Vector2).distance_to(e.pos) < 420.0:
			g._hit_enemy(e, damage, e.pos, false, true)
	if g.boss != null and g.boss.can_be_hit():
		g.boss.nova_hit(damage * 2.2)

func _update_spokes(dt: float) -> void:
	for i in range(spokes.size() - 1, -1, -1):
		var sp: Dictionary = spokes[i]
		sp.t += dt
		if float(sp.t) >= float(sp.life):
			spokes.remove_at(i)
			continue
		if float(sp.t) < float(sp.warn):
			sp.angle += float(sp.speed) * dt * 0.25
			continue
		sp.angle += float(sp.speed) * dt
		if not g.player_alive:
			continue
		var to: Vector2 = (g.player_pos as Vector2) - (sp.c as Vector2)
		for a in range(int(sp.arms)):
			var ang: float = float(sp.angle) + float(a) * TAU / float(sp.arms)
			var along: float = to.dot(Vector2.from_angle(ang))
			var off: float = absf(to.dot(Vector2.from_angle(ang + PI * 0.5)))
			if along > 0.0 and off < 22.0:
				g.hurt_player(30.0)

func paint_ground(c: CanvasItem) -> void:
	for z in zones:
		var fade: float = clampf(float(z.life), 0.0, 1.0) * clampf(float(z.age) * 2.0, 0.0, 1.0)
		var color: Color = UI.ORANGE if str(z.kind) == "ember" else Color(0.6, 0.95, 1.0)
		UI.glow(c, z.pos, float(z.r) * 1.25, Color(color, 0.5 * fade))
		c.draw_arc(z.pos, float(z.r), g.t * 0.5, g.t * 0.5 + TAU, 40, Color(color, 0.7 * fade), 3.0, true)
		# Distinct edge shapes, so ember and frost differ without relying on colour.
		var marks := 10 if str(z.kind) == "ember" else 6
		for i in range(marks):
			var a: float = float(i) * TAU / float(marks) + g.t * (0.6 if str(z.kind) == "ember" else -0.2)
			var d := Vector2.from_angle(a)
			var at: Vector2 = (z.pos as Vector2) + d * float(z.r)
			if str(z.kind) == "ember":
				c.draw_line(at, at + d * 14.0, Color(color, 0.8 * fade), 3.0)
			else:
				c.draw_line(at - d.orthogonal() * 10.0, at + d.orthogonal() * 10.0, Color(color, 0.8 * fade), 3.0)
	for w in wells:
		var fade: float = clampf(float(w.life), 0.0, 1.0)
		var col: Color = UI.VIOLET
		var grow: float = clampf(float(w.age) * 2.0, 0.0, 1.0)
		var rot: float = g.t * (2.0 if w.eats else 1.0)
		for k in range(4):
			var r: float = (70.0 + float(k) * 34.0 + fmod(g.t * 40.0, 34.0)) * grow * (2.0 if w.eats else 1.0)
			c.draw_arc(w.pos, r, rot + float(k), rot + float(k) + 4.2, 32, Color(col, (0.65 - float(k) * 0.12) * fade), 3.0, true)
		UI.glow(c, w.pos, 90.0 * grow, Color(0.1, 0.0, 0.3, 0.9 * fade))

func paint_air(c: CanvasItem) -> void:
	var W: float = g.W
	var H: float = g.H
	for b in beams:
		var col: Color = b.color
		var w: float = b.w
		var at: float = b.at
		var charging: bool = float(b.t) < float(b.warn)
		if charging:
			var k: float = float(b.t) / float(b.warn)
			var blink: float = 0.3 + 0.3 * absf(sin(g.t * (10.0 + k * 22.0)))
			if str(b.axis) == "col":
				c.draw_rect(Rect2(at - w, 0, w * 2.0, H), Color(col, blink * 0.14))
				c.draw_line(Vector2(at - w, 0), Vector2(at - w, H), Color(col, blink + 0.2), 3.0)
				c.draw_line(Vector2(at + w, 0), Vector2(at + w, H), Color(col, blink + 0.2), 3.0)
			else:
				c.draw_rect(Rect2(0, at - w, W, w * 2.0), Color(col, blink * 0.14))
				c.draw_line(Vector2(0, at - w), Vector2(W, at - w), Color(col, blink + 0.2), 3.0)
				c.draw_line(Vector2(0, at + w), Vector2(W, at + w), Color(col, blink + 0.2), 3.0)
		else:
			var life: float = (float(b.t) - float(b.warn)) / float(b.live)
			var bw: float = w * (1.0 - life * life) * (0.9 + 0.1 * sin(g.t * 60.0))
			if str(b.axis) == "col":
				c.draw_rect(Rect2(at - bw, 0, bw * 2.0, H), Color(col, 0.6))
				c.draw_rect(Rect2(at - bw * 0.5, 0, bw, H), Color(1.0, 0.9, 0.8, 0.9))
			else:
				c.draw_rect(Rect2(0, at - bw, W, bw * 2.0), Color(col, 0.6))
				c.draw_rect(Rect2(0, at - bw * 0.5, W, bw), Color(1.0, 0.9, 0.8, 0.9))
	for sp in spokes:
		var warm: bool = float(sp.t) < float(sp.warn)
		var fade: float = clampf(float(sp.life) - float(sp.t), 0.0, 1.0)
		for a in range(int(sp.arms)):
			var ang: float = float(sp.angle) + float(a) * TAU / float(sp.arms)
			var end: Vector2 = (sp.c as Vector2) + Vector2.from_angle(ang) * 1500.0
			if warm:
				c.draw_line(sp.c, end, Color(UI.VIOLET, 0.3 + 0.3 * absf(sin(g.t * 16.0))), 3.0)
			else:
				c.draw_line(sp.c, end, Color(UI.VIOLET, 0.6 * fade), 26.0)
				c.draw_line(sp.c, end, Color(1.0, 0.9, 1.0, 0.95 * fade), 8.0)
		UI.glow(c, sp.c, 60.0, Color(UI.VIOLET, 0.8))
	for wr in warnings:
		var blink: float = 0.4 + 0.6 * absf(sin(g.t * 14.0))
		if str(wr.kind) == "sides":
			c.draw_texture_rect(UI.edge_tex(), Rect2(0, H * 0.55, 90, H * 0.4), false, Color(UI.RED, blink * 0.7))
			c.draw_texture_rect(UI.edge_tex(), Rect2(W, H * 0.55, -90, H * 0.4), false, Color(UI.RED, blink * 0.7))
		else:
			var y: float = wr.y
			c.draw_rect(Rect2(0, y - 70.0, W, 140.0), Color(UI.RED, blink * 0.12))
			c.draw_line(Vector2(0, y - 70.0), Vector2(W, y - 70.0), Color(UI.RED, blink * 0.8), 2.0)
			c.draw_line(Vector2(0, y + 70.0), Vector2(W, y + 70.0), Color(UI.RED, blink * 0.8), 2.0)
