# Godot Migration

> **Status: in progress** on branch `feat/godot-migration` (started
> 2026-10-04). Phase 0, the trial port, decides whether the migration goes
> ahead. This file owns the plan; [GAME_ROADMAP.md](./GAME_ROADMAP.md) tracks
> it as milestone **G**.

## Why

Growing the game had become slow mainly because of the custom editor: Scene
Studio costs a lot of time and will never match an engine editor. The Phaser
game already copies Godot's model (Node, SceneTree, Signal, ScriptNode,
AnimationPlayer, Godot collision-layer rules, and scene documents whose node
types are Godot's), so moving to Godot is a port, not a rewrite. Decided by the
owner on 2026-10-04.

## Target

- **Godot 4.7.2 stable, GDScript** with static types. C# is not an option: a
  C# project cannot export to the web, and Release 1 is a free web build.
- **Compatibility renderer** (WebGL 2) on every platform, so the web build looks
  like the desktop one. One project exports web, desktop and Android.
- The Godot project lives in `godot/` beside the Phaser app until it matches
  today's build. Then the Phaser app (`src/`, Vite, Scene Studio) is removed.

## What happens to each part

| Part | Fate |
|---|---|
| Art and audio in `asset/` | Used as they are (WebP, OGG, WAV import directly) |
| `asset/assets.json` | Read by the converter for frame grids, origins and paths |
| Scene JSON (`content/scenes/authored/`) | Converted by a script into `.tscn` scenes, tile sets and animation libraries |
| `game-constants.json`, items, enemy types, recipes, quests | Kept as data; read by GDScript or converted to Resources |
| Scene scripts (`features/scripts/`) and pure logic (combat, AI, quests, crafting, inventory, saves) | Ported by hand to GDScript |
| UI scenes (HTML/CSS today) | Structure converted to Control nodes; styling redone as a Godot Theme |
| Scene Studio, the TS scene runtime (`runtime/scene`, `infrastructure/phaser-nodes`), Phaser plumbing | Dropped: Godot provides them |
| Occlusion silhouettes (`features/occlusion`) | Dropped (owner, 2026-10-04); Godot's Y-sort keeps draw order |
| Ground levels (elevation) | Not ported: the `feat/elevation-levels` experiment was rejected; only its art was kept. Elevation is redesigned the Godot way after the port |
| `MobileVersion/` | Removed (2026-10-04); Android becomes an export preset of the new project after Release 1 |

## Conversion map

