# World Motion Rendering Instability

## Status

Core runtime fix implemented on 2026-08-23. Normal play now defaults to integer
`1x`; fractional wheel levels are explicit smooth overview modes. The runtime
uses fixed-step physics with interpolated presentation transforms, post-physics
visual synchronization, a responsive camera deadzone, and delta-time-based
camera damping. The movement ladder is defined and base speed is now `240`.

Hardware capture across the documented refresh-rate and device-pixel matrix is
still required before closing the issue. Device-pixel-aware backing resolution
remains a follow-up experiment if Windows scaling adds unacceptable softness.

## Current evidence

The development runtime reports:

| Measurement | Value |
|---|---:|
| Canvas backing size | `912 x 692` |
| Canvas CSS size | `912 x 692` |
| Backing-to-CSS ratio | `1.0000` |
| Device pixel ratio | `1.5` |
| Default camera zoom | `0.75` |
| Camera `roundPixels` | `false` |
| Camera `renderRoundPixels` | `false` |
| Player base speed | `230` world units/s |
| Arcade Physics step | fixed `60 Hz` default |
| Camera follow factor | fixed `0.08` per rendered frame |

The backing canvas is no longer being stretched by CSS, but two fractional
transforms remain: the `0.75` world-camera zoom and the browser's `1.5` physical
pixel presentation. Phaser 3.90 only enables final WebGL pixel rounding when the
camera zoom is an integer.

Arcade Physics advances moving bodies at 60 fixed steps per second while the
camera is updated on rendered frames. The current camera then applies a
frame-rate-dependent lerp and quantizes the result. This produces uneven motion
cadence, especially when display refresh is not 60 Hz.

Manual snapping is also incomplete. `AnimatedVisual` and the player name tag are
snapped, while friends, some projectiles, particles, and standalone sprites use
their unsnapped positions. Different classes can therefore move on different
presentation grids.

## Root cause decision

The game will use a **hybrid renderer** with `1.0` as the default gameplay zoom.

- Keep fixed-step physics for deterministic movement and collision.
- Interpolate visible transforms between the previous and current physics state.
- Follow the same interpolated player transform with the gameplay camera.
- Do not quantize the smooth gameplay camera or individual visual positions.
- Use a responsive deadzone so ordinary movement does not move the camera.
- Keep `pixelArt: false` for the smooth path and make output resolution explicit.
- At the default integer `1.0` zoom, enable Phaser camera rounding and keep the
  camera on the stable gameplay path.
- Treat fractional zoom as a smooth overview mode, not as strict pixel-perfect
  rendering.
- Keep a strict integer-zoom experiment available only as a development
  comparison until the smooth path is approved.

This contract preserves the authored assets. Spritesheet frame dimensions remain
source-cropping metadata and no mass asset rescale is required.

## Planned movement-speed ladder

Use one typed list for tunable sustained movement and short movement actions:

```ts
export const PLAYER_MOVEMENT_SPEED_OPTIONS = [
  120,
  150,
  180,
  210,
  240,
  270,
  300,
  330,
  360,
  420,
] as const;
```

The values are intentionally spaced in 30-unit steps through normal movement,
with `360` retained as the current boost speed and `420` retained as the current
dodge speed. At 60 physics ticks per second, 30-unit spacing changes displacement
by exactly `0.5` world units per tick.

Recommended initial assignments:

| Purpose | Speed | Notes |
|---|---:|---|
| Slow/status movement | `120`-`180` | Carrying, heavy slow, or accessibility tuning |
| Normal movement range | `210`-`300` | `240` replaces the current `230` baseline |
| Fast movement range | `330` | Fast sustained movement without reaching boost |
| Boost | `360` | Preserve current authored balance |
| Dodge | `420` | Preserve current short action speed |

`240` is the preferred base-speed candidate because it is close to the current
feel and advances exactly `4` world units per 60 Hz physics tick. At the planned
default `1.0` camera zoom this is also `4` canvas pixels per physics tick before
device-pixel presentation. This numerical alignment is useful for the default
case, but interpolation—not restricting game balance to special speeds—must
guarantee smooth rendering for every option.

