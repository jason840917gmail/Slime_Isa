# The Weaver Hollow's Goo Bomb pieces

Sources for the Hollow's bomb locks (docs/design/2026-10-16-dungeon-weaver-hollow.md "What must be
built" -> The Goo Bomb's locks; docs/godot/BODY_SHAPES.md "The Goo Bomb"). Generated 2026-10-17 with
Magnific GPT 2.5 (`gpt-2-mini`, 1k, transparent background), the Lili creation as the style
reference, 100 credits each (300 in all). Packed by `scripts/art/pack-weaver-bomb-art.py` into
`godot/asset/abilities/goo-bomb/` (`blast-keg-2x1.webp`, `winch-post-2x1.webp`, `floor-hole.webp`);
the packer lays the cracked wall's crack decal (the bomb's universal mark) on the keg and the post and
cuts the burst keg's smoke wisp.

Every prompt starts with the style block of docs/assets/visual-style-guide.md ("Cozy storybook
woodland game art, hand-painted 2D miniature, three-quarter top-down view, chunky rounded shapes,
warm golden light from the upper left, soft painted shading with visible wood grain, moss and cloth
texture, dark warm brown outline, earthy palette of honey wood, leaf green, cream and toadstool red,
no text.") and ends with "Isolated on a transparent background, no ground shadow plate, no scenery."

| File | Size | Prompt (after the style block) |
|---|---|---|
| `keg-a.png` | 1536 x 768 (2:1) | A game prop sheet: two versions of the same object side by side, each centred in its own half with empty space between them. LEFT: an old Thorn Guard blast keg from a ruined fort: a squat, wide, heavy powder keg of dark charred oak, clearly wider than it is tall, lying on its side in a black iron cradle that is bolted down onto a square grey flagstone block with big rivets, three thick black iron hoops with rivets around it, a faded red thorn emblem painted on its round end, the curved belly facing the viewer is plain dark wood with no markings, it looks heavy, sturdy and fixed to the floor, not a liftable barrel. RIGHT: the same keg after it blew up: the black iron cradle and the flagstone block are still there, the keg itself burst open into splayed charred staves and bent iron hoops, black scorch marks, a thin wisp of smoke. |
| `winch-post-a.png` | 1536 x 768 (2:1) | A game prop sheet: two versions of the same object side by side, each centred in its own half with empty space between them. LEFT: an old fort's winch post for a drawbridge: a short, thick, square post of weathered grey stone blocks with a rounded carved capstone, about as tall as it is wide plus a half, a heavy old dark iron chain wound three times tightly around its middle and held by a big black iron ring bolted to its front, its large flat front stone face below the chain is plain and smooth with no markings, a little moss at its foot. RIGHT: the same post after an explosion: only a shattered stump of broken stone blocks is left, chunks and rubble scattered around its foot, the iron chain snapped and lying slack in loose loops on the ground beside the stump, dust. |
| `floor-hole-a.png` | 1024 x 1024 (1:1) | A game decal lying flat on the ground: a jagged round hole freshly blown through an old fort's grey flagstone floor, seen from a three-quarter top-down view: broken flagstone edges and a few cracked slab chunks tipping into the hole, a ring of cracked stone and small rubble around its rim, inside a deep pitch-dark shaft going straight down into darkness with a few old tree roots on its walls and a faint wisp of dust, no ladder, no water, no rope. The rubble fades out at the rim so it sits on any floor. |

Clarity (the level design guide's look book): the keg lies in a cradle bolted to a stone block, wider
than tall and dark, so it reads as fixed, never as the Gulp's liftable keg (an upright honey-wood
barrel) or a heavy block; the post's crack sits on its stone under the ring, the same decal as on
cracked walls.
