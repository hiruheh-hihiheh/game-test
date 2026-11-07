extends Node2D
## One flight: a campaign level, a side mission, an Expedition node, a challenge or Endless.
## This file owns the flow, the player and the enemies. Bosses, hazards, effects and the
## HUD live in src/combat so each stays small enough to reason about.

const SHOT_CYAN := preload("res://assets/starfall/projectiles/projectile_player_cyan.png")
const LASER_ART := preload("res://assets/starfall/projectiles/projectile_laser_magenta.png")
const DRONE_ART := preload("res://assets/starfall/ships/player_interceptor_02.png")
const SALVAGE_ART := preload("res://assets/starfall/environment/salvage_crystal_blue.png")
const SHIELD_ART := preload("res://assets/starfall/effects/effect_shield_orb.png")
const HUE_SHADER := preload("res://src/hue.gdshader")
const BOSS_SCRIPTS := [
	preload("res://src/combat/bosses/gravity_warden.gd"),
	preload("res://src/combat/bosses/ember_tyrant.gd"),
	preload("res://src/combat/bosses/orbital_hydra.gd"),
	preload("res://src/combat/bosses/pale_regent.gd"),
	preload("res://src/combat/bosses/crimson_admiral.gd"),
	preload("res://src/combat/bosses/sunken_core.gd"),
]

enum Phase { INTRO, PLAYING, WARNING, BOSS_INTRO, BOSS, UPGRADE, CLEAR, DEFEAT, PAUSED, RESUME }

const COMBAT_PHASES := [Phase.PLAYING, Phase.BOSS, Phase.WARNING]
const FLOOR_MARGIN := 200.0

var phase: Phase = Phase.INTRO
var previous_phase: Phase = Phase.PLAYING
var W := 720.0
var H := 1280.0
var inset := Vector2.ZERO
var top := 16.0
var t := 0.0
var phase_t := 0.0
var flight_time := 0.0

# Session
var mode := "campaign"
var mutators: Array = []
## Danger Contracts chosen for this run, and what they do. See src/data/danger.gd.
var danger: Array = []
var danger_rewards: Dictionary = {}
var danger_paid: Dictionary = {}
var danger_pace := 1.0
var danger_hull := 0
var danger_regen := 1.0
var danger_cards_minus := 0
var danger_no_reroll := false
var nova_sealed := false
var score_mult := 1.0
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
var storm_t := 0.0
var storm_timer := 0.0
var boss_done := false
var bullet_mult := 1.0
var hp_mult := 1.0
var fire_mult_enemy := 1.0
var count_mult := 1.0
var elite_chance := 0.0
var finish_slowed := false
var tier := 0
var tier_cfg: Dictionary = {}
var base_mutators: Array = []
var loot: Array = []
var bonus_parts := 0
var bonus_xp := 0
var rift_floors := 0
var result_parts := 0
var result_pilot_xp := 0
var pilot_before: Dictionary = {}
var pilot_after: Dictionary = {}
var loot_rng := RandomNumberGenerator.new()

# Player
var ship_id := "nova"
var ship: Dictionary = {}
var weapon: Dictionary = {}
var player_pos := Vector2(360, 1500)
var player_target := Vector2(360, 1040)
var player_alive := true
var hull := 3
var max_hull := 3
var shield := 60.0
var max_shield := 60.0
var energy := 0.0
var held := {}
var s := {}
var fire_timer := 0.3
var drone_timer := 0.0
var seeker_timer := 1.0
var invuln := 0.0
var shield_idle := 0.0
var shield_flash := 0.0
var hull_lost := 0
var engine_fx := EngineFx.new()
var bank_angle := 0.0
var beam_focus := 0.0
var beam_tick := 0.0
var beam_top := 0.0
var beam_active := false
var slip_t := 0.0
var surge_t := 0.0
var crystal_count := 0
var midas_stacks := 0
var overdrive_t := 0.0
var aegis_t := 0.0
var echo_t := -1.0
var phoenix_used := false
var emergency_used := false
var rerolls := 0
var drag_finger := -1
var last_tap := -10.0
var touch_moved := 0.0

# World
var shots: Array = []
var enemies: Array = []
var pickups: Array = []
var timers: Array = []
var boss = null
var fallen_bosses: Array = []
var field := BulletField.new()
var fx := Fx.new()
var shield_fx := ShieldFx.new(fx)
var hazards: Hazards
var hud: Hud
var stars_bg: Array = []
var bg_scroll := 0.0
var bg_tex: Texture2D
var warp := 0.0
var sprite_pool: Array[Sprite2D] = []

# Feel
var hitstop := 0.0
var time_scale := 1.0
var shake := 0.0
var flash := 0.0
var flash_color := Color.WHITE

# Score and objectives
var score := 0
var shown_score := 0.0
var run_salvage := 0
var banked := false
var combo := 0
var combo_timer := 0.0
var best_combo := 0
var kills := 0
var tracker := {"crystals": 0, "wrecks": 0, "ember": 0.0, "tanks": 0, "hatched": 0, "husks": 0, "shield_broke": false, "escort_ok": true, "escort_seen": false}
var threat := 0.0

# Overlays
var card_options: Array = []
var card_picked := -1
var result_win := false
var result_mask := 0
var result_reward := 0
var result_xp := 0
var stars_shown := 0
var input_lock := 0.0
var new_best := false
var rewards: Array = []
var resume_t := 0.0

# Layers
var world: Node2D
var bg_layer: DrawLayer
var ground_layer: DrawLayer
var enemy_root: Node2D
var fx_add: DrawLayer
var fx_top: DrawLayer
var player_sprite: Sprite2D
var shield_sprite: Sprite2D
var drone_sprites: Array = []
var shot_batch: SpriteBatch
var shot_glow: SpriteBatch
var missile_batch: SpriteBatch
var pickup_batch: SpriteBatch
var pickup_glow: SpriteBatch
var bullet_batches: Array = []
var bullet_glow: SpriteBatch
var bullet_core: SpriteBatch
var spark_batch: SpriteBatch
var ring_thin_batch: SpriteBatch
var ring_thick_batch: SpriteBatch
var debris_batch: SpriteBatch
var ui: UILayer
var materials := {}
var add_mat: CanvasItemMaterial

func _exit_tree() -> void:
	Cloud.hold(false)

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	Cloud.hold(true)  # cloud sync waits while a flight is on
	_measure()
	UIArt.focus(["loot"])
	var sess: Dictionary = Save.session
	mode = str(sess.get("mode", "campaign"))
	level_num = int(sess.get("level", 1))
	base_mutators = (sess.get("mutators", []) as Array).duplicate()
	danger = Danger.sanitize(sess.get("danger", []), {"mode": mode, "dials": base_mutators, "picks": -1})
	tier = int(sess.get("tier", 0)) if mode == "campaign" else 0
	tier_cfg = Tiers.cfg(tier)
	_load_level()
	_apply_mutators()
	ship_id = Save.ship if Save.ship in Ships.LIST else "nova"
	ship = Ships.LIST[ship_id]
	weapon = Ships.WEAPONS[str(ship.weapon)]
	_load_build()
	rerolls = Save.upgrade_level("reroll") + mini(Save.reroll_tokens, 1)
	if danger_no_reroll:
		rerolls = 0
	_recompute()
	hull = max_hull
	shield = max_shield
	energy = clampf(float(s.nova_start), 0.0, 90.0)
	if mode == "expedition":
		hull = clampi(int(Save.expedition.get("hull", max_hull)), 1, max_hull)
	hazards = Hazards.new(self)
	hud = Hud.new(self)
	loot_rng.randomize()
	pilot_before = Pilot.level_of(Save.pilot_xp)
	pilot_after = pilot_before
	_build_scene()
	player_target = Vector2(W * 0.5, H - 300.0)
	player_pos = Vector2(W * 0.5, H + 140.0)
	warp = 1.0
	var sector_info: Dictionary = Levels.SECTORS[int(level.sector) - 1]
	Audio.music_layered(str(sector_info.music))
	Audio.play("whoosh", 0.0, 0.8)
	var title := "LEVEL %d" % level_num
	match mode:
		"endless":
			title = "RIFT"
		"expedition":
			title = "EXPEDITION"
		"daily":
			title = "DAILY ANOMALY"
		"weekly":
			title = "WEEKLY BOSS"
		"side":
			title = "BLACK BOX"
	var banner_sub: String = str(level.get("name", "")) if mode in ["campaign", "side"] else str(sector_info.name)
	if tier > 0:
		banner_sub += "  ·  " + str(tier_cfg.name)
	hud.banner_show(title, banner_sub, 1.9, sector_info.color)
	if not danger.is_empty():
		hud.coach("DANGER: " + Danger.names(danger), 5.0)
	elif not str(level.get("tip", "")).is_empty():
		hud.coach(str(level.tip), 6.0)
	phase = Phase.INTRO
	phase_t = 0.0
	Telemetry.log_event("flight_start", {"mode": mode, "level": level_num, "ship": ship_id, "mutators": mutators, "danger": danger})

func _load_level() -> void:
	match mode:
		"endless":
			endless_wave = 1
			level = Levels.build_endless(endless_wave)
		"expedition":
			var node: Dictionary = Save.expedition.get("current", {})
			level = Levels.build_node(int(node.get("seed", 1)), int(Save.expedition.get("sector", 1)), int(node.get("tier", 1)), str(node.get("type", "battle")))
		_:
			level = Levels.build(level_num)
	scale_cfg = level.scale

func _load_build() -> void:
	held = {}
	if mode == "expedition":
		held = (Save.expedition.get("cards", {}) as Dictionary).duplicate()
	elif mode in ["campaign", "side", "daily", "weekly"]:
		for id in Save.loadout:
			if Cards.LIST.has(id) and Cards.unlocked(id, Save.blueprints):
				held[id] = 1

func _measure() -> void:
	var v := get_viewport_rect().size
	W = v.x
	H = v.y
	inset = UI.safe_insets(v)
	top = inset.x + 16.0

## Rebuilds every combat number from ship, Hangar, mastery and cards.
func _recompute() -> void:
	s = {
		"lanes": 0.0, "pierce": 0.0, "drones": 0.0, "magnet": 0.0, "crit": 0.05, "dmg_mult": 1.0, "fire_mult": 1.0,
		"shot_speed": 1.0, "nova_gain": 1.0, "shield_add": 0.0, "hull_add": 0.0, "salvage_mult": 1.0, "shield_mult": 1.0,
		"burn": 0.0, "cryo": 0.0, "arc": 0.0, "ricochet": 0.0, "graze": 0.0, "spike": 0.0, "seekers": 0.0, "phoenix": 0.0,
		"echo": 0.0, "redline": 0.0, "midas": 0.0, "prism": 0.0, "hunter": 0.0, "aegis_wing": 0.0, "tesla": 0.0,
		"inferno": 0.0, "zero": 0.0, "nova_refund": 0.0, "bastion": 0.0, "daredevil": 0.0,
		"shield_regen": 0.0, "nova_start": 0.0, "iframes": 0.0,
	}
	Cards.sum_stats(held, s)
	Gear.apply_equipped(ship_id, s)
	var lvl := Save.ship_mastery(ship_id)
	for k in range(2, lvl + 1):
		var reward: Dictionary = Ships.MASTERY[k]
		if str(reward.type) == "stat":
			var key: String = reward.stat
			if key in Cards.MULTIPLY:
				s[key] = float(s[key]) * float(reward.value)
			else:
				s[key] = float(s[key]) + float(reward.value)
	s.dmg_mult = float(s.dmg_mult) * (1.0 + 0.15 * float(Save.upgrade_level("cannon")))
	s.fire_mult = float(s.fire_mult) * pow(0.93, float(Save.upgrade_level("rapid")))
	s.nova_gain = float(s.nova_gain) * float(ship.nova_gain) * (1.0 + 0.2 * float(Save.upgrade_level("core")))
	s.magnet = float(s.magnet) + 130.0 + 45.0 * float(Save.upgrade_level("magnet"))
	s.salvage_mult = float(s.salvage_mult) * (1.0 + 0.2 * float(Save.upgrade_level("salvor")))
	# Permanent account power: pilot level and the endless Overclock Lab.
	s.dmg_mult = float(s.dmg_mult) * Pilot.dmg_bonus() * (1.0 + 0.005 * float(Save.upgrade_level("ov_dmg")))
	s.shield_add = float(s.shield_add) + Pilot.shield_bonus() + float(Save.upgrade_level("ov_shield"))
	s.salvage_mult = float(s.salvage_mult) * (1.0 + 0.005 * float(Save.upgrade_level("ov_salvage")))
	s.crit = minf(0.8, float(s.crit))
	max_hull = maxi(1, int(ship.hull) + Save.upgrade_level("hull") + int(s.hull_add))
	if Mutators.flag(mutators, "hull_cap"):
		max_hull = 1
	max_hull = maxi(1, max_hull + danger_hull)
	max_shield = maxf(10.0, (float(ship.shield) + 20.0 * float(Save.upgrade_level("shield")) + float(s.shield_add)) * float(s.shield_mult))
	hull = mini(hull, max_hull)
	shield = minf(shield, max_shield)