The array does not replace status-effect multipliers or progression bonuses.
Final resolved speeds remain clamped by `MAX_MOVEMENT_SPEED`; tests must cover
values between presets because buffs and debuffs can produce them.

## Revised implementation plan

### Phase 1 — Preserve diagnostics and add temporal measurements

- Keep `?renderDebug=1` and the existing canvas, zoom, and rounding readout.
- Add render FPS, Arcade Physics step count, interpolation alpha, raw player
  position, interpolated player position, camera position, and per-frame deltas.
- Add a development mode switch for `current`, `smooth`, and `strict` rendering
  so the same scene can be compared without rebuilding.
- Add a deterministic motion lane with repeated terrain, diagonal edges, one
  tree, one enemy, one friend, one projectile, and one particle effect.
- Capture horizontal and diagonal movement at 60, 120, 144, and 165 Hz when the
  hardware supports them.

Done when a capture can distinguish physics stepping, camera stepping, texture
sampling, and browser presentation scaling.

### Phase 2 — Add a shared interpolated presentation transform

- Keep Arcade Physics fixed at 60 Hz.
- Record previous and current physics transforms for moving actors at each
  physics step.
- Calculate one render interpolation alpha per frame and expose a reusable
  presentation-transform resolver.
- Render the player, enemies, friends, projectiles, attachments, labels, and
  world effects from interpolated transforms without changing their physics
  bodies or authored positions.
- Reset interpolation after spawn, teleport, map transition, house entry/exit,
  respawn, and any intentional instant reposition.
- Ensure depth sorting uses a documented choice of physics anchor or
  interpolated presentation anchor consistently.

Done when moving bodies remain visually smooth on displays whose refresh rate is
not equal to the 60 Hz physics rate.

### Phase 3 — Replace snapped following with a responsive deadzone camera

- Change the default gameplay zoom from `0.75` to integer `1.0`.
- Remove reciprocal-grid snapping from the smooth camera path.
- Follow the interpolated player position, never the raw fixed-step body.
- Replace the fixed `0.08` per-frame lerp with delta-time-based critically damped
  motion so camera behavior is stable at every render rate.
- Recalculate the centered deadzone whenever the camera viewport changes:
  - width: clamp approximately `18%` of viewport width to `128`-`224` pixels;
  - height: clamp approximately `14%` of viewport height to `96`-`160` pixels.
- Keep the camera stationary while the player remains inside the deadzone.
- Outside the deadzone, move only enough to bring the player back to its edge,
  then apply the time-based damping.
- Preserve camera bounds, wheel zoom, map transitions, house pans, and the
  dedicated screen-UI camera.

Done when normal direction changes and small corrections do not scroll the
world, and sustained movement produces stable camera motion without lag spikes.

### Phase 4 — Make smooth output scaling intentional

- Keep Phaser as the sole owner of canvas dimensions; do not restore forced CSS
  width/height scaling.
- Keep linear texture filtering in the smooth path.
- Prototype a device-pixel-aware backing strategy and compare it with a
  higher-resolution world `RenderTexture` that is downsampled consistently.
- Cap backing resolution by a documented GPU budget instead of blindly using
  large device-pixel ratios on every device.
- Keep HUD and editor DOM text outside world downsampling where possible.
- Validate resize behavior in normal gameplay and with the development panel.

Done when the world does not gain extra softness at Windows scale factors of
`125%`, `150%`, or `200%`, and resizing does not stretch the canvas.

### Phase 5 — Remove mixed snapping and centralize camera modes

- Remove the render-only reciprocal-grid snaps from `AnimatedVisual`, player
  labels, and any other class once interpolation owns presentation positions.
