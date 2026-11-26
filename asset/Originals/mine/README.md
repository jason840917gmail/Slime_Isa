# The Crystal Mine: sources

Chapter 3's dungeon (built 2026-10-17; [DUNGEONS.md](../../../docs/godot/DUNGEONS.md#the-crystal-mine-built)).
Every file here is one Magnific GPT 2.5 generation (`gpt-2-mini`, 1:1, 1k, transparent background,
Lili's sheet as the style reference), a 1024 px sheet with four pictures in a 2 x 2 grid. Each was
the first and only take.

| File | Pictures (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `colossus-sheet-a.png` | the Crystal Colossus standing hunched, a foot raised (the stomp's tell), the stomp landed in shards and dust, reeling with his chest armour cracked open and glowing (the weak spot) | `godot/asset/MAPS/enemies/384x384-tile_9x1-crystal-colossus.webp` (until 2026-10-17 `384x384-tile_8x1-...`), frames 0 to 3 |
| `colossus-sheet-b.png` | climbing a wall seen from behind, throwing a Crystal Mite down from the wall, landed from a jump, defeated (a heap of crystal, the Pearl rising) | the same strip, frames 4 to 7 |
| `colossus-sheet-c.png` (2026-10-17, the Pearl mid-dungeon rework; Lili's sheet and the two Colossus sheets as references) | sprawled face down after falling off his wall, his back's crystal split open and glowing, dazed (his stun); the small calm crystal golem he shrinks back into once beaten, from the front, walking left, from behind | the same strip, frame 8 (now `384x384-tile_9x1-crystal-colossus.webp`); `godot/asset/MAPS/enemies/192x192-tile_3x1-small-crystal-golem.webp` |
| `mine-props-a.png` | the mine cart, the ore lift (a plank platform with a crank), the iron-banded ore crate (a heavy block), the rotten timbers (the Heavy Roll's lock) | `godot/asset/MAPS/props/mine/256x256-mine-cart.webp`, `-ore-lift`, `-ore-crate`, `-rotten-timbers` |
| `mine-props-b.png` | the crystal lens on its post (the Bow's target), the same lens struck and glowing, the crystal veil grown across a passage, the veil shrunk back | `256x256-tile_2x1-crystal-lens.webp`, `256x256-tile_2x1-crystal-veil.webp` |
| `mine-props-c.png` | thick living roots and rocky handholds on a slab of cliff (the Feral skin's climb), a miner's lantern on a bracket, the rails' buffer stop, Pearl 3 on a crystal cradle | `256x256-root-wall.webp`, `128x128-mine-lantern.webp`, `256x256-buffer-stop.webp`, `256x256-pearl.webp` |
| `mine-props-d.png` | the mine gate shut (cold lamp cups), the gate open (the cups burning), a rock stump (cover), a heap of ore with a pickaxe | `256x256-tile_2x1-mine-gate.webp`, `256x256-rock-stump.webp`, `256x256-ore-heap.webp` |
| `mine-props-e.png` (2026-11-25, the rebuilt Mine's dressing; 1536 x 768, a 4 x 2 grid) | top row: a timber pit-prop set (two posts, a cross beam, iron brackets), a ladder's foot with its upper rungs snapped off, a lift gantry (an A-frame, a pulley wheel, two ropes), a stack of spare props tied with rope; bottom row: a heap of fallen slate with crystal shards, a lantern post with a lit miner's lantern, a tipped ore cart spilling blue ore, a pickaxe and a shovel by a crate | `godot/asset/MAPS/objects/dungeon/decor/mine-pit-props.webp`, `-ladder-foot`, `-lift-gantry`, `-spare-props`, `-slate-heap`, `-lantern-post`, `-tipped-cart`, `-tools-crate` (`scripts/art/pack-mine-decor-art.py`; the dungeon decor set's `mine-*` scenes), placed in M14, M1, M5, M10, M11 |
| `smith-sheet.png` | the smith, Pip's dad, at his mine camp: standing with his hammer, the hammer raised to strike, holding out the Lantern, pointing | `godot/asset/characters/authored/npcs/smith.webp` (4 x 1, 260 x 280 cells) |

`python scripts/art/pack-mine-art.py` cuts each sheet along its emptiest middle row and columns,
trims each picture, and draws the Colossus's eight poses at one scale (standing on y 376 of a 384 px
cell; his ninth, the stun, at that scale narrowed to fit; the small golem's three at one scale in 192 px
cells), the lens's and the veil's two at one scale each, the smith's four at one scale with their
feet centred, and every other prop alone in its cell.

Cost: 800 Magnific credits (eight generations at 100; sheet C on 2026-10-17 for the rework).

**`mine-props-e.png`** (2026-11-25) is one GPT 2.5 still at 2:1 (`gpt-2-mini`, 1k, transparent
background), the first and only take, 40 credits (counted with the pits' 200 in
`../dungeon-kit/pits/README.md`). References: `mine-props-a.png` and `mine-props-d.png`, downscaled to 768
px on grey. It is stripped of its credentials block. Its props are not on an even grid, and
`pack-mine-art.py` cuts 2 x 2 sheets only. Faint glow pixels reach past the props, so cut on the gaps:
the rows split at y 399, and each column has a gap (boxes x0, y0, x1, y1, alpha 16 and up):

| # | Prop | Box | Size | At the mine cart's scale |
|---|---|---|---|---|
| 1 | pit-prop set | 42, 59, 373, 381 | 331 x 322 | 203 x 197 |
| 2 | ladder foot | 461, 53, 677, 391 | 216 x 338 | 132 x 207 |
| 3 | lift gantry | 787, 25, 1111, 393 | 324 x 368 | 198 x 225 |
| 4 | spare props | 1167, 127, 1502, 389 | 335 x 262 | 205 x 160 |
| 5 | slate heap | 42, 456, 381, 736 | 339 x 280 | 207 x 171 |
| 6 | lantern post | 499, 405, 672, 730 | 173 x 325 | 106 x 199 |
| 7 | tipped ore cart | 761, 464, 1103, 733 | 342 x 269 | 209 x 165 |
| 8 | pickaxe, shovel, crate | 1236, 436, 1468, 734 | 232 x 298 | 142 x 182 |

The last column is in px. The standing cart on `mine-props-a.png` (362 x 405) packs to 222 x 248 in
`256x256-mine-cart.webp`, so 0.61. Packed at that scale, every prop fits a 256 cell, and the tipped cart
matches the standing one.

## Prompts

Each prompt began with the style block of the
[style guide](../../../docs/assets/visual-style-guide.md#generating-assets) and ended with "Each
pose (object) isolated on a transparent background, no ground shadow plate, no scenery, no labels,
no grid lines." Between them:

- **Colossus, sheet A:** "A sprite sheet of one boss monster for a top-down adventure game, the
  Crystal Colossus: a hulking, mean, part-beast golem of icy blue crystal grown over dark slate rock,
  hunched like a great ape, with huge crystal fists, heavy crystal feet, long crystal claws, jagged
  crystal spikes along its back and shoulders, small angry glowing amber eyes under a heavy crystal
  brow, and a glowing pearl set deep in the middle of its chest. The sheet is a 2 by 2 grid of four
  separate poses of the exact same golem ...: top left standing hunched and menacing, fists on the
  ground; top right one huge crystal foot raised high, body leaning back, about to stomp; bottom left
  the stomp landed, crystal shards and dust bursting at its foot, fists clenched; bottom right
  reeling back, a plate of its crystal chest armour cracked open and glowing hot orange inside next
  to the pearl."
- **Colossus, sheet B:** the same golem: "top left seen from behind, climbing up a wall, arms raised
  high and crystal claws dug in, legs bent, its spiky back to the viewer; top right seen from behind
  clinging high with one arm, turning its head and throwing a small rose-pink crystal creature down
  with the other arm; bottom left crouched low after landing a heavy jump, facing the viewer, fists
  on the ground, dust ring; bottom right defeated, collapsed into a heap of broken blue crystal and
  rock, the glowing pearl rising out of the heap." (ending "... no wall, ...")
- **Colossus, sheet C** (references: Lili's sheet and sheets A and B): "A third sprite sheet of the
  same boss monster as the reference sheets, the Crystal Colossus ...: top left the exact same huge
  golem, same size and colours as the reference sheets, crashed down flat on the ground after falling
  off a wall, sprawled face down on its belly with its arms and legs splayed out, dazed, its spiky back
  toward the viewer, and the big crystal plates of its back cracked wide open in a jagged split glowing
  hot orange inside; top right the golem after its defeat, shrunk back into a small calm crystal golem
  about the size of a fox: a little round golem of pale blue crystal over slate rock with stubby legs,
  short arms, a few small crystal spikes, gentle tired eyes, no pearl, standing facing the viewer;
  bottom left the same small calm golem walking to the left, seen from the side; bottom right the same
  small calm golem seen from behind, walking away." (ending "... no wall, ...")
- **Mine props A:** "top left a small sturdy wooden mine cart with iron bands and rivets on four
  iron wheels, empty, a few blue crystal chips in it; top right a square wooden mine lift platform
  of thick planks with four short corner posts, a coil of rope and a big iron crank wheel on one
  side; bottom left a heavy square ore crate of dark oak bound with thick iron bands and big rivets,
  a few blue ore chunks peeking out, clearly far too heavy to lift; bottom right a barricade of
  rotten old mine timbers: pale grey, cracked, sagging planks nailed across a broken leaning prop
  beam, splintered and old."
- **Mine props B:** "top left a round flat faceted crystal lens of clear pale blue glass held in a
  brass ring on top of a tall wooden post, like an old surveyor's sighting instrument, a target to
  shoot; top right the exact same lens and post with the lens glowing bright warm gold, struck;
  bottom left a wide barrier wall of smoky black crystal with a cold violet sheen, jagged crystal
  spikes growing up from the floor, blocking a passage; bottom right the same smoky black crystal
  shrunk down into a low ring of small stubby crystal points, receded."
- **Mine props C:** "top left a wide flat panel of thick living green roots with small leaves
  hanging straight down over grey rock with chunky rocky handholds jutting out, a climbable patch of
  cliff face, seen from the front; top right a hanging iron miner's lantern on a short wooden
  bracket, lit with a warm flame; bottom left a wooden buffer stop at the end of a mine rail, two
  short rails ending at a sturdy timber block with a red painted plank; bottom right a large glowing
  pearl, pearly white with a warm amber inner glow and a faint swirl like a claw mark, resting on a
  small cradle of blue crystal."
- **Mine props D:** "top left a sturdy mine gate seen from the front, two thick timber posts with a
  heavy grid of dark oak planks and iron straps hanging between them, closed, an empty iron lamp
  cup on top of each post; top right the exact same timber posts with the gate of planks pulled up
  and gone, the way open, a warm flame burning in each lamp cup; bottom left a low stump of grey
  cave rock with a few blue crystal points, waist high, a rock to hide behind; bottom right a small
  heap of mined ore rocks with glinting blue crystal chunks and a pickaxe stuck in it."
- **Mine props E** (2026-11-25; its ending reads "Each prop isolated on ..."): "A sprite sheet of eight
  separate mine props for a top-down adventure game, matching the reference prop sheets exactly in
  style, scale, timber colour, rusty iron bands and rivets, outline and shading, laid out as a 4 by 2
  grid with wide empty space between the props. Top row, left to right: 1) a timber pit-prop set that
  holds up a mine roof, two thick upright posts and a heavy cross beam on top joined by iron brackets,
  seen from the front, flat as if standing against a wall; 2) the foot of a wooden mine ladder, its two
  rails and the lowest four rungs whole, the rails snapped and the upper rungs broken off in splinters;
  3) a lift gantry over a shaft, a tall timber A-frame of two leaning beams with a big iron pulley wheel
  at its top and two thick ropes hanging straight down from it; 4) a neat stack of spare square mine
  timbers lying crosswise in layers, a rope tied round them. Bottom row, left to right: 5) a heap of
  fallen dark blue-grey slate rubble with a few icy-blue and violet crystal shards poking out; 6) a
  wooden lantern post with a short arm and an iron miner's lantern hanging from it, a warm flame lit;
  7) a wooden ore cart with iron wheels tipped over on its side, a few blue ore chunks spilled out on
  the ground; 8) a pickaxe and a shovel leaning against a small wooden crate."
- **The smith** (the slime line of the style block added): "the village smith, a big burly grown-up
  red jelly slime, a father, with a bushy dark red moustache, kind tired eyes, a smudge of soot on
  his cheek, a dark leather smith's apron with a pocket and rivets tied round his round body, a
  rolled cloth headband, and short stubby jelly arms ... all facing the viewer at the same size,
  feet at the bottom of each cell: top left standing calmly holding a heavy iron smith's hammer at
  his side; top right the hammer raised high over his shoulder, about to strike, determined face;
  bottom left holding out a small brass lantern with both arms toward the viewer, a warm orange
  ember glowing inside it, a proud gentle smile; bottom right pointing with one arm off to the
  side, talking, the hammer tucked under the other arm." (ending "... no anvil, ...")
