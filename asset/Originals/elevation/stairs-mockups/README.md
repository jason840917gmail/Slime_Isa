# Stairs on every side: approved design (2026-10-06)

The mockups the elevation stairs were built from. The game draws them with
`godot/game/world/elevation/elevation_stairs.gd` (geometry after `stairs_mockup.py`'s `Flight`)
and `elevation_stairs.gdshader`; how they are painted and how they work is in
[docs/godot/ELEVATION.md](../../../../docs/godot/ELEVATION.md). This folder keeps the approved
design and the tools that drew it.

- `stairs-overview.png`: an octagon hill at level 1 and 2, a flight on each of its 8 sides,
  one cell and two cells wide.
- `stairs-closeups.png`: the five designs at game size (2 px per world unit).
- `stairs-front-variants.png`: a front flight with a railed or an open landing, one or two cells
  wide.
- `stairs-north-runs.png`: the N flight at four runs per level, beside the S flight.

## What the owner asked for

- Stairs on all 8 sides of a hill or hole, in the cliff's art and colours. Lateral (E/W) flights
  look different from front ones, in the same style.
- Real stairs: a flight is a structure that runs out from the wall onto the lower ground, not
  steps painted on the wall face.
- Flights continue past the rim: a flat landing on the higher ground at the top.
- Railings on both sides, for the look and so the player can't step, drop or jump off a stair's
  side (after the A Link to the Past stairs, e.g. the Eastern Palace).
- Back flights (N, NE, NW) look smaller than front ones, as the camera sees them foreshortened
  (`stairs-north-runs.png` compares N runs of 2, 1.5, 1.25 and 1 cells per level; the owner chose
  1.5).
- Options to keep: **railed or open landing**, **one or two cells wide** (two side-by-side columns
  are one flight, railings only on its outer sides).

## Projection

A point at ground (x, y) and height h (world units) is drawn at screen (x, y − h); one level is
64 units. Along a view ray y + h grows towards the camera, so a pixel's depth is y + h (the same as
the elevation depth map's ground position, feet y + 64 · level). Faces whose normal points north
(or exactly east or west) are never seen.

## A flight

Local frame: `s` along the flight's direction D (down the stairs, 0 on the rim), `t` across it
(T = D turned 90°), `h` up. The rim's midpoint is on the top level, at ground (rim x, rim y + 64 · L)
for a rim drawn at screen (rim x, rim y).

| | World units |
|---|---|
| Walkable width | 64 per cell (one or two cells); `half` = 32 or 64 |
| Steps | 3 per level, rise 64 / 3 ≈ 21.33 |
| Run per level | S, E, W: 64 (one cell). SW, SE, NE, NW: 64·√2 (one diagonal cell). N: 96 (1.5 cells, three half cells; at one cell the camera sees the steps edge-on and they vanish, at two the flight looked too big for one facing away) |
| Step depth `run` | run per level / 3 |
| Top landing | s from −32 to 0, at the top level (into the higher ground) |
| Last step | at the lower level, `run` + 11 deep; the flight ends at `end` = 3L · run + 11 |
| Railings | 18 thick, outside the walkable cells (t from ±half to ±(half + 18)); from the landing's start (railed landing) or from the rim (open landing) to `end`; top 24 above the nosing line, flat over the landing and the last step |
| Nosing line | h(s) = 64L · (1 − s / (3L · run)), clamped to 0 … 64L |
| Newel posts | 20 long at both ends of each railing, 10 above it; flush with the railing's inner face and 6 proud of it on the outside only, so they never narrow the walkway (owner, 2026-10-06: posts that stood 3 into the walkway blocked the slime at a flight's end); the top posts stand on the higher ground (railed landing) or on the lower ground at the rim (open landing) |

Faces, all opaque (the mesh cuts the shapes):

