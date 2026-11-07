extends Node2D

const BG_FAR = null
const BG_MID = null
const BG_NEAR = null
const BGM = null
const SFX_SHOOT = null
const SFX_HIT = null
const SFX_EXPLOSION = null
const UI_FONT = null
const MEDIUM_FONT = null
const BOLD_FONT = null
const TITLE_FONT = null
const PLAYER_ART = preload("res://assets/starfall/ships/player_nova_01.png")
const ENEMY_ART = preload("res://assets/starfall/ships/enemy_fighter_01.png")
const BOSS_ART = preload("res://assets/starfall/ships/boss_ship_01.png")
const DRONE_ART = preload("res://assets/starfall/ships/player_interceptor_02.png")
const SALVAGE_ART = preload("res://assets/starfall/environment/salvage_crystal_blue.png")
const ASTEROID_SMALL = preload("res://assets/starfall/environment/asteroid_small.png")
const ASTEROID_MEDIUM = preload("res://assets/starfall/environment/asteroid_medium.png")
const ASTEROID_LARGE = preload("res://assets/starfall/environment/asteroid_large.png")
const PLAYER_PROJECTILE = preload("res://assets/starfall/projectiles/projectile_player_cyan.png")
const ENEMY_PROJECTILE = preload("res://assets/starfall/projectiles/projectile_enemy_magenta.png")
const ENEMY_PROJECTILE_ORANGE = preload("res://assets/starfall/projectiles/projectile_enemy_orange.png")
const EXPLOSION_SMALL = preload("res://assets/starfall/effects/effect_explosion_small.png")
const EXPLOSION_LARGE = preload("res://assets/starfall/effects/effect_explosion_large.png")
const SHIELD_ORB = preload("res://assets/starfall/effects/effect_shield_orb.png")
const UPGRADE_HULL = preload("res://assets/starfall/ui_icons/upgrade_hull_plating.png")
const UPGRADE_AFTERBURNER = preload("res://assets/starfall/ui_icons/upgrade_afterburner.png")
const UPGRADE_TRI_BEAM = preload("res://assets/starfall/ui_icons/upgrade_tri_beam.png")

const W := 720.0
const H := 1280.0
const PLAYER_Y := 1070.0
const SECTOR_COUNT := 3
const WAVES_PER_SECTOR := 4
const PLAYER_RADIUS := 18.0
const CYAN := Color(0.23, 0.90, 1.0)
const MINT := Color(0.29, 1.0, 0.74)
const ORANGE := Color(1.0, 0.54, 0.23)
const MAGENTA := Color(1.0, 0.25, 0.66)
const VIOLET := Color(0.47, 0.35, 1.0)

# Kept as a small phase machine so pause, restart and result states stay explicit.
enum Phase { INTRO, PLAYING, BOSS, TRANSITION, VICTORY, DEFEAT, PAUSED, UPGRADE }

var phase: Phase = Phase.INTRO
var previous_phase: Phase = Phase.PLAYING
var far_sprites: Array = []
var mid_sprites: Array = []
var near_sprites: Array = []
var player_sprite: Sprite2D
var boss_sprite: Sprite2D
var drone_sprites: Array = []
var bg_scroll := 0.0
var stars: Array = []
var nebula_clouds: Array = []
var particles: Array = []
var bullets: Array = []
var enemy_bullets: Array = []
var enemies: Array = []
var pickups: Array = []
var upgrade_options: Array = []
var card_rects: Array = []
var boss = null

var player_pos := Vector2(W * 0.5, PLAYER_Y)
var player_hp := 3
var max_player_hp := 3
var shield := 100.0
var max_shield := 100.0
var energy := 55.0
var max_energy := 100.0
var score := 0
var best_score := 0
var salvage := 0
var combo := 0
var combo_timer := 0.0
var sector := 1
var wave := 1
var wave_spawned := 0
var wave_target := 0
var wave_elapsed := 0.0
var wave_clear_wait := -1.0
var spawn_timer := 0.0
var fire_timer := 0.0
var drone_timer := 0.0
var boss_elapsed := 0.0
var boss_attack_timer := 0.0
var boss_pattern := 0
var transition_timer := 0.0
var intro_timer := 2.4
var invulnerable := 0.0
var flash := 0.0
var screen_shake := 0.0
var message := ""
var message_timer := 0.0
var selected_card := -1
var upgrade_after_boss := false
var rng := RandomNumberGenerator.new()

# Run-build stats. Every card changes the simulation, not just the presentation.
var shot_level := 1
var spread_level := 0
var pierce := 0
var drone_count := 0
var magnet_level := 0
var critical_chance := 0.05
var player_speed := 520.0
var fire_interval := 0.30

var touch_id := -1
var touch_active := false
var touch_position := Vector2.ZERO
var pause_rect := Rect2(W - 132, 26, 102, 46)
var audio_paused := false
var audio_pause_writes := 0
var bgm_player: AudioStreamPlayer
var shoot_sfx: AudioStreamPlayer
var hit_sfx: AudioStreamPlayer
var explosion_sfx: AudioStreamPlayer

func _ready() -> void:
	rng.seed = 238417
	_load_score()
	_make_background()
	_make_hero_art()
	_make_audio()
	for i in range(86):
		stars.append({"pos": Vector2(rng.randf_range(0.0, W), rng.randf_range(0.0, H)), "speed": rng.randf_range(12.0, 70.0), "size": rng.randf_range(0.7, 2.8), "layer": rng.randf_range(0.2, 1.0)})
	for i in range(9):
		nebula_clouds.append({"pos": Vector2(rng.randf_range(-80.0, W + 80.0), rng.randf_range(-120.0, H + 120.0)), "speed": rng.randf_range(3.0, 12.0), "drift": rng.randf_range(4.0, 16.0), "size": rng.randf_range(70.0, 170.0), "layer": rng.randf_range(0.18, 0.72), "phase": rng.randf_range(0.0, TAU), "color": [Color(0.22, 0.48, 0.82), Color(0.50, 0.18, 0.62), Color(0.10, 0.62, 0.70)][i % 3]})
	_start_wave()
	set_process(true)
	set_process_unhandled_input(true)
	queue_redraw()