- Route every moving visual through the shared presentation-transform resolver.
- Define camera modes in one controller:
  - `gameplay`: integer `1.0` zoom, Phaser rounding enabled, deadzone, and
    interpolated follow;
  - `overview`: existing fractional wheel-zoom levels, linear filtering, no
    pixel rounding or manual snapping, smooth output, and a larger or disabled
    deadzone;
  - `scripted`: pan/zoom used by houses and transitions;
  - `strict-dev`: integer zoom and nearest filtering for visual comparison only.
- Keep wheel zoom available across the current levels. Crossing away from `1.0`
  enters overview mode; returning to `1.0` restores the gameplay camera contract.
- Revisit a short time-based zoom ease only after immediate stepped zoom is
  stable. Any animated transition intentionally uses smooth overview rendering
  while passing through fractional values.
- Ensure mode changes cancel or reset incompatible camera effects cleanly.

Done when world objects do not jitter relative to each other and there is no
class-specific pixel-grid behavior.

### Phase 6 — Add the speed ladder and tune movement

- Add `PLAYER_MOVEMENT_SPEED_OPTIONS` to the player movement content owner.
- Type UI/editor selections from the tuple while continuing to permit validated
  numeric runtime results from perks and status effects.
- Change the initial base-speed candidate from `230` to `240`.
- Preserve boost `360`, dodge `420`, and the current `480` resolved-speed cap.
- Test every preset, diagonal normalization, boost bonuses, perk bonuses, slow
  effects, collision at corners, and movement through narrow passages.
- Approve final values by gameplay feel only after interpolation and the camera
  deadzone are active.

Done when all ten presets and intermediate modified speeds render smoothly and
remain collision-safe.

### Phase 7 — Verification and rollout

Test the final behavior at:

- device pixel ratios `1`, `1.25`, `1.5`, and `2`;
- 60, 120, 144, and 165 Hz where available;
- narrow, `1280 x 720`, `1920 x 1080`, ultrawide, and development-panel layouts;
- default `1.0` zoom, every fractional wheel-zoom level, map boundaries, diagonal movement,
  resize, teleport, respawn, house flow, and area transition;
- player, terrain, trees, houses, friends, enemies, projectiles, particles, hit
  effects, labels, minimap, and HUD.

Run:

```text
pnpm assets:check
pnpm maps:check
pnpm test:rendering
pnpm typecheck
pnpm build
pnpm check
```

Remove the old snapped path only after the smooth path passes capture review and
a normal player-controlled playtest.

## Acceptance criteria

- Motion remains clear and stable while the camera moves horizontally or
  diagonally at the default integer `1.0` zoom.
- Fractional wheel zoom remains available and has an explicitly smoother
  overview appearance without snapping, shimmer, or layer-relative jitter.
- The player and camera do not visibly step at different frequencies.
- Friends, enemies, projectiles, effects, and attachments remain locked to their
  intended actors during motion.
- The camera remains stationary while the player is inside its responsive
  deadzone.
- Camera damping feels equivalent at 60, 120, 144, and 165 FPS.
- Every movement-speed option and modified in-between speed is visually smooth.
- Resizing and device-pixel scaling do not introduce a second uncontrolled canvas
  stretch.
- Teleports and scene transitions do not interpolate across unrelated positions.
- No source sprite sheet is rescaled merely to compensate for the camera.
- Collision, depth sorting, occlusion, minimap bounds, and authored map positions
  remain correct.

## Engine migration boundary

Migrating to Godot is not required to fix this defect. Godot provides built-in
2D physics interpolation, Camera2D smoothing, reference viewports, and integer
stretch scaling, so the equivalent rendering contract is easier to configure.
It still exhibits distortion when fractional scaling is selected, and it still
requires correct separation of physics and presentation transforms.

The existing `MobileVersion/` remains the correct place for a Godot feasibility
prototype. Do not pause the Phaser fix or begin a full rewrite solely because of
this rendering bug. Revisit an engine migration after the Godot version proves
one production map, representative combat, save compatibility, animation/content
loading, camera quality, and target-platform exports.
