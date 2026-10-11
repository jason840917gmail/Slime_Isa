# Fixed-cell manual cliff prototype

2026-10-09. New sprite sheet, TileSet, scripts and labs only. Earlier cliff experiments and
the game worlds are unchanged. Built-in ImageGen generated and revised the painting; the
packing tool resampled its uniform grid once to 128px cells. No runtime deformation or shader.

## Open and paint

Open `res://game/scenes/worlds/cliff-manual-tiles-lab.tscn` and press F6.
For editing, select `Cliffs` in Godot and pick individual tiles in the TileMap palette.
The three terrace nodes are separate TileMapLayers sharing the same TileSet; their transparent
rims reveal the lower plateau. Every layer has scale 0.5: 128px artwork = 64 world units.

Runtime controls: WASD moves the slime; C shows the exact collision polygons; Ctrl-click
places the slime on a top or low ground; wheel zooms; right-drag pans; Home shows everything;
1/2/3 show heights, terraces and the L shape. Placing the slime is a lab aid, not climbing.

Sprite sheet: `godot/asset/MAPS/cliffs/manual-prototype/128x128-tile_6x6-cliff-manual.png`.
TileSet: `godot/game/world/cliffs/manual_prototype/manual_cliff_tileset.tres`.
Every tile is fixed size with physics layer 1 polygons; grass interiors are walkable.
No terrain auto-connect data is set: this is intentionally a manually selected tile palette.

The earlier `cliff-manual-prototype.tscn` is the first join audit, with terraces on one layer;
use **cliff-manual-tiles-lab.tscn** for painting and physics auditions.
The builder refuses to overwrite an existing lab, so it cannot erase hand-painted changes.

## Sheet coordinates

Columns A–F, rows 1–6 (human labels); Godot atlas coordinates are zero-based.

| Cells | Intended role |
| --- | --- |
| A1–C3 | Classic 3×3 grass top: north corners/edge, sides/centre, south corners/front lip |
| D1/E1/D2/E2 | Inner NW/NE/SW/SE corners |
| F1/F2 | Plain grass alternatives |
| D3/E3/F3 | North/west/east rim alternatives |
| A4/B4/C4 | Wall cap: left/middle/right |
| A5/B5/C5 | Repeatable wall body: left/middle/right |
| A6/B6/C6 | Wall foot: left/middle/right |
| D4/E4/F4 | Single-row wall: left/middle/right |
| D5–F6 | Alternative wall body and foot |

Use a front lip row followed by short-wall pieces for one-row cliffs. For higher walls use
cap, zero or more body rows, then foot. Rectangle dimensions change by adding whole tiles.

## Painting repairs, in priority order

See **cliff-manual-painting-guide.png**. It enlarges each cell and labels every repair address.
The marked picture is a diagram, not a replacement sprite sheet.

1. **B2 grass centre:** the current weeds make an obvious repeated motif. Paint a quieter grass
   field. Check B2 beside itself horizontally and vertically, then A2/B2/C2 and B1/B2/B3.
   Match the colour, texture and alpha of opposing edge pixels; vary the interior afterward.
2. **A4–C4 cap:** remove the second green fringe. A3–C3 already supply the grass lip, so the
   cap should begin with earth and roots continuing from that lip, then rock. Do not add a
   transparent gap between them. This fixes the doubled bright stripe on every front face.
3. **B5 repeating rock:** paint rock shapes and fissures that continue across B5's left/right
   and top/bottom joins. Preview a 3×3 repetition of B5 while painting. Match B4's lower edge
   to B5's top and B5's bottom to B6's top. Then fix the vertical joins of A5/C5, and the
   horizontal A4/B4/C4, A5/B5/C5, A6/B6/C6 joins. Current cracks visibly restart each cell.
4. **D1/E1/D2/E2 inner corners:** keep the cutout only in the named corner. At 128px, its
   intended corner cutout is 24×24px; paint a chunky but continuous rim around that cutout.
   The other connecting sides must remain full grass. These are not approved final shapes.
5. **D3/E3/F3 rim alternatives and F1/F2 ground:** the generator added unwanted surrounding
   borders. D3 has a north rim only, E3 a west rim only, F3 an east rim only. Fill the other
   edges with grass to the cell boundary. F1/F2 must be completely filled grass, with no rim.
6. **Silhouettes and collision:** cyan lines on the guide show nominal grass boundaries:
   west x=24, east x=104, north y=24, south lip y=104 in 128px cells. Keep irregularity near
   these lines and return to the same position at neighboring edge joins. The current art
   wanders toward cell edges, so some collision contours need painting alignment. Use C in
   the lab to compare; polygons are a first pass and can also be adjusted in the TileSet.

Edit the actual **768×768 runtime PNG on a 128px grid** so the existing palette and collision
coordinates stay valid. Keep a backup first. Reimport that PNG in Godot after painting; do not
run the packer again over hand-painted fixes. The larger generated master is retained in
`asset/Originals/elevation/cliff-manual-prototype/`, with the prompts and layout reference.

## Verification and limits

Scripts parsed in the editor; both baked lab scenes loaded and rendered. A direct runtime
collision probe stopped against the short wall at y≈581 and the north rim at y≈223; movement
inside the grass remained free. Collision overlay toggled successfully. Overview and collider
screenshots were inspected. This is a useful painting/physics scaffold, not finished art.

No automated integration suite, scene verifier, web export or headless import was run.
The resource builder ran headlessly after the editor imported the new PNG; it created only
new lab resources. The editor still reports the previously observed renderer startup error
`texture_set_size_override: Parameter "texture" is null`; the lab subsequently runs and
captures normally. No edits were made to address that unrelated error.

All layers share world collision: there is no elevation-aware movement, stairs, drops or
walking behind. Nested layers provide visual terraces, not a finished multilevel traversal
system. L-shape inner corners and feet need painting review before adopting them in a world.