func _build_scene() -> void:
	add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	bg_tex = load("res://assets/backgrounds/sector_%d.png" % int(level.sector))
	var star_count := 100 if int(Save.opt.particles) > 0 else 50
	for i in range(star_count):
		stars_bg.append({"pos": Vector2(randf_range(0.0, W), randf_range(0.0, H)), "depth": randf_range(0.2, 1.0), "twinkle": randf_range(0.0, TAU)})
	bg_layer = _layer(self, _paint_background)
	world = Node2D.new()
	add_child(world)
	ground_layer = _layer(world, hazards.paint_ground, true)
	pickup_glow = _batch(world, UI.glow_tex(), 90, add_mat)
	pickup_batch = _batch(world, SALVAGE_ART, 90)
	enemy_root = Node2D.new()
	world.add_child(enemy_root)
	shot_glow = _batch(world, UI.glow_tex(), 220, add_mat)
	shot_batch = _batch(world, SHOT_CYAN, 220, add_mat)
	missile_batch = _batch(world, LASER_ART, 60, add_mat)
	player_sprite = Sprite2D.new()
	player_sprite.texture = Ships.ART[ship_id]
	engine_fx.set_ship(ship_id)
	player_sprite.scale = Vector2.ONE * (118.0 / 512.0)
	var paint: Dictionary = Ships.PAINTS.get(Save.paint_of(ship_id), Ships.PAINTS.stock)
	if float(paint.hue) != 0.0:
		player_sprite.material = hue_mat(float(paint.hue))
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
	bullet_glow = _batch(world, UI.glow_tex(), BulletField.MAX, add_mat)
	for k in BulletField.KINDS:
		bullet_batches.append(_batch(world, k.tex, BulletField.MAX))
	bullet_core = _batch(world, UI.glow_tex(), BulletField.MAX)
	spark_batch = _batch(world, UI.glow_tex(), Fx.BATCH_CAPACITY, add_mat)
	ring_thin_batch = _batch(world, Fx.ring_tex(false), Fx.MAX_RINGS, add_mat)
	ring_thick_batch = _batch(world, Fx.ring_tex(true), Fx.MAX_RINGS, add_mat)
	fx_add = _layer(world, _paint_fx_add, true)
	debris_batch = _batch(world, Fx.chip_tex(), Fx.MAX_DEBRIS)
	fx_top = _layer(world, _paint_fx_top)
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	ui = UILayer.new()
	ui.painter = hud.paint
	ui.pressed.connect(_on_ui)
	canvas.add_child(ui)

func _layer(parent: Node, painter: Callable, additive := false) -> DrawLayer:
	var layer := DrawLayer.new()
	layer.painter = painter
	if additive:
		layer.material = add_mat
	parent.add_child(layer)
	return layer

func _batch(parent: Node, tex: Texture2D, capacity: int, mat: Material = null) -> SpriteBatch:
	var b := SpriteBatch.new()
	b.setup(tex, capacity, mat)
	parent.add_child(b)
	return b

func hue_mat(hue: float, white := false) -> ShaderMaterial:
	var key := "%.2f|%s" % [hue, str(white)]
	if materials.has(key):
		return materials[key]
	var m := ShaderMaterial.new()
	m.shader = HUE_SHADER
	m.set_shader_parameter("hue", hue)
	m.set_shader_parameter("flash", 1.0 if white else 0.0)
	materials[key] = m
	return m

func take_sprite() -> Sprite2D:
	var sp: Sprite2D
	if sprite_pool.is_empty():
		sp = Sprite2D.new()
		enemy_root.add_child(sp)
	else:
		sp = sprite_pool.pop_back()
		sp.visible = true
	sp.rotation = 0.0
	sp.modulate = Color.WHITE
	sp.material = null
	sp.z_index = 0
	return sp

func give_sprite(sp: Sprite2D) -> void:
	sp.visible = false
	sprite_pool.append(sp)

# ---------- Main loop ----------

func _process(delta: float) -> void:
	var real_dt := minf(delta, 0.05)
	t += real_dt
	_measure()
	_update_background(real_dt)
	input_lock = maxf(0.0, input_lock - real_dt)
	hud.update(real_dt)
	if phase == Phase.RESUME:
		resume_t -= real_dt
		if resume_t <= 0.0:
			phase = previous_phase
			Audio.set_muffled(false)
	elif phase != Phase.PAUSED:
		shown_score = move_toward(shown_score, float(score), maxf(120.0, absf(float(score) - shown_score) * 8.0) * real_dt)
		_tick(real_dt)
	_update_shake(real_dt)
	_redraw()

func _tick(real_dt: float) -> void:
	phase_t += real_dt
	flash = maxf(0.0, flash - real_dt * 3.2)
	time_scale = move_toward(time_scale, 1.0, real_dt * 1.6)
	var dt := real_dt * time_scale
	if hitstop > 0.0:
		hitstop -= real_dt
		dt = 0.0
	fx.update(real_dt)
	if combo_timer > 0.0:
		combo_timer -= dt
		if combo_timer <= 0.0:
			combo = 0
	if echo_t > 0.0:
		echo_t -= dt
		if echo_t <= 0.0:
			_fire_nova(true)
	match phase:
		Phase.INTRO:
			_update_world(dt)
			warp = maxf(0.0, warp - real_dt * 0.7)
			if phase_t > 1.7:
				warp = 0.0
				_start_wave(0)
		Phase.PLAYING:
			flight_time += dt
			_update_world(dt)
			if player_alive:
				_update_spawning(dt)
			_update_threat(real_dt)
		Phase.WARNING:
			_update_world(dt)
			if phase_t > 2.3:
				_spawn_boss()
		Phase.BOSS_INTRO:
			_update_world(dt)
			if boss != null:
				boss.update(dt)
			if phase_t > 2.6:
				phase = Phase.BOSS
				phase_t = 0.0
		Phase.BOSS:
			flight_time += dt
			_update_world(dt)
			if boss != null:
				boss.update(dt)
			_update_threat(real_dt)
		Phase.UPGRADE:
			_emit_engine(real_dt)
			if card_picked >= 0 and input_lock <= 0.0:
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

func _update_threat(dt: float) -> void:
	# Drives the music: more shots and heavier enemies bring the intense layer in.
	var want := clampf(float(field.count) / 60.0 + float(enemies.size()) / 18.0, 0.0, 1.0)
	if boss != null or hull <= 1:
		want = 1.0
	threat = move_toward(threat, want, dt * 0.7)
	Audio.set_intensity(threat)

func _redraw() -> void:
	bg_layer.queue_redraw()
	ground_layer.queue_redraw()
	fx_add.queue_redraw()
	fx_top.queue_redraw()
	_fill_batches()

func _update_background(dt: float) -> void:
	bg_scroll += dt * (16.0 + warp * 900.0)
	for st in stars_bg:
		var depth: float = st.depth
		st.pos.y += dt * (24.0 + 170.0 * depth * depth + warp * 1700.0 * depth)
		if st.pos.y > H + 10.0:
			st.pos = Vector2(randf_range(0.0, W), -10.0)

func _update_shake(dt: float) -> void:
	shake = maxf(0.0, shake - dt * 44.0)
	var k := float(Save.opt.shake) * (0.0 if Save.opt.reduced_motion else 1.0)
	if shake > 0.0 and k > 0.0:
		world.position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * k
	else:
		world.position = Vector2.ZERO

func kick(amount: float) -> void:
	shake = minf(20.0, shake + amount)

func do_flash(amount: float, color: Color) -> void:
	flash = amount * (0.25 if Save.opt.reduced_flash else 1.0)
	flash_color = color

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
	if aegis_t > 0.0:
		ready_glow = 0.5 + sin(t * 12.0) * 0.1
	# Only the look follows the shield: wear dims and flickers the glow, and a broken shield collapses outwards.
	var wear := shield_fx.flicker(shield_fx.ratio(shield, max_shield))
	shield_sprite.scale = Vector2.ONE * (170.0 / 512.0) * shield_fx.collapse_scale()
	shield_sprite.modulate.a = 0.0 if not player_alive else clampf(ready_glow * wear + shield_flash * 0.75 + shield_fx.collapse_alpha(), 0.0, 1.0)
	shield_sprite.rotation += dt * 0.5
	var shield_event := shield_fx.update(dt, player_pos, shield, max_shield, player_alive, phase in COMBAT_PHASES)
	if shield_event == "up":
		CombatAudio.shield("up")
	elif shield_event == "warn":
		CombatAudio.shield("warn")
	engine_fx.update_motion(dt, player_pos, player_alive)
	var drones := int(s.drones)
	for i in range(drone_sprites.size()):
		var d: Sprite2D = drone_sprites[i]
		d.visible = i < drones and player_alive
		if d.visible:
			d.position = drone_pos(i)

func drone_pos(i: int) -> Vector2:
	var side := -1.0 if i % 2 == 0 else 1.0
	var row := float(i / 2)
	return player_pos + Vector2(side * (84.0 + row * 34.0), 26.0 + row * 34.0 + sin(t * 3.0 + float(i)) * 6.0)

func _update_world(dt: float) -> void:
	if dt <= 0.0:
		return
	_update_player(dt)
	_update_shots(dt)
	var catching: bool = player_alive and (invuln <= 0.0 or aegis_t > 0.0)
	field.update(dt, W, H, player_pos, float(ship.hitbox), 40.0, _on_bullet_hit, _on_graze, _on_bullet_blocked, catching)
	_update_enemies(dt)
	_update_pickups(dt)
	hazards.update(dt)
	_update_timers(dt)
	if storm_t > 0.0:
		_update_storm(dt)

func _update_timers(dt: float) -> void:
	for i in range(timers.size() - 1, -1, -1):
		if i >= timers.size():
			continue
		var entry: Dictionary = timers[i]
		entry.t -= dt
		if float(entry.t) <= 0.0:
			timers.remove_at(i)
			var fn: Callable = entry.fn
			if fn.is_valid():
				fn.call()

func after(seconds: float, fn: Callable) -> void:
	timers.append({"t": seconds, "fn": fn})

# ---------- Player ----------

func _update_player(dt: float) -> void:
	if not player_alive:
		return
	if phase in COMBAT_PHASES or phase == Phase.BOSS_INTRO:
		var axis := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			axis.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			axis.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			axis.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			axis.y += 1.0
		var speed: float = 640.0 * float(ship.speed)
		if axis != Vector2.ZERO:
			player_target += axis.normalized() * speed * dt
			touch_moved += speed * dt
		hazards.pull_player(dt)
		clamp_target()
		var before := player_pos
		player_pos = player_pos.lerp(player_target, 1.0 - exp(-dt * 26.0 * float(ship.speed)))
		var moved := player_pos.distance_to(before) / maxf(dt, 0.001)
		beam_focus = move_toward(beam_focus, 1.0 if moved < 120.0 else 0.0, dt * (0.62 if moved < 120.0 else 2.2))
		if phase != Phase.BOSS_INTRO:
			_update_weapons(dt)
		energy = minf(100.0, energy + dt * 0.8 * float(s.nova_gain))
	elif phase == Phase.INTRO:
		player_pos = player_pos.lerp(player_target, 1.0 - exp(-dt * 3.6))
	shield_idle += dt
	invuln = maxf(0.0, invuln - dt)
	slip_t = maxf(0.0, slip_t - dt)
	surge_t = maxf(0.0, surge_t - dt)
	overdrive_t = maxf(0.0, overdrive_t - dt)
	aegis_t = maxf(0.0, aegis_t - dt)
	var regen_delay := 2.2 if str(ship.trait) == "BULWARK" else 3.5
	if shield_idle > regen_delay and shield < max_shield and not Mutators.flag(mutators, "noregen"):
		shield = minf(max_shield, shield + dt * (12.0 + float(s.shield_regen)) * danger_regen)
	_emit_engine(dt)

func clamp_target() -> void:
	player_target.x = clampf(player_target.x, 44.0, W - 44.0)
	# The floor sits above the Nova button so the ship can never hide behind it.
	player_target.y = clampf(player_target.y, H * 0.42, H - FLOOR_MARGIN - inset.y)

func _emit_engine(dt: float) -> void:
	engine_fx.emit(dt, fx, player_pos, player_alive)

func shot_power() -> float:
	var power: float = float(s.dmg_mult)
	if float(s.redline) > 0.0:
		power *= 1.0 + float(s.redline) * (1.0 - shield / max_shield)
	if surge_t > 0.0:
		power *= 1.5
	if overdrive_t > 0.0:
		power *= 1.25
	power *= 1.0 + float(midas_stacks) * 0.01
	return power

func _fire_interval() -> float:
	var base: float = float(weapon.interval) * float(s.fire_mult)
	if slip_t > 0.0:
		base *= 0.7
	if overdrive_t > 0.0:
		base *= 0.34
	return maxf(0.05, base)

func _update_weapons(dt: float) -> void:
	if str(ship.weapon) == "beam":
		_update_beam(dt)
	else:
		fire_timer -= dt
		if fire_timer <= 0.0:
			fire_timer = _fire_interval()
			_fire()
	var drones := int(s.drones)
	if drones > 0:
		drone_timer -= dt
		if drone_timer <= 0.0:
			drone_timer = 0.42
			for i in range(drones):
				_add_shot(drone_pos(i) + Vector2(0, -24), -PI * 0.5, shot_power() * 0.7, UI.MINT, 62.0)
	var seekers := int(s.seekers) + (drones if float(s.hunter) > 0.0 else 0)
	if seekers > 0:
		seeker_timer -= dt
		if seeker_timer <= 0.0:
			seeker_timer = 1.6
			for i in range(seekers):
				var side := -1.0 if i % 2 == 0 else 1.0
				_add_missile(player_pos + Vector2(side * 30.0, -10.0), -PI * 0.5 + side * 0.9, shot_power() * 1.4)
			Audio.play("missile", -10.0, 1.0, 0.1)
	if float(s.aegis_wing) > 0.0 and drones > 0:
		field.clear_circle(player_pos, 92.0, _soft_pop)

func _soft_pop(p: Vector2) -> void:
	fx.sparks(p, 2, UI.MINT, 100.0, 0.25, 8.0)

