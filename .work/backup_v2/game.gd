extends Node2D
## One level (or an endless run): flight, combat, bosses, modules and results.

const ART := {
	"rock_l": preload("res://assets/starfall/environment/asteroid_large.png"),
	"rock_m": preload("res://assets/starfall/environment/asteroid_medium.png"),
	"rock_s": preload("res://assets/starfall/environment/asteroid_small.png"),
	"fighter": preload("res://assets/starfall/ships/enemy_fighter_01.png"),
	"raider": preload("res://assets/starfall/ships/player_interceptor_02.png"),
	"boss": preload("res://assets/starfall/ships/boss_ship_01.png"),
	"mine": preload("res://assets/starfall/effects/effect_shield_orb.png"),
}
const SHIP_ART := {
	"nova": preload("res://assets/starfall/ships/player_nova_01.png"),
	"interceptor": preload("res://assets/starfall/ships/player_interceptor_02.png"),
}
const DRONE_ART := preload("res://assets/starfall/ships/player_interceptor_02.png")
const SALVAGE_ART := preload("res://assets/starfall/environment/salvage_crystal_blue.png")
const SHOT_CYAN := preload("res://assets/starfall/projectiles/projectile_player_cyan.png")
const SHOT_MAGENTA := preload("res://assets/starfall/projectiles/projectile_enemy_magenta.png")
const SHOT_ORANGE := preload("res://assets/starfall/projectiles/projectile_enemy_orange.png")
const LASER_ART := preload("res://assets/starfall/projectiles/projectile_laser_magenta.png")
const BOOM_S := preload("res://assets/starfall/effects/effect_explosion_small.png")
const BOOM_L := preload("res://assets/starfall/effects/effect_explosion_large.png")
const SHIELD_ART := preload("res://assets/starfall/effects/effect_shield_orb.png")
const ICON_PAUSE := preload("res://assets/starfall/ui_icons/icon_pause.png")
const ICON_PLAY := preload("res://assets/starfall/ui_icons/icon_play.png")
const ICON_HOME := preload("res://assets/starfall/ui_icons/icon_home.png")
const ICON_MODULES := preload("res://assets/starfall/ui_icons/icon_modules.png")
const ICON_BOSS := preload("res://assets/starfall/ui_icons/icon_boss.png")
const ICON_WAVE := preload("res://assets/starfall/ui_icons/icon_wave_status.png")
const ICON_HULL := preload("res://assets/starfall/ui_icons/upgrade_hull_plating.png")
const ICON_BURN := preload("res://assets/starfall/ui_icons/upgrade_afterburner.png")
const ICON_BEAM := preload("res://assets/starfall/ui_icons/upgrade_tri_beam.png")
const HUE_SHADER := preload("res://src/hue.gdshader")

const CARDS := [
	{"id": "spread", "name": "TRI-BEAM", "desc": "Fire one more beam", "color": UI.CYAN, "icon": ICON_BEAM, "max": 4},
	{"id": "pierce", "name": "PHASE ROUNDS", "desc": "Shots pass through one more target", "color": UI.VIOLET, "icon": SHOT_CYAN, "max": 3},
	{"id": "drone", "name": "ORBITAL DRONE", "desc": "A wingman fires beside you", "color": UI.MINT, "icon": DRONE_ART, "max": 3},
	{"id": "magnet", "name": "SALVAGE MAGNET", "desc": "Pull crystals from farther away", "color": UI.ORANGE, "icon": SALVAGE_ART, "max": 3},
	{"id": "plating", "name": "HULL PLATING", "desc": "+25 shield and refill it now", "color": UI.CYAN, "icon": ICON_HULL, "max": 4},
	{"id": "afterburner", "name": "AFTERBURNER", "desc": "Your shots fly 25% faster and hit harder", "color": UI.MAGENTA, "icon": ICON_BURN, "max": 3},
	{"id": "critical", "name": "CRIT MATRIX", "desc": "+10% chance of double damage", "color": UI.GOLD, "icon": ICON_BOSS, "max": 4},
	{"id": "overclock", "name": "OVERCLOCK", "desc": "Fire 15% faster", "color": UI.VIOLET, "icon": ICON_WAVE, "max": 4},
	{"id": "repair", "name": "FIELD REPAIR", "desc": "Restore one hull", "color": UI.MINT, "icon": SHIELD_ART, "max": 9},
]

enum Phase { INTRO, PLAYING, WARNING, BOSS, UPGRADE, CLEAR, DEFEAT, PAUSED }

var phase: Phase = Phase.INTRO
var previous_phase: Phase = Phase.PLAYING
var W := 720.0
var H := 1280.0
var inset := Vector2.ZERO
var top := 16.0
var t := 0.0
var phase_t := 0.0

# Level state
var endless := false
var level_num := 1
var level: Dictionary = {}
var scale_cfg: Dictionary = {}
var wave_index := 0
var group_queue: Array = []
var group_timer := 0.0
var pending: Array = []
var clear_wait := -1.0
var next_id := 1
var endless_wave := 1

# Player
var player_pos := Vector2(360, 1500)
var player_target := Vector2(360, 1040)
var player_alive := true
var hull := 3
var max_hull := 3
var shield := 60.0
var max_shield := 60.0
var energy := 0.0
var energy_gain := 1.0
var shot_damage := 1.0
var fire_interval := 0.26
var shot_speed := 900.0
var magnet := 130.0
var crit := 0.05
var spread := 0
var pierce := 0
var drones := 0
var card_counts := {}
var fire_timer := 0.3
var drone_timer := 0.0
var invuln := 0.0
var shield_idle := 0.0
var shield_flash := 0.0
var hull_lost := 0
var engine_accum := 0.0
var bank_angle := 0.0

# World
var bullets: Array = []
var enemy_bullets: Array = []
var enemies: Array = []
var pickups: Array = []
var lasers: Array = []
var timers: Array = []
var boss = null
var boss_sprite: Sprite2D
var sparks: Array = []
var booms: Array = []
var rings: Array = []
var floaters: Array = []
var stars_bg: Array = []
var bg_scroll := 0.0
var bg_tex: Texture2D
var warp := 0.0

# Feel
var hitstop := 0.0
var time_scale := 1.0
var shake := 0.0
var flash := 0.0
var flash_color := Color.WHITE

# Score
var score := 0
var shown_score := 0.0
var run_salvage := 0
var banked := false
var combo := 0
var combo_timer := 0.0
var best_combo := 0
var kills := 0

# Messages
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var banner_color := UI.CYAN

# Overlays
var card_options: Array = []
var card_picked := -1
var result_win := false
var result_stars := 0
var result_reward := 0
var stars_shown := 0
var input_lock := 0.0
var new_best := false

# Touch
var drag_finger := -1
var tut_active := false
var tut_moved := 0.0
var burst_hint := false

var world: Node2D
var pickup_layer: DrawLayer
var enemy_root: Node2D
var player_shots_layer: DrawLayer
var enemy_shots_layer: DrawLayer
var fx_add: DrawLayer
var fx_top: DrawLayer
var bg_layer: DrawLayer
var player_sprite: Sprite2D
var shield_sprite: Sprite2D
var drone_sprites: Array = []
var ui: UILayer
var materials := {}
var add_mat: CanvasItemMaterial

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	_measure()
	endless = Save.play_endless
	level_num = Save.play_level
	if endless:
		endless_wave = 1
		level = Levels.build_endless(endless_wave)
	else:
		level = Levels.build(level_num)
	scale_cfg = level.scale
	_apply_stats()
	_build_scene()
	shield = max_shield
	hull = max_hull
	player_target = Vector2(W * 0.5, H - 300.0)
	player_pos = Vector2(W * 0.5, H + 140.0)
	warp = 1.0
	var sector_info: Dictionary = Levels.SECTORS[int(level.sector) - 1]
	Audio.music(str(sector_info.music))
	Audio.play("whoosh", 0.0, 0.8)
	if endless:
		_show_banner("ENDLESS", "How far can you go?", 1.9, UI.GOLD)
	else:
		_show_banner("LEVEL %d" % level_num, str(sector_info.name), 1.9, sector_info.color)
	tut_active = not Save.tutorial_done and not endless
	phase = Phase.INTRO
	phase_t = 0.0

func _measure() -> void:
	var s := get_viewport_rect().size
	W = s.x
	H = s.y
	inset = UI.safe_insets(s)
	top = inset.x + 16.0

func _apply_stats() -> void:
	var ship_cfg: Dictionary = Levels.SHIPS.get(Save.ship, Levels.SHIPS.nova)
	shot_damage = 1.0 + 0.15 * float(Save.upgrade_level("cannon"))
	fire_interval = 0.26 * pow(0.93, float(Save.upgrade_level("rapid"))) * float(ship_cfg.fire)
	max_hull = 3 + Save.upgrade_level("hull") + int(ship_cfg.hull)
	max_shield = (60.0 + 20.0 * float(Save.upgrade_level("shield"))) * float(ship_cfg.shield)
	magnet = 130.0 + 45.0 * float(Save.upgrade_level("magnet"))
	energy_gain = 1.0 + 0.2 * float(Save.upgrade_level("reactor"))

func _build_scene() -> void:
	add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	bg_tex = load("res://assets/backgrounds/sector_%d.png" % int(level.sector))
	for i in range(100):
		var depth := randf_range(0.2, 1.0)
		stars_bg.append({"pos": Vector2(randf_range(0.0, W), randf_range(0.0, H)), "depth": depth, "twinkle": randf_range(0.0, TAU)})
	bg_layer = _layer(self, _paint_background)
	world = Node2D.new()
	add_child(world)
	pickup_layer = _layer(world, _paint_pickups)
	enemy_root = Node2D.new()
	world.add_child(enemy_root)
	player_shots_layer = _layer(world, _paint_player_shots, true)
	player_sprite = Sprite2D.new()
	player_sprite.texture = SHIP_ART.get(Save.ship, SHIP_ART.nova)
	player_sprite.scale = Vector2.ONE * (118.0 / 512.0)
	world.add_child(player_sprite)
	for i in range(3):
		var d := Sprite2D.new()
		d.texture = DRONE_ART
		d.scale = Vector2.ONE * (58.0 / 512.0)
		d.visible = false
		world.add_child(d)
		drone_sprites.append(d)
	shield_sprite = Sprite2D.new()
	shield_sprite.texture = SHIELD_ART
	shield_sprite.scale = Vector2.ONE * (170.0 / 512.0)
	shield_sprite.material = add_mat
	shield_sprite.modulate.a = 0.0
	world.add_child(shield_sprite)
	enemy_shots_layer = _layer(world, _paint_enemy_shots)
	fx_add = _layer(world, _paint_fx_add, true)
	fx_top = _layer(world, _paint_fx_top)
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	ui = UILayer.new()
	ui.painter = _paint_ui
	ui.pressed.connect(_on_ui)
	canvas.add_child(ui)

