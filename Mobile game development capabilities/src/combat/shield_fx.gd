class_name ShieldFx
extends RefCounted
## What a shield looks like as it is hit, wears down, breaks and comes back. It only READS the shield value: it never
## changes it, so the shield calculations in game.gd are exactly what they were.
##
## The player's bubble is the existing shield sprite; this adds ripples where shots land, a worn-shield look, a collapse
## when it breaks and a recovery when it returns. The same ripples, break and wear ring are used for enemies that have a
## shield (the "shielded" elite modifier) through the static helpers at the bottom.
##
## Wear is shown by SHAPE as well as brightness, so it never depends on colour or on flashing:
##   above 60%   a smooth bubble        30 to 60%  a ring with gaps         under 30%  a ring with more gaps and
##   brief electrical arcs              under 12%  the ring pulses slowly as a warning
## Reduce Flash removes the flicker, Reduce Motion removes the arcs, spreading ripples and pulse; the gaps remain.

const FULL := 0.6
const WORN := 0.3
const CRITICAL := 0.12
const COLOR := Color(0.35, 0.85, 1.0)
const SEGMENTS := 14

var fx: Fx
## What a ripple follows: a dictionary with a "pos".
var anchor := {"pos": Vector2.ZERO}
var radius := 85.0
## Counts down while a broken shield collapses (seconds).
var collapse := 0.0
var _down := false
var _was := -1.0
var _arc_t := 1.0
var _regen_t := 0.0
var _warn_t := 0.0
var _t := 0.0

func _init(effects: Fx) -> void:
	fx = effects

func ratio(shield: float, max_shield: float) -> float:
	return clampf(shield / maxf(1.0, max_shield), 0.0, 1.0)

## 0 full, 1 worn, 2 low, 3 critical. What the shield looks like follows this.
static func tier_of(r: float) -> int:
	if r > FULL:
		return 0
	if r > WORN:
		return 1
	return 2 if r > CRITICAL else 3

## A hit the shield absorbed. `from` is where the shot was (Vector2.INF when unknown), `amount` and `max_shield` give its weight.
func on_hit(centre: Vector2, from: Vector2, amount: float, max_shield: float) -> float:
	anchor.pos = centre
	var power := clampf(amount / maxf(1.0, max_shield * 0.18), 0.5, 2.0)
	var dir_from := from if from != Vector2.INF else centre + Vector2(0, -radius)
	var dir := (dir_from - centre).normalized() if dir_from.distance_to(centre) > 1.0 else Vector2(0, -1)
	fx.ripple(anchor, radius, centre + dir * radius, power, COLOR)
	fx.impact(centre + dir * radius, "pulse", power, "shield")
	return power

## The shield just reached zero.
func on_break(centre: Vector2) -> void:
	anchor.pos = centre
	collapse = 0.35 if fx.calm() else 0.55
	_down = true
	fx.shield_break(centre, radius, COLOR)

## Called every frame with the real shield state. Detects recovery and drives the slow wear effects.
## Returns "up" once, on the frame a broken shield comes back, and "warn" now and then while nearly gone.
func update(dt: float, centre: Vector2, shield: float, max_shield: float, alive: bool, in_combat: bool) -> String:
	_t += dt
	anchor.pos = centre
	collapse = maxf(0.0, collapse - dt)
	var event := ""
	if not alive:
		_was = shield
		return event
	if _was < 0.0:
		_was = shield
	var r := ratio(shield, max_shield)
	if shield <= 0.0:
		_down = true
	elif _down and shield > 0.0:
		_down = false
		fx.shield_recover(centre, radius, COLOR)
		event = "up"
	# Regeneration: a few motes drawn in, now and then, while the value is climbing.
	if shield > _was + 0.001 and shield < max_shield and not fx.calm():
		_regen_t -= dt
		if _regen_t <= 0.0:
			_regen_t = 0.7
			var a := randf() * TAU
			var from := centre + Vector2.from_angle(a) * radius * 1.25
			fx.spark(from, (centre - from).normalized() * 110.0, 0.3, COLOR, 6.0)
	else:
		_regen_t = minf(_regen_t, 0.3)
	_was = shield
	if in_combat and shield > 0.0:
		var tier := tier_of(r)
		if tier >= 2 and not fx.calm():
			_arc_t -= dt
			if _arc_t <= 0.0:
				_arc_t = randf_range(0.5, 1.0) if tier == 3 else randf_range(0.9, 1.8)
				var a2 := randf() * TAU
				fx.bolt(centre + Vector2.from_angle(a2) * radius, centre + Vector2.from_angle(a2 + randf_range(0.35, 0.8)) * radius * 1.12, COLOR)
		if tier == 3:
			_warn_t -= dt
			if _warn_t <= 0.0:
				_warn_t = 3.0
				event = "warn"
	return event

## How much the glow of the bubble is dimmed by wear (1 = not at all). Steady under Reduce Flash.
func flicker(r: float) -> float:
	if fx.gentle():
		return 1.0
	var tier := tier_of(r)
	if tier == 0:
		return 1.0
	var s := maxf(0.0, sin(_t * 23.0) * sin(_t * 7.3))
	return 1.0 - s * (0.18 if tier == 1 else (0.32 if tier == 2 else 0.4))

## Extra scale and fade of the bubble while it collapses after breaking.
func collapse_scale() -> float:
	return 1.0 + (1.0 - collapse / 0.55) * 0.4 if collapse > 0.0 else 1.0

func collapse_alpha() -> float:
	return clampf(collapse / 0.55, 0.0, 1.0) * 0.7

## The wear ring. Gaps make the state readable without colour or flashing.
func paint(c: CanvasItem, centre: Vector2, shield: float, max_shield: float) -> void:
	if shield <= 0.0:
		return
	var r := ratio(shield, max_shield)
	var tier := tier_of(r)
	if tier == 0:
		return
	_paint_ring(c, centre, radius * 1.04, r, tier, _t)

## A ring of SEGMENTS arcs, fewer of them as the shield wears. Shared by the player's and enemies' shields.
static func _paint_ring(c: CanvasItem, centre: Vector2, rad: float, r: float, tier: int, t: float) -> void:
	var shown := clampi(int(ceil(r / FULL * float(SEGMENTS))), 2, SEGMENTS)
	var alpha := 0.5 if tier < 3 else 0.35 + 0.2 * (0.5 + 0.5 * sin(t * 4.0))
	var step := TAU / float(SEGMENTS)
	for i in range(SEGMENTS):
		# Segments drop out in a fixed scattered order, so the same pieces are missing from one frame to the next.
		var order := (i * 5) % SEGMENTS
		if order >= shown:
			continue
		c.draw_arc(centre, rad, float(i) * step + 0.03, float(i + 1) * step - 0.03, 6, Color(COLOR, alpha), 3.0, true)

## A shield on an enemy: the bubble ring, worn down the same way. `eshield` and `emax` are the enemy's own values.
static func paint_enemy(c: CanvasItem, e: Dictionary, t: float) -> void:
	var emax := float(e.get("eshield_max", 0.0))
	var cur := float(e.eshield)
	if cur <= 0.0 or emax <= 0.0:
		return
	var r := clampf(cur / emax, 0.0, 1.0)
	var rad := float(e.r) * 1.3
	var tier := tier_of(r)
	if tier == 0:
		c.draw_arc(e.pos, rad, 0.0, TAU, 36, Color(COLOR, 0.28), 2.5, true)
	else:
		_paint_ring(c, e.pos, rad, r, tier, t)
