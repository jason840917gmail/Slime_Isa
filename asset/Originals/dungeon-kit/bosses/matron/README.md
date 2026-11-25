# The Orb-Weaver Matron, reworked: look sources (2026-11-24)

Step 2 of the [dungeons 2 and 3 rework](../../../../../docs/design/2026-11-23-dungeons-2-3-rework.md#the-orb-weaver-matron):
her look, for the owner's yes before any frames or fight are built. Not packed, not in the game: the
look sheet `output/boss-rework/matron-look.png` (built by `output/boss-rework/make_look_sheets.py`)
shows them. The cocoon fight's packed art of today is still `asset/Originals/enemies/matron/`.

Four Magnific GPT 2.5 generations (`gpt-2-mini`, 1:1, 1k, `transparentBackground`), each the first
and only take, 160 credits. The style reference on all four is Lili's sheet
(`godot/asset/characters/authored/npcs/lili.webp`, uploaded as "style-reference-character-sheet").

| File | What | Magnific creation | Other reference |
|---|---|---|---|
| `matron-design.png` | her design, facing the viewer | `oviV3le829` | today's `enemies/matron/matron-sheet-a.png` (uploaded, `Bh6T6LloQR`) |
| `matron-poses-1.png` | hanging idle, spitting, the dive, caught by the ram (flung) | `vQGXc1da47` | the design |
| `matron-poses-2.png` | on her back kicking, climbing back up (from behind), spinning a cocoon, beaten | `6A57xediJO` | the design |
| `matron-cocoons.png` | the cocoon she fights from, whole and torn | `MBOzN53DCm` | the design |

All four carry a faint background haze (alpha under about 48); the sheet script clears it.

## Frames (2026-11-24)

The owner approved the look ("i like both keep going") and the animation frames followed, in
`frames/`: nine GPT 2.5 sheets (`gpt-2-mini`, 1:1, 1k, `transparentBackground`), each four frames
of one animation in a 2 x 2 grid read left to right, top to bottom; 400 credits (ten generations
with the rejected take). References on every sheet: Lili's sheet (the style), `matron-design.png`
and the look sheet whose pose it animates. Packed on 2026-11-24 by `python scripts/art/boss_frames.py
pack matron` into `godot/asset/MAPS/enemies/bosses/matron/` (one strip per animation and
`frames.json`; the fallen cocoon's frames at 0.75 of her scale, since the model drew it filling its
picture) and played by her ram fight (docs/godot/specs/matron.md section 9).

| File | The four frames | Magnific creation | Third (fourth) reference |
|---|---|---|---|
| `frames/matron-hang.png` | hanging idle, a loop: legs half curled, opening, widest, closing | `vQGtJOya47` | `matron-poses-1.png` |
| `frames/matron-spit.png` | wind-up, charge (a glob between the fangs), the spit (web spray), recover | `xSokTovjfW` | `matron-poses-1.png` |
| `frames/matron-dive.png` | lets go, falling, legs flung wide like a star, landed in dust | `WDSzk7RcXe` | `matron-poses-1.png` |
| `frames/matron-rammed.png` | struck from the left, flung, tumbling (belly up), crashed on her back | `DoyTsiapcl` | `matron-poses-1.png` (`matron-poses-2.png`) |
| `frames/matron-on-back.png` | on her back kicking, a loop (belly up, legs in the air) | `vQGt045a47` | `frames/matron-rammed.png` |
| `frames/matron-on-back-rejected.png` | the first take: her back and legs up, it reads as rearing, not upside down | `gOhLeFxSXO` | `matron-poses-2.png` |
| `frames/matron-climb.png` | climbing her thread from behind, a loop, front legs hand over hand | `vQGt9pTa47` | `matron-poses-2.png` |
| `frames/matron-spin.png` | spinning her cocoon: the first bands, abdomen wrapped, wrapped to the collar, closed | `fHnh6oqCDY` | `matron-poses-2.png` (`matron-cocoons.png`) |
| `frames/matron-cocoon.png` | **frame 1 not used** (asked "dented by a blow", it came torn open: it would read as round 1's tear); knocked down whole on its side, straining (a claw through the silk), torn open on the ground | `SyvsdjGUb8` | `matron-design.png` (the cocoons first) |
| `frames/matron-dazed.png` | dropping out of the torn cocoon, dazed twice (legs splayed, then twitching), flinching from a hit | `tCZoy8fmZJ` | `matron-poses-2.png` |

Not frames: the cocoon's breathing and its swing when struck stay in code
(`matron_cocoon_look.gd` already swells it and pulses its eyes, smoother than four frames), drawn
from `matron-cocoons.png`. The fall out of the cocoon is `matron-dazed.png` frame 1; her death,
the look's "beaten" pose (`matron-poses-2.png`, bottom right).

`python scripts/art/boss_frames.py preview|contact|showcase` cuts the sheets, clears the haze, lines
the frames up on the part that holds still (the abdomen hanging, the belly on her back, the
abdomen climbing; dive, rammed and dazed centred, the cocoon on the ground bottom-centred) at one
scale for every sheet (hanging 190 game px wide, as in the game today) and writes previews to
`output/boss-rework/frames/` (git-ignored): a GIF and strip per animation, `matron-contact.png`
(every frame at game size) and `matron-showcase.gif` / `.webp` (all nine playing at once).

The frames' prompts all open as the poses' did (the style block, "The first reference picture is
only the painting style.", "A sprite sheet of animation frames for one boss monster ...: the exact
same giant spider queen as in the second reference picture, the Orb-Weaver Matron, same design in
every frame: [her design restated]. Mean and frightening, never cute.") and end "Each frame isolated
on a transparent background, no ground shadow plate, no scenery, no glow or haze, no labels, no
numbers, no grid lines." Between them:

- **Hang:** "The sheet is a 2 by 2 grid of four frames of ONE slow breathing idle loop, read left to
  right then top to bottom, each frame in its own quarter with wide empty space between them. In
  every frame she hangs head down exactly as in the top-left picture of the third reference
  picture: her abdomen above, her crowned head lowest and facing the viewer, a short straight piece
  of thick taut silk thread rising from the tip of her abdomen. Her body, head, crown, colours, size
  and position are IDENTICAL in all four frames; ONLY her legs move, slowly, and her abdomen swells
  a little: frame 1, legs half curled and spread; frame 2, the legs opening a little wider, the
  claws flexing, the abdomen slightly swollen; frame 3, the legs at their widest, claws spread;
  frame 4, the legs closing halfway back, between frame 3 and frame 1."
- **Spit:** the same hanging pose "exactly as in the top-right picture"; "only her head, fangs and
  front legs move": the wind-up (head drawn back into her collar), the charge (fangs wide, a glob of
  pale web and venom welling between them), the spit ("a small burst of pale sticky web spray and
  venom droplets just in front of her fangs"), the recovery (a last string of web drooping).
- **Dive:** "ONE dive attack from above ... her crowned head and six red eyes facing the viewer in
  every frame, no thread": lets go (legs pulled in tight), falling (legs opening), "plunging at the
  viewer with all eight legs flung wide open like a star ... exactly like the bottom-left picture of
  the third reference picture", "landed hard: slammed flat onto the ground ... a low ring of dust
  and loose silk around her".
- **Rammed:** "ONE moment when a heavy swinging log rams her from the LEFT side and flings her to the
  RIGHT (the log itself is NOT drawn)": struck (crumpled, chips of chitin and silk flying off her
  left side), flung (tilted far over, legs trailing), still tumbling ("turned almost upside down,
  her pale segmented belly showing"), "crashed down on her back on the ground ... like the top-left
  picture of the fourth reference picture". The game mirrors it for a ram from the right.
- **On her back** (retaken): "In every frame she lies flipped UPSIDE DOWN on her back on the ground,
  like the bottom-left picture of the third reference picture, and we look down at her UNDERSIDE:
  her pale mauve-and-cream segmented belly and the underside of her chest face up toward the
  viewer, her web-marked abdomen is hidden underneath her, her crowned head upside down at the
  bottom of her body, fangs gnashing; her eight legs stick UP into the air from both sides of her
  body, bent at the joints like an upturned beetle", then ONLY the legs move: left kicked up, all
  half curled, right kicked up, all spread wide. (The first take asked only "her paler segmented
  belly up" and drew her right way up.)
- **Climb:** "she climbs straight up her thick taut silk thread, seen from behind exactly as in the
  top-right picture of the third reference picture ... a short straight piece of thread above her
  and below her", ONLY her legs moving hand over hand.
- **Spin:** hanging head down, "the same size in every frame": the first bands from her abdomen, the
  abdomen wrapped, "wrapped up to her collar ... like the bottom-left picture of the third reference
  picture", "the cocoon closed ... exactly like the left picture of the fourth reference picture".
- **Cocoon** (the cocoons first, the design second): "the exact same cocoon as the left picture of
  the second reference picture ... Same cocoon, same size, same colours in every frame": struck
  (asked dented; came torn), knocked down whole on its side ("the torn end of its thread pointing to
  the left, a small puff of dust"), "bulging and straining as the spider queen struggles inside, one
  claw tip poking out through the silk", "torn wide open down its front by a blast".
- **Dazed:** "she drops out of her torn cocoon (the cocoon is not drawn), tumbling head first, legs
  flailing, scraps of cream silk stuck to her"; "dazed: sprawled flat on her belly on the ground,
  her eight legs splayed limp around her, her six red eyes dim and dizzy"; the same with two legs
  twitching and her head lolling; "struck while dazed: recoiling from a hit, her body jerked up,
  legs flinched in, fangs agape, eyes flaring, a few chips of chitin flying".

## Prompts

Each began with the style block of the
[style guide](../../../../../docs/assets/visual-style-guide.md#generating-assets), then "The first
reference picture is only the painting style."

**Design:** "One boss monster for a top-down adventure game, a single large picture filling the frame:
the Orb-Weaver Matron, a huge, heavy, mean spider queen, the mother of a whole brood of forest
spiders. She is a grander, more regal and more frightening version of the purple spider in the second
reference picture: keep that spider's colours and markings. Seen from the game's three-quarter
top-down view, facing the viewer, standing low and wide on her eight legs. A massive, swollen, heavy
dark plum-purple abdomen, far bigger than the rest of her, marked with a bold pale cream orb-web
pattern and ringed with short thorny spines, with three small cream egg sacs with orange spots stuck
to its rear with silk. A smaller armoured head and chest crowned with dark crimson chitin plates
edged in old gold, like a cruel queen's crown and collar. A cluster of six small fierce glowing red
eyes, two long curved ivory fangs dripping yellow-green venom. Eight long, thick, spiky violet legs
with dark hooked claws, torn wisps of cream silk wound round them. Dangerous, heavy and nasty, never
cute, no big friendly eyes. Isolated on a transparent background, no ground shadow plate, no scenery,
no glow or haze behind her, no labels."

**Poses 1** (the design as reference): "A sprite sheet of one boss monster for a top-down adventure
game: the exact same giant spider queen as in the second reference picture, the Orb-Weaver Matron,
same design in every pose: [the design's features restated]. Mean and frightening, never cute. The
sheet is a 2 by 2 grid of four separate poses of her, all the same size, with wide empty space
between them. Top left, hanging idle: she hangs head down from one thick taut silk thread that runs
from the tip of her abdomen straight up out of the top of her picture, her abdomen above, her head
lowest and facing the viewer, her legs half curled and spread, waiting, watching. Top right,
spitting: the same hanging pose on her thread, her head reared back, fangs wide open, spitting a fat
glob of pale sticky web and yellow-green venom down toward the viewer. Bottom left, the dive: she has
let go and plunges down through the air at the viewer, no thread, all eight legs flung wide open like
a star, claws out, fangs wide, eyes blazing, about to land on her prey. Bottom right, struck: hit
hard from the left by a heavy blow and flung sideways through the air to the right, her body tilted
and tumbling, legs trailing behind her, eyes wide with shock, fangs agape, a few scraps of silk and
spit flying off her. Each pose isolated on a transparent background, no ground shadow plate, no
scenery, no glow or haze, no labels, no grid lines."

**Poses 2** (the design as reference), the same opening, then: "Top left, on her back: she lies
flipped on her back on the ground, her web-marked abdomen underneath, her paler segmented belly up,
all eight legs kicking and clawing at the air, helpless and furious, fangs gnashing. Top right,
climbing: seen from behind, she climbs straight up one thick taut silk thread that runs out of the
top of her picture, her front legs gripping the thread above her, her big web-marked abdomen toward
the viewer. Bottom left, spinning a cocoon: hanging on her thread, she pulls broad bands of fresh
cream silk from the tip of her abdomen with her hind legs and winds them round her own body, her
lower half already wrapped in a half-made silk cocoon, her crowned head and front legs still free.
Bottom right, beaten: collapsed on her belly on the ground, all eight legs curled in tight under
her, her head down, her red eyes gone dark."

**Cocoons** (the design as reference): "Two separate pictures side by side with wide empty space
between them, for a boss fight against the giant spider queen of the second reference picture, who
fights from inside her cocoon. Left: her boss cocoon, whole: a huge, tight, swollen, egg-shaped
cocoon of thick pale cream spider silk wound in many crossing bands, hanging from one thick taut silk
thread at its top, bulging as if it breathes; the dark plum-purple shape of the big spiky spider
queen curled up inside shows through the silk, with her cluster of six small fierce glowing red eyes
burning through the silk in its upper half and the gold-edged crimson points of her crown and two
thorny spines poking out through the silk; menacing and alive. Right: the exact same cocoon, same
size, same silk, same thread, torn wide open down its front by a blast: ragged shredded silk flaps
curling outward, scorched at their edges, dark, empty and shadowy inside, loose strands hanging."
