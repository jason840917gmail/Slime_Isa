# Dungeon decor: sources

The dungeons' scenery set (2026-10-19; [PROPS.md](../../../../docs/godot/PROPS.md) "Dungeon decor").
Every file here is one Magnific GPT 2.5 generation (`gpt-2-mini`, 1:1, 1k, transparent background,
`192x192-tile_8x8-interior-mushroom-furniture-props.webp` as the style reference), a 1024 px sheet
with four props in a 2 x 2 grid. Each was the first and only take.

| File | Props (top left, top right, bottom left, bottom right) |
|---|---|
| `dungeon-decor-iron-a.png` | hanging chains, wall shackles, hanging cage, weapon rack |
| `dungeon-decor-furniture-a.png` | guard table, guard bench, barrel stack, broken crates |
| `dungeon-decor-stone-a.png` | sarcophagus, broken pillar, bone pile, worm-head statue |
| `dungeon-decor-misc-a.png` | candelabra, bookshelf, floor grate, stalagmites |

`python scripts/art/pack-dungeon-decor-art.py` cuts each sheet, scales each prop to its size in game
units (2 px a unit) into `godot/asset/MAPS/objects/dungeon/decor/` and writes the scenes in
`godot/game/scenes/objects/dungeon-decor/`.

Cost: 400 Magnific credits (four generations at 100).

## Prompts

Each prompt began with the style block of the
[style guide](../../../../docs/assets/visual-style-guide.md#generating-assets), then "A sprite sheet of
four separate ... props for an old stone dungeon ... in a top-down adventure game, a little gloomy but
still cozy and storybook[, no gore]. The sheet is a 2 by 2 grid of four separate objects, each
centered in its own quarter with wide empty space between them:", the four props, and "Each object
isolated on a transparent background, no ground shadow plate, no scenery, no labels, no grid lines."

- **Iron:** heavy rusty iron chains hanging down in loops from an iron ring bolted to a small mossy
  stone block; a pair of old iron wall shackles on short chains fixed to a mossy stone slab; a small
  round rusty iron birdcage-style hanging cage, empty, its little door hanging open; a wooden weapon
  rack holding three old spears and a dented round shield with a red worm emblem.
- **Furniture** (a guard room): a heavy rough wooden guard table with iron bands, a melted candle, a
  tin mug, dice and a rolled old map on it; a long rough wooden bench with a worn plank seat; a stack
  of three old oak barrels bound with rusty iron hoops, one lying on its side; a heap of broken wooden
  crates and splintered planks with a torn sack.
- **Stone** (a crypt, cartoon-like): an old grey stone sarcophagus with a carved lid, moss in its
  cracks; a broken stone pillar stump with fallen chunks and rubble round its base; a small cartoon
  pile of old bleached bones and two round skulls with moss, harmless and storybook; a squat mossy
  stone statue of a fierce worm warrior's head with a crown of horns and glowing amber eyes.
- **Misc:** a tall wrought-iron standing candelabra with five dripping lit candles; a tall rickety
  wooden bookshelf with dusty old books, scrolls and a few cobwebs; a square rusty iron floor drain
  grate set in a few worn flagstones with a small dark puddle; a cluster of three damp grey
  stalagmites with moss at their feet.
