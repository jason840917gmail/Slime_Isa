# Slime Isa — Agent Guide

Top-down open-world slime game in **Godot 4.7.2** with statically typed GDScript, Compatibility
renderer (WebGL 2), exported to the web first. The project is `godot/`. pnpm runs the test runner and
a few art tools; Python tools need Pillow (several also numpy).

The game was ported from a Phaser 3 + TypeScript app, which was removed on 2026-10-05 (the cutover in
[docs/GODOT_MIGRATION.md](docs/GODOT_MIGRATION.md)); its docs are in `docs/archive/phaser/` and
its code is in git history.

## Working Rules

- Work on the current branch. Do not create new branches unless the user asks for one.
- Do not run tests after every change — it wastes compute and time. Run `pnpm test:godot`,
  `tools/verify_scenes.gd` or a web export only when the user asks, or once after a really big,
  breaking change. A `--check-only` compile of an edited script is fine.
- Scenes, data and art are edited in the Godot project. An open Godot editor holds its own copy of
  every open scene: a "save all" there writes it back over files changed on disk, so reload changed
  scenes in the editor (or close them) before saving.
- Avoid headless `--import` runs while someone has the editor open (they share the import cache).
- Commit the `*.import` and `*.gd.uid` files Godot creates next to assets and scripts.
- Keep docs truthful: when you change behavior, paths, or commands, update the doc that describes
  them in the same change.
- Delete your screenshots when you are done (owner, 2026-11-24). A film's or render's frame
  pictures (`output/<area>/<name>/f000.png` ..., any screenshot taken to check your work) go once
  you have looked at them and before you report: a film's frames are 300 to 900 pictures, and
  11 GB of them had piled up. Keep only what is shown to the owner or tells what the film found:
  the strip, the GIFs, `film.json`. The same for review sheets and scratch pictures you made.

## Commands