| Scene JSON | Godot |
|---|---|
| `Node2D`, `Sprite2D`, `Area2D`, `StaticBody2D`, `CharacterBody2D`, `CollisionShape2D`, `AnimationPlayer`, `AudioStreamPlayer(2D)` | Same node types |
| `TileMapLayer2D` + `terrain.tiles` | `TileMapLayer` + a generated `TileSet` (one atlas source per tile id, Phaser's exact frame choice); solid tiles become merged rectangle bodies inset on their outer edges, as in Phaser |
| `ScriptNode` | A child `Node` with the ported script (`game.<id>` → `game/scripts/<id>.gd`); unported scripts keep their id and properties as data |
| Instances with overrides | Instanced scenes with overridden properties (editable children where a sub-node changes) |
| Signal connections | `[connection]` entries; audio `play`/`stop` handlers call `play_cue`/`stop_cue` |
| Sprite `origin` (0–1) and `visualOffset` | `centered = false` and a pixel `offset` |
| `alpha`, `tint`, `flipX`/`flipY` | `self_modulate`, `flip_h`/`flip_v` |
| Sprite-sheet resources | `hframes`/`vframes` on the Sprite2D, from `assets.json` |
| Animation keys at frame `at` | Keys at `at / framesPerSecond` seconds; `alpha` → `self_modulate:a`; events → method keys emitting `animation_event` |
| Collision layers and masks | Same bits; the eleven names from `collision-layers.json` become layer names |
| Rectangle and circle shapes | `RectangleShape2D`, `CircleShape2D` |
| Ellipse and sector shapes (30 in all) | Polygon approximations |
| `depthAnchor` on a scene root | The root is moved to the anchor (the feet) and keeps `metadata/depth_anchor`, so Y-sorting by node position matches Phaser's sort line |
| `depthBand` | `z_index` (ground decals below, overhead art above); world containers are Y-sorted |
| `depthBounds` (custom sort line) | A position/offset shift that puts the node origin on the sort line |
| `depthOffset`, `occlusionBounds` | Dropped (weapon layering is handled in script; occlusion is not ported) |
| UI Control scenes | Control nodes with anchors and offsets and a generated minimal Theme; the HTML/CSS styling is not converted |

## Phases

0. **Trial** (go/no-go). Convert every scene, play level-1 with the player,
   a worm swordsman and the basic sword, and export to the web. It passes when:
   - every converted scene loads in Godot without errors, and level-1 looks
     like the Phaser version apart from the known gaps (terrain blending,
     water shader, occlusion);
   - movement and the sword feel right to the owner;
   - the web build holds 60 fps in level-1 on the reference laptop.
1. **Full conversion.** All worlds, objects, characters, weapons and effects.
   From here the Godot scenes are the source of truth and scene JSON is frozen.
2. **Gameplay.** Every scene script and service; services become autoloads.
3. **UI.** HUD, menus, inventory, crafting, quests and dialogue as Control
   scenes with one Theme.
4. **Shell, saves and audio.** Title, settings, versioned saves in `user://`,
   music director and buses.
5. **Parity and cutover.** A fresh-save playthrough of Chapter 1 in Godot,
   then the Phaser app is removed and Release 1 continues in Godot.

After the cutover, elevation is designed natively: one collision layer per
level switched on stairs, a height value for jumps and projectiles, and cliffs
painted as tiles in the editor.

## Working with the Godot project

Use Godot **4.7.2** (the GDScript build). Project rules, layout and checks are in
[godot/CONVENTIONS.md](./godot/CONVENTIONS.md); how the game is built is in
[godot/ARCHITECTURE.md](./godot/ARCHITECTURE.md); the exact Phaser behaviour each
ported area reproduces is in [godot/specs/](./godot/specs/).

```bash
pnpm godot:sync
pnpm godot:convert
```

`godot:sync` copies the mapped assets into `godot/asset/`; `godot:convert`
(`scripts/godot/convert-scenes.mjs`) writes `godot/generated/` from the scene
JSON (`--check` exits 1 when that output is stale). Then open `godot/` in the
Godot editor and press F5, or run headless checks:

- `--headless --path godot --import` imports the assets;
- `--headless --path godot -s res://tools/verify_generated.gd` loads and
  instantiates every converted scene, checks every property, node reference and
  tile against the JSON, and plays level-1 for 30 frames;
- `--headless --path godot --quit-after 600` boots the game for ten seconds.

Web build: `--headless --path godot --export-release "Web" export/web/index.html`,
then serve `godot/export/web` (the `godot-web` entry in `.claude/launch.json`
serves it on port 3200). Launch options for testing: `?map=<world id>` and
`?spawn=<x>,<y>` (old Phaser coordinates) on the web, `-- --map=<id>
--spawn=<x>,<y>` on desktop.

## Trial status (2026-10-04)

- All 1,186 scenes convert in under a second and load in Godot 4.7.2 with no
  errors; level-1's 1,670 sprites match Phaser's placement within 0.02 px and
  all 332 animation clips match frame by frame.
- Level-1 plays in the web build: the player moves and swings the basic
  sword; worm swordsmen spawn at the starter camp, chase, attack and deal
  damage; the HUD, damage numbers, death and respawn work. Dodge, sword hits on
  worms and the damage numbers' values were checked in headless probes. Headless Brave on
  the owner's machine held 60 fps (16.7 ms frames, 17 ms worst) idle, walking
  and fighting. The web data pack is 44 MB (textures imported as lossy WebP at
  quality 0.9) plus the 39.5 MB engine (about 9 MB compressed).
- Not yet (updated 2026-10-05): the reference-laptop measurement, the owner's feel
  check, and Phase 5's fresh-save playthrough of Chapter 1 by hand (an automated run of its main line,
  `test_chapter_one_main_line`, passes). Every scene script id the authored scenes use is ported except `game.ui-surface`,
  which Godot-owned windows replace. A headless Brave run of the web build on 2026-10-05 held
  58-59 fps in level-1, the Fatty fight and the Matron's nest (pack 46.1 MB).
- World objects are ported (2026-10-05, [godot/specs/world-objects.md](./godot/specs/world-objects.md)):
  trees, stone and iron take tool hits (the sword shows "Requires an Axe"), break into
  piles that fly out and can be walked over into the bag, and regrow 10 minutes after
  their last pile is taken. The run (inventory, coins, records, story flags) lives in the
  `RunState` autoload; world exits travel between areas, gated exits take their key, and
  story variants swap with their flags. `?weapon=<id>` / `-- --weapon=<id>` holds
  another weapon (a stone axe to harvest, a spear for Fatty).
