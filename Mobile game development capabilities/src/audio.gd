extends Node
## Sound effects and music. Autoloaded as "Audio".
## Uses its own buses so volume settings, ducking and the pause filter are one call each.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_NAMES := [
	"enemy_shoot", "hit", "crit", "explode_s", "explode_m", "explode_l", "shield_hit",
	"hull_hit", "pickup", "repair", "powerup", "burst", "energy_ready", "ui_click", "ui_back",
	"ui_deny", "ui_buy", "card_in", "card_pick", "star_1", "star_2", "star_3", "wave_start",
	"wave_clear", "warning", "charge", "laser", "mine", "whoosh",
	"missile", "beam", "arc", "clank", "rock", "ice", "hatch", "flame", "well", "combo", "evolve", "unlock",
	# Combat: weapon fire, impacts, shields and the explosion hierarchy (see CombatAudio).
	"fire_plasma", "fire_laser", "fire_scatter", "impact_plasma", "impact_laser", "impact_explosive", "impact_heavy",
	"shield_heavy", "shield_break", "shield_up", "shield_warn", "explode_heavy", "boss_chain", "boss_final",
]
# Shortest gap between repeats, so a screen full of hits never turns into a wall of noise.
const THROTTLE := {
	"hit": 0.045, "crit": 0.07, "enemy_shoot": 0.09, "pickup": 0.05,
	"explode_s": 0.07, "explode_m": 0.1, "mine": 0.12, "beam": 0.09, "clank": 0.08,
	"missile": 0.1, "rock": 0.07, "hatch": 0.08, "ice": 0.09, "arc": 0.1,
	"fire_plasma": 0.07, "fire_laser": 0.06, "fire_scatter": 0.12,
	"impact_plasma": 0.06, "impact_laser": 0.05, "impact_explosive": 0.09, "impact_heavy": 0.09,
	"shield_hit": 0.07, "shield_heavy": 0.2, "shield_break": 0.35, "shield_up": 0.8, "shield_warn": 1.2,
	"explode_heavy": 0.15, "boss_chain": 0.12, "boss_final": 1.0,
}
const POOL_SIZE := 22

# Sounds that compete for the same few voices. When a group is full, a new sound only gets in by being more important
# than one already playing, which it then replaces.
const GROUPS := {
	"fire": ["fire_plasma", "fire_laser", "fire_scatter", "missile", "beam", "enemy_shoot"],
	"impact": ["hit", "crit", "clank", "impact_plasma", "impact_laser", "impact_explosive", "impact_heavy", "arc"],
	"explosion": ["explode_s", "explode_m", "explode_l", "explode_heavy", "boss_chain", "boss_final", "rock", "ice", "hatch"],
	"shield": ["shield_hit", "shield_heavy", "shield_break", "shield_up", "shield_warn"],
}
const GROUP_LIMIT := {"fire": 4, "impact": 5, "explosion": 5, "shield": 3}
# Higher wins. Anything not listed is DEFAULT_PRIORITY.
const PRIORITY := {
	"boss_final": 10, "explode_l": 9, "hull_hit": 9, "shield_break": 8, "burst": 8, "explode_heavy": 7, "boss_chain": 6,
	"explode_m": 5, "shield_heavy": 5, "impact_heavy": 4, "impact_explosive": 4, "shield_hit": 4, "explode_s": 4,
	"hit": 2, "impact_plasma": 2, "impact_laser": 1, "clank": 2, "fire_plasma": 2, "fire_laser": 2, "enemy_shoot": 1, "beam": 1,
}
const DEFAULT_PRIORITY := 3

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _layer: AudioStreamPlayer
var _layer_track := ""
var _intensity := 0.0
var _current := ""
var _music_bus := -1
var _sfx_bus := -1
var _fade: Tween
var _pool_priority := PackedInt32Array()
var _pool_group: Array[String] = []
var _pool_started := PackedFloat64Array()
var _group_of := {}
var _duck_db := 0.0
var _duck_hold := 0.0

## Lets go of every stream when the game closes, so playing sounds do not outlive the audio server.
func _exit_tree() -> void:
	var players: Array = []
	players.append_array(_pool)
	players.append_array([_music_a, _music_b, _layer])
	for p in players:
		if p != null:
			p.stop()
			p.stream = null
	_streams.clear()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_bus = _make_bus("Music")
	_sfx_bus = _make_bus("SFX")
	_add_limiter(_sfx_bus)
	for group in GROUPS:
		for sound in GROUPS[group]:
			_group_of[sound] = group
	var filter := AudioEffectLowPassFilter.new()
	filter.cutoff_hz = 700.0
	AudioServer.add_bus_effect(_music_bus, filter)
	AudioServer.set_bus_effect_enabled(_music_bus, 0, false)
	for sfx_name in SFX_NAMES:
		_streams[sfx_name] = load(SFX_DIR + sfx_name + ".wav")
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
		_pool_priority.append(0)
		_pool_group.append("")
		_pool_started.append(0.0)
	set_process(false)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_layer = _make_music_player()
	apply_volumes()

## A limiter at the end of the SFX bus, so a screen full of explosions can never clip.
func _add_limiter(bus: int) -> void:
	var limiter: AudioEffect = null
	if ClassDB.class_exists("AudioEffectHardLimiter"):
		limiter = ClassDB.instantiate("AudioEffectHardLimiter")
		limiter.ceiling_db = -1.0
		limiter.release = 0.1
	elif ClassDB.class_exists("AudioEffectLimiter"):
		limiter = ClassDB.instantiate("AudioEffectLimiter")
		limiter.ceiling_db = -1.0
	if limiter != null:
		AudioServer.add_bus_effect(bus, limiter)

