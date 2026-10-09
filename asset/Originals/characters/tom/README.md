# Tom: sources

Tom (roadmap 8.13, built 2026-10-09) is the slime caught in a spider web in Gloop Forest; cutting
him free (quest Tom in the Web) teaches Swallow. Every file here is a Magnific GPT 2.5 still with a
transparent background (1024 px).

| File | What it is |
|---|---|
| `tom-a.png` | The chosen take: a round blue jelly slime with a moss-green scarf and a small bottle of glowing essence on a cord. The prompt asked for amber-orange; the model made him blue, which was kept because it reads well and differs from the other NPCs |
| `tom-b-sheet.png` | The other take, a sheet of small Toms with different expressions; not used |
| `cocoon.png` | Made from `tom-a`: Tom wrapped in white silk between two twigs, worried, his bottle showing |
| `web-torn.png` | The torn, empty web between two twigs |

`python scripts/characters/pack-tom.py` packs Tom into
`godot/asset/characters/authored/npcs/tom.webp` (one 256 px cell, Tom 210 px tall) and the web into
`godot/asset/MAPS/props/256x256-tile_2x1-tom-web.webp` (the cocoon 228 px tall, then the torn web at
the cocoon's scale, so it sits where the cocoon stood). Each still is centred at x 128 and stands on
y 252. Scenes: `character.tom` and `object.tom-web`.

Cost: 400 Magnific credits (four stills at 100).

## Prompts

Mode `gpt-2-mini`, 1:1, 1k, transparent background.

- `tom-a`, `tom-b-sheet` (one call, two takes; Lili's sheet as the style reference; the style
  guide's style block plus its slime line): "Tom, a chubby friendly amber-orange slime character, a
  little rounder and bigger-bellied than a young slime, with a wide cheerful grin showing he loves
  a good gulp, a short knitted moss-green scarf, and a tiny cork-stoppered glass bottle of glowing
  blue essence hanging from a cord around him. Standing still, facing the viewer. Single character
  only, centered, full body visible, no ground, no shadow, no other objects, transparent
  background."
- `cocoon` (`tom-a` as the image reference): "The exact same blue jelly slime from the reference
  image, with the same face, moss-green scarf and essence bottle, now caught in a spider web:
  wrapped up to his cheeks in thick white silk strands like a cocoon, the silk tied to two short
  broken twigs stuck in the ground on either side, only his worried big eyes and the top of his
  head showing, sweat drop on his head. Single subject only, centered, fully visible, no ground, no
  shadow, no spider, no other objects, transparent background."
- `web-torn` (Lili's sheet as the style reference): "A torn, empty spider silk cocoon lying open on
  the ground: loose ragged white silk strands and cut threads hanging between two short broken
  twigs stuck in the ground, a few wisps of silk on the floor. Nothing inside. Single object only,
  centered, fully visible, no ground plane, no shadow, no creatures, transparent background."