func _make_hero_art() -> void:
	player_sprite = Sprite2D.new()
	player_sprite.texture = PLAYER_ART
	player_sprite.scale = Vector2(0.18, 0.18)
	player_sprite.position = player_pos
	player_sprite.z_index = 4
	add_child(player_sprite)
	boss_sprite = Sprite2D.new()
	boss_sprite.texture = BOSS_ART
	boss_sprite.scale = Vector2(0.24, 0.24)
	boss_sprite.z_index = 3
	boss_sprite.visible = false
	add_child(boss_sprite)
	for i in range(3):
		var drone := Sprite2D.new()
		drone.texture = DRONE_ART
		drone.scale = Vector2(0.075, 0.075)
		drone.z_index = 5
		drone.visible = false
		add_child(drone)
		drone_sprites.append(drone)

func _make_background() -> void:
	# The procedural starfield and nebula pool provide the background without external template files.
	pass

func _create_background_layer(texture: Texture2D, target: Array, z: int, tint: Color) -> void:
	var cover := maxf(W / float(texture.get_width()), H / float(texture.get_height())) * 1.08
	for i in range(2):
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.position = Vector2(W * 0.5, H * 0.5 + float(i) * H)
		sprite.scale = Vector2(cover, cover)
		sprite.modulate = tint
		sprite.z_index = z
		add_child(sprite)
		target.append(sprite)

func _make_audio() -> void:
	# Audio is optional for this standalone build; gameplay remains fully playable without template audio.
	bgm_player = null
	shoot_sfx = null
	hit_sfx = null
	explosion_sfx = null

func _process(delta: float) -> void:
	_sync_audio_pause()
	_update_ambient(minf(delta, 0.05))
	if phase == Phase.PAUSED:
		queue_redraw()
		return
	var dt := minf(delta, 0.04)
	_screen_shake_step(dt)
	if message_timer > 0.0:
		message_timer = maxf(0.0, message_timer - dt)
	if invulnerable > 0.0:
		invulnerable = maxf(0.0, invulnerable - dt)
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	if combo_timer > 0.0:
		combo_timer = maxf(0.0, combo_timer - dt)
	else:
		combo = 0
	_update_particles(dt)
	if phase == Phase.INTRO:
		intro_timer -= dt
		if intro_timer <= 0.0:
			phase = Phase.PLAYING
	elif phase == Phase.PLAYING:
		_update_playing(dt)
	elif phase == Phase.BOSS:
		_update_playing(dt)
		_update_boss(dt)
	elif phase == Phase.TRANSITION:
		transition_timer -= dt
		if transition_timer <= 0.0:
			sector += 1
			wave = 1
			_start_wave()
	elif phase == Phase.UPGRADE:
		# Cards are intentionally static while the player decides.
		pass
	if player_sprite:
		player_sprite.position = player_pos
	_sync_hero_art()
	queue_redraw()

func _sync_hero_art() -> void:
	if boss_sprite:
		boss_sprite.visible = boss != null
		if boss != null:
			boss_sprite.position = boss.pos
			boss_sprite.rotation = boss_elapsed * 0.12
	for i in range(drone_sprites.size()):
		var drone: Sprite2D = drone_sprites[i]
		drone.visible = i < drone_count and phase not in [Phase.VICTORY, Phase.DEFEAT]
		if drone.visible:
			var angle := bg_scroll * 2.0 + float(i) * TAU / float(max(1, drone_count))
			drone.position = player_pos + Vector2.from_angle(angle) * (56.0 + i * 7.0)
			drone.rotation = -angle

func _update_ambient(dt: float) -> void:
	bg_scroll += dt
	for s in stars:
		s.pos.y += s.speed * dt * (0.24 + s.layer * 1.18)
		s.pos.x += sin(bg_scroll * (0.25 + s.layer * 0.5) + s.pos.y * 0.004) * dt * s.layer * 3.0
		if s.pos.y > H + 20.0:
			s.pos.y = -20.0
			s.pos.x = rng.randf_range(0.0, W)
	for cloud in nebula_clouds:
		cloud.pos.y += cloud.speed * dt * (0.35 + cloud.layer)
		cloud.pos.x += sin(bg_scroll * 0.22 + cloud.phase) * dt * cloud.drift * cloud.layer
		if cloud.pos.y > H + cloud.size:
			cloud.pos.y = -cloud.size
			cloud.pos.x = rng.randf_range(-80.0, W + 80.0)
	for layer in [far_sprites, mid_sprites, near_sprites]:
		for sprite in layer:
			sprite.position.y += dt * (9.0 + float(layer.size()) * 1.5)
			if sprite.position.y > H * 1.5:
				sprite.position.y -= H * 2.0

func _update_playing(dt: float) -> void:
	_update_player(dt)
	_update_bullets(dt)
	_update_enemy_bullets(dt)
	_update_enemies(dt)
	_update_pickups(dt)
	_update_drone(dt)
	energy = minf(max_energy, energy + dt * 9.0)
	if phase == Phase.PLAYING:
		_update_wave(dt)

func _update_player(dt: float) -> void:
	var axis := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		axis -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		axis += 1.0
	if touch_active:
		var target_x := clampf(touch_position.x, 48.0, W - 48.0)
		player_pos.x = move_toward(player_pos.x, target_x, player_speed * 1.8 * dt)
	else:
		player_pos.x += axis * player_speed * dt
	player_pos.x = clampf(player_pos.x, 48.0, W - 48.0)
	player_pos.y = PLAYER_Y + sin(Time.get_ticks_msec() * 0.006) * 2.0
	fire_timer -= dt
	if fire_timer <= 0.0:
		shoot_player()

func shoot_player() -> void:
	fire_timer = fire_interval
	var lanes := 1 + spread_level
	for i in range(lanes):
		var offset := (float(i) - float(lanes - 1) * 0.5) * 0.18
		var direction := Vector2(sin(offset), -cos(offset)).normalized()
		bullets.append({"pos": player_pos + Vector2(0, -30), "vel": direction * 820.0, "radius": 5.0, "damage": 1.0, "pierce": pierce, "color": CYAN, "texture": PLAYER_PROJECTILE})
	if shoot_sfx:
		shoot_sfx.pitch_scale = rng.randf_range(0.96, 1.06)
		shoot_sfx.play()
	_kick_shake(1.1)
	for i in range(5):
		particles.append({"pos": player_pos + Vector2(rng.randf_range(-10, 10), 24), "vel": Vector2(rng.randf_range(-32, 32), rng.randf_range(90, 190)), "life": rng.randf_range(0.12, 0.22), "max": 0.22, "color": ORANGE if i % 2 == 0 else Color(1.0, 0.88, 0.42), "size": rng.randf_range(2.0, 4.0)})
	for i in range(lanes):
		var lane_offset := (float(i) - float(lanes - 1) * 0.5) * 0.18
		particles.append({"pos": player_pos + Vector2(sin(lane_offset) * 8.0, -25), "vel": Vector2(sin(lane_offset) * 28.0, -rng.randf_range(120.0, 190.0)), "life": 0.14, "max": 0.14, "color": CYAN, "size": 2.5})

