# West town villagers and animals (2026-11-01)

The West town's people and animals: the cast, lines and the owner's picks are in
[docs/design/2026-11-01-west-town-villagers.md](../../../../docs/design/2026-11-01-west-town-villagers.md);
how they are packed, built and placed in
[docs/godot/VILLAGERS.md](../../../../docs/godot/VILLAGERS.md).

Every image is Magnific GPT 2.5 (`gpt-2-mini`), 2k, transparent background, 65 credits; 107 in all,
about 6,950 credits. Each prompt began with the style block of
[docs/assets/visual-style-guide.md](../../../../docs/assets/visual-style-guide.md#generating-assets),
then "Glossy translucent jelly slime body with rim light, cute big glossy eyes" for a slime (the
eyes left out for a back view), and ended with "Each frame isolated on a transparent background, no
ground shadow plate, no scenery, no labels, no grid lines."

## Roughs (`roughs/`) and boards (`board/`)

| Sheet | Grid | Figures | Reference |
|---|---|---|---|
| `villagers-1.png` .. `-4.png` | 3 x 2 (the last 2 x 2) | V1-V22, the pick board's numbers | `villager-style-ref` |
| `animals-1.png`, `-2.png` | 3 x 2, 4 x 2 | A1-A12 | both |
| `sisters-a.png`, `-b.png` | 3 in a row | the sisters, three colours / one family colour | `villager-style-ref` |
| `sisters-c.png` (picked), `-d.png` | 3 in a row | look B with a colour each and the owner's hair and builds; C hair of jelly, D natural hair | `villager-style-ref` |
| `parents-a.png`, `-b.png` (picked) | 2 in a row | Dan and May, two takes of one prompt | `villager-style-ref` |

`villager-style-ref` is the smith, Burr, Lili, Elder Plop and Yoi side by side (one idle frame of
each); the animals also had the town set's `concepts/props-a.png`. The boards: the pick boards
(`west-town-villagers-board.jpg`, `west-town-animals-board.jpg`), the game-scale mockup on the town
set's test layout (`west-town-life-mockup*.jpg`), `sisters-board.jpg`, `family-board.jpg` and the
rooms' first pass (`rooms-first-pass.jpg`, the shops and the family home; `homes-first-pass.jpg`, the 19
other homes). `tools/` holds the scripts that made them
(`cut_roughs.py`, `board.py`, `mockup.py`, `preview_gif.py`).

## Final sheets (`generated/`)

Packed by `scripts/characters/pack-villagers.py` into `godot/asset/characters/villagers/`.

- `<id>-poses.png`, 2 x 2: a villager standing idle, the same blinking, talking (a hand or its prop
  raised), laughing ("The body, accessories and size are identical in all four frames; only the face
  and one hand change"); an animal idle, two rest poses (a snuffle, a nap, a peck...), the idle
  blinking. Reference: the character's rough cut out of its roughs sheet.
- `<id>-walk-side.png`, `-walk-down.png`, `-walk-up.png`, 2 x 2, one loop each. A slime: "Slimes have
  no legs: she walks with a soft bouncy jelly hop ... ONLY the squash and stretch of the jelly body
  changes: top left standing upright at rest; top right squashed low and wide; bottom left stretched
  tall and leaning forward; bottom right landing". An animal: "ONLY its four short legs change, in a
  trotting walk" (a step, passing, the other step, passing). The side sheets say "In ALL FOUR frames
  ... in strict SIDE PROFILE, turned fully to face the RIGHT edge of the picture ... never faces the
  viewer"; the up sheets "seen from BEHIND ... no face showing". Reference: the rough (Penny, the
  pig, the animals) or the character's own pose sheet (the other walkers and the family).
- 3 x 2 sheets: the birds (`robin`, `dove`, `bluebird`, `goldfinch`: standing side, pecking, a hop,
  wings up, wings down, standing front; `swallow`: perched, gliding, swooping, wings up, wings down,
  perched front; the robin's sheet the others' reference), `chick` (side, peck, hop, two running
  steps, front), `duck` and `duckling` (swimming side, bobbing, dabbling, toward, away, blinking; "the
  bottom of its body cut off in a soft flat line at the waterline"), `snail` (three crawl lengths,
  hidden in its shell, peeking, front) and `butterflies` (orange, blue, yellow; wings open, then
  raised).
