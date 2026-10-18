# Review: the unified paintable fences (2026-10-17)

Reviewed: the fence work in commit 2a04028b plus its uncommitted edits (`game/world/elevation/fences/`,
`docs/godot/FENCES.md`, `tests/test_fences.gd`, `game-constants.json` `fences.clearance` 8 → 14, the 44
scenes that paint a `fences` layer, the builders that write them). Nothing was edited. Pictures with the
collision drawn over the art (red = collision, yellow cross = the post's foot, blue = the slime's body
where it stops) are in the session scratchpad `fence-review/` (`twig-run-ground`, `isolated-directions`,
`square-hill`, `diamond`, `square-hole`, `raised-run`; `run.log` lists every rectangle and probe stop);
the overlay script is `godot/output/fence_review/render_fence_collision.gd` (untracked).

The owner's ask: one fence concept, painted anywhere, with its own collision; no "elevation fence" or
"ground fence". His complaints: the old elevation-fence files were reused instead of renamed or
replaced; the collisions are too wide and off at the bottom.

## (a) Collision: what is there and what it should be

Measured on the wood kit (post drawn 19 units wide, opaque 14 = ±7 round the cell centre; post foot at
y0 = the cell centre; rails from y0−31 to y0−8):

- Every link: a rectangle 52 long (64 − 2 × `posts.half_width`), **28 thick** (2 × clearance 14), centred
  ON the foot line (y0−14 to y0+14). Every linked post: a 28 × 28 square on the foot. Every isolated tile:
  a 64 × 64 square over the whole cell.
- From the north the feet stop at y0−14; **from the south the body's head stops 15 units BELOW the posts'
  feet** with grass between: the "off at the bottom". A north-south fence stops the body 14 from the post
  column, 7 past the post's opaque edge. An isolated tile stops the body 33 units short of the art.

Errors: east-west and diagonal bands 18–20 units too thick and centred 6 units too low (the bottom edge
should be ~16 higher); north-south bands 14 too wide; post squares 14 too wide and 20 too tall; isolated
tiles 50 × 56 too big.

Recommended (wood; other kits follow from their json):

- One band per link, **thickness 8, from y0−10 to y0−2** (centre y0−6), running cell centre to cell centre
  (no `half_width` inset for collision; the inset is for the art and opens a gap at corners). A 45° link
  shifts whole by (0, −6). Result: from the north the feet stop at y0−10 and the lower body hides behind
  the rails; from the south the head stops at y0−2, overlapping the posts' feet by ~3, the Zelda overlap.
- North-south links: **width 14** (±7), centred on the post column.
- Posts: 14 × 8 at [x0 ± 7, y0−10..y0−2]. Isolated tile: the post rect plus its one-cell stub's band; drop
  the full-cell square and the `_bands` / `_add_solid_band` / `_bounds` machinery.
- Constants in `game-constants.json` `fences`: `bandAbove` 10, `bandBelow` 2, `sideHalfWidth` 7
  (replacing `clearance`), read once in `build`, not through `setting()` per post, segment and
  `blocks_point` call.
- **Must go with the thinning:** `Elevation.body_fits` samples only 5 points and `ledge_below` probes a
  point 14 units past the body's side, so a band thinner than ~14 lets a hop or a drop pass over a fence
  (that is why the band was widened to 28). Give the fences `blocks_rect(rect, level)` and
  `blocks_sweep(from, to, level)` and use them in `body_fits` and `ledge_below` instead of `blocks_point`.
- The y-sort is right from both sides and stays; corners are closed; run ends are open on purpose;
  levels are right on the hill and round the hole. A fence on a stairs cell takes the stairs' lower
  level: document or forbid.

## (b) Rename and move

The concept reads a cell's level and writes into the depth map, nothing else of the elevation.

- `game/world/elevation/fences/` → `game/world/fences/`; `elevation_fences.gd` → `fences.gd` (keep
  `NODE_NAME "Fences"`; `PIECES_NAME` → `"FencePieces"`; owner line "world (fences)");
  `elevation_fence.gdshader` → `fence.gdshader`, `elevation_fence_depth.gdshader` → `fence_depth.gdshader`
  (their headers still say "a fence along a hill's rim"); `fence_layer.gd` and `fence_tileset.tres` keep
  their names.
