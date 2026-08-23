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
  fractional zoom cannot remain pixel-perfect; linear filtering avoids harsh
  nearest-neighbor shimmer.
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

## House transitions and respawn

Scripted house and respawn pans temporarily stop normal following. Returning to
the player restores the default `1x` zoom and resumes the responsive controller.
Camera bounds remain the authored map dimensions.

## Screen-space UI and minimap

`setScrollFactor(0)` ignores camera scroll but not camera zoom. The runtime
therefore renders HUD and minimap objects through a dedicated `screen-ui` camera
at `1x`, while the world camera ignores those objects.

The minimap recalculates its size and lower-left position from the viewport. It
uses the world camera's visible bounds for the view rectangle, so wheel zoom is
still represented correctly.

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
