# Tile compare lab

**Paused 2026-11-05** (owner: "we are going to pause this experiment for now"). This page is the state
it was left in; the failed rounds were deleted then, their lessons are under [Our art](#our-art).

2026-11-03, owner's request: "i want this exact tileset and then one with our art so i can paint
with both and compare". The ground and wall tiles of *A Link to the Past*, reverse-engineered from
five screenshots (and a low ledge from a sixth), and the same tiles in our art, stone and dirt. A dev
scene, not a world system: our cliffs stay the [elevation](ELEVATION.md) layer's.

The Zelda tiles are a **reference only**: Nintendo's pixels, cut from the owner's screenshots. They
live in `godot/game/dev/tile_compare/`, which both web presets leave out (`game/dev/*` in "Web",
`game/dev/tile_compare/*` in "Web (dev)"). Never paint them into a world, move them out of the dev
folder, or give a picture of them to an image generator as a guide for our art.

## Open and paint

Open `res://game/dev/tile_compare/tile_compare_lab.tscn`. Its TileMapLayers, one below the other,
each a tile 32 world units (about a slime wide, as Link is a tile wide; the owner's choice, our cells
are 64):

- **Zelda**: `zelda_tileset.tres`, 16 px tiles, layer scale 2, nearest filtering: all the figures.
- **Stone**, **Dirt**: `stone_tileset.tres`, `dirt_tileset.tres`, 64 px tiles, layer scale 0.5: the
  single figure painted in our art (a dry-stone wall of big rounded stones; earth in bulging lumps),
  at the same place as on the Zelda layer, each cell its own painted tile ([Our art](#our-art)).

Our sets have **the same tiles as Zelda's** (owner, 2026-11-04: "i should be able to create something
like this with the tile map"): every cell is named with the Zelda code it paints (`tile_name`
metadata), so a figure painted with Zelda's can be painted with ours, code for code. Select a layer and
pick tiles from the TileMap palette (drag a rectangle to take a piece of wall). F6 shows the lab
through its camera. No collision and no terrain auto-connect. What the owner painted is his: on the
Zelda layer outside the figures (rows -7 to -1, his whole figure in progress) and on the Dirt layer.

The palettes show where each tile goes: six figures, compacted (no grass outside the walls, no row or
column twice in a row: "maybe we don't need to put many duplicate tiles"):

- the single figure (2026-11-04): the owner's whole figure (his top edge with both corners, a 45° step
  down and the side walls) extended to hold every tile but the cliff ends ("give magnific a sole
  figure that hold all the tiles ... make wall at least 2 tile wide even if tiles repeat"): a dip in
  the top edge (K2, Q4h), a two-step 45° at the top-left corner, a jog in each side wall (J3), the U's
  front; every neighbour pair one Zelda's own figures have. 43 of the 60 tiles: no cliff ends (they
  need a cliff fading into ground of its own height) and no low ledge (it came later);
- the owner's U plateau (side walls with their 45° jogs, a two-level front) and V plateau (both cliff
  ends);
- the top side: a plateau's top edge stepping down a 45°, and its mirror (screenshot d);
- the top corners: a plateau's top meeting its side walls through a small 45°, both sides
  (screenshot e): the small 45° is the top side's own 45° tiles, the side wall starts right under them;
- the low ledge (2026-11-05): the rain screenshot's ledge, a top side one tile lower with a 45° going
  down at each end, at the bottom of the Zelda palette. Not painted in the lab (a `--force` rebuild
  would drop the Stone and Dirt layers' painting): paint it from the palette.

Zelda's palette: 60 tiles in 593 places.

## The set

The analysis is in `asset/Originals/concepts/zelda-tile-grid/`: every screenshot mapped on its 16 px
grid with each cell's code, `walls-1..3` (a house cliff, a round plateau, a side wall) and `walls-7..9`
(the top side, the top corner, the rain ledge); `walls-4-tile-maps.png` (a, b, c as code maps),
`walls-5-tile-set.png` (the front and side tiles cut in 8 px quarters), `walls-6-right-side.png` (the
right side as the left mirrored); the codes as data in `walls-tile-map.json` and
`walls-top-tile-map.json` (`*` = close but not exact: tufts, Link over it); `top-side-vs-ledge.png`
(why the low ledge's tiles differ from the tall top side's). One cell is 16x16 game pixels. A plain
code is the left side (or as in its screenshot), `h` its mirror; straight walls and grass have none.

| Group | Tiles |
| --- | --- |
| ground | G1 grass (the tufts and dirt patch of the analysis are not on the sheets) |
| front wall (faces south) | S1 rim, S2 face, S3 base: 3 tiles tall, the same column everywhere; S2 repeats for a taller wall |
| 45° front | D1–D5: lip, upper rock, face, base, the extra face band where it crosses a side wall |
| side wall | W1–W3: lip + rock, rock, foot |
| turns | J1–J3: side wall into the 45° and back |
| cliff end | E1–E5: tip, outline, end of upper, of face, of base |
| top side (faces north) | N0–N2: the wall's shadow on the low ground behind (with its edge), the back wall's top, the back wall with its whole lip down to the plateau grass: 3 tiles tall, as the front |
| 45° top side | Q0–Q4: the shadow's edge, the wall's top, its middle, the wall with its lip, the lip's last bit on the plateau (the edge running down to the right; Qh up); K1 the straight top side's wall turning down the 45°, K2 the 45° turning into a lower straight top side |
| low top side | N3: a ledge one tile lower, its shadow and wall top in one tile, over N2 (2 tiles tall); its 45°: Q5 the shadow's edge, Q6 the wall, over Q3 and Q4; K3 its straight wall turning down the 45° |
| top corner | no tiles of its own: the 45° top side (Qh on the left, Q on the right) with the side wall (W1–W3) right under Q3 Q2 Q1 |

What the screenshots show: a 45° meets a straight wall with no corner tile, front or top; a side
wall needs the turn tiles on the front, none at the top; the right side is the left one mirrored.
Every edge tile holds its whole transition from the wall to the grass (owner, 2026-11-04); the tile
against the upper ground is the same at any wall height (N2 under a tall or a low top side), the tiles
above it depend on the height.

The low ledge's screenshot is in the rain, which darkens every colour, so its four tiles (shot `f` in
`tile-sources.json`, from `native-ledge.png` on its grid at x 7, y 1) are rebuilt: the rain's colours
mapped to the top side's day colours (learned where N2, Q3 and Q4 show in both), the majority of every
copy kept; about 85-95% of the pixels as the game draws them, the rest a near twin colour. Missing: the
low 45° landing on a lower straight ledge (a low K2), a low ledge meeting a side wall, and the exact
pixels; a daytime screenshot of a low ledge stepping down a 45° and back would give all three.