func _fire() -> void:
	var lanes := int(s.lanes)
	var dmg: float = float(weapon.damage) * shot_power()
	match str(ship.weapon):
		"pulse":
			var n := 1 + lanes
			for i in range(n):
				var lane := float(i) - float(n - 1) * 0.5
				_add_shot(player_pos + Vector2(lane * 20.0, -46.0 + absf(lane) * 12.0), -PI * 0.5 + lane * 0.085, dmg, UI.CYAN, float(weapon.size))
			CombatAudio.fire("pulse", n)
		"twin":
			var n := 2 + lanes
			for i in range(n):
				var lane := float(i) - float(n - 1) * 0.5
				_add_shot(player_pos + Vector2(lane * 24.0, -34.0), -PI * 0.5 + lane * 0.03, dmg, Color(0.6, 1.0, 0.8), float(weapon.size))
			CombatAudio.fire("twin", n)
		"missile":
			var n := 2 + lanes
			for i in range(n):
				var lane := float(i) - float(n - 1) * 0.5
				_add_missile(player_pos + Vector2(lane * 30.0, -20.0), -PI * 0.5 + lane * 0.5, dmg)
			CombatAudio.fire("missile", n)
		"scatter":
			var n := 5 + lanes * 2
			for i in range(n):
				var lane := float(i) - float(n - 1) * 0.5
				var b := _add_shot(player_pos + Vector2(lane * 8.0, -40.0), -PI * 0.5 + lane * 0.13 + randf_range(-0.03, 0.03), dmg, UI.GOLD, float(weapon.size))
				b.life = 0.72
			CombatAudio.fire("scatter", n)
	fx.spark(player_pos + Vector2(0, -50), Vector2(0, -30), 0.1, UI.CYAN, 18.0)

func _add_shot(at: Vector2, angle: float, damage: float, color: Color, size: float) -> Dictionary:
	var speed: float = float(weapon.speed) * float(s.shot_speed)
	if speed <= 0.0:
		speed = 900.0 * float(s.shot_speed)
	var b := {"pos": at, "vel": Vector2.from_angle(angle) * speed, "dmg": damage, "pierce": int(s.pierce), "hits": [], "color": color, "size": size, "life": 2.0, "home": false, "bounce": int(s.ricochet), "prism": float(s.prism) > 0.0, "missile": false, "wpn": str(ship.weapon)}
	if shots.size() < 220:
		shots.append(b)
	return b

func _add_missile(at: Vector2, angle: float, damage: float) -> void:
	if shots.size() >= 220:
		return
	shots.append({"pos": at, "vel": Vector2.from_angle(angle) * 360.0, "dmg": damage, "pierce": 0, "hits": [], "color": UI.ORANGE, "size": 56.0, "life": 2.6, "home": true, "bounce": 0, "prism": false, "missile": true, "wpn": "missile"})

func _nearest_enemy(from: Vector2, skip: Array, reach := 1e9) -> Dictionary:
	var best := {}
	var best_d := reach * reach
	for e in enemies:
		if e.dead or e.ghost or e.ally or e.id in skip or float(e.pos.y) < 0.0:
			continue
		var d: float = from.distance_squared_to(e.pos)
		if d < best_d:
			best_d = d
			best = e
	return best

