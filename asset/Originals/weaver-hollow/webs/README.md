# The Weaver Hollow's webs

Sources for the Hollow's webs (docs/design/2026-10-16-dungeon-weaver-hollow.md "What must be built"
-> Webs; docs/godot/WEBS.md): floor webs painted on a WebLayer, web walls (`object.web-wall`) and
silk parcels (`object.silk-parcel`). Generated 2026-10-17 with Magnific GPT 2.5 (`gpt-2-mini`, 1k,
transparent background), the Lili creation as the style reference, 100 credits each (400 in all), one
take each. Packed by `scripts/art/pack-web-art.py` into `godot/asset/MAPS/webs/`
(`floor-webs-6x1.webp`, `palette.png`, `web-wall-across-2x1.webp`, `web-wall-side-2x1.webp`,
`silk-parcel-3x1.webp`); the packer thins the floor webs' milky fill between the strands and paints
the parcel's glint star where the generated glint frame has its sparkle.

Every prompt starts with the style block of docs/assets/visual-style-guide.md ("Cozy storybook
woodland game art, hand-painted 2D miniature, three-quarter top-down view, chunky rounded shapes,
warm golden light from the upper left, soft painted shading with visible wood grain, moss and cloth
texture, dark warm brown outline, earthy palette of honey wood, leaf green, cream and toadstool red,
no text.") and ends with "Isolated on a transparent background, no ground shadow plate, no scenery."
(the floor webs: "no ground, no shadow plate, no scenery").

| File | Size | Prompt (after the style block) |
|---|---|---|
| `floor-webs-a.png` | 1536 x 1024 (3:2) | A sprite sheet of six separate flat spider-silk webs lying flat on the ground, seen from above, arranged in a 3 by 2 grid with clear empty space between them. Each one is a thin, loose, irregular sheet of cream-white silk strands stuck to the floor like a ground decal: a few radiating threads and sagging cross threads, small torn holes, a few tiny glossy dew drops, slightly sticky. Each web is roughly round, about as wide as tall, completely flat with no height: no posts, no frame, no spider, no cocoon, no egg sacs, no leaves. The six differ in their strand pattern. Delicate strands, mostly see-through, each strand with a faint warm brown edge so it reads on any floor; it must read as a web lying on the floor. |
| `web-wall-front-a.png` | 1536 x 768 (2:1) | Two states of the same thick spider-web wall that fills a doorway, seen from the front, side by side with empty space between them. Left: intact, a dense square curtain of thick cream-white silk filling the whole opening, anchored along its left and right edges and its top edge, layered sagging strands over a radial web pattern, so thick that nothing could pass, a few glossy dew drops. Right: the same web after it was cut open: only torn strands and ragged tatters hanging from its left and right edges and the top, the middle clear. Only the silk: no door frame, no wall, no stone, no wooden posts, no spider. Each is about as wide as tall. |
| `web-wall-side-a.png` | 1024 x 768 (4:3) | Two states of the same thick spider-web plug filling a narrow side passage, seen from above and a little from the side, side by side with empty space between them. Each is a tall narrow vertical band, about three times as tall as wide. Left: intact, a dense band of thick cream-white silk strands bunched and layered from its top end to its bottom end, sagging threads crossing it, so thick that nothing could pass, a few glossy dew drops. Right: the same band after it was cut through: only short ragged tatters of silk left clinging at its top end and its bottom end, the long middle clear and empty. Only the silk: no wall, no stone, no posts, no spider. |
| `silk-parcel-a.png` | 1536 x 768 (2:1) | Three states of the same small flat silk parcel lying on the ground, in a row with empty space between them. The parcel is a low, wide, flat bundle wrapped tightly in cream-white spider silk, lying flat on the floor like a wrapped package, clearly wider than tall and very low: never upright, not an egg, not a cocoon, no face, no eyes. Silk threads crisscross it and a few loose strands are stuck to the ground around it. Left: closed. Middle: closed, with a small bright golden glint sparkle on its top as if something shiny were inside. Right: torn open: the silk split down the middle and peeled back in flaps, empty inside, loose strands around it. |

Clarity (the level design guide's look book, question 129): floor webs lie flat and round on the
floor, never standing; web walls are thick standing silk filling an opening; the parcel lies flat,
wide and low, glints and never breathes, so it never reads as the Cocoon Mimic (upright, breathing)
or Tom's cocoon. The side web wall's band is the front web's anchored silk column, seen edge on.
