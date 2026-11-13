# Cave animals (2026-11-12)

Harmless animals for caves and caverns: how they live, their options and where they are placed are
in [docs/godot/VILLAGERS.md](../../../docs/godot/VILLAGERS.md#cave-animals-2026-11-12).

Every image is Magnific GPT 2.5 (`gpt-2-mini`), 3:2, 2k, transparent background, 65 credits; 8 in
all, 520 credits. Each prompt began with the style block of
[docs/assets/visual-style-guide.md](../../../docs/assets/visual-style-guide.md#generating-assets)
and ended with "Each frame isolated on a transparent background, no ground shadow plate, no
scenery, no labels, no grid lines."

## Roughs (`roughs/`) and the board (`board/`)

| Sheet | Grid | Figures | Reference |
|---|---|---|---|
| `cave-animals-1.png` | 4 x 2 | firefly, bat asleep, bat flying, glow-worm, pill bug, pill bug rolled up, cave newt, crystal snail | the town's `roughs/animals-2.png` |
| `cave-animals-2.png` | 4 x 2 | lantern moth, blind cave fish, glow beetle, cave mouse, cave frog, cave cricket, cave crab, three fireflies | the same |

"A character sheet of eight small, harmless, friendly CAVE animals in the same painted style as the
reference animals, cute big glossy eyes, gentle smiles, never scary", then one line per animal.

`board/cave-animals-board.jpg` is the pick board (C1 to C12); `board/cave-animals-game-size.png`
shows the six built animals' frames at the game's size. The bat (C7) was not built: its rough is
the same brown bat as the Glint Bat enemy (`godot/asset/MAPS/enemies/256x256-tile_4x1-glint-bat.webp`).

## Final sheets (`generated/<id>-poses.png`)

One 3 x 2 sheet each, the animal's own figure cut from its roughs sheet as the reference ("the same
... as in the reference"), "six frames of the same ... at the same size". Walkers: "In frames 1 to
3 it is in strict SIDE PROFILE, its head turned fully to face the RIGHT edge of the picture". The
glowing ones: "The light is painted only on the tail itself: no halo, no rays, no glow around" (a
painted halo would spoil the cut and the scale; the game adds the glow).

| Sheet | Frames, in reading order |
|---|---|
| `firefly` | wings raised, level, lowered with the tail bright; the same three with the tail dim |
| `glow-worm` | stretched long, humped, a low hump; long with the tail very bright; long with the tail dim and a blink; front |
| `pill-bug` | standing, two walking steps; rolled into a ball; half unrolled, peeking; front |
| `cave-newt` | standing, two walking steps; sitting and looking up; standing with a blink; front |
| `crystal-snail` | body long, short, half; hidden (the shell alone); long with the crystals shining; front |
| `lantern-moth` | wings open, half raised, nearly closed; half lowered; resting with folded wings; open with a blink |

Packed by `scripts/characters/pack-villagers.py` into `godot/asset/characters/cave-animals/`
(layouts in the town's `packed.json`); scenes by `scripts/characters/build-villager-scenes.py`.

## Tools (`tools/`)

- `cut_roughs.py <roughs dir> <out dir>`: the roughs sheets cut into single figures.
- `board.py <cuts dir> <out dir>`: the pick board.
- `sheet.py <out.png>`: the game-size sheet from the packed sheets.
- `game_gif.py <frames dir> <out.gif> <x0,y0,x1,y1>`: a GIF from frames filmed in the running game
  (`godot/tools/render_door_walk.gd`), at a 1400 x 1024 window. In `preview/`:
  `playground-cave-corner.gif` (the playground's cave corner, where the animals are placed) and
  three closer ones filmed earlier in the playground's cavern room (`cavern-*.gif`), where the
  animals stood first.
