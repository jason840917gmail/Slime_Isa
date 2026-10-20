# Session summary, 2026-10-17 to 2026-10-19 (for the next agent)

Read `AGENTS.md` first, then this, then the docs linked below. Everything here is committed locally on
`main` (last: the commit that added this file); **nothing is pushed** (never push unless the owner asks).
The owner writes in Spanish and English; answer in the language he uses.

## How the owner works (keep to these)

- **Editor first:** he edits by painting, dragging and setting fields in the Inspector, with live editor
  previews. Content lives in hand-edited scenes; code makes tools and behaviours, never levels. Never
  regenerate a scene he edits; a one-off script that touches his scene needs a backup first and the
  smallest change.
- **Reuse what works:** rooms run the outdoor code for drops, slabs, collision and hazards. No per-room
  special cases; fixes must be general procedures.
- **Pictures first:** he judges by renders and in-game captures; mock up before building anything visual.
- **Commit only when asked; never push. Tests only when asked** (or once after a big breaking change).
- His Godot editor is often open: no headless `--import` then, and tell him which scenes to reload before
  he saves (an open editor writes its old copies back). Check with `tasklist` for
  `Godot_v4.7.2-stable_win64.exe`.
- No godot-ai MCP tools. Magnific: GPT 2.5 (`gpt-2-mini`), `transparentBackground: true`, style reference
  the Lili creation `XmsSFu2Bfo`; tell him the credits.
- Design rules he set: hearts hide (at most one in sight per map; "coffers" are chests); worms look
  mean; he plays with keys only; the playground grows sideways only.

## What was built (and where it is described)

| Area | State | Read |
|---|---|---|
| **Pearl inside each dungeon** (taken before the boss; the boss seals the exits; the skin is taught in the second half) | Built in all three dungeons | `docs/design/2026-10-17-pearl-mid-dungeon.md`, `docs/godot/DUNGEONS.md` "The seal", open questions 141-145 in `docs/story/06-open-questions.md` |
| **Skins** (Heavy, Silk, Feral: always on once won; the look shows only while a skin works) | Built | `docs/godot/SKINS.md` |
| **Fatty's Lair, one world per room** (Zelda: each room loads on entry; doors name a target room and door in the Inspector; screen scroll, or `transition = iris` for closets like R1's store; cross-room links are records; the map is a draggable layout scene; enemies reset; the seal's glimpse is a still picture) | Built; the old shell and the Lair builder's write path are retired | `docs/godot/DUNGEON_ROOMS.md`, `docs/design/2026-10-18-lair-rooms-as-worlds.md` |
| **Interior walls** (Zelda bevel frame, two cells deep, three styles: fort stone, cave rock, root rock, with plain floors; every door kind cut into its face, the north piece turned for each side; doors painted from a picture palette and made automatically; door frames drawn over bodies in doorways; paired doors via `link_id`) | Built | `docs/godot/INTERIOR_WALLS.md` |
| **Levels in rooms** (level edges drawn as the room's own wall faces, one cell per level; slabs and decks over them; one hazard per floor level, hurting only on its level, drawn under the upper floors; objects react only on their own level) | Built; R7 has an end-to-end test | `docs/godot/ELEVATION.md` "Faces in rooms" |
| **Painted level collision** (`level-collision` layer: orange rims that hold and drop, red bases that block, per level; replaces the automatic collision where painted; "Fill from the automatic collision" button) | Built | `docs/godot/ELEVATION.md` "Painting collision" |
| **Dungeon dividers** (low pillar dividers on the `fences` layer; eye block for secret/latch passages, pen gate for switch/key ones) replacing the latch doors in R5, R7, C2 and the Old Armoury | Built (fort stone only; cave and root styles still to make) | `docs/godot/FENCES.md` "Dungeon dividers" |
| **Unified fences** (one painted concept in `game/world/fences/`, thin collision, two-post single tiles) | Built | `docs/godot/FENCES.md`, `docs/reviews/2026-10-17-fences-review.md` |
| **Chapter 1 second map pass** (C4 plateau, river on the C4/D4 border, bigger lake and island, falling-plank bridge, caves, hidden heart chests; C4's props as grouped nodes; the first bell fixed) | Built | `docs/story/chapters/chapter-1-the-clearing.md`, `docs/handover/2026-10-17-chapter1-second-pass.md` |
| **Falling planks and the goo heart in a chest** | Built | `docs/handover/2026-10-17-kit-planks-heart-chest.md` |
| **Music** (dungeon, boss, two cave and two interior loops from Magnific/Lyria; loops cut by `scripts/audio/make-music-loop.py`; the same track carries on between floors) | Built | `docs/godot/specs/audio.md`, `docs/TOOLING.md` |
| **Editor tools**: camera room drag handles (`addons/camera_room_handles/`, enable it in Project Settings > Plugins), Scenery dock's Enemies category, `tools/paint_to_nodes.gd --group` | Built | `docs/godot/DUNGEON_ROOMS.md`, `docs/godot/PROPS.md` |
| Bolt-hole hatch slams shut behind the slime; D5's moat holes return the slime to one safe spot (`fixed_return`); F6 in the Lair lends the Heavy skin | Built | `docs/godot/DUNGEONS.md`, `docs/godot/CONVENTIONS.md` |

## Open, waiting on the owner or not done

- **Tests failing from map edits, not code:** `test_chapter_one_flow`, `test_world_objects`, `test_quests`,
  `test_world` (C4/D5 positions and ground moved in the editor). Ask him whether the new positions are
  intended; then update the tests or move the things back.
- **The review ran and its fixes are in:** `docs/reviews/2026-10-19-review.md` (first pass committed,
  1d4d756b; the second pass uncommitted: [2026-10-19-review-fixes.md](2026-10-19-review-fixes.md)).
- **Not built:** hazards that fill a painted hole by themselves; level faces taller than one level, and
  doors or chests set into a level face; cave and root divider styles; the drop's one-frame "ghost" on
  landing (outdoor occlusion, check in play); the energy flower refilling on each room entry, Burr's cell
  as its own world, the stairs' fade, the quest arrow (open points in the rooms-as-worlds doc).
- **The Weaver Hollow and the Crystal Mine** still use the old one-scene model and cliff walls; convert
  them the Lair's way when he asks.
- **The owner has not played most of this yet**: expect feedback from a playthrough.

## Useful paths

- Godot console exe: `C:\Users\User\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.
- Agents' review renders and scratch live in `output/` and `godot/output/` (ignored by git).
- A test lock convention for parallel agents: create the session scratchpad's `test.lock` with your name
  before `pnpm test:godot`, delete it after.
