# Documentation

Project notes for Slime Isa. The agent/developer quick reference (commands,
structure, rules) is [`AGENTS.md`](../AGENTS.md) at the repository root.

## Top-level docs

- [GAME_GUIDELINES.md](GAME_GUIDELINES.md) — agreed game design direction (living draft).
- [GAME_ROADMAP.md](GAME_ROADMAP.md) — the road to Release 1: ordered milestones, task status, needed assets, and the post-release idea parking lot.
- [GODOT_MIGRATION.md](GODOT_MIGRATION.md) — the move from Phaser to Godot 4.7 (done 2026-10-05): decisions, what carried over, the phases and the cutover.
- [TOOLING.md](TOOLING.md) — the art, audio and test tools in `scripts/` and what they read and write.
- [CREDITS.md](CREDITS.md) — where every asset, font and library comes from, with licences.

## Folders

- [godot/](godot/CONVENTIONS.md) — how the game is built: [conventions](godot/CONVENTIONS.md), [architecture](godot/ARCHITECTURE.md), the [terrain edges](godot/TERRAIN_LAB.md), the [UI theme](godot/UI_THEME.md), and [specs/](godot/specs) recording the exact behaviour each area reproduces (they cite the Phaser sources, `src/...`, which are in git history before the cutover).
- [assets/](assets/README.md) — creating and packing art. Start here for any new media.
- [story/](story/README.md) — the story script (draft): direction, premise, world, characters, chapter beats, the unlock map, and open questions.
- [design/](design/) — engine-neutral design notes (the Chapter 2 outline, the Orb-Weaver Matron).
- `task/ideas/` — open idea notes.
- [archive/phaser/](archive/phaser/) — the Phaser-era docs (architecture, authored maps, terrain blending, Scene Studio plans and specs, fixed bugs). Historical: they describe code that was removed at the cutover.

## Asset size quick reference

Measured from the runtime art in `godot/asset/`:

- World tile: `64 x 64` world units. Ground materials are `1216 x 1216` sheets (`19 x 19` tiles of 64 px) in `godot/asset/MAPS/grounds/`; new art is made at 128 px per 64-unit cell ([godot/TERRAIN_LAB.md](godot/TERRAIN_LAB.md)).
- Player slime: `2048 x 2048` sheets, `8 x 8` grid of `256 x 256` frames (`godot/asset/characters/256x256-tile_8x8-slime-v2-page-*.webp`).
- NPC sheets: `6 x 5` grid of `229 x 229` frames. Worm/spider enemies: `64 x 64` frames.
- Trees: `128 x 170` frames; rocks and props: `96`, `128`, or `256 px` square frames; houses: `320 x 320` frames.
- Item icons: `64 x 64` frames in `5 x 2` (or `5 x 4`) sheets.
- Interior furniture: `128`, `192`, or `256 px` square frames.

These are current conventions, not hard limits: every object scene sets its own
scale, offset, collision shape and draw order, so a new size only needs a
matching scene.
