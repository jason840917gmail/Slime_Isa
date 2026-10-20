# Handover 2026-10-17: falling planks over water, and a Goo Heart inside a chest

Committed in 2a04028b (2026-10-17's snapshot). The full description is in [DUNGEONS.md](../godot/DUNGEONS.md#falling-planks-over-water)
("Falling planks over water", and "Chests" for the heart).

## Done and working

- **Falling planks**: `object.falling-plank` (`godot/game/dungeon/falling_plank.gd`, on
  `falling_slab.gd`, which now has small hooks for its art, cues, drop time and drawing; the slab's
  own behaviour is unchanged). **Plank landing**: `object.plank-landing` (`plank_landing.gd`, a
  HazardDeck). Shared look and lane: `plank_look.gd`. Splash rings: `water_splash.gd`.
- **Water hazard**: `hazard.gd` has a new `kind` "water". `hazard_watch.gd` sinks the slime with a
  splash, takes off `dungeon.water.damage` and puts it back on the bank. A form that swims never falls
  in. The fall's tween is now stopped when the slime lands, so a tween that runs on in real time can
  no longer hide the slime after a void or water fall.
- **Heart chest**: `chest.gd` has the `goo_heart_id` export, so world chests and dungeon chests both
  have it. `goo_heart.gd` has a static `grant(...)` (the pickup uses it too, and works as before),
  `is_heart_taken` and `default_icon`. `dungeon_chest.gd` gives the heart beside dungeon items.
- **Item pop fix**: `item_pop.gd` takes a size and a duration, and is placed before it enters the
  tree. Before, it started at the world origin, which also hid the dungeon items' pops.
- **Cue**: `WaterSplash` in `game/scenes/audio/global.tscn` (the SwimEnter takes).
- **Numbers**: `dungeon.water` and `dungeon.plank` in game-constants.json.
- **Dev world** `world.playground-planks` (`godot/game/dev/planks/playground-planks.tscn`, built by
  `godot/tools/build_plank_lab.gd`). It is in game/dev, so the export leaves it out. Run it with
  `?map=playground-planks`. It plays in the body-shapes mode unless `?classic`.
- **Film** `godot/tools/film_planks.gd`, **art packer** `scripts/art/pack-plank-art.py`.
- Docs: DUNGEONS.md, TOOLING.md, specs/audio.md.

## Interface for the maps agent

- **A bridge**: lay one `object.falling-plank` per 64-unit cell along a lane one cell wide across
  deep water. Each plank has `size` 64 x 64, its position on the cell's corner, and `east_west = true`
  for a bridge that runs east-west. Put an `object.hazard` before the planks in the tree, with
  `kind = "water"` and `size` covering the lane only (not the banks). Give the hazard two Node2D
  children named `Return...` (for example `ReturnSouth` and `ReturnNorth`), one on each bank, each
  set to the slime's centre there. The planks open the water's collision under their cells
  themselves, so do not add a bridge_deck node for them.
- **A long bridge with no landing** (the come-back secret): only a Roll that keeps rolling crosses
  it. In the story's mode (the body-shapes mode) that is the **charged Roll, the `roll-charge`
  upgrade**, held all the way. That upgrade is planned and not given anywhere in the story yet. In
  the classic game, the Roll held crosses. Walking, the quick Roll, and quick Rolls in a row fall in.
  The bridge must be straight north-south or east-west, because the Roll does not steer.
- **A bridge for the quick Roll**: put an `object.plank-landing` (64 x 64) after every two planks.
- **A chest's heart**: set `goo_heart_id` on the chest's `ChestScript` child to a heart id that is
  unique across maps (the chest needs editable children). It works on `game.chest` and on
  `object.dungeon-chest` / `object.dungeon-big-chest`. If the chest holds only the heart, leave
  `initial_contents` empty.

## Tests

- `godot/tests/test_falling_planks.gd` (4 tests) and `godot/tests/test_heart_chest.gd` (2 tests).
  All 6 passed when they were run. After those runs I changed three things and did not run the tests
  again:
  - the tween stop in `hazard_watch.gd`;
  - the item pop's placement;
  - the chests moved to row 3.2 on the island, with the heart test's standing spot moved to match.
- Next step: run each file once, `pnpm test:godot -- --filter=test_falling_planks` and
  `--filter=test_heart_chest`, using the test.lock routine.
- I also did not run `test_dungeon_kit.gd`'s slab and void tests, which `falling_slab.gd` and
  `hazard_watch.gd` touch.

## Pictures

The scratchpad folder `kit-planks/` holds `contact-sheet.png` (14 frames: the held Roll across, the
walk falling in and back on the bank, the chest's heart), `heart-closeup.png`, and the frames in
`frames/`. These pictures come from the film run before the last fixes:

- In that run the walk's slime was invisible after its fall. The tween fix addresses this.
- In that run the Roll was released too early and fell in. The film now holds it until the island.

The last film run, after the fixes, shows the heart rising out of the chest.

## Art and credits

Magnific GPT 2.5 (`gpt-2-mini`), transparent background, the Lili creation as the style reference.
One call with 2 variants, 200 credits in all.

- Kept: `asset/Originals/dungeon-kit/generated/plank.png`, packed to
  `godot/asset/MAPS/objects/dungeon/plank-2x1.webp`.
- Not used: `asset/Originals/dungeon-kit/generated/rejected/plank-b.png`.

Its `.import` file (`plank-2x1.webp.import`) came from the editor and is committed with it (2a04028b).

## Not done

- The East-west planks (`east_west`) were never tried in a world.
- The heart's "+10 max HP" text shows over the rising heart at the start. It would read better if
  the text came a moment later.