func _layer(parent: Node, painter: Callable, additive := false) -> DrawLayer:
	var layer := DrawLayer.new()
	layer.painter = painter
	if additive:
		layer.material = add_mat
	parent.add_child(layer)
	return layer

func _hue_mat(hue: float, white: bool) -> ShaderMaterial:
	var key := "%.2f|%s" % [hue, str(white)]
	if materials.has(key):
		return materials[key]
	var m := ShaderMaterial.new()
	m.shader = HUE_SHADER
	m.set_shader_parameter("hue", hue)
	m.set_shader_parameter("flash", 1.0 if white else 0.0)
	materials[key] = m
	return m

# ---------- Main loop ----------

func _process(delta: float) -> void:
	var real_dt := minf(delta, 0.05)
	t += real_dt
	_measure()
	_update_background(real_dt)
	input_lock = maxf(0.0, input_lock - real_dt)
	if phase != Phase.PAUSED:
		shown_score = move_toward(shown_score, float(score), maxf(120.0, absf(float(score) - shown_score) * 8.0) * real_dt)
		_tick(real_dt)
	_update_shake(real_dt)
	_redraw()

func _tick(real_dt: float) -> void:
	phase_t += real_dt
	banner_t = maxf(0.0, banner_t - real_dt)
	flash = maxf(0.0, flash - real_dt * 3.2)
	time_scale = move_toward(time_scale, 1.0, real_dt * 1.6)
	var dt := real_dt * time_scale
	if hitstop > 0.0:
		hitstop -= real_dt
		dt = 0.0
	_update_fx(real_dt)
	if combo_timer > 0.0:
		combo_timer -= dt
		if combo_timer <= 0.0:
			combo = 0
	match phase:
		Phase.INTRO:
			_update_world(dt)
			warp = maxf(0.0, warp - real_dt * 0.7)
			if phase_t > 1.7:
				_start_wave(0)
		Phase.PLAYING:
			_update_world(dt)
			if player_alive:
				_update_spawning(dt)
		Phase.WARNING:
			_update_world(dt)
			if phase_t > 2.3:
				_spawn_boss()
		Phase.BOSS:
			_update_world(dt)
			_update_boss(dt)
		Phase.UPGRADE:
			_update_fx_only_player(real_dt)
			if card_picked >= 0 and phase_t > 0.0 and input_lock <= 0.0:
				_install_card()
		Phase.CLEAR:
			_update_world(dt)
			player_target = player_pos
			if phase_t > 0.5:
				player_pos.y -= (phase_t - 0.5) * 1400.0 * real_dt
			_update_result_stars()
		Phase.DEFEAT:
			_update_world(dt)
	_sync_sprites(real_dt)

func _redraw() -> void:
	bg_layer.queue_redraw()
	pickup_layer.queue_redraw()
	player_shots_layer.queue_redraw()
	enemy_shots_layer.queue_redraw()
	fx_add.queue_redraw()
	fx_top.queue_redraw()

func _update_background(dt: float) -> void:
	bg_scroll += dt * (16.0 + warp * 900.0)
	for s in stars_bg:
		var depth: float = s.depth
		s.pos.y += dt * (24.0 + 170.0 * depth * depth + warp * 1700.0 * depth)
		if s.pos.y > H + 10.0:
			s.pos = Vector2(randf_range(0.0, W), -10.0)

func _update_shake(dt: float) -> void:
	shake = maxf(0.0, shake - dt * 44.0)
	if shake > 0.0 and Save.screen_shake:
		world.position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		world.position = Vector2.ZERO

func _kick(amount: float) -> void:
	shake = minf(20.0, shake + amount)

func _sync_sprites(dt: float) -> void:
	var blink := invuln > 0.0 and hull_lost > 0 and int(invuln * 16.0) % 2 == 0
	player_sprite.visible = player_alive
	player_sprite.position = player_pos
	player_sprite.modulate.a = 0.4 if blink else 1.0
	var dx := player_target.x - player_pos.x
	bank_angle = lerpf(bank_angle, clampf(dx * 0.0035, -0.3, 0.3), 1.0 - exp(-dt * 12.0))
	player_sprite.rotation = bank_angle
	player_sprite.scale.x = (118.0 / 512.0) * (1.0 - absf(bank_angle) * 0.45)
	shield_flash = maxf(0.0, shield_flash - dt * 3.0)
	shield_sprite.position = player_pos
	var ready_glow := 0.06 + sin(t * 3.0) * 0.015 if shield > 0.0 else 0.0
	shield_sprite.modulate.a = 0.0 if not player_alive else clampf(ready_glow + shield_flash * 0.75, 0.0, 1.0)
	shield_sprite.rotation += dt * 0.5
	for i in range(drone_sprites.size()):
		var d: Sprite2D = drone_sprites[i]
		d.visible = i < drones and player_alive
		if d.visible:
			d.position = _drone_pos(i)

func _drone_pos(i: int) -> Vector2:
	var side := -1.0 if i % 2 == 0 else 1.0
	var row := float(i / 2)
	return player_pos + Vector2(side * (84.0 + row * 34.0), 26.0 + row * 34.0 + sin(t * 3.0 + float(i)) * 6.0)

func _update_world(dt: float) -> void:
	if dt <= 0.0:
		return
	_update_player(dt)
	_update_bullets(dt)
	_update_enemy_bullets(dt)
	_update_enemies(dt)
	_update_pickups(dt)
	_update_lasers(dt)
	_update_timers(dt)

func _update_fx_only_player(dt: float) -> void:
	_emit_engine(dt)

func _update_timers(dt: float) -> void:
	for i in range(timers.size() - 1, -1, -1):
		var entry: Dictionary = timers[i]
		entry.t -= dt
		if float(entry.t) <= 0.0:
			timers.remove_at(i)
			var fn: Callable = entry.fn
			fn.call()

func _after(seconds: float, fn: Callable) -> void:
	timers.append({"t": seconds, "fn": fn})

# ---------- Player ----------

func _update_player(dt: float) -> void:
	if not player_alive:
		return
	if phase in [Phase.PLAYING, Phase.BOSS, Phase.WARNING]:
		var axis := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			axis.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			axis.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			axis.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			axis.y += 1.0
		if axis != Vector2.ZERO:
			player_target += axis.normalized() * 620.0 * dt
			tut_moved += 620.0 * dt
		_clamp_target()
		player_pos = player_pos.lerp(player_target, 1.0 - exp(-dt * 26.0))
		fire_timer -= dt
		if fire_timer <= 0.0:
			_fire()
		if drones > 0:
			drone_timer -= dt
			if drone_timer <= 0.0:
				drone_timer = 0.42
				for i in range(drones):
					_add_shot(_drone_pos(i) + Vector2(0, -24), -PI * 0.5, shot_damage * 0.7, UI.MINT, 62.0)
		energy = minf(100.0, energy + dt * 0.8 * energy_gain)
	elif phase == Phase.INTRO:
		player_pos = player_pos.lerp(player_target, 1.0 - exp(-dt * 3.6))
	shield_idle += dt
	invuln = maxf(0.0, invuln - dt)
	if shield_idle > 3.5 and shield < max_shield:
		shield = minf(max_shield, shield + dt * 12.0)
	_emit_engine(dt)

func _clamp_target() -> void:
	player_target.x = clampf(player_target.x, 44.0, W - 44.0)
	# The floor sits above the Nova button so the ship can never hide behind it.
	player_target.y = clampf(player_target.y, H * 0.42, H - 200.0 - inset.y)

func _emit_engine(dt: float) -> void:
	if not player_alive:
		return
	engine_accum += dt
	while engine_accum > 0.022:
		engine_accum -= 0.022
		var side := -1.0 if randf() < 0.5 else 1.0
		var at := player_pos + Vector2(side * randf_range(0.0, 14.0), 50.0)
		_spark(at, Vector2(randf_range(-22.0, 22.0), randf_range(170.0, 300.0)), randf_range(0.14, 0.3), UI.ORANGE if randf() < 0.6 else Color(1.0, 0.9, 0.5), randf_range(9.0, 16.0))

func _fire() -> void:
	fire_timer = fire_interval
	var lanes := 1 + spread
	for i in range(lanes):
		var lane := float(i) - float(lanes - 1) * 0.5
		var at := player_pos + Vector2(lane * 20.0, -46.0 + absf(lane) * 12.0)
		_add_shot(at, -PI * 0.5 + lane * 0.085, shot_damage, UI.CYAN, 82.0)
	Audio.play("shoot", -9.0, 1.0, 0.06)
	_spark(player_pos + Vector2(0, -50), Vector2(0, -30), 0.1, UI.CYAN, 30.0)

func _add_shot(at: Vector2, angle: float, damage: float, color: Color, size: float) -> void:
	bullets.append({"pos": at, "vel": Vector2.from_angle(angle) * shot_speed, "dmg": damage, "pierce": pierce, "hits": [], "color": color, "size": size, "angle": angle})

