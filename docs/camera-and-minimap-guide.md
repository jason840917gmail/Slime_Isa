# Camera and Minimap Guide

This guide documents the camera system, zoom behavior, and the minimap implementation.

## Camera Zoom Constants

All zoom values are defined as constants at the top of `src/game/scenes/WorldScene.ts`.

```typescript
const DEFAULT_ZOOM = 1.7;
const HOUSE_ZOOM   = 1;
```

| Constant | Value | Purpose |
|----------|-------|---------|
| `DEFAULT_ZOOM` | `1.7` | Normal gameplay zoom. Makes the slime and world feel appropriately sized. |
| `HOUSE_ZOOM` | `1` | Zoom level when viewing a house interior. Shows more context around the building. |

**Rule:** Never hardcode zoom numbers anywhere else. If you change `DEFAULT_ZOOM`, every transition (entering and leaving houses) stays consistent automatically.

## Camera Lifecycle

### Initial Load

1. `createCamera()` is called during `WorldScene.create()`.
2. Camera bounds are locked to the world: `(0, 0)` to `(WORLD_WIDTH, WORLD_HEIGHT)`.
3. Zoom is set to `DEFAULT_ZOOM`.
4. Camera starts following the player with a smooth lerp (`0.08, 0.08`).

### House Transitions

**Entering a house (`F` key near a house door):**

```
stopFollow()      → stop tracking the player
pan(house.x, y)   → glide camera to house center
zoomTo(HOUSE_ZOOM, 350) → zoom out to 1 over 350 ms
showHouseUI()     → display Sleep / Leave menu
```

**Leaving a house (`Leave` button or `F` key):**

```
pan(player.x, y)          → glide back to player
zoomTo(DEFAULT_ZOOM, 350) → zoom back in over 350 ms
startFollow(player)       → resume smooth tracking
```

**Past bug:** `closeHouse()` used to call `zoomTo(1, 350)` instead of `zoomTo(DEFAULT_ZOOM, 350)`. This meant after leaving a house, the camera stayed zoomed out to `1` instead of returning to `1.7`, breaking the intended gameplay feel and causing UI positioning bugs.

## Why Zoom Breaks Screen-Space UI

Phaser 3's `setScrollFactor(0)` only ignores **camera scroll** (panning). It does **not** ignore **camera zoom**. When the main camera is zoomed to `1.7`:

- A Graphics object with `setScrollFactor(0)` still gets scaled 1.7×.
- A 160 px box becomes 272 px on screen.
- A coordinate at `y = camera.height - 160` is pushed off the bottom of the viewport.

This is why the minimap disappeared on initial load (zoom = 1.7) but appeared after entering a house (zoom = 1).

## Minimap Architecture

The minimap uses a **world-coordinate Graphics object** (scrollFactor = 1 by default). Every frame it recalculates its position so it stays visually anchored to the viewport corner.

```typescript
const viewW = camera.width / zoom;
const viewH = camera.height / zoom;
const baseX = camera.scrollX + MINIMAP_MARGIN / zoom;
const baseY = camera.scrollY + viewH - MINIMAP_MARGIN / zoom - size;
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
2. **Hardcoded zoom values are a trap.** When `zoomTo(1)` was written for house transitions, nobody noticed it clashed with the `setZoom(1.7)` initialization. Always use named constants.
3. **Zoom affects viewport dimensions in world space.** `camera.width / zoom` gives you the actual width of the world visible on screen. This is essential for placing UI relative to screen edges.
4. **EXPAND vs FIT scale mode.** `EXPAND` fills the entire browser window with the canvas. `FIT` preserves aspect ratio and adds letterbox bars. We use `EXPAND` for a true fullscreen experience.

## Safe Patterns

- Define zoom constants at the module level.
- Pass zoom values only through those constants.
- When drawing screen-space UI inside a zoomed scene, divide all coordinates and stroke widths by `camera.zoom`.
- For complex UI, consider a second Phaser Camera with its own `setZoom(1)` and `setScrollFactor(0)` objects layered on top.
