# Gloop Forest terrain rendering performance

Investigated 2026-09-08 against commit `5c0f7c6`, Phaser 3.90.0.

Status: global fix implemented on 2026-09-09. The original investigation and
measurements are retained below; the implementation results follow here.

## Implemented fix

The shared TerrainTransitionRenderer now builds an ordered command list and
bakes occupied 512-pixel chunks using TerrainTransitionLayer. Gameplay and Map
Studio both use this path for every map. Cropped interior frames have two-pixel
gutters containing neighboring artwork. Chunk images are culled against the
camera's final view, and all temporary masks/graphics are destroyed after baking.
Explicit editor rebuilds, scene shutdown, and partial bake failures release owned
textures and listeners. Base terrain, collision, entities, and save data retain
their existing behavior.

Gloop Forest produces 49 cached chunks and reached **59.9 FPS at 0.5x** in the
browser check. Its RGBA texture payload is about 46.3 MiB. Crystal Caverns produces
44 chunks (42.7 MiB RGBA). These figures exclude render-target depth buffers and
other engine allocations. Texture dimensions are bounded, but total retained
memory follows occupied map area; this implementation does not stream chunks.

The rendering tests cover all 15 authored maps, empty/same-material terrain,
partial rectangular chunks, gutters, ordering, source frames/flips, culling,
rebuild/shutdown disposal, and simulated bake failure. A retained browser pixel
comparison uses the frozen pre-fix renderer with synthetic patterned and partly
transparent tile sources. WebGL and Canvas both passed at tile sizes 64 and 37
and zooms 1, 0.75, and 0.5, with zero retained masks and zero leaked textures.
Mean per-channel pixel differences were below 0.52/255; small edge filtering
differences are expected when static masks become sampled textures.

Run the browser comparison with Vite at
`/scripts/tests/rendering/__tests__/terrain-visual-check.html` and again with
`?renderer=canvas`. It is a test-only page, outside the production entry point.

## Finding

Static terrain transitions are rebuilt on the GPU every rendered frame using
thousands of separate geometry masks, including transitions outside the camera.
This is the dominant cause of the reproduced Gloop Forest slowdown.

The original renderer measured **7.2 FPS** at a 912 x 692 game canvas. A temporary
prototype that excluded offscreen transition images measured **60.4 FPS** at the
same canvas size, camera location, and 1x zoom, with terrain blending enabled.
However, that prototype fell to **16.3 FPS at 0.5x zoom**. Culling is useful
immediate relief, but caching static transitions is the recommended durable fix.

## Runtime evidence

Measured in the Codex in-app browser using the existing `?renderDebug=1` overlay.
Vite development mode, WebGL, debug drawing disabled. Recovery was continued;
gameplay systems and map content were retained. The desktop browser viewport was
1280 x 720, yielding a 912 x 692 game canvas alongside the development panel.

| Canvas | Zoom | Terrain transition rendering | Observed FPS |
| --- | --- | --- | ---: |
| 318 x 256 | 1x | Original | 18.3 |
| 318 x 256 | 1x | Transitions omitted temporarily | 60.5 |
| 912 x 692 | 1x | Original | 7.2 |
| 912 x 692 | 1x | Offscreen transitions culled | 60.4 |
| 912 x 692 | 0.5x | Offscreen transitions culled | 16.3 |
| 912 x 692 | 0.5x | Transitions omitted temporarily | 60.5 |

These are settled readings from Phaser's FPS overlay, not frame-time percentiles
or guarantees for other GPUs. The experiments isolate transition rendering as a
dominant bottleneck; they do not prove that every other subsystem is optimal.
The culling experiment used an axis-aligned camera test for the current terrain
images, preserving the original `willRender` flags and camera filtering. It was
a diagnostic prototype, not a general culling implementation.

## Why this map is especially affected

Counts were calculated directly from the authored map JSON and the actual
`TILE_CATALOG` transition group/material rules. Each qualifying east/south edge
is counted once, matching `TerrainTransitionRenderer`.

| Map | Terrain tiles | Authored objects | Blend boundaries | Transition images and masks |
| --- | ---: | ---: | ---: | ---: |
| Level 1 | 432 | 24 | 0 | 0 |
| Meadow Crossing | 2,916 | 414 | 0 | 0 |
| Gloop Forest | 2,916 | 65 | 1,027 | 3,081 |
| Crystal Caverns | 2,916 | 0 | 925 | 2,775 |

Gloop Forest mixes forest floor, moss, and some crystal floor. Meadow's two grass
IDs have the same transition material, so their boundaries generate no masks.
Crystal Caverns has the same architectural exposure, although its FPS was not
measured in this investigation.

At the measured Gloop Forest 1x desktop camera position, only 213 of the 3,081
transition images intersect the camera rectangle. The original path still
submits all 3,081. At the small viewport, just 21 intersect it.

## Code-level cause

