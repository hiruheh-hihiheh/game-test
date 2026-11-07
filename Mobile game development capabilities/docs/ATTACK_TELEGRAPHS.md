# Attack telegraphs

What the player sees before an enemy or boss attack lands. Nothing here changes a damage, speed, rate, count, health or
pattern: it only describes attacks the game already makes, and it describes them from the same numbers the attack uses.

## Files

| File | Job |
|---|---|
| `src/combat/telegraph.gd` (`Telegraph`) | The geometry every attack and every warning share (`enemy_shots`, `fan_rays`, `aimed_rays`, `ring_rays`, `radial_rays`, `curtain_xs`), the small store of warnings that outlive a charge, and `collect()`, which builds this frame's **descriptors**. |
| `src/combat/telegraph_paint.gd` (`TelegraphPaint`) | Turns descriptors into capped line, arc, glow and polygon lists and draws them in two passes. Reads accessibility settings. |
| `src/combat/boss_base.gd` | `prepare()` (the plan for an attack, made when the charge begins), `describe()`, `run_curtain()`, `intent` / `plan`. Bosses override `prepare_special()`, `describe_special()` and `ambient()`. |
| `game.gd` | `enemy_can_fire()` and `enemy_aim()`, the tell now records `tell_max` and `tphase`, `_enemy_shoot()` reads its shots from `Telegraph`, and the two draw layers. |
| `src/combat/hazards.gd` | `roll_spot()` and optional `angle`/`dir` for `add_spokes()`, so a warning can show the real spot. |

## How a warning is guaranteed to match its attack

1. **One source of geometry.** `_enemy_shoot()` and every boss attack read their shot origins and angles from
   `Telegraph` (or, for boss-specific shots, from a method the warning also calls, such as `throw_rays()`). The painter
   reads the same functions, so there is no second copy to drift.
2. **Enemies have no second clock.** An enemy's warning is a function of its own `tell` timer
   (`k = 1 - tell / tell_max`). It is shown only while `enemy_can_fire()` is true and the enemy is not frozen or dead,
   which is exactly when the tell can advance. Hit-stop, slow motion, freezing and pause therefore need no handling.
3. **Anything random is rolled once, when the tell or charge begins, and kept.** The boss `plan` holds the ring gap,
   every curtain row's opening, the extra strike columns, the barrage columns, the zone and well spots, the spoke start
   angle and direction, and where each member of a group enters. The attack uses the plan. The one thing an enemy
   rolls early is the elite ring's turn (`tphase`); it used to be the clock at the instant of firing.
4. **Tracking is the same as the shot's.** Attacks that aim at the ship when they fire (aimed, fan, lance, boss aimed,
   burst, boss shards, boulder throws, hurl) re-read the ship every frame with the same formula. The first strike
   column and the first broadside or sweep row follow the ship the same way the beam will be placed.
