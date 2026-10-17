# The Weaver Hollow's Spinning Loft and the brood's altar

Sources for the Hollow's rework around the Pearl inside the dungeon
(docs/design/2026-10-17-pearl-mid-dungeon.md "The Weaver Hollow": "New art: the loft's dressing
(silk rafters)"; docs/godot/DUNGEONS.md "The Weaver Hollow (built)"): the dressing of C4 the Spinning
Loft and the Hoard's altar for Pearl 2. Generated 2026-10-17 with Magnific GPT 2.5 (`gpt-2-mini`, 1k,
transparent background), the Lili creation as the style reference, 100 credits each (200 in all),
one take each. Packed by `scripts/art/pack-loft-art.py` into `godot/asset/MAPS/props/weaver-hollow/`
(`loft-rafter`, `loft-peg-rail`, `loft-spool`, `loft-spinning-wheel`, `brood-altar`), drawn by the
scenes in `godot/game/scenes/objects/weaver-hollow/` and placed by `tools/weaver_hollow/hollow_floors.gd`.

Every prompt starts with the style block of docs/assets/visual-style-guide.md ("Cozy storybook
woodland game art, hand-painted 2D miniature, three-quarter top-down view, chunky rounded shapes,
warm golden light from the upper left, soft painted shading with visible wood grain, moss and cloth
texture, dark warm brown outline, earthy palette of honey wood, leaf green, cream and toadstool red,
no text.") and ends with "Isolated on a transparent background, no ground shadow plate, no scenery."

| File | Size | Prompt (after the style block) |
|---|---|---|
| `loft-dressing-a.png` | 1536 x 1024 (3:2) | A sprite sheet of four separate props for an old spider spinning loft inside a giant hollow oak, arranged in a 2 by 2 grid with clear empty space between them, each one complete and not touching the others. Top left: a long weathered wooden rafter beam seen from the front, as it hangs high on a wall, with loose swags of cream-white spun silk thread draped over it in a few sagging loops and thin strands dangling below; much wider than tall; the silk is thin and loose, not a curtain, not a web. Top right: an old wooden peg rail seen from the front with three hanks of cream silk yarn hanging from its pegs, wider than tall. Bottom left: a big old wooden bobbin spool standing upright on the floor, wound thick with cream silk thread, a loose end trailing to the floor. Bottom right: a small old wooden spinning wheel standing on the floor, its wheel and spindle tangled with cream silk thread. No spider, no web, no cocoon, no egg sacs, no faces. |
| `brood-altar-a.png` | 1024 x 1536 (2:3) | One prop: an old round stone altar pillar, the spider brood's shrine inside a giant hollow oak, about one and a half times as tall as wide, standing on a base of mossy rocks. Its top is a shallow round empty stone cup where a glowing pearl would rest (the cup is empty). The pillar is carved with faint old spiral marks and loosely bound with a few old strands and ribbons of cream-white spun silk, a little moss, three small amber beads tied on the silk. Not a cocoon, not an egg, no web, no spider, no face, no eyes, no pearl. |

Clarity (the level design guide's look book): the loft's silk is thread on wood (spools, hanks, swags
over a beam), never a standing curtain filling an opening (a web wall), a flat bundle on the floor (a
silk parcel) or anything that breathes (the Cocoon Mimic). The rafters and the peg rail hang on the
north wall's face, the spool and the wheel stand in the corridors' corners, away from the parcel.
