class_name Telegraph
extends RefCounted
## Attack telegraphs: what the player is shown before an enemy or boss attack lands.
##
## Accuracy rule: the code that FIRES an attack and the code that DRAWS its warning call the same functions here
## (`enemy_shots`, `fan_rays`, `ring_rays`, `curtain_xs`, ...). Anything random is rolled once, when the existing tell
## or charge begins, kept in the attack's plan, and reused when the attack fires. Nothing here changes a damage,
## speed, rate or count: it only describes them.
##
## Enemies need no separate clock: the warning is a function of the enemy's own `tell` timer, so it can never drift
## from the shot. Bosses keep a `plan` from the start of the charge; the few warnings that must outlive the charge
## (later curtain rows, queued spawns, a burst, a delayed rebound) live in `timed`, which has a hard cap.
##
## `collect()` builds this frame's DESCRIPTORS: plain dictionaries of exactly the geometry the player is shown (the
## rays with their real origins and angles, the real column or row positions, the real gap). TelegraphPaint turns
## descriptors into lines. Tests compare descriptors with what the attack really emitted.

const MAX_TIMED := 24
const MAX_ENEMY_SHOWN := 10
const MAX_SHOWN := 40
const TELL_FAST := 0.3
const TELL_SLOW := 0.5
const SLOW_SHOTS := ["lance", "fan", "elite", "broadside", "bomb"]
## Arrival markers sit this far below the top of the play area: clear of the HUD and the boss bar.
const MARKER_Y := 190.0
const ELITE_FOLLOW_DELAY := 0.45
const BURST_GAP := 0.26
const CURTAIN_GAP := 0.8
const CURTAIN_WARN := 0.55
const SHELL_GAP := 0.16
const COLLAPSE_DELAY := 2.0
## Pixels between the entries of each group form, mirrored from `_spawn_group`.
const STAGGER := {"rain": 0.42, "dive": 0.55, "scatter": 0.6, "pincer": 0.3, "swarm": 0.14, "line": 0.0}

## Boss summons (rocks, raiders, mines, the Admiral's launch, the Tyrant's cinders, the Regent's raise, the Hydra's brood)
## are queued in `game.pending`, which game.gd only advances in the PLAYING phase. In a boss fight they are queued and
## never arrive, so the arrival markers are hidden: a warning must not announce something that does not happen. This
## was found while building the warnings and left alone, because fixing it adds seven attacks to every boss fight. Set
## this to true when the queue is advanced during a boss fight; a test fails until it matches the game.
static var summons_arrive := false

var timed: Array = []
var shown: Array = []

# ---------- Shared attack geometry (used by the attacks themselves) ----------

static func tell_time(shot: String) -> float:
	return TELL_SLOW if shot in SLOW_SHOTS else TELL_FAST

## Where each shot of an enemy attack starts and which way it goes. `aim` is the angle to the ship, `phase` the
## turn of the elite ring chosen when its tell began.
static func enemy_shots(shot: String, pos: Vector2, aim: float, phase: float) -> Array:
	var out: Array = []
	match shot:
		"aimed":
			out.append({"at": pos + Vector2(0, 40), "ang": aim})
		"twin":
			out.append({"at": pos + Vector2(-26, 30), "ang": PI * 0.5})
			out.append({"at": pos + Vector2(26, 30), "ang": PI * 0.5})
		"fan":
			for i in range(5):
				out.append({"at": pos + Vector2(0, 80), "ang": aim + (float(i) - 2.0) * 0.2})
		"lance":
			# Five delayed shots share this one line.
			out.append({"at": pos + Vector2.from_angle(aim) * 60.0, "ang": aim})
		"bomb":
			for side in [-0.32, 0.0, 0.32]:
				out.append({"at": pos + Vector2(0, 50), "ang": PI * 0.5 + float(side)})
		"broadside":
			for i in range(5):
				out.append({"at": pos + Vector2((float(i) - 2.0) * 44.0, 30), "ang": PI * 0.5})
		"elite":
			for i in range(14):
				out.append({"at": pos + Vector2(0, 40), "ang": float(i) * TAU / 14.0 + phase})
		"elite_follow":
			for i in range(3):
				out.append({"at": pos + Vector2(0, 80), "ang": aim + (float(i) - 1.0) * 0.16})
	return out

static func spawn_points(pos: Vector2) -> Array:
	return [pos + Vector2(-60.0, 50.0), pos + Vector2(60.0, 50.0)]

## The boss fan: n shots spread 0.17 rad apart, centred straight down.
static func fan_rays(from: Vector2, n: int, step := 0.17, centre := PI * 0.5) -> Array:
	var out: Array = []
	for i in range(n):
		out.append({"at": from, "ang": centre + (float(i) - float(n - 1) * 0.5) * step})
	return out

