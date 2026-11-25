# The dungeon mechanisms: sources

The knock target, the ram with its bricked arch and the runaway cart with its rail gate (built
2026-11-23, step 1 of the [dungeons 2 and 3 rework](../../../../docs/design/2026-11-23-dungeons-2-3-rework.md);
[DUNGEONS.md "Mechanisms"](../../../../docs/godot/DUNGEONS.md#mechanisms-the-knock-target-the-ram-the-runaway-cart)).
Every file here is one Magnific GPT 2.5 generation (`gpt-2-mini`, 1:1, 1k, transparent background,
the Lili creation `XmsSFu2Bfo` as the style reference), a 1024 px sheet with four pictures in a
2 x 2 grid. Each was the first and only take.

| File | Pictures (top left, top right, bottom left, bottom right) | Packed into (`godot/asset/MAPS/objects/mechanisms/`) |
|---|---|---|
| `knock-target-a.png` | the whole target on its post (a guide, not packed); the disc face on; the disc's straw back; the post with its pivot bracket | `knock-target-disc-2x1.webp` (front, back; the disc's middle on each cell's middle), `knock-target-post.webp` |
| `ram-a.png` | the iron-capped log; the timber gantry from the front; the ratchet cog; the pawl on its bracket | `ram-log.webp`, `ram-log-north.webp` and `ram-log-south.webp` (the log without its rings, turned on end), `ram-gantry-front.webp` (its crossbeam drawn out so the log fits between the posts), `ram-cog.webp`, `ram-pawl.webp` |
| `bricked-arch-a.png` | the brick panel; the panel half knocked down; eight loose bricks; a heap of rubble | `bricked-arch-2x1.webp` (whole, half; sized as a north doorway's leaf, 141 x 132 px), `bricked-arch-bricks-8x1.webp`, `bricked-arch-rubble.webp` |
| `ram-cart-a.png` | the loaded cart from the side (facing left); from the front; one wheel face on; six loose pieces of ore | `ram-cart-side.webp`, `ram-cart-front.webp`, `ram-cart-wheel.webp`, `ram-cart-ore-6x1.webp` |
| `rail-gate-a.png` | the gate shut; the gate smashed; five broken planks and two chain links; the brake lever and its chock | `rail-gate-2x1.webp`, `rail-gate-planks-7x1.webp`, `ram-cart-brake-lever.webp`, `ram-cart-chock.webp` |
| `rail-buffer-a.png` | the rails' buffer stop from the front; from the side (its bumper facing left); the pulley post that hauls a cart back; its counterweight | `rail-buffer-front.webp`, `rail-buffer-side.webp`, `ram-cart-pulley.webp`, `ram-cart-counterweight.webp` |

`rail-gate-a-hazy.png` is the rail gate's generation as it came: its transparent background held a
grey haze (alpha 8 to 200 over the whole sheet). `rail-gate-a.png` is that picture after Magnific's
background removal (`images_remove_background`, as the
[Magnific guide](../../../../docs/assets/magnific-mcp-guide.md) says to do instead of regenerating).

`python scripts/art/pack-mechanism-art.py [--preview <dir>]` sends every separate piece of a sheet
to the quarter its middle lies in (so a picture that reaches past the sheet's middle line stays
whole), trims it and scales it to its size in the game at 2 px per game unit, and writes
`mechanisms.json` beside the sheets (sizes and anchors in game units, for whoever places them).

Cost: 243 Magnific credits (six generations at 40, one background removal at 3). The sounds
(`scripts/audio/picker/round-15-make.py`, ten prompts, 22 takes) cost 115 more.

## Prompts

Each prompt began with the style block of the
[style guide](../../../../docs/assets/visual-style-guide.md#generating-assets) and ended with "Each
object isolated on a transparent background, no ground shadow plate, no scenery, no labels, no grid
lines." (the cart's and the gate's also "no rails"). Between them:

- **Knock target:** "A sprite sheet of one prop for a top-down adventure game, an old fort's practice
  knock target: a big round wooden target of thick boards painted with bold toadstool-red and
  cream-white rings and a red bullseye, backed by a fat round bundle of golden straw, hung on a short
  stout wooden post, with an iron hook on its rim. The sheet is a 2 by 2 grid of four separate
  pictures of the exact same prop, same size and colours: top left the whole target standing upright
  on its short post, seen from the front; top right only the round target disc alone seen exactly
  face on, a perfect circle of red and white rings on wooden boards with an iron rim, no post and no
  straw showing; bottom left only the back of the same round disc seen exactly from behind, a perfect
  circle of bound golden straw with two wooden cross battens and rope bindings, no post; bottom right
  only the short stout wooden post alone, with an iron pivot bracket on its top and a small mossy
  stone base, nothing hanging on it."
- **Ram:** "A sprite sheet of the parts of one machine for a top-down adventure game, an old fort
  guard's battering ram. The sheet is a 2 by 2 grid of four separate pictures, all in the same wood
  and dark iron: top left the ram's log alone lying perfectly horizontal, a very thick heavy
  tree-trunk log of honey wood with three dark iron hoops, each hoop with an iron ring on top, its
  right end capped with a big rounded dark iron ram head with rivets, its left end sawn flat, seen
  from the side and slightly from above; top right a heavy timber gantry frame alone seen from the
  front: two thick upright square posts on mossy stone feet with diagonal wooden braces, joined
  across the top by one thick crossbeam with iron straps, a wide empty gap between the posts,
  nothing hanging in it; bottom left one dark iron ratchet cog wheel alone seen exactly face on, a
  perfect circle with saw teeth around a round wooden drum hub wrapped in chain; bottom right a short
  wooden winch crank handle with an iron pawl latch on an iron bracket, alone."
- **Bricked arch:** "A sprite sheet for a top-down adventure game: an old doorway that was bricked up
  long ago. The sheet is a 2 by 2 grid of four separate pictures, all the same old weathered
  terracotta and sand-coloured bricks with pale mortar and a little moss: top left a flat square
  panel of old brickwork seen exactly from the front, a solid wall of chunky uneven bricks in neat
  rows filling the whole square edge to edge, sound and whole, with no cracks at all and no hole; top
  right the same square brick panel half knocked down: the upper bricks gone in a jagged stepped
  edge, only the lower rows still standing, loose bricks tipping off it; bottom left eight single
  loose bricks and broken half bricks, each one separate and well apart, lying at different angles;
  bottom right a low heap of fallen bricks and mortar rubble lying on the floor."
- **Runaway cart:** "A sprite sheet of one prop for a top-down adventure game, a runaway mine cart
  heaped high with ore. The sheet is a 2 by 2 grid of four separate pictures of the exact same cart,
  same size and colours: top left the cart seen exactly from the side, facing left: a small sturdy
  wooden mine cart with dark iron bands and rivets, heaped high with grey ore rocks and glowing
  icy-blue crystals, on two big spoked iron wheels fully visible; top right the same loaded cart
  seen exactly from the front, coming toward the viewer, its two front wheels seen edge on; bottom
  left one single iron cart wheel alone seen exactly face on, a perfect circle with six thick spokes
  and a round hub; bottom right six loose ore rocks and small icy-blue crystal chunks, each one
  separate and well apart."
- **Rail gate:** "A sprite sheet for a top-down adventure game: a mine's rail gate and a cart brake.
  The sheet is a 2 by 2 grid of four separate pictures, all in the same honey wood and dark iron: top
  left a low wide gate that bars a mine rail track, seen exactly from the front: two short thick
  timber posts with iron bands, and between them three heavy horizontal planks bolted with iron
  straps, a thick iron chain wrapped across the planks and held by one big iron padlock-free shackle
  ring, shut tight; top right the same gate smashed open: the two posts still standing, the planks
  between them gone, only short splintered plank stubs left on each post and the broken chain hanging
  down; bottom left six broken splintered planks and plank halves, each one separate and well apart,
  lying at different angles, with two loose chain links; bottom right a mine cart brake alone: a long
  wooden brake lever with an iron grip standing upright on an iron pivot on a small wooden base, with
  a thick wooden wedge chock on the ground beside it."
- **Rail buffer:** "A sprite sheet of mine railway props for a top-down adventure game, all in the
  same honey wood and dark iron. The sheet is a 2 by 2 grid of four separate pictures: top left a
  rail buffer stop seen exactly from the front: one thick horizontal timber beam faced with a dark
  iron bumper plate and two round iron buffers, held up by two short stout timber posts with diagonal
  braces, low and wide; top right the same buffer stop seen exactly from the side: one short stout
  post with a diagonal brace behind it and the end of the beam with its iron bumper plate facing
  left; bottom left a short stout timber post with a big iron pulley wheel on its top and a thick
  iron chain wound around the wheel, a winch that hauls a cart back; bottom right a heavy dark iron
  counterweight block with rivets and an iron ring on top, hanging from a short length of chain."
