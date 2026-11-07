# Combat effects and audio

How combat looks and sounds: explosions, weapon impacts, shields, engines, and the sound that goes with each. None of it
changes a gameplay number. It is all drawn and played from events the game already had.

## Where things live

| File | Job |
|---|---|
| `src/combat/fx.gd` (`Fx`) | The effects store: sparks, flashes, rings, bursts, debris, ripples, bolts, scheduled stages. `explode()`, `impact()`, `ripple()`, `shield_break()`, `shield_recover()`, `boss_blast()`, `boss_finale()`. |
| `src/combat/shield_fx.gd` (`ShieldFx`) | The player's shield look: ripples, wear, collapse, recovery. Also paints enemy shields. Only reads the shield value. |
| `src/combat/engine_fx.gd` (`EngineFx`) | The player ship's exhaust, particles and short trail, from real movement. Ship differences are `PROFILES`. |
| `src/combat/combat_audio.gd` (`CombatAudio`) | Which sound a combat event makes. Playback is `Audio`'s. |
| `src/audio.gd` (`Audio`) | Voice priorities, per-group voice limits, a limiter on the SFX bus, music ducking. |
| `tools/gen_audio.mjs` | Synthesises every sound from scratch. The combat sounds are in its "Combat polish sounds" section. |

Where an effect starts: `game.gd` (`_fire`, `_hit_enemy`, `_splash`, `hurt_player`, `_destruction_fx`, `_explosion`,
`_player_destroyed`, `_sync_sprites`, `_paint_fx_add`) and `boss_base.gd` (`take_hit`, `kill_part`, `_stage_up`,
`_update_death`, `_finish_death`). Each call is one line into `Fx`, `ShieldFx`, `EngineFx` or `CombatAudio`.

## Explosions

`Fx.explode(at, tier, size, palette)` draws five layers: a brief bright flash, an expanding burst, a shockwave ring,
sparks and debris, and a few embers that linger. Every call varies size, ring width and debris, so no two match.
`TIERS` describes each class (flash, burst, ring `[from, to, seconds, width, opacity]`, spark and debris counts, speed,
stages, shake). `Fx.tier_for(heavy, size)` picks it from the enemy data:

| Tier | For | Look |
|---|---|---|
| `small` | enemies under 100 px | quick and compact |
| `medium` | enemies 100 px and up | larger orange burst, more debris |
| `heavy` | enemies marked `heavy` (gunship, frigate, brood mother, dreadnought) | two secondary bursts, then a larger final blast |
| `part` | boss parts and phase changes | a medium blast with extra wreckage |

Palettes: `fire` (default), `energy` (pods and brood), `ice` (husks, revenants, sentinels), `rock` (boulders and wrecks).
A boss dying keeps its existing sequence (attacks stop, bullets clear, blasts for about two seconds) with `boss_blast()`
for each secondary explosion and `boss_finale()` for the last: a large burst, three staggered shockwaves, thrown wreckage
and embers.

## Weapon impacts

`Fx.impact(at, weapon, power, surface)`. `IMPACTS` has one look per weapon in `Ships.WEAPONS`, plus `arc`:

| Weapon | Class | Impact |
|---|---|---|
| `pulse` | plasma | bright flash, small expanding ring, short glowing sparks |
| `twin`, `beam` | laser | small sharp flash, a few fast sparks, no ring |
| `missile` | explosive | large flash, burst, ring, debris (drawn by the splash) |
| `scatter` | pellets | small gold flash and sparks |

`power` is 1 for a normal hit and larger for crits and heavy shots, so a heavy hit is clearly bigger. `surface` is
`hull` or `shield`; a shield hit is blue-white and also ripples the shield. Impacts are limited to 150 a second (a burst
of 14), so a screen full of shots costs no more than a busy one.

## Shields

Player: the existing shield sprite, plus `ShieldFx`. A hit ripples on the side the shot came from (stronger hits make a
wider, brighter ripple) with a flash at the contact point. As the shield wears, the look changes by shape as well as
brightness, so it never depends on colour or on flashing:

| Shield | Look |
|---|---|
| above 60% | smooth bubble |
| 30 to 60% | a ring with gaps, brief glow dips |
| under 30% | more gaps and short electrical arcs |
| under 12% | the ring pulses slowly, and a quiet warning sound every 3 seconds |

At zero the bubble expands and fades while a burst, two rings, arcs and curved fragments fly outwards, with a distinct
break sound. When it returns, a ring closes in and a few motes are drawn to the ship, with a soft sound; during normal
regeneration a mote appears now and then. Enemies that already have a shield (the `shielded` elite modifier) get the
same ripple, wear ring and break. No other enemy was given one. `hurt_player()` keeps its arithmetic exactly; `ShieldFx`
is called after it, with the values it computed.

