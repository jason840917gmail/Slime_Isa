# Handover (2026-10-17)

> **Throw combat:** the `exp/throw-combat` branch was merged into `main` on 2026-11-01 and its worktree (`D:/projects/Slime isa-throw`) deleted; [its handover, 2026-10-23](2026-10-23-throw-combat.md) is the record (the owner's rules for throw combat still hold).
>
> **Start here instead: [2026-10-19 session summary](2026-10-19-session-summary.md)** (the current state, the owner's rules, what is open). The rest of this file is the 2026-10-17 record.
>
> **Then: [the review's fixes, 2026-10-19](2026-10-19-review-fixes.md)** (the second pass of the review, uncommitted: what changed, the scenes to reload, the tests, what waits for the owner).
>
> **For review: [the Heavy grab's poses, text and hint, 2026-10-19](2026-10-19-heavy-grab.md)** (uncommitted: push and pull poses on slime page 7, the Heavy skin's texts naming W, the touch hint; what to check).

Work in flight when the owner's credits ran out. Start with the roadmap's
"Immediate Next Sprint" → "Where things stand (2026-10-17)"
([GAME_ROADMAP.md](../GAME_ROADMAP.md)), then the files below.

## State

- Committed locally on `main`, **not pushed**: 7973880e, 53e5df74, 48a7b514 (the bestiary, the
  prologue, the three dungeons and their kit, the skins, the Pearl inside the dungeon, Chapter 1's
  first map pass). Never push unless the owner asks.
- **Uncommitted:** the docs below; the owner's editor's `.import` and `.gd.uid` files for the last
  commit's new assets and scripts (commit them); and three unfinished pieces of work:

| Work | Handover | State |
|---|---|---|
| Falling planks over water (a long bridge crossed only by a continuous Roll, a come-back secret) and a goo heart inside a chest | [2026-10-17-kit-planks-heart-chest.md](2026-10-17-kit-planks-heart-chest.md) | Built and verified; placed in C5; dev world `?map=playground-planks` remains available |
| Chapter 1's second map pass: C4's fenced level-1 plateau (stairs north and south, a few gaps to jump down, fence only along the river and the lake), the river moved onto the C4/D4 border (crossing it is crossing chunks; banks must show their normal water edges), the bigger lake with an island, the long falling-plank bridge, enemies, a cracked wall (Goo Bomb) into a new cave room of chests and pots (a secret goes there later); hearts hidden in chests (D5's pocket closed into a cave room, D4's pen, D4's plateau) | [2026-10-17-chapter1-second-pass.md](2026-10-17-chapter1-second-pass.md) | Built: chunks, caves, hidden heart chests and caches; targeted gameplay and seam checks passed |
| Doors that belong to the wall, and doors always at a room's edge | [../design/2026-10-17-doorways-in-walls.md](../design/2026-10-17-doorways-in-walls.md) | Built after owner chose separate room scenes and two-cell arches: 60 room scenes, wall frames and room darkness; owner review remains |

**Next for doors (owner, 2026-10-17):** a new interior wall script where all four walls show, Zelda's
box room, with doors as pieces of each side (a south door part of the south wall): see the doors
plan's last section and the reference sheet in `asset/Originals/dungeon-kit/doorways/reference/`.

## The owner's rules from this session (also in the guides)

- **Hearts hide** (level design guide, rule 3): at most one heart in plain sight per map; the rest
  in chests, caves or odd corners. "Coffers" means chests.
- **Doors** (owner, 2026-10-17): a door is part of the wall's art (lintel, jambs, the wall's own
  stone; cracks and blown holes are wall pieces), and a door always sits at the edge of its room,
  where the room's camera area ends, so going through scrolls to the next room and nothing behind
  a door is seen. Rooms may be bigger than a screen and any shape. He says the edge rule fixes 90%
  of the problem; matching door art is the rest.
- Unanswered, built with my defaults: the camp's bridge east of the starter camp is removed (the
  plateau's river edge is all fence).

## Working rules

`AGENTS.md`; plus: commit only when asked, never push; tests only when asked (or once after a big
breaking change); the owner's Godot editor is usually open (no headless `--import`, list scenes to
reload); no godot-ai MCP tools; show pictures early; Magnific GPT 2.5 (`gpt-2-mini`),
`transparentBackground: true`, style reference the Lili creation `XmsSFu2Bfo`, report credits;
worms look mean; the playground grows sideways; the owner plays with keys only.


## Continuation (2026-10-17)

The second-pass builder has been applied: the four chunks, two cave scenes, both cave
mouth mappings, 12 east-west falling planks, hidden heart chests, world-map markers and
elevation caches are on disk. Plop fades back to his saved village position after the meeting.
The HP text from a chest waits for its heart to rise. No commits or pushes.
Review renders: `output/chapter1-review/`. Doorway composites: `output/doorway-review/`;
no new generation credits. Door/camera changes use 60 separate editable room scenes, assembled in a shared dungeon shell to preserve puzzles and saves. See [DUNGEON_ROOMS.md](../godot/DUNGEON_ROOMS.md).
Targeted regression work is recorded in `output/chapter1-review/*.log`; see the continuation
report there for the final results. The final dungeon regression passed 12/12 checks. Reload the four changed chunks and any open cave scene
and the six dungeon shells/any open room scenes in Godot before saving them.


## Fatty's Lair: one world per room (2026-10-18)

The owner decided (and approved the build, then left): every room of Fatty's Lair is its own world,
the Zelda way. Built, uncommitted:
[DUNGEON_ROOMS.md](../godot/DUNGEON_ROOMS.md#fattys-lair-one-world-per-room-2026-10-18) (how it works and
how to edit it), [the plan with every link between rooms](../design/2026-10-18-lair-rooms-as-worlds.md).

- The 24 room scenes are the worlds (R1 is `fatty-lair`, the rest `fatty-lair-<room>`); the shell
  `game/scenes/worlds/fatty-lair.tscn` and its elevation cache are deleted (backups of every touched
  scene and test: the session's scratchpad, `rooms-worlds/`).
- Room doors (`object.room-door`, 54, in 27 pairs) are set in the Inspector (target room and door
  from lists, red in the editor when wrong); the screen scrolls through them.
- Records instead of links: the kit's records under `fatty-lair`; a session record for R10's plate
  and R9's door; a flag for the map nook's gap (new).
- The map is `rooms/fatty-lair/layout.tscn`, dragged in the editor; the take's glimpse is a picture
  of R1's seal (`tools/capture_lair_seal.gd`).
- **Reload in the editor before any save-all**: all 24 room scenes of `rooms/fatty-lair/`, and close
  `fatty-lair.tscn` if it is open (it no longer exists).
- Left for the owner: a playthrough (the scroll's look, the pockets' walls: the lower hall, the
  alcove and Burr's cell got copies of the rim they shared), and the doc's open questions
  (Burr's cell as its own world, the stairs' fade, the energy flower, the quest arrow).

C4 follow-up: the oversized standalone stone doorway and exposed watch-post chest are now a
keeper's timber storehouse with a separate furnished interior (`watchkeeper-hideout`). The
original bell unlock and chest save records are retained. The shared latch-door prefab and
five Lair room overrides now use the wall kit in the editor too. See `docs/TOOLING.md`.