## Three shots, 0.12 rad apart, around the angle to the ship.
static func aimed_rays(from: Vector2, aim: float) -> Array:
	var out: Array = []
	for i in range(3):
		out.append({"at": from, "ang": aim + (float(i) - 1.0) * 0.12})
	return out

## The boss ring: `count` evenly spaced shots, with two neighbours missing at `gap`.
static func ring_rays(from: Vector2, count: int, gap: int) -> Array:
	var out: Array = []
	for i in range(count):
		if i == gap or i == (gap + 1) % count:
			continue
		out.append({"at": from, "ang": float(i) * TAU / float(count)})
	return out

## Evenly spaced shots all the way round.
static func radial_rays(from: Vector2, count: int, phase := 0.0) -> Array:
	var out: Array = []
	for i in range(count):
		out.append({"at": from, "ang": float(i) * TAU / float(count) + phase})
	return out

## The x of every shot in a curtain row. The opening is whatever is missing within 118 px of `gap`.
static func curtain_xs(gap: float, width: float) -> Array:
	var out: Array = []
	var x := 30.0
	while x < width:
		if absf(x - gap) > 118.0:
			out.append(x)
		x += 58.0
	return out

## The two shots that bound a curtain opening: [left, right], or the screen edge when the opening touches it.
static func curtain_open(xs: Array, gap: float, width: float) -> Array:
	var left := 0.0
	var right := width
	for x in xs:
		if float(x) < gap:
			left = float(x)
		elif right == width:
			right = float(x)
	return [left, right]

static func group_count(g, cfg: Dictionary) -> int:
	var kind: String = str(cfg.kind)
	var scaled: bool = kind not in ["elite", "gunship", "frigate", "brood"]
	return maxi(1, int(round(float(cfg.count) * (g.count_mult if scaled else 1.0))))

# ---------- Timed warnings (the ones that outlive a charge) ----------

## `list` holds the keys the attack will report through `fired()`. The item is also removed when its time is up,
## when its owner enemy dies, and whenever the boss is cleared.
func add(kind: String, delay: float, dur: float, data: Dictionary, owner = null) -> Dictionary:
	if timed.size() >= MAX_TIMED:
		timed.remove_at(0)
	var it := {"kind": kind, "age": 0.0, "delay": delay, "dur": dur, "data": data, "owner": owner}
	timed.append(it)
	return it

## The attack has happened: take its key off the warning (and the warning with it once nothing is left).
func fired(kind: String, key) -> void:
	for i in range(timed.size() - 1, -1, -1):
		var it: Dictionary = timed[i]
		if str(it.kind) != kind:
			continue
		var list: Array = it.data.get("list", [])
		var at := list.find(key)
		if at >= 0:
			list.remove_at(at)
			if list.is_empty():
				timed.remove_at(i)
			return

func update(dt: float) -> void:
	for i in range(timed.size() - 1, -1, -1):
		var it: Dictionary = timed[i]
		it.age = float(it.age) + dt
		var o = it.owner
		if float(it.age) >= float(it.dur) or (o is Dictionary and bool(o.dead)):
			timed.remove_at(i)

func clear() -> void:
	timed.clear()
	shown.clear()

func clear_boss() -> void:
	for i in range(timed.size() - 1, -1, -1):
		if (timed[i] as Dictionary).owner == null:
			timed.remove_at(i)

# ---------- Descriptors ----------

func collect(g) -> void:
	shown.clear()
	var ph = g.previous_phase if g.phase in [g.Phase.PAUSED, g.Phase.RESUME] else g.phase
	if ph in [g.Phase.CLEAR, g.Phase.DEFEAT, g.Phase.UPGRADE, g.Phase.INTRO]:
		timed.clear()
		return
	if not g.player_alive or ph not in [g.Phase.PLAYING, g.Phase.WARNING, g.Phase.BOSS_INTRO, g.Phase.BOSS]:
		return
	var b = g.boss
	if b == null or b.dead or float(b.dying) > 0.0:
		clear_boss()
	_collect_enemies(g)
	if b != null and not b.dead and float(b.dying) <= 0.0:
		if float(b.charge) > 0.0 and not b.intent.is_empty():
			var k := clampf(1.0 - float(b.charge) / BossBase.CHARGE, 0.0, 1.0)
			var d: Dictionary = b.describe(b.intent, k)
			if not d.is_empty():
				shown.append(d)
		for d in b.ambient():
			if shown.size() < MAX_SHOWN:
				shown.append(d)
	_collect_timed(g)