1. `src/game/features/world/MapBuilder.ts` creates an individual image for every
   terrain cell, then builds all transitions for the complete map.
2. `src/game/features/world/TerrainTransitionRenderer.ts` creates three feather
   bands per boundary. Each band gets its own image, graphics polygon, and
   `GeometryMask`. These are static but remain on the normal display list.
3. Phaser's `CameraManager.getVisibleChildren` calls `GameObject.willRender`.
   For these images, that checks rendering flags and camera filters, not spatial
   intersection with the viewport. `ImageWebGLRenderer` submits the image.
4. `node_modules/phaser/src/display/mask/GeometryMask.js` flushes the renderer,
   enables and clears stencil state, draws the mask geometry, and flushes again.
   Leaving each mask also forces a flush. Separate masks break sprite batching.
5. GPU clipping cannot eliminate the CPU submission and stencil setup work
   already performed for offscreen images. Thousands of these operations recur
   every frame. The larger canvas also makes the observed cost worse.

The relevant installed-engine methods are `GameObject.willRender` (line 628),
`CameraManager.getVisibleChildren` (line 625), and `GeometryMask.preRenderWebGL`,
`applyStencil`, and `postRenderWebGL` (lines 133, 170, and 221).

## Original implementation recommendation

Implement a scene-owned static terrain rendering component under
`features/world/`, composed by `MapBuilder`.

1. Cache the blended transition artwork into bounded texture chunks, initially
   considering 512 x 512 world pixels (8 x 8 cells). Generate each chunk once
   while loading the authored map. Preserve the existing seeded polygons,
   material priorities, frame selection, flip, band alpha, and band draw order.
   Flattening must reproduce the current globally sorted band order, not draw
   all bands of one boundary before moving to the next.
2. Render those cached chunks as ordinary images with no live geometry masks.
   Cull chunks using the current camera bounds after camera transforms update.
   At runtime the cost should follow visible chunks, not total map boundaries.
3. Keep terrain collision bodies independent from render chunks. Trees, houses,
   collectibles, NPCs, enemies, actor silhouettes, and other interactive or
   animated entities retain their existing ownership and depth behavior.
4. Start with transition-only chunks at the existing ground-decal depth. If
   profiling justifies it, fold the base ground into the same static terrain
   renderer while preserving collision geometry and all visual depth ordering.
5. Bound the texture cache and dispose its images, textures, and listeners on
   shutdown. Handle edge chunk sizes and texture seams at fractional zoom.
   A full-map 3456 x 3456 RGBA surface alone costs about 45.6 MiB before extra
   render targets or CPU copies; chunking needs an explicit memory budget too.
6. For editor use, invalidate only changed chunks and affected neighboring
   boundaries. Production gameplay must still consume authored map data and
   must not invoke the procedural map generator.

The measured culling prototype is suitable as an immediate mitigation while
this component is implemented. It is insufficient as the final solution because
zooming out brings the expensive masks back into view. Removing blending
entirely is a useful diagnostic or fallback but changes the terrain appearance.
An engine migration or a rewrite of movement/combat is not supported by the
evidence for this issue.

## Secondary opportunities

These are code observations, not separately measured causes of the reproduced
7.2 FPS result. Reprofile after removing live terrain masks before expanding scope.

- `WorldScene.syncCameraLayers()` scans the complete display list each update.
  Assign camera ownership on creation/removal, with explicit support for objects
  that change layers, instead of revisiting thousands of static terrain images.
- Animated actors call `setDepth` repeatedly, causing the shared display list to
  be sorted. Separating static terrain from sortable entities would reduce the
  amount of work affected by actor movement.
- `OcclusionController.registerOccluder()` samples source alpha using repeated
  `TextureManager.getPixelAlpha` calls when building an uncached source mask.
  Reading frame pixels in one operation could reduce loading cost. Source masks
  are already cached and actor queries use spatial cells; this is distinct from
  the thousands of terrain masks rendered every frame.
- Development bounds overlays can add drawing work, but they were disabled in
  the measured baseline and cannot explain that result.

## Verification criteria

- Repeat Gloop Forest at 1x and every supported overview zoom, including 0.5x,
  while moving horizontally/diagonally, fighting, and panning across chunk edges.
- Capture CPU update/render times, draw calls, live terrain mask count, texture
  memory, and median/p95 frame times. Target stable 60 FPS on the reproduction
  device and zero live terrain geometry masks after the cache is built.
- Compare screenshots against the original renderer for blend ordering, seeded
  edges, texture flips, corner intersections, and seams.
- Check terrain collision, water traversal, object occlusion, house interactions,
  map transitions, restart cleanup, and repeated area loads.
- Include Crystal Caverns as another transition-heavy map and Meadow Crossing
  as a control. Test editor invalidation if the renderer is shared with editing.
- Run the repository's rendering tests, map validation, typecheck, build, and
  complete `pnpm check` after implementation.