func _update_bullets(dt: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		b.pos += b.vel * dt
		var p: Vector2 = b.pos
		if p.y < -60.0 or p.x < -60.0 or p.x > W + 60.0 or _shot_hits(b):
			bullets.remove_at(i)

func _shot_hits(b: Dictionary) -> bool:
	var p: Vector2 = b.pos
	var hits: Array = b.hits
	if boss != null and float(boss.dying) <= 0.0 and not boss.entering and not (0 in hits):
		var offset: Vector2 = p - boss.pos
		var ex: float = offset.x / float(boss.rx)
		var ey: float = offset.y / float(boss.ry)
		if ex * ex + ey * ey < 1.0:
			hits.append(0)
			var damage := _roll_damage(float(b.dmg), p)
			_damage_boss(damage, p)
			b.pierce = int(b.pierce) - 1
			if int(b.pierce) < 0:
				return true
	for e in enemies:
		if e.dead or e.id in hits or float(e.pos.y) < 0.0:
			continue
		var r: float = float(e.r) + 8.0
		if p.distance_squared_to(e.pos) < r * r:
			hits.append(e.id)
			_damage_enemy(e, _roll_damage(float(b.dmg), p), p)
			b.pierce = int(b.pierce) - 1
			if int(b.pierce) < 0:
				return true
	return false

func _roll_damage(base: float, at: Vector2) -> float:
	if randf() < crit:
		_float_text("CRIT", at + Vector2(0, -24), 24, UI.GOLD)
		Audio.play("crit", -8.0, 1.0, 0.05)
		return base * 2.0
	return base

func _hurt_player(amount: float) -> void:
	if invuln > 0.0 or not player_alive or phase not in [Phase.PLAYING, Phase.BOSS, Phase.WARNING]:
		return
	shield_idle = 0.0
	if shield > 0.0:
		shield = maxf(0.0, shield - amount)
		invuln = 0.4
		shield_flash = 1.0
		_kick(6.0)
		Audio.play("shield_hit", -3.0, 1.0, 0.06)
		Save.vibrate(25)
		_ring(player_pos, 0.3, 40.0, 110.0, UI.CYAN, 5.0)
		return
	hull -= 1
	hull_lost += 1
	combo = 0
	combo_timer = 0.0
	invuln = 1.5
	_kick(15.0)
	flash = 0.55
	flash_color = UI.RED
	hitstop = 0.06
	Audio.play("hull_hit")
	Save.vibrate(70)
	_sparks(player_pos, 26, UI.ORANGE, 300.0, 0.5, 15.0)
	_boom(player_pos, 150.0, BOOM_S, 0.4)
	_ring(player_pos, 0.35, 30.0, 190.0, UI.RED, 7.0)
	_clear_bullets_near(player_pos, 260.0)
	if hull <= 0:
		_player_destroyed()

func _clear_bullets_near(at: Vector2, radius: float) -> void:
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var b: Dictionary = enemy_bullets[i]
		if at.distance_to(b.pos) < radius:
			_sparks(b.pos, 2, UI.CYAN, 90.0, 0.25, 12.0)
			enemy_bullets.remove_at(i)

func _player_destroyed() -> void:
	player_alive = false
	time_scale = 0.3
	_kick(20.0)
	Audio.play("explode_l")
	_boom(player_pos, 340.0, BOOM_L, 0.9)
	_sparks(player_pos, 60, UI.ORANGE, 420.0, 0.9, 20.0)
	_ring(player_pos, 0.6, 40.0, 420.0, UI.ORANGE, 8.0)
	Audio.stop_music(1.0)
	_after(1.0, _show_defeat)

func _nova_burst() -> void:
	if energy < 100.0 or not player_alive or phase not in [Phase.PLAYING, Phase.BOSS]:
		return
	energy = 0.0
	burst_hint = false
	Audio.play("burst")
	Save.vibrate(90)
	_kick(18.0)
	flash = 0.6
	flash_color = UI.CYAN
	hitstop = 0.07
	_ring(player_pos, 0.7, 60.0, H * 1.1, UI.CYAN, 16.0)
	_ring(player_pos, 0.9, 30.0, H * 0.85, Color.WHITE, 6.0)
	for b in enemy_bullets:
		_sparks(b.pos, 2, UI.CYAN, 90.0, 0.3, 12.0)
	var cleared := enemy_bullets.size()
	enemy_bullets.clear()
	if cleared > 0:
		_float_text("+%d" % (cleared * 10), player_pos + Vector2(0, -90), 34, UI.CYAN)
		score += cleared * 10
	var damage := 9.0 * shot_damage
	for e in enemies:
		if not e.dead and float(e.pos.y) > 0.0:
			_damage_enemy(e, damage, e.pos)
	if boss != null and not boss.entering:
		_damage_boss(float(boss.max) * 0.08 + damage, boss.pos)

# ---------- Waves ----------

func _start_wave(index: int) -> void:
	wave_index = index
	group_queue = (level.waves[index] as Array).duplicate()
	group_timer = 0.7
	clear_wait = -1.0
	phase = Phase.PLAYING
	phase_t = 0.0
	Audio.play("wave_start", -5.0)
	var total: int = (level.waves as Array).size()
	if endless:
		_show_banner("WAVE %d" % endless_wave, "", 1.2, UI.GOLD)
	elif total > 1 or level.boss:
		_show_banner("WAVE %d/%d" % [index + 1, total], "", 1.2, UI.WHITE)

func _update_spawning(dt: float) -> void:
	if not group_queue.is_empty():
		group_timer -= dt
		if group_timer <= 0.0:
			var g: Dictionary = group_queue.pop_front()
			group_timer = float(g.delay)
			_spawn_group(g)
	for i in range(pending.size() - 1, -1, -1):
		var entry: Dictionary = pending[i]
		entry.t -= dt
		if float(entry.t) <= 0.0:
			pending.remove_at(i)
			_spawn_enemy(entry)
	if group_queue.is_empty() and pending.is_empty() and enemies.is_empty():
		if clear_wait < 0.0:
			clear_wait = 0.9
			_attract_all()
		clear_wait -= dt
		if clear_wait <= 0.0:
			_on_wave_cleared()

func _queue_spawn(delay: float, kind: String, pos: Vector2, move: String, vel: Vector2, extra: Dictionary = {}) -> void:
	var entry := {"t": delay, "kind": kind, "pos": pos, "move": move, "vel": vel}
	entry.merge(extra)
	pending.append(entry)

func _spawn_group(g: Dictionary) -> void:
	var kind: String = g.kind
	var count: int = g.count
	var form: String = g.form
	var speed: float = scale_cfg.speed
	var mid := W * 0.5
	match form:
		"rain":
			for i in range(count):
				var roll := randf()
				var rock := "rock_l" if roll < 0.24 else ("rock_m" if roll < 0.62 else "rock_s")
				if int(level.level) <= 2 and not endless:
					rock = "rock_m" if roll < 0.4 else "rock_s"
				_queue_spawn(float(i) * 0.42, rock, Vector2(randf_range(50.0, W - 50.0), -70.0), "straight", Vector2(randf_range(-45.0, 45.0), randf_range(120.0, 200.0) * speed))
		"line":
			for i in range(count):
				_queue_spawn(0.0, kind, Vector2(W * (float(i) + 1.0) / (float(count) + 1.0), -70.0), "straight", Vector2(0, 130.0 * speed))
		"vee":
			for i in range(count):
				var off := float(i) - float(count - 1) * 0.5
				_queue_spawn(absf(off) * 0.26, kind, Vector2(mid + off * minf(110.0, (W - 120.0) / float(count)), -70.0), "straight", Vector2(0, 135.0 * speed))
		"column":
			var x := randf_range(150.0, W - 150.0)
			for i in range(count):
				_queue_spawn(float(i) * 0.46, kind, Vector2(x, -70.0), "sine", Vector2(0, 150.0 * speed), {"amp": 90.0, "freq": 1.5})
		"sine":
			var base := randf_range(240.0, W - 240.0)
			var flip := 1.0 if randf() < 0.5 else -1.0
			for i in range(count):
				_queue_spawn(float(i) * 0.4, kind, Vector2(base, -70.0), "sine", Vector2(0, 165.0 * speed), {"amp": flip * minf(200.0, W * 0.3), "freq": 1.7})
		"pincer":
			for i in range(count):
				var left := i % 2 == 0
				var start := Vector2(-60.0 if left else W + 60.0, randf_range(190.0, 340.0))
				var heading := -0.15 if left else PI + 0.15
				_queue_spawn(float(i) * 0.3, kind, start, "arc", Vector2.from_angle(heading) * 330.0 * speed, {"turn": 1.5 if left else -1.5})
		"dive":
			for i in range(count):
				_queue_spawn(float(i) * 0.55, kind, Vector2(randf_range(70.0, W - 70.0), -70.0), "dive", Vector2(0, 170.0 * speed))
		"scatter":
			for i in range(count):
				_queue_spawn(float(i) * 0.6, kind, Vector2(randf_range(80.0, W - 80.0), -60.0), "drift", Vector2(0, randf_range(85.0, 125.0) * speed))
		"hold":
			for i in range(count):
				var hx := W * (float(i) + 1.0) / (float(count) + 1.0)
				_queue_spawn(0.0, kind, Vector2(hx, -170.0), "hold", Vector2.ZERO, {"hold_y": top + 210.0 + float(i % 2) * 90.0, "amp": W * 0.5 / float(count) - 70.0})

func _spawn_enemy(cfg: Dictionary) -> void:
	var kind: String = cfg.kind
	var info: Dictionary = Levels.ENEMIES[kind]
	var hp: float = float(info.hp) * float(scale_cfg.hp)
	var s := Sprite2D.new()
	s.texture = ART[str(info.art)]
	s.scale = Vector2.ONE * (float(info.size) / 512.0)
	var hue: float = info.hue
	s.material = _hue_mat(hue, false) if hue != 0.0 else null
	enemy_root.add_child(s)
	var e := {
		"id": next_id, "kind": kind, "pos": cfg.pos, "vel": cfg.vel, "move": cfg.move, "hp": hp, "max": hp,
		"r": info.r, "hue": hue, "sprite": s, "t": randf_range(0.0, 2.0), "age": 0.0, "dead": false,
		"fire": randf_range(0.7, float(info.fire)) if float(info.fire) > 0.0 else 0.0,
		"rate": info.fire, "flash": 0.0, "spin": randf_range(-1.8, 1.8), "base": float(cfg.pos.x),
		"amp": float(cfg.get("amp", 0.0)), "freq": float(cfg.get("freq", 1.0)), "turn": float(cfg.get("turn", 0.0)),
		"hold_y": float(cfg.get("hold_y", 0.0)), "score": info.score, "drop": info.drop,
		"heavy": kind == "gunship" or kind == "elite",
	}
	next_id += 1
	s.position = e.pos
	enemies.append(e)
	if kind == "mine":
		Audio.play("mine", -10.0)

func _update_enemies(dt: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[i]
		var sprite: Sprite2D = e.sprite
		if e.dead:
			sprite.queue_free()
			enemies.remove_at(i)
			continue
		e.t += dt
		e.age += dt
		_move_enemy(e, dt)
		sprite.position = e.pos
		if float(e.flash) > 0.0:
			e.flash -= dt
			if float(e.flash) <= 0.0:
				var hue: float = e.hue
				sprite.material = _hue_mat(hue, false) if hue != 0.0 else null
		var pos: Vector2 = e.pos
		if pos.y > H + 130.0 or pos.x < -220.0 or pos.x > W + 220.0:
			sprite.queue_free()
			enemies.remove_at(i)
			continue
		if float(e.rate) > 0.0 and pos.y > top + 40.0 and pos.y < player_pos.y - 170.0:
			e.fire -= dt * float(scale_cfg.fire)
			if float(e.fire) <= 0.0:
				e.fire = float(e.rate) * randf_range(0.85, 1.15)
				_enemy_shoot(e)
		if player_alive and phase in [Phase.PLAYING, Phase.BOSS]:
			var reach: float = float(e.r) + 24.0
			if pos.distance_squared_to(player_pos) < reach * reach:
				_hurt_player(32.0)
				if not e.heavy:
					_kill_enemy(e, false)

func _move_enemy(e: Dictionary, dt: float) -> void:
	var sprite: Sprite2D = e.sprite
	match str(e.move):
		"straight":
			e.pos += e.vel * dt
			if str(e.kind).begins_with("rock"):
				sprite.rotation += dt * float(e.spin)
				if float(e.pos.x) < 30.0 or float(e.pos.x) > W - 30.0:
					e.vel.x = absf(float(e.vel.x)) * (1.0 if float(e.pos.x) < 30.0 else -1.0)
		"sine":
			e.pos.y += float(e.vel.y) * dt
			e.pos.x = clampf(float(e.base) + sin(float(e.age) * float(e.freq)) * float(e.amp), 50.0, W - 50.0)
			sprite.rotation = -cos(float(e.age) * float(e.freq)) * 0.34 * signf(float(e.amp))
		"arc":
			var angle: float = (e.vel as Vector2).angle()
			if absf(wrapf(angle - PI * 0.5, -PI, PI)) > 0.1:
				e.vel = (e.vel as Vector2).rotated(float(e.turn) * dt)
			e.pos += e.vel * dt
			sprite.rotation = (e.vel as Vector2).angle() + PI * 0.5
			if str(e.kind) == "fighter" or str(e.kind) == "weaver":
				sprite.rotation += PI
		"dive":
			if float(e.age) < 0.85:
				e.pos += e.vel * dt
				sprite.rotation = PI
			else:
				var aim := signf(player_pos.x - float(e.pos.x))
				e.vel.x = move_toward(float(e.vel.x), aim * 240.0, dt * 520.0)
				e.vel.y = move_toward(float(e.vel.y), 620.0 * float(scale_cfg.speed), dt * 680.0)
				e.pos += e.vel * dt
				sprite.rotation = (e.vel as Vector2).angle() + PI * 0.5
		"drift":
			e.pos += e.vel * dt
			e.pos.x += sin(float(e.age) * 1.4) * 34.0 * dt
			sprite.rotation += dt * 0.8
			var pulse := 1.0 + sin(float(e.age) * 7.0) * 0.08
			sprite.scale = Vector2.ONE * (72.0 / 512.0) * pulse
			if float(e.pos.distance_to(player_pos)) < 120.0:
				_kill_enemy(e, false)
		"hold":
			if float(e.pos.y) < float(e.hold_y):
				e.pos.y += 190.0 * dt
				e.age = 0.0
			elif float(e.age) < 16.0:
				e.pos.x = float(e.base) + sin(float(e.age) * 0.75) * maxf(30.0, float(e.amp))
			else:
				e.pos.y += 240.0 * dt

func _enemy_shoot(e: Dictionary) -> void:
	var from: Vector2 = e.pos
	var aim: float = (player_pos - from).angle()
	var speed: float = 270.0 * float(scale_cfg.bullet)
	match str(e.kind):
		"fighter":
			_ebullet(from + Vector2(0, 40), aim, speed, 0)
		"weaver":
			_ebullet(from + Vector2(-26, 30), PI * 0.5, speed * 1.08, 1, 18.0)
			_ebullet(from + Vector2(26, 30), PI * 0.5, speed * 1.08, 1, 18.0)
		"gunship":
			for i in range(5):
				_ebullet(from + Vector2(0, 80), aim + (float(i) - 2.0) * 0.2, speed * 0.95, 1)
		"elite":
			for i in range(14):
				_ebullet(from + Vector2(0, 40), float(i) * TAU / 14.0 + t, speed * 0.8, 0)
			_after(0.45, _elite_followup.bind(e))
	Audio.play("enemy_shoot", -12.0, 1.0, 0.1)

func _elite_followup(e: Dictionary) -> void:
	if e.dead or not player_alive:
		return
	var from: Vector2 = e.pos
	var aim: float = (player_pos - from).angle()
	for i in range(3):
		_ebullet(from + Vector2(0, 80), aim + (float(i) - 1.0) * 0.16, 330.0 * float(scale_cfg.bullet), 1)

func _ebullet(at: Vector2, angle: float, speed: float, tex: int, damage := 24.0) -> void:
	if enemy_bullets.size() > 260:
		return
	enemy_bullets.append({"pos": at, "vel": Vector2.from_angle(angle) * speed, "tex": tex, "dmg": damage, "r": 9.0})

func _update_enemy_bullets(dt: float) -> void:
	for i in range(enemy_bullets.size() - 1, -1, -1):
		# A hull hit clears nearby shots mid-loop, so the list can shrink under us.
		if i >= enemy_bullets.size():
			continue
		var b: Dictionary = enemy_bullets[i]
		b.pos += b.vel * dt
		var p: Vector2 = b.pos
		if p.y > H + 50.0 or p.y < -60.0 or p.x < -50.0 or p.x > W + 50.0:
			enemy_bullets.remove_at(i)
			continue
		# The ship's hitbox is much smaller than its art, which keeps dodging fair.
		var reach: float = float(b.r) + 15.0
		if player_alive and p.distance_squared_to(player_pos) < reach * reach:
			enemy_bullets.remove_at(i)
			_sparks(p, 6, UI.MAGENTA, 160.0, 0.25, 12.0)
			_hurt_player(float(b.dmg))

func _damage_enemy(e: Dictionary, damage: float, at: Vector2) -> void:
	if e.dead:
		return
	e.hp -= damage
	var sprite: Sprite2D = e.sprite
	sprite.material = _hue_mat(0.0, true)
	e.flash = 0.06
	if float(e.hp) <= 0.0:
		_kill_enemy(e, true)
	else:
		Audio.play("hit", -12.0, 1.0, 0.1)
		_sparks(at, 3, UI.CYAN, 200.0, 0.2, 9.0)

func _kill_enemy(e: Dictionary, by_player: bool) -> void:
	if e.dead:
		return
	e.dead = true
	var pos: Vector2 = e.pos
	var kind: String = e.kind
	var size: float = float(Levels.ENEMIES[kind].size)
	kills += 1
	if by_player:
		combo += 1
		best_combo = maxi(best_combo, combo)
		combo_timer = 2.6
		var mult := 1 + combo / 10
		var value: int = int(e.score) * mult
		score += value
		if e.heavy or combo % 10 == 0:
			_float_text("+%d" % value, pos, 30, UI.GOLD)
		_add_energy(2.6 if not e.heavy else 16.0)
		_maybe_drop(e)
	if e.heavy:
		Audio.play("explode_m")
		_boom(pos, size * 1.6, BOOM_L, 0.7)
		_ring(pos, 0.5, 30.0, size * 1.4, UI.ORANGE, 7.0)
		_sparks(pos, 34, UI.ORANGE, 380.0, 0.7, 17.0)
		_kick(11.0)
		hitstop = 0.05
		Save.vibrate(40)
	else:
		Audio.play("explode_s", -5.0, 1.0, 0.12)
		_boom(pos, size * 1.25, BOOM_S if size < 100.0 else BOOM_L, 0.34)
		_sparks(pos, 12, UI.ORANGE if randf() < 0.5 else Color(1.0, 0.85, 0.5), 240.0, 0.4, 13.0)
		_kick(2.6)
	if kind == "rock_l":
		for side in [-1.0, 1.0]:
			_spawn_enemy({"kind": "rock_s", "pos": pos + Vector2(side * 26.0, 0), "move": "straight", "vel": Vector2(side * 110.0, 170.0 * float(scale_cfg.speed))})
	elif kind == "mine":
		var count := 8 + int(float(scale_cfg.d) * 4.0)
		for i in range(count):
			_ebullet(pos, float(i) * TAU / float(count) + 0.2, 215.0 * float(scale_cfg.bullet), 0, 20.0)
		Audio.play("explode_m", -4.0, 1.2)
		_ring(pos, 0.35, 20.0, 170.0, UI.MAGENTA, 6.0)

func _maybe_drop(e: Dictionary) -> void:
	var chance: float = e.drop
	if randf() > chance:
		return
	var heavy: bool = e.heavy
	var count := 4 if heavy else 1
	for i in range(count):
		var v := Vector2(randf_range(-90.0, 90.0), randf_range(-140.0, -60.0)) if heavy else Vector2(randf_range(-30.0, 30.0), -40.0)
		pickups.append({"pos": e.pos, "vel": v, "value": 2 if not heavy else 3, "spin": randf_range(0.0, TAU), "pull": false})

func _add_energy(amount: float) -> void:
	var before := energy
	energy = minf(100.0, energy + amount * energy_gain)
	if before < 100.0 and energy >= 100.0:
		Audio.play("energy_ready", -3.0)
		burst_hint = true

func _update_pickups(dt: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[i]
		p.spin += dt * 3.0
		var pos: Vector2 = p.pos
		var dist := pos.distance_to(player_pos)
		if player_alive and (p.pull or dist < magnet):
			var dir: Vector2 = (player_pos - pos).normalized()
			p.vel = (p.vel as Vector2).lerp(dir * 900.0, 1.0 - exp(-dt * 7.0))
		else:
			p.vel = (p.vel as Vector2).lerp(Vector2(0, 150), 1.0 - exp(-dt * 1.6))
		p.pos += p.vel * dt
		if player_alive and dist < 48.0:
			run_salvage += int(p.value)
			_add_energy(3.0)
			Audio.play("pickup", -9.0, 1.0 + minf(0.5, float(combo) * 0.01), 0.04)
			_sparks(pos, 4, UI.MINT, 120.0, 0.25, 11.0)
			pickups.remove_at(i)
		elif float(p.pos.y) > H + 40.0:
			pickups.remove_at(i)

func _attract_all() -> void:
	for p in pickups:
		p.pull = true

func _on_wave_cleared() -> void:
	clear_wait = -1.0
	Audio.play("wave_clear", -3.0)
	if endless:
		if level.boss and boss == null and not _boss_done_this_wave:
			_begin_warning()
			return
		_boss_done_this_wave = false
		_begin_upgrade()
		return
	if wave_index + 1 < (level.waves as Array).size():
		_begin_upgrade()
	elif level.boss and boss == null and not _boss_done_this_wave:
		_begin_warning()
	else:
		_level_complete()

var _boss_done_this_wave := false

# ---------- Bosses ----------

func _begin_warning() -> void:
	phase = Phase.WARNING
	phase_t = 0.0
	Audio.stop_music(0.5)
	Audio.play("warning")
	Save.vibrate(60)
	_show_banner("WARNING", str(level.boss_def.name), 2.2, UI.RED)

func _spawn_boss() -> void:
	var def: Dictionary = level.boss_def
	var hp: float = float(def.hp)
	if endless:
		hp *= 0.5 + float(endless_wave) * 0.08
	boss_sprite = Sprite2D.new()
	boss_sprite.texture = ART.boss
	boss_sprite.scale = Vector2.ONE * (minf(W * 0.76, 520.0) / 512.0)
	var hue: float = def.hue
	boss_sprite.material = _hue_mat(hue, false) if hue != 0.0 else null
	enemy_root.add_child(boss_sprite)
	boss = {
		"pos": Vector2(W * 0.5, -260.0), "hp": hp, "max": hp, "def": def, "t": 0.0, "attack": 1.6, "order": 0,
		"stage": 0, "flash": 0.0, "rx": minf(W * 0.34, 230.0), "ry": 96.0, "entering": true, "dying": 0.0,
		"charge": 0.0, "pending": "", "stream": 0.0, "stream_angle": 0.0, "stream_timer": 0.0, "hue": hue, "boom": 0.0,
	}
	boss_sprite.position = boss.pos
	phase = Phase.BOSS
	phase_t = 0.0
	Audio.music("boss", 0.3)

func _update_boss(dt: float) -> void:
	if boss == null:
		return
	if float(boss.dying) > 0.0:
		_update_boss_death(dt)
		return
	boss.t += dt
	if boss.entering:
		boss.pos.y = move_toward(float(boss.pos.y), top + 250.0, dt * 260.0)
		if float(boss.pos.y) >= top + 250.0:
			boss.entering = false
	else:
		var sway := maxf(40.0, W * 0.5 - float(boss.rx) - 30.0)
		boss.pos.x = W * 0.5 + sin(float(boss.t) * 0.7) * sway
		boss.pos.y = top + 250.0 + sin(float(boss.t) * 1.4) * 20.0
		boss.attack -= dt * (1.0 + float(boss.stage) * 0.18) * lerpf(1.0, 1.1, float(scale_cfg.d))
		if float(boss.attack) <= 0.0:
			var patterns: Array = boss.def.patterns
			var name_: String = patterns[int(boss.order) % patterns.size()]
			boss.order = int(boss.order) + 1
			boss.pending = name_
			boss.charge = 0.55
			boss.attack = 2.5
			Audio.play("charge", -3.0)
		if float(boss.charge) > 0.0:
			boss.charge -= dt
			if float(boss.charge) <= 0.0:
				_boss_attack(str(boss.pending))
		_update_boss_stream(dt)
		var offset: Vector2 = player_pos - (boss.pos as Vector2)
		if absf(offset.x) < float(boss.rx) * 0.8 and absf(offset.y) < float(boss.ry):
			_hurt_player(36.0)
	if float(boss.flash) > 0.0:
		boss.flash -= dt
		if float(boss.flash) <= 0.0:
			var hue: float = boss.hue
			boss_sprite.material = _hue_mat(hue, false) if hue != 0.0 else null
	boss_sprite.position = boss.pos
	boss_sprite.rotation = sin(float(boss.t) * 0.7) * 0.04

func _muzzle() -> Vector2:
	return (boss.pos as Vector2) + Vector2(0, 80)

func _boss_attack(name_: String) -> void:
	if boss == null or float(boss.dying) > 0.0:
		return
	var from := _muzzle()
	var speed: float = 245.0 * lerpf(1.0, float(scale_cfg.bullet), 0.6)
	var stage: int = boss.stage
	Audio.play("enemy_shoot", -2.0, 0.7)
	match name_:
		"fan":
			var n := 9 + stage * 2
			for i in range(n):
				_ebullet(from, PI * 0.5 + (float(i) - float(n - 1) * 0.5) * 0.17, speed, 1)
			if stage > 0:
				_after(0.5, _boss_attack.bind("aimed"))
		"aimed":
			var aim: float = (player_pos - from).angle()
			for i in range(3):
				_ebullet(from, aim + (float(i) - 1.0) * 0.12, speed * 1.25, 0)
		"burst":
			for i in range(4 + stage):
				_after(float(i) * 0.26, _boss_attack.bind("aimed"))
		"ring":
			var count := 20 + stage * 4
			var gap := randi() % count
			for i in range(count):
				if i == gap or i == (gap + 1) % count:
					continue
				_ebullet(from, float(i) * TAU / float(count), speed * 0.9, 0)
		"spiral":
			boss.stream = 1.9 + float(stage) * 0.4
			boss.stream_angle = randf() * TAU
		"curtain":
			for row in range(3 + stage):
				_after(float(row) * 0.8, _curtain_row)
		"strike":
			var strikes := 1 + stage
			for i in range(strikes):
				var x := randf_range(60.0, W - 60.0) if i > 0 else player_pos.x
				lasers.append({"x": x, "t": 0.0, "warn": 0.95 + float(i) * 0.2, "live": 0.55, "fired": false})
		"rocks":
			_spawn_group({"kind": "rocks", "form": "rain", "count": 4 + stage, "delay": 0.0})
		"raiders":
			_spawn_group({"kind": "raider", "form": "dive", "count": 3 + stage, "delay": 0.0})
		"mines":
			_spawn_group({"kind": "mine", "form": "scatter", "count": 2 + stage, "delay": 0.0})

func _curtain_row() -> void:
	if boss == null or float(boss.dying) > 0.0:
		return
	var gap := randf_range(110.0, W - 110.0)
	var x := 30.0
	while x < W:
		if absf(x - gap) > 118.0:
			_ebullet(Vector2(x, float(boss.pos.y) + 30.0), PI * 0.5, 205.0 * float(scale_cfg.bullet), 1, 20.0)
		x += 58.0

func _update_boss_stream(dt: float) -> void:
	if float(boss.stream) <= 0.0:
		return
	boss.stream -= dt
	boss.stream_timer -= dt
	if float(boss.stream_timer) <= 0.0:
		boss.stream_timer = 0.11
		boss.stream_angle += 0.41
		var from := _muzzle()
		for arm in range(2 + int(boss.stage)):
			_ebullet(from, float(boss.stream_angle) + float(arm) * TAU / float(2 + int(boss.stage)), 215.0 * float(scale_cfg.bullet), 0, 20.0)

func _update_lasers(dt: float) -> void:
	for i in range(lasers.size() - 1, -1, -1):
		var l: Dictionary = lasers[i]
		l.t += dt
		if float(l.t) >= float(l.warn):
			if not l.fired:
				l.fired = true
				Audio.play("laser", -3.0)
				_kick(6.0)
			if float(l.t) >= float(l.warn) + float(l.live):
				lasers.remove_at(i)
				continue
			if player_alive and absf(player_pos.x - float(l.x)) < 58.0:
				_hurt_player(34.0)

func _damage_boss(damage: float, at: Vector2) -> void:
	boss.hp -= damage
	boss.flash = 0.05
	boss_sprite.material = _hue_mat(0.0, true)
	score += 2
	_sparks(at, 2, UI.ORANGE, 220.0, 0.22, 10.0)
	Audio.play("hit", -13.0, 0.8, 0.1)
	_add_energy(0.16)
	var ratio: float = float(boss.hp) / float(boss.max)
	var stage := 2 if ratio < 0.34 else (1 if ratio < 0.67 else 0)
	if stage > int(boss.stage):
		boss.stage = stage
		_kick(10.0)
		flash = 0.3
		flash_color = UI.ORANGE
		Audio.play("explode_m")
		_ring(boss.pos, 0.6, 60.0, 420.0, UI.ORANGE, 8.0)
		_boom(boss.pos, 280.0, BOOM_L, 0.5)
		_show_banner("CORE BREACHED", "It's getting angry", 1.3, UI.ORANGE)
	if float(boss.hp) <= 0.0:
		_boss_killed()

func _boss_killed() -> void:
	boss.dying = 1.9
	boss.boom = 0.0
	time_scale = 0.3
	enemy_bullets.clear()
	lasers.clear()
	for e in enemies:
		_kill_enemy(e, true)
	Audio.stop_music(0.4)
	Save.vibrate(120)

func _update_boss_death(dt: float) -> void:
	var real := dt / maxf(0.05, time_scale)
	boss.dying -= real
	boss.boom -= real
	boss_sprite.position = (boss.pos as Vector2) + Vector2(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0))
	if float(boss.boom) <= 0.0:
		boss.boom = 0.17
		var at: Vector2 = (boss.pos as Vector2) + Vector2(randf_range(-float(boss.rx), float(boss.rx)), randf_range(-float(boss.ry), float(boss.ry)))
		_boom(at, randf_range(120.0, 220.0), BOOM_L, 0.5)
		_sparks(at, 14, UI.ORANGE, 300.0, 0.5, 14.0)
		Audio.play("explode_m", -2.0, 1.0, 0.15)
		_kick(7.0)
	if float(boss.dying) <= 0.0:
		var pos: Vector2 = boss.pos
		Audio.play("explode_l")
		flash = 1.0
		flash_color = Color.WHITE
		_kick(20.0)
		_boom(pos, 640.0, BOOM_L, 1.0)
		_ring(pos, 0.9, 80.0, 900.0, UI.ORANGE, 12.0)
		_ring(pos, 1.1, 40.0, 700.0, Color.WHITE, 6.0)
		_sparks(pos, 90, UI.ORANGE, 560.0, 1.1, 22.0)
		score += 1000 * int(level.sector)
		for i in range(14):
			pickups.append({"pos": pos + Vector2(randf_range(-120.0, 120.0), randf_range(-50.0, 50.0)), "vel": Vector2.from_angle(randf() * TAU) * 240.0, "value": 4, "spin": 0.0, "pull": true})
		boss_sprite.queue_free()
		boss = null
		_boss_done_this_wave = true
		if endless:
			Audio.music(str(Levels.SECTORS[int(level.sector) - 1].music), 1.0)
		phase = Phase.PLAYING
		phase_t = 0.0
		group_queue.clear()
		clear_wait = 1.5
		_attract_all()

# ---------- Modules ----------

func _begin_upgrade() -> void:
	phase = Phase.UPGRADE
	phase_t = 0.0
	card_picked = -1
	input_lock = 0.45
	var pool: Array = []
	for c in CARDS:
		var count := int(card_counts.get(c.id, 0))
		if count >= int(c.max):
			continue
		if c.id == "repair" and hull >= max_hull:
			continue
		pool.append(c)
	pool.shuffle()
	card_options = pool.slice(0, 3)
	if card_options.is_empty():
		if endless:
			_next_endless_wave()
		else:
			_start_wave(wave_index + 1)
		return
	Audio.play("card_in")
	_after_real_card_sounds()

func _after_real_card_sounds() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(0.1).timeout.connect(func() -> void: Audio.play("card_in", 0.0, 1.1))
	tree.create_timer(0.2).timeout.connect(func() -> void: Audio.play("card_in", 0.0, 1.2))

func _select_card(index: int) -> void:
	if phase != Phase.UPGRADE or card_picked >= 0 or input_lock > 0.0 or index >= card_options.size():
		return
	card_picked = index
	input_lock = 0.34
	Audio.play("card_pick")
	Audio.play("powerup", -5.0)
	Save.vibrate(30)

func _install_card() -> void:
	var c: Dictionary = card_options[card_picked]
	card_counts[c.id] = int(card_counts.get(c.id, 0)) + 1
	match str(c.id):
		"spread":
			spread += 1
		"pierce":
			pierce += 1
		"drone":
			drones += 1
		"magnet":
			magnet += 90.0
		"plating":
			max_shield += 25.0
			shield = max_shield
		"afterburner":
			shot_speed += 225.0
			shot_damage *= 1.12
		"critical":
			crit = minf(0.55, crit + 0.10)
		"overclock":
			fire_interval = maxf(0.09, fire_interval * 0.85)
		"repair":
			hull = mini(max_hull, hull + 1)
			Audio.play("repair", -2.0)
	_ring(player_pos, 0.5, 30.0, 220.0, c.color, 6.0)
	_sparks(player_pos, 20, c.color, 260.0, 0.5, 14.0)
	card_picked = -1
	if endless:
		_next_endless_wave()
	else:
		_start_wave(wave_index + 1)

func _next_endless_wave() -> void:
	endless_wave += 1
	level = Levels.build_endless(endless_wave)
	scale_cfg = level.scale
	_start_wave(0)

# ---------- Endings ----------

func _bank() -> void:
	if banked:
		return
	banked = true
	Save.salvage += run_salvage
	Save.save_data()

func _level_complete() -> void:
	phase = Phase.CLEAR
	phase_t = 0.0
	result_win = true
	result_stars = 3 if hull_lost == 0 else (2 if hull_lost == 1 else 1)
	result_reward = int(level.reward) * (2 + result_stars) / 3
	run_salvage += result_reward
	_bank()
	new_best = Save.stars_for(level_num) < result_stars
	Save.record_level(level_num, result_stars, score)
	Save.map_sector = Levels.sector_of(mini(level_num + 1, Levels.LEVEL_COUNT))
	Save.tutorial_done = true
	Save.save_data()
	stars_shown = 0
	input_lock = 1.0
	enemy_bullets.clear()
	Audio.music("stinger_win", 0.2, false)

func _update_result_stars() -> void:
	var due := int((phase_t - 0.7) / 0.38) + 1
	if phase_t > 0.7 and stars_shown < mini(due, result_stars):
		stars_shown += 1
		Audio.play("star_%d" % stars_shown)
		Save.vibrate(20)

func _show_defeat() -> void:
	phase = Phase.DEFEAT
	phase_t = 0.0
	result_win = false
	input_lock = 0.8
	# A consolation payout, so that retrying a tough boss always moves you forward.
	run_salvage += int(level.reward) / 4
	_bank()
	if endless:
		new_best = endless_wave > Save.endless_best_wave
		Save.endless_best_wave = maxi(Save.endless_best_wave, endless_wave)
	Save.best_score = maxi(Save.best_score, score)
	Save.save_data()
	Audio.music("stinger_lose", 0.2, false)

func _set_paused(on: bool) -> void:
	if on:
		if phase in [Phase.CLEAR, Phase.DEFEAT, Phase.PAUSED, Phase.UPGRADE]:
			return
		previous_phase = phase
		phase = Phase.PAUSED
		Audio.set_muffled(true)
		input_lock = 0.1
	elif phase == Phase.PAUSED:
		phase = previous_phase
		Audio.set_muffled(false)

func _leave(scene: String) -> void:
	Audio.set_muffled(false)
	_bank()
	Fade.go(scene)

func _on_ui(id: String) -> void:
	if input_lock > 0.0 and not id in ["pause", "burst"]:
		return
	match id:
		"pause":
			_set_paused(true)
		"burst":
			_nova_burst()
		"resume":
			_set_paused(false)
		"retry":
			_leave("res://game.tscn")
		"next":
			Save.play_level = mini(level_num + 1, Levels.LEVEL_COUNT)
			_leave("res://game.tscn")
		"map":
			Save.menu_screen = "title" if endless else "map"
			Audio.music("menu")
			_leave("res://title_screen.tscn")
		"hangar":
			Save.menu_screen = "hangar"
			Audio.music("menu")
			_leave("res://title_screen.tscn")
		"music":
			Save.music_volume = 0.0 if Save.music_volume > 0.0 else 0.8
			Audio.apply_volumes()
			Save.save_data()
		"sound":
			Save.sfx_volume = 0.0 if Save.sfx_volume > 0.0 else 1.0
			Audio.apply_volumes()
			Save.save_data()
		"card0", "card1", "card2":
			_select_card(int(id.substr(4)))

func _notification(what: int) -> void:
	if Save.path == Save.TEST_PATH:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_paused(true)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if phase == Phase.PAUSED:
			_set_paused(false)
		else:
			_set_paused(true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_P:
				_set_paused(phase != Phase.PAUSED)
			KEY_SPACE:
				_nova_burst()
			KEY_1, KEY_2, KEY_3:
				_select_card(event.keycode - KEY_1)
			KEY_R:
				if phase in [Phase.CLEAR, Phase.DEFEAT]:
					_on_ui("retry")
			KEY_ENTER:
				if phase == Phase.CLEAR:
					_on_ui("next" if level_num < Levels.LEVEL_COUNT else "map")
				elif phase == Phase.DEFEAT:
					_on_ui("retry")
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if drag_finger < 0:
				drag_finger = event.index
		elif event.index == drag_finger:
			drag_finger = -1
	elif event is InputEventScreenDrag and event.index == drag_finger:
		if phase in [Phase.PLAYING, Phase.BOSS, Phase.WARNING]:
			# Relative steering: the ship follows the thumb without sitting under it.
			player_target += event.relative * 1.3
			tut_moved += event.relative.length()
			_clamp_target()

# ---------- Effects ----------

func _update_fx(dt: float) -> void:
	for i in range(sparks.size() - 1, -1, -1):
		var s: Dictionary = sparks[i]
		s.life -= dt
		if float(s.life) <= 0.0:
			sparks.remove_at(i)
		else:
			s.pos += s.vel * dt
			s.vel *= 1.0 - minf(0.9, dt * 3.2)
	for i in range(booms.size() - 1, -1, -1):
		var b: Dictionary = booms[i]
		b.life -= dt
		if float(b.life) <= 0.0:
			booms.remove_at(i)
	for i in range(rings.size() - 1, -1, -1):
		var r: Dictionary = rings[i]
		r.life -= dt
		if float(r.life) <= 0.0:
			rings.remove_at(i)
	for i in range(floaters.size() - 1, -1, -1):
		var f: Dictionary = floaters[i]
		f.life -= dt
		f.pos += Vector2(0, -70.0) * dt
		if float(f.life) <= 0.0:
			floaters.remove_at(i)

func _spark(at: Vector2, vel: Vector2, life: float, color: Color, size: float) -> void:
	if sparks.size() >= 520:
		sparks.remove_at(0)
	sparks.append({"pos": at, "vel": vel, "life": life, "max": life, "color": color, "size": size})

func _sparks(at: Vector2, count: int, color: Color, speed: float, life: float, size: float) -> void:
	for i in range(count):
		_spark(at, Vector2.from_angle(randf() * TAU) * randf_range(speed * 0.25, speed), randf_range(life * 0.5, life), color, randf_range(size * 0.5, size))

func _boom(at: Vector2, size: float, tex: Texture2D, life: float) -> void:
	booms.append({"pos": at, "size": size, "tex": tex, "life": life, "max": life, "rot": randf() * TAU})

func _ring(at: Vector2, life: float, r0: float, r1: float, color: Color, width: float) -> void:
	rings.append({"pos": at, "life": life, "max": life, "r0": r0, "r1": r1, "color": color, "width": width})

func _float_text(value: String, at: Vector2, size: int, color: Color) -> void:
	floaters.append({"pos": at, "text": value, "size": size, "color": color, "life": 0.8})

func _show_banner(title: String, sub: String, duration: float, color: Color) -> void:
	banner = title
	banner_sub = sub
	banner_t = duration
	banner_color = color

# ---------- World painting ----------

func _paint_background(c: DrawLayer) -> void:
	var th := W * 2.0
	var y := fmod(bg_scroll, th) - th
	while y < H:
		c.draw_texture_rect(bg_tex, Rect2(0, y, W, th), false, Color(0.58, 0.58, 0.68))
		y += th
	c.draw_rect(Rect2(0, 0, W, H), Color(0.0, 0.0, 0.03, 0.2))
	for s in stars_bg:
		var depth: float = s.depth
		var twinkle := 0.72 + 0.28 * sin(t * 2.4 + float(s.twinkle))
		var col := Color(0.76, 0.9, 1.0, (0.22 + depth * 0.62) * twinkle)
		var pos: Vector2 = s.pos
		var length := warp * 90.0 * depth
		if length > 1.0:
			c.draw_line(pos, pos - Vector2(0, length), col, 1.0 + depth)
		else:
			c.draw_rect(Rect2(pos, Vector2(1.0, 1.0) * (1.0 + depth * 1.8)), col)

func _paint_pickups(c: DrawLayer) -> void:
	for p in pickups:
		var at: Vector2 = p.pos
		var pulse := 1.0 + sin(t * 8.0 + float(p.spin)) * 0.14
		UI.glow(c, at, 42.0 * pulse, Color(0.3, 0.8, 1.0, 0.5))
		c.draw_set_transform(at, float(p.spin) * 0.4, Vector2.ONE)
		c.draw_texture_rect(SALVAGE_ART, Rect2(-24, -24, 48, 48), false)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _paint_player_shots(c: DrawLayer) -> void:
	for b in bullets:
		var size: float = b.size
		var tint: Color = b.color if pierce == 0 else (b.color as Color).lerp(UI.VIOLET, 0.5)
		c.draw_set_transform(b.pos, float(b.angle) + PI * 0.5, Vector2.ONE)
		c.draw_texture_rect(SHOT_CYAN, Rect2(-size * 0.5, -size * 0.5, size, size), false, tint)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		UI.glow(c, b.pos, 28.0, Color(tint, 0.34))

func _paint_enemy_shots(c: DrawLayer) -> void:
	for b in enemy_bullets:
		var vel: Vector2 = b.vel
		var magenta: bool = int(b.tex) == 0
		var halo := UI.MAGENTA if magenta else UI.ORANGE
		UI.glow(c, b.pos, 36.0, Color(halo, 0.55))
		c.draw_set_transform(b.pos, vel.angle() + (-PI * 0.5 if magenta else PI * 0.5), Vector2.ONE)
		c.draw_texture_rect(SHOT_MAGENTA if magenta else SHOT_ORANGE, Rect2(-34, -34, 68, 68), false)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		c.draw_circle(b.pos, 5.0, Color(1, 1, 1, 0.95))

func _paint_fx_add(c: DrawLayer) -> void:
	for s in sparks:
		var a: float = float(s.life) / float(s.max)
		var size: float = float(s.size) * (0.5 + a * 0.5)
		c.draw_texture_rect(UI.glow_tex(), Rect2((s.pos as Vector2) - Vector2(size, size), Vector2(size, size) * 2.0), false, Color(s.color, a))
	for r in rings:
		var k: float = 1.0 - float(r.life) / float(r.max)
		var ease_k := 1.0 - pow(1.0 - k, 3.0)
		c.draw_arc(r.pos, lerpf(float(r.r0), float(r.r1), ease_k), 0.0, TAU, 72, Color(r.color, (1.0 - k) * 0.9), float(r.width) * (1.0 - k * 0.7), true)
	if player_alive and phase != Phase.UPGRADE:
		var flick := 0.8 + sin(t * 41.0) * 0.2
		UI.glow(c, player_pos + Vector2(0, 54), 46.0 * flick, Color(1.0, 0.6, 0.2, 0.6))
	for e in enemies:
		if e.heavy:
			UI.glow(c, e.pos, float(e.r) * 2.0, Color(UI.MAGENTA, 0.16 + sin(t * 4.0) * 0.05))
	if boss != null:
		var at: Vector2 = boss.pos
		UI.glow(c, at, float(boss.rx) * 1.6, Color(UI.MAGENTA, 0.14))
		if float(boss.charge) > 0.0:
			var k: float = 1.0 - float(boss.charge) / 0.55
			UI.glow(c, _muzzle(), 40.0 + k * 90.0, Color(1.0, 0.5, 0.3, 0.55 + k * 0.4))
	for l in lasers:
		var x: float = l.x
		if float(l.t) < float(l.warn):
			var k: float = float(l.t) / float(l.warn)
			var blink := 0.3 + 0.3 * absf(sin(t * (10.0 + k * 22.0)))
			c.draw_rect(Rect2(x - 58.0, 0, 116.0, H), Color(UI.RED, blink * 0.16))
			c.draw_line(Vector2(x - 58.0, 0), Vector2(x - 58.0, H), Color(UI.RED, blink), 2.0)
			c.draw_line(Vector2(x + 58.0, 0), Vector2(x + 58.0, H), Color(UI.RED, blink), 2.0)
		else:
			var life: float = (float(l.t) - float(l.warn)) / float(l.live)
			var w := 58.0 * (1.0 - life * life) * (0.9 + 0.1 * sin(t * 60.0))
			c.draw_rect(Rect2(x - w, 0, w * 2.0, H), Color(UI.MAGENTA, 0.6))
			c.draw_rect(Rect2(x - w * 0.5, 0, w, H), Color(1.0, 0.8, 0.95, 0.9))

func _paint_fx_top(c: DrawLayer) -> void:
	for b in booms:
		var k: float = 1.0 - float(b.life) / float(b.max)
		var size: float = float(b.size) * (0.55 + 0.6 * pow(k, 0.5))
		var tex: Texture2D = b.tex
		c.draw_set_transform(b.pos, float(b.rot) + k * 0.4, Vector2.ONE)
		c.draw_texture_rect(tex, Rect2(-size * 0.5, -size * 0.5, size, size), false, Color(1, 1, 1, clampf((1.0 - k) * 1.5, 0.0, 1.0)))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for e in enemies:
		if float(e.hp) < float(e.max) and float(e.max) >= 6.0 and not e.dead:
			var size: float = float(e.r) * 1.5
			var at: Vector2 = (e.pos as Vector2) + Vector2(-size * 0.5, -float(e.r) - 16.0)
			c.draw_rect(Rect2(at, Vector2(size, 6)), Color(0, 0, 0, 0.6))
			c.draw_rect(Rect2(at, Vector2(size * clampf(float(e.hp) / float(e.max), 0.0, 1.0), 6)), UI.ORANGE)
	for f in floaters:
		var a := clampf(float(f.life) * 2.2, 0.0, 1.0)
		UI.outlined(c, str(f.text), f.pos, int(f.size), Color(f.color, a), true, UI.CENTER)

# ---------- Interface painting ----------

func _paint_ui(c: UILayer) -> void:
	if phase != Phase.UPGRADE and phase != Phase.CLEAR and phase != Phase.DEFEAT:
		_paint_hud(c)
	if hull == 1 and player_alive and phase != Phase.PAUSED:
		var a := 0.26 + sin(t * 5.0) * 0.12
		c.draw_texture_rect(UI.edge_tex(), Rect2(0, 0, 120, H), false, Color(UI.RED, a))
		c.draw_texture_rect(UI.edge_tex(), Rect2(W, 0, -120, H), false, Color(UI.RED, a))
	_paint_banner(c)
	if tut_active:
		_paint_tutorial(c)
	match phase:
		Phase.UPGRADE:
			_paint_cards(c)
		Phase.CLEAR:
			if phase_t > 0.5:
				_paint_results(c)
		Phase.DEFEAT:
			_paint_results(c)
		Phase.PAUSED:
			_paint_pause(c)
	if flash > 0.0:
		c.draw_rect(Rect2(0, 0, W, H), Color(flash_color, flash * 0.42))

func _paint_hud(c: UILayer) -> void:
	for i in range(max_hull):
		var alive := i < hull
		UI.icon(c, ICON_HULL, Vector2(40.0 + float(i) * 44.0, top + 24.0), 44.0, Color.WHITE if alive else Color(0.3, 0.34, 0.44, 0.5))
	UI.bar(c, Rect2(20, top + 52.0, 232, 18), shield / max_shield, UI.CYAN)
	if shield <= 0.0:
		UI.text(c, "SHIELD DOWN", Vector2(26, top + 96.0), 18, Color(UI.RED, 0.7 + sin(t * 9.0) * 0.3), true)
	elif combo >= 2:
		var size := 26 + mini(combo, 30) / 3
		UI.outlined(c, "COMBO %d" % combo, Vector2(22, top + 100.0), size, UI.GOLD, true)
		c.draw_rect(Rect2(22, top + 108.0, 180.0 * clampf(combo_timer / 2.6, 0.0, 1.0), 4), UI.GOLD)
	UI.outlined(c, str(int(shown_score)), Vector2(W * 0.5, top + 42.0), 42, UI.WHITE, true, UI.CENTER)
	var label := "WAVE %d" % endless_wave if endless else ("LEVEL %d" % level_num)
	if not endless and (level.waves as Array).size() > 0:
		label += "  ·  %d/%d" % [wave_index + 1, (level.waves as Array).size()]
	UI.outlined(c, label, Vector2(W * 0.5, top + 72.0), 20, UI.TEXT_DIM, false, UI.CENTER)
	c.button("pause", Rect2(W - 92, top - 2.0, 74, 74), "", UI.WHITE, {"icon": ICON_PAUSE, "instant": true, "sound": "ui_click"})
	UI.icon(c, SALVAGE_ART, Vector2(W - 42, top + 96.0), 36.0)
	UI.outlined(c, str(run_salvage), Vector2(W - 64, top + 106.0), 26, UI.MINT, true, UI.RIGHT)
	if boss != null:
		_paint_boss_bar(c)
	_paint_burst(c)

func _paint_boss_bar(c: UILayer) -> void:
	var y := top + 128.0
	var r := Rect2(40, y, W - 80, 22)
	UI.outlined(c, str(boss.def.name), Vector2(W * 0.5, y - 8.0), 22, Color(1.0, 0.8, 0.86), true, UI.CENTER)
	UI.bar(c, r, float(boss.hp) / float(boss.max), UI.MAGENTA)
	for k in [0.34, 0.67]:
		var x: float = r.position.x + r.size.x * float(k)
		c.draw_line(Vector2(x, y), Vector2(x, y + 22.0), Color(1, 1, 1, 0.65), 2.0)

func _paint_burst(c: UILayer) -> void:
	var center := Vector2(W - 92.0, H - 104.0 - inset.y)
	var ready := energy >= 100.0
	var r := 64.0
	if ready:
		c.hit_area("burst", Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), {"instant": true, "sound": ""})
		UI.glow(c, center, r * 1.8 + sin(t * 6.0) * 10.0, Color(UI.CYAN, 0.5))
	c.draw_circle(center, r, Color(0.02, 0.05, 0.12, 0.82))
	c.draw_arc(center, r - 4.0, 0.0, TAU, 48, Color(UI.CYAN, 0.2), 6.0, true)
	c.draw_arc(center, r - 4.0, -PI * 0.5, -PI * 0.5 + TAU * energy / 100.0, 48, UI.MINT if ready else UI.CYAN, 7.0, true)
	UI.icon(c, ICON_WAVE, center + Vector2(0, -12), 70.0, Color.WHITE if ready else Color(1, 1, 1, 0.45))
	UI.text(c, "NOVA" if ready else "%d%%" % int(energy), center + Vector2(0, 34), 20, UI.WHITE if ready else UI.TEXT_DIM, true, UI.CENTER)
	if ready and burst_hint and not Save.tutorial_done:
		UI.outlined(c, "TAP TO CLEAR THE SCREEN", center + Vector2(-90, -94), 22, UI.MINT, true, UI.RIGHT)

func _paint_banner(c: UILayer) -> void:
	if banner_t <= 0.0:
		return
	var a := clampf(banner_t * 3.5, 0.0, 1.0)
	var y := H * 0.34
	var slide := pow(a, 2.0)
	var w := 600.0 * slide
	c.draw_rect(Rect2(W * 0.5 - w * 0.5, y - 92.0, w, 3), Color(banner_color, a * 0.9))
	c.draw_rect(Rect2(W * 0.5 - w * 0.5, y + (34.0 if not banner_sub.is_empty() else 18.0), w, 3), Color(banner_color, a * 0.9))
	UI.glow_text(c, banner, Vector2(W * 0.5, y - 14.0), 66, Color(1, 1, 1, a), banner_color)
	if not banner_sub.is_empty():
		UI.outlined(c, banner_sub, Vector2(W * 0.5, y + 22.0), 25, Color(banner_color, a), false, UI.CENTER)

func _paint_tutorial(c: UILayer) -> void:
	if tut_moved > 500.0 or phase not in [Phase.PLAYING, Phase.INTRO]:
		if tut_moved > 500.0:
			tut_active = false
		return
	if phase == Phase.INTRO:
		return
	var y := H * 0.5 - 60.0
	var hand := Vector2(W * 0.5 + sin(t * 2.4) * 150.0, y + 60.0)
	c.draw_line(Vector2(W * 0.5 - 170.0, y + 60.0), Vector2(W * 0.5 + 170.0, y + 60.0), Color(UI.CYAN, 0.35), 3.0)
	UI.glow(c, hand, 56.0, Color(UI.CYAN, 0.5))
	c.draw_circle(hand, 22.0, Color(1, 1, 1, 0.85))
	UI.outlined(c, "DRAG ANYWHERE TO MOVE", Vector2(W * 0.5, y), 30, UI.WHITE, true, UI.CENTER)
	UI.outlined(c, "Your ship fires by itself", Vector2(W * 0.5, y + 118.0), 22, UI.TEXT_DIM, false, UI.CENTER)

func _paint_cards(c: UILayer) -> void:
	var a := clampf(phase_t * 5.0, 0.0, 1.0)
	c.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.01, 0.04, 0.82 * a))
	var w := minf(W - 48.0, 672.0)
	var x := (W - w) * 0.5
	var h := 196.0
	var gap := 22.0
	var count := card_options.size()
	var y0 := H * 0.5 - (float(count) * h + float(count - 1) * gap) * 0.5 + 40.0
	UI.icon(c, ICON_MODULES, Vector2(W * 0.5, y0 - 158.0), 76.0, Color(1, 1, 1, a))
	UI.glow_text(c, "MODULE BAY", Vector2(W * 0.5, y0 - 66.0), 52, Color(1, 1, 1, a), UI.CYAN)
	UI.text(c, "Pick one upgrade for this level", Vector2(W * 0.5, y0 - 26.0), 22, Color(UI.MINT, a), false, UI.CENTER)
	for i in range(count):
		var option: Dictionary = card_options[i]
		var delay := float(i) * 0.09
		var k := clampf((phase_t - delay) * 4.5, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		var color: Color = option.color
		var rect := Rect2(x + (1.0 - k) * W * (1.0 if i % 2 == 0 else -1.0), y0 + float(i) * (h + gap), w, h)
		var id := "card%d" % i
		c.hit_area(id, rect, {"sound": ""})
		var picked := card_picked == i
		var press := c.press_amount(id)
		var fade := 0.28 if card_picked >= 0 and not picked else 1.0
		var scale_by := 1.0 - press * 0.03 + (0.03 if picked else 0.0)
		c.draw_set_transform(rect.get_center(), 0.0, Vector2(scale_by, scale_by))
		var r := Rect2(-rect.size * 0.5, rect.size)
		var fill := Color(color.darkened(0.8), 0.98 * fade)
		if picked:
			fill = color.darkened(0.45)
		UI.panel(c, r, fill, Color(color, 0.95 * fade), 18, 3, 14 if picked else 0)
		var icon_at := r.position + Vector2(100, h * 0.5)
		UI.glow(c, icon_at, 96.0, Color(color, 0.3 * fade))
		UI.icon(c, option.icon, icon_at, 128.0, Color(1, 1, 1, fade))
		var tx := r.position.x + 190.0
		UI.text(c, str(option.name), Vector2(tx, r.position.y + 72.0), 31, Color(UI.WHITE, fade), true)
		var lines := UI.wrap_lines(str(option.desc), 22, w - 216.0)
		for l in range(lines.size()):
			UI.text(c, lines[l], Vector2(tx, r.position.y + 110.0 + float(l) * 30.0), 22, Color(UI.TEXT_DIM, fade))
		var owned := int(card_counts.get(option.id, 0))
		if int(option.max) < 9:
			UI.pips(c, Vector2(tx, r.position.y + 164.0), int(option.max), owned, Color(color, fade))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	UI.text(c, "Tap a card", Vector2(W * 0.5, y0 + float(count) * (h + gap) + 26.0), 20, Color(UI.TEXT_DIM, a * 0.8), false, UI.CENTER)

func _paint_results(c: UILayer) -> void:
	var k := clampf((phase_t - (0.5 if result_win else 0.0)) * 3.5, 0.0, 1.0)
	c.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.01, 0.04, 0.84 * k))
	var w := minf(W - 56.0, 664.0)
	var x := (W - w) * 0.5
	var mid := H * 0.5
	var color: Color = UI.MINT if result_win else UI.RED
	var offset := (1.0 - k) * 60.0
	var title := "LEVEL CLEAR" if result_win else "SIGNAL LOST"
	if result_win and level_num == Levels.LEVEL_COUNT:
		title = "YOU WON"
	UI.glow_text(c, title, Vector2(W * 0.5, mid - 330.0 + offset), 62, Color(1, 1, 1, k), color)
	var sub := "All sectors cleared. The starfall is over." if result_win and level_num == Levels.LEVEL_COUNT else (str(Levels.sector(level_num).name) if not endless else "ENDLESS")
	UI.text(c, sub, Vector2(W * 0.5, mid - 286.0 + offset), 23, Color(color, k), false, UI.CENTER)
	var panel := Rect2(x, mid - 250.0 + offset, w, 330.0)
	UI.panel(c, panel, Color(0.03, 0.05, 0.12, 0.97 * k), Color(color, 0.7 * k), 20, 2, 12)
	if result_win:
		for i in range(3):
			var at := Vector2(W * 0.5 + (float(i) - 1.0) * 112.0, panel.position.y + 84.0 - (14.0 if i == 1 else 0.0))
			var on := i < stars_shown
			var r := 50.0 if i == 1 else 42.0
			if on:
				UI.glow(c, at, r * 2.0, Color(UI.GOLD, 0.5))
			UI.star(c, at, r, UI.GOLD if on else Color(0.2, 0.24, 0.34, k))
	elif endless:
		UI.text(c, "REACHED WAVE", Vector2(W * 0.5, panel.position.y + 56.0), 22, UI.TEXT_DIM, false, UI.CENTER)
		UI.text(c, str(endless_wave), Vector2(W * 0.5, panel.position.y + 122.0), 64, UI.GOLD, true, UI.CENTER)
	else:
		var tip := "Spend salvage in the Hangar to get stronger"
		var lines := UI.wrap_lines(tip, 24, w - 80.0)
		for l in range(lines.size()):
			UI.text(c, lines[l], Vector2(W * 0.5, panel.position.y + 70.0 + float(l) * 34.0), 24, UI.TEXT_DIM, false, UI.CENTER)
	var row := panel.position.y + 180.0
	UI.text(c, "SCORE", Vector2(x + 40.0, row), 23, Color(UI.TEXT_DIM, k), true)
	UI.text(c, str(score), Vector2(x + w - 40.0, row), 34, Color(UI.WHITE, k), true, UI.RIGHT)
	c.draw_line(Vector2(x + 34.0, row + 18.0), Vector2(x + w - 34.0, row + 18.0), Color(1, 1, 1, 0.1 * k), 1.0)
	row += 58.0
	UI.icon(c, SALVAGE_ART, Vector2(x + 58.0, row - 10.0), 40.0, Color(1, 1, 1, k))
	UI.text(c, "SALVAGE", Vector2(x + 86.0, row), 23, Color(UI.TEXT_DIM, k), true)
	UI.text(c, "+%d" % run_salvage, Vector2(x + w - 40.0, row), 34, Color(UI.MINT, k), true, UI.RIGHT)
	c.draw_line(Vector2(x + 34.0, row + 18.0), Vector2(x + w - 34.0, row + 18.0), Color(1, 1, 1, 0.1 * k), 1.0)
	row += 50.0
	UI.text(c, "BEST COMBO", Vector2(x + 40.0, row), 23, Color(UI.TEXT_DIM, k), true)
	UI.text(c, str(best_combo), Vector2(x + w - 40.0, row), 28, Color(UI.GOLD, k), true, UI.RIGHT)
	if k < 1.0:
		return
	var by := panel.end.y + 34.0
	var half := (w - 20.0) * 0.5
	if result_win:
		if level_num < Levels.LEVEL_COUNT:
			c.button("next", Rect2(x, by, w, 100), "NEXT LEVEL", UI.MINT, {"primary": true, "icon": ICON_PLAY, "size": 34})
		else:
			c.button("map", Rect2(x, by, w, 100), "BACK TO MAP", UI.MINT, {"primary": true, "size": 34})
		c.button("retry", Rect2(x, by + 118.0, half, 84), "REPLAY", UI.CYAN, {"size": 26})
		c.button("hangar", Rect2(x + half + 20.0, by + 118.0, half, 84), "HANGAR", UI.CYAN, {"size": 26})
	else:
		c.button("retry", Rect2(x, by, w, 100), "TRY AGAIN", UI.ORANGE, {"primary": true, "icon": ICON_PLAY, "size": 34})
		c.button("hangar", Rect2(x, by + 118.0, half, 84), "HANGAR", UI.CYAN, {"size": 26})
		c.button("map", Rect2(x + half + 20.0, by + 118.0, half, 84), "MENU" if endless else "MAP", UI.CYAN, {"size": 26})