func _make_bus(bus_name: String) -> int:
	var existing := AudioServer.get_bus_index(bus_name)
	if existing >= 0:
		return existing
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
	return index

func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p

func apply_volumes() -> void:
	var music_db := _to_db(float(Save.opt.music_volume))
	AudioServer.set_bus_volume_db(_music_bus, music_db if music_db <= -79.0 else music_db + _duck_db)
	AudioServer.set_bus_volume_db(_sfx_bus, _to_db(float(Save.opt.sfx_volume)))

func _to_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)

func play(sfx_name: String, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.0) -> void:
	var stream: AudioStream = _streams.get(sfx_name)
	if stream == null:
		return
	var now := Time.get_ticks_msec() * 0.001
	if THROTTLE.has(sfx_name) and now - float(_last.get(sfx_name, -1.0)) < float(THROTTLE[sfx_name]):
		return
	var priority := int(PRIORITY.get(sfx_name, DEFAULT_PRIORITY))
	var group := str(_group_of.get(sfx_name, ""))
	var index := _voice_for(group, priority)
	if index < 0:
		return  # every voice is busy with something at least as important
	_last[sfx_name] = now
	var p := _pool[index]
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.1, pitch + randf_range(-pitch_jitter, pitch_jitter))
	_pool_priority[index] = priority
	_pool_group[index] = group
	_pool_started[index] = now
	p.play()

## Picks the voice a new sound will use, or -1 when it should not play. A full group (see GROUPS) gives up its quietest
## oldest voice only to a more important sound; otherwise a free voice is used, and failing that the least important
## playing voice if the new sound is at least as important.
func _voice_for(group: String, priority: int) -> int:
	if group != "":
		var playing := 0
		var victim := -1
		for i in range(POOL_SIZE):
			if _pool[i].playing and _pool_group[i] == group:
				playing += 1
				if victim < 0 or _pool_priority[i] < _pool_priority[victim] or (_pool_priority[i] == _pool_priority[victim] and _pool_started[i] < _pool_started[victim]):
					victim = i
		if playing >= int(GROUP_LIMIT.get(group, POOL_SIZE)):
			return victim if priority > _pool_priority[victim] else -1
	for i in range(POOL_SIZE):
		var k := (_next + i) % POOL_SIZE
		if not _pool[k].playing:
			_next = (k + 1) % POOL_SIZE
			return k
	var weakest := -1
	for i in range(POOL_SIZE):
		if weakest < 0 or _pool_priority[i] < _pool_priority[weakest] or (_pool_priority[i] == _pool_priority[weakest] and _pool_started[i] < _pool_started[weakest]):
			weakest = i
	return weakest if priority >= _pool_priority[weakest] else -1

## Briefly lowers the music under a big blast, so it never buries it and comes back on its own.
func duck(amount_db: float, hold := 0.35) -> void:
	_duck_db = minf(_duck_db, -absf(amount_db))
	_duck_hold = maxf(_duck_hold, hold)
	apply_volumes()
	set_process(true)

func _process(delta: float) -> void:
	_duck_hold -= delta
	if _duck_hold <= 0.0:
		_duck_db = move_toward(_duck_db, 0.0, delta * 14.0)
		apply_volumes()
		if _duck_db >= 0.0:
			_duck_db = 0.0
			set_process(false)

## Plays a sector's calm stem with its intense stem running silently in sync.
func music_layered(track: String, fade := 0.9) -> void:
	if track == _current:
		return
	music(track, fade)
	var stem: AudioStreamWAV = load(MUSIC_DIR + track + "_hot.wav")
	if stem == null:
		return
	stem = stem.duplicate()
	stem.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stem.loop_begin = 0
	stem.loop_end = int(stem.get_length() * stem.mix_rate)
	_layer.stream = stem
	_layer.volume_db = -60.0
	_layer.play()
	_layer_track = track
	_intensity = 0.0

## 0 is calm, 1 is full intensity. Only moves the intense stem's volume.
func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	if _layer.playing:
		_layer.volume_db = lerpf(-40.0, 0.0, sqrt(_intensity))

func _stop_layer() -> void:
	_layer_track = ""
	if _layer.playing:
		_layer.stop()

func music(track: String, fade := 0.9, looped := true) -> void:
	if track == _current:
		return
	_current = track
	if track != _layer_track:
		_stop_layer()
	var stream: AudioStreamWAV = load(MUSIC_DIR + track + ".wav")
	if stream == null:
		return
	stream = stream.duplicate()
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var incoming := _music_b if _music_a.playing else _music_a
	var outgoing := _music_a if incoming == _music_b else _music_b
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	if _fade:
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(incoming, "volume_db", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if outgoing.playing:
		_fade.tween_property(outgoing, "volume_db", -60.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_fade.chain().tween_callback(outgoing.stop)

func stop_music(fade := 0.6) -> void:
	_current = ""
	_stop_layer()
	if _fade:
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	for p in [_music_a, _music_b]:
		if p.playing:
			_fade.tween_property(p, "volume_db", -60.0, fade)
	_fade.chain().tween_callback(func() -> void:
		_music_a.stop()
		_music_b.stop())

## Muffles the music while the pause menu is open.
func set_muffled(on: bool) -> void:
	AudioServer.set_bus_effect_enabled(_music_bus, 0, on)
