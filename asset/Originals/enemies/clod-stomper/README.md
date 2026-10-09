# Clod Stomper: sources

The Clod Stomper (roadmap 8.12, built 2026-10-09) is a squat one-eyed golem of mud and pebbles, a
small Fatty One Eye that stomps instead of swinging. Every file here is a Magnific GPT 2.5 still
with a transparent background (1024 px).

| File | What it is |
|---|---|
| `idle-a.png` | The chosen look: a round body of brown mud studded with pebbles and moss, a stone slab for a brow over one big blue eye, a leaf sprout on top, two stubby feet |
| `idle-b.png` | The other take; not used |
| `crouch.png` | Made from `idle-a` as the image reference: squatting low, the eye narrowed (the stomp's wind-up) |
| `air.png` | From `idle-a`: up in the air, the feet tucked (the hop) |
| `slam.png` | From `idle-a`: squashed flat on landing, the eye squeezed shut, pebbles flying |
| `defeated.png` | From `idle-a`: slumped into a heap, the eye closed |

`python scripts/characters/pack-clod-stomper.py` packs them into
`godot/asset/MAPS/enemies/256x256-tile_5x1-clod-stomper.webp` (frames: idle, crouch, air, slam,
defeated). Every pose is drawn at one scale (the idle 170 px wide), centred at x 128 and standing on
y 248 of its 256 px cell, so the poses keep their sizes relative to each other. Walk and idle have
no frames of their own: the scene (`character.clod-stomper`) keys them on the idle frame, a waddle
tilt and a breath. Its script is `godot/game/scripts/clod_stomper.gd`.

Cost: 600 Magnific credits (six stills at 100).

## Prompts

Mode `gpt-2-mini`, 1:1, 1k, transparent background. `idle-a`/`idle-b` (one call, two takes) used
Lili's sheet as the style reference and began with the style block from the
[style guide](../../../../docs/assets/visual-style-guide.md#generating-assets); the poses used
`idle-a` as an image reference and began with a short form of it ("Cozy storybook woodland game
art, hand-painted 2D miniature, three-quarter top-down view, dark warm brown outline, no text.").

- `idle-a`, `idle-b`: "A single small squat golem creature made of packed brown mud and embedded
  round pebbles, wide dome-shaped body as wide as it is tall, two stubby thick mud feet, no arms,
  one big round glossy eye in the middle of its face with a grumpy heavy brow made of a flat stone,
  a few tufts of moss and a tiny sprout on top, cracks in the dried mud, standing still and facing
  the viewer and slightly to the right. Single creature only, centered, full body visible, no
  ground, no shadow, no other objects, transparent background."
- `crouch`: "The exact same mud and pebble golem creature from the reference image, same colours,
  same pebbles, same stone brow, same single big eye and sprout, now crouching low before a jump:
  its round body squashed down and wider, its stubby feet bent and spread, its eye narrowed in
  effort under the heavy stone brow. Same size and same view as the reference." + "Single creature
  only, centered, full body visible, no ground, no shadow, no dust, no other objects, transparent
  background."
- `air`: same opening, "now in mid-air at the top of a jump: its body stretched a little taller and
  narrower, its stubby feet tucked up under it, its eye wide open, the sprout bent by the jump",
  plus "no motion lines".
- `slam`: same opening, "at the instant it lands a heavy stomp: its body slammed flat and very wide
  like a squashed dumpling, its feet splayed out to the sides, its eye squeezed shut, a few loose
  pebbles popping off its back", plus "no dust cloud".
- `defeated`: "The same mud and pebble golem creature from the reference image, defeated: it has
  crumbled into a low rounded heap of brown mud and loose pebbles, the flat stone brow lying on
  top, its single eye closed as a sleepy curved line, the little sprout drooping. Same colours as
  the reference. Single heap only, ..."