func _paint_pause(c: UILayer) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.01, 0.04, 0.84))
	var w := minf(W - 100.0, 560.0)
	var x := (W - w) * 0.5
	var y := H * 0.5 - 330.0
	UI.glow_text(c, "PAUSED", Vector2(W * 0.5, y), 66, UI.WHITE, UI.CYAN)
	UI.text(c, "LEVEL %d" % level_num if not endless else "WAVE %d" % endless_wave, Vector2(W * 0.5, y + 42.0), 24, UI.MINT, false, UI.CENTER)
	y += 90.0
	c.button("resume", Rect2(x, y, w, 104), "RESUME", UI.MINT, {"primary": true, "icon": ICON_PLAY, "size": 36})
	y += 122.0
	c.button("retry", Rect2(x, y, w, 88), "RESTART LEVEL" if not endless else "RESTART", UI.CYAN, {"size": 28})
	y += 106.0
	var half := (w - 18.0) * 0.5
	var music_on := Save.music_volume > 0.0
	var sound_on := Save.sfx_volume > 0.0
	c.button("music", Rect2(x, y, half, 84), "MUSIC ON" if music_on else "MUSIC OFF", UI.CYAN if music_on else Color(0.5, 0.54, 0.64), {"size": 23})
	c.button("sound", Rect2(x + half + 18.0, y, half, 84), "SOUND ON" if sound_on else "SOUND OFF", UI.CYAN if sound_on else Color(0.5, 0.54, 0.64), {"size": 23})
	y += 102.0
	c.button("map", Rect2(x, y, w, 88), "QUIT LEVEL", UI.RED, {"icon": ICON_HOME, "size": 28, "sound": "ui_back"})
