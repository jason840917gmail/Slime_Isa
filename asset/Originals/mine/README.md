# The Crystal Mine: sources

Chapter 3's dungeon (built 2026-10-17; [DUNGEONS.md](../../../docs/godot/DUNGEONS.md#the-crystal-mine-built)).
Every file here is one Magnific GPT 2.5 generation (`gpt-2-mini`, 1:1, 1k, transparent background,
Lili's sheet as the style reference), a 1024 px sheet with four pictures in a 2 x 2 grid. Each was
the first and only take.

| File | Pictures (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `colossus-sheet-a.png` | the Crystal Colossus standing hunched, a foot raised (the stomp's tell), the stomp landed in shards and dust, reeling with his chest armour cracked open and glowing (the weak spot) | `godot/asset/MAPS/enemies/384x384-tile_8x1-crystal-colossus.webp`, frames 0 to 3 |
| `colossus-sheet-b.png` | climbing a wall seen from behind, throwing a Crystal Mite down from the wall, landed from a jump, defeated (a heap of crystal, the Pearl rising) | the same strip, frames 4 to 7 |
| `mine-props-a.png` | the mine cart, the ore lift (a plank platform with a crank), the iron-banded ore crate (a heavy block), the rotten timbers (the Heavy Roll's lock) | `godot/asset/MAPS/props/mine/256x256-mine-cart.webp`, `-ore-lift`, `-ore-crate`, `-rotten-timbers` |
| `mine-props-b.png` | the crystal lens on its post (the Bow's target), the same lens struck and glowing, the crystal veil grown across a passage, the veil shrunk back | `256x256-tile_2x1-crystal-lens.webp`, `256x256-tile_2x1-crystal-veil.webp` |
| `mine-props-c.png` | thick living roots and rocky handholds on a slab of cliff (the Feral skin's climb), a miner's lantern on a bracket, the rails' buffer stop, Pearl 3 on a crystal cradle | `256x256-root-wall.webp`, `128x128-mine-lantern.webp`, `256x256-buffer-stop.webp`, `256x256-pearl.webp` |
| `mine-props-d.png` | the mine gate shut (cold lamp cups), the gate open (the cups burning), a rock stump (cover), a heap of ore with a pickaxe | `256x256-tile_2x1-mine-gate.webp`, `256x256-rock-stump.webp`, `256x256-ore-heap.webp` |
| `smith-sheet.png` | the smith, Pip's dad, at his mine camp: standing with his hammer, the hammer raised to strike, holding out the Lantern, pointing | `godot/asset/characters/authored/npcs/smith.webp` (4 x 1, 260 x 280 cells) |

`python scripts/art/pack-mine-art.py` cuts each sheet along its emptiest middle row and columns,
trims each picture, and draws the Colossus's eight poses at one scale (standing on y 376 of a 384 px
cell), the lens's and the veil's two at one scale each, the smith's four at one scale with their
feet centred, and every other prop alone in its cell.

Cost: 700 Magnific credits (seven generations at 100).

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
- **The smith** (the slime line of the style block added): "the village smith, a big burly grown-up
  red jelly slime, a father, with a bushy dark red moustache, kind tired eyes, a smudge of soot on
  his cheek, a dark leather smith's apron with a pocket and rivets tied round his round body, a
  rolled cloth headband, and short stubby jelly arms ... all facing the viewer at the same size,
  feet at the bottom of each cell: top left standing calmly holding a heavy iron smith's hammer at
  his side; top right the hammer raised high over his shoulder, about to strike, determined face;
  bottom left holding out a small brass lantern with both arms toward the viewer, a warm orange
  ember glowing inside it, a proud gentle smile; bottom right pointing with one arm off to the
  side, talking, the hammer tucked under the other arm." (ending "... no anvil, ...")
