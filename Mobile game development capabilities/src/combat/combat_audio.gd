class_name CombatAudio
extends RefCounted
## Which sound each combat event makes. The game and the bosses ask for an event ("a pulse shot hit a hull", "a heavy
## enemy exploded") and this decides the file, level and pitch. Playback, voice limits, priorities and the SFX volume
## are all the Audio autoload's, so nothing here can bypass the player's settings.

const FIRE := {
	"pulse": {"sound": "fire_plasma", "db": -9.0, "pitch": 1.0, "jitter": 0.07},
	"twin": {"sound": "fire_laser", "db": -12.0, "pitch": 1.0, "jitter": 0.1},
	"scatter": {"sound": "fire_scatter", "db": -8.0, "pitch": 1.0, "jitter": 0.08},
	"missile": {"sound": "missile", "db": -7.0, "pitch": 1.0, "jitter": 0.1},
}

## A volley. More lanes fire more bullets at once, so each lane is a little quieter and the volley is not louder than it must be.
static func fire(weapon: String, lanes := 1) -> void:
	var f: Dictionary = FIRE.get(weapon, FIRE.pulse)
	Audio.play(str(f.sound), float(f.db) - minf(4.0, float(maxi(0, lanes - 1)) * 1.0), float(f.pitch), float(f.jitter))

## A projectile hitting something. `surface` is "hull" or "shield"; `power` is 1 for a normal hit.
static func impact(weapon: String, surface: String, power := 1.0) -> void:
	if surface == "shield":
		Audio.play("clank", -12.0 + minf(4.0, power * 2.0), 1.0 + minf(0.15, power * 0.05), 0.1)
		return
	if power >= 1.7:
		Audio.play("impact_heavy", -9.0, 1.0, 0.08)
		return
	match weapon:
		"missile":
			Audio.play("impact_explosive", -10.0, 1.0, 0.08)
		"twin", "beam", "arc":
			Audio.play("impact_laser", -14.0, 1.0, 0.1)
		"scatter":
			Audio.play("impact_plasma", -13.0, 1.15, 0.1)
		_:
			Audio.play("impact_plasma", -12.0, 1.0, 0.1)

## Destruction, from small to boss. Bigger things are lower and longer, and the biggest briefly lower the music.
static func explosion(tier: String, size := 100.0) -> void:
	var low := clampf(1.18 - size / 450.0, 0.78, 1.15)
	match tier:
		"small":
			Audio.play("explode_s", -5.0, low, 0.1)
		"medium":
			Audio.play("explode_m", -3.0, low, 0.08)
		"heavy":
			Audio.play("explode_heavy", -3.0, low, 0.06)
			Audio.duck(3.0, 0.4)
		"part":
			Audio.play("boss_chain", -4.0, 1.0, 0.1)
		"boss_chain":
			Audio.play("boss_chain", -5.0, 1.0, 0.12)
			Audio.duck(2.0, 0.25)
		"boss_final":
			Audio.play("boss_final", 0.0)
			Audio.duck(7.0, 1.4)
		"player":
			Audio.play("explode_l")

## Shield sounds: "hit" (absorbed), "heavy", "break", "up" (recovered) and "warn" (nearly gone).
static func shield(kind: String) -> void:
	match kind:
		"hit":
			Audio.play("shield_hit", -3.0, 1.0, 0.06)
		"heavy":
			Audio.play("shield_heavy", -2.0, 1.0, 0.04)
		"break":
			Audio.play("shield_break", 0.0)
			Audio.duck(3.0, 0.5)
		"up":
			Audio.play("shield_up", -6.0)
		"warn":
			Audio.play("shield_warn", -12.0)
