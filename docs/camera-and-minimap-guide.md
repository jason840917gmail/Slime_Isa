# Camera and Minimap Guide

This guide documents the responsive camera, wheel zoom, and screen-space minimap.

## Camera modes

Camera zoom definitions live in `src/game/presentation/CameraZoom.ts`; camera
following lives in `src/game/presentation/ResponsiveCameraController.ts`.

```ts
const DEFAULT_CAMERA_ZOOM = 1;
const CAMERA_ZOOM_LEVELS = [0.5, 0.625, 0.75, 0.875, 1, 1.125, 1.25];
```

- `1x` is the normal gameplay mode. Phaser camera rounding is enabled for the
  most stable authored-pixel presentation.
- Fractional wheel levels are overview mode. Rounding is disabled because
  fractional zoom cannot remain pixel-perfect; the game runs with
  `pixelArt: false`, so linear filtering avoids harsh nearest-neighbor shimmer.
- Wheel changes are immediate and stepped. There is no tween through arbitrary
  fractional values, and each change re-centers on the followed player instead
  of scaling around the deadzone's previous camera center.

## Motion pipeline

Arcade Physics runs at a fixed 60 Hz. Render-only positions are interpolated
from the last physics displacement using the world's remaining fixed-step time.
The player, animated actors, friends, projectiles, weapon attachments, and
following hit effects use this shared presentation position without moving or
resizing their physics bodies.

Presentation synchronization runs during the scene's `POST_UPDATE` phase, after
Arcade Physics has copied body positions to game objects and before rendering.
The camera follows the same interpolated player position, preventing the player
and world from stepping at different times.

The old reciprocal-grid position snapping was removed. It made different object
types move on different grids and could not solve fractional device-pixel
scaling.

## Responsive deadzone

The camera stays stationary during small player movements. Its centered
deadzone adapts to the current viewport:

- width: about 18% of the viewport, clamped to 128–224 pixels;
- height: about 14% of the viewport, clamped to 96–160 pixels.

After the player crosses an edge, the camera moves only enough to restore that
edge. Exponential, delta-time-based damping keeps the response consistent at
different display refresh rates. Phaser camera scroll remains relative to the
unzoomed viewport midpoint; only the deadzone's screen size is converted through
zoom when comparing it with world positions.

## Fixed cameras and respawn

A world whose `game.world-definition` sets `cameraMode: "fixed"` (small
interiors) does not follow the player. The camera removes its bounds, centers
on the whole world, and zooms out only as far as needed to fit it (never above
`1x`); it re-fits on resize and wheel zoom re-centers on the world.

Otherwise camera bounds are the authored world dimensions. On respawn the camera
pans to the respawn point, restores the default `1x` zoom, and resumes the
responsive controller; a fixed camera just re-fits.

## Screen-space UI and minimap

`setScrollFactor(0)` ignores camera scroll but not camera zoom. The runtime
therefore renders Phaser objects with a zero scroll factor through a dedicated
`screen-ui` camera at `1x`, while the world camera ignores them.

The HUD and minimap are authored DOM UI scenes (`ui.minimap`), not Phaser
objects. `features/ui/MinimapSurfacePort.ts` draws the minimap into a canvas
inside that scene's Control host, sizes it from the viewport (24% of the short
side, clamped to 128–180 px) in the lower-left corner, and derives the view
rectangle from the world camera's scroll and zoom, so wheel zoom is still
represented.

## Rendering diagnostics

Append `?renderDebug=1` to a development gameplay URL. The readout reports:

- camera zoom, gameplay/overview mode, deadzone, scroll, and rounding;
- physics interpolation alpha and actual render FPS;
- backing-canvas size, CSS size, CSS ratio, and device-pixel ratio;
- player visual size and active renderer.

A healthy responsive canvas has matching backing and CSS dimensions and a CSS
ratio of `1.0000` on both axes. The remaining device-pixel-ratio behavior is a
browser/output-scaling concern, not a reason to rescale source spritesheets.

See [World Motion Rendering Instability](./task/bugs/world-motion-rendering-instability.md)
for the diagnosis, acceptance matrix, and future high-DPI experiments.
