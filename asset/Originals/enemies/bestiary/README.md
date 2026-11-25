# The bestiary's first batch: sources

The bestiary's rows 4 to 10 (built 2026-10-16; [BESTIARY.md](../../../../docs/godot/BESTIARY.md)).
Every file here is one Magnific GPT 2.5 generation (`gpt-2-mini`, 1:1, 1k, transparent background,
Lili's sheet as the style reference), a 1024 px sheet with four poses in a 2 x 2 grid. Each was the
first and only take.

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `prologue-worm-sheet.png` (repainted 2026-10-16: [Gorge's worm soldiers](#gorges-worm-soldiers-rows-1-to-5-repainted-2026-10-16); the take below is `prologue-worm-sheet-rejected-timid.png`) | idle, walk, the twig swing, knocked over dazed | `256x256-tile_4x1-prologue-worm.webp` |
| `popworm-sheet.png` (repainted 2026-10-16, as above; the take below is `popworm-sheet-rejected-cute.png`) | the dirt mound, the tail flicking up out of it, popped up biting, limp on the soil | `256x256-tile_4x1-popworm.webp` |
| `spitcap-sheet.png` | hidden under its cap, up, spitting, the spore seed alone | `256x256-tile_3x1-spitcap.webp`, `64x64-spore-seed.webp` |
| `hopper-sheet.png` | standing, crouched to spring, in the air, flipped on its back | `256x256-tile_4x1-hopper.webp` |
| `bramble-boar-sheet.png` | standing, scraping the ground, charging, on its back stunned (all facing right) | `256x256-tile_4x1-bramble-boar.webp` |
| `thorn-guard-sheet.png` | asleep (dark eye slit), marching left foot, marching right foot (glowing eyes), rubble | `256x256-tile_4x1-thorn-guard.webp` |
| `rook-thief-sheet.png` | gliding, swooping with talons out, flying off with a coin pouch, knocked down dazed | `256x256-tile_4x1-rook-thief.webp` |

`python scripts/characters/pack-bestiary-enemies.py` cuts each sheet along its empty middle row and
columns, trims each pose to its opaque pixels and draws one enemy's poses at one scale (the largest
that fits all of them in 240 px), centred at x 128 and standing on y 248 of a 256 px cell, into
`godot/asset/MAPS/enemies/`. Walk cycles, bobs, squashes, lifts and flashes are code
(`game/enemy/patterned_enemy.gd` `set_look`; the prologue worm's clips in its scene).

Cost: 700 Magnific credits (seven generations at 100).

## Prompts

Each prompt began with the style block of the
[style guide](../../../../docs/assets/visual-style-guide.md#generating-assets) ("Cozy storybook
woodland game art, hand-painted 2D miniature, three-quarter top-down view, chunky rounded shapes,
warm golden light from the upper left, soft painted shading with visible wood grain, moss and cloth
texture, dark warm brown outline, earthy palette of honey wood, leaf green, cream and toadstool red,
no text.") and ended with "Each pose isolated on a transparent background, no ground shadow plate, no
scenery, no labels, no grid lines." Between them:

- **Prologue worm:** "A sprite sheet of one small enemy creature for a top-down adventure game: a
  weak, timid young worm with a short soft pale green segmented body, a cream belly, big worried
  glossy eyes, a tiny leaf sprouting on its head, and a little bent wooden twig held as a stick. It
  looks harmless and clumsy. The sheet is a 2 by 2 grid of four separate poses of the exact same
  worm, same size, same colours, same three-quarter top-down view facing the viewer and slightly to
  the right, evenly spaced with wide empty space between them: top left standing idle holding the
  twig; top right walking, body leaning forward mid-wriggle; bottom left swinging the twig forward
  in a clumsy attack; bottom right knocked over on its side, dizzy with swirly eyes, the twig
  dropped."
- **Popworm:** "A sprite sheet of one burrowing enemy creature for a top-down adventure game, the
  Popworm: a plump dusty-pink earthworm with a big round mouth ringed with small blunt teeth, two
  small beady glossy eyes, and a tail that ends in a small green leaf. The sheet is a 2 by 2 grid of
  four separate poses, same size, same colours, same three-quarter top-down view, evenly spaced with
  wide empty space between them: top left a small rounded mound of loose brown soil with pebbles
  and a tuft of grass, the worm hidden inside it; top right the same soil mound with only the
  worm's leafy tail tip flicking straight up out of it; bottom left the worm popped up out of a hole
  in the soil, rearing up with its toothy mouth wide open in a bite; bottom right the worm lying out
  on top of the soil, limp and dazed with swirly eyes."
- **Spitcap:** "A sprite sheet of one turret enemy for a top-down adventure game, the Spitcap: a
  squat grumpy toadstool creature with a wide toadstool-red cap with cream spots, a stubby cream
  stalk body, two small glossy eyes under the cap rim and a round puckered tube-shaped mouth. The
  sheet is a 2 by 2 grid of four separate images, evenly spaced with wide empty space between them,
  same three-quarter top-down view facing the viewer: top left hiding, the cap pulled all the way
  down flat to the ground like a closed dome shell, no eyes showing; top right popped up standing
  tall, idle and alert; bottom left spitting, cheeks puffed and the tube mouth pushed forward, a
  little puff of green spores at the mouth; bottom right a single round green spore seed with tiny
  bumps and a faint glow, the projectile it spits, drawn large and alone." (ending "Each image
  isolated ...")
- **Hopper:** "A sprite sheet of one jumping enemy creature for a top-down adventure game, the
  Hopper: a springy round bug with a domed mossy teal shell, one big glossy amber eye in front, and
  four long thin jointed legs bent like a grasshopper's. The sheet is a 2 by 2 grid of four separate
  poses of the exact same creature, same size, same colours, same three-quarter top-down view facing
  the viewer, evenly spaced with wide empty space between them: top left standing on the ground at
  rest; top right crouched very low, all four legs folded tight, about to spring; bottom left high
  in mid-air in a leap, legs stretched out and dangling; bottom right flipped onto its back, legs
  kicking, dazed with a swirly eye."
- **Bramble Boar:** "A sprite sheet of one charging enemy for a top-down adventure game, the Bramble
  Boar: a stocky little wild boar with bristly chestnut-brown fur, thorny bramble vines with a few
  red berries wrapped over its back, two small curved cream tusks and small angry eyes. All four
  poses face to the right in the same three-quarter top-down view. The sheet is a 2 by 2 grid of four
  separate poses of the exact same boar, same size, same colours, evenly spaced with wide empty space
  between them: top left standing still, watching; top right scraping the ground with one front
  hoof, head lowered, snorting angrily, ready to charge; bottom left charging at full gallop, head
  down, tusks forward, legs stretched; bottom right flipped over on its back, stunned, its soft pale
  pink belly up, legs in the air, dizzy swirly eyes." (ending "... no scenery, no dust, ...")
- **Thorn Guard Statue:** "A sprite sheet of one enemy for a top-down adventure game, the Thorn
  Guard Statue: a short chunky old soldier statue carved from weathered grey stone, a round helmet
  with a narrow eye slit, a small round stone shield and a short stone spear, patches of moss, cracks
  and thorny vines curling around its legs. The sheet is a 2 by 2 grid of four separate images of
  the exact same statue, same size, same colours, same three-quarter top-down view facing the
  viewer, evenly spaced with wide empty space between them: top left asleep, standing perfectly
  still, the eye slit dark; top right awake, two glowing amber eyes in the eye slit, marching with
  its left stone foot forward; bottom left awake, glowing eyes, marching with its right stone foot
  forward; bottom right crumbled into a low heap of broken stone rubble with the helmet on top and
  the vines loose." (ending "Each image isolated ...")
- **Rook Thief:** "A sprite sheet of one flying thief enemy for a top-down adventure game, the Rook
  Thief: a cheeky round rook bird with glossy blue-black feathers, a pale grey beak, bright golden
  eyes with a sly look and a little red scarf tied around its neck. The sheet is a 2 by 2 grid of
  four separate poses of the exact same bird, same size, same colours, same three-quarter top-down
  view, evenly spaced with wide empty space between them: top left flying, wings spread wide,
  gliding; top right diving down in a swoop, wings swept back, talons stretched forward to grab;
  bottom left flying away flapping hard, clutching a small cloth pouch of gold coins in its talons;
  bottom right knocked down sitting on the ground, feathers ruffled, dazed with swirly eyes."

## Fatty's Lair (rows 11 to 14)

Built 2026-10-16, the same way (GPT 2.5, 1:1, 1k, transparent background, Lili's sheet as the style
reference; the Big Squint also had the Squint's sheet as its first reference). Each was the first
take but the Pipe Worm, regenerated once in place for the owner's art direction of the same day
(the worms are Gorge's soldiers: a mean face and the army's mark, the red war scarf and Gorge's
emblem on a dark iron badge), with its first sheet as the reference for the same poses and layout.

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `squint-sheet.png` | standing, visor shut (a crimson slit); reared up to leap; slammed flat, the visor open on its crimson eye; on its back, cracked | `256x256-tile_16x1-squint.webp` (with sheets 2 to 4, its walk) |
| `pipe-worm-sheet.png` | the empty clay pipe; the worm glaring out of it; spitting mud; the worm alone, fallen out, dazed | `256x256-tile_4x1-pipe-worm.webp` (the first three hang from the pipe's top: `HUNG` in the packer) |
| `dung-roller-sheet.png` | pushing (two strides, facing right); on its back; the mud ball alone | `256x256-tile_8x1-dung-roller.webp` (the ball is frame 3, drawn by its own sprite) |
| `dung-roller-sheet-2.png` (2026-11-21) | pushing away from the viewer, seen from behind (two strides); pushing toward the viewer, seen from the front (two strides) | frames 4 to 7 of the same sheet (`WALK_MATCHED`; its specks cleared: `HAZY_LATER`) |
| `big-squint-sheet.png` | the Squint's four poses, bulkier, horned and mossy | `256x256-tile_4x1-big-squint.webp` |
| `mud-glob.png` | one image: the Pipe Worm's mud glob | `64x64-mud-glob.webp` (`SINGLES` in the packer) |

**The walk cycles** (2026-10-19; [BESTIARY.md](../../../../docs/godot/BESTIARY.md#art)): the
Squint first (300 credits), then the Big Squint, the Bramble Boar, the Thornball, the Brood Warden,
the Shardback, the Bone Marcher and the Bone Thrower (2,700 credits: 24 sheets and the Thornball's
side walk three more times: fog behind the first take, the head turning to the camera every other
step in the second; the fourth, asked for "strict side profile ... the head never turns toward the
viewer ... ONLY the four tiny pink feet change position", was kept), each with its first
sheet and Lili as references: `<enemy>-sheet-2.png` (four steps facing right), `-3` (walking toward
the viewer) and `-4` (walking away); the Bone Thrower's `-2` to `-4` hold its bone up, `-5` to `-7`
are empty-handed with fists clenched. Then the Broodling, the Cocoon Mimic (its open-mouthed
pose), the Crystal Mite, the Thorn Guard Statue, the Bone Leaper (crawling on its knuckles) and the
prologue worm (wriggling, no legs) (2,200 credits: 18 sheets and two takes each of the Mite's and
the Guard's side walks, whose first takes, kept out of the repo, faced the camera). A side walk
holds its profile only when the prompt insists: "In ALL FOUR frames it is shown in strict SIDE
PROFILE, turned fully to face the RIGHT edge ... It never faces the viewer. The body, head and size
are identical in all four frames and ONLY its legs change". Packed after the four poses (frames 4
on; `WALK`, `WALK_MATCHED`). Prompt (the Squint's; the others name their own body, gait and back view, the
skeletons' legs stride and their arms swing):
the style block, the transparent line, then "A walk-cycle sprite sheet of the exact armoured creature
in the first reference picture, the Squint: [its description]. Same design, same colours, same
proportions as the first reference. The sheet is a 2 by 2 grid of four separate frames of one
walking loop, all seen from the side [from the front, walking down toward the viewer / from behind,
walking away], ... same size in every frame, ... the body staying level, only the stubby legs moving
in a heavy waddling trot", then each frame's legs (a step, passing, the other step, passing).

`python scripts/characters/pack-bestiary-enemies.py squint pipe-worm dung-roller big-squint mud-glob`
packs only these.

Cost: 600 Magnific credits (six generations at 100: five sheets and the Pipe Worm's second take).

Prompts (the same style block first, the same ending):

- **Squint:** "A sprite sheet of one armoured enemy creature for a top-down adventure game, the
  Squint: a squat, heavy, round burrow beast, its whole body covered in thick overlapping curved
  armour plates of dark slate-blue fired clay with rusty copper rims and rivets, like a pill bug
  wearing an old iron helmet, with four short stubby clawed feet. On its front sits one single big
  eye behind two heavy armour eyelid plates that close like a visor; no mouth shows and it has no
  other face. It looks tough and grumpy, nothing like a slime. The sheet is a 2 by 2 grid of four
  separate poses of the exact same creature, same size, same colours, same three-quarter top-down
  view facing the viewer and slightly to the right, evenly spaced with wide empty space between
  them: top left standing on its feet, the visor plates shut tight so only a thin glowing crimson
  slit of the eye shows; top right reared back on its hind feet with its front lifted high and its
  plates bristling, about to leap and slam down, the eye slit still shut; bottom left slammed flat
  onto the ground with its plates spread, the visor wide open showing its huge glossy crimson eye
  with a golden ring, dazed and blinking; bottom right knocked over on its back with its feet in the
  air, armour plates cracked, the eye shut in a dizzy swirl."
- **Big Squint** (the Squint's sheet as the first reference): the Squint's prompt with "the Big
  Squint: the elder of the armoured creature in the first reference picture, the same dark
  slate-blue fired clay armour plates with rusty copper rims and rivets and the same single crimson
  eye behind a visor of two heavy eyelid plates, but much bulkier and heavier, with a tall horned
  crest plate over its visor, thick spiked shoulder plates, moss and old scratches on its shell and
  iron bands on its four thick clawed feet. It looks like a dangerous boss." and "about to leap and
  stomp down".
- **Pipe Worm** (the second take, its first sheet as the first reference): "A sprite sheet of one
  turret enemy for a top-down adventure game, the Pipe Worm, redrawn from the first reference
  picture with the same 2 by 2 layout, the same old round terracotta clay drain pipe seen end-on and
  the same four poses. It is a mean, glaring soldier of a worm army: a dark plum-purple worm with
  ochre-yellow bands and a pale belly, a long tube-shaped snout like a short trumpet, narrowed angry
  golden eyes under a scowling brow and a few stiff whiskers, and it wears its army's mark: a ragged
  brick-red war scarf tied around its neck and a short dark leather strap with a small dark iron
  badge stamped with a black horned slime-head emblem. Nothing cute or scared about it. The four
  separate images, evenly spaced with wide empty space between them, the pipe exactly the same size
  and shape in the first three: top left the empty pipe mouth alone, dark inside, nothing in it; top
  right the worm's head and neck poking straight out of the pipe toward the viewer, glaring, the red
  scarf at its neck, never rising above the pipe's rim; bottom left the worm stretched out of the
  pipe toward the viewer spitting, its tube snout puffed wide with a blob of wet brown mud bursting
  out of it; bottom right the worm alone, fallen out of its pipe, lying knocked out on the ground in
  a loose curl with its red scarf and badge showing, dazed with swirly eyes, no pipe." (ending
  "Each image isolated on a transparent background, no ground shadow plate, no wall, no scenery,
  ...")
- **Dung Roller:** "A sprite sheet of one patrolling enemy for a top-down adventure game, the Dung
  Roller: a stocky dung beetle with a glossy dark bronze-green shell, a broad shovel-shaped head with
  a short blunt horn, six sturdy spiny legs, and a soft pale tan striped bottom at the back of its
  body. All the beetle's poses face to the right in the same three-quarter top-down view. The sheet
  is a 2 by 2 grid of four separate images, evenly spaced with wide empty space between them: top
  left the beetle pushing forward to the right with its head down and front legs raised, as if
  shoving something big in front of it; top right the same pushing pose mid-stride with the other
  legs forward; bottom left the beetle flipped onto its back, legs kicking in the air, dazed with
  swirly eyes; bottom right a large perfectly round ball of packed brown mud with straw, pebbles and
  a little moss stuck in it, drawn alone, as big as the whole beetle."
- **Dung Roller, sheet 2** (2026-11-21, the owner: "we need vertical tiles also"; references: sheet
  1, Lili; the first take, 40 credits): the style block, then "A sprite sheet of the exact dung
  beetle in the first reference picture, the Dung Roller: [its description]. Same design, same
  colours, same proportions and same painting as the first reference. The sheet is a 2 by 2 grid of
  four separate frames, evenly spaced with wide empty space between them, the beetle exactly the
  same size in every frame, and no ball drawn anywhere. Top left: the beetle seen from directly
  BEHIND in the three-quarter top-down view, walking straight away from the viewer up the screen,
  its head down and its front legs raised as if shoving something big in front of it; we see its
  striped tan bottom and the back of its shell, its head mostly hidden behind its shell, only the
  tip of the horn showing. Top right: the same view from behind, mid-stride with the other legs
  forward. Bottom left: the beetle seen from the FRONT, walking straight toward the viewer down the
  screen, head lowered with its horn and both front legs raised forward as if shoving something big
  toward the viewer, its face and both eyes showing. Bottom right: the same front view, mid-stride
  with the other legs forward. Each image isolated on a transparent background, no ground shadow
  plate, no scenery."
- **Mud glob:** "One single projectile for a top-down adventure game: a small round blob of wet
  glossy dark brown mud that a worm spits, with a few thick drips trailing off one side, a couple of
  tiny pebbles and a bright wet highlight, drawn large and alone in the middle of the picture.
  Isolated on a transparent background, no ground shadow plate, no scenery, no labels."

## Gloop Forest and the Weaver Hollow (rows 18 to 22)

Built 2026-10-16, the same way (GPT 2.5, 1:1, 1k, transparent background, Lili's sheet as the style
reference). Every sheet was the first take. The props sheet also had the Cocoon Mimic's sheet and
the Broodling's sheet as references, so its real cocoon is the mimic's disguise and its egg pods hold
the Broodlings; it came with a faint haze over its whole background (alpha 2 or 3), which the packer
clears (`HAZY`: each pose keeps only its main body).

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `silk-lurker-sheet.png` | hanging, legs folded; dropping, legs flung open; spinning upside down, dizzy; on its back | `256x256-tile_4x1-silk-lurker.webp` |
| `thornball-sheet.png` | standing (facing right); curling up, quills out; the spiked ball; flipped belly up, dizzy | `256x256-tile_4x1-thornball.webp` |
| `broodling-sheet.png` | scuttling (two steps); leaping to bite; popped into a goo splat | `256x256-tile_4x1-broodling.webp` |
| `brood-props-sheet.png` | the egg sac; the egg sac hatching (legs poking out); the egg sac burst; the real silk cocoon | `256x256-tile_4x1-brood-props.webp` (the egg sac's frames 0 to 2, the real cocoon's frame 3) |
| `cocoon-mimic-sheet.png` | disguised (the cocoon with a gold coin); bursting into a toothy mouth; clamped shut over its prey; slumped open, dazed | `256x256-tile_4x1-cocoon-mimic.webp` |
| `brood-warden-sheet.png` | on guard, blades raised; winding up, blades back to one side; mid-sweep; planted, back plates open on glowing joints | `256x256-tile_4x1-brood-warden.webp` (now `256x256-tile_24x1-brood-warden.webp`, with his walk and the sheets below) |
| `brood-warden-sheet-5.png` (2026-11-25) | knocked over on his back, belly up, legs and blades kicking: a loop of four (left legs up; all flailing out; right legs up; all curled in) | frames 16 to 19 (`STILL_BODY`: the body on one spot) |
| `brood-warden-sheet-6.png` (2026-11-25) | struck off his feet, tipped onto his side; tumbling over, belly turning up; heaving himself up on his blades; crouched back on his feet | frames 20 to 23 (its faint haze cleared: `FAINT_HAZE_FILES`) |

`python scripts/characters/pack-bestiary-enemies.py silk-lurker thornball broodling brood-props
cocoon-mimic brood-warden` packs only these.

Cost: 600 Magnific credits (six generations at 100).

Prompts (the same style block first, the same ending):

- **Silk Lurker:** "A sprite sheet of one ambush enemy for a top-down adventure game, the Silk
  Lurker: a fat furry hanging spider with a round fuzzy charcoal-brown body, a pale bone-white
  skull-shaped marking on its back, a cluster of small glowing amber eyes, small curved fangs, and
  eight long thick hairy legs with cream joint bands. It looks sneaky and menacing, not cute. The
  silk thread it hangs from is not drawn. The sheet is a 2 by 2 grid of four separate poses of the
  exact same spider, same size, same colours, same three-quarter top-down view, evenly spaced with
  wide empty space between them: top left hanging still, legs folded tight around its body, waiting;
  top right dropping down fast, all eight legs flung wide open, fangs bared in a lunge; bottom left
  hanging upside down and spinning helplessly like a pinata, legs flailing, dizzy swirly eyes; bottom
  right fallen on the ground on its back, legs curled up, dazed with swirly eyes."
- **Thornball:** "A sprite sheet of one rolling enemy for a top-down adventure game, the Thornball:
  a grumpy round little hedgehog with a thick coat of long sharp dusty grey-brown quills tipped in
  cream, a soft pale peach face and belly, a shiny black button nose, small beady angry eyes and tiny
  pink feet. All four poses face to the right in the same three-quarter top-down view. The sheet is a
  2 by 2 grid of four separate poses of the exact same hedgehog, same size, same colours, evenly
  spaced with wide empty space between them: top left standing on all fours, sniffing, watching; top
  right curling up, half rolled into a ball, quills bristling straight out, angry eyes peeking out,
  about to roll; bottom left curled into a tight perfectly round spiked ball, nothing but sharp quills
  showing, rolling; bottom right flipped over onto its back, its soft pale belly up, tiny feet in the
  air, dizzy swirly eyes." (ending "... no scenery, no dust, ...")
- **Broodling:** "A sprite sheet of one tiny swarm enemy for a top-down adventure game, the
  Broodling: a tiny freshly hatched spiderling with a soft round fuzzy pale ivory-cream body with
  rust-orange spots on its back, a big head with two huge glossy black eyes, tiny red fangs, and
  eight short stubby tan legs. It looks hungry and twitchy. The sheet is a 2 by 2 grid of four
  separate poses of the exact same spiderling, same size, same colours, same three-quarter top-down
  view facing the viewer, evenly spaced with wide empty space between them: top left scuttling, legs
  spread mid-step; top right scuttling, legs in the opposite step; bottom left leaping forward to
  bite, front legs thrown forward, fangs wide open; bottom right popped, burst flat into a small
  splat of pale cream goo with two little legs sticking out." (Cream and rust, never the Slime
  Spider's lime green and purple: the clarity rule.)
- **Cocoon Mimic:** "A sprite sheet of one mimic enemy for a top-down adventure game, the Cocoon
  Mimic: a monster disguised as a silk-wrapped treasure cocoon. The sheet is a 2 by 2 grid of four
  separate images of the exact same cocoon creature, same size, same colours, same three-quarter
  top-down view facing the viewer, evenly spaced with wide empty space between them: top left
  disguised, a plump round cocoon bundle of tightly wound pale cream silk sitting upright on the
  ground, a few loose threads at its base and a gleaming gold coin showing through a small gap in the
  silk, it looks exactly like a harmless prize, no eyes, no mouth; top right bursting open, the same
  cocoon splitting across its middle into a wide toothy mouth with a purple tongue, silk tatters
  flying, two mean yellow eyes opening on top; bottom left holding its prey, the same cocoon clamped
  shut again and bulging out of shape as if something round is trapped and squirming inside, silk
  strands wrapped tight around it, its yellow eyes squeezed shut in a greedy gulp; bottom right
  dazed, the cocoon slumped wide open and limp, torn silk flaps hanging, tongue lolling out, dizzy
  swirly eyes." (ending "Each image isolated ...")
- **Brood props** (references: Lili, the Cocoon Mimic's sheet, the Broodling's sheet): "A sprite
  sheet of props for a spider lair in a top-down adventure game, in the same painted style as the
  reference sheets. The sheet is a 2 by 2 grid of four separate images, evenly spaced with wide empty
  space between them, same three-quarter top-down view: top left a spider egg sac sitting on the
  ground: a cluster of three plump round translucent pale peach egg pods glued together and to the
  ground by sticky white web strands, inside each pod the faint curled shape of a tiny cream
  spiderling with orange spots (the spiderling of the third reference sheet); top right the same egg
  sac swelling and hatching, its biggest pod split open at the top with two tiny tan spiderling legs
  poking out, sticky goo dripping; bottom left the same egg sac burst and torn apart, the pods
  deflated, ripped open and empty, a puddle of pale goo and loose web strands; bottom right exactly
  the same silk cocoon as the top-left image of the second reference sheet: a plump egg-shaped bundle
  of tightly wound pale cream silk with a few moss flecks, a gleaming gold coin showing through a
  small gap in the silk and a few loose threads at its base, no eyes, no mouth." (ending "Each image
  isolated ...")
- **Brood Warden:** "A sprite sheet of one armoured mini-boss enemy for a top-down adventure game,
  the Brood Warden: a big hulking guard spider covered in thick rust-red and dark bronze chitin armour
  plates like a knight's armour, a heavy helmet-shaped head plate with a narrow visor slit and two
  glowing orange eyes, two huge front legs shaped like curved scythe blades, and six thick armoured
  walking legs. It looks heavy, stern and dangerous. The sheet is a 2 by 2 grid of four separate poses
  of the exact same spider, same size, same colours, same three-quarter top-down view facing the
  viewer, evenly spaced with wide empty space between them: top left standing guard, both blade legs
  raised in front of it; top right winding up a sweep, both blade legs pulled far back to its left
  side, body twisted; bottom left mid-sweep, both blade legs swung far out to its right side in a wide
  slash; bottom right planted and worn out, all its legs dug into the ground, head plate lowered, its
  back armour plates spread open to show soft pale glowing joints underneath." (ending "Each pose
  isolated ...")
- **Brood Warden, sheets 5 and 6** (2026-11-25, knocked over by B5's ram; references: his first
  sheet, Lili; first takes, 40 credits each): the style block, then "A sprite sheet of the exact
  armoured spider in the first reference picture: [his description]. Same design, same colours, same
  proportions and same painting as the first reference, drawn at the same size." Sheet 5: "a 2 by 2
  grid of four separate frames of one looping animation ...: the spider has been knocked over and
  lies helpless flat on its back, belly up ... Its underside faces the camera: dark bronze segmented
  belly plates ..., a few soft pale glowing joints showing between the plates. Its helmet head plate
  is at the bottom toward the viewer, tipped back, the two orange eyes narrowed in fury, still mean
  and dangerous, never scared, never cute. All eight legs and both scythe blades stick up into the air
  ..., kicking and thrashing as it struggles to roll back over. The body is identical in size and
  position in all four frames and ONLY the legs and blades move", then each frame's legs. Sheet 6:
  "struck hard from the side and knocked off its feet, its whole heavy body tipped far over onto its
  side ...; tumbled further over, nearly on its back ...; rolled onto its side and heaving itself back
  up, both scythe blades stabbed into the ground to push ...; back on its feet but still crouched low
  and heavy ..., about to rise back into its guard. Mean and dangerous in every image, never scared,
  never cute." Both ending "Each image isolated on a transparent background, no ground shadow plate,
  no scenery, no dust, no motion lines, no labels, no grid lines."

## Gorge's worm soldiers (rows 1 to 5, repainted 2026-10-16)

The owner (2026-10-16): the old 64 px worm sheets "do not fit the game art now", and "the worms
can't have that expression, they are warriors in Gorge's service, they have to be bad"; worms of
every kind make up most of his army. So the Worm Swordsman, the Worm Archer and the Worm Brawler
(rows 1 to 3) were painted new, and the prologue worm and the Popworm (rows 4 and 5) repainted: mean
faces, war gear by rank (the grunt a scarf scrap, the swordsman and the archer kitted, the brawler
heavy) and one army mark, the same words in every prompt as the Pipe Worm's: "a ragged brick-red war
scarf" and "a small dark iron badge stamped with a black horned slime-head emblem" (Gorge). Each
file is one Magnific GPT 2.5 generation (`gpt-2-mini`, 1:1, 1k, transparent background), Lili's sheet
as the style reference; a soldier's later sheets also take its first sheet(s) as references, so it
stays the same worm.

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `worm-swordsman-sheet.png` | battle stance, marching, wind-up (sword over its head), slash | `256x256-tile_8x1-worm-swordsman.webp` frames 0 to 3 |
| `worm-swordsman-sheet-2.png` | hurt, defeated, back view walking up, back view slashing up | frames 4 to 7 |
| `worm-archer-sheet.png` | standing, walking, drawing (side), loosed (side) | `256x256-tile_12x1-worm-archer.webp` frames 0 to 3 |
| `worm-archer-sheet-2.png` | hurt, defeated (arrows spilled), back view walking up, back view drawing up | frames 4 to 7 |
| `worm-archer-sheet-3.png` | drawing down (facing the viewer), loosed down, back view loosed up, running | frames 8 to 11 (the four-line archer, owner 2026-10-16) |
| `worm-brawler-sheet.png` | boxer's guard, stomping, coiled (fist back), punch | `256x256-tile_8x1-worm-brawler.webp` frames 0 to 3 |
| `worm-brawler-sheet-2.png` | hurt, defeated, back view walking up, back view punching up | frames 4 to 7 |
| `prologue-worm-sheet.png` | idle (club ready), walking, the club swing, knocked over | `256x256-tile_4x1-prologue-worm.webp` (in place) |
| `popworm-sheet.png` | the mound, the tail tell, up and biting, dazed on the soil | `256x256-tile_4x1-popworm.webp` (in place) |
| `worm-army-props-sheet.png` | the arrow (pointing right), three frames of the punch hit | `64x64-worm-arrow.webp`, `64x64-tile_3x1-worm-brawler-hit.webp` (PROP_SHEETS) |
| `worm-archer-sheet-3-rejected.png` | the first take of the archer's third sheet: its "draw down" aimed sideways and its "shot up" kept an arrow | not packed |
| `prologue-worm-sheet-rejected-timid.png`, `popworm-sheet-rejected-cute.png` | the first takes of rows 4 and 5 (prompts above): too cute and scared for Gorge's army | not packed |

Packing: the soldiers' poses come from several sheets (`<enemy>-sheet.png`, `-sheet-2.png`, ...:
`SHEET_POSES`), drawn at one scale per enemy, and stand by their weight (`MASS_CENTRED`: the middle
of their opaque pixels at x 128), so a sword, a bow or a fist thrust out does not push the body
back; the prologue worm too. The brawler's second sheet has no empty row across it (its punch up
reaches into the top row's band), so the packer cuts its columns first.

Cost: 1,100 Magnific credits (11 generations at 100: the swordsman 2, the archer 4 with the rejected
take, the brawler 2, the prologue worm, the Popworm, the props sheet).

### Prompts

The same style block first and "Each pose isolated on a transparent background, no ground shadow
plate, no scenery, no labels, no grid lines." last (the props sheet and the Popworm: "Each image
isolated ..."). Between them:

- **Worm Swordsman, sheet 1:** "A sprite sheet of one enemy soldier for a top-down adventure game,
  the Worm Swordsman: a menacing, mean villain worm, a foot soldier of a worm army, with a stout
  honey-yellow segmented body, a pale cream belly and two small stubby arms, heavy scowling brows,
  narrowed glaring eyes and a sneer with bared blunt teeth. It wears the army's mark: a ragged
  brick-red war scarf tied around its neck with its ends flying, and a dark leather strap across its
  chest with a small dark iron badge stamped with a black horned slime-head emblem; a dented iron cap
  on its head. It carries a short straight iron sword with a nicked blade and a leather-wrapped hilt.
  Nothing cute, scared or blushing: no pink cheeks, no big glossy innocent eyes. The sheet is a 2 by
  2 grid of four separate poses of the exact same worm, same size, same colours, same three-quarter
  top-down view, the worm facing the viewer and turned to the right, evenly spaced with wide empty
  space between them: top left standing in a battle stance, the sword held ready in front of it; top
  right marching forward, body leaning mid-wriggle, the sword ready; bottom left winding up, reared
  back with the sword raised high over its head, about to strike; bottom right slashing, lunging to
  the right with the sword swung out straight in front of it at full reach, a small curved white
  swoosh along the blade."
- **Worm Swordsman, sheet 2** (references: sheet 1, Lili): "A sprite sheet of one enemy soldier for
  a top-down adventure game, the Worm Swordsman from the first reference picture: the exact same
  menacing, mean villain worm, same stout honey-yellow segmented body and cream belly, same dented
  iron cap, same ragged brick-red war scarf, same dark leather strap with the small dark iron badge
  stamped with a black horned slime-head emblem, and the same short nicked iron sword, same size,
  same colours, same painting. Nothing cute, scared or blushing. The sheet is a 2 by 2 grid of four
  new separate poses, evenly spaced with wide empty space between them: top left hurt, flinching back
  to the left from a hit, eyes squeezed shut in an angry grimace, the sword still in its hand; top
  right defeated, knocked out lying flat on its side on the ground, dazed with swirly eyes, the sword
  dropped beside it, the cap tipped off its head; bottom left seen from behind with its back to the
  viewer, marching away up the screen, the sword in its hand, the scarf knot, the strap and the back
  of the cap showing, no face visible; bottom right seen from behind with its back to the viewer,
  slashing the sword straight up and away from the viewer, the blade far out above its head at full
  reach with a small curved white swoosh."
- **Worm Archer, sheet 1:** as the swordsman's sheet 1, with "the Worm Archer: a menacing, mean
  villain worm, a sharpshooter of a worm army, with a lean moss-green segmented body with darker
  olive bands, a pale cream belly and two small stubby arms, heavy scowling brows, narrowed glaring
  eyes and a cruel smirk. It wears the army's mark: [the scarf and the badge]; a dark brown leather
  hood, and a quiver of red-fletched arrows on its back. It carries a short curved wooden bow. [...]
  top left standing alert, the bow held low at its side; top right walking, body leaning mid-wriggle,
  the bow in hand; bottom left drawing the bow, the string pulled back hard with an arrow nocked and
  aimed straight to the right, one eye squinting; bottom right just after shooting, the bow still
  held out to the right, the string twanging, no arrow on it."
- **Worm Archer, sheet 2** (references: sheet 1, Lili): as the swordsman's sheet 2, the archer's
  body, hood, quiver and bow named again: "top left hurt, flinching back to the left from a hit, eyes
  squeezed shut in an angry grimace, the bow still in its hand; top right defeated, knocked out lying
  flat on its side on the ground, dazed with swirly eyes, the bow dropped beside it and a few arrows
  spilled from the quiver; bottom left seen from behind with its back to the viewer, walking away up
  the screen, the hood, the quiver and the scarf knot showing, the bow in its hand, no face visible;
  bottom right seen from behind with its back to the viewer, drawing the bow and aiming straight up
  and away from the viewer, the string pulled back with an arrow nocked pointing up the screen."
- **Worm Archer, sheet 3** (references: sheets 1 and 2, Lili; the second take, kept): "[the archer
  named as in sheet 2] top left facing the viewer, shooting downward: the bow turned flat and held
  horizontally across the front of its belly, the string drawn back up toward its chin, an arrow
  nocked and pointing straight down to the bottom of the picture, its head bent forward glaring down
  along the arrow; top right the same front pose just after the shot: the bow still horizontal across
  its belly, the string twanging, the bow empty with no arrow; bottom left seen from behind with its
  back to the viewer just after shooting straight up: the bow turned flat and raised horizontally
  above its hood, the string twanging, the bow empty with no arrow at all, the quiver on its back, no
  face visible; bottom right running fast to the right, its body stretched long and low mid-dash, the
  bow clutched in one hand, the scarf ends flying back." (The rejected first take asked for "aiming
  straight down the screen toward the viewer, the bow held level in front of its chest".)
- **Worm Brawler, sheet 1:** as the swordsman's sheet 1, with "the Worm Brawler: a menacing, mean
  villain worm, the heavy bruiser of a worm army, with a big burly thick slate-blue segmented body, a
  broad chest, a pale grey belly and two short thick muscular arms ending in huge fists wrapped in
  dirty cloth bandages and dark leather straps, heavy scowling brows, small furious eyes, a snarl of
  bared teeth and a few scars. It wears the army's mark: [the scarf and the badge]; a heavy dented
  iron shoulder plate. [...] top left standing in a boxer's guard, both wrapped fists raised; top
  right stomping forward, body leaning mid-wriggle, fists up; bottom left crouched low and coiled, one
  fist pulled far back, ready to lunge; bottom right lunging to the right with a huge punch, the fist
  thrust out straight in front of it at full reach, the body stretched forward."
- **Worm Brawler, sheet 2** (references: sheet 1, Lili): as the swordsman's sheet 2: "top left hurt,
  flinching back to the left from a hit, eyes squeezed shut in an angry grimace, fists still up; top
  right defeated, knocked out lying flat on its side on the ground, dazed with swirly eyes, its
  wrapped fists limp; bottom left seen from behind with its back to the viewer, stomping away up the
  screen, its broad back, the shoulder plate, the strap and the scarf knot showing, no face visible;
  bottom right seen from behind with its back to the viewer, punching straight up and away from the
  viewer, one wrapped fist thrust far out above it at full reach."
- **Prologue worm (grunt):** "A sprite sheet of one small enemy grunt for a top-down adventure game:
  a scrawny, nasty little worm, the lowest grunt of a worm army, with a short thin dull pale green
  segmented body, a dirty cream belly and two small stubby arms, a mean scowl with heavy brows,
  narrowed beady glaring eyes and a crooked sneer showing one snaggle tooth. It wears only a scrap of
  the army's mark: a torn, ragged brick-red scarf rag tied around its neck with a small dark iron
  badge stamped with a black horned slime-head emblem pinned to it. It carries a knobbly crooked
  wooden twig club. It is small and weak but bad: a menacing little villain, nothing cute, scared or
  blushing, no pink cheeks, no big glossy innocent eyes, no leaf. The sheet is a 2 by 2 grid of four
  separate poses of the exact same worm, same size, same colours, same three-quarter top-down view
  facing the viewer and slightly to the right, evenly spaced with wide empty space between them: top
  left standing idle, sneering, the twig club held ready; top right walking, body leaning forward
  mid-wriggle, the club raised; bottom left swinging the twig club forward hard in an attack; bottom
  right knocked over on its side, dizzy with swirly eyes, the club dropped."
- **Popworm** (references: the rejected first take, for its layout and mound; Lili): "A sprite sheet
  of one burrowing enemy for a top-down adventure game, the Popworm, redrawn from the first reference
  picture with the same 2 by 2 layout, the same soil mound and the same four poses. It is a menacing,
  mean villain worm, an ambusher of a worm army: a plump dusty-pink earthworm with darker segment
  rings, a big round mouth ringed with small sharp jagged teeth, heavy scowling brows over narrowed
  glaring little eyes, and a tail that ends in a small dark green leaf. It wears the army's mark: a
  ragged brick-red war band tied around its neck and a scrap of dented dark iron armour on its back
  with a small dark iron badge stamped with a black horned slime-head emblem. Nothing cute, scared or
  blushing: no pink cheeks, no big glossy innocent eyes. The four separate images, same size, same
  colours, same three-quarter top-down view, evenly spaced with wide empty space between them: top
  left a small rounded mound of loose brown soil with pebbles and a tuft of grass, the worm hidden
  inside it; top right the same soil mound with only the worm's leafy tail tip flicking straight up
  out of it; bottom left the worm popped up out of a hole in the soil, rearing up with its toothy
  mouth wide open in a vicious bite, glaring, the red war band at its neck; bottom right the worm
  lying out on top of the soil, limp and knocked out with swirly eyes, its red war band and armour
  scrap showing."
- **Worm army props:** "A sheet of four separate game pictures for a top-down adventure game, in a 2
  by 2 grid, evenly spaced with wide empty space between them: top left a single arrow drawn large,
  lying perfectly horizontal and pointing straight to the right, a straight dark wooden shaft, a sharp
  dented dark iron arrowhead at its right end and brick-red feather fletching at its left end; top
  right, bottom left and bottom right three frames of one small punch impact burst effect, in order:
  a bright cream-white and warm yellow star-shaped impact flash with short thick spikes; the same
  burst bigger, breaking apart into a ring of chunky cream and pale orange puffs; the same puffs
  small, faint and fading away."

## Every dungeon: the skeletons (rows 30 to 32)

Built 2026-10-16, the same way (GPT 2.5, 1:1, 1k, transparent background, Lili's sheet as the style
reference); the props sheet also had the Bone Thrower's and the Bone Marcher's sheets as references,
so the remains match the skeletons. Each was the first take. All four came with a faint haze over
the transparent background, which the packer clears (`HAZY`).

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `bone-leaper-sheet.png` | crouched watching (dim embers in its sockets); rattling, eye sockets glowing; leaping, arms and legs spread; landed stuck in a crack, swirly eyes | `256x256-tile_4x1-bone-leaper.webp` |
| `bone-thrower-sheet.png` | standing with the bone raised; wind-up, the bone behind its head; after the throw, hand empty; empty-handed, shaking its fists | `256x256-tile_4x1-bone-thrower.webp` |
| `bone-marcher-sheet.png` | marching toward the viewer, left foot and right foot; marching away (from behind), left foot and right foot | `256x256-tile_4x1-bone-marcher.webp` |
| `skeleton-props-sheet.png` | the thrown bone; a skull; the skull in the Marcher's helmet; the bone pile without its skull | `64x64-bone.webp`, `64x64-skull.webp`, `64x64-helmet-skull.webp`, `128x128-bone-pile.webp` (`PROP_SHEETS` in the packer) |

`python scripts/characters/pack-bestiary-enemies.py bone-leaper bone-thrower bone-marcher skeleton-props`
packs only these.

Cost: 400 Magnific credits (four generations at 100).

Prompts (the same style block first, the same ending):

- **Bone Leaper:** "A sprite sheet of one pouncing enemy for a top-down adventure game, the Bone
  Leaper: a small cute but menacing skeleton, a fallen soldier of an old war, with warm ivory bones,
  a big round skull with dark hollow eye sockets, long bony arms, and a ragged faded red scarf tied
  round its neck. It always crouches low like a frog ready to pounce, knuckles on the ground. The
  sheet is a 2 by 2 grid of four separate poses of the exact same skeleton, same size, same colours,
  same three-quarter top-down view facing the viewer, evenly spaced with wide empty space between
  them: top left crouched low and still, watching, tiny dim embers in its eye sockets; top right
  crouched even lower, rattling and shaking, bones jittering, its eye sockets glowing bright
  orange-gold, about to spring; bottom left high in mid-air in a big leap, arms and legs spread wide,
  scarf flying, glowing eyes; bottom right landed hard, stuck with both feet sunk in a small crack in
  the ground, bones knocked askew, dazed with swirly eyes."
- **Bone Thrower:** "A sprite sheet of one bone-throwing enemy for a top-down adventure game, the
  Bone Thrower: a tall lanky cute but menacing skeleton standing upright, a fallen soldier of an old
  war, with warm ivory bones, a big round skull with dark hollow eye sockets and tiny amber embers in
  them, a tattered moss-green hood and short cloak, and a big old femur bone it throws. The sheet is
  a 2 by 2 grid of four separate poses of the exact same skeleton, same size, same colours, same
  three-quarter top-down view facing the viewer and slightly to the right, evenly spaced with wide
  empty space between them: top left standing ready, holding the big bone up in its right hand like a
  club; top right winding up to throw, leaning back, the bone pulled far back behind its head; bottom
  left right after the throw, its right arm stretched forward and its hand empty and open; bottom
  right empty-handed, no bone anywhere, clattering its jaw and shaking both bony fists angrily."
- **Bone Marcher:** "A sprite sheet of one patrolling enemy for a top-down adventure game, the Bone
  Marcher: a sturdy stiff cute but menacing skeleton soldier, a fallen guard of an old war, with warm
  ivory bones, a big round skull with dark hollow eye sockets and tiny amber embers in them, an old
  dented round iron helmet, and a round wooden shield with a faded green thorn emblem strapped to its
  left arm. It marches stiffly like a toy soldier, arms swinging. The sheet is a 2 by 2 grid of four
  separate poses of the exact same skeleton, same size, same colours, evenly spaced with wide empty
  space between them: top left seen from the front, facing the viewer, marching with its left foot
  forward; top right seen from the front, facing the viewer, marching with its right foot forward;
  bottom left seen from behind, walking away from the viewer, marching with its left foot forward,
  the back of the helmet and the shield's back showing; bottom right seen from behind, walking away,
  marching with its right foot forward."
- **Skeleton props** (references: Lili, the Thrower's and the Marcher's sheets; a shorter style
  block without the wood grain and cloth): "A sheet of four separate objects for a top-down adventure
  game, the remains of the cute skeleton soldiers in the reference pictures, same warm ivory bones and
  same painting. The sheet is a 2 by 2 grid of four separate objects, evenly spaced with wide empty
  space between them: top left a single big old femur bone with a strip of brown cloth wrapped round
  its middle and a little moss, the bone the skeleton throws, drawn large and alone, lying
  diagonally; top right a single big round cartoon skull on its own, the same skull as the
  skeletons, dark hollow eye sockets with tiny dim amber embers, a few teeth, facing the viewer;
  bottom left the same skull wearing the old dented round iron helmet from the reference; bottom
  right a low flat heap of loose ivory bones lying on the ground, ribs, arm and leg bones, a pelvis
  and a few finger bones tangled together, with no skull in it." (ending "Each object isolated ...")

## The Crystal Caverns and the mine (rows 23 to 29) and the Watcher Eye (row 33)

Built 2026-10-16 ([BESTIARY.md](../../../../docs/godot/BESTIARY.md#23-gloomling-shadow)). Nine
generations, each the first take: GPT 2.5 (`gpt-2-mini`, 1:1, 1k, transparent background), Lili's
sheet as the style reference, the style block first and "Each pose (image, prop) isolated on a
transparent background, no ground shadow plate, no scenery, no labels, no grid lines." last. 900
credits.

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `gloomling-sheet.png` | resting, flinching, scuttling away, dissolving into wisps | `256x256-tile_4x1-gloomling.webp` |
| `glint-bat-sheet.png` | asleep hanging, woken hanging, swooping, fallen | `256x256-tile_4x1-glint-bat.webp` |
| `crystal-crawler-sheet.png` | crawling (two steps, seen from above, head right), turning belly up, flipped | `256x256-tile_4x1-crystal-crawler.webp` (`CENTRED`) |
| `prism-eye-sheet.png` | watching (blank orb), blazing, petals shut, shattered | `256x256-tile_4x1-prism-eye.webp` |
| `pick-mole-sheet.png` | ducked, pickaxe raised, throwing, knocked out | `256x256-tile_4x1-pick-mole.webp` |
| `shardback-sheet.png` | walking, rearing, slamming, shell broken (all facing right) | `256x256-tile_4x1-shardback.webp` |
| `crystal-mite-sheet.png` | ready, running, falling curled, shattered | `256x256-tile_4x1-crystal-mite.webp` |
| `watcher-eye-sheet.png` | front (blank eyeball), glowing, its back, broken | `256x256-tile_4x1-watcher-eye.webp` |
| `caverns-props-sheet.png` | crystal pillar, pickaxe, brazier unlit, brazier lit | `props/caverns/256x256-crystal-pillar.webp`, `enemies/64x64-pickaxe.webp`, `props/caverns/256x256-tile_2x1-brazier.webp` |

The two eyes' orbs were asked blank (no iris, no pupil): the game draws the pupil and the iris and
turns them with the gaze.

### Prompts

- **Gloomling:** "A sprite sheet of one shadow creature for a top-down adventure game, the Gloomling:
  a living shadow, a soft round blob of inky deep-violet smoke, darkest in its middle, with thin
  curling wisps of smoke lifting off its edges, and two big round pale lilac glowing eyes with no
  pupils. No mouth, no legs, no arms; it looks shy and sneaky, not scary. The sheet is a 2 by 2 grid
  of four separate poses of the exact same shadow blob, same colours, same three-quarter top-down
  view facing the viewer, evenly spaced with wide empty space between them: top left sitting at
  rest, wide and round and calm, eyes half closed; top right flinching in fright, squeezed tall and
  thin, eyes wide open; bottom left shrunk to a small ball scuttling away to the left, wisps
  streaming behind it; bottom right dissolving, breaking apart into drifting wisps of violet smoke
  with only the faint eyes left."
- **Glint Bat:** "A sprite sheet of one flying cave enemy for a top-down adventure game, the Glint
  Bat: a small round cave bat with dusty plum-grey fur, big pointed ears, leathery dark brown wings
  with tiny pale crystal flecks along the wing bones, and two tiny bright golden glinting eyes. The
  sheet is a 2 by 2 grid of four separate poses of the exact same bat, same size, same colours, same
  three-quarter top-down view, evenly spaced with wide empty space between them: top left asleep
  hanging upside down, wings wrapped tight around its body like a little cloak, eyes shut; top right
  just woken, still hanging upside down, eyes wide and glinting gold, wings starting to unfold;
  bottom left swooping in flight, wings spread wide, mouth open showing two tiny fangs; bottom right
  fallen on the ground, wings crumpled, dazed with swirly eyes."
- **Crystal Crawler:** "A sprite sheet of one cave enemy for a top-down adventure game, the Crystal
  Crawler: a long low centipede-like crawler with a segmented slate-grey armoured body, a row of
  sharp pale icy-blue crystal spikes along its back, many short dark legs, two small glowing teal
  eyes, and a soft pale pink belly underneath. The sheet is a 2 by 2 grid of four separate poses of
  the exact same crawler, same size, same colours, evenly spaced with wide empty space between them:
  top left crawling, seen straight from above, its head pointing to the right, the crystal spikes
  along its back; top right the same top view crawling to the right with its legs in the other
  step; bottom left twisting round a corner, its body curled on its side so its soft pale pink belly
  and legs show; bottom right flipped on its back, legs curled up, dazed with swirly eyes."
- **Prism Eye:** "A sprite sheet of one sentinel enemy for a top-down adventure game, the Prism Eye:
  a squat round pillar of dark slate rock, a little taller than wide, with bands of pale violet
  crystal, topped by a large smooth round crystal orb that is its eye, clear pale lavender with no
  pupil and no iris, held in a ring of pointed crystal petals. The sheet is a 2 by 2 grid of four
  separate images of the exact same sentinel, same size, same colours, same three-quarter top-down
  view facing the viewer, evenly spaced with wide empty space between them: top left watching, the
  orb softly lit lavender, the petals open; top right charging a beam, the orb blazing with bright
  white-violet light and the crystal bands glowing; bottom left closed, the crystal petals folded
  tight over the orb like a shut bud, dim; bottom right shattered, the orb cracked into pieces, the
  petals broken, the pillar chipped, crystal shards around its base." (ending "Each image ...")
- **Pick Mole:** "A sprite sheet of one lobbing enemy for a top-down adventure game, the Pick Mole: a
  stout little miner mole with velvety dark brown fur, a big pink nose, tiny squinting eyes, big
  pale pink digging claws, a patched cream work apron, and a dented mustard-yellow miner's helmet
  with a small lamp on the front. The sheet is a 2 by 2 grid of four separate poses of the exact
  same mole, same size, same colours, same three-quarter top-down view facing the viewer, evenly
  spaced with wide empty space between them: top left ducking, crouched very low and small, head
  pulled down, only the helmet and the top of its head and its claws showing above its shoulders;
  top right standing up tall holding a miner's pickaxe raised high over its head with both claws,
  ready to throw; bottom left throwing, both arms swung forward, empty claws open, the pickaxe just
  released and gone; bottom right knocked out flat on its back, helmet rolled off beside it, dazed
  with swirly eyes."
- **Shardback:** "A sprite sheet of one armoured mini-boss enemy for a top-down adventure game, the
  Shardback: a big sturdy old tortoise with a stony grey-green scaly head and thick legs, small stern
  amber eyes, and a tall domed shell made of clustered pale icy-blue crystals growing out of dark
  rock plates. All four poses face to the right in the same three-quarter top-down view. The sheet is
  a 2 by 2 grid of four separate poses of the exact same tortoise, same size, same colours, evenly
  spaced with wide empty space between them: top left walking slowly, one front foot forward; top
  right rearing up on its hind legs, front feet raised high, the crystals on its shell glowing, about
  to slam down; bottom left slamming its front feet into the ground, head low, small crystal shards
  bursting out around its feet; bottom right defeated, its crystal shell cracked and broken into
  pieces, the tortoise lying flat and dazed with swirly eyes."
- **Crystal Mite:** "A sprite sheet of one tiny swarm enemy for a top-down adventure game, the
  Crystal Mite: a tiny chunky golem made of rose-pink quartz crystal, with a blocky faceted pink
  body, two glowing amber-gold eyes, stubby grey rock arms and legs, and a cheeky angry little face.
  The sheet is a 2 by 2 grid of four separate poses of the exact same mite, same size, same colours,
  same three-quarter top-down view facing the viewer and slightly to the right, evenly spaced with
  wide empty space between them: top left standing ready, fists up; top right running fast, leaning
  forward, legs mid-stride, arms pumping; bottom left falling from above, curled up into a ball with
  arms and legs tucked in, eyes squeezed shut; bottom right shattered into a small heap of broken
  pink crystal pieces."
- **Watcher Eye:** "A sprite sheet of one floating sentinel enemy for a top-down adventure game, the
  Watcher Eye: a round floating orb of weathered grey carved stone, with a band of faint amber runes
  round its middle, patches of moss, and one big glossy eyeball set in its front under a heavy stone
  brow; the eyeball is plain blank white, with no iris and no pupil. The sheet is a 2 by 2 grid of
  four separate images of the exact same stone eye, same size, same colours, evenly spaced with
  wide empty space between them: top left seen from the front, the big blank white eyeball facing
  the viewer; top right seen from the front, charging a beam, the eyeball blazing with bright
  orange-red light and the runes glowing; bottom left seen from behind, turned away from the
  viewer, showing only its round carved stone back with moss and runes and no eye at all; bottom
  right cracked in two and fallen, the eye dark and dull." (ending "... no scenery, no stand, ...")
- **Caverns props:** "A sheet of four separate props for a crystal cave mine in a top-down adventure
  game, in a 2 by 2 grid, evenly spaced with wide empty space between them, same three-quarter
  top-down view: top left a squat crystal pillar, a thick round column of dark slate rock about as
  tall as it is wide, with clusters of pale icy-blue crystals growing from its top and sides and a
  flat base; top right a single miner's pickaxe drawn large and alone, a curved dark iron head and a
  worn honey-wood handle, lying diagonally; bottom left an unlit iron brazier, a round black iron
  bowl on three short curled legs, filled with dark cold coal; bottom right the exact same iron
  brazier lit, a bright crackling orange fire with glowing embers in its bowl." (ending "Each prop
  isolated ...")

## The Gloop Forest's spiders (rows 15 and 16, repainted 2026-10-16)

The owner (2026-10-16) wanted the old 64 px Slime Spider and Orb-weaver sheets (3D renders, the
Orb-weaver cute) replaced, and their webs spat only straight up, down, left or right. They are the
Orb-Weaver Matron's forest brood, goo-slime spiders, mean, each keeping its old look: the Slime
Spider lime goo with dark spots and purple legs, the Orb-weaver leaf green with a web on its back
and a leaf sprout. Never the Broodling's cream and orange, never the Brood Warden's red armour.
Each file is one Magnific GPT 2.5 generation (`gpt-2-mini`, 1:1, 1k, transparent background),
Lili's sheet as the style reference (for the style only); a spider's second and third sheets also
take its first sheet as their first reference, so it stays the same spider.

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `slime-spider-sheet.png` | facing the viewer: crouched idle, scuttling, reared up (the spit tell), spitting down | `256x256-tile_13x1-slime-spider.webp` frames 0 to 3 |
| `slime-spider-sheet-2.png` | facing right: idle, scuttling, reared up, spitting right | frames 4 to 7 |
| `slime-spider-sheet-3.png` | from behind idle, from behind spitting up, hurt (facing the viewer), defeated on its back in a goo puddle | frames 8 to 11 (frame 12: the front scuttle mirrored, `MIRRORED`) |
| `orb-weaver-sheet.png` | the same four as the Slime Spider's first | `256x256-tile_13x1-orb-weaver.webp` frames 0 to 3 |
| `orb-weaver-sheet-2.png` | the same four as its second | frames 4 to 7 |
| `orb-weaver-sheet-3.png` | the same four as its third (the retake) | frames 8 to 11 (frame 12 mirrored) |
| `spider-webs-sheet.png` | the spat web glob flying right, the glob bursting, the open web net, the web wrapped round something round | `64x64-tile_3x1-spider-web.webp` (the first three), `128x128-spider-web-cover.webp` (PROP_SHEETS) |
| `orb-weaver-sheet-3-rejected-haze.png` | the first take of the Orb-weaver's third sheet: a soft glow (alpha up to 128) round every pose | not packed |

Packing: `python scripts/characters/pack-bestiary-enemies.py slime-spider orb-weaver spider-webs`.
The spiders' poses are placed by their body (`BODY_ANCHORED`: the middle of what is left once 48 px
is eroded off each pose, so legs, drips and sprays do not count, sits at the cell's centre), so the
body stays put whichever way the legs rear or the spray shoots; a pose hanging more than
`BODY_FLOOR_PX` (6) below the idle pose's bottom is lifted (the ground ghosts a body's pixels more
than 12 px below its feet). Their faint background haze (alpha 16 at most) is cleared
(`FAINT_HAZE`), keeping stray goo drops.

Cost: 800 Magnific credits (eight generations at 100: seven sheets and the retake).

Prompts (the same style block first, the same ending: "Each pose isolated on a transparent
background, no ground shadow plate, no scenery, no labels, no grid lines."; the webs' "Each image
isolated ..."):

- **Slime Spider, sheet 1:** "A sprite sheet of one enemy creature for a top-down adventure game,
  the Slime Spider: a mean goo-slime spider of a dark forest brood. Its round body is a glossy
  wobbling dome of thick chartreuse yellow-lime slime goo with dark olive-green spots, sticky drips
  of goo hanging from its sides, a small head at the front with a cluster of small glaring crimson
  eyes under an angry scowl and two hooked dark purple fangs dripping lime goo. Eight long thin
  jointed legs in deep violet purple with darker plum tips arch out all around it. It looks
  hostile, sly and menacing, never cute, never scared. The sheet is a 2 by 2 grid of four separate
  poses of the exact same spider, same size, same colours, all facing the viewer (toward the bottom
  of the picture) in the same three-quarter top-down view, evenly spaced with wide empty space
  between them: top left crouched low and still, legs spread wide, glaring, ready to pounce; top
  right scuttling forward toward the viewer, its legs mid-stride on alternating sides; bottom left
  reared up on its back legs with its front legs raised high, fangs spread wide open, its goo body
  swelling, a ball of sticky goo gathering in its mouth, about to spit; bottom right spitting
  straight toward the viewer, body lunging forward, a short burst of sticky lime goo and white silk
  strands shooting out of its fangs."
- **Slime Spider, sheet 2** (references: sheet 1, Lili): "... the Slime Spider, exactly the spider of
  the first reference picture, redrawn in the same painted style: the same glossy wobbling dome body
  of thick chartreuse yellow-lime slime goo with dark olive-green spots and sticky goo drips, the
  same small head with a cluster of glaring crimson eyes and two hooked dark purple fangs, the same
  eight long thin jointed deep violet purple legs with darker plum tips, the same size and colours.
  It looks hostile, sly and menacing, never cute, never scared. All four poses are turned to face to
  the right, seen from its right side in the same three-quarter top-down view, its head and fangs at
  the right of its body. ... top left standing still facing right, legs spread, glaring ahead; top
  right scuttling to the right, its legs mid-stride on alternating sides; bottom left reared up on
  its back legs facing right, its front legs raised high, fangs spread wide open, its goo body
  swelling, a ball of sticky goo gathering in its mouth, about to spit; bottom right spitting to the
  right, body lunging forward, a short burst of sticky lime goo and white silk strands shooting out
  of its fangs toward the right."
- **Slime Spider, sheet 3** (references: sheet 1, Lili): the same description, then "top left seen
  from behind, facing away from the viewer toward the top of the picture, standing still, its big
  spotted goo back and its two stubby spinnerets toward the viewer, legs spread; top right seen from
  behind, facing away toward the top of the picture, reared up on its back legs with its front legs
  raised and spitting straight up away from the viewer, a short burst of sticky lime goo and white
  silk strands shooting upward beyond its head toward the top of the picture; bottom left facing the
  viewer, struck by a blow and recoiling, its goo body squashed sideways and splashing goo drops,
  legs flung out, eyes narrowed in a furious snarl, fangs bared; bottom right defeated, flipped over
  onto its back with its eight purple legs curled up in the air, its goo body sagging into a flat
  lime puddle, eyes shut in dizzy swirls."
- **Orb-weaver, sheet 1:** "A sprite sheet of one enemy creature for a top-down adventure game, the
  Orb-weaver: a big, heavy goo-slime orb-weaver spider of a dark forest brood. A fat round abdomen
  of thick glossy leaf-green slime goo with a pale silvery-white orb-web pattern marked across its
  back and a curled green leaf sprout growing from the top of it, tufts of moss on its shoulders, a
  smaller dark green head with a row of narrowed glowing amber eyes under a heavy brow and big
  hooked black fangs, spinnerets at its rear, and eight thick chunky leaf-green legs with darker
  moss-green bands and hooked dark claws. It is plump, heavy and strong, and looks hostile and
  menacing, never cute, never scared." and the Slime Spider's four poses ("legs planted wide,
  glaring, guarding"; "a ball of sticky silk gathering in its mouth"; "a short spray of sticky white
  silk web and green goo shooting out of its fangs").
- **Orb-weaver, sheets 2 and 3** (references: sheet 1, Lili): "... the Orb-weaver, exactly the
  spider of the first reference picture, redrawn in the same painted style: the same fat round
  abdomen of thick glossy leaf-green slime goo with the pale silvery-white orb-web pattern across
  its back and the curled green leaf sprout growing from its top, the same moss tufts on its
  shoulders, the same smaller dark green head with a row of narrowed glowing amber eyes and big
  hooked black fangs, the same eight thick chunky leaf-green legs with darker moss-green bands and
  hooked dark claws, small stubby dark green spinnerets at its rear, the same size and colours." and
  the Slime Spider's second and third sheets' poses (its web-marked back and leaf sprout from
  behind; "the leaf sprout wilted" when defeated). The third sheet's retake added "Crisp clean
  painted edges with the dark brown outline, no glow, no halo, no mist around the poses."
- **Webs:** "A sprite sheet of four separate effect images for a top-down adventure game: the sticky
  webs that goo-slime spiders spit, painted in the same style as the reference sheet. ... top left
  a spat web glob flying to the right: a round blob of glossy sticky lime-green goo wrapped in pale
  silk threads, with a few loose silk strands and goo drips streaming out behind it to the left; top
  right the same glob bursting open into a small sticky web, silk threads springing out from its goo
  centre in every direction; bottom left a fully open round sticky spider web net seen from above,
  thick pale silvery-white silk threads in a spiral orb pattern with straight radial spokes, small
  lime goo droplets on the threads, the gaps between the threads empty; bottom right a round tangled
  wrap of thick sticky pale silk web strands and a few lime goo blobs, criss-crossing over an empty
  round middle as if wrapped around something round, a few strands drooping at its sides, the gaps
  between the strands empty."

## The climb monsters (rows 34 to 36, 2026-11-14)

Four GPT 2.5 generations (`gpt-2-mini`, 1:1, 1k, transparent background, Lili's sheet as the style
reference, 40 credits each, 160 in all), each the first take. Each prompt began with the style
block and ended with "Each pose isolated on a transparent background, no ground shadow plate, no
scenery, no labels, no grid lines." (the caterpillar's and the raven's also "no vines", "no
ledge").

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `rock-chucker-sheet.png` | ready (a boulder at its belly), the boulder over its head, thrown (arms out), knocked over dazed | `256x256-tile_4x1-rock-chucker.webp` |
| `spiny-caterpillar-sheet.png` | crawling stretched, crawling humped, curled into a C turning, on its back dazed (seen from above, head up) | `256x256-tile_4x1-spiny-caterpillar.webp` |
| `ledge-raven-sheet.png` | perched, flying right wings up, flying right wings down, fallen on its back | `256x256-tile_4x1-ledge-raven.webp` |
| `climb-props-sheet.png` | the boulder, the boulder turned, its shards, a pebble | `64x64-tile_2x1-climb-rock.webp`, `128x128-climb-rock-shards.webp`, `64x64-climb-pebble.webp` |

- **Rock Chucker:** "A sprite sheet of one mountain enemy for a top-down adventure game, the Rock
  Chucker: a burly, mean-looking grey-brown worm warrior with a thick segmented body, a dented iron
  helmet, a scowling face with small angry glossy eyes and a gritted underbite, two short stubby
  strong arms, and a cloth sack of rocks slung on its back. It squats on a cliff top and throws
  boulders down the cliff." Then the 2 x 2 grid of the four poses above, facing the viewer.
- **Spiny Caterpillar:** "... the Spiny Caterpillar: a fat, mean caterpillar that crawls on vines up
  a cliff wall, with a mustard-yellow and moss-green banded body, a row of long sharp toadstool-red
  spikes along its back and sides, small mean red glossy eyes and little hooked mandibles. It is
  seen from straight above, lying flat on the wall, its head pointing up toward the top of the
  image and its tail toward the bottom." Then the four poses.
- **Ledge Raven:** "... the Ledge Raven: a big scruffy glossy black raven with blue-violet sheen on
  its feathers, a heavy sharp grey beak, mean glowing amber eyes and ragged wing tips. It nests on
  rock ledges of a cliff wall." The flights "in strict side profile" to the right.
- **Climb props:** "A sheet of four separate game props in a 2 by 2 grid ...: a round heavy grey
  boulder about the size of a melon, cracked and chipped, with a speck of moss; the exact same
  boulder turned a quarter round; the same boulder smashed into five or six sharp grey rock shards
  and a little gravel; a small grey pebble."

## The Worm Bulwark (row 37, 2026-11-21)

The owner's new enemy: a heavy-armour worm with a big shield who charges ([BESTIARY.md](../../../../docs/godot/BESTIARY.md#37-worm-bulwark-charger)).
GPT 2.5 (`gpt-2-mini`, 1:1, 1k, transparent background), two takes per sheet (count 2, 40 credits
each: 160 for sheets 1 and 2, 240 for the walks, 400 in all). Sheet 1's references: Lili's sheet (the style) and `worm-brawler-sheet.png` (the
army's worms); sheet 2's: sheet 1's take A and Lili. Each prompt began with the style block and
ended with "Each pose isolated on a transparent background, no ground shadow plate, no scenery, no
labels, no grid lines." (sheet 2 also "no stars").

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `worm-bulwark-sheet.png` (take A) | standing guard behind the shield, the wind-up (crouched, braced), charging, defeated (helmet off, shield flat); facing right | `256x256-tile_20x1-worm-bulwark.webp` frames 0 to 3 |
| `worm-bulwark-sheet-take-b.png` | sheet 1's take B, the same four (not packed; the owner may prefer it) | not packed |
| `worm-bulwark-sheet-2.png` (take B) | charging toward the viewer (only the helmet over the shield), charging away seen from behind, skidding to a stop (leaning back, facing right), dazed after a wall (sitting, helmet crooked, swirly eyes) | frames 4 to 7 (`WALK_MATCHED`) |
| `worm-bulwark-sheet-3.png` (take A) | the walk facing right: stretched long, bunched into a hump, stretched, bunched | frames 8 to 11 (`WALK`) |
| `worm-bulwark-sheet-4.png` (take A) | the walk toward the viewer behind the shield: the tail out to one side, bunched, out again, bunched | frames 12 to 15 |
| `worm-bulwark-sheet-5.png` (take A) | the walk away, seen from behind: stretched, humped, the hump rolled forward, stretched | frames 16 to 19 |

- **Sheet 1:** "A sprite sheet of one heavy enemy soldier for a top-down adventure game, the Worm
  Bulwark: a hulking, menacing, mean villain worm, the heavy shield-bearer of a worm army, much
  bulkier than a foot soldier, painted like the worm warriors in the second reference picture, with
  a thick dark olive-green segmented body, a dull ochre belly and two short thick arms, heavy
  scowling brows, small furious glaring eyes and a snarl with bared blunt teeth. It is clad in heavy
  armour: a dented dark iron helmet with a nose guard, and riveted dark iron plates over its
  shoulders and back segments. It wears the army's mark: a ragged brick-red war scarf ... and a dark
  leather strap across its chest with a small dark iron badge stamped with a black horned
  slime-head emblem. It carries a huge rectangular iron tower shield, almost as tall as itself, with
  heavy rivets, a battered rim and a black horned slime-head emblem painted in its middle. Nothing
  cute, scared or blushing ..." Then the 2 x 2 grid "turned to face the RIGHT": standing guard, the
  shield up on its right side, glaring over its top; winding up to charge, crouched low behind the
  shield, tail coiled back like a spring, eyes glinting with fury; charging, stretched forward and
  low, shield thrust out, scarf streaming, dust behind; defeated on its side, swirly eyes, helmet
  tipped off, shield flat beside it.
- **Sheet 2:** "... the Worm Bulwark from the first reference picture: the exact same ... worm [its
  body, helmet, plates, scarf, badge and shield named again] ..." Then four new poses: charging
  straight DOWN toward the viewer, the shield covering most of its body, only the helmet and the
  glaring eyes over its top edge; charging straight UP away from the viewer, seen from behind, no
  face, dust kicked back toward the viewer; facing the RIGHT, skidding to a stop, leaning far back,
  tail dug in, dust spraying ahead; facing the RIGHT, dazed after slamming its shield into a wall,
  slumped back on its coiled tail, helmet crooked over one eye, swirly eyes, shield sagging.

- **Walk sheets 3 to 5** (the same day, after the owner's go-ahead; references: sheet 1's take A and
  Lili, sheets 4 and 5 also sheet 2; two takes each, 240 credits, take A kept): "A walk-cycle sprite
  sheet of the exact armoured worm soldier in the first reference picture, the Worm Bulwark: [his
  body, helmet, plates, scarf, badge and shield named again] ... a 2 by 2 grid of four separate
  frames of one slow plodding walking loop ... same size in every frame." Sheet 3: "In ALL FOUR
  frames it is shown in strict SIDE PROFILE, turned fully to face the RIGHT edge ... It never faces
  the viewer. The helmet, the head, the shield and the size are identical in all four frames ... and
  ONLY its worm body changes in a heavy inching crawl like a caterpillar, no legs", then each frame
  (stretched long; the tail pulled forward into a hump; the hump rolled toward the shield; stretched
  again). Sheet 4: "seen from the FRONT, walking straight DOWN the screen toward the viewer, exactly
  like the top-left picture of the first reference but walking slowly, not charging", only the body
  behind and below the shield changing (the tail out to the left, bunched, out to the right,
  bunched), "No dust". Sheet 5: "seen from BEHIND ... walking straight UP the screen away from the
  viewer, exactly like the top-right picture of the first reference but walking slowly", the body
  stretching and humping, "No dust".

Packing: `python scripts/characters/pack-bestiary-enemies.py worm-bulwark`.

## The Carnivore Plant (row 38, 2026-11-21)

The owner's man-eating plant in a pot ([BESTIARY.md](../../../../docs/godot/BESTIARY.md#38-carnivore-plant-ambusher)).
GPT 2.5 (`gpt-2-mini`, 1:1, 1k, transparent background), two takes per sheet (count 2, 40 credits
each, 160 in all). Sheet 1's reference: Lili's sheet; sheet 2's: sheet 1's take A and Lili. Each
prompt began with the style block and ended with "Each pose isolated on a transparent background,
no ground shadow plate, no scenery, no labels, no grid lines."

| File | Poses (top left, top right, bottom left, bottom right) | Packed into |
|---|---|---|
| `carnivore-plant-sheet.png` (take A) | waiting, the head bowed over the pot rim; about to strike, reared up, jaws wide; the snap, the stem stretched far to the right; chewing, the head bulging full | `384x384-tile_8x1-carnivore-plant.webp` frames 0 to 3 |
| `carnivore-plant-sheet-take-b.png` | sheet 1's take B, the same four (not packed; the owner may prefer it) | not packed |
| `carnivore-plant-sheet-2.png` (take A) | dozing, the head drooped; digesting, fat and asleep; spitting goo to the right; burnt, charred and smoking | frames 4 to 7 |
| `carnivore-plant-sheet-3.png` (take B, 2026-11-21) | about to strike down toward the viewer; snapping down, the head below the pot; about to strike up, from behind; snapping up, the stem stretched over the pot | frames 8 to 11 |
| `carnivore-plant-sheet-4.png` (take A, 2026-11-21) | spitting down toward the viewer; spitting up, from behind; swallowing, a bulge down her stem; a big burp | frames 12 to 15 |

Packed in 384 px cells (`CELLS`) with every pose placed by its pot (`POT_ANCHORED`: the biggest
terracotta blob, its bottom on `POT_FLOORS` 300; the down snap's and the down spit's pots by hand,
`POT_ANCHORS`; each later sheet sized by its usual pot), so the pot stays put however far the plant
reaches. Sheets 3 and 4 (the owner: "eat from top and down as well", and the swallow) took the
first sheet's take A, the second sheet's take A and Lili as references (two takes each, 160
credits): the same plant and pot named again, "The pot never moves and is exactly the same in every
pose, upright, seen from the same three-quarter top-down view", then the four poses each.

- **Sheet 1:** "A sprite sheet of one plant enemy for a top-down adventure game, the Carnivore
  Plant: a menacing, greedy man-eating plant living in a big cracked terracotta clay pot with moss on
  its rim. She has a thick twisting dark green stem, a few broad jagged leaves around the pot rim,
  and a big round flytrap head made of two heavy jaws, deep green outside with dark red veins, lined
  with long pale thorn teeth, the inside of the mouth a glistening crimson; two small mean glowing
  yellow eyes on top of the head and a sly wicked grin. Dangerous and hungry, not cute. The pot never
  moves and is the same in every pose." Then the 2 x 2 grid "facing the viewer and turned slightly to
  the right": waiting, the head bowed low over the pot rim, jaws shut, eyes half closed, watching
  slyly; about to strike, reared up tall, jaws gaping wide, drool dripping; snapping, the stem
  stretched far out to the right, the head lunged forward with the jaws clamped shut; chewing, jaws
  shut and bulging round full of something, cheeks puffed, a smug evil grin.
- **Sheet 2:** "... the Carnivore Plant from the first reference picture: the exact same greedy
  man-eating plant in the exact same big cracked terracotta clay pot [her stem, leaves, head, teeth
  and eyes named again] ... Not cute. The pot never moves and is the same in every pose." Then four
  new poses: dozing, the head drooped limp over the pot rim, eyes closed, a little drool; fast asleep
  and digesting after a big meal, the head swollen fat and round, a smug sleepy smile; spitting, the
  head jerked back with the jaws thrown wide open toward the right, a spray of green goo flying out;
  burnt and defeated, charred black and grey, the stem withered and slumped over the scorched pot
  rim, the leaves crumbled to ash, wisps of smoke, the eyes dark crosses.

Packing: `python scripts/characters/pack-bestiary-enemies.py carnivore-plant`.

## The Jelly Bouncer (row 39, 2026-11-22)

The owner's electric jelly ([BESTIARY.md](../../../../docs/godot/BESTIARY.md#39-jelly-bouncer-shocker)).
GPT 2.5 (`gpt-2-mini`, 1:1, 1k, transparent background), Lili's sheet as the reference, two takes
of each (count 2, 40 credits each, 160 in all); take A of each packed, take B kept beside it.

| File | Pictures | Packed into |
|---|---|---|
| `jelly-bouncer-sheet.png` (take A) | resting, the dome settled low; charging up, swollen, sparks over his skin; zapping, lit almost white with bolts bursting out; defeated, melted into a puddle with cross eyes | `256x256-tile_4x1-jelly-bouncer.webp` frames 0 to 3 |
| `jelly-bouncer-sheet-take-b.png` | the same four, take B (not packed) | not packed |
| `shock-skeleton.png` (take A) | the cartoon skeleton of a round slime: a big round skull, a stubby spine, a small ribcage, two hip bones, glowing cream bones | `128x128-shock-skeleton.webp` (a single picture) |
| `shock-skeleton-take-b.png` | take B (not packed) | not packed |

- **The sheet:** the style block, then "A sprite sheet of one enemy for a top-down adventure game,
  the Jelly Bouncer: a wobbly electric jelly monster shaped like a plump gelatin dome, wider than
  tall, with no legs and no arms. Its body is glossy translucent electric cyan jelly with a bright
  rim light, and inside the jelly floats a glowing pale yellow spark core with little crackling
  yellow lightning threads. It has two small narrow mean yellow eyes and a grumpy wobbly frown near
  the top of the dome. Menacing and charged with electricity, not a cute slime: no big glossy eyes,
  no mouth smile." Then the 2 x 2 grid facing the viewer (the four poses above) and "Each pose
  isolated on a transparent background, no ground shadow plate, no scenery, no labels, no grid
  lines."
- **The skeleton:** the style block (without its palette line), then "A funny cartoon X-ray skeleton
  for an electrocution gag in a top-down adventure game: the bones of a little round slime creature
  as if it were struck by lightning, seen from the front. A big round cartoon skull with two large
  round empty eye sockets and a tiny grinning row of teeth, below it a short stubby spine and a small
  rounded ribcage of four curved ribs, two tiny round hip bones at the bottom. Chunky, rounded,
  glowing bright creamy white bones with a faint pale cyan glow around them, cute and silly, not
  scary. The skeleton fills a squat round shape about as wide as it is tall, like the inside of a
  round jelly blob. One single skeleton, centred, isolated on a transparent background, no body, no
  jelly, no ground shadow plate, no scenery, no labels."

Packing: `python scripts/characters/pack-bestiary-enemies.py jelly-bouncer shock-skeleton`.
