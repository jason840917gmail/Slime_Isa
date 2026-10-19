# Review prompt (2026-10-19)

A prompt for an agent that checks and verifies the work of 2026-10-17 to 2026-10-19, looking for bugs,
for ways to make it simpler, faster or easier to use, and for improvements, without breaking the core
mechanics. Paste it as the agent's task.

---

You are reviewing recent work on Slime Isa (Godot 4.7.2, repo `D:/projects/Slime isa`, project `godot/`,
branch `main`). Read `AGENTS.md`, `docs/godot/CONVENTIONS.md`, `docs/godot/ARCHITECTURE.md` and
`docs/handover/README.md` first.

## What to review

The commits after `48a7b514` (`git log --oneline 48a7b514..HEAD`): `2a04028b` (a mixed snapshot),
`442dd8b2` (unified fences, C4's props as nodes, the first bell, D5's moat safe spot) and `0a6b9954`
(Fatty's Lair as one world per room, bevel interior walls, dungeon music, painted level collision,
dividers). The areas, with their docs:

- **Fatty's Lair, one world per room:** `docs/godot/DUNGEON_ROOMS.md`, `docs/design/2026-10-18-lair-rooms-as-worlds.md`;
  `game/dungeon/room_door.gd`, `room_travel.gd`, `dungeon_layout.gd`, `layout_room.gd`, `seal_moment.gd`,
  `main.gd` (`travel_through_room_door`, the iris option), `game/scenes/worlds/rooms/fatty-lair/`.
- **Interior walls (Zelda bevel, two cells deep, three styles):** `docs/godot/INTERIOR_WALLS.md`;
  `game/world/interior/`, the door objects' `frame_drawn_by_wall`, `scripts/art/pack-interior-walls.py`.
- **Levels in rooms:** `docs/godot/ELEVATION.md` ("Faces in rooms", "Painting collision");
  `game/world/elevation/room_faces.gd`, `level_collision_layer.gd`, `elevation.gd`; the kit's level checks
  (`game/dungeon/hazard.gd`, `hazard_watch.gd`, `hazard_deck.gd`, `falling_slab.gd`, `dungeon_state.gd`).
- **Fences and dividers:** `docs/godot/FENCES.md`, `docs/reviews/2026-10-17-fences-review.md`;
  `game/world/fences/`, `game/dungeon/divider_gate.gd`.
- **Smaller pieces:** the falling planks and goo heart in a chest (`docs/handover/2026-10-17-kit-planks-heart-chest.md`),
  the camera room handles (`addons/camera_room_handles/`), the music (`docs/godot/specs/audio.md`,
  `game/audio/music_director.gd`, `scripts/audio/make-music-loop.py`), the bolt-hole hatch
  (`game/fattys_lair/bolt_hole_hatch.gd`), the skins' look rule (`docs/godot/SKINS.md`), `tools/paint_to_nodes.gd --group`.

## The owner's directives (never break them)

- **Editor first:** everything the designer does is painted, dragged or set in the Inspector, with a live
  preview in the editor. Content lives in hand-edited scenes; code builds tools and behaviours, never
  levels. Never regenerate a scene he edits (the Lair builder and the splitter are retired for the Lair).
- **Reuse what works:** dungeon rooms run the same code paths as the outdoor world for ledge drops,
  falling slabs, elevation collision and hazards; only the wall drawing differs. No per-room special
  cases (by node name, position or room id): procedures that work anywhere.
- **Zelda rules:** doors always sit on a room's edge and are part of the wall's art; rooms may be bigger
  than a screen and any shape; every wall is a bevel face facing into the room; each door is the north
  piece turned for its side; divisions inside a room are low dividers with an eye block (secret or latch)
  or a pen gate (switch or key), never walls with doors; level changes inside rooms are drawn as the
  room's own wall faces; one hazard per floor level, hurting only on its level, drawn under the upper floors.
- **Hearts hide** (at most one in plain sight per map). Worms look mean. The owner plays with keys only.
- **Project rules** (AGENTS.md): static typing, `Services`, `ArcadeMover`, values from `game-constants.json`,
  one gameplay clock, docs kept truthful.

## How to review

1. **Verify the claims.** For each area, read the code and the doc, and check that the doc describes
   what the code does. Load the scenes headless and confirm they build without errors
   (`tools/verify_scenes.gd`, after checking that no Godot editor is open; if one is, ask before running anything).
2. **Look for bugs**, by priority: crashes and script errors; save/load and record bugs (a chest, key,
   door, barricade, plate, crack, seal, Pearl or boss state lost or duplicated across room travel or a
   reload); travel bugs (a room door arriving in the wrong place, scrolling into a wall, the iris and the
   scroll mixed up); collision that disagrees with the drawing; objects reacting on the wrong level;
   things that only work in one room; editor tools that lose or overwrite the designer's paint; leftovers
   of the retired shell and old door art still referenced.
3. **Look for simpler or faster ways:** duplicated logic between the outdoor and room paths, dead code
   left by the reworks (the shell, `doorway_art.gd`, the room mask's frame exception, the old latch door,
   the builder), slow per-frame work, editor rebuilds that redo too much, test helpers that could be shared.
4. **Look for ways to make it easier to use in the editor:** steps a designer must remember that a tool
   could do, Inspector fields that could be lists, missing editor previews or warnings (a room door with
   a bad target already turns red: what else should?), docs a newcomer could not follow.
5. **Tests:** read the new tests (`test_lair_rooms`, `test_level_collision`, `test_interior_walls`, the R7
   end-to-end test in `test_fattys_lair`) and say what they miss. Then run, once, the full suite
   (`pnpm test:godot`, about ten minutes) and report every failure with its cause. Four were known to fail
   from map edits (C4/D5 positions and ground): `test_chapter_one_flow`, `test_world_objects`,
   `test_quests`, `test_world`; say whether that is still the only cause.

## Rules for you

- **Review first, fix second.** Write your findings to `docs/reviews/2026-10-19-review.md`: each with
  severity (high / medium / low), where it is (file and line), what goes wrong, how to reproduce it, and
  the fix you propose. Then fix only the **high** ones that are clearly bugs and safe, each as a small,
  general change (never a patch for one room), with a test that would have caught it. List the medium
  and low ones, and every improvement, for the owner to choose; do not build them.
- **Never edit the owner's scenes** (`game/scenes/worlds/rooms/`, the chunks, the caves) unless a high bug
  can only be fixed there; then back the file up first and make the smallest edit. Never run a builder
  that rewrites them.
- Do not use the godot-ai MCP tools. Do not commit or push; the owner decides. If a Godot editor is
  open, no headless `--import`, and list every scene you change so he can reload it.
- Keep docs truthful: if you change behaviour, update the doc in the same change.

## Report

A short summary for the owner (in plain words: what works, what was broken and is fixed, what still
needs his decision), the path of the review file, the test results, and the list of files you changed.