- References: `elevation.gd` (preload, `var fences`, comments), `elevation_occlusion.gd`,
  `elevation_rims.gd` (says fences are built along rims: false), `elevation_stairs.gd` (stairs gaps: that
  code is gone); the 44 scenes' `ext_resource path=` (`fence-park`, `crystal-mine`,
  `rooms/crystal-mine/M4-great-shaft`, `chunks/level-1-c4`, 40 placeholder chunks); builders
  `build_slimeshire_chunks.gd`, `build_crystal_mine.gd`, `tools/region_worlds/region_scene.gd`;
  `scripts/maps/build-fence-park.py`, `scripts/art/build-fence-paint-tiles.py`, `tools/render_fence_park.gd`,
  `tests/test_fences.gd`; docs `FENCES.md`, `ELEVATION.md`, `docs/handover/2026-10-17-chapter1-second-pass.md`.
- Keep: `ElevationGrid` (levels), `ElevationOcclusion` (depth), `elevation_mesh.gd`, the shader includes;
  say so in the header.
- Remove: `_bands`, `_add_solid_band`, `_bounds`, the isolated-tile full-cell case; rename
  `_connected_collision` → `_segments`.

## (c) Bugs and improvements

**High**

1. The 40 placeholder chunks' pit fences were remapped mechanically and partly erased: every corner cell
   of each ring (source −1) and whole runs (e.g. `volcano-ridge-g1` lost 10 of 36 cells, all of row 31).
   Nobody rendered them. Each needs a look, or the region builder re-run after fixing 2.
2. The builders paint the wrong tiles now that the tileset's columns changed: `region_canvas.gd`
   `FENCE_STONE (3, 0)` is sandstone; `build_slimeshire_chunks.gd` `FENCE_WOOD (1, 0)` is snow and its
   `_c4_rim_cell` loop writes all-neighbour tiles while `level-1-c4.tscn` was hand-repainted with arrows;
   `build_crystal_mine.gd` `FENCE_AUTO (0, 0)` "auto" no longer exists, so the mine's 22 cells render wood
   instead of crystal/stone. Re-running any of them regresses the scenes.
3. Hop and drop probing versus band thickness (see (a)).
4. The collision geometry itself (see (a)).

**Medium**

5. Flat worlds (no `elevation` layer) take a separate mount path no test or dev world exercises.
6. `fence_layer._rebuild` rebuilds the whole elevation on every paint stroke; rebuild only the fences.
7. `_can_link` lets an all-neighbour tile link to an arrow tile from any side, so an arrow cannot refuse a
   neighbour; two parallel runs one row apart cross-link.
8. `setting("clearance")` is read per post, per segment and per `blocks_point` segment: cache it.
9. When two styles meet, the north-west cell's style wins unless the other arrow points back: undocumented.
10. `level-1-c4.tscn` paints (−1, 29), outside the chunk (dropped silently); two isolated east arrows at
    (29, 8) and (29, 10) each get a full-cell block.
11. `fence_tileset.tres` was hand-edited and no longer matches `build-fence-paint-tiles.py`: regenerate.

**Low**

12. `render_fence_park.gd` still describes rim fences and "the strip behind the hill".
13. An isolated all-neighbour tile draws an east-west stub (`direction_index` default 2): intended?

## (d) Doc errors (`FENCES.md`)

"The first material picture lets the ground choose a matching style" is false (no auto style; it
contradicts "every material column is a fixed fence style"); the collision paragraph (28 wide, full-cell
isolated tiles, "blocks drops and hops") changes with the fix; the styles table has four headers for three
columns; the Fence Park tool is said to render rim fences; `fence_layer.gd`'s docstring describes the
rebuild cost as a feature; `elevation_stairs.gd` / `elevation_rims.gd` / shader headers still say fences
follow rims and leave stairs gaps.

## (e) Hand-off list for the fence agent

1. Collision: bands 8 thick at [y0−10, y0−2] centre to centre; north-south width 14; posts 14 × 8;
   isolated tile = post + stub band; the three constants read once; delete the `_bands` machinery.
2. Add `blocks_rect` and `blocks_sweep`; use them in `Elevation.body_fits` and `ledge_below`; re-check hops
   and drops over the square hill's south fence and the hole's fence with the overlay script's probes.
3. Rename and move per (b); fix every path; purge the rim and stairs comments.
4. Fix the builders (region_canvas → (2, 0); slimeshire → (0, 0) writing the arrow layout the scene has, or
   stop touching `fences`; crystal mine → the crystal column or stone); update the handover doc.
5. Render the 40 placeholder chunks' pits and crystal-mine; restore the erased corner cells.
6. Document the arrow semantics (or tighten `_can_link`), the mixed-style rule, the stub, the stairs level.
7. Rebuild only fences in `fence_layer._rebuild`.
8. Regenerate `fence_tileset.tres`; update the tests (the 28 / 64 × 64 asserts, a flat-world mount test, a
   diagonal collision test); fix FENCES.md as in (d).
9. Re-render `twig-run-ground`, `square-hill`, `diamond`, `isolated-directions` with the overlay for the
   owner before asking his verdict.
