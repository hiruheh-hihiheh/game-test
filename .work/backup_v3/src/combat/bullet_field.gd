class_name BulletField
extends RefCounted
## Enemy shots stored as flat arrays instead of objects.
## Nothing is allocated per bullet, so firing hundreds of them causes no garbage or stutter.

const MAX := 640

# orb: aimed shots. dart: straight shots. heavy: big and slow. shard: ice. spore: alien.
const KINDS := [
	{"tex": preload("res://assets/starfall/projectiles/projectile_enemy_magenta.png"), "size": 68.0, "r": 9.0, "rot": -PI * 0.5, "halo": Color(1.0, 0.27, 0.66)},
	{"tex": preload("res://assets/starfall/projectiles/projectile_enemy_orange.png"), "size": 68.0, "r": 9.0, "rot": PI * 0.5, "halo": Color(1.0, 0.58, 0.20)},
	{"tex": preload("res://assets/starfall/effects/effect_explosion_small.png"), "size": 84.0, "r": 22.0, "rot": 0.0, "halo": Color(1.0, 0.3, 0.2)},
	{"tex": preload("res://assets/starfall/gen/boss_regent_shard.png"), "size": 62.0, "r": 10.0, "rot": PI * 0.5, "halo": Color(0.55, 0.95, 1.0)},
	{"tex": preload("res://assets/starfall/gen/swarmlet.png"), "size": 42.0, "r": 12.0, "rot": 0.0, "halo": Color(0.9, 0.3, 0.9)},
]
const ORB := 0
const DART := 1
const HEAVY := 2
const SHARD := 3
const SPORE := 4

var count := 0
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var kind := PackedByteArray()
var dmg := PackedFloat32Array()
var grazed := PackedByteArray()
var wells: Array = []
var frost: Array = []
var blockers: Array = []
var time_factor := 1.0

func _init() -> void:
	pos.resize(MAX)
	vel.resize(MAX)
	kind.resize(MAX)
	dmg.resize(MAX)
	grazed.resize(MAX)

func add(at: Vector2, velocity: Vector2, k: int, damage: float) -> void:
	if count >= MAX:
		return
	pos[count] = at
	vel[count] = velocity
	kind[count] = k
	dmg[count] = damage
	grazed[count] = 0
	count += 1

func remove(i: int) -> void:
	count -= 1
	if i < count:
		pos[i] = pos[count]
		vel[i] = vel[count]
		kind[i] = kind[count]
		dmg[i] = dmg[count]
		grazed[i] = grazed[count]

func clear() -> void:
	count = 0

## Steps every shot. Returns hits through the callables so the game keeps the rules.
func update(dt: float, w: float, h: float, player: Vector2, hit_radius: float, graze_radius: float, on_hit: Callable, on_graze: Callable, on_block: Callable, alive: bool) -> void:
	var has_wells := not wells.is_empty()
	var has_frost := not frost.is_empty()
	var has_blockers := not blockers.is_empty()
	var i := count - 1
	while i >= 0:
		var p := pos[i]
		var v := vel[i]
		if has_wells:
			for well in wells:
				var to: Vector2 = (well.pos as Vector2) - p
				var d2 := to.length_squared() + 900.0
				v += to.normalized() * float(well.pull) * 60000.0 / d2 * dt
			vel[i] = v
		var step := dt
		if has_frost:
			for zone in frost:
				if p.distance_squared_to(zone.pos) < float(zone.r) * float(zone.r):
					step *= 0.45
					break
		p += v * step
		pos[i] = p
		if p.y > h + 60.0 or p.y < -80.0 or p.x < -60.0 or p.x > w + 60.0:
			remove(i)
			i -= 1
			continue
		if has_blockers:
			var blocked := false
			for b in blockers:
				var r: float = float(b.r) + 6.0
				if p.distance_squared_to(b.pos) < r * r:
					on_block.call(b, dmg[i], p)
					remove(i)
					blocked = true
					break
			if blocked:
				i -= 1
				continue
		if alive:
			var d := p.distance_to(player)
			var reach: float = float(KINDS[kind[i]].r) + hit_radius
			if d < reach:
				var damage := dmg[i]
				remove(i)
				on_hit.call(p, damage)
				# A hit may clear shots around the player, so resync with the list.
				i = mini(i, count)
				i -= 1
				continue
			if d < reach + graze_radius and grazed[i] == 0:
				grazed[i] = 1
				on_graze.call(p)
		i -= 1

## Removes every shot inside a circle and returns how many were removed.
func clear_circle(center: Vector2, radius: float, on_each: Callable = Callable()) -> int:
	var removed := 0
	var r2 := radius * radius
	var i := count - 1
	while i >= 0:
		if i < count and pos[i].distance_squared_to(center) < r2:
			if on_each.is_valid():
				on_each.call(pos[i])
			remove(i)
			removed += 1
		i -= 1
	return removed