- Interaction is ported (2026-10-05, [godot/specs/interaction.md](./godot/specs/interaction.md)):
  right click on doors (travel between houses and the world), gates (with the key),
  chests, beds (sleep heals and sets the respawn point) and NPCs, with Phaser's prompt
  and key badge. A chest opens the chest window (2026-10-05,
  [godot/specs/journal-and-chest.md](./godot/specs/journal-and-chest.md)): its stacks, Take Stack
  and a right click to take one; NPCs talk through the dialogue box (with the quests) and
  workbenches open the crafting window (with crafting).
- The water shader is ported (2026-10-05, [godot/specs/water.md](./godot/specs/water.md)):
  the animated surface over `water` and `deep-water` tiles, with the water life
  drawn and animated as in Phaser. Shores are rounded by the terrain edges (next item), which
  draw over the surface with the same water maths; a shader step smooths the deep/shallow ground.
- Terrain edges replace Phaser's code blend (2026-10-05, [godot/TERRAIN_LAB.md](./godot/TERRAIN_LAB.md)):
  hand-made edge tiles (Magnific art) for every natural ground, drawn on a dual grid over the ground
  layer in every world, water shores included. The terrain lab (F6, T toggles) shows every pair.
- The level-1 boss fight is ported (2026-10-05, [godot/specs/boss.md](./godot/specs/boss.md)):
  the Fatty One Eye camp spawns the boss when the player walks in; it chases,
  contact-hops, leaps with a ground telegraph, lands for damage with the ground
  crack and a camera shake, walks home and heals when the player leaves the arena,
  shows the boss health bar, and dies with its death clip (the body stays 2 s and
  fades out, owner decision; Phaser removed it at once). Only spears hurt it: craft one, or start with
  `--weapon=basic-spear`.
