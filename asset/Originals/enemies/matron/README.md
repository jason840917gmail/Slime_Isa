# The Orb-Weaver Matron's cocoon fight: sources

The Weaver Hollow's boss (built 2026-10-17; [specs/matron.md](../../../../docs/godot/specs/matron.md)).
Two Magnific GPT 2.5 generations (`gpt-2-mini`, 1:1, 1k, transparent background, Lili's sheet as the
style reference), each a 1024 px sheet with four pictures in a 2 x 2 grid, each the first and only
take (200 credits): `cocoon-sheet-a.png`, and `matron-sheet-a.png`, made with the cocoon sheet as a
second reference so she is the spider inside it.

| Picture | Packed into |
|---|---|
| `cocoon-sheet-a.png`, top left: the cocoon hanging from its thread, her purple shape and six red eyes through the silk | `godot/asset/MAPS/enemies/256x416-tile_2x1-matron-cocoon.webp`, frame 0 |
| top right: the same cocoon torn open, empty | the same strip, frame 1 |
| bottom left: Pearl 2 in a cradle of silk | `godot/asset/MAPS/props/256x256-pearl-silk.webp` |
| bottom right: her thread's spool | `godot/asset/MAPS/props/128x128-matron-spool.webp` and the bag icon `godot/asset/MAPS/items/64x64-matron-thread.webp` |
| `matron-sheet-a.png`, top left and top right: the Matron fallen out of her cocoon, dazed (her legs twitch between the two) | `godot/asset/MAPS/enemies/384x384-tile_4x1-matron.webp`, frames 0 and 1 |
| bottom left: recoiling from a hit | the same strip, frame 2 |
| bottom right: climbing her thread, from behind | the same strip, frame 3 |

`python scripts/art/pack-matron-art.py` cuts each sheet along its emptiest middle row and columns,
trims each picture, hangs the two cocoons at one scale from the top middle of their 256 x 416 cells
(the rest of the thread, the shadow, the eyes' glow, the breath and the threads of the re-spin are
drawn in code: `game/bosses/matron_cocoon_look.gd`), stands her four poses at one scale in 384 px cells
(the thread above and below the climbing pose, and a stray bit of it, trimmed), and fits the Pearl and
the spool alone in their cells.

## Prompts

Each began with the style block of the
[style guide](../../../../docs/assets/visual-style-guide.md#generating-assets).

**Cocoon sheet:** "A sheet of four separate pictures for a boss fight against a giant, mean spider queen (the
Orb-Weaver Matron) in a top-down adventure game, laid out in a 2 by 2 grid with wide empty space
between the pictures. Top left: a huge, tight, egg-shaped boss cocoon of thick pale cream spider silk
wound in many crossing strands, hanging from a single taut silk thread at its top, the dark purple
shape of a big spiky spider curled up inside showing faintly through the silk, and a cluster of six
small fierce glowing red spider eyes burning through the silk near its top, menacing and alive. Top
right: the exact same cocoon, same size and silk, torn wide open down its front, ragged shredded silk
flaps curling outward, empty and shadowy inside, still hanging from its thread. Bottom left: a large
lustrous magic pearl, milky white with a soft violet and silver sheen and a gentle glow, resting in a
small round cradle of woven silk strands, a precious treasure. Bottom right: a small old wooden spool
wound thick with shining silver-white spider thread, a loose end of thread trailing from it, on its
own. Each picture isolated on a transparent background, no ground shadow plate, no scenery, no
labels, no grid lines."

**Matron sheet** (the cocoon sheet as a second reference): "A sprite sheet of one boss monster for a
top-down adventure game, the Orb-Weaver Matron: a huge, mean spider queen, the same dark purple spiky
spider that is curled up inside the cocoon of the second reference picture. She has a big bulbous dark
purple abdomen marked with a pale cream orb-web pattern, a smaller armoured purple head and body,
eight long spiky violet legs with dark hooked tips, a cluster of six fierce small red eyes, two cruel
curved fangs, and a few torn wisps of pale cream silk clinging to her legs. She looks dangerous and
nasty, never cute. The sheet is a 2 by 2 grid of four separate poses of the exact same spider, same
size and colours, with wide empty space between them: top left she has just fallen out of her cocoon
onto the ground, dazed and stunned, legs splayed out and curled, body slumped low, her red eyes dim;
top right the same dazed pose with her legs twitching the other way and her head lolling to the other
side; bottom left recoiling from a hit, legs flinched in, eyes squeezed shut, fangs bared; bottom
right seen from behind climbing straight up a single taut silk thread, all legs gripping the thread
above her. Each pose isolated on a transparent background, no ground shadow plate, no scenery, no
labels, no grid lines."
