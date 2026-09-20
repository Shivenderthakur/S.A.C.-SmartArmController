# Versions

What changed in each release, newest first. The version lives in
`pubspec.yaml`; pushing a new one to `main` is what makes CI tag it and publish
the APK.

## Unreleased

Work sitting on `feat/dof-modes` and `feat/step-sequencer`, not yet merged.

### The claw is two servos

A claw closes with two servos facing each other, and the app had that as a
special case: channel 5 always carried `180 - claw`, which quietly overwrote
the fifth joint of any larger arm. It is configuration now — a joint can name a
second pin, gets the opposite angle on a channel of its own, and the link no
longer knows what a claw is.

### Steps, on the Control screen

Add step opens the arm itself: a slider per joint, however many this arm has,
moving the servos as you drag them. Leave the arm where the step should be,
name it, give it a speed and a hold, and save. Cancelling puts the arm back
where it was.

Steps drag into order, the routine has a wait between steps and a repeat
switch, and the whole thing plays back. Saved on the phone.

Playback interpolates in the app rather than sending one pose per step: the
firmware ramps at its own fixed rate and never reports arrival, so sending a
pose a degree or two along every 50 ms is what makes a step's speed mean
anything. It stays open loop — dwell and gap are measured from the last pose
sent, not from a servo arriving.

### Track leaves the bar

The camera yields three joints and a claw and never more, so on a bigger arm
the Track tab is gone and its screen cannot be reached. Shrinking the arm
brings it back.

### Smoother

Four things repainted for nothing: the player notified the UI twenty times a
second, the Control screen rebuilt on every angle, the hand skeleton repainted
per angle on a listenable it never read, and the full-screen gradients had no
repaint boundary.

## 3.0.0 — 19 September 2026

**The arm moves.** The firmware drives up to nine servos on GPIO 16–23 and
32/33, reusing the one-degree-per-15 ms ramp so it sweeps rather than snaps,
and holding position when the phone disconnects — detaching would drop the
holding torque and the arm would sag.

**Pins are assigned from the app.** A new Board screen draws the real ESP32 and
a joint is dragged onto the pin it is wired to. The map is pushed to the board
on every connect as one `M,<channel>,<gpio>;` line, all or nothing, and the
board answers with the channels that actually attached. It keeps the map in RAM
only, so a board that reboots answers the heartbeat with `ok,0;` and the phone
pushes it again.

**Joints replaced the four hardcoded servos** throughout the app, persisted as
JSON.

Fixed on the way: the board drawing rendered as nothing, because every one of
its 98 elements carried a `filter="url(…)"` and flutter_svg drops those.

## 2.0.0 — 16 September 2026

**The ESP32 runs its own hotspot** at a fixed `192.168.4.1`, so there is no
router to share and no address to look up. It received commands and printed
them; it did not drive servos yet.

**A real app icon** on every platform, generated from one source by
`tools/generate_icons.py`, including Android's adaptive and themed icons.

**Releases are signed with one permanent key** held in Actions secrets. Before
this every CI build used a throwaway debug key, so no release could install
over another.

## 1.0.0 — 16 September 2026

The first release: hand tracking on the phone driving four servos over WiFi,
and a CI pipeline that analyzes, tests, builds and publishes a versioned APK.
