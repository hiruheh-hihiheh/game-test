# Device Testing Workflow

The automated tests run on a PC and can't judge touch feel, sound or real phone speed. Run through this on real hardware before each release.

## Test phones

Try to cover one of each:

- A budget phone with 3 GB of RAM or less. This is the one that matters most for performance.
- A mid-range phone.
- A tall phone with a notch or hole-punch camera.
- A tablet, if you plan to support tablets.

## First 10 minutes

Use **Settings > Reset Progress**, or a fresh install.

- [ ] Level 1 teaches moving without needing explanation.
- [ ] Crystals, the first card, Nova and the Hangar are all understood through play.
- [ ] Nothing feels unfair or confusing by level 5.
- [ ] You want to play level 6.

## Touch

- [ ] Dragging feels 1:1 and never loses the ship.
- [ ] Your thumb never hides the ship.
- [ ] The Nova button is easy to reach but hard to hit by accident.
- [ ] The Nova side setting and double-tap Nova both work.
- [ ] Lists scroll smoothly and scrolling doesn't press buttons.

## Interruptions

- [ ] Phone call, notification shade, app switch and screen lock all pause the game.
- [ ] Resuming shows the Get Ready countdown.
- [ ] The Android back button pauses in a flight and goes back in menus.
- [ ] Force-closing mid-level keeps progress from earlier levels, and an Expedition run survives.

## Performance

Fly a Sector 6 level and its boss with the Effects setting on High.

- [ ] Frame rate stays steady in the densest fights. If it doesn't, check Effects on Low.
- [ ] The phone doesn't get uncomfortably hot in 15 minutes of play.
- [ ] Check battery drain at 60 and 30 fps.

## Sound and haptics

- [ ] Music loops without a click on every sector theme.
- [ ] The intense music layer fades in smoothly and stays in time with the calm layer.
- [ ] No sound effect is too loud or harsh, on speakers and on headphones.
- [ ] Vibration feels good at Low and Full, and Off really is off.

## Accessibility

- [ ] Large interface fits on every screen.
- [ ] Colour-blind palette and shot outlines make shots easier to read.
- [ ] Reduce Flashes and Reduce Motion work, including on boss deaths.

## Difficulty

Have people who didn't make the game play it, and watch them without helping. Note where they get stuck or quit. Turn on **Save balance log on device** to record their results in `user://telemetry.log`.

## Glass interface: what to record on a phone

Nothing about the glass UI has been run on a real device yet (no Android SDK, export templates or phone were available on the development PC). When you can, write down:

- Device model, screen resolution and density, Android version, and the renderer shown in the Godot output (the project uses GL Compatibility).
- Frame rate in menus (Hangar gear tab and the map are the heaviest), in a busy level, and in a boss fight. Turn on `show_fps` through Godot's Remote debugger, or use `adb shell dumpsys gfxinfo com.starfall.salvage framestats`.
- Whether Settings segments, Gear filter chips and tabs are easy to hit with a thumb. They are drawn 54 to 62 units tall and rely on a 84-unit touch margin.
- Any clipping at the notch, rounded corners or navigation bar, especially the Launch button, the results buttons and the pause menu.
- Whether the score plate, boss bar or Nova disc ever hide something important.
- Frame rate again with Reduce motion and Reduce flashes on, and with the interface size set to Large.
