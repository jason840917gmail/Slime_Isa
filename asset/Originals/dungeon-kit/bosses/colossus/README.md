# The Crystal Colossus, reworked: look sources (2026-11-24)

Step 2 of the [dungeons 2 and 3 rework](../../../../../docs/design/2026-11-23-dungeons-2-3-rework.md#the-crystal-colossus):
his look, three armour plates (L, C, R) that are his health bar, for the owner's yes before any frames
or fight are built. Not packed, not in the game: the look sheet `output/boss-rework/colossus-look.png`
(built by `output/boss-rework/make_look_sheets.py`) shows them. Today's packed art is still
`asset/Originals/mine/colossus-sheet-*.png`.

Six Magnific GPT 2.5 generations (`gpt-2-mini`, 1:1, 1k, `transparentBackground`), 240 credits. The
style reference on all of them is Lili's sheet (`godot/asset/characters/authored/npcs/lili.webp`).

| File | What | Magnific creation | Other reference |
|---|---|---|---|
| `colossus-design-a-rejected.png` | design, take A: the chest plate came heart-shaped (reads as a love heart) | `gOhkvXySXO` | today's `mine/colossus-sheet-a.png` (uploaded, `iGKJKhG3uK`) |
| `colossus-design-b-rejected.png` | design, take B: asked to change only the chest plate; still a heart | `P3FgKAf42C` | take A |
| `colossus-design.png` | **the design**, take C: a broad flat breastplate slab, the two shoulder plates apart | `xSoHfJbjfW` | today's sheet A |
| `colossus-poses-1.png` | walking toward the viewer, to the right (profile), away (from behind), the stomp raised | `ksdufnI16B` | the design |
| `colossus-poses-2.png` | a plate brittle (chest glowing orange), a plate burst (bare rose quartz under it), clinging to a wall (from behind), on his back; **the last one is not used** (a jumble: his plates scattered, the body not readable as lying belly up) | `dt9cnwZXSL` | the design |
| `colossus-on-his-back.png` | on his back, retaken alone: head left with dizzy eyes, soles up, the three plates face up | `gOhk1D4SXO` | the design |

Every picture carries a faint background haze (alpha under about 48); the sheet script clears it.
The retaken "on his back" is drawn bigger than the 2 x 2 poses: the sheet shrinks it by 170 / 300 (its
breastplate's width against the pose sheets', measured by eye).

## Frames and plate layers (2026-11-24)

The owner approved the look ("i like both keep going"); the frames followed in `frames/`: six GPT
2.5 sheets of four frames each (2 x 2, read left to right, top to bottom), each sheet again as a
plate-less edit, and one sheet of burst shards; 13 generations, 520 credits. References: Lili's
sheet (the style), `colossus-design.png` and the look sheet whose pose it animates; each `-bare`
sheet has its plated sheet as the picture to edit and `colossus-walk-down-bare.png` as the second
reference (the sockets' look). Not packed, not in the game.

| Plated sheet | Its four frames | Creation | Bare edit | Creation |
|---|---|---|---|---|
| `colossus-walk-down.png` | walking toward the viewer: a step, passing, the other step, passing | `Td7W5rvVNR` | `-walk-down-bare.png` | `ksdb0Nq16B` |
| `colossus-walk-side.png` | walking right, strict profile (the near shoulder plate and the breastplate's edge) | `6A54ERXiJO` | `-walk-side-bare.png` | `bxDFow65Y2` |
| `colossus-walk-up.png` | walking away, from behind (the backs of the shoulder plates) | `nVlAkVKYQD` | `-walk-up-bare.png` | `yiQ7K03PW9` |
| `colossus-stomp.png` | the raise, reared up (fists high, a foot lifted), the slam (shards and dust), staggered (a fist to his face, dizzy stars) | `O6uwmRCynm` | `-stomp-bare.png` | `jU81aZ1LD0` |
| `colossus-leap-cling.png` | crouched to leap (front), leaping up (behind), clinging (behind), shifting his grip | `w4fg8Rj7EI` | `-leap-cling-bare.png` | `O6uw5puynm` |
| `colossus-fall.png` | falling off the wall, crashed in dust, on his back dazed twice (**frame 4 drawn the wrong way round, head right: mirrored**) | `8a3Xy5vIrU` | `-fall-bare.png` | `iGK9LhA3uK` |
| `colossus-plate-burst.png` | a plate bursting into shards, eight loose cold shards, the same shards glowing hot, a burst of crystal dust | `nVlAkfyYQD` | — | — |

**The plates as layers** (`scripts/art/boss_frames.py`, "the Colossus's plates as layers"): the
game draws the bare body and lays each plate still on him over it. Per frame the bare edit is
scaled to the plated frame's height, placed on it by cross-correlation and its colours matched to
the plated rock. A plate's region is the pale, low-saturation, bright pixels of the plated frame
(the facet lines closed, the crystal glints opened away), its holes filled, joined by the bare
frame's rose-quartz socket under it; a socket with no plate seen over it (his right shoulder plate
behind his fist when staggered) is named by where it sits. The layer is the plated frame's pixels
in that region grown by 11 px (its outline and a ring of rock that hides the socket's edge),
feathered by 4 px over solid rock only. Plates are named by the screen side they sit on when he
faces the viewer: **L** (his right shoulder), **C** (the breastplate), **R** (his left shoulder);
from behind L is on the right; in profile facing right the near plate is L and the chest edge C
(mirrored for the left: swap L and R); on his back (head left) L is below his head. A hot plate is
the layer's light pixels mapped to an ember ramp with an orange halo (the game may do it as a
shader); a burst plate is its layer gone, the shards of `colossus-plate-burst.png` flying.

Fixes the tool makes, by name: `colossus-walk-down-bare.png` came back with a see-through grey haze
for a background (the only one; its figure is its opaque part, the light patches and rim peeled
off), and its frame 3 has no chest socket (frame 4's is copied in, `borrow`); `colossus-fall.png`'s
frame 4 is mirrored; the fall's frame 1 (mid-air) shows two plates, the third hidden.

`python scripts/art/boss_frames.py preview|contact|showcase` writes the previews to
`output/boss-rework/frames/` (git-ignored): per animation a GIF of five plate states,
`colossus-contact.png` (every frame twice: three plates; the chest gone and L hot) and
`colossus-showcase.gif` / `.webp` (the walks, the stomp, the leap, the fall, and the breastplate
going cold, hot, bursting). One scale for every sheet: walking toward the viewer 180 game px tall, as
in the game today.

Prompts: the plated sheets open as the poses' did (the style block, "The first reference picture is
only the painting style.", "A [walk-cycle] sprite sheet ... the exact same rock golem as in the second
reference picture, the Crystal Colossus, same design in every frame: [the design restated, the three
plates named]") and end "Each frame isolated on a transparent background, no ground shadow plate, no
scenery, [no dust,] no glow or haze, no labels, no numbers, no grid lines." Between them:

- **Walk down:** "a 2 by 2 grid of four frames of ONE heavy walking loop ... In every frame he walks
  straight DOWN the screen toward the viewer, seen from the front exactly like the top-left picture
  of the third reference picture, all three plates facing the viewer. His body, head, plates, colours
  and size are IDENTICAL in all four frames and his body stays level; ONLY his legs and arms move in
  a slow, heavy, lumbering stride: frame 1, his left foot stepping forward and down, his right fist
  swinging forward; frame 2, passing: both feet under him, fists hanging low; frame 3, his right foot
  stepping forward and down, his left fist swinging forward; frame 4, passing again."
- **Walk side:** "In ALL FOUR frames he is shown in strict SIDE PROFILE, turned fully to face the
  RIGHT edge of the picture, walking to the right, exactly like the top-right picture of the third
  reference picture: his near shoulder plate toward the viewer, the front edge of his breastplate on
  his chest, his far shoulder plate hidden behind his body ... He never faces the viewer and never
  turns his head toward the viewer", the stride as above (front leg far forward, passing, back leg
  far forward, passing).
- **Walk up:** "he walks straight UP the screen, away from the viewer, seen from BEHIND exactly like
  the bottom-left picture of the third reference picture: his broad rock back toward the viewer with
  the crystal crest down his spine, the backs of his two shoulder plates on top of his shoulders; his
  face and his breastplate are hidden", the stride as above.
- **Stomp** (the second pose sheet as a fourth reference): "seen from the front facing the viewer,
  all three plates whole and facing the viewer in every frame, the same size in every frame: frame
  1, the raise: leaning back, his right foot lifting off the ground, both fists rising to his chest;
  frame 2, reared up tall, the right foot lifted high and both fists raised above his head, exactly
  like the bottom-right picture of the third reference picture; frame 3, the stomp: his right foot
  slammed down, both fists hammered into the ground before him, his body bent forward low, a burst
  of crystal shards and dust around his foot and fists; frame 4, staggered by a blow: reeling back
  off balance, one fist raised to his face, his eyes squeezed shut, dazed."
- **Leap and cling:** "ONE leap onto a high wall ...: frame 1, crouched low ready to leap, seen from
  the front ...; frame 2, leaping straight up, seen from BEHIND, his arms reaching high above his
  head, legs trailing below ...; frame 3, clinging to a flat wall (the wall itself is NOT drawn),
  seen from behind exactly like the bottom-left picture of the third reference picture ...; frame
  4, the same clinging pose shifting his grip: his left arm reaching higher, his right arm lower,
  one leg drawn up."
- **Fall** (the retaken "on his back" as the third reference): "ONE fall from a high wall ...: frame
  1, falling backward off the wall, seen from the front, arms flung up, legs kicking, his body
  tipping back; frame 2, crashed down flat on his back on the ground with a burst of dust and
  pebbles, his head to the left; frame 3, lying flat on his back, dazed, exactly like the third
  reference picture: [its layout restated] ...; frame 4, the same pose as frame 3, his feet and fists
  twitching, his head lolling the other way."
- **Each bare edit:** "The exact same picture as the first reference picture: the same four frames
  of the same rock golem in exactly the same poses, positions, sizes, colours, outline and painting
  style, changed in ONE way only: his three bright pale cyan crystal armour plates are gone. Where
  the breastplate was, his chest is bare: a raw socket in his dark rock filled with a rough cluster
  of glowing rose-pink quartz crystal points, sitting flatter and a little smaller than the plate
  was. Where each shoulder plate was, his rounded bare rock shoulder shows, lower and smaller than
  the plate was, with a small cluster of glowing rose-pink quartz crystal points in its middle. The
  bare sockets look exactly like those in the second reference picture. No pale cyan plates
  anywhere, no shards. Everything else is identical ...", worded per sheet (only the shoulders
  from behind; "he still faces the right in strict side profile"; "the same dust, shards and
  stars").
- **Plate burst:** "A sheet of four separate effect pictures ... for the moment the boss golem of the
  second reference picture loses one of his armour plates ...: top left, one big pale icy cyan-white
  crystal armour plate, like his breastplate, bursting apart into eight big sharp separate shards
  flying outward, with a few small chips; top right, eight separate sharp loose shards of pale icy
  cyan-white crystal plate lying apart from each other with clear space between them, each a
  different shape and size, each with a bold dark outline; bottom left, the same eight loose shards
  glowing hot orange and amber like embers, apart from each other; bottom right, a small round burst
  of sparkling pale cyan crystal dust and bright glints."

## Prompts

Each began with the style block of the
[style guide](../../../../../docs/assets/visual-style-guide.md#generating-assets), then "The first
reference picture is only the painting style."

**Design, take C:** "One boss monster for a top-down adventure game, a single large picture filling
the frame: the Crystal Colossus, a hulking, mean rock golem, the lord of a crystal mine. He is a
reworked version of the golem in the second reference picture: the same heavy build, hunched, long
thick arms with big clawed fists, short thick legs, a small head sunk between huge shoulders, amber
glowing eyes under a craggy brow, a jagged jaw of deep-blue crystal teeth. Seen from the game's
three-quarter top-down view, standing facing the viewer. His body is dark slate-grey rock, rough and
plain, with only a few small deep-blue crystal studs on his fists and feet and a short crest of
deep-blue crystal spikes down his head and back, and thin cracks between his rocks showing a faint
rose-pink quartz inside. Over this dark body he wears exactly THREE big separate armour plates of
bright pale icy cyan-white crystal, each one a single thick smooth faceted slab with a clean bevelled
edge and a bold dark outline, set clearly apart from each other with dark rock between them. Plate
one, the breastplate: a broad, heavy, wide octagonal slab bolted flat across his chest below his
chin, wider than it is tall, with a straight horizontal top edge, a straight horizontal bottom edge
and cut corners, like the lid of a stone chest; no notch, no point. Plate two: one large rounded
pauldron slab on his left shoulder. Plate three: one large rounded pauldron slab on his right
shoulder. The three plates are by far the brightest and biggest shapes on him, much lighter than
everything else, easy to read and count at a glance from far away. No other armour, no glowing orb
in his chest, no extra plates. Dangerous and heavy, never cute. Isolated on a transparent background,
no ground shadow plate, no scenery, no glow or haze behind him, no labels." (Take A asked for "one
large shield-shaped plate covering his chest" and got a heart; take B asked for "a wide hexagon with
a straight flat top edge and a blunt pointed bottom" and kept the heart.)

**Poses 1** (the design as reference): "A sprite sheet of one boss monster for a top-down adventure
game: the exact same rock golem as in the second reference picture, the Crystal Colossus, same design
in every pose: [the design's features restated, the three plates named]. Same size and colours in
every pose. The sheet is a 2 by 2 grid of four separate poses of him, with wide empty space between
them. Top left, walking toward the viewer: seen from the front, one heavy foot stepping forward,
fists swinging low, all three plates facing the viewer. Top right, walking to the right: seen from
the side in strict profile facing right, one heavy foot stepping forward, his right shoulder plate
toward the viewer, the edge of his breastplate showing on his chest, his crystal crest along his
back. Bottom left, walking away: seen from behind, one foot stepping, his broad rock back with the
crystal crest down his spine and the backs of his two shoulder plates on top of his shoulders.
Bottom right, the stomp raised: seen from the front, rearing up tall, one huge foot lifted high off
the ground and both fists raised above his head, about to slam down, all three plates facing the
viewer. Each pose isolated on a transparent background, no ground shadow plate, no scenery, no glow
or haze, no labels, no grid lines."

**Poses 2** (the design as reference), the same opening, then: "Top left, a plate brittle with
heat: standing seen from the front, his breastplate glowing bright hot orange and amber from inside
like an ember, a web of fine glowing cracks across it, wisps of heat rising off it, his two shoulder
plates still pale icy cyan-white and cold. Top right, a plate burst: standing seen from the front,
staggering, his breastplate shattered and gone, big pale cyan shards flying off his chest, and where
it was his bare chest shows a raw cluster of glowing rose-pink quartz crystal, his two shoulder
plates still whole. Bottom left, clinging to a wall: seen from behind, climbing up a flat wall, both
arms raised high with his clawed fists dug into the rock above him, legs braced, his crystal crest
and the backs of his two shoulder plates toward the viewer. Bottom right, on his back: fallen flat
on his back on the ground, dazed, his feet and fists in the air, his head turned toward the viewer
with dizzy eyes, all three plates on top of him facing up."

**On his back, retaken** (the design as reference): "One boss monster for a top-down adventure game,
a single picture: the exact same rock golem as in the second reference picture, the Crystal
Colossus, [the design's features restated]. Here he has fallen over and lies flat on his back on the
ground, knocked out for a moment, seen from above at the game's three-quarter view. His body is laid
out lengthways across the picture from left to right, his head at the left end tipped back with dizzy
swirling eyes and stars, his two short thick legs at the right end sticking up in the air with the
soles of his feet showing, his two big arms flopped out to the sides above and below his body, fists
half open. His broad breastplate faces straight up at the camera in the middle of his body, the
biggest bright shape, and his two shoulder pauldron plates sit on either side of his head, all three
plates clearly separate and easy to count. A small puff of dust under him. Dangerous even when down,
never cute. Isolated on a transparent background, no ground shadow plate, no scenery, no glow or
haze, no labels."

## The quake's cracks and craters (2026-11-24)

The owner added his quake (a warning, then the floor shaking for 5 s; only climbing the roots is
safe), first drawn with code lines, then: "raise credits to 1,400 and make the crack art". Two
Magnific GPT 2.5 stills (`gpt-2-mini`, 1:1, 1k, `transparentBackground`), 80 credits (the rework's
total then 1,270 of 1,400). The style reference on both is Fatty's ground crack
(`godot/asset/MAPS/effects/boss-ground-crack-4x1.webp`, enlarged three times and uploaded): a
cracked-ground effect already painted in the game's style. Packed by
`python scripts/art/pack-quake-art.py` into `godot/asset/MAPS/effects/colossus-quake-fissures-1x4.webp`
(each fissure trimmed and fitted to 640 x 120, its crack along the cell's middle line) and
`colossus-quake-craters-4x1.webp` (each crater fitted to 240 px in a 256 px cell); the game draws
them in `godot/game/bosses/colossus_quake.gd`.

| File (`quake/`) | What |
|---|---|
| `fissures-raw.png` | four long fissures stacked in rows: dark grey-blue stone split open, chipped slabs lifted along the lips, molten orange glowing inside, thick in the middle and thinning to hairline tips |
| `craters-raw.png` | four impact craters in a 2 x 2 grid: the stone sunk and broken into slabs, glowing cracks radiating, pale blue crystal chips, dust at the rim |

Both prompts began with the style block, then:

- **fissures:** "A game sprite sheet of four separate long ground fissures, stacked in four rows with
  empty space between them, each a single horizontal crack running across the whole width of its
  row, painted like the cracks in the reference image but long and narrow: a jagged split in dark
  grey-blue cave stone seen from above, lying flat on the floor, with a few short side branches and
  chipped edges, small broken stone flakes lifted along its lips, glowing molten orange light deep
  inside the crack, widest in the middle and thinning to hairline tips at both ends. Only the cracks
  and their chipped lips, no floor around them. Isolated on a transparent background, no ground
  shadow plate, no scenery."
- **craters:** "A game sprite sheet of four separate small ground impact craters in a 2 by 2 grid
  with empty space between them, painted like the cracked ground bursts in the reference image but in
  a dark crystal cave: seen from above, lying flat on the floor, each a round burst of cracked dark
  grey-blue cave stone, its middle sunk and broken into chunky slabs, short cracks radiating out with
  glowing molten orange light inside them, a few pale blue crystal chips and pebbles thrown around
  it, a puff of dust at its rim; four different shapes. Only the craters, no floor around them.
  Isolated on a transparent background, no ground shadow plate, no scenery."
