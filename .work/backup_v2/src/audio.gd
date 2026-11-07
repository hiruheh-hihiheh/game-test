extends Node
## Sound effects and music. Autoloaded as "Audio".
## Uses its own buses so volume settings, ducking and the pause filter are one call each.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_NAMES := [
	"shoot", "enemy_shoot", "hit", "crit", "explode_s", "explode_m", "explode_l", "shield_hit",
	"hull_hit", "pickup", "repair", "powerup", "burst", "energy_ready", "ui_click", "ui_back",
	"ui_deny", "ui_buy", "card_in", "card_pick", "star_1", "star_2", "star_3", "wave_start",
	"wave_clear", "warning", "charge", "laser", "mine", "whoosh",
]
# Shortest gap between repeats, so a screen full of hits never turns into a wall of noise.
const THROTTLE := {
	"shoot": 0.06, "hit": 0.045, "crit": 0.07, "enemy_shoot": 0.09, "pickup": 0.05,
	"explode_s": 0.07, "explode_m": 0.1, "mine": 0.12,
}
const POOL_SIZE := 18

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current := ""
var _music_bus := -1
var _sfx_bus := -1
var _fade: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_bus = _make_bus("Music")
	_sfx_bus = _make_bus("SFX")
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
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	apply_volumes()

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
	AudioServer.set_bus_volume_db(_music_bus, _to_db(Save.music_volume))
	AudioServer.set_bus_volume_db(_sfx_bus, _to_db(Save.sfx_volume))

func _to_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)

func play(sfx_name: String, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.0) -> void:
	var stream: AudioStream = _streams.get(sfx_name)
	if stream == null:
		return
	var now := Time.get_ticks_msec() * 0.001
	if THROTTLE.has(sfx_name) and now - float(_last.get(sfx_name, -1.0)) < float(THROTTLE[sfx_name]):
		return
	_last[sfx_name] = now
	var p := _free_player()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.1, pitch + randf_range(-pitch_jitter, pitch_jitter))
	p.play()

func _free_player() -> AudioStreamPlayer:
	for i in range(POOL_SIZE):
		var p := _pool[(_next + i) % POOL_SIZE]
		if not p.playing:
			_next = (_next + i + 1) % POOL_SIZE
			return p
	var oldest := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	return oldest

func music(track: String, fade := 0.9, looped := true) -> void:
	if track == _current:
		return
	_current = track
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
