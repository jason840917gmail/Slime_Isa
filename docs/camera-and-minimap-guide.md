# Camera and Minimap Guide

This guide documents the camera system, zoom behavior, and the minimap implementation.

## Camera Zoom Constants

Gameplay zoom values are defined as constants at the top of `src/game/scenes/WorldScene.ts`.

```typescript
const DEFAULT_ZOOM = 0.75;
const CAMERA_ZOOM_LEVELS = [0.5, 0.625, 0.75, 0.875, 1, 1.125, 1.25];
```

| Setting | Value | Purpose |
|---------|-------|---------|
| `DEFAULT_ZOOM` | `0.75` | Normal gameplay zoom; shows more world while keeping sprites readable. |
| `CAMERA_ZOOM_LEVELS` | `0.5`–`1.25` | Stepped zoom targets selected with the mouse wheel. |

Mouse-wheel zoom is smooth between the discrete targets. Stepping instead of using arbitrary fractional values helps pixel-art assets stay visually stable. The minimum and maximum levels prevent the camera from becoming either too distant or too tight.

## Camera Lifecycle

### Initial Load

1. `createCamera()` is called during `WorldScene.create()`.
2. Camera bounds are locked to the world: `(0, 0)` to `(WORLD_WIDTH, WORLD_HEIGHT)`.
3. Zoom is set to `DEFAULT_ZOOM`.
4. Camera starts following the player with a smooth lerp (`0.08, 0.08`).

### House Transitions

The legacy house flow, when enabled, uses the normal gameplay zoom rather than a separate house-specific zoom:

```
stopFollow()      → stop tracking the player
pan(house.x, y)   → glide camera to house center
zoomTo(DEFAULT_ZOOM, 350) → use the normal gameplay zoom
showHouseUI()     → display Sleep / Leave menu
```

Leaving a house (`Leave` button or `F` key) returns to the player and the normal zoom:

```
pan(player.x, y)          → glide back to player
zoomTo(DEFAULT_ZOOM, 350) → zoom back in over 350 ms
startFollow(player)       → resume smooth tracking
```

## Why Zoom Breaks Screen-Space UI

Phaser 3's `setScrollFactor(0)` only ignores **camera scroll** (panning). It does **not** ignore **camera zoom**. At the default gameplay zoom of `0.75`:

- A Graphics object with `setScrollFactor(0)` still gets scaled by the camera.
- A 160 px box becomes 120 px on screen.
- A coordinate at `y = camera.height - 160` is pushed off the bottom of the viewport.

The same principle applies to every gameplay zoom level: UI that must remain a fixed screen size needs either camera-aware positioning or a dedicated UI camera.

The runtime now uses a dedicated `screen-ui` camera at `1×` zoom. World objects render only through the follow camera, while screen UI objects render only through `screen-ui`. This keeps the HUD, minimap, controls, and action bars anchored to the viewport while the world camera zooms.

## Minimap Architecture

The minimap uses a **screen-coordinate Graphics object** rendered by the `screen-ui` camera. Every frame it recalculates its size and position so it stays visually anchored to the viewport corner and scales down on compact screens.

```typescript
const size = clamp(Math.min(camera.width, camera.height) * 0.24, 128, 180);
const margin = clamp(Math.min(camera.width, camera.height) * 0.025, 12, 16);
const viewW = camera.width / camera.zoom;
const viewH = camera.height / camera.zoom;
const baseX = margin;
const baseY = camera.height - margin - size;
```

All drawn shapes are also scaled by `1 / zoom` so their on-screen pixel size stays constant regardless of zoom level:

- Border thickness: `3 / zoom`
- Dot radius: `3 / zoom` (friends), `4 / zoom` (player)
- Corner radius: `8 / zoom`

### Minimap Contents

| Element | Color | Meaning |
|---------|-------|---------|
| Background | `#0a1f15` | Minimap panel background |
| Border | `#44cc88` | Bright green outline |
| Friend dots | `#ffb347` | Orange dots for each friend |
| Player dot | `#6be0ff` | Cyan dot for the player |
| View rectangle | `#88c899` | Outline showing the camera's visible area |

## Key Learnings

1. **Never rely on `setScrollFactor(0)` for zoomed cameras.** It does not create true screen-space UI. Use world-coordinate positioning recalculated every frame, or use a dedicated UI camera.
2. **Camera zoom is not screen resizing.** `Phaser.Scale.EXPAND` and the CSS canvas sizing control the physical game viewport. Camera zoom controls how much of the world is visible inside that viewport.
3. **Stepped zoom is friendlier to pixel art.** The game uses `0.5` through `1.25` targets and smooth transitions, giving players a wider view without making the default composition as small as the old `0.5` experiment.
4. **Zoom affects viewport dimensions in world space.** `camera.width / zoom` gives you the actual width of the world visible on screen. This is essential for placing UI relative to screen edges.
5. **EXPAND vs FIT scale mode.** `EXPAND` fills the entire browser window with the canvas. `FIT` preserves aspect ratio and adds letterbox bars. We use `EXPAND` for a true fullscreen experience.

## Safe Patterns

- Define zoom constants at the module level.
- Pass zoom values only through those constants.
- Render screen-space UI through the dedicated `screen-ui` camera at `1×` zoom.
- If a UI element must remain on the world camera, divide its coordinates and stroke widths by `camera.zoom` explicitly.