- Godot editor: open `godot/` in Godot 4.7.2; `scripts\godot\open-editor.cmd` opens it with a log
  file, so a crash leaves Godot's crash report behind (the editor logs nothing otherwise:
  [When the editor crashes](docs/godot/CONVENTIONS.md#when-the-editor-crashes)). F5 runs the title screen; `game/dev/playground.tscn`
  with F6 runs the playground testbed (every weapon and ability); F6 on a world scene runs the game
  in that world.
- Launch options: `?map=<world id>`, `?spawn=<x>,<y>`, `?weapon=<id>`, `?quest=<id>[:<stage>]`,
  `?recipes`, `?arsenal`, `?audition`, `?shapes` (lends the shapes and box abilities in any world;
  the body-shapes rework mode itself is on in every world on this branch), `?prologue` (a new
  run in the prologue, as New Game starts it), `?skins=heavy,silk,feral` (lends those skins for the
  session), `?melee` (the throw combat off: the
  shapes' attack back), `?gulp=<1..3>` (the Gulp's level) and `?aimhelp` on the web;
  `-- --map=<id> ...`, `-- --shapes`, `-- --prologue`, `-- --skins=<ids>` on desktop
  ([docs/godot/CONVENTIONS.md](docs/godot/CONVENTIONS.md#running-a-world);
  the rework: [docs/godot/BODY_SHAPES.md](docs/godot/BODY_SHAPES.md); the throw-combat experiment:
  [docs/godot/THROW_COMBAT.md](docs/godot/THROW_COMBAT.md); the prologue:
  [docs/godot/PROLOGUE.md](docs/godot/PROLOGUE.md); the skins: [docs/godot/SKINS.md](docs/godot/SKINS.md)).
- Dev powers board: **F10** in any world run from the project lists every shape, ability and skin
  and switches each on or off for the session (never saved; not in the production web export:
  [The powers board](docs/godot/CONVENTIONS.md#the-powers-board)).
- `pnpm test:godot [-- --filter=<text>]` — the headless integration tests in `godot/tests/`
  (about an hour for the full suite: 53 minutes for 611 tests on 2026-11-20).
- `"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/verify_scenes.gd` — loads every
  scene in `godot/game/scenes/scene_index.json` and plays level-1.
- `"<Godot console exe>" --headless --path godot -s res://tools/bake_elevation.gd` — bakes every
  world's elevation cache (`game/scenes/worlds/elevation_cache/`, commit it); a game run from the
  project rebakes a world whose painting changed ([docs/godot/ELEVATION.md](docs/godot/ELEVATION.md#baked-cache)).
- `"<Godot console exe>" --headless --path godot -s res://tools/check_crossings.gd` — lists every
  crossing between worlds (doors, stairs, holes, landings, exits) and what is wrong with its link;
  every kind can be tried on the playground's crossings corner
  ([docs/design/2026-10-31-crossings-and-arrivals.md](docs/design/2026-10-31-crossings-and-arrivals.md)).
- `"<Godot console exe>" --headless --path godot -s res://tools/check_chunk_lines.gd [-- --world=<text>]`
  — lists the crossings on every line two chunk worlds share and flags the ones the chunk-line rule
  forbids ([docs/godot/WORLD_ATLAS.md](docs/godot/WORLD_ATLAS.md#chunk-worlds-2026-10-12)).
- `"<Godot console exe>" --headless --path godot -s res://tools/check_cliff_joints.gd [-- --world=<text>] [--all]`
  — lists the joints between levels that keep the plain join instead of folding (45° edges against
  another level's wall, runs too short to fold), by world and cell, for repainting
  ([The joint folds](docs/godot/ELEVATION.md#side-walls)).
- `bash scripts/godot/film-throw.sh <name> [options]` — films one Gulp throw in the playground frame
  by frame (windowed, one film at a time) and lays it out as a strip and GIFs in
  `output/throw-feel/<name>/`, to judge the throw's feel
  ([Filming a throw](docs/godot/THROW_COMBAT.md#filming-a-throw)).
- `bash scripts/godot/film-enemy-ways.sh <name> --film=<film> [options]` — films the Dung Roller's
  stolen ball (`axis`, `steal`, `throw-miss`, `throw-back`, `throw-other`, `leave`, `pen`) or an
  enemy's walk home (`home-wall`, `home-notice`) in the playground into `output/enemy-ways/<name>/`
  ([Dung Roller](docs/godot/BESTIARY.md#13-dung-roller-patroller),
  "Getting home" in [docs/godot/specs/enemy.md](docs/godot/specs/enemy.md) §4.3); with
  `--tool=film_worm_bulwark` the Worm Bulwark's charge (`dodge`, `bowl`, `wall`, `front`, `pen`)
  ([Worm Bulwark](docs/godot/BESTIARY.md#37-worm-bulwark-charger)), with
  `--tool=film_carnivore_plant` the Carnivore Plant (`bite`, `eat`, `doze`, `fire`, `feed`)
  ([Carnivore Plant](docs/godot/BESTIARY.md#38-carnivore-plant-ambusher)), with
  `--tool=film_jelly_bouncer` the Jelly Bouncer (`zap`, `throw`, `catch`, `spear`, `arrows`)
  ([Jelly Bouncer](docs/godot/BESTIARY.md#39-jelly-bouncer-shocker)).
- `bash scripts/godot/film-mechanisms.sh <name> --film=<film> [options]` — films the dungeon mechanisms
  in their lab (`world.mechanism-lab`) into `output/mechanisms/<name>/`: `ram-arch`, `ram-enemies`,
  `ram-slime`, `ram-south`, `ram-west`, `target-refuse`, `target-arrow`, `target-blast`, `target-roll`,
  `arch-refuse`, `gate-refuse`, `cart-gate`, `cart-enemy`, `cart-return`, `cart-hook`, `look`
  ([Mechanisms](docs/godot/DUNGEONS.md#mechanisms-the-knock-target-the-ram-the-runaway-cart)).
- `bash scripts/godot/film-matron.sh <name> --film=<film> [options]` — films the Orb-Weaver Matron's
  ram fight (the rework) in her lab (`world.matron-lab`, built by `tools/build_matron_lab.gd`) into
  `output/boss-rework/matron-films/<name>/`: `round1`, `dive`, `ram-catch`, `ring`, `round3`,
  `ram-call`, `look` ([matron spec §9](docs/godot/specs/matron.md#9-the-ram-fight-the-rework-built-2026-11-24-in-a-lab-not-yet-in-the-hollow));
  with `--tool=film_crown` the same films in the rebuilt Weaver Hollow's Crown (C2, the lab's arena in
  the room) into `output/dungeon-rework/hollow/crown-films/<name>/`, round1, ram-catch and round3 with
  a PASS or FAIL ([The Crown](docs/godot/DUNGEONS.md#the-crown-step-3s-third-piece-2026-11-25)).
- `bash scripts/godot/film-colossus.sh <name> --film=<film> [options]` — films the Crystal Colossus's
  plate fight (the rework) in his lab (`world.colossus-lab`, built by `tools/build_colossus_lab.gd`)
  into `output/boss-rework/colossus-films/<name>/`: `look`, `poses`, `walks`, `glow`, `burst`, `clang`,
  `pass`, `dip`, `bare`, `wall`, `core` ([The Colossus lab](docs/godot/DUNGEONS.md#the-colossus-lab)).
- `"<Godot console exe>" --path godot -s res://tools/film_weaver_hollow_rooms.gd -- --film=<walk|ram|wall-walk|warden-ram|webbed-slab|look> --out=<dir>`
  — plays the rebuilt Weaver Hollow (step 3 of the dungeons rework; the game enters it since the
  switch-over of 2026-11-25, today's four worlds unreached until step 5;
  `?map=weaver-hollow-t1-root-door`) the designed way, windowed: `walk` checks every step from the
  forecourt (a Goo Bomb on the root gate) through T1, the Trunk, the Roots, the Boughs and the Crown
  (her fight ended by the tool, a faint and the way back up) to C3's drop, in through the gate again
  and out by T1's way out (`--from=boughs`: from the hub's south door,
  `--from=crown`: from the Crown Door; PASS or FAIL, a picture a step), the others film R3's lesson, the wall-walk, the Warden and the ram,
  B2's webbed slabs, or take a still of a room in the game (`look --world=<room> --at=<x>,<y> --zoom=<z> [--slime=<x>,<y>]`);
  its rooms' first versions came from `tools/build_weaver_hollow_rooms.gd` (refuses to overwrite a
  hand-edited room without `--force`)
  ([The Weaver Hollow rebuilt](docs/godot/DUNGEONS.md#the-weaver-hollow-rebuilt-the-trunk-and-the-roots-step-3-2026-11-25)).
- Web build: `"<Godot console exe>" --headless --path godot --export-release "Web" export/web/index.html`
  (the "Web (dev)" preset keeps the dev worlds); `.claude/launch.json` "godot-web" serves it on port 3200.
- World map: `pnpm story:map` sketches the layout (`godot/game/data/world-map.json`) in the browser;
  `game/dev/world_atlas.tscn` shows every region's world on it in the editor and moves regions, and
  its **Edit area** joins up to 6 chunks into one scene to edit across their lines, written back into
  the chunk scenes ([Editing an area](docs/godot/WORLD_ATLAS.md#editing-an-area-2026-11-01));
  `"<Godot console exe>" --headless --path godot -s res://tools/build_region_worlds.gd` rebuilds the
  placeholder regions and `res://tools/split_region_chunks.gd -- --region=<ids>` cuts regions into
  one scene per chunk, the scenes to edit ([docs/godot/WORLD_ATLAS.md](docs/godot/WORLD_ATLAS.md)).
- Art tools (`pnpm items:pack`, `grounds:pack`, `props:pack`, `audio:bake` and the Python scripts in
  `scripts/`) turn sources in `asset/Originals/` into runtime sheets in `godot/asset/`:
  [docs/TOOLING.md](docs/TOOLING.md).

## Project Map

- `godot/project.godot` — settings, input map, physics layer names, autoloads.
- `godot/game/main.tscn` — the world bootstrap; `game/shell/title.tscn` is the main scene.
- `godot/game/autoload/` — `WorldService`, `RunState` (the run and saves), `GameConstants` (data)
  and `SimClock`; the other autoloads (`DamageRouter`, `GameFeel`, `MusicDirector`, `Shell`) live
  with their areas. Reach every autoload through `res://game/shared/services.gd`.
- `godot/game/scenes/` — every world, object, character, weapon, effect, projectile and encounter
  scene, with `scene_index.json` (scene id → path; add a line for a scene the game loads by id).
- `godot/game/throw/` — the throw-combat experiment (on in every world, `?melee` turns it off):
  [docs/godot/THROW_COMBAT.md](docs/godot/THROW_COMBAT.md).
- `godot/game/world/villagers/` — the towns' villagers (VillagerScript) and animals (Critter), placed
  from the Scenery dock's Villagers and Animals categories: [docs/godot/VILLAGERS.md](docs/godot/VILLAGERS.md).
- `godot/game/data/` — game constants, items, enemy types, recipes, quests, NPC definitions,
  weapons and item icons (JSON read through `GameConstants`), and the world layout
  `world-map.json` (read through `game/world/atlas/world_map_data.gd`).
- `godot/game/scripts/` — scene scripts (`game.<id>` → `<snake_id>.gd`); the rest of `godot/game/`
  holds gameplay, UI, shell, audio and world systems by area.
- `godot/asset/` — runtime art and audio (`res://asset/...`); `asset/Originals/` (sources and
  concepts) and `asset/project/` (sprite-sheet projects) stay outside the Godot project.
- `godot/tools/` — headless tools (scene verifier, clip and theme builders, labs, the region world
  builder);
  `godot/tests/` — the test suite; `godot/addons/godot_ai/` — the editor plugin (MCP bridge);
  `godot/addons/strike_preview/` — the body shapes' strike preview in the Inspector.
  `godot/addons/scenery_dock/` — the Scenery dock (props by picture, dragged in as nodes).
  `godot/addons/camera_room_handles/` — drag handles for camera rooms' corners and outline points.
  `godot/addons/door_area_handles/` — every door's trigger area drawn in the 2D view, with drag
  handles on the selected door's ([A door's area in the editor](docs/godot/CONVENTIONS.md#doors)).
- `scripts/` — art and audio tools and the test runner; `tools/` is unrelated to the game build.

## Architecture Rules

How the game is built: [docs/godot/ARCHITECTURE.md](docs/godot/ARCHITECTURE.md); project rules:
[docs/godot/CONVENTIONS.md](docs/godot/CONVENTIONS.md); the exact behaviour each area reproduces:
[docs/godot/specs/](docs/godot/specs/).

- Static typing everywhere, tabs, snake_case, one class per file; reference scripts with `preload`.
- Autoloads only through `Services` (`Services.world()`, `.run()`, `.constants()`, `.now_ms()`, ...).
- One gameplay clock: `Services.now_ms()`; real time only for presentation.
- Bodies move only through their own scene script with `ArcadeMover.move(body, delta)`, never
  `move_and_slide()`.
- Gameplay values come from `godot/game/data/game-constants.json` or scene properties, never new
  literals.
- Worlds are scenes: NPCs, gates, interactions and props with logic are instances in the world
  scene; scenery (rock walls, rocks, houses, nature, water life, interiors) is painted from a
  palette on the `cell-props` (64-unit cells) and `details` (32) PropLayers, or dragged in as nodes
  under `Scenery` from the Scenery dock ([docs/godot/PROPS.md](docs/godot/PROPS.md)); the
  player is spawned by code. World enemies are placed nodes (`placed-enemy.tscn` under `Enemies`,
  from the Scenery dock's Enemies category) with wander areas, back each time a chunk is built
  again; spawn areas only in the playground and the dev worlds
  ([docs/godot/specs/enemy.md](docs/godot/specs/enemy.md) §3).
- Terrain is ground only; transitions between grounds are hand-made edge tiles
  ([docs/godot/TERRAIN_LAB.md](docs/godot/TERRAIN_LAB.md)); built stone walls are painted on a
  `walls` WallLayer, whose cells join by themselves ([docs/godot/WALLS.md](docs/godot/WALLS.md)),
  tree walls on a `ForestLayer` ([docs/godot/FORESTS.md](docs/godot/FORESTS.md)); interior (dungeon
  room) walls as Zelda's bevelled frame, two cells deep, with their doors cut into the faces, on an
  `interior-walls` InteriorWallLayer ([docs/godot/INTERIOR_WALLS.md](docs/godot/INTERIOR_WALLS.md); the box-room lab
  only so far), a round or oval room's as a `RoundInteriorWalls` node with its openings as children
  ([Round rooms](docs/godot/INTERIOR_WALLS.md#round-rooms)), the floor's edging along them painted per cell on a `floor-trim` InteriorTrimLayer
  ([Floor trim](docs/godot/INTERIOR_WALLS.md#floor-trim)).
- Chunk lines are closed by terrain (cliffs, water and canals, forest bands, walls), each chunk
  closing its own side; two touching chunks meet at one to three crossings, each inside those two
  chunks (never at a corner), a road wide at most and marked as a way out (bridge, ford, stairs,
  gate, a trail gap between lantern posts); no open ground or road along a line (owner,
  2026-11-01: [level design rule 11](docs/design/2026-10-16-level-design.md#the-rules-that-matter-most)).
- Hills, holes and stairs are painted on a world's `elevation` layer (levels −3 … 16:
  [High levels](docs/godot/ELEVATION.md#high-levels)); the cliffs' side walls and
  each level's collision follow (bake a world's cache after painting; a chunk world's cliffs read
  its neighbours' paint past its edges, so a hill runs on across a chunk line: bake the chunks
  around a painted one too, [Across chunk lines](docs/godot/ELEVATION.md#across-chunk-lines)); a wall's rock follows its ground unless a style is painted on
  the `cliffs` layer ([docs/godot/ELEVATION.md](docs/godot/ELEVATION.md)). A world's level
  collision can be painted on a `level-collision` layer (orange rims that hold and drop, red bases
  that block, green open tiles, whole or 45° halves, per level): in Replace mode it collides exactly
  as painted, in Override mode its tiles change the automatic collision only where painted
  ([Painting collision](docs/godot/ELEVATION.md#painting-collision)); walls, trees, fences and props
  collide by themselves. Inside dungeon rooms the level changes are drawn as the room's own wall
  faces and collide by their square footprint (drops and slabs stay the outdoor ones:
  [Faces in rooms](docs/godot/ELEVATION.md#faces-in-rooms));
  a division inside a room is a low divider painted on the `fences` layer with a divider gate
  ([docs/godot/FENCES.md](docs/godot/FENCES.md#dungeon-dividers)).
- Climbable vines (the Feral skin) and balconies (rock ledges that step out of a tall wall, to land
  and stand on: the layer's second tile) are painted on a `vines` VineLayer, on the cells of a cliff's
  front wall: an interact press clings (a second lets go) and the movement keys move the slime over them; a placed
  `climb-wall` only for a climb out of a world or one that ends on the face
  ([docs/godot/SKINS.md](docs/godot/SKINS.md#painting-vines)).
- A sky floor (islands over clouds) is the sky painted as holes (level -2 or lower) on the
  `elevation` layer inside a `SkyFloor` node's area, which draws the parallax backdrop and the cloud
  bank there; a drop into it is a void fall back to where the slime fell from, and rope bridges
  (solid railings) cross it
  ([docs/godot/SKY_FLOOR.md](docs/godot/SKY_FLOOR.md)).
- Saves go through `RunState` to `user://saves/`.

## Status

No CI. Automated coverage is `pnpm test:godot` and `tools/verify_scenes.gd`; interactive feel
(movement, combat, visuals) still needs a manual playthrough.