func _update_shots(dt: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var b: Dictionary = shots[i]
		b.life -= dt
		if b.home:
			var target: Vector2 = player_pos + Vector2(0, -900)
			var near := _nearest_enemy(b.pos, [])
			if not near.is_empty() and boss == null:
				target = near.pos
			elif boss != null:
				target = boss.aim_point()
			var want: Vector2 = (target - (b.pos as Vector2)).normalized() * 720.0
			b.vel = (b.vel as Vector2).lerp(want, 1.0 - exp(-dt * 5.0))
			if randf() < 0.6 * fx.density:
				fx.spark(b.pos, Vector2.ZERO, 0.22, UI.ORANGE, 7.0)
		b.pos += b.vel * dt
		var p: Vector2 = b.pos
		if float(b.life) <= 0.0 or p.y < -60.0 or p.x < -60.0 or p.x > W + 60.0 or p.y > H + 60.0 or _shot_hits(b):
			if i < shots.size():
				shots.remove_at(i)

func _shot_hits(b: Dictionary) -> bool:
	var p: Vector2 = b.pos
	var hits: Array = b.hits
	if boss != null and boss.can_be_hit():
		var part: Dictionary = boss.hit_part(p)
		if not part.is_empty() and not (part.id in hits):
			hits.append(part.id)
			if b.missile:
				_splash(p, b)
			var dmg := _roll_crit(float(b.dmg), p)
			if boss == null or not boss.take_hit(part, dmg, p, str(b.wpn)):
				return true
			_apply_ricochet(b)
			b.pierce = int(b.pierce) - 1
			return int(b.pierce) < 0 and int(b.bounce) < 0
	for e in enemies:
		if e.dead or e.ghost or e.ally or e.id in hits or float(e.pos.y) < -10.0:
			continue
		var r: float = float(e.r) + 8.0
		if p.distance_squared_to(e.pos) < r * r:
			hits.append(e.id)
			if b.missile:
				_splash(p, b)
			var dmg := _roll_crit(float(b.dmg), p)
			_hit_enemy(e, dmg, p, dmg > float(b.dmg), false, str(b.wpn))
			if b.prism:
				_split_prism(b, p)
			if int(b.bounce) > 0:
				_apply_ricochet(b)
				continue
			b.pierce = int(b.pierce) - 1
			if int(b.pierce) < 0:
				return true
	return false

func _apply_ricochet(b: Dictionary) -> void:
	if int(b.bounce) <= 0:
		b.bounce = -1
		return
	b.bounce = int(b.bounce) - 1
	var near := _nearest_enemy(b.pos, b.hits, 520.0)
	if not near.is_empty():
		b.vel = ((near.pos as Vector2) - (b.pos as Vector2)).normalized() * (b.vel as Vector2).length()
		b.life = 1.0

func _split_prism(b: Dictionary, at: Vector2) -> void:
	var ang: float = (b.vel as Vector2).angle()
	for side in [-0.6, 0.6]:
		var c := _add_shot(at, ang + side, float(b.dmg) * 0.5, UI.VIOLET, 60.0)
		c.prism = false
		c.pierce = 0
		c.bounce = 0
		c.hits = (b.hits as Array).duplicate()
		c.life = 0.8

func _splash(at: Vector2, b: Dictionary) -> void:
	fx.impact(at, "missile", clampf(float(b.dmg) / 1.1, 0.8, 2.0))
	CombatAudio.impact("missile", "hull", clampf(float(b.dmg) / 1.1, 0.8, 2.0))
	for e in enemies:
		if not e.dead and not e.ghost and not e.ally and not (e.id in b.hits) and at.distance_squared_to(e.pos) < 8100.0:
			_hit_enemy(e, float(b.dmg) * 0.4, e.pos, false, true)

func _roll_crit(base: float, at: Vector2) -> float:
	if randf() < float(s.crit):
		fx.text("CRIT", at + Vector2(0, -24), 24, UI.GOLD)
		Audio.play("crit", -8.0, 1.0, 0.05)
		if float(s.tesla) > 0.0:
			_arc_from(at, 4, base)
		return base * 2.0
	return base

func _arc_from(at: Vector2, links: int, damage: float) -> void:
	var from := at
	var seen: Array = []
	for i in range(links):
		var e := _nearest_enemy(from, seen, 340.0)
		if e.is_empty():
			break
		seen.append(e.id)
		fx.bolt(from, e.pos, UI.CYAN)
		_hit_enemy(e, damage * 0.8, e.pos, false, true)
		from = e.pos
	if not seen.is_empty():
		Audio.play("arc", -8.0, 1.0, 0.1)

func _beam_offsets() -> Array:
	var offsets: Array = [0.0]
	for i in range(int(s.lanes)):
		offsets.append(float(i / 2 + 1) * (-44.0 if i % 2 == 0 else 44.0))
	return offsets

func _update_beam(dt: float) -> void:
	beam_active = true
	beam_tick -= dt
	if beam_tick > 0.0:
		return
	beam_tick = _fire_interval()
	beam_top = 0.0
	var width := 15.0 + float(s.pierce) * 7.0
	var dmg: float = float(weapon.damage) * shot_power() * (1.0 + beam_focus * 1.4)
	for off in _beam_offsets():
		_beam_column(player_pos.x + float(off), width, dmg * (1.0 if off == 0.0 else 0.6))
	Audio.play("beam", -14.0, 0.9 + beam_focus * 0.3)

func _beam_column(x: float, width: float, dmg: float) -> void:
	var stop := -20.0
	if float(s.pierce) <= 0.0:
		for e in enemies:
			if not e.dead and e.cover and not e.ally and absf(float(e.pos.x) - x) < float(e.r) and float(e.pos.y) < player_pos.y:
				stop = maxf(stop, float(e.pos.y))
	if boss != null and boss.can_be_hit():
		var hit: Dictionary = boss.beam_part(x, width, player_pos.y)
		if not hit.is_empty():
			stop = maxf(stop, float(hit.y))
			boss.take_hit(hit.part, _roll_crit(dmg, Vector2(x, hit.y)), Vector2(x, hit.y), "beam")
	beam_top = maxf(beam_top, stop)
	for e in enemies:
		if e.dead or e.ghost or e.ally or float(e.pos.y) < stop - 1.0 or float(e.pos.y) > player_pos.y or float(e.pos.y) < -10.0:
			continue
		if absf(float(e.pos.x) - x) < float(e.r) + width:
			_hit_enemy(e, _roll_crit(dmg, e.pos), e.pos, false, false, "beam")

# ---------- Taking damage ----------

func _on_bullet_hit(at: Vector2, damage: float) -> void:
	if aegis_t > 0.0:
		var near := _nearest_enemy(at, [])
		var dir: Vector2 = Vector2(0, -1) if near.is_empty() else ((near.pos as Vector2) - at).normalized()
		_add_shot(at, dir.angle(), float(weapon.damage) * shot_power() * 2.0, UI.MAGENTA, 70.0)
		fx.sparks(at, 3, UI.CYAN, 120.0, 0.25, 8.0)
		return
	if invuln > 0.0:
		return
	fx.sparks(at, 6, UI.MAGENTA, 160.0, 0.25, 12.0)
	hurt_player(damage, at)

func _on_graze(at: Vector2) -> void:
	Meta.count("graze")
	var slip: bool = str(ship.trait) == "SLIPSTREAM"
	if slip or float(s.graze) > 0.0:
		add_energy(1.6 * (1.0 + float(s.graze)))
		fx.spark(at, Vector2.ZERO, 0.2, UI.WHITE, 14.0)
	if slip:
		slip_t = 2.0
	if float(s.daredevil) > 0.0:
		for e in enemies:
			if not e.dead and not e.ghost and not e.ally and float(e.pos.y) > 0.0:
				_hit_enemy(e, 0.5 * shot_power(), e.pos, false, true)
		if boss != null and boss.can_be_hit():
			boss.nova_hit(1.0 * shot_power())

func _on_bullet_blocked(b: Dictionary, damage: float, at: Vector2) -> void:
	fx.sparks(at, 3, Color(0.8, 0.85, 0.95), 130.0, 0.2, 8.0)
	if b.ally:
		b.hp -= damage * 0.09
		if float(b.hp) <= float(b.max) * 0.5:
			tracker.escort_ok = false
		if float(b.hp) <= 0.0:
			_kill_enemy(b, false)
	else:
		b.hp -= 0.3
		if float(b.hp) <= 0.0:
			_kill_enemy(b, false)

func hurt_player(amount: float, from := Vector2.INF) -> void:
	if invuln > 0.0 or not player_alive or aegis_t > 0.0 or phase not in COMBAT_PHASES:
		return
	shield_idle = 0.0
	if overdrive_t > 0.0:
		shield_flash = 1.0
		invuln = 0.3
		return
	if shield > 0.0:
		var overflow: bool = float(s.bastion) > 0.0 and amount >= shield and shield > 1.0
		shield = 1.0 if overflow else maxf(0.0, shield - amount)
		invuln = 0.4 + float(s.iframes)
		shield_flash = 1.0
		kick(6.0)
		combo = combo / 2
		var shield_power := shield_fx.on_hit(player_pos, from, amount, max_shield)
		CombatAudio.shield("heavy" if shield_power >= 1.3 else "hit")
		Save.haptic(25)
		if str(ship.trait) == "BULWARK" or float(s.spike) > 0.0:
			field.clear_circle(player_pos, 210.0, _soft_pop)
			fx.ring(player_pos, 0.35, 40.0, 210.0, UI.MINT, 5.0)
		if shield <= 0.0:
			tracker.shield_broke = true
			shield_fx.on_break(player_pos)
			CombatAudio.shield("break")
			if Save.upgrade_level("emergency") > 0 and not emergency_used:
				emergency_used = true
				shield = max_shield
				Audio.play("repair", -2.0)
				hud.coach("EMERGENCY CELL ENGAGED", 2.0)
		return
	hull -= 1
	hull_lost += 1
	combo = 0
	combo_timer = 0.0
	invuln = 1.5 + float(s.iframes)
	kick(15.0)
	do_flash(0.55, UI.RED)
	if not Save.opt.reduced_motion:
		hitstop = 0.06
	Audio.play("hull_hit")
	Save.haptic(70)
	fx.sparks(player_pos, 26, UI.ORANGE, 300.0, 0.5, 15.0)
	fx.boom(player_pos, 150.0, false, 0.4)
	fx.ring(player_pos, 0.35, 30.0, 190.0, UI.RED, 7.0)
	field.clear_circle(player_pos, 260.0, _soft_pop)
	if hull <= 0:
		if float(s.phoenix) > 0.0 and not phoenix_used:
			phoenix_used = true
			hull = 1
			shield = max_shield
			invuln = 2.5
			do_flash(0.8, UI.GOLD)
			Audio.play("powerup")
			hud.banner_show("SECOND WIND", "", 1.2, UI.GOLD)
			field.clear()
		else:
			_player_destroyed()

func _player_destroyed() -> void:
	player_alive = false
	time_scale = 0.3
	kick(20.0)
	CombatAudio.explosion("player")
	fx.explode(player_pos, "heavy", 240.0, "fire")
	fx.ring(player_pos, 0.6, 40.0, 420.0, UI.ORANGE, 8.0)
	Audio.stop_music(1.0)
	after(1.0, _show_defeat)

func add_energy(amount: float) -> void:
	var before := energy
	energy = minf(100.0, energy + amount * float(s.nova_gain))
	if before < 100.0 and energy >= 100.0:
		Audio.play("energy_ready", -3.0)
		hud.nova_ready_hint()

func try_nova() -> void:
	if nova_sealed or energy < 100.0 or not player_alive or phase not in [Phase.PLAYING, Phase.BOSS]:
		return
	energy = float(s.nova_refund)
	_fire_nova(false)
	if float(s.echo) > 0.0:
		echo_t = 0.9
	Meta.count("nova")
	Save.mark_tutorial("nova")

func _fire_nova(echo: bool) -> void:
	if not player_alive:
		return
	Save.haptic(90)
	kick(18.0)
	if not echo:
		do_flash(0.6, UI.CYAN)
	if not Save.opt.reduced_motion:
		hitstop = 0.07
	match Save.nova_mode:
		"singularity":
			Audio.play("burst", 0.0, 0.7)
			hazards.add_singularity(Vector2(player_pos.x, maxf(player_pos.y - 330.0, top + 200.0)))
		"overdrive":
			Audio.play("powerup")
			overdrive_t = 6.0
			fx.ring(player_pos, 0.5, 30.0, 300.0, UI.GOLD, 10.0)
			field.clear_circle(player_pos, 320.0)
		"aegis":
			Audio.play("shield_hit", 2.0, 0.6)
			aegis_t = 5.0
			fx.ring(player_pos, 0.5, 30.0, 300.0, UI.MAGENTA, 10.0)
		_:
			Audio.play("burst")
			fx.ring(player_pos, 0.7, 60.0, H * 1.1, UI.CYAN, 16.0)
			fx.ring(player_pos, 0.9, 30.0, H * 0.85, Color.WHITE, 6.0)
			var cleared := field.count
			for i in range(mini(cleared, 80)):
				fx.sparks(field.pos[i], 2, UI.CYAN, 90.0, 0.3, 8.0)
			field.clear()
			if cleared > 0:
				var bonus := int(float(cleared * 10) * score_mult)
				score += bonus
				fx.text("+%d" % bonus, player_pos + Vector2(0, -90), 34, UI.CYAN)
			var damage := 9.0 * shot_power()
			for e in enemies:
				if not e.dead and not e.ally and float(e.pos.y) > 0.0:
					_hit_enemy(e, damage, e.pos, false, true)
			if boss != null and boss.can_be_hit():
				boss.nova_hit(damage * 2.2)

# ---------- Waves and spawning ----------

func _start_wave(index: int) -> void:
	wave_index = index
	group_queue = (level.waves[index] as Array).duplicate(true)
	group_timer = 0.7
	clear_wait = -1.0
	phase = Phase.PLAYING
	phase_t = 0.0
	Audio.play("wave_start", -5.0)
	var total: int = (level.waves as Array).size()
	if mode == "endless":
		var dial_names: Array = []
		for d in level.get("mutators", []):
			dial_names.append(str(Mutators.LIST[d].name))
		hud.banner_show("FLOOR %d" % endless_wave, " + ".join(dial_names), 1.4, UI.GOLD)
	elif total > 1:
		hud.banner_show("WAVE %d/%d" % [index + 1, total], "", 1.2, UI.WHITE)

func _update_spawning(dt: float) -> void:
	if not group_queue.is_empty():
		group_timer -= dt * danger_pace
		if group_timer <= 0.0:
			var g: Dictionary = group_queue.pop_front()
			group_timer = float(g.delay)
			if g.has("event"):
				_run_event(g)
			else:
				_spawn_group(g)
	for i in range(pending.size() - 1, -1, -1):
		var entry: Dictionary = pending[i]
		entry.t -= dt
		if float(entry.t) <= 0.0:
			pending.remove_at(i)
			spawn_enemy(entry)
	if group_queue.is_empty() and pending.is_empty() and storm_t <= 0.0 and _hostiles_left() == 0:
		if clear_wait < 0.0:
			clear_wait = 0.9
			_attract_all()
			if kills > 0 and not finish_slowed and boss == null and not Save.opt.reduced_motion:
				finish_slowed = true
				time_scale = 0.45
		clear_wait -= dt
		if clear_wait <= 0.0:
			finish_slowed = false
			_on_wave_cleared()

func _hostiles_left() -> int:
	var n := 0
	for e in enemies:
		if not e.dead and not e.ally and not e.cover and not e.treasure:
			n += 1
	return n

func _run_event(g: Dictionary) -> void:
	match str(g.event):
		"storm":
			storm_t = float(g.amount)
			storm_timer = 0.0
			hud.banner_show("ASTEROID STORM", "", 1.2, UI.ORANGE)
			Audio.play("warning", -12.0, 1.4)
		"ambush":
			_spawn_ambush(str(g.kind), int(g.count))
		"treasure":
			_spawn_treasure()
		"escort":
			_spawn_escort()
		_:
			hazards.event(str(g.event), float(g.amount))

func _update_storm(dt: float) -> void:
	storm_t -= dt
	storm_timer -= dt
	if storm_timer <= 0.0:
		storm_timer = 0.32
		var roll := randf()
		var rock := "rock_l" if roll < 0.18 else ("rock_m" if roll < 0.6 else "rock_s")
		spawn_enemy({"kind": rock, "pos": Vector2(randf_range(40.0, W - 40.0), -80.0), "move": "straight", "vel": Vector2(randf_range(-60.0, 60.0), randf_range(240.0, 340.0) * float(scale_cfg.speed))})

func _spawn_ambush(kind: String, count: int) -> void:
	hud.banner_show("AMBUSH", "", 1.0, UI.RED)
	Audio.play("warning", -10.0, 1.6)
	hazards.side_warning()
	for i in range(count):
		var left := i % 2 == 0
		var at := Vector2(-70.0 if left else W + 70.0, H * 0.72 + float(i % 3) * 70.0)
		queue_spawn(0.9 + float(i) * 0.22, kind, at, "ambush", Vector2.from_angle(-0.5 if left else PI + 0.5) * 300.0, {"turn": -1.0 if left else 1.0})

func _spawn_treasure() -> void:
	hud.coach("GOLD COURIER! Catch it before it jumps away", 3.0)
	var left := randf() < 0.5
	queue_spawn(0.3, "treasure", Vector2(-60.0 if left else W + 60.0, top + 230.0), "courier", Vector2(190.0 if left else -190.0, 0.0))

func _spawn_escort() -> void:
	tracker.escort_seen = true
	queue_spawn(0.2, "ally", Vector2(W * 0.5 + randf_range(-120.0, 120.0), H + 120.0), "convoy", Vector2(0, -52.0))

func queue_spawn(delay: float, kind: String, pos: Vector2, move: String, vel: Vector2, extra: Dictionary = {}) -> void:
	var entry := {"t": delay, "kind": kind, "pos": pos, "move": move, "vel": vel}
	entry.merge(extra)
	pending.append(entry)

func spawn_group(g: Dictionary) -> void:
	_spawn_group(g)

func _spawn_group(g: Dictionary) -> void:
	var kind: String = g.kind
	var scaled: bool = kind not in ["elite", "gunship", "frigate", "brood"]
	var count: int = maxi(1, int(round(float(g.count) * (count_mult if scaled else 1.0))))
	var form: String = g.form
	var extra := {"mod": str(g.get("mod", ""))}
	var speed: float = scale_cfg.speed
	var mid := W * 0.5
	if kind == "swarm":
		kind = "swarmlet"
	match form:
		"rain":
			for i in range(count):
				var roll := randf()
				var rock := "rock_l" if roll < 0.24 else ("rock_m" if roll < 0.62 else "rock_s")
				if level_num <= 2 and mode == "campaign":
					rock = "rock_m" if roll < 0.4 else "rock_s"
				queue_spawn(float(i) * 0.42, rock, Vector2(randf_range(50.0, W - 50.0), -70.0), "straight", Vector2(randf_range(-45.0, 45.0), randf_range(120.0, 200.0) * speed))
		"drift":
			for i in range(count):
				queue_spawn(float(i) * 0.9, kind, Vector2(randf_range(90.0, W - 90.0), -90.0), "drift", Vector2(randf_range(-14.0, 14.0), randf_range(58.0, 84.0) * speed))
		"line":
			for i in range(count):
				queue_spawn(0.0, kind, Vector2(W * (float(i) + 1.0) / (float(count) + 1.0), -70.0), "straight", Vector2(0, 130.0 * speed), extra)
		"vee":
			for i in range(count):
				var off := float(i) - float(count - 1) * 0.5
				queue_spawn(absf(off) * 0.26, kind, Vector2(mid + off * minf(110.0, (W - 120.0) / float(count)), -70.0), "straight", Vector2(0, 135.0 * speed), extra)
		"column":
			var x := randf_range(150.0, W - 150.0)
			for i in range(count):
				var ex := {"amp": 90.0, "freq": 1.5}
				ex.merge(extra)
				queue_spawn(float(i) * 0.46, kind, Vector2(x, -70.0), "sine", Vector2(0, 150.0 * speed), ex)
		"sine":
			var base := randf_range(240.0, W - 240.0)
			var flip := 1.0 if randf() < 0.5 else -1.0
			for i in range(count):
				var ex := {"amp": flip * minf(200.0, W * 0.3), "freq": 1.7}
				ex.merge(extra)
				queue_spawn(float(i) * 0.4, kind, Vector2(base, -70.0), "sine", Vector2(0, 165.0 * speed), ex)
		"pincer":
			for i in range(count):
				var left := i % 2 == 0
				var start := Vector2(-60.0 if left else W + 60.0, randf_range(190.0, 340.0))
				var heading := -0.15 if left else PI + 0.15
				var ex := {"turn": 1.5 if left else -1.5}
				ex.merge(extra)
				queue_spawn(float(i) * 0.3, kind, start, "arc", Vector2.from_angle(heading) * 330.0 * speed, ex)
		"dive":
			for i in range(count):
				var move := "hunt" if kind == "cinder" else "dive"
				queue_spawn(float(i) * 0.55, kind, Vector2(randf_range(70.0, W - 70.0), -70.0), move, Vector2(0, 170.0 * speed), extra)
		"scatter":
			for i in range(count):
				queue_spawn(float(i) * 0.6, kind, Vector2(randf_range(80.0, W - 80.0), -60.0), "drift", Vector2(0, randf_range(85.0, 125.0) * speed), extra)
		"swarm":
			var origin := randf_range(150.0, W - 150.0)
			for i in range(count):
				queue_spawn(float(i) * 0.14, kind, Vector2(origin + randf_range(-110.0, 110.0), -60.0), "swarm", Vector2(0, 210.0 * speed), extra)
		"hold":
			for i in range(count):
				var hx := W * (float(i) + 1.0) / (float(count) + 1.0)
				var ex := {"hold_y": top + 230.0 + float(i % 2) * 90.0, "amp": W * 0.5 / float(count) - 70.0}
				ex.merge(extra)
				queue_spawn(float(i) * 0.3, kind, Vector2(hx, -170.0), "hold", Vector2.ZERO, ex)
		"side":
			for i in range(count):
				var left := i % 2 == 0
				var lane_y: float = top + 300.0 + float(i) * 170.0
				hazards.lane_warning(lane_y)
				queue_spawn(1.0 + float(i) * 1.3, kind, Vector2(-170.0 if left else W + 170.0, lane_y), "cross", Vector2(150.0 if left else -150.0, 0.0), extra)

func spawn_enemy(cfg: Dictionary) -> Dictionary:
	var kind: String = cfg.kind
	var info: Dictionary = Enemies.DB[kind]
	var hp: float = float(info.hp) * float(scale_cfg.hp) * hp_mult
	if info.get("ally", false):
		hp = float(info.hp)
	var sp := take_sprite()
	var art: String = info.art
	if kind == "wreck" and randf() < 0.5:
		art = "wreck_b"
	sp.texture = Enemies.ART[art]
	var size: float = info.size
	sp.scale = Vector2.ONE * (size / 512.0)
	var hue: float = info.hue
	if hue != 0.0:
		sp.material = hue_mat(hue)
	if kind == "husk":
		sp.modulate = Color(0.75, 0.9, 1.0, 0.9)
	var mod: String = cfg.get("mod", "")
	if mod.is_empty() and elite_chance > 0.0 and randf() < elite_chance and kind in ["fighter", "weaver", "gunship", "bomber", "revenant", "sentinel"]:
		mod = Enemies.ELITE_ORDER[randi() % Enemies.ELITE_ORDER.size()]
	var e := {
		"id": next_id, "kind": kind, "pos": cfg.pos, "vel": cfg.vel, "move": cfg.move, "hp": hp, "max": hp,
		"r": info.r, "hue": hue, "sprite": sp, "age": 0.0, "dead": false, "size": size,
		"fire": randf_range(0.8, float(info.fire)) if float(info.fire) > 0.0 else 0.0,
		"rate": info.fire, "shot": info.shot, "tell": 0.0, "flash": 0.0, "spin": randf_range(-1.8, 1.8), "base": float(cfg.pos.x),
		"amp": float(cfg.get("amp", 0.0)), "freq": float(cfg.get("freq", 1.0)), "turn": float(cfg.get("turn", 0.0)),
		"hold_y": float(cfg.get("hold_y", 0.0)), "score": info.score, "drop": info.drop,
		"heavy": info.get("heavy", false), "cover": info.get("cover", false), "volatile": info.get("volatile", false),
		"ally": info.get("ally", false), "treasure": info.get("treasure", false), "revive": info.get("revive", false) and not cfg.get("revived", false),
		"phasing": info.get("phase", false), "ghost": false, "mod": mod, "eshield": 0.0, "eshield_max": 0.0, "idle": 0.0, "speed_k": 1.0,
		"burn": 0.0, "burn_tick": 0.0, "slow": 0.0, "frozen": 0.0, "hatch": 0.0, "cryo_hits": 0,
	}
	next_id += 1
	match kind:
		"pod":
			e.hatch = 6.5
		"husk":
			e.hatch = 3.6
		"treasure":
			e.hatch = 7.5
	match mod:
		"shielded":
			e.eshield = hp * 0.6
			e.eshield_max = e.eshield
		"swift":
			e.speed_k = 1.4
			e.rate = float(e.rate) * 0.72
	sp.position = e.pos
	enemies.append(e)
	if e.cover or e.ally:
		field.blockers.append(e)
	if not mod.is_empty() and not Save.tutorial_seen("mod_" + mod):
		Save.mark_tutorial("mod_" + mod)
		var mod_def: Dictionary = Enemies.MODS[mod]
		hud.coach(str(mod_def.name) + ": " + str(mod_def.desc), 4.5)
	if kind == "mine":
		Audio.play("mine", -10.0)
	if Meta.discover("enemy_" + kind):
		hud.codex_toast(str(info.name))
	return e

func _update_enemies(dt: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if i >= enemies.size():
			continue
		var e: Dictionary = enemies[i]
		var sprite: Sprite2D = e.sprite
		if e.dead:
			_release_enemy(i, e)
			continue
		e.age += dt
		var local_dt := dt
		if float(e.frozen) > 0.0:
			e.frozen -= dt
			local_dt = 0.0
			sprite.modulate = Color(0.6, 0.9, 1.0)
		elif float(e.slow) > 0.0:
			e.slow -= dt
			local_dt = dt * 0.55
		local_dt *= float(e.speed_k)
		if local_dt > 0.0:
			_move_enemy(e, local_dt)
		sprite.position = e.pos
		_update_status(e, dt)
		if e.dead:
			continue
		if float(e.flash) > 0.0:
			e.flash -= dt
			if float(e.flash) <= 0.0:
				sprite.material = hue_mat(float(e.hue)) if float(e.hue) != 0.0 else null
		if e.phasing:
			var cycle := fmod(float(e.age), 3.8)
			e.ghost = cycle > 2.3
			sprite.modulate.a = 0.22 if e.ghost else 1.0
		var pos: Vector2 = e.pos
		if pos.y > H + 150.0 or pos.x < -320.0 or pos.x > W + 320.0 or pos.y < -320.0:
			if e.ally and pos.y < 0.0:
				_escort_arrived(e)
			_release_enemy(i, e)
			continue
		if float(e.rate) > 0.0 and pos.y > top + 40.0 and pos.y < player_pos.y - 170.0 and local_dt > 0.0:
			e.fire -= local_dt * float(scale_cfg.fire) * fire_mult_enemy
			if float(e.tell) > 0.0:
				e.tell -= dt
				if float(e.tell) <= 0.0:
					_enemy_shoot(e)
					e.fire = float(e.rate) * randf_range(0.85, 1.15)
			elif float(e.fire) <= 0.0:
				e.tell = 0.5 if str(e.shot) in ["lance", "fan", "elite", "broadside", "bomb"] else 0.3
		if player_alive and phase in COMBAT_PHASES and not e.ghost and not e.ally:
			var reach: float = float(e.r) * 0.82 + 20.0
			if pos.distance_squared_to(player_pos) < reach * reach:
				if e.cover:
					# Wrecks shove the ship aside rather than destroying it outright.
					player_target += (player_pos - pos).normalized() * 220.0 * dt
					hurt_player(14.0)
				else:
					hurt_player(32.0)
					if not e.heavy:
						_kill_enemy(e, false)

func _release_enemy(i: int, e: Dictionary) -> void:
	give_sprite(e.sprite)
	enemies.remove_at(i)
	if e.cover or e.ally:
		field.blockers.erase(e)

func _update_status(e: Dictionary, dt: float) -> void:
	if float(e.burn) > 0.0:
		e.burn -= dt
		e.burn_tick -= dt
		if float(e.burn_tick) <= 0.0:
			e.burn_tick = 0.4
			fx.spark(e.pos, Vector2(randf_range(-40.0, 40.0), -60.0), 0.3, UI.ORANGE, 12.0)
			_hit_enemy(e, 0.5 * float(s.burn) * shot_power(), e.pos, false, true)
	if str(e.mod) == "regen":
		e.idle += dt
		if float(e.idle) > 2.0 and float(e.hp) < float(e.max):
			e.hp = minf(float(e.max), float(e.hp) + float(e.max) * 0.05 * dt)
	if float(e.hatch) > 0.0:
		e.hatch -= dt
		if float(e.hatch) <= 0.0:
			match str(e.kind):
				"pod":
					_hatch_pod(e)
				"husk":
					_revive_husk(e)
				"treasure":
					_courier_jumps(e)

func _hatch_pod(e: Dictionary) -> void:
	tracker.hatched = int(tracker.hatched) + 1
	Audio.play("hatch", -3.0)
	fx.sparks(e.pos, 16, UI.MAGENTA, 220.0, 0.5, 13.0)
	fx.ring(e.pos, 0.4, 20.0, 150.0, UI.MAGENTA, 5.0)
	for i in range(5):
		var a := float(i) * TAU / 5.0
		spawn_enemy({"kind": "swarmlet", "pos": (e.pos as Vector2) + Vector2.from_angle(a) * 34.0, "move": "swarm", "vel": Vector2(0, 170.0)})
	e.dead = true

func _revive_husk(e: Dictionary) -> void:
	Audio.play("ice", -3.0, 0.7)
	fx.sparks(e.pos, 10, Color(0.7, 0.95, 1.0), 180.0, 0.4, 11.0)
	var r := spawn_enemy({"kind": "revenant", "pos": e.pos, "move": "straight", "vel": Vector2(0, 90.0 * float(scale_cfg.speed)), "revived": true})
	r.hp = float(r.max) * 0.6
	e.dead = true

func _courier_jumps(e: Dictionary) -> void:
	Audio.play("whoosh", 0.0, 1.5)
	fx.ring(e.pos, 0.4, 20.0, 160.0, UI.GOLD, 6.0)
	fx.text("IT GOT AWAY", e.pos, 26, UI.GOLD)
	e.dead = true

func _escort_arrived(e: Dictionary) -> void:
	if float(e.hp) <= 0.0:
		return
	var pay := 40
	run_salvage += pay
	fx.text("+%d ESCORT BONUS" % pay, Vector2(W * 0.5, H * 0.3), 32, UI.MINT)
	Audio.play("powerup")

func _move_enemy(e: Dictionary, dt: float) -> void:
	var sprite: Sprite2D = e.sprite
	var kind: String = e.kind
	match str(e.move):
		"straight":
			e.pos += e.vel * dt
			if kind.begins_with("rock"):
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
			sprite.rotation = _facing(kind, e.vel)
		"ambush":
			var angle: float = (e.vel as Vector2).angle()
			if absf(wrapf(angle + PI * 0.5, -PI, PI)) > 0.1:
				e.vel = (e.vel as Vector2).rotated(float(e.turn) * dt)
			e.pos += e.vel * dt
			sprite.rotation = _facing(kind, e.vel)
		"dive":
			if float(e.age) < 0.85:
				e.pos += e.vel * dt
				sprite.rotation = PI if kind == "raider" else 0.0
			else:
				var aim := signf(player_pos.x - float(e.pos.x))
				e.vel.x = move_toward(float(e.vel.x), aim * 240.0, dt * 520.0)
				e.vel.y = move_toward(float(e.vel.y), 620.0 * float(scale_cfg.speed), dt * 680.0)
				e.pos += e.vel * dt
				sprite.rotation = _facing(kind, e.vel)
		"hunt":
			var want: Vector2 = (player_pos - (e.pos as Vector2)).normalized() * 330.0 * float(scale_cfg.speed)
			if float(e.pos.y) < player_pos.y - 90.0:
				e.vel = (e.vel as Vector2).lerp(want, 1.0 - exp(-dt * 1.3))
			e.pos += e.vel * dt
			sprite.rotation = (e.vel as Vector2).angle() - PI * 0.5
			if randf() < 0.5 * fx.density:
				fx.spark(e.pos, -(e.vel as Vector2) * 0.25, 0.3, UI.ORANGE, 11.0)
		"swarm":
			var toward := signf(player_pos.x - float(e.pos.x))
			e.vel.x = move_toward(float(e.vel.x), toward * 120.0 + sin(float(e.age) * 5.0 + float(e.id)) * 110.0, dt * 500.0)
			e.pos += e.vel * dt
			sprite.rotation = -float(e.vel.x) * 0.0015
		"drift":
			e.pos += e.vel * dt
			if kind == "mine":
				e.pos.x += sin(float(e.age) * 1.4) * 34.0 * dt
				sprite.rotation += dt * 0.8
				var pulse := 1.0 + sin(float(e.age) * 7.0) * 0.08
				sprite.scale = Vector2.ONE * (72.0 / 512.0) * pulse
				if (e.pos as Vector2).distance_to(player_pos) < 120.0:
					_kill_enemy(e, false)
			elif kind == "pod":
				var pulse := 1.0 + sin(float(e.age) * (3.0 + (6.5 - float(e.hatch)) * 1.3)) * 0.07
				sprite.scale = Vector2.ONE * (float(e.size) / 512.0) * pulse
			else:
				sprite.rotation += dt * float(e.spin) * 0.25
		"hold":
			if float(e.pos.y) < float(e.hold_y):
				e.pos.y += 190.0 * dt
				e.age = 0.0
			elif float(e.age) < 16.0:
				e.pos.x = float(e.base) + sin(float(e.age) * 0.75) * maxf(30.0, float(e.amp))
				if kind == "sentinel":
					sprite.rotation = lerp_angle(sprite.rotation, (player_pos - (e.pos as Vector2)).angle() - PI * 0.5, dt * 2.0)
			else:
				e.pos.y += 240.0 * dt
		"cross":
			e.pos += e.vel * dt
			sprite.rotation = 0.0 if float(e.vel.x) > 0.0 else PI
		"courier":
			e.pos += e.vel * dt
			e.pos.y += sin(float(e.age) * 3.0) * 60.0 * dt
			if float(e.pos.x) < 60.0 or float(e.pos.x) > W - 60.0:
				e.vel.x = absf(float(e.vel.x)) * (1.0 if float(e.pos.x) < 60.0 else -1.0)
			if randf() < 0.5 * fx.density:
				fx.spark(e.pos, Vector2.ZERO, 0.4, UI.GOLD, 10.0)
		"convoy":
			e.pos += e.vel * dt

func _facing(kind: String, vel: Vector2) -> float:
	# Raiders are drawn nose up, the rest of the fleet nose down.
	return vel.angle() + (PI * 0.5 if kind == "raider" else -PI * 0.5)

func _enemy_shoot(e: Dictionary) -> void:
	var from: Vector2 = e.pos
	var aim: float = (player_pos - from).angle()
	var speed: float = 270.0 * float(scale_cfg.bullet) * bullet_mult
	match str(e.shot):
		"aimed":
			ebullet(from + Vector2(0, 40), aim, speed, BulletField.ORB)
		"twin":
			ebullet(from + Vector2(-26, 30), PI * 0.5, speed * 1.08, BulletField.DART, 18.0)
			ebullet(from + Vector2(26, 30), PI * 0.5, speed * 1.08, BulletField.DART, 18.0)
		"fan":
			for i in range(5):
				ebullet(from + Vector2(0, 80), aim + (float(i) - 2.0) * 0.2, speed * 0.95, BulletField.DART)
		"lance":
			for i in range(5):
				after(float(i) * 0.09, _lance_shot.bind(e, aim))
		"bomb":
			for side in [-0.32, 0.0, 0.32]:
				ebullet(from + Vector2(0, 50), PI * 0.5 + float(side), speed * 0.6, BulletField.HEAVY, 30.0)
		"broadside":
			for i in range(5):
				ebullet(from + Vector2((float(i) - 2.0) * 44.0, 30), PI * 0.5, speed * 0.9, BulletField.DART)
		"spawn":
			for side in [-1.0, 1.0]:
				spawn_enemy({"kind": "swarmlet", "pos": from + Vector2(side * 60.0, 50.0), "move": "swarm", "vel": Vector2(side * 80.0, 190.0)})
			Audio.play("hatch", -9.0, 1.3)
			return
		"elite":
			for i in range(14):
				ebullet(from + Vector2(0, 40), float(i) * TAU / 14.0 + t, speed * 0.8, BulletField.ORB)
			after(0.45, _elite_followup.bind(e))
	Audio.play("enemy_shoot", -12.0, 1.0, 0.1)

func _lance_shot(e: Dictionary, aim: float) -> void:
	if e.dead:
		return
	ebullet((e.pos as Vector2) + Vector2.from_angle(aim) * 60.0, aim, 400.0 * float(scale_cfg.bullet) * bullet_mult, BulletField.SHARD, 20.0)

func _elite_followup(e: Dictionary) -> void:
	if e.dead or not player_alive:
		return
	var from: Vector2 = e.pos
	var aim: float = (player_pos - from).angle()
	for i in range(3):
		ebullet(from + Vector2(0, 80), aim + (float(i) - 1.0) * 0.16, 330.0 * float(scale_cfg.bullet) * bullet_mult, BulletField.DART)

func ebullet(at: Vector2, angle: float, speed: float, kind: int, damage := 24.0) -> void:
	field.add(at, Vector2.from_angle(angle) * speed, kind, damage)

## `wpn` is the weapon that hit ("" for effects like arcs and Nova), used only to choose how the hit looks and sounds.
func _hit_enemy(e: Dictionary, damage: float, at: Vector2, crit_hit: bool, secondary := false, wpn := "") -> void:
	if e.dead or e.ghost or e.ally:
		return
	e.idle = 0.0
	var power := clampf(damage / 1.1, 0.7, 2.0) * (1.25 if crit_hit else 1.0)
	if float(e.eshield) > 0.0:
		e.eshield -= damage
		if not secondary:
			fx.ripple(e, float(e.r) * 1.3, at, power, ShieldFx.COLOR)
			fx.impact(at, wpn if wpn != "" else "pulse", power, "shield")
			CombatAudio.impact(wpn, "shield", power)
		if float(e.eshield) <= 0.0:
			fx.shield_break(e.pos, float(e.r) * 1.3, ShieldFx.COLOR)
			CombatAudio.shield("break")
		return
	e.hp -= damage
	var sprite: Sprite2D = e.sprite
	sprite.material = hue_mat(0.0, true)
	e.flash = 0.06
	if not secondary:
		if float(s.burn) > 0.0:
			e.burn = 2.0
		if float(s.cryo) > 0.0:
			e.slow = 1.2
			e.cryo_hits = int(e.cryo_hits) + 1
			if float(s.zero) > 0.0 and int(e.cryo_hits) >= 4 and not e.heavy:
				e.cryo_hits = 0
				e.frozen = 1.6
		if float(s.arc) > 0.0 and randf() < float(s.arc):
			_arc_from(e.pos, 2, damage)
	if float(e.hp) <= 0.0:
		_kill_enemy(e, true)
	elif not secondary and wpn != "missile":
		# A missile's hit is drawn and heard by its blast (_splash). Everything else shows its own weapon's impact.
		fx.impact(at, wpn if wpn != "" else "pulse", power)
		if crit_hit:
			fx.sparks(at, 3, UI.GOLD, 220.0, 0.2, 9.0)
		CombatAudio.impact(wpn, "hull", power)

func _kill_enemy(e: Dictionary, by_player: bool) -> void:
	if e.dead:
		return
	e.dead = true
	var pos: Vector2 = e.pos
	var kind: String = e.kind
	var size: float = e.size
	kills += 1
	if e.ally:
		tracker.escort_ok = false
		hud.coach("The hauler was lost", 2.5)
		CombatAudio.explosion("medium", size)
		fx.explode(pos, "medium", size, "fire")
		return
	if by_player:
		combo += 1
		best_combo = maxi(best_combo, combo)
		combo_timer = 2.8
		Meta.peak("best_combo", combo)
		if combo in [10, 25, 50, 100, 150]:
			hud.combo_milestone(combo)
		var value := int(float(e.score) * float(1 + combo / 10) * score_mult)
		score += value
		if e.heavy or combo % 10 == 0:
			fx.text("+%d" % value, pos, 30, UI.GOLD)
		add_energy(16.0 if e.heavy else 2.6)
		_drop_loot(e)
		Meta.count("kill")
		if kind.begins_with("rock"):
			Meta.count("kill_rock")
		elif kind == "fighter":
			Meta.count("kill_fighter")
		elif kind == "treasure":
			Meta.count("kill_treasure")
		if e.heavy:
			Meta.count("kill_heavy")
			roll_loot(0.1, 0.0, 0, 0, pos)
		elif not str(e.mod).is_empty():
			roll_loot(0.18, 0.0, 0, 0, pos)
		if kind == "wreck":
			tracker.wrecks = int(tracker.wrecks) + 1
		elif kind == "tank":
			tracker.tanks = int(tracker.tanks) + 1
		elif kind == "husk":
			tracker.husks = int(tracker.husks) + 1
	if e.volatile or (float(s.inferno) > 0.0 and float(e.burn) > 0.0):
		_explosion(pos, 170.0 if e.volatile else 120.0, 10.0 if e.volatile else 3.0 * shot_power(), e.id)
	_destruction_fx(e, pos, size)
	if kind == "rock_l":
		for side in [-1.0, 1.0]:
			spawn_enemy({"kind": "rock_s", "pos": pos + Vector2(side * 26.0, 0), "move": "straight", "vel": Vector2(side * 110.0, 170.0 * float(scale_cfg.speed))})
	elif kind == "mine":
		var count := 8 + int(float(scale_cfg.d) * 4.0)
		for i in range(count):
			ebullet(pos, float(i) * TAU / float(count) + 0.2, 215.0 * float(scale_cfg.bullet) * bullet_mult, BulletField.ORB, 20.0)
		Audio.play("explode_m", -4.0, 1.2)
		fx.ring(pos, 0.35, 20.0, 170.0, UI.MAGENTA, 6.0)
	if e.revive:
		spawn_enemy({"kind": "husk", "pos": pos, "move": "drift", "vel": Vector2(0, 26.0)})
	if str(e.mod) == "volatile":
		for i in range(12):
			ebullet(pos, float(i) * TAU / 12.0, 240.0 * float(scale_cfg.bullet), BulletField.DART, 20.0)

func _destruction_fx(e: Dictionary, pos: Vector2, size: float) -> void:
	var kind: String = e.kind
	var tier := Fx.tier_for(e.heavy, size)
	var palette := "fire"
	if kind.begins_with("rock") or kind == "wreck":
		# Rock breaks into grey chips: keep the rock's own crunch and a smaller burst.
		palette = "rock"
		tier = "small" if size < 130.0 else "medium"
		Audio.play("rock", -6.0, 1.3 - size / 300.0, 0.1)
	elif kind in ["pod", "swarmlet", "brood"]:
		palette = "energy"
		if tier == "heavy":
			CombatAudio.explosion("heavy", size)
		else:
			Audio.play("hatch", -9.0, 1.4, 0.15)
	elif kind in ["husk", "revenant", "sentinel"]:
		palette = "ice"
		Audio.play("ice", -5.0, 1.0, 0.15)
	elif kind == "mine":
		pass  # silent here: _kill_enemy plays the mine's own blast with its burst of bullets, so it is heard once
	else:
		CombatAudio.explosion(tier, size)
	fx.explode(pos, tier, size, palette)
	kick(float(Fx.TIERS[tier].kick))
	if tier == "heavy":
		if not Save.opt.reduced_motion:
			hitstop = 0.05
		Save.haptic(40)

func _explosion(pos: Vector2, radius: float, damage: float, skip_id: int) -> void:
	CombatAudio.explosion("medium", radius)
	fx.explode(pos, "medium", radius * 1.1, "fire")
	fx.ring(pos, 0.3, 30.0, radius, UI.ORANGE, 6.0)
	kick(8.0)
	for e in enemies:
		if e.dead or e.id == skip_id or e.ally:
			continue
		if pos.distance_squared_to(e.pos) < radius * radius:
			_hit_enemy(e, damage, e.pos, false, true)
	if player_alive and pos.distance_to(player_pos) < radius * 0.72:
		hurt_player(26.0)

func _drop_loot(e: Dictionary) -> void:
	var chance: float = e.drop
	if randf() > chance and not e.treasure:
		return
	if not Save.tutorial_seen("crystal"):
		Save.mark_tutorial("crystal")
		hud.coach("Crystals buy permanent upgrades in the Hangar", 4.0)
	var count := 1
	if e.heavy or e.cover:
		count = 4
	if e.treasure:
		count = 12
	elif str(e.kind) == "pod":
		count = 3
	for i in range(count):
		var v := Vector2(randf_range(-110.0, 110.0), randf_range(-160.0, -50.0)) if count > 1 else Vector2(randf_range(-30.0, 30.0), -40.0)
		pickups.append({"pos": e.pos, "vel": v, "value": 2 if count == 1 else 3, "spin": randf_range(0.0, TAU), "pull": false})

func _update_pickups(dt: float) -> void:
	var reach: float = float(s.magnet)
	for i in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[i]
		p.spin += dt * 3.0
		var pos: Vector2 = p.pos
		var dist := pos.distance_to(player_pos)
		if player_alive and (p.pull or dist < reach):
			var dir: Vector2 = (player_pos - pos).normalized()
			p.vel = (p.vel as Vector2).lerp(dir * 900.0, 1.0 - exp(-dt * 7.0))
		else:
			p.vel = (p.vel as Vector2).lerp(Vector2(0, 150), 1.0 - exp(-dt * 1.6))
		p.pos += p.vel * dt
		if player_alive and dist < 48.0:
			_collect(p, pos)
			pickups.remove_at(i)
		elif float(p.pos.y) > H + 40.0:
			pickups.remove_at(i)

func _collect(p: Dictionary, pos: Vector2) -> void:
	var value: float = float(p.value) * float(s.salvage_mult) * float(tier_cfg.salvage)
	if str(ship.trait) == "FINDERS KEEPERS":
		value *= 1.5
		crystal_count += 1
		if crystal_count % 10 == 0:
			surge_t = 3.0
			fx.text("SURGE", player_pos + Vector2(0, -80), 30, UI.GOLD)
			Audio.play("powerup", -8.0, 1.3)
	if float(s.midas) > 0.0:
		midas_stacks = mini(60, midas_stacks + 1)
	run_salvage += int(ceil(value))
	tracker.crystals = int(tracker.crystals) + 1
	add_energy(3.0)
	Meta.count("crystal")
	Audio.play("pickup", -9.0, 1.0 + minf(0.5, float(combo) * 0.01), 0.04)
	fx.sparks(pos, 4, UI.MINT, 120.0, 0.25, 9.0)

func _attract_all() -> void:
	for p in pickups:
		p.pull = true

func _on_wave_cleared() -> void:
	clear_wait = -1.0
	Audio.play("wave_clear", -3.0)
	if mode == "endless":
		if level.boss and boss == null and not boss_done:
			_begin_warning()
			return
		boss_done = false
		_begin_upgrade()
		return
	if wave_index + 1 < (level.waves as Array).size():
		_begin_upgrade()
	elif level.boss and boss == null and not boss_done:
		_begin_warning()
	else:
		_level_complete()

# ---------- Bosses ----------

func _begin_warning() -> void:
	phase = Phase.WARNING
	phase_t = 0.0
	Audio.stop_music(0.5)
	Audio.play("warning")
	Save.haptic(60)
	var def: Dictionary = Bosses.LIST[int(level.boss_id) - 1]
	hud.banner_show("WARNING", str(def.name), 2.2, UI.RED)

func _spawn_boss() -> void:
	var index: int = int(level.boss_id) - 1
	var b = BOSS_SCRIPTS[index].new()
	var hp_scale := hp_mult
	if mode == "endless":
		hp_scale *= 0.45 + float(endless_wave) * 0.08
	elif mode == "expedition":
		hp_scale *= 0.8
	b.setup(self, Bosses.LIST[index], hp_scale)
	boss = b
	phase = Phase.BOSS_INTRO
	phase_t = 0.0
	Audio.music("boss", 0.3)
	Meta.discover("boss_%d" % (index + 1))
	hud.boss_intro(Bosses.LIST[index])

func on_boss_destroyed() -> void:
	var sector_num: int = level.sector
	score += int(1000.0 * float(sector_num) * score_mult)
	var pos: Vector2 = boss.pos
	for i in range(14):
		pickups.append({"pos": pos + Vector2(randf_range(-120.0, 120.0), randf_range(-50.0, 50.0)), "vel": Vector2.from_angle(randf() * TAU) * 240.0, "value": 4, "spin": 0.0, "pull": true})
	Meta.count("boss")
	Meta.unique("boss_unique", sector_num)
	_boss_loot(sector_num)
	if hull_lost == 0:
		Meta.count("boss_flawless")
	# Queued attacks may still point at the boss, so it stays alive until the flight ends.
	fallen_bosses.append(boss)
	boss = null
	boss_done = true
	if mode == "endless":
		Audio.music_layered(str(Levels.SECTORS[sector_num - 1].music), 1.0)
	phase = Phase.PLAYING
	phase_t = 0.0
	group_queue.clear()
	clear_wait = 1.8
	_attract_all()

# ---------- Modules ----------

func _begin_upgrade() -> void:
	var count := maxi(2, 3 + Save.upgrade_level("extra_card") - danger_cards_minus)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	card_options = Cards.offer(held, Save.blueprints, rng, count, hull < max_hull, 0.5 * float(Save.upgrade_level("lucky")))
	if card_options.is_empty():
		_after_card()
		return
	if not Save.tutorial_seen("card"):
		hud.coach("Modules last for this level. Pair the right two and they evolve", 6.0)
	phase = Phase.UPGRADE
	phase_t = 0.0
	card_picked = -1
	input_lock = 0.45
	Audio.play("card_in")
	var tree := get_tree()
	if tree:
		tree.create_timer(0.1).timeout.connect(func() -> void: Audio.play("card_in", 0.0, 1.1))
		tree.create_timer(0.2).timeout.connect(func() -> void: Audio.play("card_in", 0.0, 1.2))

func select_card(index: int) -> void:
	if phase != Phase.UPGRADE or card_picked >= 0 or input_lock > 0.0 or index >= card_options.size():
		return
	card_picked = index
	input_lock = 0.34
	var c: Dictionary = Cards.LIST[card_options[index]]
	Audio.play("evolve" if int(c.rarity) == Cards.EVOLVED else "card_pick")
	Audio.play("powerup", -5.0)
	Save.haptic(30)

func reroll_cards() -> void:
	if phase != Phase.UPGRADE or rerolls <= 0 or card_picked >= 0:
		return
	rerolls -= 1
	if rerolls < mini(Save.reroll_tokens, 1):
		Save.reroll_tokens = maxi(0, Save.reroll_tokens - 1)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fresh := Cards.offer(held, Save.blueprints, rng, card_options.size(), hull < max_hull, 0.5 * float(Save.upgrade_level("lucky")))
	if not fresh.is_empty():
		card_options = fresh
	phase_t = 0.0
	input_lock = 0.3
	Audio.play("card_in")

func _install_card() -> void:
	var id: String = card_options[card_picked]
	var c: Dictionary = Cards.LIST[id]
	held[id] = int(held.get(id, 0)) + 1
	Save.mark_tutorial("card")
	var before_shield := max_shield
	_recompute()
	if id == "plating":
		shield = max_shield
	elif max_shield > before_shield:
		shield += max_shield - before_shield
	if str(c.get("instant", "")) == "repair":
		hull = mini(max_hull, hull + 1)
		Audio.play("repair", -2.0)
	if int(c.rarity) == Cards.EVOLVED:
		Meta.count("evolve")
		Meta.unique("evolve_unique", id)
		hud.banner_show(str(c.name), "MODULE EVOLVED", 1.8, UI.GOLD)
		do_flash(0.4, UI.GOLD)
	var color: Color = Cards.RARITY_COLORS[int(c.rarity)]
	fx.ring(player_pos, 0.5, 30.0, 220.0, color, 6.0)
	fx.sparks(player_pos, 20, color, 260.0, 0.5, 14.0)
	card_picked = -1
	_after_card()

func _after_card() -> void:
	if mode == "endless":
		_rift_floor_cleared(endless_wave)
		endless_wave += 1
		Meta.peak("endless_wave", endless_wave)
		level = Levels.build_endless(endless_wave)
		scale_cfg = level.scale
		_apply_mutators()
		_recompute()
		_start_wave(0)
	else:
		_start_wave(wave_index + 1)

# ---------- Loot, tiers and the Rift ----------

func _apply_mutators() -> void:
	mutators = base_mutators.duplicate()
	for id in level.get("mutators", []):
		if not id in mutators:
			mutators.append(id)
	score_mult = Mutators.multiplier(mutators)
	bullet_mult = Mutators.value(mutators, "bullet", 1.0) * float(tier_cfg.bullet)
	hp_mult = Mutators.value(mutators, "hp", 1.0) * float(tier_cfg.hp)
	fire_mult_enemy = Mutators.value(mutators, "fire", 1.0) * float(tier_cfg.fire)
	count_mult = Mutators.value(mutators, "count", 1.0) * float(tier_cfg.count)
	elite_chance = maxf(0.25 if Mutators.flag(mutators, "elites") else 0.0, float(tier_cfg.elite))
	_apply_danger()

## Danger Contracts change the run, never the rules of the game: stats are nudged within ceilings
## so a contract on top of a dial or tier can not push the same stat out of reach.
func _apply_danger() -> void:
	danger_rewards = Danger.rewards(danger)
	danger_hull = int(Danger.fx_sum(danger, "hull_add"))
	danger_pace = Danger.fx_product(danger, "pace")
	danger_regen = Danger.fx_product(danger, "regen")
	danger_cards_minus = int(Danger.fx_sum(danger, "cards_minus"))
	danger_no_reroll = Danger.fx_flag(danger, "no_reroll")
	nova_sealed = Danger.fx_flag(danger, "nova_off")
	bullet_mult = minf(bullet_mult * Danger.fx_product(danger, "bullet"), maxf(bullet_mult, Danger.BULLET_CEILING))
	fire_mult_enemy = minf(fire_mult_enemy * Danger.fx_product(danger, "fire"), maxf(fire_mult_enemy, Danger.FIRE_CEILING))
	elite_chance = maxf(elite_chance, Danger.fx_max(danger, "elite"))

## Pays the contracts once: after a win, or in the Rift once enough floors are behind you.
## A loss pays nothing extra and costs nothing extra.
func _pay_danger() -> void:
	if danger.is_empty() or not danger_paid.is_empty():
		return
	danger_paid = danger_rewards.duplicate(true)
	run_salvage += int(float(run_salvage) * float(danger_paid.salvage))
	if mode != "endless":
		for roll in danger_paid.rolls:
			_danger_roll(roll)
	Danger.record_win(danger, mode)
	var lines: Array = Danger.summary_lines(danger)
	rewards.insert(0, {"title": "DANGER BONUS", "detail": ", ".join(lines)})

func _danger_roll(roll: Dictionary) -> void:
	roll_loot(1.0, float(roll.get("luck", 0.0)), int(roll.min), int(level.sector) if bool(roll.get("boss", false)) else 0)
## How strong the gear dropped by this flight is.
func loot_power() -> float:
	var p := 1.0
	match mode:
		"endless":
			p = 1.0 + float(endless_wave) * 0.8
		"expedition":
			p = 1.0 + float((int(level.sector) - 1) * 3 + int(Save.expedition.get("layer", 0)))
		_:
			p = 1.0 + float(mini(level_num, Levels.LEVEL_COUNT)) / 6.0
	return p + float(tier_cfg.loot)

func loot_luck() -> float:
	return float(tier_cfg.luck) + (float(endless_wave) / 10.0 if mode == "endless" else 0.0) + float(danger_rewards.get("luck", 0.0))

func add_loot(item: Dictionary, at := Vector2.ZERO) -> void:
	loot.append(item)
	var color: Color = Gear.RARITY_COLORS[int(item.rarity)]
	var pos := at if at != Vector2.ZERO else player_pos + Vector2(0, -130)
	fx.text("GEAR  " + str(Gear.RARITY_NAMES[int(item.rarity)]), pos, 26, color)
	Audio.play("unlock", -8.0)
	if int(item.rarity) >= Gear.EPIC:
		fx.ring(pos, 0.5, 30.0, 200.0, color, 6.0)
		Save.haptic(30)
	if not Save.tutorial_seen("gear"):
		Save.mark_tutorial("gear")
		hud.coach("You found gear! Equip it in the Hangar", 4.5)

func roll_loot(chance: float, luck_bonus := 0.0, min_rarity := 0, boss_sector := 0, at := Vector2.ZERO) -> bool:
	if loot_rng.randf() > chance:
		return false
	add_loot(Gear.roll_item(loot_rng, loot_power(), loot_luck() + luck_bonus, min_rarity, boss_sector), at)
	return true

## Bosses are the best farm: guaranteed gear, and their own legendary perks are likelier.
func _boss_loot(sector_num: int) -> void:
	roll_loot(1.0, 1.5, Gear.RARE, sector_num)
	roll_loot(0.6, 3.0, Gear.UNCOMMON, sector_num)
	roll_loot(0.25, 3.0, Gear.RARE, sector_num)

func _clear_loot(had_clear: bool) -> void:
	match mode:
		"campaign", "side":
			roll_loot(1.0)
			if not had_clear:
				roll_loot(1.0, 0.5, Gear.UNCOMMON)
				if tier > 0:
					roll_loot(1.0, 1.0, Gear.RARE)
			if mode == "side":
				roll_loot(1.0, 1.0, Gear.RARE)
		"daily":
			roll_loot(1.0, 0.5)
		"weekly":
			roll_loot(1.0, 1.5, Gear.EPIC)
		"expedition":
			var kind := str((Save.expedition.get("current", {}) as Dictionary).get("type", "battle"))
			match kind:
				"elite":
					roll_loot(1.0, 1.0, Gear.UNCOMMON)
					roll_loot(0.5, 1.0, Gear.RARE)
				"boss":
					roll_loot(1.0, 2.0, Gear.EPIC, int(level.sector))
				_:
					roll_loot(0.6)

func _rift_floor_cleared(floor_n: int) -> void:
	rift_floors += 1
	Meta.count("rift_floor")
	Meta.peak("rift_floor_best", floor_n)
	run_salvage += 6 + floor_n * 2
	if floor_n % 5 != 0:
		roll_loot(0.22)
	elif not floor_n in Save.rift_claimed:
		Save.rift_claimed.append(floor_n)
		var min_r: int = Gear.RARE if floor_n < 15 else Gear.EPIC
		if floor_n >= 25 and loot_rng.randf() < 0.5:
			min_r = Gear.LEGENDARY
		if floor_n >= 50:
			min_r = Gear.LEGENDARY
		add_loot(Gear.roll_item(loot_rng, loot_power(), 2.0, min_r, (floor_n - 1) / 5 % Levels.SECTOR_COUNT + 1))
		var extra_parts: int = 20 * (floor_n / 5)
		bonus_parts += extra_parts
		bonus_xp += 50 * (floor_n / 5)
		rewards.append({"title": "RIFT FLOOR %d" % floor_n, "detail": "Milestone: gear and +%d parts" % extra_parts})
	if floor_n % 5 == 0 and not danger.is_empty() and not (danger_rewards.rolls as Array).is_empty():
		_danger_roll((danger_rewards.rolls as Array)[0])
		hud.banner_show("RIFT MILESTONE", "Floor %d cleared" % floor_n, 1.6, UI.GOLD)

## Pays out everything a flight earned: gear, parts and pilot XP.
func _commit_loot() -> void:
	for item in loot:
		item["kept"] = Save.add_gear(item)
		# A free slot fills itself, so a new pilot feels the gear straight away.
		if bool(item.kept) and Save.equipped_uid(ship_id, str(item.slot)) == 0:
			Save.equip(ship_id, int(item.uid))
		Meta.count("gear_found")
		if int(item.rarity) == Gear.LEGENDARY:
			Meta.count("legendary")
	var earned_parts: int = 2 + kills / 12 + (6 if result_win else 0) + bonus_parts
	earned_parts = int(float(earned_parts) * float(tier_cfg.xp) * (1.0 + float(danger_paid.get("parts", 0.0))))
	Save.parts += earned_parts
	result_parts = earned_parts
	var xp: int = kills + int(score / 60) + bonus_xp + rift_floors * 8
	if result_win:
		xp += 30 + mini(level_num, Levels.LEVEL_COUNT) / 2
	if boss_done:
		xp += 100
	xp = int(float(xp) * float(tier_cfg.xp) * (1.0 + float(danger_paid.get("xp", 0.0))))
	result_pilot_xp = xp
	pilot_before = Pilot.level_of(Save.pilot_xp)
	var grant := Pilot.grant(xp)
	pilot_after = Pilot.level_of(Save.pilot_xp)
	for r in grant.rewards:
		rewards.append(r)
	for it in grant.items:
		loot.append(it)

func _tier_unlock() -> void:
	if mode == "campaign" and level_num == Levels.LEVEL_COUNT and Save.unlock_tier_after(tier):
		rewards.append({"title": "TIER UNLOCKED", "detail": str(Tiers.cfg(tier + 1).name)})

# ---------- Endings ----------

func _bank() -> void:
	if banked:
		return
	banked = true
	if mode == "endless" and rift_floors >= Danger.RIFT_MIN_FLOORS:
		_pay_danger()
	Save.salvage += run_salvage
	_commit_loot()
	result_xp = int(float(score) * 0.05) + kills
	var before := Save.ship_mastery(ship_id)
	Save.mastery[ship_id] = Save.ship_xp(ship_id) + result_xp
	for lvl in range(before + 1, Save.ship_mastery(ship_id) + 1):
		var reward: Dictionary = Ships.MASTERY.get(lvl, {})
		if not reward.is_empty():
			rewards.append({"title": "%s MASTERY %d" % [str(ship.name), lvl], "detail": str(reward.text)})
	Meta.sync_collection_stats()
	Save.save_data()

func objective_done() -> bool:
	var obj: Array = level.get("obj", [])
	if obj.is_empty():
		return false
	var n := int(obj[1])
	match str(obj[0]):
		"crystals":
			return int(tracker.crystals) >= n
		"combo":
			return best_combo >= n
		"time":
			return flight_time <= float(n)
		"wrecks":
			return int(tracker.wrecks) >= n
		"ember":
			return float(tracker.ember) >= float(n)
		"tanks":
			return int(tracker.tanks) >= n
		"nohatch":
			return int(tracker.hatched) == 0
		"husks":
			return int(tracker.husks) >= n
		"shield":
			return not tracker.shield_broke
		"escort":
			return bool(tracker.escort_ok) and bool(tracker.escort_seen)
	return false

func objective_progress() -> String:
	var obj: Array = level.get("obj", [])
	if obj.is_empty():
		return ""
	var n := int(obj[1])
	match str(obj[0]):
		"crystals":
			return "%d/%d" % [tracker.crystals, n]
		"combo":
			return "%d/%d" % [best_combo, n]
		"time":
			return "%ds" % maxi(0, n - int(flight_time))
		"wrecks":
			return "%d/%d" % [tracker.wrecks, n]
		"ember":
			return "%d/%d" % [int(tracker.ember), n]
		"tanks":
			return "%d/%d" % [tracker.tanks, n]
		"husks":
			return "%d/%d" % [tracker.husks, n]
	return ""

func _level_complete() -> void:
	if phase == Phase.CLEAR:
		return
	phase = Phase.CLEAR
	phase_t = 0.0
	result_win = true
	field.clear()
	input_lock = 1.0
	stars_shown = 0
	result_mask = 1
	if hull_lost == 0:
		result_mask |= 2
	if objective_done():
		result_mask |= 4
	var star_count := (result_mask & 1) + ((result_mask >> 1) & 1) + ((result_mask >> 2) & 1)
	result_reward = int(float(int(level.reward) * (2 + star_count) / 3) * score_mult * float(tier_cfg.salvage))
	Meta.count("clear")
	if hull_lost == 0:
		Meta.count("flawless")
	if not mutators.is_empty():
		Meta.count("mutated_clear")
	if "brittle" in mutators:
		Meta.count("brittle_clear")
	var had_clear := false
	if mode in ["campaign", "side"]:
		had_clear = Save.mask_at(tier, level_num) > 0
	_clear_loot(had_clear)
	match mode:
		"campaign", "side":
			var was := Save.stars_at(tier, level_num)
			Save.record_level(level_num, result_mask, score, tier)
			new_best = Save.stars_at(tier, level_num) > was
			if mode == "side":
				if not level_num in Save.side_cleared:
					Save.side_cleared.append(level_num)
				if Save.add_blueprint(str(level.side_reward)):
					rewards.append({"title": "BLUEPRINT FOUND", "detail": Levels.BLUEPRINT_NAMES[level.side_reward]})
			elif not had_clear and tier == 0:
				_first_clear_rewards()
			Save.map_sector = Levels.sector_of(mini(level_num + 1, Levels.LEVEL_COUNT))
			_tier_unlock()
		"daily", "weekly":
			if Meta.record_challenge(mode, score):
				var bonus := int(Save.session.get("reward", 100))
				result_reward += bonus
				rewards.append({"title": "CHALLENGE COMPLETE", "detail": "+%d bonus salvage" % bonus})
		"expedition":
			Expedition.on_node_cleared(self)
	run_salvage += result_reward
	_pay_danger()
	_bank()
	Telemetry.log_event("flight_end", {"win": true, "mode": mode, "level": level_num, "time": int(flight_time), "hull_lost": hull_lost, "score": score, "salvage": run_salvage, "stars": star_count, "cards": held.keys()})
	Audio.music("stinger_win", 0.2, false)

func _first_clear_rewards() -> void:
	if level.boss:
		var r: Dictionary = Levels.BOSS_REWARDS[int(level.sector)]
		if not int(level.sector) in Save.bosses_beaten:
			Save.bosses_beaten.append(int(level.sector))
		for bp in r.blueprints:
			if Save.add_blueprint(bp):
				rewards.append({"title": "BOSS BLUEPRINT", "detail": Levels.BLUEPRINT_NAMES[bp]})
		if int(level.sector) < Levels.SECTOR_COUNT:
			rewards.append({"title": "SECTOR UNLOCKED", "detail": str(Levels.SECTORS[int(level.sector)].name)})
	if level_num == Levels.ENDLESS_UNLOCK - 1:
		rewards.append({"title": "MODE UNLOCKED", "detail": "ENDLESS"})
	elif level_num == Levels.EXPEDITION_UNLOCK - 1:
		rewards.append({"title": "MODE UNLOCKED", "detail": "EXPEDITION"})
	elif level_num == 2:
		rewards.append({"title": "HANGAR OPEN", "detail": "Spend salvage on upgrades"})

func _update_result_stars() -> void:
	var earned := (result_mask & 1) + ((result_mask >> 1) & 1) + ((result_mask >> 2) & 1)
	var due := int((phase_t - 0.7) / 0.38) + 1
	if phase_t > 0.7 and stars_shown < mini(due, earned):
		stars_shown += 1
		Audio.play("star_%d" % stars_shown)
		Save.haptic(20)

func _show_defeat() -> void:
	if phase == Phase.DEFEAT or phase == Phase.CLEAR:
		return
	phase = Phase.DEFEAT
	phase_t = 0.0
	result_win = false
	input_lock = 0.8
	run_salvage += int(level.reward) / 4
	if mode == "endless":
		new_best = endless_wave > Save.endless_best_wave
		Save.endless_best_wave = maxi(Save.endless_best_wave, endless_wave)
		Meta.peak("endless_wave", endless_wave)
	elif mode == "expedition":
		Expedition.on_run_lost()
	Save.best_score = maxi(Save.best_score, score)
	_bank()
	if not danger.is_empty() and danger_paid.is_empty():
		rewards.append({"title": "CONTRACT NOT COMPLETED", "detail": "Nothing was lost. Try again any time."})
	Telemetry.log_event("flight_end", {"win": false, "mode": mode, "level": level_num, "time": int(flight_time), "score": score, "wave": wave_index, "cards": held.keys()})
	Audio.music("stinger_lose", 0.2, false)

func set_paused(on: bool) -> void:
	if on:
		if phase in [Phase.CLEAR, Phase.DEFEAT, Phase.PAUSED, Phase.UPGRADE, Phase.RESUME]:
			return
		previous_phase = phase
		phase = Phase.PAUSED
		Audio.set_muffled(true)
		input_lock = 0.1
		drag_finger = -1
		Save.save_data()
	elif phase == Phase.PAUSED:
		# A short countdown so nobody gets hit the moment they unpause.
		phase = Phase.RESUME
		resume_t = 0.9
		Audio.play("ui_click")

func _leave(scene: String) -> void:
	Audio.set_muffled(false)
	_bank()
	Fade.go(scene)

func _on_ui(id: String) -> void:
	if input_lock > 0.0 and not id in ["pause", "burst"]:
		return
	match id:
		"pause":
			set_paused(true)
		"burst":
			try_nova()
		"resume":
			set_paused(false)
		"retry":
			_leave("res://game.tscn")
		"next":
			Save.session.level = mini(level_num + 1, Levels.LEVEL_COUNT)
			Save.session.mutators = []
			Save.session.danger = []
			_leave("res://game.tscn")
		"map":
			if mode in ["campaign", "side"]:
				Save.menu_screen = "map"
			elif mode == "expedition":
				Save.menu_screen = "expedition"
			elif mode in ["daily", "weekly"]:
				Save.menu_screen = "ops"
			else:
				Save.menu_screen = "title"
			Audio.music("menu")
			_leave("res://title_screen.tscn")
		"hangar":
			Save.menu_screen = "hangar"
			Audio.music("menu")
			_leave("res://title_screen.tscn")
		"music":
			Save.opt.music_volume = 0.0 if float(Save.opt.music_volume) > 0.0 else 0.8
			Audio.apply_volumes()
			Save.save_data()
		"sound":
			Save.opt.sfx_volume = 0.0 if float(Save.opt.sfx_volume) > 0.0 else 1.0
			Audio.apply_volumes()
			Save.save_data()
		"reroll":
			reroll_cards()
		"card0", "card1", "card2", "card3":
			select_card(int(id.substr(4)))

func _notification(what: int) -> void:
	if Save.test_mode or hud == null:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_paused(true)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		set_paused(phase != Phase.PAUSED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_P:
				set_paused(phase != Phase.PAUSED)
			KEY_SPACE:
				try_nova()
			KEY_1, KEY_2, KEY_3, KEY_4:
				select_card(event.keycode - KEY_1)
			KEY_R:
				if phase in [Phase.CLEAR, Phase.DEFEAT]:
					_on_ui("retry")
			KEY_ENTER:
				if phase == Phase.CLEAR:
					_on_ui("next" if level_num < Levels.LEVEL_COUNT and mode == "campaign" else "map")
				elif phase == Phase.DEFEAT:
					_on_ui("retry")
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if drag_finger < 0:
				drag_finger = event.index
			if Save.opt.nova_double_tap and t - last_tap < 0.28:
				try_nova()
			last_tap = t
		elif event.index == drag_finger:
			drag_finger = -1
	elif event is InputEventScreenDrag and event.index == drag_finger:
		if phase in COMBAT_PHASES or phase == Phase.BOSS_INTRO:
			# Relative steering: the ship follows the thumb without sitting under it.
			player_target += event.relative * float(Save.opt.sensitivity)
			touch_moved += event.relative.length()
			clamp_target()

# ---------- World painting ----------

func _fill_batches() -> void:
	var outline: bool = Save.opt.bullet_outline
	var size_k: float = float(Save.opt.bullet_size)
	bullet_glow.begin()
	bullet_core.begin()
	for b in bullet_batches:
		b.begin()
	for i in range(field.count):
		var k: int = field.kind[i]
		var def: Dictionary = BulletField.KINDS[k]
		var at := field.pos[i]
		var size: float = float(def.size) * size_k
		var halo: Color = def.halo
		if Save.opt.colorblind:
			# Shapes already differ. This swaps magenta and orange for blue and yellow.
			halo = Color(0.3, 0.6, 1.0) if k == BulletField.ORB else (Color(1.0, 0.9, 0.2) if k == BulletField.DART else halo)
		bullet_glow.add(at, size * 1.3, 0.0, Color(halo, 0.5))
		var rot: float = t * 3.0 if k == BulletField.HEAVY or k == BulletField.SPORE else field.vel[i].angle() + float(def.rot)
		(bullet_batches[k] as SpriteBatch).add(at, size, rot, Color.WHITE)
		bullet_core.add(at, 16.0 * size_k, 0.0, Color(1, 1, 1, 0.95))
		if outline:
			bullet_core.add(at, 34.0 * size_k, 0.0, Color(1, 1, 1, 0.4))
	bullet_glow.commit()
	bullet_core.commit()
	for b in bullet_batches:
		b.commit()
	shot_batch.begin()
	shot_glow.begin()
	missile_batch.begin()
	for b in shots:
		var color: Color = b.color
		var ang: float = (b.vel as Vector2).angle() + PI * 0.5
		if b.missile:
			missile_batch.add(b.pos, float(b.size), ang, color)
		else:
			shot_batch.add(b.pos, float(b.size), ang, color)
		shot_glow.add(b.pos, 44.0, 0.0, Color(color, 0.3))
	shot_batch.commit()
	shot_glow.commit()
	missile_batch.commit()
	pickup_batch.begin()
	pickup_glow.begin()
	for p in pickups:
		var pulse := 1.0 + sin(t * 8.0 + float(p.spin)) * 0.14
		pickup_glow.add(p.pos, 84.0 * pulse, 0.0, Color(0.3, 0.8, 1.0, 0.5))
		pickup_batch.add(p.pos, 48.0, float(p.spin) * 0.4, Color.WHITE)
	pickup_batch.commit()
	pickup_glow.commit()
	fx.fill_spark_batch(spark_batch)
	fx.fill_ring_batches(ring_thin_batch, ring_thick_batch)
	fx.fill_debris_batch(debris_batch)

func _paint_background(c: DrawLayer) -> void:
	var th := W * 2.0
	var y := fmod(bg_scroll, th) - th
	while y < H:
		c.draw_texture_rect(bg_tex, Rect2(0, y, W, th), false, Color(0.58, 0.58, 0.68))
		y += th
	c.draw_rect(Rect2(0, 0, W, H), Color(0.0, 0.0, 0.03, 0.2))
	for st in stars_bg:
		var depth: float = st.depth
		var twinkle := 0.72 + 0.28 * sin(t * 2.4 + float(st.twinkle))
		var col := Color(0.76, 0.9, 1.0, (0.22 + depth * 0.62) * twinkle)
		var pos: Vector2 = st.pos
		var length := warp * 90.0 * depth
		if length > 1.0:
			c.draw_line(pos, pos - Vector2(0, length), col, 1.0 + depth)
		else:
			c.draw_rect(Rect2(pos, Vector2(1.0, 1.0) * (1.0 + depth * 1.8)), col)

func _paint_fx_add(c: DrawLayer) -> void:
	fx.paint_additive(c)
	if player_alive and phase != Phase.UPGRADE:
		engine_fx.paint(c, player_pos, bank_angle)
		shield_fx.paint(c, player_pos, shield, max_shield)
		if beam_active and phase in COMBAT_PHASES:
			_paint_beam(c)
	for e in enemies:
		if not e.dead and float(e.eshield) > 0.0:
			ShieldFx.paint_enemy(c, e, t)
		if e.heavy:
			UI.glow(c, e.pos, float(e.r) * 2.0, Color(UI.MAGENTA, 0.16 + sin(t * 4.0) * 0.05))
		if float(e.tell) > 0.0:
			var k: float = clampf(1.0 - float(e.tell) / 0.5, 0.0, 1.0)
			UI.glow(c, (e.pos as Vector2) + Vector2(0, float(e.r) * 0.7), 30.0 + 50.0 * k, Color(1.0, 0.4, 0.4, 0.4 + k * 0.5))
	if boss != null:
		boss.paint_add(c)
	hazards.paint_air(c)

func _paint_beam(c: DrawLayer) -> void:
	var width := 15.0 + float(s.pierce) * 7.0
	var core := Color(0.8, 0.6, 1.0).lerp(Color(1.0, 0.95, 1.0), beam_focus)
	for off in _beam_offsets():
		var x: float = player_pos.x + float(off)
		var w: float = (width * (1.0 if off == 0.0 else 0.6)) * (0.8 + beam_focus * 0.6) * (0.92 + 0.08 * sin(t * 50.0))
		var h: float = player_pos.y - 50.0 - beam_top
		c.draw_rect(Rect2(x - w * 1.8, beam_top, w * 3.6, h), Color(0.5, 0.3, 1.0, 0.22))
		c.draw_rect(Rect2(x - w * 0.5, beam_top, w, h), Color(core, 0.95))
		if beam_top > 0.0:
			UI.glow(c, Vector2(x, beam_top), 40.0, Color(0.7, 0.5, 1.0, 0.8))

func _paint_fx_top(c: DrawLayer) -> void:
	fx.paint_top(c)
	for e in enemies:
		if e.dead:
			continue
		if float(e.hatch) > 0.0 and str(e.kind) in ["pod", "husk"]:
			var total := 6.5 if str(e.kind) == "pod" else 3.6
			var k: float = clampf(float(e.hatch) / total, 0.0, 1.0)
			var col: Color = UI.MAGENTA if str(e.kind) == "pod" else UI.CYAN
			c.draw_arc(e.pos, float(e.r) + 14.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, col, 5.0, true)
		if float(e.hp) < float(e.max) and float(e.max) >= 6.0 and not e.ally:
			var size: float = float(e.r) * 1.5
			var at: Vector2 = (e.pos as Vector2) + Vector2(-size * 0.5, -float(e.r) - 16.0)
			c.draw_rect(Rect2(at, Vector2(size, 6)), Color(0, 0, 0, 0.6))
			c.draw_rect(Rect2(at, Vector2(size * clampf(float(e.hp) / float(e.max), 0.0, 1.0), 6)), UI.ORANGE)
		if e.ally:
			var at: Vector2 = (e.pos as Vector2) + Vector2(-75.0, float(e.r) + 18.0)
			c.draw_rect(Rect2(at, Vector2(150.0, 8)), Color(0, 0, 0, 0.6))
			c.draw_rect(Rect2(at, Vector2(150.0 * clampf(float(e.hp) / float(e.max), 0.0, 1.0), 8)), UI.MINT)
		if not str(e.mod).is_empty():
			hud.paint_mod_mark(c, e)
	fx.paint_text(c)
	if player_alive and Save.opt.show_hitbox and field.count > 0 and phase in COMBAT_PHASES:
		c.draw_circle(player_pos, 6.0, Color(1, 1, 1, 0.9))
		c.draw_arc(player_pos, 8.0, 0.0, TAU, 16, Color(1.0, 0.3, 0.5, 0.9), 2.0, true)
