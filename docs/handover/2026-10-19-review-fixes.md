# Handover: the 2026-10-19 review and its fixes

Read `AGENTS.md` first, then this, then [the review](../reviews/2026-10-19-review.md) ("For the owner,
in short" and "Second pass"). Never push; commit only when the owner asks.

## Where things stand

- **First pass, committed:** `1d4d756b` (the review file, and four high fixes with their tests: painted
  layers keep doors and gates the designer set up, flat-world fences collide, one area banner for the
  Lair).
- **Second pass, NOT committed** (the owner said: fix every high, medium and low finding with the
  review's proposals, keep the docs true, repaint the pockets one scene at a time). All of it is in
  the working tree. What was done, item by item, and what was left by design: the review's "Second
  pass" section.
- **Mixed in the same tree, uncommitted, from another session** ("Agents handover onboarding",
  2026-10-19, on the owner's requests): `player.gd` (`arrive_at`: a respawn or a stair arrival takes
  the ground's level), `stair_hatch.gd` `_arrive`, `dungeon.gd:643`, one R7 faint test in
  `test_fattys_lair.gd`; the `edge` tile of painted level collision (rim for its level, base below),
  room back faces (`room_back_faces`, 24-unit strips), decks drawn in the depth map; the level-collision
  tileset and palette; `ELEVATION.md`; R7's scene (`r7-bell-bridge.tscn`, the owner's own edits and
  that session's). Commit them together with this work or separately, as the owner prefers; the two
  sets touch some of the same files (`elevation.gd`, `hazard_deck.gd`, `test_fattys_lair.gd`,
  `dungeon.gd`, `ELEVATION.md`), so splitting them needs `git add -p`.

- **After the suite ran**, the other session went on with two changes the owner approved there:
  `hazard_watch.gd` (a slime falls when the middle of its body, not its feet, is over a hazard with
  no deck holding it) and four walls (`room_back_faces`) in r2, r3, r11, the Old Armoury and the
  Glow-Moss Burrow (one line each, `room_back_faces = true`), with those five caches rebaked; R7 stays
  the owner's. Done and compile-checked, **not tested**: the suite numbers below are from before
  them, and the centre rule may move R7's Roll tests and the plank tests a little (about 13 units for
  a north-south Roll). Run `pnpm test:godot -- "--filter=test_fattys_lair|test_falling_planks|test_dungeon_kit"`
  when the owner asks.
- **Also after the suite (other session, owner's requests, compile-checked, not tested):** in the Lair
  the HUD minimap shows only the current room, clipped to its box (`dungeon_minimap.gd`,
  `dungeon_map_draw.gd` `draw(..., only_current)`, `minimap.gd`); the M map keeps every discovered
  room and the compass's chest dots. A divider run's end post whose next cell is an interior wall or a
  WallLayer cell now gets its stub to the cell's edge, so runs reach their walls (`fences.gd`
  `_wall_beyond`; the Weigh House and R5 rendered by that session). Run `test_fences`, `test_map` and
  `test_lair_rooms` when the owner asks.

## Tests

- `tools/verify_scenes.gd`: **OK** (1376 scenes; the 46 false failures from the room shells are gone,
  M1).
- **Full suite (after every change and the cache rebake): 585 passed, 10 failed.**
  - 8 from map edits, not code (the review's "Test results" has each cause):
    `test_chapter_one_flow::test_stone_tools_by_hand`, `test_chapter_one_second_pass::test_chunk_seams_and_hidden_hearts`,
    `test_water::test_level1_surface_covers_the_water_tiles_in_draw_order`, `test_quests::test_waypoint_targets_on_level_1`,
    `test_world::test_level1_dimensions_tiles_and_spawn`, and three of `test_world_objects`.
  - **2 from the divider-gate fix (H3), the first thing to settle:** `test_fattys_lair::test_the_bell_bridge_is_played_from_its_north_door_to_r2`
    and `..._with_its_automatic_collision`. After the bell the slime walks north at x 200 and stops at
    (209.7, 504), south of R7's open gate (cell 3,7, middle x 224): the open passage is now the gate
    block's width (44 eye, 42 pen) for the 30-wide slime, so a push more than about 7 units off the
    middle stops on the rail's end (the fences helper flagged it as a decision). With keys only this
    is hard to line up. Options: Zelda's corner slide (a push into a rail end near an open gate nudges
    the slime toward the passage), or a wider passage (the rails' collision stops at the cell's edge,
    ±32, while their art stops at the block, ±22). Do not just move the test's walk to x 224.
  - Re-run with `pnpm test:godot` (about 30 minutes).
- The groups ran their own filtered tests as they finished: interior walls 17/17, fences 39/41 (then
  the two fixed), smaller pieces 37/38 (the one a transient), Lair rooms 37/37, R5 merge 39/39, Burr's
  cell 14/14, elevation 136/140 (the 4: a map test and three R7 tests since fixed by the other
  session's back-face change).
- All 71 elevation caches were rebaked after the last elevation change (`tools/bake_elevation.gd`).

## The owner's scenes that changed (reload them in the editor before any save-all)

- `game/scenes/worlds/rooms/fatty-lair/`: every room scene except R7 (cleaned: grid metadata, empty
  tile entries, old shell metadata, `interior-walls` no longer saved disabled, unused resources);
  `r5-eye-hall.tscn` (R5 is one world again: the eye hall, lower hall and key alcove behind their
  dividers), `r3-pit-hall.tscn` (Burr's cell is rock behind the hub's faces, the two-key door in the
  face, the pit's west edge two columns east on rows 4-8), `burr-cell.tscn` (a full 6 x 9 box),
  `r1-gatehouse`, `r1-store`, `r11-drop-gate-bridge`, `layout.tscn`.
- **Deleted:** `r5-lower-hall.tscn`, `r5-key-alcove.tscn`, `written.json` (close the two scenes if
  open in the editor).
- `game/scenes/worlds/chunks/level-1-c4.tscn` (the bell's pots are clay pots again; a stray fence cell
  at (-1, 29) erased).
- `game/scenes/objects/dungeon/divider-gate.tscn` (the prefab).
- Originals of every scene: git `HEAD` (`git show HEAD:<path>`).
- Pictures for the owner: `output/review-fixes/` (r5, burr-cell, fences, h1-corners, hollow).

## Waiting for the owner (each in the review's "Second pass")

- H1 (room corners round in the collision): explained with an example and pictures; fixing it (corner
  radii and wobble 0 for interior styles) is his call.
- The choices made for him: the far side of a bolted door shows the shutter's plain slab; heart, then
  ceremony, then the chest window; the coins picture; camera rooms down to one cell; `paint_to_nodes
  --group` puts big props straight under `Scenery`; divider gates (passage the block's width, the pen
  folding behind the west rail, R7's and R5's alcove stub posts); refusal times in game-constants.
- Not done by design: the music's 15 ms fade-in on the game's loops; the storehouse's pots coming back
  (proposal: `for_good` on PotLoot); the gate art's depth cut-out; the Hollow's two `wall_bands` rooms.
- R7's paint: the landing's north edge is a level -1 base, so after the north slabs fall the slime
  falls straight in walking north off the landing; repaint it as an `edge`.
- The map-edit test failures: are the new positions and seams intended? Then update the tests'
  numbers; else move things back.
- Commit: the second pass and the other session's work (see above). The editor made `.gd.uid` files
  for `test_camera_rooms.gd`, `test_paint_to_nodes.gd`, `render_divider_gates.gd`: commit them with
  their scripts.

## Left behind on purpose

- `godot/output/merge_r5.gd` (the one-off that merged R5's three scenes) and
  `godot/output/probe_r7_arrival.gd` (a headless probe of R7's arrival walk-out): git-ignored, delete
  them when no longer useful.
- `tools/build_fattys_lair.gd` is now a stub that refuses to run; its old builder is in git history
  (`git show 0a6b9954:godot/tools/build_fattys_lair.gd`).