- Every enemy the worlds spawn is ported (2026-10-05, [godot/specs/enemy.md](./godot/specs/enemy.md)
  part 2): worm archers shoot arrows and keep their distance, slime spiders and orb weavers
  spiral in and spit webs, worm brawlers punch with their hit effect; projectiles fly, stop at
  walls and hit once; enemies can be slowed; crystal-caverns spawns around the player as in
  Phaser. Every camp type spawns in play (the trial's worm-swordsman-only filter is lifted).
- The gloop-forest boss is ported (2026-10-05, [godot/specs/matron.md](./godot/specs/matron.md)):
  the Orb-Weaver Matron's nest camp, her spit, her web volleys with their ground marks, the web
  patches they leave and the spider-web barriers, with the boss bar and the camp records. Webs
  root the slime (`apply_web`), and the Sticky form tears patches and barriers.
- The music director is ported (2026-10-05, [godot/specs/audio.md](./godot/specs/audio.md)):
  world music fades in on arrival and out before a travel,
  crossfades to the boss music while a boss fight lasts, ducks under a pause menu, waits for the
  web audio unlock, and plays the arrival cue; `apply_mix` gives the settings their bus mix.
- The UI theme and the game shell are ported (2026-10-05, [godot/UI_THEME.md](./godot/UI_THEME.md),
  [godot/specs/shell.md](./godot/specs/shell.md)); the `Shell` autoload is registered, the title is
  the main scene and the theme is the project theme: one Theme built from the CSS tokens with type variations
  for every recurring role, the title screen over the drifting level-1 (launch options skip it),
  the pause menu, settings saved to `user://settings.cfg` and applied to the buses and screen
  shake, the controls list, credits, area title cards, game over and end cards; the HUD uses the
  theme. The UI font is Source Sans 3 (owner pick) with Noto Sans Symbols 2 for symbols.
- Owner decisions (2026-10-05, [godot/ARCHITECTURE.md](./godot/ARCHITECTURE.md#12-open-questions)):
  keep the live aim origin; the sword's combo off-by-one is fixed in the port
  (24 per hit); the player gets new three-quarter top-down art with clips per
  direction. New art is made at 128 px per 64-unit cell (2 px per world unit;
  the grid does not change), and terrain transitions are tried as hand-made
  tiles instead of a code blend ([godot/TERRAIN_LAB.md](./godot/TERRAIN_LAB.md)).
- Phase 1 has started with the player: `character.player-slime` is the first
  scene Godot owns ([godot/CONVENTIONS.md](./godot/CONVENTIONS.md#scenes-godot-owns)),
  with page 1 of the new slime (idle and walk facing down, up and side; idle
  keeps the last facing). The playground runs with F6 from `game/dev/playground.tscn`.
  Page 2 (2026-10-05) adds the roll and the attack swing for every direction.
- The player's abilities are ported (2026-10-05, [godot/specs/abilities.md](./godot/specs/abilities.md)):
  energy, jump, dodge, stretch lash, squash slam, teleport, Gulp forms (eat stone to turn Heavy or silk to
  turn Sticky for a while), the Goo Trail passive, and their puzzle pieces (training dummy,
  pressure plates, cracked ground, lash bells, ability lessons, Goo Hearts, restoration sites).
  Status effects on the slime (burn, poison, slow, webs that root it) work too. There is no quick
  wheel for Gulp materials yet.
- Saves are ported (2026-10-05): the run saves to `user://saves/slot-<n>.json`, slot 0 being a
  recovery autosave written shortly after every change (never while dead) and when the window closes.
- Enemy rewards are ported (2026-10-05): coins ("+10c") and loot piles scattered round the corpse,
  kept on the ground across visits until picked up. A slime defeated far from its bed wakes at the
  bed in that bed's world.
- The minimap and the world map are ported (2026-10-05, [godot/specs/map.md](./godot/specs/map.md)):
  the framed minimap in the HUD's corner draws a small map of the world's ground (owner decision;
  Phaser's was see-through, `Minimap.terrain_alpha = 0` brings that back) and shows the slime, the
  camera view and markers; the world map window (M or the pause menu's Map) lists the
  discovered areas and the ways between them. Other features place markers through `MapUi.set_marker`.
- Quests are ported (2026-10-05, [godot/specs/quests.md](./godot/specs/quests.md)): the 14 quests
  of chapters 1 and 2 with their stages, objectives, rewards and chapter flags, saved with the run;
  NPCs offer, take back and talk about quests through the dialogue box and the offer / turn-in
  window, wear "!" / "?" markers, and the HUD tracker lists the quests (a click shows the gold
  waypoint, also on the maps). Pickups, ordinary enemy deaths, boss defeats, restorations, arrivals,
  sprinting, the menus, crafting, belt switches and placing furniture count. The quest journal
  (the menu's Journal tab or the pause menu's Journal) lists the quests taken on with their steps
  and abandons or retries side quests ([godot/specs/journal-and-chest.md](./godot/specs/journal-and-chest.md)).
  `?quest=<id>[:<stage>]` starts a
  quest at a stage for testing.
- Crafting, the bag and the weapon belt are ported (2026-10-05, [godot/specs/crafting.md](./godot/specs/crafting.md)):
  E opens the bag (belt, cells, details; Use, Hold in hand, belt assignment, drag onto the belt,
  Drop on the ground, Destroy), and its tab strip switches to Crafting; workbenches, the Workshop
  and the Forge open the crafting window for their recipes. A crafted weapon goes onto the belt
  and into an empty hand; the mouse wheel and the HUD hotbar switch belt weapons; tonics, brews
  and baskets heal. A new run starts empty-handed in level-1, as in Phaser (owner decision
  2026-10-05); the playground hands out all 13 weapons, and `?weapon=<id>` starts with one in hand.
  `?recipes` makes every recipe known (a dev aid). The release web export ("Web") leaves out
  `game/dev/` (playground wrapper, terrain lab) and the dev-only worlds; "Web (dev)" keeps them.
- Furniture placement is ported (2026-10-05, [godot/specs/furniture.md](./godot/specs/furniture.md)):
  crafting a Workbench (or "Place" in the bag) shows a ghost that follows the pointer on a 32 px
  grid, green within reach on free ground and red elsewhere; left click places it (the wheel
  switches to the bench with a vise, right click or Esc cancels) while the slime keeps walking. A
  placed bench is a crafting station, comes back with the world, and a 450 ms hold of the interact
  button picks it up. "A Place to Work" can now be finished in play. Placement ends if the slime
  is defeated (owner decision F1 as recommended).

## Rules while it runs

- Until Phase 1 ends, scene JSON stays the source: fix content there and
  re-run the converter; never hand-edit converted output.
- After the trial passes, new gameplay is built in Godot only.