## Engines

`EngineFx` follows how the ship is actually moving (position change per frame, smoothed): idle is a short calm exhaust,
cruising is stable, fast movement is longer and brighter and leans against sideways movement, and a short trail of at most
five fading afterimages appears only when moving fast. The end-of-level fly-off is the fastest the exhaust gets. No
movement value was added or changed. Each exhaust has a bright core, a softer outer glow, a tapering energy flame and
particles. `PROFILES` sets nozzles, width, length and colours per ship: Nova cyan, Interceptor narrow and long, Lancer
violet, Warden wide and amber, Magpie gold.

## Accessibility

| Setting | Effect |
|---|---|
| Reduce Flash | core flashes are smaller and dimmer, staged flashes become plain bursts, shield glow stops flickering, engine brightness is capped. Shield wear is still shown by the ring's gaps. |
| Reduce Motion | no staged heavy explosions, half the flying pieces, shorter shockwaves, one boss shockwave, no shield arcs or motes, no engine trail or flame wobble. The existing screen-shake and hit-stop rules are unchanged. |
| Particles (Low, Medium, High) | scales sparks, debris and engine particles through `Fx.density`. |
| Colour blind | shield state is shape; hits on shield and hull also differ in ring and sound. |
| SFX and Music volume | unchanged: everything plays on the existing buses. |

## Audio

Weapon fire: plasma `fire_plasma` (deep discharge), laser `fire_laser` (sharp electrical), scatter `fire_scatter` (heavy
cannon), missile `missile` (launch) followed by `impact_explosive` on the hit. Pitch and level vary a little per shot.
Impacts: `impact_plasma`, `impact_laser`, `impact_explosive`, `impact_heavy` for big hits, and `clank` on shields. Shields:
`shield_hit`, `shield_heavy`, `shield_break`, `shield_up`, `shield_warn`. Destruction: `explode_s`, `explode_m`,
`explode_heavy`, `boss_chain` for boss parts and blasts, `boss_final` for the end (about three seconds: crack, sub boom,
rumble, falling debris), and `explode_l` for the player's ship.

Mixing: the SFX bus ends in a limiter so nothing clips. `Audio.GROUPS` and `GROUP_LIMIT` cap how many voices each of
fire, impact, explosion and shield may use; a full group lets a new sound in only by replacing a quieter or older one
(`Audio.PRIORITY`, boss and shield break highest). Throttles space repeats. Heavy blasts and the shield break lower the
music by 2 to 7 dB for under a second and it returns by itself. The retired `shoot`, `shoot_twin` and `shoot_scatter`
sounds were replaced and removed. The new sounds use a random stream of their own in the generator, so no existing sound
or music track changed by a byte.

## Performance

Nothing here creates a Node while playing. Every list has a cap (`MAX_SPARKS` 480, `MAX_DEBRIS` 72, `MAX_FLASHES` 40,
`MAX_RINGS` 60, `MAX_BOOMS` 60, `MAX_SCHEDULED` 48, `MAX_RIPPLES` 24) and effects expire by themselves. Flashes ride in the
spark batch, rings in two batches (thin and thick ring textures) and debris in one, so they cost three draw calls however
many there are. Measured on this PC in a window with 24 enemies and 500 bullets and an enemy dying every third frame:
draw calls 113 to 116 before, 122 to 128 after; before batching the same scene was 258 to 262. Script cost in `bench.gd`
was 4.5 to 5.0 ms a frame before and after. This PC is not a phone: frame time here was pinned at the display rate, so the
draw-call count is the figure that carries over.

## Tests

`_test_combat_polish` in `tools/test_game.gd` (part of the quick suite): the effect tables, the five explosion layers,
size ordering, variation, caps and cleanup under 300 explosions, every weapon's impact and the impact budget, Reduce Flash
and Reduce Motion, shield wear, ripples, break, recovery and warning, that shield and hull damage are exactly what they were,
enemy shields, every enemy kind exploding, thirty dying at once, every ship's engine profile and weapon, exhaust against
speed, the trail, every sound loading, group limits, priorities, the limiter, ducking, the SFX volume, and a real boss
being destroyed.

## Not verified

The effects and sounds were checked in headless tests and in screenshots of a real window on Windows. **No sound has been
listened to** (the sounds are synthesised and their levels and length are checked by number only), nothing was run on an
Android device, and no frame times on a phone were measured.
