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
| `TileMapLayer2D` + `terrain.tiles` | `TileMapLayer` + a generated `TileSet` (one atlas per ground sheet) |
| `ScriptNode` | A child `Node` with the ported script; unported scripts keep their id and properties as data |
| Instances with overrides | Instanced scenes with overridden properties (editable children where a sub-node changes) |
| Signal connections | `[connection]` entries |
| Sprite `origin` (0–1) and `visualOffset` | `centered = false` and a pixel `offset` |
| `alpha`, `tint`, `flipX`/`flipY` | `modulate`, `flip_h`/`flip_v` |
| Sprite-sheet resources | `hframes`/`vframes` on the Sprite2D |
| Animation keys at frame `at` | Keys at `at / framesPerSecond` seconds; `alpha` → `modulate:a` |
| Collision layers and masks | Same bits; the eleven names from `collision-layers.json` become layer names |
| Rectangle and circle shapes | `RectangleShape2D`, `CircleShape2D` |
| Ellipse and sector shapes (30 in all) | Polygon approximations |
| `depthMode`, `depthBand`, `occlusionBounds`, `depthBounds` | Dropped: the world is Y-sorted by node position (feet) |

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

## Rules while it runs

- Until Phase 1 ends, scene JSON stays the source: fix content there and
  re-run the converter; never hand-edit converted output.
- After the trial passes, new gameplay is built in Godot only.