| Face | Where | Texture |
|---|---|---|
| Landing | s −32 … 0, t ±half, h = 64L | tread |
| Riser k (k = 0 … 3L − 1) | s = k · run, h from 64L − k·21.33 down by one rise; faces D | riser (only S, SW, SE show them) |
| Tread k | s from k · run to (k + 1) · run (the last to `end`), h = 64L − (k + 1)·21.33 | tread |
| Railing top | follows the nosing line + 24 | coping |
| Railing sides and ends, posts | outer and inner faces, the end faces | cliff rock (`meadow-rock-wall`, courses level with the cliff's: v = depth below the top level) |
| Post tops | flat | coping |

The railings' inner faces run from the ground up, so they also close the stair body's sides under
the steps; there is no separate cheek face.

What shows from each side (the mockups draw every face and let the depth test decide):

- **S**: landing, risers and treads between the two railing tops; the bottom posts' fronts.
- **SW / SE**: risers face the wall's way (lit on SW, dark on SE), the railing on the side facing
  the camera shows its whole outer face.
- **E / W**: treads seen from above (risers are edge-on), the near railing's outer face (south)
  in front of them and the far railing's inner face behind them.
- **N**: only treads, each partly hidden by the one above; railing tops; the top posts' fronts on
  the landing. The landing lies in the walk-behind strip under the back rim.
- **NE / NW**: treads stepping away, foreshortened, and the outer face of the railing that faces
  the camera.

Light as the walls' (`elevation_wall.gdshader`): tops 1.0, faces SW 1.0, S 0.86, SE 0.66; no
baked light in the textures. The mockups add contact shadows (tread edges against the riser
above and the railings, riser tops under the nosing), a light nosing edge, dark lines where faces
meet, the lower ground's foot strip (`highland-foot.png`) where railings and posts stand on it,
and a cast shadow to the lower right (20 units per level, as the cliffs').

## Textures

Magnific GPT 2.5 sources in `asset/Originals/elevation/generated/` (2026-10-06, 600 credits),
all generated with the cliff wall and the old stairs as references:

| File | Used | Row (source px, crevice to crevice) |
|---|---|---|
| `stairs-tread-a.png` | treads and the landing (seen from above), one row per step | 394–530 |
| `stairs-riser-b.png` | risers, one row per rise, baked × 0.8; also the coping (one row across a railing top, tinted halfway to the rock's colour) | 322–471 |
| `stairs-tread-b.png`, `stairs-riser-a.png` | spare candidates | |
| `stairs-steps-a.png`, `-b.png` | a tread and its riser baked together (not used: separate textures suit every side) | |

Scale: a row is one step (21.33 units) deep or high, 6.375 source px per unit along a step.
The sources are 1024² with alpha about 0.87–0.98 (the transparent-background flag).
`scripts/art/build-elevation-art.py` packs these rows, opaque and periodic in x, into
`godot/game/world/elevation/art/meadow-rock-stairs-tread.png`, `-riser.png` and `-coping.png`.

## Gameplay (the elevation owner's plan, 2026-10-06)

Railings are solid at every level: they close the sides of the run over the lower ground and of
the landing on the top; the ledge drop and the jump's landing search treat them as blocked, so
nothing leaves a flight sideways. Railings are drawn into the depth map, so a body behind a front
railing hides its lower part. Bodies take the level of the stretch they stand on (the landing is
the top level, the last step the bottom level).

## Re-running the mockups

```
"<Godot 4.7.2 console exe>" --path godot -s "<repo>/asset/Originals/elevation/stairs-mockups/stairs_backdrop.gd" -- --out=<work dir>
python asset/Originals/elevation/stairs-mockups/stairs_mockup.py <work dir>
python asset/Originals/elevation/stairs-mockups/stairs_mockup.py <work dir> variants
```

The first renders the octagon hill with the game's own elevation drawing (windowed; about 8 MB
per level, keep them out of the repo). `stairs_mockup.py` holds the geometry (`Flight`), the
texture mapping (`colour_of`) and the octagon's sides (`sides()`); the overview and close-up sheets
were composed from its output.