func _collect_enemies(g) -> void:
	var count := 0
	for e in g.enemies:
		if e.dead or float(e.tell) <= 0.0 or float(e.frozen) > 0.0 or not g.enemy_can_fire(e):
			continue
		var d := enemy_desc(g, e)
		if d.is_empty():
			continue
		if count < MAX_ENEMY_SHOWN:
			shown.append(d)
			count += 1
			continue
		# Over the cap: the warnings closest to firing win.
		var weakest := 0
		for i in range(count):
			if float((shown[i] as Dictionary).k) < float((shown[weakest] as Dictionary).k):
				weakest = i
		if float(d.k) > float((shown[weakest] as Dictionary).k):
			shown[weakest] = d

func enemy_desc(g, e: Dictionary) -> Dictionary:
	var shot := str(e.shot)
	var tmax := maxf(0.01, float(e.get("tell_max", tell_time(shot))))
	var k := clampf(1.0 - float(e.tell) / tmax, 0.0, 1.0)
	var pos: Vector2 = e.pos
	var d := {"src": "enemy", "kind": shot, "style": shot, "hue": "warn", "k": k, "owner": e,
		"origin": pos + Vector2(0, float(e.r) * 0.7), "enemy_pos": pos}
	if shot == "spawn":
		var m: Array = []
		for p in spawn_points(pos):
			m.append({"pos": p, "shape": "sigil"})
		d.style = "markers"
		d.markers = m
		return d
	var rays := enemy_shots(shot, pos, g.enemy_aim(e), float(e.get("tphase", 0.0)))
	if rays.is_empty():
		return {}
	d.rays = rays
	d.len = clampf(pos.distance_to(g.player_pos) + 140.0, 260.0, 1500.0)
	if shot == "elite":
		d.style = "radial"
		d.hue = "danger"
		d.rl = 230.0
		d.centre = rays[0].at
	elif shot == "bomb":
		d.len = 620.0
	elif shot in ["twin", "broadside"]:
		d.len = clampf(float(g.H) - pos.y, 300.0, 900.0)
	elif shot == "fan":
		d.len = 560.0
	return d

func _collect_timed(g) -> void:
	var b = g.boss
	for it in timed:
		var owner = it.owner
		if float(it.age) < float(it.delay) or (owner is Dictionary and bool(owner.dead)):
			continue
		var data: Dictionary = it.data
		var span := maxf(0.05, float(it.dur) - float(it.delay))
		var k := clampf((float(it.age) - float(it.delay)) / span, 0.0, 1.0)
		var d := {}
		match str(it.kind):
			"curtain_row":
				if b != null:
					d = curtain_desc(b.pos.y + 30.0, float(data.gap), float(g.W), k, str(data.hue))
			"elite_follow":
				var e: Dictionary = it.owner
				var pos: Vector2 = e.pos
				d = {"src": "enemy", "kind": "elite_follow", "style": "aimed", "hue": "danger", "k": k, "origin": pos + Vector2(0, 80), "owner": e,
					"rays": enemy_shots("elite_follow", pos, g.enemy_aim(e), 0.0), "len": clampf(pos.distance_to(g.player_pos) + 140.0, 260.0, 1500.0)}
			"burst":
				if b != null:
					var from: Vector2 = b.muzzle()
					d = {"src": "boss", "kind": "burst", "style": "burst", "hue": "warn", "k": k, "origin": from,
						"rays": aimed_rays(from, (g.player_pos - from).angle()), "len": clampf(from.distance_to(g.player_pos) + 140.0, 260.0, 1500.0),
						"n": int(data.n), "left": (data.list as Array).size(), "track": true}
			"barrage":
				if b != null:
					d = {"src": "boss", "kind": "barrage", "style": "drops", "hue": "warn", "k": k, "origin": b.pos, "xs": (data.list as Array).duplicate(), "y0": b.pos.y + 90.0}
			"collapse":
				if b != null:
					d = {"src": "boss", "kind": "collapse", "style": "radial", "hue": "danger", "k": k, "origin": b.pos, "rays": radial_rays(b.pos, 28), "rl": 300.0, "centre": b.pos}
			"marker":
				d = {"src": "boss", "kind": "marker", "style": "markers", "hue": "warn", "k": k, "origin": data.pos, "markers": [{"pos": data.pos, "shape": data.shape}]}
		if not d.is_empty() and shown.size() < MAX_SHOWN:
			shown.append(d)

## One curtain row: the pips that will fall, and the opening between the two nearest.
static func curtain_desc(y: float, gap: float, width: float, k: float, hue: String) -> Dictionary:
	var xs := curtain_xs(gap, width)
	var edge := curtain_open(xs, gap, width)
	return {"src": "boss", "kind": "curtain", "style": "curtain", "hue": hue, "k": k, "origin": Vector2(gap, y), "y": y, "xs": xs, "gap": gap,
		"open_l": float(edge[0]), "open_r": float(edge[1]), "width": width}
