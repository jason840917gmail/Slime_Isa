# Documentation

Project notes for Slime Isa. The agent/developer quick reference (commands,
structure, rules) is [`AGENTS.md`](../AGENTS.md) at the repository root.

## Top-level docs

- [ARCHITECTURE.md](./ARCHITECTURE.md) — dependency direction, feature/scene ownership rules, the universal scene tree, Scene Studio, and authored maps.
- [AUTHORED_MAPS.md](./AUTHORED_MAPS.md) — authored worlds: world scenes, map JSON, areas, exits, and spawns.
- [TOOLING.md](./TOOLING.md) — what each `pnpm` script and generator/pack tool touches.
- [TERRAIN_TRANSITIONS.md](./TERRAIN_TRANSITIONS.md) — how logical terrain tiles are blended into organic regions.
- [TERRAIN_BLEND_MATH.md](./TERRAIN_BLEND_MATH.md) — the blend formulas step by step, with a pipeline diagram and an interactive playground (`terrain-blend/playground.html`).
- [camera-and-minimap-guide.md](./camera-and-minimap-guide.md) — responsive camera, zoom, and minimap.
- [GAME_GUIDELINES.md](./GAME_GUIDELINES.md) — agreed game design direction (living draft).
- [GAME_ROADMAP.md](./GAME_ROADMAP.md) — the road to Release 1: ordered milestones, task status, needed assets, and the post-release idea parking lot.

## Folders

- [assets/](./assets/README.md) — creating, packing, registering, and integrating art. Start here for any new media.
- [knowledge/](./knowledge/README.md) — focused how-to notes (quest authoring).
- [story/](./story/README.md) — the story script (draft): direction, premise, world, characters, chapter beats, the unlock map, and open questions.
- `superpowers/` — dated historical specs and implementation plans. Not maintained; may describe retired systems.
- `task/` — bug reports (`task/bugs/`) and idea/plan notes (`task/ideas/`).

## Asset size quick reference

Measured from `asset/assets.json` and the files on disk:

- World tile: `64 x 64 px`. Ground materials are `1216 x 1216` sheets (`19 x 19` tiles of 64 px) in `asset/MAPS/grounds/`.
- Player slime: `2048 x 2048` sheet, `8 x 8` grid of `256 x 256` frames, drawn at scale `0.28125` in its character scene.
- NPC sheets: `6 x 5` grid of `229 x 229` frames. Worm/spider enemies: `64 x 64` frames.
- Trees: `128 x 170` frames; rocks and props: `96`, `128`, or `256 px` square frames; houses: `320 x 320` frames.
- Item icons: `64 x 64` frames in `5 x 2` (or `5 x 4`) sheets.
- Interior furniture: `128`, `192`, or `256 px` square frames.

These are current conventions, not hard limits: every object scene sets its own
scale, origin, collision shape, and depth bounds, so a new size only needs a
matching manifest entry and scene.
