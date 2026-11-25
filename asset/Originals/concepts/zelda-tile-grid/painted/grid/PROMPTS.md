# Our walls painted on the tile grid: the recipe

The dirt and stone in the tile compare lab (docs/godot/TILE_COMPARE_LAB.md "Our art"), painted
2026-11-05 with Magnific's Nano Banana 2.1 (`imagen-nano-banana-2-1`, 65 credits a picture). The
earlier rounds (2026-11-03/04) were deleted when the experiment was paused; what they taught is in the
lab doc. Two steps per set:

1. **Concept**: Nano Banana 2.1, 4:3 at 2k, one reference: `style-h-plateau-crop.png` (a crop of the
   approved H plateau painting, `asset/Originals/elevation/cliff-concepts/h-plateau-a.png`, for its
   level of detail). Four pictures; the one kept is `dirt-concept.png` / `stone-concept.png` (the
   stone's: the only one with real 45-degree corners).
2. **The figure on the grid**: Nano Banana 2.1 at exactly 1600 x 1344, four references in this order:
   `guide-<name>.png` (the template the tool writes; the stone's is the plain one),
   `guide-<name>-numbered.png` (the matrix), `guide-levels.png` (the levels), the concept. Two
   pictures; the one kept (best wall fit, no drift) is `dirt-lumps-nano.png` / `stone-drystone-nano.png`.
   The tool fits it to the guide and cuts it.

| Painting | Wall fit (fitted) | Same-numbered cells differ by (of 255, fitted) |
| --- | --- | --- |
| dirt-lumps-nano.png | 0.84 (0.96) | 30 |
| stone-drystone-nano.png | 0.85 (0.96) | 22 |

## Dirt

Concept:

> A top-down 2D game map in the classic 16-bit adventure-game view (ground seen from above, cliff
> walls seen from the front), painted in exactly the style and level of detail of the reference
> image: crisp, finely textured, richly shaded hand-painted game art with dark warm outlines and
> warm sunlight from the upper left. The scene: a raised grass plateau standing on low grass,
> closed by a tall earthen cliff: a long straight front wall facing the viewer, a 45-degree
> diagonal wall at each front corner, straight side walls on the left and right, and the back wall
> along the top. The cliff is real eroded earth, not stone blocks: big rounded bulging lumps of
> compacted brown soil and clay stacked in rows that follow the wall, each lump lit on its top and
> in deep dark shadow beneath, dark crevices between them, gritty soil grain, small embedded
> pebbles, fine cracks, a few thin roots. Along the whole top edge of the cliff: a narrow band of
> pale packed sandy ground, then a scalloped edge of darker grass, then the plateau's grass. At the
> cliff's foot a dark line and a short soft shadow. The same calm, finely textured grass on the
> plateau and the low ground. No ferns, no flowers, no plants on the cliff, no props, no text.

The figure on the grid:

> Edit the first image: a top-down game tile map, 25 columns by 21 rows of square tiles, 64 pixels
> each, of one raised grass plateau (the UPPER ground) closed by earthen cliff walls on every side,
> standing on low grass (the LOWER ground). The second image is the same map with its tile grid drawn
> and the cliff tiles numbered: cells with the same number are the same tile and must be painted
> identically; it is only a map, do not paint its lines or numbers. The third image is the height
> map: yellow is the UPPER ground (the plateau), blue is the LOWER ground, grey are the walls, and the
> white arrows point downhill, from the upper ground to the lower ground; it is only a map, do not
> paint its colours, arrows or words. Every wall drops from the upper ground to the lower ground: the
> walls along the top of the plateau (with the dip in the middle) drop UPWARD in the picture, to the
> lower ground above them. The fourth image shows exactly how the earth walls must look: paint every
> wall with its big rounded bulging lumps of compacted soil stacked in rows along the wall, each lump
> lit on top with a deep shadow beneath, its gritty texture, small pebbles, fine cracks and thin
> roots, its dark warm outlines, colours and crisp, richly shaded hand-painted rendering, and paint the
> grass with its fine texture. Take only the look from the fourth image, never its shapes: keep the
> composition of the first image pixel-exact, every wall, rim, corner, 45-degree wall and side wall at
> exactly the same position, width and angle, with sharp 45-degree corners, because the result is cut
> into tiles along that grid; same framing and size. Along every wall's upper side, exactly as drawn
> in the first image: the wall's earth, then a band of pale packed sandy ground, then a first grass
> edge (a scalloped band of darker grass), then the plateau's grass. No grass tufts or plants hanging
> over the walls. Where each wall stands on the lower ground: a dark line and a short soft shadow only
> inside the wall's foot, no long cast shadow across the low grass. The same even, calm grass on the
> upper and the lower ground; no flowers, no props, no lighting gradient across the picture, no text,
> no grid lines, no numbers, no arrows.

## Stone

Concept: the dirt's, with "closed by a tall stone cliff" and the cliff sentence:

> The cliff is a dry-stone retaining wall of big rounded grey-brown stones like the reference's,
> laid in courses that follow the wall: each stone lit on its top and in soft dark shadow beneath,
> dark joints between them with a little moss, fine cracks and grain in the stone, a few smaller
> stones wedged between.

and "No ferns, no flowers, no plants on the wall, no props, no text."

The figure on the grid: the dirt's, with "closed by stone cliff walls on every side, standing on low
grass (the LOWER ground); its walls are drawn as plain grey-brown areas, to be painted", the look:

> The fourth image shows exactly how the stone walls must look: paint every wall as its dry-stone
> retaining wall of big rounded grey-brown stones laid in courses that follow each wall's direction,
> about three courses in the height of the front wall (three tiles), the same stone size on every
> wall, each stone lit on top with a soft dark shadow beneath, dark joints with a little moss, fine
> cracks and grain in the stone, a few smaller stones wedged between, its dark warm outlines, colours
> and crisp, richly shaded hand-painted rendering, and paint the grass with its fine texture.

and "the wall's stone" in the rim sentence. Painted from the plain template: from the drawn one the
side and top walls kept the drawn small stones next to the concept's big ones on the front.