## Our art

Painted by Magnific from one figure on the tile grid, and cut cell by cell. Everything in
`asset/Originals/concepts/zelda-tile-grid/painted/grid/`, the prompts in its `PROMPTS.md`:

1. **A concept in our style**: a free painting of the cliff (front wall, 45° corners, side walls, the
   rim), with `style-h-plateau-crop.png` (a crop of the approved H plateau painting) as the reference:
   `dirt-concept.png` (bulging lumps of soil), `stone-concept.png` (a dry-stone wall of big rounded
   stones).
2. **The figure on the grid** (Nano Banana 2.1, `imagen-nano-banana-2-1`, exact 1600 x 1344), from
   four pictures the tool writes or keeps:
   - `guide-<name>.png`, the template: the single figure (`GUIDE`) drawn in Zelda's tile shapes, 64 px
     a tile on 25 x 21 tiles, with Zelda's rim along every wall's plateau side (owner: "wall, then a
     light ground, then a first grass edge, finally a grass that will match your ground"). The stone's
     is **plain** (its walls' drawing blurred away, `plain_guide`): from the drawn one its side and top
     walls came back with the drawn small stones next to the concept's big ones;
   - `guide-<name>-numbered.png`, the matrix: the grid drawn and every cell numbered, the same number
     for the same tile (owner: "numerate each tile in the matrix letting know what tiles are the
     same");
   - `guide-levels.png`, the levels: upper ground yellow, lower ground blue, walls grey with arrows
     downhill, labelled (owner: signal "what is the lower ground and the upper ground");
   - the concept, for the look only ("take only the look from the fourth image, never its shapes").
   Painted: `dirt-lumps-nano.png`, `stone-drystone-nano.png` (wall fit 0.84-0.85, 0.96 fitted).
3. **Fitted to the grid** (`fit_to_guide`): the walls come out up to half a tile thicker, their edge
   in the next cell (owner: the edge "compose of 2 tiles instead of 1"). Each painting is warped so its
   walls' edges lie on the guide's: every guide edge pixel takes the shift to the nearest painted edge
   pixel on the same side, the shifts spread smoothly and fade out away from the walls, applied in 64
   small steps so the painting bends but never tears (owner on the first fit: "there are artefacts on
   the sides"). Written as `<name>-fitted.png`.
4. **The cut**: every cell of the fitted painting is its own tile, named by its Zelda code; the lab's
   figure is the fitted painting, pixel for pixel. The sheets import lossless.

What failed (2026-11-03 to 11-05; deleted): our own drawn textures as the art ("not good enough", "i
dont like your art"); one cut per code reused across the figure, and front tiles flipped to make top
tiles ("tiles don't fit and blur", "i can see the joint and the differences"): one-off paintings seam
wherever their cells are pieced; separate figures in one guide (confused the model); GPT 2.5 and
restyles (drifted off the grid, long shadows); paintings without the levels map (the top side painted
as a front wall, twice); retouching the wrong top side (disliked); richer prompt words alone (the model
copies the guide's flat look), the H crop alone as style (uneven, long cast shadows), Magnific's
creative upscale (invented diamond grass, cracked mud).

Limits: the paintings are one-off pictures, not tiles made to repeat; the same-numbered cells are
alike but not identical (they differ by 22-30 of 255). Painted as in the guide, the figure is exact;
dragged as rectangles from the palette it stays whole; a painted cell placed next to cells from
elsewhere shows a seam. The fit squeezes the stones and lumps a little where it moved them most. The
dirt's 45° corners came out rounded and its dark grass edge soft. Tiles for a world would need
painting to repeat; the owner's edge palette idea (a palette of only edge tiles, many per ground style
and colour) waits on this set.

## Rebuild

`python scripts/art/build-tile-compare-sheets.py` rewrites the sheets and TileSets,
`tile-layout.json`, the templates (`painted/grid/guide-*.png`), the fitted paintings and the pictures
`tile-compare-sheets.png` (every sheet), `tile-compare-preview.png` (the lab's layers) and
`tile-compare-single.png` (the single figure in all three sets). A new painting: put it in
`painted/grid/` and name it in `VARIANTS`. It keeps the lab scene (what was painted in it) unless given
`--force`; `--force` rebuilds it and keeps what was painted on its Zelda layer outside the figures, by
tile name (`--no-carry` drops it; use it when tiles changed meaning), but not the Stone and Dirt
layers' painting. Changing the figures (`FIGURES`) moves the tiles on the sheets (a new figure goes at
the end, so the others keep their places). Let the editor import the sheets, and reload the lab if it
is open.