5. **A stage change during a charge re-prepares the plan**, because counts depend on the stage.
6. **The attack removes its own warning.** Anything delayed (curtain rows, shells, burst shots, the elite follow-up,
   the Core's rebound) reports to `Telegraph.fired()` when it happens, and also expires on a timer as a backstop.

## Enemy attacks

| Shot | Enemy | Warning | Matches |
|---|---|---|---|
| `aimed` | Scav Fighter, Revenant, Wraith | thin laser with a sweeping dash and a tightening four-bracket reticle short of the ship | the one shot, at the ship |
| `twin` | Weaver | two rails with ladder rungs | both shots, straight down |
| `fan` | Gunship | segmented arcs between the five boundaries, a lighter outer arc, a faint wedge | all five shots |
| `lance` | Sentinel | one fine line, five diamond pips lighting in turn, a scope | the captured aim all five shots use |
| `bomb` | Bomber | three wide lanes with chevrons and a ring at the end of each | all three bombs |
| `broadside` | Frigate | five parallel strips, each charging downward in turn | all five shots |
| `elite` | Dreadnought | 14 rays and a tightening, turning segmented ring (red-orange) | the ring volley; the **follow-up** is shown separately, after the ring, as its own three aimed lines |
| `spawn` | Brood Mother | two small summoning sigils, no projectile lines | the two swarmlets, and they vanish when they spawn |

## Boss attacks

Shared: `fan` (segmented fan), `aimed` (three lines and a reticle), `burst` (one chevron per shot, lighting in order, then
counting down as the shots land 0.26 s apart), `ring` (a ring with the real gap, two edge lines, chevrons and a bracketed
arc across the gap in the "safe" colour), `spiral` (the curved trail the stream will leave, with a chevron showing the
turn), `curtain` (a row of pips with the real opening bracketed; later rows warn for the 0.55 s before they fall),
`strike` (columns with the real beam width and a reticle on the tracked one), `rocks` / `raiders` / `mines` (small markers
at the real entry points, each leaving as its member arrives; hidden for now, see below).

Boss-specific, all covered: Admiral `broadside` (rows), `launch` (side markers), `barrage` (eight shell columns, leaving as
they fall), `ram` (a lane the width of the prow), turret fire (each turret, last 0.45 s); Tyrant `flame` (columns),
`embers` (zones), `sweep` (rows), `cinders` (markers), `meltdown` (16 rays); Warden `throw` (boulder lines), `hurl` (a
line from every remaining ring piece); Hydra `brood` (marker), `curtain_spore`, head spits (last 0.4 s); Regent `shards`
(fan), `curtain_ice`, `frost` (zones), `raise` (markers); Core `wells`, `spokes` (start angle and turn), `collapse` (the
28-shot rebound, warned for its whole 2 s delay).

**Summons are not warned, because they do not arrive.** `rocks`, `raiders`, `mines`, the Admiral's `launch`, the Tyrant's
`cinders`, the Regent's `raise` and the Hydra's `brood` all queue their enemies in `game.pending`, and `_tick()` only
advances that queue in the PLAYING phase, never in BOSS_INTRO or BOSS. In a boss fight those enemies are queued and
never appear (the same at the last commit). The arrival markers are written, placed from the real entry positions, and
tested against the queue, but `Telegraph.summons_arrive` is `false`, so none is shown: a warning must not announce
something that does not happen. Nothing in the game was changed, because fixing it would add seven attacks to every boss
fight. A test probes the game and fails if the flag and the game disagree, so enabling them is one line in `_tick()` and
one flag.

**Excluded on purpose:** the Regent's `blink` (it only moves) and `mirror` (it teleports and places decoys; the burst
is a reaction to shooting a decoy). `tests` fails if any boss attack is neither warned nor in this list.

## Look and accessibility

Stages follow progress: preparing (faint, geometry visible), locking (brackets tighten, lines brighten), executing (full
brightness, amber turns hot orange). Colours: amber to orange for ordinary attacks, red-orange for the most dangerous
(ring, meltdown, elite, collapse, broadside, ram), orange for fire, cyan for ice, magenta for strike and spores, violet for
gravity and spokes, green for the safe opening. Every attack also has its own shape, so no meaning rests on colour.

| Setting | Effect |
|---|---|
| Reduce Flash | no pulsing, glows at half strength; all geometry stays |
| Reduce Motion | nothing spins, sweeps or swings; shapes hold still and only tighten with progress |
| Colour blind | blue and yellow palette; shapes unchanged |
| SFX volume | the existing tones use the normal buses |

Sound: the existing `charge` plays as it always did. Strike, ring, ram, meltdown and collapse add the existing `warning`
tone quietly; the Dreadnought's tell plays a soft `charge`. Ordinary projectiles make no warning sound.

## Cost

Nothing creates a Node. Warnings are built once per frame into capped arrays (`MAX_LINES` 640, `MAX_ARCS` 140,
`MAX_GLOWS` 40, `MAX_POLYS` 24, `MAX_PLINES` 24, `MAX_SEGS` 1800; at most 10 enemy warnings drawn, the ones nearest
firing; `MAX_TIMED` 24). Every stroke, arcs included, is cut into straight segments and drawn with one
`draw_multiline_colors` call per width and pass, in two passes: a dark outline and faint fill beneath the sprites (so it
reads on a bright background) and the bright additive lines on top. The first version drew each arc with `draw_arc`, two
draw calls per arc; ten warnings took the scene from 86 to 177 draw calls, which is why the strokes are batched.

Measured on this PC (RTX 4050 laptop, a real window, vsync off, `tools` script run from the scratch folder): 24 enemies,
500 bullets and 30 explosions on screen.

| Scene | Draw calls | Warning script cost per frame |
|---|---|---|
| no warnings | 86 | 8 us |
| 10 enemy warnings at once (the cap), 188 lines, 43 arcs | 91 | 510 us |

A boss scene with 300 bullets is 71 draw calls without a warning, and 74 to 77 with a ring, strike, spiral, curtain, fan or
collapse warning (script cost 44 to 185 us). This PC is not a phone: the draw-call count is the figure that carries over;
frame times here are set by the display.

## Not verified

Checked headless and in screenshots of a real Windows window. **No sound has been listened to**, nothing was run on an
Android device, and no phone frame times were measured.
