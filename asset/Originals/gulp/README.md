# Gulp art: sources

The owner asked on 2026-10-09 for original things to suck in and throw for the Gulp (roadmap 7.5):
first no vessels or pots (no copies of Zelda's). Later that day the owner accepted this first
round's art and asked for at least 8 by 8 things, for dungeons, different terrains and interiors,
pots included as long as they are original: the four grids below. Every picture in `generated/` is
a Magnific GPT 2.5 (`gpt-2-mini`, 1:1, 1k) still with a transparent background (1024 px), two
takes per call (`a` and `b`) except the grids (one each). The prompts are below; the references
were the mushroom furniture sheet for the liftables and the grids, Lili for the essences, the
slime's start stills (`characters/slime-v2/start-*.png`) and Lili for the full poses, and the side
start still and the old sheet's ball for the ball.

## Files (`generated/`)

| File | What it is | Used |
|---|---|---|
| `grid-1.png` | 16 objects in a 4 x 4 grid. Row 1, home and kitchen: clay pot, honey jar, bucket, crate. Row 2: wicker basket, flour sack, kettle, keg. Row 3, dungeon: rune urn, candle jar, lantern, cracked amphora. Row 4: mossy brick, iron ball, gargoyle head, fancy pot | All: liftables frames 0-15 (sheet rows 0 and 1) |
| `grid-2.png` | Row 1, forest: log, giant acorn, toadstool, bird nest. Row 2, cave and crystal: crystal cluster, geode, stalagmite, ore rock. Row 3: glow mushrooms, glowworm pot, amethyst, coal lump. Row 4, snow and ice: snowball, ice block, frosted jar, snowy log | All: frames 16-31 |
| `grid-3.png` | Row 1: icicle, snowy rock, frost crystal, snow brick. Row 2, desert: sandstone block, water jug, dry gourd, tumbleweed. Row 3: potted cactus, desert urn, sandbag, fossil stone. Row 4, beach: coconut, seashell, driftwood, coral | All: frames 32-47 |
| `grid-4.png` | Row 1, swamp: mud ball, swamp gourd, glass float, bottle. Row 2, garden: pumpkin, cabbage, watermelon, hay bundle. Row 3, garden and lava: turnip, flower pot, obsidian, lava rock. Row 4, spares: grain basket, teapot, stone lantern, piggy bank. It came with a see-through haze over its background, which the packer keys out | All: frames 48-63 |
| `rock-a.png`, `rock-b.png` | A mossy fieldstone with a clover sprig | Both: liftables frames 64 and 65 |
| `puffball-a.png`, `puffball-b.png` | A stemless, speckled puffball mushroom on a tuft of grass and leaves | Both: frames 66 and 67 |
| `pinecone-a.png`, `pinecone-b.png` | A fat brown pinecone with a little moss | Both: frames 68 and 69 |
| `essence-stone-a.png`, `essence-stone-b.png` | A glass teardrop holding pebbles and a glowing amber stone | `a`: essences frame 0 |
| `essence-silk-a.png`, `essence-silk-b.png` | A pale lilac drop of swirling silk threads with a curled tip | `b`: frame 1 |
| `essence-swim-a.png`, `essence-swim-b.png` | A clear blue water drop with bubbles and a waterweed | `b`: frame 2 |
| `ball-a.png`, `ball-b.png` | The slime curled into a green ball, its sprout lying flat on it | `b`: on a flat #FF00FF square it is `characters/slime-v2/start-ball.png`, spun into the Roll's ball (slime page 4) |
| `full-down-a.png`, `full-down-b.png`, `full-up-a.png`, `full-up-b.png`, `full-side-a.png`, `full-side-b.png` | The slime swollen full, a dark shape inside its belly (the down view puffs its cheeks) | The `a` takes, as the start stills below |
| `start-full-down.png`, `start-full-up.png`, `start-full-side.png` | The `full-*-a` poses on a flat #FF00FF 1024 px square, 1.15 times the start slime's width and on its baseline | The start stills of the full and spit videos (`characters/slime-v2/videos/`, pages 4 and 5) |

## Runtime sheets

`python scripts/props/pack-gulp-art.py` trims each picture to its opaque pixels, fits it to its
cell (never upscaled) and stands it on the cell's bottom centre. A grid is cut cell by cell (256
px each) and each object is cleared of specks under 40 px. Where a cell's border is not fully
clear (grid-4's haze), only what stands well above that haze is kept, and the cut is closed and
softened with a slight blur.

- `godot/asset/MAPS/props/192x192-tile_8x9-gulp-liftables.webp` (8 columns x 9 rows of 192 px;
  it replaced the 6 x 1 sheet of the first round): rows 0-7 are the grids in reading order (two
  grid rows per sheet row), row 8 the rock, puffball and pinecone, two variants each. One scene,
  `object.liftable`, shows any kind (`game/scripts/liftable.gd` `kind`); `object.liftable-rock`,
  `-puffball` and `-pinecone` preset the kind, and their `variant` picks the look.
- `godot/game/data/liftables.json`: the catalog of the 67 kinds (name, material, frames, art
  size), written from the kinds, names and materials authored in the packer (`GRIDS`, `FIRST`).
- `godot/asset/MAPS/items/128x128-tile_3x1-gulp-essences.webp`: stone, silk, swim. The essence on
  the ground (`object.essence-*`), in the mouth, and its bag icon (`gulp-essences-3x1` in
  `item-icons.json`).

The HUD's form badges (`godot/asset/UI/ui-gulp-form-icons-3x1.webp`) are an older sheet, packed by
`scripts/props/pack-gulp-props.py`. `godot/tools/render_gulp_art.gd` renders all the Gulp art with
the game's scenes on one sheet, to check sizes side by side (docs/TOOLING.md).

## Prompts

Every still prompt began with the style block of
[the style guide](../../../docs/assets/visual-style-guide.md#generating-assets) ("Cozy storybook
woodland game art, hand-painted 2D miniature, three-quarter top-down view, chunky rounded shapes,
... no text."; the full poses and the ball used its short form plus "glossy translucent jelly
slime body with rim light"). Then:

- **rock:** "One small round mossy fieldstone a little slime could lift: a lumpy warm-grey stone
  speckled with darker flecks, a soft cushion of green moss on its top, a tiny clover sprout tucked
  at its side, chunky and rounded, sitting on the ground, seen from the same gentle three-quarter
  top-down angle as the furniture in the reference sheet. Match the painting style, outline and
  light of the reference sheet. Isolated on a transparent background, no ground shadow plate, no
  scenery."
- **puffball** (the second try; the first painted a little slime beside it): "A single object only:
  one fat round puffball mushroom with no stem, a plump creamy-white dome like a soft dumpling,
  freckled with tiny warm brown speckles, a few blades of grass and one small fallen leaf hugging
  its base, slightly squishy looking, sitting on the ground, ... No creatures, no characters,
  nothing else." and the same closing sentences as the rock.
- **pinecone:** "One big chunky pinecone lying on its side, as big as a little slime: plump rounded
  honey-brown scales layered like roof shingles, darker walnut gaps between them, a little dusting
  of moss and one short green pine sprig at its tip, sitting on the ground, ..." and the same
  closing sentences.
- **grid-1 .. grid-4** (one take each, the mushroom furniture sheet as the image reference): "A
  game sprite sheet of 16 separate small objects that a little slime could lift and throw,
  arranged in a neat 4 by 4 grid ...", then one line per grid row naming its theme and its four
  objects ("Row 1, home and kitchen: ..."), as in the table above.
- **essences** ("Glossy translucent jelly with rim light. One magical essence: a fist-sized plump
  teardrop of living jelly goo standing upright, ... a bright specular highlight on the upper left,
  a soft magical glow, a darker base where it touches the ground. Match the painting style, outline
  and light of the reference."): stone "pebble-grey and translucent, with a warm amber stone glowing
  at its heart like a tiny ember and a few floating grains of grit inside"; silk "pearly
  lavender-white and translucent, with glowing silver silk threads curled inside it like a tiny
  cocoon, one loose thread curling out of its tip"; swim "clear aqua-blue and translucent like pond
  water, with little rising bubbles and a tiny curling water-weed sprig inside it, a small fin-like
  wave curl at its tip".
- **full-down / full-up / full-side:** "Redraw the exact green slime from the first reference image,
  facing the viewer exactly as it does there (up: seen from behind, no face visible; side: in strict
  side view facing right), same painted look, same green, same sprout on its head, same outline and
  light, but puffed up full: it has just sucked something big into its body, so it swells into a
  big round jelly ball about one fifth wider than normal, its cheeks bulge, its mouth is pressed
  shut in a tight little line, its eyes are happy and a bit strained, a faint dark round lump shows
  through its translucent belly, and it still sits on the ground with a flat heavy bottom."
- **ball:** "The exact green slime from the first reference image, ... curled up into a tight
  perfectly round ball for rolling, like the second reference image: a glossy green jelly sphere,
  its face and its two-leaf sprout tucked flat into the ball so only a curling swirl line shows on
  its side where it folded in, a bright specular highlight on the upper left, a darker underside.
  No speed lines, no motion marks, no eyes."

The nine Seedance 1.5 Pro videos (4 s, 1:1, 1080p, no audio) in `characters/slime-v2/videos/`
began "Hand-painted 2D storybook game animation of the provided green jelly slime, seen from a
fixed three-quarter top-down camera." and ended with the usual no-adds ("Flat, unlit, solid
#FF00FF chroma-key background with no gradient, no floor, no shadows, no light rays, no
particles, ... No camera movement. No audio."):

- **suck** (start and end `start-<direction>.png`): "It inhales hard in place: it opens its mouth
  very wide in a big round O, leans back a little, and its whole jelly body stretches and quivers
  as it sucks air in strongly, its two sprout leaves bending toward its mouth; then it closes its
  mouth and settles back to exactly the starting pose." (up: leans forward away from the viewer;
  side: opens its mouth toward the right).
- **spit** (start `start-full-<direction>.png`, end `start-<direction>.png`): "It starts puffed up
  full ... It spits once in place: it squashes down, puffs its cheeks, then blows forward ... in one
  quick hard burst, and its swollen body shrinks quickly back to its normal smaller round shape,
  ending exactly on the end image's pose. Nothing visible comes out of its mouth." The side take
  blew a long white blast anyway; the packer leaves those frames out.
- **full** (start and end `start-full-<direction>.png`): "... the provided puffed-up green jelly
  slime, so full it can barely move ... It waddles in place: slow heavy rocking steps, its swollen
  round body tipping from side to side, squashing down and jiggling with each step, its sprout
  wobbling, its cheeks staying puffed."

Cost: about 2,200 credits of stills (22 at 100, with the retried puffball), 3,960 for the nine
videos (440 each), and 400 for the four grids.
