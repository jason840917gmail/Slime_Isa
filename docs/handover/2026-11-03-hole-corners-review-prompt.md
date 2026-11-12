# Review prompt: the cliff walls' inner corners (2026-11-03)

A prompt for a fresh agent: find and fix the artifacts the owner still sees at the inner corners of
cliff walls (first of all the octagon hole in the playground's park). Paste everything below the line
as the agent's task.

---

You are reviewing a drawing bug in Slime Isa (Godot 4.7.2, statically typed GDScript, Compatibility
renderer; repo `D:/projects/Slime isa`, Godot project `godot/`, branch `main`). Read `AGENTS.md` first,
then `docs/godot/ELEVATION.md` "Side walls" (it starts at the heading `## Side walls`; the corner rules
are the bullets "Inner corners fold", "Corners that cannot fold" and "Every other inner corner").

## The problem

The owner still sees artifacts in the corners of cliff walls. His example is the **octagon hole in the
playground's park**: 3 levels deep, short west and east side walls (4 cells long) between 45° faces,
a north (back) edge and a south (front) wall. Spawn the slime beside it with `-- --spawn=2138,4560`. He
said its cliff "before was perfect", but renders of the commits from 2026-10-17 to 2026-11-01 are
identical, so the defects are old and were never caused by recent work.

An earlier session (2026-11-03) changed the corner code and removed the worst of it: a dark shadow
rectangle over the 45° faces, wedges at the bottoms of the side walls and spikes under the north
corners. The owner still sees artifacts. The pictures are in `asset/Originals/elevation/octagon-hole-fix/`:

- `octagon-hole-before-after.png`: the whole hole, before (left) and after (right) that session's fix.
- `octagon-hole-corners.png`: the four corners close up, before (top row) and after (bottom row).
- `octagon-hole-feet-now.png`: the feet and shadows close up, before (top) and now (bottom).

What is still visible in the "now" pictures (verify this yourself; he may mean more than this):

- the foot shadows at the inner corners are made of hard-edged polygons: light wedges, darker
  quadrilaterals and visible facets where the shadow pieces of two walls overlap or leave a gap
  (south corners especially);
- thin bright or dark slivers and a dashed dark line along the foot of the 45° faces next to the
  north corners;
- a hard vertical seam in the stone texture where a side wall's strip meets a 45° face. Judge whether
  this reads as a real stone corner or as a defect: the art should run on, or turn the corner the way
  it does elsewhere.

If you cannot tell which corners he means, ask the owner for a screenshot. Do not guess.

## The code

All of it is in `godot/game/world/elevation/sides/elevation_sides.gd`. This file draws every cliff
in every world, so a change here changes every world. Its header comment explains the model. Key
pieces:

- **`reach(n, drop)`:** a wall's fibre for a normal and a drop.
- **`_border`, `_add_corner`:** the rounded border and its corners. A corner has first/last points,
  the vertex, e_a/e_b, n_a/n_b, convex/back/fold/turn and drop_a/drop_b.
- **`_add_chain`:** one chain's whole wall. It sets the fibres, runs `_caps` and `_fold_corners`, then
  the 2026-11-03 additions `_open_corners` and `_meet_feet`, then the pieces:
  - `_add_wall`
  - `_add_corner_stones`
  - `_add_top_edge`
  - `_add_foot` (with `_mitre_shadows`)
  - `_add_shape` (walkability)
- **`_add_foot`:** the foot line and its shadow ring, built from FOOT_UP, FOOT_OUT, SHADOW_PER_LEVEL,
  SHADOW_EAST, SHADOW_SOUTH and FOOT_SHADOW. The shadow is translucent pieces drawn per segment, so at
  an inner corner two walls' shadows overlap (doubling up) or leave a gap. This is the likely source
  of the faceted shadows.
- **The shader:** `godot/game/world/elevation/sides/elevation_sides.gdshader`. It draws the pieces
  by kind; the vertex colour r is the kind (KIND_WALL 0, KIND_SIDE 0.2, KIND_CORNER 0.3, KIND_FOOT 0.5,
  KIND_FOOT_WATER 0.54, KIND_FILL_LOW 0.6, KIND_FILL_TOP 0.7, KIND_EDGE 1.0).

The 2026-11-03 session's changes are uncommitted: `git diff -- godot/game/world/elevation/sides/elevation_sides.gd`
shows them (about 220 lines), and `HEAD` holds the old version. They are:

- **`_open_corners`:** an inner corner of a side wall and a front wall or back edge that
  `_fold_corners` could not fold, because the runs are shorter than FOLD_RUN. The side strip widens
  from the corner along the corner's edge, and the front wall's foot starts where the two feet meet,
  with SEAM_SHADE fading the shadow in. At a back edge the strip runs on to its own foot line.
- **`_meet_feet`:** at every other inner corner, the two walls' foot lines are cut to meet at one
  point (they used to cross).
- **`_mitre_shadows`:** each shadow's depth near an inner corner is clipped to the corner's
  bisector. SHADOW_MITRE is 1.0.

Approaches already tried that failed:

- **Treating 45° faces as side walls:** this added seams at the north corners. `_open_corners` now
  skips a corner when `|n_side.y| > 0.3`.
- **Extending the feet without marking them folded:** they wobbled and crossed into bow-ties.
- **Cutting the folded fibres short (a `_cut_fold`):** this made fans of dark triangles. It was
  reverted.
- **Mitring the shadows at open corners:** this cut a V notch. Open corners are now skipped.
- **SHADOW_MITRE 0.8:** this left a light gap.

Each of these was a patch on the per-segment pieces. Before adding another, judge whether overlapping
translucent pieces can ever meet cleanly at a corner. A different design may be the real fix, for
example:

- one shadow polygon per corner;
- a blend that does not add up (min or max instead of alpha-over);
- a shadow the shader computes from the distance to the wall's foot.

Weigh any such change against the rule below about reusing what works.

## How to see it

Renders come from Godot's movie maker, which needs a renderer, so do not pass `--headless`. Use the
console exe:
`C:/Users/User/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`.
Debug scripts are in `asset/Originals/elevation/octagon-hole-fix/debug/`:

- **`play.gd`:** plays the playground. `WALK_PLAN="1.0:;3:"` stands still.
- **`kinds.gd`:** draws the Sides meshes in false colour by kind, half see-through so overlaps show:
  - wall red (yellower on a side)
  - corner stone green
  - foot blue
  - fill grey or white
  - top edge magenta
- **`feet.gd`:** draws only the feet, striped per piece and shaded by depth.
- **`fibres.gd`:** draws the walls' fibre stripes and stone courses.
- **`hide_group.gd`:** hides the elevation groups listed in `HIDE`, e.g. `HIDE=Shade`.

To render, run this from the repo root in Git Bash:

```bash
G="C:/Users/User/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"; D="$PWD/asset/Originals/elevation/octagon-hole-fix/debug"; OUT="<your scratch folder>/now"; mkdir -p "$OUT"; WALK_PLAN="1.0:;3:" timeout 400 "$G" --path godot --write-movie "$OUT/f.png" --fixed-fps 15 --quit-after 45 -s "$D/play.gd" -- --spawn=2138,4560 > "$OUT/log.txt" 2>&1
```

What the render gives you:

- **The frames:** 2048×1792; use the last full one, `f00000044.png`.
- **Where the hole is:** its west side wall is around x 400–700 and its east one around x 1360–1660,
  for y 500–980.
- **The other debug scripts:** run them the same way with `ALPHA=0.55` or `ALPHA=1.0`. Their frames
  end at about `f00000039.png`, with `--quit-after 40`.
- **Comparing:** crop and enlarge with Pillow; compare before and after side by side.

Notes on running it:

- A run takes about a minute.
- Debug runs rebuild stale elevation caches themselves, because `elevation_sides.gd` is one of the
  cache's scripts.
- To get the old picture, copy the file from `git show HEAD:<path>` over it temporarily, render, then
  put the current version back.

## Rules (never break them)

- **No branches, no commits:** stay on `main`, create no branch, and commit nothing. The owner
  commits when he asks.
- **Tests only when asked:** run no tests (`pnpm test:godot`, `tools/verify_scenes.gd`) unless the
  owner asks. A `--check-only` compile of an edited script is fine:
  `"$G" --headless --path godot --check-only -s res://game/world/elevation/sides/elevation_sides.gd`.
- **The owner's editor is often open:** no headless `--import`. Tell him which scenes to reload
  before he does a save-all.
- **The file has CRLF line endings:** edit it so they survive. Python with `newline=''` works;
  shell heredocs collapse backslashes.
- **Reuse what works:** fix the shared corner code for every case. No special case for this hole by
  position, size or world. Every world's cliffs use this code: before you finish, render other inner
  corners to check you broke nothing:
  - the other park spots, e.g. spawns `1280,2500`, `2300,2500`, `1280,4200`, `2300,3600`;
  - the sky corner, spawn `6300,4640`;
  - one or two chunk worlds.
- **Pictures first:** the owner judges by pictures. Show him the before/after renders early with
  `SendUserFile` and do not go long without showing anything. Read reach and size the way he does:
  from what is on screen.
- **Rebake once at the end:** after the final change, rebake every world's elevation cache (the
  exports need it), then say that it touched the caches of chunks other sessions are editing:
  `"$G" --headless --path godot -s res://tools/bake_elevation.gd`
- **Keep the docs truthful:** update the corner bullets in `docs/godot/ELEVATION.md` "Side walls" to
  match what the code does.

## What to deliver

1. A diagnosis: for each artifact, which piece and which function makes it, with a false-colour
   render that proves it.
2. A fix in the shared code, with before/after pictures of the hole's four corners and of the other
   spots, with nothing else changed.
3. A short list of what is untested: the web build, the editor view and the tests.