func _update_wave(dt: float) -> void:
	wave_elapsed += dt
	if wave_spawned < wave_target:
		spawn_timer -= dt
		if spawn_timer <= 0.0:
			spawn_timer = maxf(0.24, 0.56 - sector * 0.04 - wave * 0.02)
			spawn_enemy(wave_spawned)
			wave_spawned += 1
	else:
		if enemies.is_empty() and wave_clear_wait < 0.0:
			wave_clear_wait = 0.8
		if wave_clear_wait >= 0.0:
			wave_clear_wait -= dt
			if wave_clear_wait <= 0.0:
				_begin_upgrade(false)

func _start_wave() -> void:
	phase = Phase.PLAYING
	wave_spawned = 0
	wave_elapsed = 0.0
	wave_clear_wait = -1.0
	spawn_timer = 0.25
	wave_target = 7 + sector * 3 + wave * 2
	message = "SECTOR %02d  //  WAVE %02d" % [sector, wave]
	message_timer = 2.2

func spawn_enemy(index: int) -> void:
	var elite := (index + wave + sector) % 7 == 0 or (wave == WAVES_PER_SECTOR and index % 5 == 0)
	var radius := 30.0 if elite else rng.randf_range(19.0, 27.0)
	var hp := 4.0 + sector * 1.5 if elite else 1.0 + sector * 0.55
	var x := rng.randf_range(46.0, W - 46.0)
	var color := MAGENTA if elite else Color(0.45, 0.68, 0.92)
	var data: Dictionary = {"pos": Vector2(x, -60.0 - index * 32.0), "vel": Vector2(rng.randf_range(-48.0, 48.0), rng.randf_range(75.0, 125.0) + sector * 12.0), "hp": hp, "max_hp": hp, "radius": radius, "elite": elite, "phase": rng.randf_range(0.0, TAU), "fire": rng.randf_range(0.65, 1.6), "rot": rng.randf_range(-1.7, 1.7), "color": color}
	var art := Sprite2D.new()
	if elite:
		art.texture = ENEMY_ART
		art.scale = Vector2(0.115, 0.115)
	else:
		art.texture = ASTEROID_LARGE if radius > 25.0 else (ASTEROID_MEDIUM if radius > 22.0 else ASTEROID_SMALL)
		var asteroid_scale := 0.22 if radius > 25.0 else (0.17 if radius > 22.0 else 0.13)
		art.scale = Vector2(asteroid_scale, asteroid_scale)
	art.z_index = 2
	add_child(art)
	data["art"] = art
	enemies.append(data)

func _update_enemies(dt: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		enemy.pos += enemy.vel * dt
		enemy.pos.x += sin(bg_scroll * 2.2 + float(enemy.phase)) * dt * (32.0 if enemy.elite else 18.0)
		enemy.rot += dt * float(enemy.get("rot", 0.0))
		if enemy.has("art"):
			enemy.art.position = enemy.pos
			enemy.art.rotation = enemy.rot
		enemy.fire -= dt
		if enemy.fire <= 0.0 and enemy.pos.y > 40.0 and enemy.pos.y < H * 0.62:
			enemy.fire = 1.4 if enemy.elite else 2.3
			var aim: Vector2 = (player_pos - enemy.pos).normalized()
			enemy_bullets.append({"pos": enemy.pos, "vel": aim * (270.0 + sector * 25.0), "radius": 7.0 if enemy.elite else 5.0, "damage": 18.0 if enemy.elite else 12.0, "color": MAGENTA if enemy.elite else Color(0.88, 0.45, 0.72), "texture": ENEMY_PROJECTILE if enemy.elite else ENEMY_PROJECTILE_ORANGE})
		if enemy.pos.y > H + 80.0:
			if enemy.has("art"):
				enemy.art.queue_free()
			enemies.remove_at(i)
		else:
			enemies[i] = enemy

func _update_bullets(dt: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[i]
		bullet.pos += bullet.vel * dt
		var remove_bullet: bool = bullet.pos.y < -60.0 or bullet.pos.y > H + 60.0
		if phase == Phase.BOSS and boss != null and not remove_bullet:
			if bullet.pos.distance_to(boss.pos) < 112.0:
				var damage := float(bullet.damage)
				if rng.randf() < critical_chance:
					damage *= 2.0
				boss.hp -= damage
				_spawn_hit(bullet.pos, ORANGE)
				bullet.pierce = int(bullet.pierce) - 1
				remove_bullet = int(bullet.pierce) < 0
				if boss.hp <= 0.0:
					_boss_defeated()
		if not remove_bullet and phase == Phase.PLAYING:
			for j in range(enemies.size() - 1, -1, -1):
				var enemy: Dictionary = enemies[j]
				if bullet.pos.distance_to(enemy.pos) < float(enemy.radius) + float(bullet.radius):
					var damage := float(bullet.damage)
					if rng.randf() < critical_chance:
						damage *= 2.0
					enemy.hp -= damage
					_spawn_hit(bullet.pos, ORANGE if damage > 1.0 else CYAN)
					bullet.pierce = int(bullet.pierce) - 1
					remove_bullet = int(bullet.pierce) < 0
					if enemy.hp <= 0.0:
						_destroy_enemy(j)
					if remove_bullet:
						break
		if remove_bullet:
			bullets.remove_at(i)
		else:
			bullets[i] = bullet

func _update_enemy_bullets(dt: float) -> void:
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var bullet: Dictionary = enemy_bullets[i]
		bullet.pos += bullet.vel * dt
		if bullet.pos.y > H + 40.0 or bullet.pos.x < -60.0 or bullet.pos.x > W + 60.0:
			enemy_bullets.remove_at(i)
			continue
		if bullet.pos.distance_to(player_pos) < PLAYER_RADIUS + float(bullet.radius):
			_damage_player(float(bullet.damage))
			enemy_bullets.remove_at(i)
		else:
			enemy_bullets[i] = bullet

func _destroy_enemy(index: int) -> void:
	if index < 0 or index >= enemies.size():
		return
	var enemy: Dictionary = enemies[index]
	var value := 40 if enemy.elite else 15
	score += value * max(1, combo + 1)
	salvage += 4 if enemy.elite else 1
	combo += 1
	combo_timer = 2.2
	_kick_shake(7.0 if enemy.elite else 3.5)
	for k in range(12 if enemy.elite else 7):
		var angle := rng.randf_range(0.0, TAU)
		particles.append({"pos": enemy.pos, "vel": Vector2.from_angle(angle) * rng.randf_range(45.0, 160.0), "life": rng.randf_range(0.24, 0.55), "max": 0.55, "color": ORANGE if enemy.elite else CYAN, "size": rng.randf_range(2.0, 5.0), "texture": EXPLOSION_LARGE if enemy.elite else EXPLOSION_SMALL})
	if rng.randf() < (0.32 if enemy.elite else 0.18):
		var salvage_art := Sprite2D.new()
		salvage_art.texture = SALVAGE_ART
		salvage_art.scale = Vector2(0.018, 0.018)
		salvage_art.z_index = 3
		add_child(salvage_art)
		pickups.append({"pos": enemy.pos, "vel": Vector2(0, 60), "kind": "salvage", "value": 8 if enemy.elite else 3, "spin": rng.randf_range(0.0, TAU), "art": salvage_art})
	if enemy.has("art"):
		enemy.art.queue_free()
	if hit_sfx:
		hit_sfx.pitch_scale = rng.randf_range(0.88, 1.12)
		hit_sfx.play()
	enemies.remove_at(index)

func _update_pickups(dt: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var pickup: Dictionary = pickups[i]
		pickup.spin += dt * 4.0
		if magnet_level > 0:
			var distance: float = pickup.pos.distance_to(player_pos)
			if distance < 220.0 + magnet_level * 40.0:
				pickup.vel = pickup.vel.lerp((player_pos - pickup.pos).normalized() * (160.0 + magnet_level * 70.0), dt * 4.0)
		pickup.pos += pickup.vel * dt
		if pickup.has("art"):
			pickup.art.position = pickup.pos
			pickup.art.rotation = pickup.spin
			if pickup.pos.distance_to(player_pos) < 34.0:
				salvage += int(pickup.value)
				energy = minf(max_energy, energy + 6.0)
				particles.append({"pos": player_pos, "vel": Vector2.ZERO, "life": 0.32, "max": 0.32, "color": MINT, "size": 5.0})
				if pickup.has("art"):
					pickup.art.queue_free()
				pickups.remove_at(i)
		elif pickup.pos.y > H + 50.0:
			if pickup.has("art"):
				pickup.art.queue_free()
			pickups.remove_at(i)
		else:
			pickups[i] = pickup

func _update_drone(dt: float) -> void:
	if drone_count <= 0:
		return
	drone_timer -= dt
	if drone_timer <= 0.0:
		drone_timer = 0.85
		for i in range(drone_count):
			var angle := bg_scroll * 2.0 + float(i) * TAU / float(max(1, drone_count))
			var drone_pos := player_pos + Vector2.from_angle(angle) * (56.0 + i * 7.0)
			bullets.append({"pos": drone_pos, "vel": Vector2(0, -760), "radius": 4.0, "damage": 1.0, "pierce": 0, "color": MINT})

func _update_boss(dt: float) -> void:
	if boss == null:
		return
	boss_elapsed += dt
	boss.pos.x = W * 0.5 + sin(boss_elapsed * 0.8) * 180.0
	boss_attack_timer -= dt
	if boss_attack_timer <= 0.0:
		boss_attack_timer = maxf(0.72, 1.65 - sector * 0.18)
		boss_pattern = (boss_pattern + 1) % 3
		_spawn_boss_pattern()

func _spawn_boss_pattern() -> void:
	if boss == null:
		return
	var count := 5 + sector
	for i in range(count):
		var ratio := float(i) / float(max(1, count - 1))
		var angle := PI * 0.30 + ratio * PI * 0.40
		if boss_pattern == 1:
			angle = PI * 0.5 + sin(float(i)) * 0.28
		if boss_pattern == 2:
			angle = PI * 0.5 + (float(i) - float(count - 1) * 0.5) * 0.11
			enemy_bullets.append({"pos": boss.pos + Vector2(0, 72), "vel": Vector2(cos(angle), sin(angle)) * (250.0 + sector * 28.0), "radius": 9.0, "damage": 20.0, "color": ORANGE if boss_pattern == 2 else MAGENTA})
	for k in range(8):
		var p: Vector2 = boss.pos + Vector2.from_angle(float(k) * TAU / 8.0) * 94.0
		particles.append({"pos": p, "vel": Vector2.ZERO, "life": 0.28, "max": 0.28, "color": MAGENTA, "size": 4.0})

func _begin_boss() -> void:
	phase = Phase.BOSS
	boss_elapsed = 0.0
	boss_attack_timer = 1.0
	boss_pattern = 0
	var hp := 300.0 + sector * 170.0
	boss = {"pos": Vector2(W * 0.5, 210.0), "hp": hp, "max_hp": hp, "radius": 106.0, "name": ["THE GRAVITY WARDEN", "THE ORBITAL HYDRA", "THE SUNKEN CORE"][sector - 1]}
	message = "ELITE CORE  //  %s" % boss.name
	message_timer = 3.0

func _boss_defeated() -> void:
	if boss == null:
		return
	_kick_shake(16.0)
	for k in range(34):
		var angle := rng.randf_range(0.0, TAU)
		particles.append({"pos": boss.pos, "vel": Vector2.from_angle(angle) * rng.randf_range(50.0, 260.0), "life": rng.randf_range(0.45, 1.1), "max": 1.1, "color": ORANGE if k % 2 == 0 else MAGENTA, "size": rng.randf_range(3.0, 9.0), "texture": EXPLOSION_LARGE})
	score += 500 * sector
	salvage += 30
	boss = null
	if explosion_sfx:
		explosion_sfx.pitch_scale = 0.84 + sector * 0.07
		explosion_sfx.play()
	if sector >= SECTOR_COUNT:
		phase = Phase.VICTORY
		_save_score()
	else:
		_begin_upgrade(true)

func _begin_upgrade(from_boss: bool) -> void:
	phase = Phase.UPGRADE
	upgrade_after_boss = from_boss
	selected_card = -1
	card_rects.clear()
	var pool := [
		{"id": "spread", "label": "TRI-BEAM", "desc": "Add a side shot.", "color": CYAN, "icon": UPGRADE_TRI_BEAM},
		{"id": "pierce", "label": "PHASE ROUNDS", "desc": "Bolts pierce +1.", "color": VIOLET},
		{"id": "drone", "label": "ORBITAL DRONE", "desc": "An ally fires with you.", "color": MINT},
		{"id": "magnet", "label": "SALVAGE MAGNET", "desc": "Pull salvage from farther.", "color": ORANGE},
		{"id": "shield", "label": "HULL PLATING", "desc": "+25 max shield.", "color": Color(0.52, 0.78, 1.0), "icon": UPGRADE_HULL},
		{"id": "afterburner", "label": "AFTERBURNER", "desc": "Move faster.", "color": MAGENTA, "icon": UPGRADE_AFTERBURNER},
		{"id": "critical", "label": "CRIT MATRIX", "desc": "+8% critical hits.", "color": Color(1.0, 0.82, 0.38)},
		{"id": "overclock", "label": "OVER-CLOCK", "desc": "Fire faster.", "color": Color(0.70, 0.48, 1.0)}
	]
	pool.shuffle()
	upgrade_options = pool.slice(0, 3)
	for i in range(3):
		card_rects.append(Rect2(28.0 + float(i) * 224.0, 545.0, 208.0, 272.0))
	message = "CHOOSE YOUR NEXT MODULE"
	message_timer = 99.0

func _apply_upgrade(option: Dictionary) -> void:
	match String(option.id):
		"spread":
			spread_level += 1
		"pierce":
			pierce += 1
		"drone":
			drone_count += 1
		"magnet":
			magnet_level += 1
		"shield":
			max_shield += 25.0
			shield = max_shield
		"afterburner":
			player_speed += 70.0
		"critical":
			critical_chance = minf(0.45, critical_chance + 0.08)
		"overclock":
			fire_interval = maxf(0.12, fire_interval - 0.04)
	message = "%s INSTALLED" % option.label
	message_timer = 1.7
	if upgrade_after_boss:
		phase = Phase.TRANSITION
		transition_timer = 1.7
		upgrade_after_boss = false
	elif wave >= WAVES_PER_SECTOR:
		_begin_boss()
	else:
		wave += 1
		_start_wave()

func _damage_player(amount: float) -> void:
	if invulnerable > 0.0 or phase not in [Phase.PLAYING, Phase.BOSS]:
		return
	invulnerable = 1.0
	flash = 0.18
	_kick_shake(10.0)
	if shield > 0.0:
		shield = maxf(0.0, shield - amount)
		message = "SHIELD HIT  //  %03d" % roundi(shield)
		message_timer = 0.9
	else:
		player_hp -= 1
		shield = max_shield * 0.35
		combo = 0
		if player_hp <= 0:
			phase = Phase.DEFEAT
			_save_score()
	if explosion_sfx:
		explosion_sfx.pitch_scale = 1.18
		explosion_sfx.play()

func _spawn_hit(pos: Vector2, color: Color) -> void:
	_kick_shake(2.8 if color == ORANGE else 1.4)
	for i in range(3):
		particles.append({"pos": pos, "vel": Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(18.0, 65.0), "life": 0.18 + i * 0.04, "max": 0.3, "color": color, "size": 2.0 + i, "texture": EXPLOSION_SMALL})
	for i in range(5):
		particles.append({"pos": pos, "vel": Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(70.0, 155.0), "life": rng.randf_range(0.16, 0.30), "max": 0.30, "color": color, "size": rng.randf_range(2.0, 4.5)})

func _kick_shake(amount: float) -> void:
	screen_shake = minf(18.0, screen_shake + amount)

func _screen_shake_step(dt: float) -> void:
	if screen_shake > 0.0:
		screen_shake = move_toward(screen_shake, 0.0, dt * 42.0)
		position = Vector2(rng.randf_range(-screen_shake, screen_shake), rng.randf_range(-screen_shake, screen_shake) * 0.65)
	else:
		position = Vector2.ZERO

func _update_particles(dt: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= dt
		p.pos += p.vel * dt
		p.vel = p.vel * (1.0 - minf(0.86 * dt, 0.5))
		if p.life <= 0.0:
			particles.remove_at(i)
		else:
			particles[i] = p

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause()
			return
		if event.keycode == KEY_R and phase in [Phase.VICTORY, Phase.DEFEAT]:
			_restart_run()
			return
			if event.keycode == KEY_M and phase in [Phase.VICTORY, Phase.DEFEAT, Phase.PAUSED]:
				get_tree().change_scene_to_file("res://title_screen.tscn")
				return
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_press(event.position, event.index)
		else:
			if event.index == touch_id:
				touch_id = -1
				touch_active = false
		return
	if event is InputEventScreenDrag:
		if event.index == touch_id:
			touch_position = event.position
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_press(event.position, 0)
		else:
			touch_active = false
			touch_id = -1
		return
	if event is InputEventMouseMotion and touch_active:
		touch_position = event.position

func _handle_press(pos: Vector2, id: int) -> void:
	if pos.x < 0.0 or pos.x > W or pos.y < 0.0 or pos.y > H:
		return
		if phase == Phase.PAUSED:
			if Rect2(86, 530, 548, 78).has_point(pos):
				_toggle_pause()
			elif Rect2(86, 632, 548, 78).has_point(pos):
				get_tree().change_scene_to_file("res://title_screen.tscn")
			return
	if phase == Phase.UPGRADE:
		for i in range(card_rects.size()):
			if card_rects[i].has_point(pos):
				_apply_upgrade(upgrade_options[i])
				return
		return
	if phase in [Phase.VICTORY, Phase.DEFEAT]:
		_restart_run()
		return
	if pause_rect.has_point(pos):
		_toggle_pause()
		return
	if pos.y > H * 0.48:
		touch_id = id
		touch_active = true
		touch_position = pos

func _toggle_pause() -> void:
	if phase == Phase.PAUSED:
		phase = previous_phase
	else:
		previous_phase = phase
		phase = Phase.PAUSED

func _restart_run() -> void:
	get_tree().reload_current_scene()

func _sync_audio_pause() -> void:
	if bgm_player == null:
		return
	var should_pause := phase == Phase.PAUSED
	if should_pause == audio_paused:
		return
	audio_paused = should_pause
	audio_pause_writes += 1
	bgm_player.stream_paused = audio_paused

func _save_score() -> void:
	if score <= best_score:
		return
	best_score = score
	var config := ConfigFile.new()
	config.set_value("progress", "best_score", best_score)
	config.save("user://starfall_save.cfg")

func _load_score() -> void:
	var config := ConfigFile.new()
	if config.load("user://starfall_save.cfg") == OK:
		best_score = int(config.get_value("progress", "best_score", 0))

func _draw() -> void:
	# Preserve the texture layers behind a crisp, hand-drawn foreground.
	draw_rect(Rect2(0, 0, W, H), Color(0.012, 0.008, 0.04, 0.42))
	for cloud in nebula_clouds:
		var cloud_alpha := 0.028 + float(cloud.layer) * 0.032
		var pulse := 1.0 + sin(bg_scroll * 0.45 + cloud.phase) * 0.08
		var cloud_pos: Vector2 = cloud.pos
		var cloud_size: float = cloud.size * pulse
		draw_circle(cloud_pos, cloud_size, Color(cloud.color, cloud_alpha))
		draw_circle(cloud_pos + Vector2(18.0, 12.0), cloud_size * 0.62, Color(cloud.color.lightened(0.14), cloud_alpha * 0.64))
		draw_circle(cloud_pos + Vector2(-22.0, -9.0), cloud_size * 0.42, Color(cloud.color.darkened(0.12), cloud_alpha * 0.50))
	for s in stars:
		var alpha := float(s.layer) * 0.55 + 0.12
		draw_circle(s.pos, float(s.size), Color(0.62, 0.86, 1.0, alpha))
		if s.layer > 0.78:
			draw_line(s.pos, s.pos + Vector2(0, 10 + float(s.size) * 7.0), Color(CYAN, alpha * 0.20), 1.0)
	# Sector accent stripe and mobile playfield rails.
	var accent: Color = [CYAN, MAGENTA, ORANGE][sector - 1]
	draw_rect(Rect2(0, 0, W, 8), Color(accent, 0.76))
	draw_line(Vector2(26, 120), Vector2(26, H - 120), Color(CYAN, 0.12), 1.0)
	draw_line(Vector2(W - 26, 120), Vector2(W - 26, H - 120), Color(CYAN, 0.12), 1.0)
	for bullet in bullets:
		_draw_projectile(bullet)
	for bullet in enemy_bullets:
		_draw_projectile(bullet)
	for enemy in enemies:
		_draw_asteroid(enemy)
	for pickup in pickups:
		_draw_pickup(pickup)
	if boss != null:
		_draw_boss()
	_draw_player()
	for p in particles:
		var alpha := clampf(float(p.life) / float(p.max), 0.0, 1.0)
		if p.has("texture"):
			_draw_effect(p)
		else:
			draw_circle(p.pos, float(p.size) * (0.6 + alpha), Color(p.color, alpha * 0.7))
	_draw_hud()
	if phase == Phase.INTRO:
		_draw_intro()
	elif phase == Phase.UPGRADE:
		_draw_upgrade()
	elif phase == Phase.TRANSITION:
		_draw_transition()
	elif phase == Phase.PAUSED:
		_draw_pause()
	elif phase == Phase.VICTORY or phase == Phase.DEFEAT:
		_draw_result()
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1.0, 0.18, 0.25, flash * 0.32))

func _draw_projectile(bullet: Dictionary) -> void:
	var direction: Vector2 = bullet.vel.normalized()
	var texture: Texture2D = bullet.texture
	var tint := Color(bullet.color, 0.96)
	if texture:
		draw_set_transform(bullet.pos, direction.angle() + PI * 0.5, Vector2(0.07, 0.07))
		draw_texture_rect(texture, Rect2(-18, -34, 36, 68), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_line(bullet.pos - direction * 18.0, bullet.pos, Color(bullet.color, 0.35), 4.0)
		draw_circle(bullet.pos, float(bullet.radius), tint)

func _draw_effect(p: Dictionary) -> void:
	var alpha := clampf(float(p.life) / float(p.max), 0.0, 1.0)
	var texture: Texture2D = p.texture
	var scale := 0.12 + (1.0 - alpha) * 0.10
	if texture:
		draw_set_transform(p.pos, bg_scroll * 0.5, Vector2(scale, scale))
		draw_texture_rect(texture, Rect2(-30, -30, 60, 60), false, Color(p.color, alpha * 0.92))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
func _draw_asteroid(enemy: Dictionary) -> void:
	var center: Vector2 = enemy.pos
	var radius: float = enemy.radius
	if enemy.has("art"):
		draw_arc(center, radius + 12.0 + sin(bg_scroll * 5.0) * 3.0, 0.2, 2.2, 16, Color(MAGENTA, 0.8), 2.0)
		return
	var sides := 8 if enemy.elite else 7
	var points := PackedVector2Array()
	for i in range(sides):
		var angle: float = enemy.rot + TAU * float(i) / float(sides)
		var wobble := 0.82 + 0.16 * sin(float(i) * 2.4 + float(enemy.phase))
		points.append(center + Vector2.from_angle(angle) * radius * wobble)
	var fill := Color(enemy.color, 0.88)
	draw_colored_polygon(points, fill)
	var outline := MAGENTA if enemy.elite else Color(0.55, 0.82, 1.0)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, Color(outline, 0.96), 2.0)
	if enemy.elite:
		draw_arc(center, radius + 9.0 + sin(bg_scroll * 5.0) * 3.0, 0.2, 2.2, 16, Color(MAGENTA, 0.8), 2.0)
		draw_line(center + Vector2(-radius * 0.6, 0), center + Vector2(radius * 0.6, 0), Color(1.0, 0.82, 0.94, 0.65), 2.0)
	else:
		draw_line(center + Vector2(-radius * 0.4, -radius * 0.18), center + Vector2(radius * 0.2, radius * 0.3), Color(0.12, 0.25, 0.38, 0.75), 2.0)

func _draw_pickup(pickup: Dictionary) -> void:
	var p: Vector2 = pickup.pos
	var spin: float = pickup.spin
	for r in range(3, 0, -1):
		draw_circle(p, 11.0 + r * 5.0, Color(MINT, 0.035 * r))
	if pickup.has("art"):
		return
	var diamond := PackedVector2Array([p + Vector2.from_angle(spin) * 13.0, p + Vector2.from_angle(spin + PI * 0.5) * 13.0, p + Vector2.from_angle(spin + PI) * 13.0, p + Vector2.from_angle(spin + PI * 1.5) * 13.0])
	draw_colored_polygon(diamond, Color(MINT, 0.95))
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color(0.85, 1.0, 0.96), 2.0)

func _draw_boss() -> void:
	var center: Vector2 = boss.pos
	var hp_ratio := clampf(float(boss.hp) / float(boss.max_hp), 0.0, 1.0)
	for r in range(4, 0, -1):
		draw_circle(center, 120.0 + r * 18.0, Color(MAGENTA, 0.012 * r))
	draw_arc(center, 138.0, -bg_scroll * 0.3, -bg_scroll * 0.3 + PI * 1.3, 24, Color(MAGENTA, 0.65), 4.0)
	draw_arc(center, 126.0, bg_scroll * 0.5, bg_scroll * 0.5 + PI * 1.2, 20, Color(ORANGE, 0.55), 3.0)
	for i in range(6):
		var a := bg_scroll * 0.38 + float(i) * TAU / 6.0
		var p1 := center + Vector2.from_angle(a) * 58.0
		var p2 := center + Vector2.from_angle(a) * 112.0
		draw_line(p1, p2, Color(CYAN, 0.68), 4.0)
	if not boss_sprite or not boss_sprite.visible:
		draw_circle(center, 62.0, Color(0.16, 0.08, 0.26, 0.96))
		draw_circle(center, 38.0, Color(MAGENTA, 0.76))
		draw_circle(center, 15.0, Color(1.0, 0.82, 0.46))
	draw_rect(Rect2(58, 330, W - 116, 16), Color(0.04, 0.02, 0.09, 0.9))
	draw_rect(Rect2(58, 330, (W - 116) * hp_ratio, 16), Color(MAGENTA, 0.92))
	_text("BOSS // %s" % boss.name, Vector2(58, 318), 15, Color(1.0, 0.78, 0.92), BOLD_FONT)
	_text("CORE %03d%%" % roundi(hp_ratio * 100.0), Vector2(W - 176, 318), 13, Color(1.0, 0.78, 0.92), UI_FONT)

func _draw_player() -> void:
	var alpha := 0.35 if invulnerable > 0.0 and int(invulnerable * 14.0) % 2 == 0 else 1.0
	var c := Color(CYAN, alpha)
	if shield > 0.0:
		draw_arc(player_pos, 34.0 + sin(bg_scroll * 5.0) * 2.0, -PI * 0.8, PI * 0.8, 24, Color(CYAN, alpha * 0.55), 3.0)
	var flame := PackedVector2Array([player_pos + Vector2(-12, 27), player_pos + Vector2(0, 56 + sin(bg_scroll * 16.0) * 7.0), player_pos + Vector2(12, 27)])
	draw_colored_polygon(flame, Color(ORANGE, alpha * 0.9))
	if not player_sprite or not player_sprite.visible:
		var hull := PackedVector2Array([player_pos + Vector2(0, -40), player_pos + Vector2(28, 18), player_pos + Vector2(16, 30), player_pos + Vector2(0, 25), player_pos + Vector2(-16, 30), player_pos + Vector2(-28, 18)])
		draw_colored_polygon(hull, Color(0.12, 0.32, 0.53, alpha))
		draw_polyline(PackedVector2Array([hull[0], hull[1], hull[2], hull[3], hull[4], hull[5], hull[0]]), c, 2.5)
		draw_colored_polygon(PackedVector2Array([player_pos + Vector2(-7, 7), player_pos + Vector2(-46, 30), player_pos + Vector2(-20, 0)]), Color(0.16, 0.65, 0.78, alpha))
		draw_colored_polygon(PackedVector2Array([player_pos + Vector2(7, 7), player_pos + Vector2(46, 30), player_pos + Vector2(20, 0)]), Color(0.16, 0.65, 0.78, alpha))
		draw_circle(player_pos + Vector2(0, -8), 8.0, Color(1.0, 0.87, 0.45, alpha))
		draw_circle(player_pos + Vector2(0, -8), 3.0, Color(1, 1, 1, alpha))
	for i in range(drone_count):
		var a := bg_scroll * 2.0 + float(i) * TAU / float(max(1, drone_count))
		var d := player_pos + Vector2.from_angle(a) * (56.0 + i * 7.0)
		draw_circle(d, 9.0, Color(MINT, 0.18))
		draw_circle(d, 5.0, Color(MINT, 0.94))
		draw_line(d, player_pos + Vector2.from_angle(a) * 38.0, Color(MINT, 0.3), 1.0)

func _draw_hud() -> void:
	draw_rect(Rect2(0, 0, W, 112), Color(0.015, 0.01, 0.06, 0.9))
	draw_line(Vector2(24, 112), Vector2(W - 24, 112), Color(CYAN, 0.26), 1.0)
	_text("STARFALL // SALVAGE", Vector2(28, 34), 14, Color(CYAN, 0.82), BOLD_FONT)
	_text("%06d" % score, Vector2(28, 72), 30, Color(0.95, 0.98, 1.0), TITLE_FONT)
	_text("SCORE", Vector2(30, 94), 11, Color(0.58, 0.66, 0.82), BOLD_FONT)
	_text("SALVAGE %04d" % salvage, Vector2(246, 42), 14, Color(MINT, 0.92), BOLD_FONT)
	_text("COMBO x%d" % combo, Vector2(246, 76), 15, Color(1.0, 0.78, 0.42), BOLD_FONT)
	_text("SECTOR %02d / %02d" % [sector, SECTOR_COUNT], Vector2(462, 42), 13, Color(0.74, 0.78, 0.96), BOLD_FONT)
	_text("WAVE %02d / %02d" % [wave, WAVES_PER_SECTOR], Vector2(462, 70), 12, Color(0.56, 0.64, 0.84), UI_FONT)
	draw_rect(pause_rect, Color(0.06, 0.14, 0.22, 0.9))
	draw_rect(Rect2(pause_rect.position, Vector2(3, pause_rect.size.y)), CYAN)
	_text("PAUSE", pause_rect.position + Vector2(17, 29), 13, Color(0.88, 0.96, 1.0), BOLD_FONT)
	# Resource bars.
	_text("HULL", Vector2(30, 1215), 12, Color(0.68, 0.75, 0.90), BOLD_FONT)
	draw_rect(Rect2(88, 1203, 180, 14), Color(0.05, 0.08, 0.16, 0.9))
	draw_rect(Rect2(88, 1203, 180.0 * float(player_hp) / float(max_player_hp), 14), Color(ORANGE, 0.92))
	_text("SHIELD", Vector2(292, 1215), 12, Color(CYAN, 0.82), BOLD_FONT)
	draw_rect(Rect2(360, 1203, 150, 14), Color(0.05, 0.08, 0.16, 0.9))
	draw_rect(Rect2(360, 1203, 150.0 * shield / max_shield, 14), Color(CYAN, 0.84))
	_text("ENERGY", Vector2(532, 1215), 12, Color(MINT, 0.82), BOLD_FONT)
	draw_rect(Rect2(596, 1203, 92, 14), Color(0.05, 0.08, 0.16, 0.9))
	draw_rect(Rect2(596, 1203, 92.0 * energy / max_energy, 14), Color(MINT, 0.84))
	_text("DRAG TO STEER  //  AUTO-FIRE", Vector2(28, 1250), 13, Color(0.55, 0.66, 0.84), UI_FONT)
	if message_timer > 0.0 and not message.is_empty():
		_text(message, Vector2(0, 164), 18, Color(1.0, 0.86, 0.56), BOLD_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)

func _draw_intro() -> void:
	var panel := Rect2(44, 450, W - 88, 284)
	draw_rect(panel, Color(0.025, 0.02, 0.09, 0.94))
	draw_rect(Rect2(panel.position, Vector2(5, panel.size.y)), CYAN)
	_text("SECTOR %02d // DEBRIS BELT" % sector, Vector2(76, 518), 30, Color(0.94, 0.98, 1.0), TITLE_FONT)
	_text("YOUR SHIP IS SMALL. YOUR BUILD IS NOT.", Vector2(78, 568), 15, Color(MINT, 0.9), BOLD_FONT)
	_text("Drag in the lower half to steer.", Vector2(78, 624), 17, Color(0.78, 0.82, 0.94), UI_FONT)
	_text("Destroy the falling rocks, collect salvage,", Vector2(78, 654), 17, Color(0.78, 0.82, 0.94), UI_FONT)
	_text("then pick one module between waves.", Vector2(78, 684), 17, Color(0.78, 0.82, 0.94), UI_FONT)
	_text("TAP TO LAUNCH", Vector2(78, 706), 13, Color(ORANGE, 0.88), BOLD_FONT)

func _draw_upgrade() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.012, 0.008, 0.04, 0.78))
	_text("MODULE BAY", Vector2(0, 318), 46, Color(0.96, 0.99, 1.0), TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("CHOOSE ONE UPGRADE TO SHAPE THIS RUN", Vector2(0, 364), 15, Color(MINT, 0.92), BOLD_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("The next threat is already falling.", Vector2(0, 397), 15, Color(0.64, 0.70, 0.88), UI_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	for i in range(upgrade_options.size()):
		var rect: Rect2 = card_rects[i]
		var option: Dictionary = upgrade_options[i]
		var color: Color = option.color
		draw_rect(rect, Color(0.035, 0.05, 0.12, 0.98))
		draw_rect(Rect2(rect.position, Vector2(5, rect.size.y)), color)
		draw_rect(Rect2(rect.position + Vector2(18, 22), Vector2(58, 58)), Color(color, 0.12))
		draw_circle(rect.position + Vector2(47, 51), 18.0, Color(color, 0.24))
		_text("0%d" % (i + 1), rect.position + Vector2(31, 57), 16, color, BOLD_FONT)
		_text(option.label, rect.position + Vector2(20, 122), 19, Color(0.95, 0.98, 1.0), BOLD_FONT)
		_text(option.desc, rect.position + Vector2(20, 157), 14, Color(0.66, 0.72, 0.88), UI_FONT)
		_text("TAP TO INSTALL", rect.position + Vector2(20, 236), 12, Color(color, 0.88), BOLD_FONT)
	_text("WAVE CLEAR // SALVAGE SECURED", Vector2(0, 864), 14, Color(ORANGE, 0.9), BOLD_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("Touch a card or press 1 / 2 / 3", Vector2(0, 900), 14, Color(0.62, 0.68, 0.84), UI_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)

func _draw_transition() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.012, 0.008, 0.04, 0.74))
	_text("SECTOR BREAK", Vector2(0, 520), 52, Color(0.96, 0.99, 1.0), TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("NEW ORBITAL RULES DETECTED", Vector2(0, 578), 16, Color(ORANGE, 0.92), BOLD_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("Get ready for faster patterns and heavier cores.", Vector2(0, 632), 16, Color(0.70, 0.74, 0.90), UI_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)

func _draw_pause() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.012, 0.008, 0.04, 0.82))
	_text("FLIGHT PAUSED", Vector2(0, 430), 52, Color(0.96, 0.99, 1.0), TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("Your run is safe. Your next card is not.", Vector2(0, 494), 17, Color(MINT, 0.9), UI_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	var resume := Rect2(86, 530, 548, 78)
	var menu := Rect2(86, 632, 548, 78)
	draw_rect(resume, Color(0.08, 0.21, 0.28, 0.96))
	draw_rect(menu, Color(0.05, 0.08, 0.16, 0.96))
	_text("RESUME RUN", resume.position + Vector2(28, 48), 22, Color(0.92, 1.0, 1.0), BOLD_FONT)
	_text("MAIN MENU", menu.position + Vector2(28, 48), 22, Color(0.82, 0.86, 0.96), BOLD_FONT)
	_text("ESC / TAP PAUSE TO RESUME", Vector2(0, 790), 14, Color(0.58, 0.68, 0.86), UI_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)

func _draw_result() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.012, 0.008, 0.04, 0.82))
	var victory := phase == Phase.VICTORY
	var accent := MINT if victory else MAGENTA
	_text("RUN COMPLETE" if victory else "SIGNAL LOST", Vector2(0, 392), 54, Color(0.96, 0.99, 1.0), TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("ALL SECTORS CLEARED" if victory else "THE DEBRIS BELT WINS THIS ROUND", Vector2(0, 450), 16, Color(accent, 0.95), BOLD_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	draw_rect(Rect2(72, 512, W - 144, 250), Color(0.035, 0.05, 0.12, 0.98))
	draw_rect(Rect2(72, 512, 5, 250), accent)
	_text("FINAL SCORE", Vector2(104, 566), 14, Color(0.60, 0.68, 0.84), BOLD_FONT)
	_text("%06d" % score, Vector2(104, 626), 48, Color(1.0, 0.83, 0.45), TITLE_FONT)
	_text("SALVAGE %04d   //   SECTOR %02d" % [salvage, sector], Vector2(106, 676), 16, Color(MINT, 0.9), BOLD_FONT)
	_text("BUILD: %d lanes  /  %d drones  /  %d pierce" % [1 + spread_level, drone_count, pierce], Vector2(106, 716), 14, Color(0.68, 0.74, 0.9), UI_FONT)
	_text("TAP TO FLY AGAIN", Vector2(0, 850), 21, Color(accent, 0.96), BOLD_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text("R = RETRY   //   M = MAIN MENU", Vector2(0, 884), 14, Color(0.62, 0.68, 0.84), UI_FONT, HORIZONTAL_ALIGNMENT_CENTER, W)

func _text(value: String, pos: Vector2, size: int, color: Color, font: Font = UI_FONT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var resolved_font: Font = font if font != null else ThemeDB.fallback_font
	draw_string(resolved_font, pos, value, align, width, size, color)




