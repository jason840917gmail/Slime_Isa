# Spec: World bootstrap, camera, HUD, NPCs (Phase 0 trial)

Area owner: world bootstrap / camera / HUD / NPC wandering. Binding inputs: `docs/GODOT_MIGRATION.md`, `docs/godot/CONVENTIONS.md`. All Phaser references are `src/game/...` paths, read-only.

Legend: **[IN]** = build for the trial. **[OUT]** = exists in Phaser, not in the trial (recorded so later phases know). **[FEET]** = a place where Phaser treats the body/root position as something other than the feet; the Godot port must convert (see §0).

---

## 0. Coordinate rule (applies everywhere below)

Conventions "Feet origin": a converted scene root with `depthAnchor` is re-anchored so `root.global_position` is the old depth anchor. Every Phaser position in this spec is an **old root position** ("P"). Conversions:

```gdscript
# old Phaser root position from a Godot (feet) root
func phaser_pos(root: Node2D) -> Vector2:
	var anchor: Vector2 = root.get_meta("depth_anchor", Vector2.ZERO)
	return root.global_position - anchor * root.scale
# place a re-anchored scene at an old Phaser position P
root.global_position = P + anchor * root.scale
```

What the old root position *means* differs per scene, which is why the conversion matters:

| Scene | Phaser root = | `depthAnchor` (scene JSON, root local) | Godot root (feet) = |
|---|---|---|---|
| `character.player-slime` | centre of the slime sprite (Visual origin 0.5,0.5 at 0,0) | `(0, 27.56)` (`player-slime.scene.json` body) | P + (0, 27.56) |
| `character.village-elder-plop` | bottom-centre of the sprite (Visual origin 0.5,1 at 0,0) | `(0, -13)` | P + (0, -13) |
| `character.lili` | sprite bottom-centre | `(0, -7)` | P + (0, -7) |
| `character.red-slime-boy` | sprite bottom-centre | `(0, -7)` | P + (0, -7) |
| `character.yellow-blond-slime-girl` | sprite bottom-centre | `(0, -9)` | P + (0, -9) |
| `character.mossy-scout` | sprite bottom-centre | `(0, -6)` | P + (0, -6) |
| `character.fisherman-slime` | sprite bottom-centre | `(0, -10)` | P + (0, -10) |

(NPC depth anchors are the bottom of their BodyShape: e.g. elder shape at y −26, height 26 → bottom −13. So for NPCs the Godot origin sits **above** the old origin.)

**Converter dependency (flag to converter owner):** authored instances of re-anchored scenes in `world.level-1` (the six NPCs, and any other character/effect instance) carry a `position` override that is an old root position. The converter must write `P + depth_anchor * scale` for those overrides. Check after conversion: `level-1-npc-village-elder-plop` root `global_position == (524.8, 703.8)`; `level-1-npc-lili` == `(435.2, 914.6)`. World code must **not** shift them again.

---

## 1. Startup order

### 1.1 Phaser (for reference)

`src/game/config.ts:158-189`: `Phaser.Scale.RESIZE` (canvas = page size in CSS px, Phaser resolution 1, no devicePixelRatio), `backgroundColor '#0b1020'`, `roundPixels: true`, Arcade fixed step 60 Hz. Scenes `BootScene → MapLoadScene → WorldScene`.

1. `MapLoadScene.create` (`scenes/MapLoadScene.ts:22-77`): `resolveAreaRequest({})` → area id = pending navigation ?? `?area=` ?? `STARTING_AREA_ID` (`world/Area.ts:22`, `'level-1'`). Dev `?map=<id>` overrides. Loads `world.<mapId>` scene + its images behind a loading bar, then `scene.start('world', {areaId, entryEdge, entryDoor, loadedWorld})`.
2. `WorldSceneLoader.loadedMapFromScene` (`infrastructure/scenes/WorldSceneLoader.ts:53-118`) builds the legacy `MapFile` from the scene: world-definition properties, tile layers, `player-spawn` / `player-entry-<dir>` marker positions, door arrivals, and world-area perimeters (§3). `cameraMode = definition.properties.cameraMode ?? 'follow'` (`:115`).
3. `WorldScene.init` (`scenes/WorldScene.ts:280-294`): stores area, map, `worldDimensions`.
4. `WorldScene.create` (`:296-...`), relevant order:
   - new run installed if none (`:309-312`, OUT: saves);
   - `buildWorld()` (`:1342-1399`): terrain grid; **`physics.world.setBounds(0, 0, width, height)`** (`:1356`);
   - `createPlayer()` (`:1437-1471`): spawn point (§2.2) → `createUniversalSceneWorld(spawn)` → `UniversalSceneWorldController` constructor (`features/world/UniversalSceneWorldController.ts:455-781`): builds script services, mounts `audio.global`, all `ui.*` scenes (hud, weapon-hotbar, ability-bar, health-bar, boss-health-bar, area-title-card, inventory, chest, crafting, quest-journal, quest-offer, npc-dialogue, quest-tracker, world-map, shell scenes, minimap), then **`mountPlayer()` (`:1882-1900`) before `mountAuthoredWorld()` (`:1739-1786`)**; then the player name tag;
   - `createCamera()` (`:1477-1513`, §4);
   - combat, hotkeys (`bindHotkeys :2032-2041` = zoom keys).
5. Every frame: `WorldScene.update` → `universalWorld.advanceFrame(delta/1000)` (fixed 1/60 s steps, max 5 per frame: `PhaserSceneTreeHost.ts:3-4`); then on `POST_UPDATE` `handlePresentationPostUpdate` (`WorldScene.ts:1590-1597`) → `cameraController.update(delta)` (every rendered frame, also while paused / during hit-stop).

### 1.2 Godot trial bootstrap [IN]

Proposed files (architect may rename; keep behaviour): `res://game/world/world_bootstrap.gd` (on `main.tscn`), `res://game/world/world_camera.gd`, `res://game/world/world_bounds.gd` (or inline), `res://game/ui/hud.gd`, `res://game/ui/player_health_bar.gd`, `res://game/ui/fps_readout.gd`, scene scripts `res://game/scripts/world_definition.gd`, `world_area.gd`, `npc.gd` (names fixed by the converter rule `game.<id>` → `res://game/scripts/<snake>.gd`).

Order in `world_bootstrap._ready()`:

1. Resolve map id: `"level-1"` (= `STARTING_AREA_ID`). Optional: on web read `?map=` via `JavaScriptBridge.eval("new URLSearchParams(location.search).get('map')")`; desktop `OS.get_cmdline_user_args()`. Scene path from `res://game/scenes/scene_index.json["world.<mapId>"]`.
2. `var world := load(path).instantiate()`; `add_child(world)` (under a `World` Node2D; the world root already has `y_sort_enabled = true` from the converter).
3. Read the world definition (§2.1) from the `world_definition.gd` node; compute `WorldDimensions`.
4. Build world bounds walls (§2.3).
5. Collect world areas (§3.1) into the world service.
6. Resolve the spawn point P (§2.2). Instance `character.player-slime` (`scene_index`), set `global_position = P + depth_anchor * scale` **[FEET]**, add it **as a child of the world root** (so it Y-sorts with props; Phaser mounted it as a separate root but depth-sorted globally, same visual result). Note Phaser mounts the player *before* the world; in Godot add it after the world so the world root exists — no behavioural difference (no script reads the other at mount time).
7. Configure NPCs (§5.3): for every `npc.gd` node under the world root call `configure_wander(...)`.
8. Create camera (§4), start follow with immediate centring, start the arrival fade-in (§4.7).
9. Add UI: HUD CanvasLayer (§6), floating health bar (§6.3), FPS readout (§7).

Integrator settings this area needs (report, do not edit `project.godot`):
- **Viewport scale**: the screen shows a fixed number of tiles, as in Zelda: A Link to the Past (16 × 14). `project.godot` sets the base size 1024 × 896 (16 × 14 tiles of 64 px) with `stretch/mode="canvas_items"`, `aspect="expand"`, and the bootstrap's `apply_viewport_scale()` keeps `get_tree().root.content_scale_size` at that base size (on start and on `root.size_changed`). Godot scales the base to the window: the view is always 14 tiles tall at least and 16 wide at least, a wider window shows more columns (16:9 → about 25 × 14), and the UI scales with the world. This replaced the Phaser rule (1 game px = 1 CSS px, the visible world grew with the window) on 2026-10-07; the rules are in [docs/story/03-world.md](../../story/03-world.md#world-size-and-screen).
- `physics/common/physics_interpolation = true` (Phaser interpolates presentation between fixed steps: `presentation/PhysicsPresentation.ts:30-46`, `CameraMotion.ts:52-62`). `max_physics_steps_per_frame=5` is already set (matches `MAX_FIXED_STEPS_PER_FRAME = 5`).
- Clear colour `#0b1020` already set.

---

## 2. World definition, spawn, bounds

### 2.1 `world_definition.gd` [IN]

Phaser: `features/scripts/WorldDefinitionScript.ts:11-30` (data holder). Exports (snake_case of JSON keys; the converter writes only declared exports):

```gdscript
extends Node
@export var map_id: String = ""
@export var tile_size: int = 0
@export var columns: int = 0
@export var rows: int = 0
@export var metadata: Dictionary = {}     # level-1: {objects: [], player: {spawn:{x:640,y:704}, entries:{east:{x:3872,y:569.6}, south:{x:1081,y:990}}}}
@export var camera_mode: String = "follow" # absent in level-1 → "follow"; "fixed" in interiors
```

level-1 values (`worlds/level-1.scene.json`, node `world-definition`): `mapId "level-1"`, `tileSize 64`, `columns 64`, `rows 64`. Validation as Phaser (`WorldSceneLoader.ts:57-60`, `WorldDimensions.ts:15-19`): positive integers, else push_error and abort. `camera_mode` other than follow/fixed → error.

`WorldDimensions` = `{tile_size: 64, columns: 64, rows: 64, width: columns*tile_size = 4096, height: rows*tile_size = 4096}`.

Spawn source: Phaser uses the **`player-spawn` Node2D marker position**, not `metadata.player.spawn` (`WorldSceneLoader.ts:90-96`; they are equal in level-1: `(640, 704)`). Missing marker → error. Entries (`player-entry-east (3872,569.6)`, `player-entry-south (1081,990)`) and door arrivals (`home-door/arrival` global `(1083, 954)`, `mushroom-door/arrival` `(1493, 538)`, rounded) are [OUT] (only used when arriving through an exit/door).

### 2.2 Spawn point resolution [IN]

Phaser `WorldScene.createPlayer` (`:1437-1446`): a new run's location is `level-1.map.json` spawn `(640,704)` (`content/initial-state/InitialRun.ts:7-11,27-35`), which equals the marker. Then:

```ts
// WorldScene.ts:1443-1445
const spawnPoint = restoredLocation && this.isValidSavedPosition(restoredLocation)
  ? new Phaser.Math.Vector2(restoredLocation.x, restoredLocation.y)
  : this.findSpawnPoint(this.getEntryAnchor());
```

Trial (no saves) algorithm, P in old-root coordinates **[FEET]** (P is the slime's sprite centre):
1. `P = player-spawn` marker position.
2. Valid if finite, `0 <= x <= width`, `0 <= y <= height`, and the tile `(floor(x/64), floor(y/64))` is inside the grid and **not solid** (`isValidSavedPosition :1540-1548`). Solid tiles = tile ids whose `terrain.tiles` entry has `physics` (`content/terrain/TileCatalog.ts:95-97`): `water`, `deep-water`, `rock-wall` (Godot since 2026-10-06: shallow `water` is walkable, so `WorldService.SOLID_TILE_IDS` is `deep-water`, `rock-wall`). Read the cell's tile id from the ground `TileMapLayer` (atlas source id ↔ tile id mapping from the converter) or from the tile-data. level-1 tile (10,11) is `town-cobble` → P stays exactly `(640, 704)` (not tile-centred).
3. If invalid → `findSpawnPoint(anchor = P)` (`:1615-1638`): `start = (floor(P.x/64), floor(P.y/64))`; for `radius` in `0 ..< max(columns, rows)`: for `ty` in `start.y-radius ..= start.y+radius`: for `tx` in `start.x-radius ..= start.x+radius`: first cell in-grid and not solid → return its centre `(tx*64+32, ty*64+32)`. Nothing → world centre `(width/2, height/2)`.
4. Godot player root `global_position = P + (0, 27.56)` (scale 1).

The tile under the **centre** (not the feet) is what Phaser tests; keep that **[FEET]**.

### 2.3 World bounds [IN]

Phaser: `physics.world.setBounds(0, 0, width, height)` (`WorldScene.ts:1356`) and every `CharacterBody2DNode` has `collideWorldBounds` default `true` (`infrastructure/phaser-nodes/CharacterBody2DNode.ts:25`; player sets it explicitly). Arcade keeps each body's **collision rectangle** inside `[0,width]×[0,height]` regardless of collision masks. Camera bounds are the same rect (§4.5).

Godot: one `StaticBody2D` "WorldBounds" under the world root with four `CollisionShape2D` rectangles placed just outside the rect, thickness `T = 256` (no tunnelling at dodge speed 380 px/s): left `Rect(-T, -T, T, H+2T)`, right `Rect(W, -T, T, H+2T)`, top `Rect(0, -T, W, T)`, bottom `Rect(0, H, W, T)` with W=H=4096. `collision_layer = 1` ("world"), `collision_mask = 0`. Every character body mask in level-1 includes bit 1 (player 1157, NPC 1027; enemy masks per the enemy spec), so the result matches Arcade. Because the shapes are fully outside the world, they never affect sight checks inside it. The converter drops `collideWorldBounds`; nothing else replaces it.

---

## 3. World areas

### 3.1 `world_area.gd` [IN as data]

Phaser: `features/scripts/WorldAreaScript.ts:39-54` (data holder) + `WorldSceneLoader.worldAreaData :182-225` + `content/scenes/worldAreaGeometry.ts:32-52`.

```gdscript
extends Node
@export var area_kind: String = ""   # "enemy-safe-zone" | "enemy-spawn" | "npc-wander"; anything else → push_error
@export var area_id: String = ""
@export var area: Area2D
@export var data: Dictionary = {}    # camelCase keys kept (npcInstanceId, enemies, intervalMs, maxPopulation)
@export var shape: CollisionShape2D
@export var stay_shape: CollisionShape2D   # enemy-spawn only
```

Perimeter from a CollisionShape2D (use `shape_node.global_position`, `global_rotation`, `global_scale` — the shape node's own position counts, e.g. webwood shape at `(-64, 51.2)` local):
- circle: needs `|sx - sy| <= 1e-6`; `{shape:"circle", x: round(gx), y: round(gy), radius: max(1, round(r * |sx|))}`.
- rectangle: needs `|sin(rotation)| < 1e-6`; `w = width*|sx|, h = height*|sy|`; `left = round(gx - w/2)`, `top = round(gy - h/2)`, `right = max(left+1, round(gx + w/2))`, `bottom = max(top+1, round(gy + h/2))` → `{shape:"rectangle", x:left, y:top, w:right-left, h:bottom-top}`.
- other shapes → error. JS `Math.round` = round-half-up; use `floor(v + 0.5)` (all level-1 values are positive).
- Converted shape resources: `CircleShape2D.radius`, `RectangleShape2D.size`.

Records the world service exposes (Phaser `MapFile` fields, `WorldSceneLoader.ts:209-224`):
- `enemy-safe-zone`: must be a rectangle → `{x, y, w, h}` (level-1 `enemy-safe-1`: Area2D `(896,640)`, rect 1536×1024 → `{x:128, y:128, w:1536, h:1024}`).
- `enemy-spawn`: `{...data, id, stayPerimeter, pursuePerimeter: shape}`; stay must fit inside pursue (same shape kind) or error. Consumed by the enemy population spec (not this area). level-1 has `level-1-starter-camp` (worm-swordsman ×3, intervalMs 2500, maxPopulation 3) plus webwood/autumn-grove/south-meadow (other enemy types, [OUT] for the trial unless the enemy spec says otherwise).
- `npc-wander`: `{...data, id, perimeter}`; `data.npcInstanceId` names the NPC instance.

Suggested API on the world service autoload/bootstrap: `areas(kind: String) -> Array[Dictionary]`, `npc_wander_area(instance_id: String) -> Dictionary` (empty if none), `dimensions() -> Dictionary`, `is_solid_tile(tx, ty) -> bool`.

### 3.2 level-1 NPC wander areas (computed; verify at runtime)

| Area | NPC instance (`data.npcInstanceId`) | Perimeter |
|---|---|---|
| npc-area-01 | `level-1-npc-village-elder-plop` | circle (525, 717) r 80 |
| npc-area-02 | `level-1-npc-mossy-scout` | rect x 798 y 658 w 120 h 80 |
| npc-area-03 | `level-1-npc-lili` | circle (435, 922) r 64 |
| npc-area-04 | `level-1-npc-red-slime-boy` | rect x 559 y 906 w 150 h 70 |
| npc-area-05 | `level-1-npc-yellow-blond-slime-girl` | circle (858, 947) r 64 |
| npc-area-06 | `level-1-npc-fisherman-slime` | rect x 1275 y 718 w 150 h 48 |

Each NPC instance is authored at its area's centre (old root position).

---

## 4. Camera [IN]

Phaser: `presentation/ResponsiveCameraController.ts`, `CameraMotion.ts`, `CameraZoom.ts`, `WorldScene.createCamera :1477-1513`, `bindHotkeys :2032-2041`, `handleResize :1884-1888`. All values are TS literals (none in game-constants.json); keep them as named `const`s in `world_camera.gd` (presentation values, not balance).

### 4.1 Node setup

`Camera2D` "WorldCamera" (child of the bootstrap, not of the player), `anchor_mode = ANCHOR_MODE_DRAG_CENTER`, `position_smoothing_enabled = false`, `drag_horizontal_enabled = drag_vertical_enabled = false`, leave Godot `limit_*` at defaults (clamping is done in script, §4.5), `ignore_rotation = true`, `process_callback = CAMERA2D_PROCESS_IDLE`, `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF` (moved in `_process`), `process_mode = PROCESS_MODE_ALWAYS` (Phaser updates the camera every frame even when paused or during hit-stop), `process_priority = 100` (after gameplay `_process`, like `POST_UPDATE`). The script keeps its own `center: Vector2` and writes `global_position = center` and `zoom = Vector2(z, z)` (Godot zoom semantics = Phaser: 2 means twice as big).

### 4.2 State

```
CAMERA_ZOOM_LEVELS = [0.5, 0.625, 0.75, 0.875, 1.0, 1.125, 1.25]   # CameraZoom.ts:7
DEFAULT_CAMERA_ZOOM = 1.0                                          # CameraZoom.ts:1
CAMERA_DAMPING_RATE = 12.0                                         # CameraMotion.ts:11
ZOOM_EPSILON = 0.000001
mode: "gameplay" (integer zoom) | "overview" (fractional)           # CameraZoom.ts:18-24
target_zoom: float = 1.0
following: bool, follow_target: Node2D, fixed_view: Rect/Dict or null
center: Vector2
```

### 4.3 Follow update (every rendered frame, `deltaMs` = frame delta in ms)

```ts
// ResponsiveCameraController.ts:135-161
const target = resolvePhysicsPresentationPosition(this.scene, this.followTarget, this.presentationTarget);
const deadzone = responsiveDeadzoneSize(this.camera.width, this.camera.height);
const desiredCenter = resolveDeadzoneCenter(currentCenter, target,
  deadzone.width / (2 * zoom), deadzone.height / (2 * zoom));
const damping = exponentialDampingFactor(deltaMs);
this.camera.centerOn(lerp(current.x, desired.x, damping), lerp(current.y, desired.y, damping));
```

Godot:
1. Skip if not following, no target, or a pan effect runs ([OUT] respawn pan).
2. `target = player.get_global_transform_interpolated().origin - depth_anchor * player.scale` **[FEET]**: Phaser follows the Arcade sprite position = the slime's sprite centre, interpolated between physics steps (`PhysicsPresentation.ts:30-46`: `current - lastStepDelta * (1 - alpha)`; Godot physics interpolation gives the same). With `depth_anchor (0, 27.56)` the camera looks 27.56 px above the feet.
3. `vp = get_viewport().get_visible_rect().size` (CSS px, see §1.2). Deadzone (screen px):
   `dz_w = clamp(vp.x * 0.18, 128, 224)`, `dz_h = clamp(vp.y * 0.14, 96, 160)` (`CameraMotion.ts:18-23`, written `max(128, min(224, w*0.18))`). Examples: 1280×720 → 224×100.8; 1920×1080 → 224×151.2; 1366×768 → 224×107.52.
4. `half_w = dz_w / (2*zoom)`, `half_h = dz_h / (2*zoom)` (world units). `current = center` (the clamped value from last frame).
5. Deadzone (`CameraMotion.ts:25-41`), per axis independently:
   ```
   desired = current
   if target.x < current.x - half_w: desired.x = target.x + half_w
   elif target.x > current.x + half_w: desired.x = target.x - half_w
   (same for y with half_h)
   ```
6. Damping (`CameraMotion.ts:43-50`): `d = 0 if deltaMs <= 0 or not finite; else 1 - exp(-12 * min(deltaMs, 100) / 1000)` (≈0.1813 at 60 fps, ≈0.0952 at 120 fps).
7. `center = current.lerp(desired, d)` → `center_on(center)` (§4.5 clamps).
8. Update `mode = "gameplay" if is_integer_zoom(zoom) else "overview"` and the deadzone size (for the FPS/debug panel).

Effect: inside the deadzone rectangle (centred on the camera) the player moves without the camera; outside, the camera eases (time constant 1/12 s) to put the player back on the deadzone edge. Camera never overshoots.

### 4.4 Zoom

- Start: `resetZoom()` → `setZoom(1)` (follow mode) (`WorldScene.ts:1488`, `:111-114`).
- `setZoom(z)` (`:68-76`): ignore non-finite or `<= 0`; `target_zoom = z`; apply zoom; **round pixels on iff integer zoom** (`isIntegerCameraZoom: |z - round(z)| < 1e-6`). Godot: `get_viewport().snap_2d_transforms_to_pixel = is_integer_zoom(z)` (and `snap_2d_vertices_to_pixel` the same); verify it does not cause jitter with physics interpolation — if it does, report and leave both off.
- Keys: `zoom_in` (`=`, numpad +) → `step_zoom(-1)`; `zoom_out` (`-`, numpad −) → `step_zoom(+1)` (`WorldScene.ts:2036-2038`; `PlayerInputActions.ts:36-37`). Key repeat is ignored (`event.repeat`) → `event.is_action_pressed("zoom_in", false)`. Works while paused/modals open (handled in `_input`/`_unhandled_input` with PROCESS_MODE_ALWAYS). [OUT] disabled in title mode.
- `nextCameraZoom(current, deltaY)` (`CameraZoom.ts:42-52`): `i = closest index` (ties → lower index: `reduce` keeps the earlier index when `|levels[closest]-v| <= |zoom-v|`); `dir = +1 if deltaY < 0 else -1`; `next = clamp(i + dir, 0, 6)`; return `levels[next]`.
- `stepZoom(deltaY)` (`:78-89`): `deltaY == 0` → false; `next = nextCameraZoom(target_zoom, deltaY)`; `|next - target_zoom| < 1e-6` → false (at an end of the list); `setZoom(next)`; then **re-centre**: fixed → `center_on(fixed centre)`; following → `center_on(target)` immediately (drops the deadzone offset so zoom never pivots on a stale centre). The mouse wheel is **not** zoom (wheel = weapon_next/previous).

### 4.5 `center_on` and camera bounds (Phaser `Camera.centerOn` + `clampX/clampY`)

`WorldScene.ts:1482`: `cameras.main.setBounds(0, 0, width, height)` = `(0,0,4096,4096)` for level-1. Phaser clamps on `centerOn` and again before render, and the clamped value is what the next frame reads as `current`. Port:

```gdscript
func center_on(p: Vector2) -> void:
	if use_bounds:
		var view := get_viewport().get_visible_rect().size / target_zoom   # world units
		var min_c := bounds.position + view * 0.5
		var max_c := Vector2(maxf(min_c.x, bounds.end.x - view.x * 0.5), maxf(min_c.y, bounds.end.y - view.y * 0.5))
		p = Vector2(clampf(p.x, min_c.x, max_c.x), clampf(p.y, min_c.y, max_c.y))
	center = p
	global_position = p
```

When the view is wider/taller than the world, Phaser pins the view's **left/top** edge to the bounds (the `max(...)` collapses to `min_c`), it does not centre. Level-1 at zoom 0.5 on a 1920-px-wide window (3840 world px) hits this.

Bounds are removed in fixed mode (§4.6).

Integer zoom (roundPixels on, §4.4): `Camera.preRender` (`node_modules/phaser/src/cameras/2d/Camera.js:557-571`) floors the scroll (`centre - viewport/2`, screen px) **before** the clamp and stores it back, so the next follow update reads the floored value. Port: when rounding, `p = (p - vp * 0.5).floor() + vp * 0.5` before clamping, and keep that value in `center` (the damped catch-up truncates; moving right/down the camera settles a few px short of the deadzone edge, as in Phaser).

### 4.6 Fixed camera [OUT for level-1, documented]

`cameraMode == "fixed"` (interiors): `holdFixed({centerX: W/2, centerY: H/2, width: W, height: H})` (`:96-103`): stop following, remove bounds, `zoom = min(1, vp.x / W, vp.y / H)` (`fixedCameraZoom`, `CameraZoom.ts:54-55`; non-positive area → 1), centre on the world centre. `refitFixed()` on viewport resize. `resetZoom()` in fixed mode re-holds. `startFollow` is a no-op in fixed mode.

### 4.7 Arrival fade [IN]

`createCamera :1481`: `cameras.main.fadeIn(400, 11, 16, 32)`: the **world camera only** fades (HUD is DOM / UI camera, not faded). Godot: a full-rect `ColorRect` colour `#0b1020` on a CanvasLayer between the world and the HUD (e.g. layer 5; HUD layer 10), alpha 1 → 0 linearly over 400 ms (`AREA_ARRIVE_FADE_MS`, `WorldScene.ts:128`), `mouse_filter = IGNORE`, freed at the end. Leaving (`AREA_LEAVE_FADE_MS = 320`, fade to the same colour) is [OUT] with exits.

### 4.8 Resize

`handleResize :1884-1888`: viewport = new size; `refitFixed()`. The follow deadzone is recomputed every update from the current viewport size, so nothing else is needed. In Godot also re-apply `content_scale_size` (§1.2).

### 4.9 Shake (hook only) [OUT for trial behaviour, expose the API]

Combat/feel uses `gameFeel.play(event)` → `camera.shake(ms, intensity * shakeScale)` (`features/feel/GameFeel.ts:37-50,83-94`; default `screenShake` setting 1). Presets: hit 0/0; critical-hit 80 ms/0.006; combo-finisher 120/0.008; slam 150/0.01; player-hurt 110/0.005; boss-landing 100/0.003; boss-defeated 450/0.012; player-defeated 400/0.012; ground-crack 260/0.012; building-restored 320/0.006. Phaser shake (`Shake.js:242-250`): each frame while running, offset = `uniform(-1,1) * intensity * viewport_size * zoom` (per axis), rounded when roundPixels, applied as `camera.matrix.translate` after the matrix is already scaled by zoom, so the on-screen shift is `intensity * viewport_size * zoom²`. Godot: `Camera2D.offset` (world units) = that same `* zoom` value. Expose `shake(duration_ms: float, intensity: float)` on the camera applying `Camera2D.offset` with that formula so the combat spec can call it; whether the trial calls it is the combat spec's choice.

### 4.10 Title-mode drift [OUT]

Title screen backdrop: centre on `spawn + (160, 120) + (sin(t/60000·2π)·360, 0)` (`WorldScene.ts:161-164,1600-1605`).

---

## 5. NPCs [IN: wandering]

Phaser: `features/scripts/NpcScript.ts`, `features/npcs/NpcWanderPolicy.ts`, `UniversalSceneWorldController.acquireNpcAgent :1940-1960`, `content/npcs/npcWanderGeometry.ts:8-27`, `content/maps/agentAreaGeometry.ts:35-38`.

### 5.1 NPC scene shape (all six identical in structure)

Root `CharacterBody2D` (layer 128 = `npc`, mask 1027 = world|player|water), children `BodyShape` (rectangle), `Visual` Sprite2D (229×229 frames, 6×5 sheet, scale 0.32, origin 0.5,1), `Animation` AnimationPlayer (`domain: physics`, autoplay `idle`), `NpcScript` ScriptNode (`game.npc`). Clips (all loop): `idle`, `walk-down`, `walk-up`, `walk-left`, `walk-right`.

`npc.gd` exports (from the scene JSON):

```gdscript
extends Node
@export var body: CharacterBody2D
@export var visual: Sprite2D
@export var animation: AnimationPlayer
@export var character_id: String = "npc"
@export var npc_definition_id: String = ""   # "" → character_id
@export var wander_speed: float = 0.0        # sanitize: max(0, v)
@export var pause_min_ms: float = 0.0        # max(0, v)
@export var pause_max_ms: float = 0.0        # max(pause_min_ms, v)
```

| NPC (characterId) | npcDefinitionId | wanderSpeed px/s | pauseMinMs | pauseMaxMs | Name tag (displayName, [OUT]) |
|---|---|---|---|---|---|
| village-elder-plop | village-elder-plop | 18 | 3000 | 50000 | Village Elder Plop |
| lili | lili | 28 | 1200 | 2400 | Lili |
| red-slime-boy | red-slime-boy | 38 | 800 | 1800 | Pip |
| yellow-blond-slime-girl | yellow-blond-slime-girl | 24 | 1600 | 2800 | Sunny |
| mossy-scout | level-1-spider-giver | 42 | 2000 | 3000 | Mossy |
| fisherman-slime | fisherman-slime | 30 | 1400 | 3200 | Lily the Fishergirl |

(Values from each `characters/<id>.scene.json` script node; they equal `content/characters/<id>/character.json` `npc` block.)

**Wander body bounds** come from the character catalogue (`content/characters/<id>/character.json` `body`, via `getCharacterPackage(...).character.body`, `UniversalSceneWorldController.ts:1941,1950`) — **not** from the scene's BodyShape, and that file is not converted. Bounds relative to the old root (`resolveEffectiveArcadeBodyBoundsRelativeToAnchor`, `shared/collisionShapes.ts:42-47`): `minX = cx - w/2, maxX = cx + w/2, minY = cy - h/2, maxY = cy + h/2`:

| NPC | body (character.json) | minX | maxX | minY | maxY |
|---|---|---|---|---|---|
| village-elder-plop | ellipse 34×24, offset (0,10) | −17 | 17 | −2 | 22 |
| the other five | ellipse 36×24, offset (0,10) | −18 | 18 | −2 | 22 |

Ask the integrator/converter to copy these bodies into `res://game/data/` (e.g. `character-bodies.json`: `{characterId: {width, height, centerOffsetX, centerOffsetY, shape}}`); until then `npc.gd` may hold a const table citing the source file.

### 5.2 Wander domain (where targets are sampled; old-root coordinates **[FEET]**)

```ts
// npcWanderGeometry.ts:8-27 (margin = NPC_AREA_MARGIN = 8, NpcWanderPolicy.ts:6)
circle: bodyRadius = max(hypot(minX,minY), hypot(minX,maxY), hypot(maxX,minY), hypot(maxX,maxY));
        radius = perimeter.radius - bodyRadius - margin;  // > 0 else no domain
rect:   left = margin - minX; right = margin + maxX; top = margin - minY; bottom = margin + maxY;
        {x: p.x + left, y: p.y + top, w: p.w - left - right, h: p.h - top - bottom}  // w,h > 0 else none
```

Random point (`agentAreaGeometry.ts:35-38`): circle `angle = rand()*2π; dist = sqrt(rand())*r; (cx + cos·dist, cy + sin·dist)`; rect `(x + rand()*w, y + rand()*h)`. `rand()` = `randf()` in [0,1).

level-1 domains: elder circle (525,717) r 44.197; mossy-scout rect x 824 y 668 w 68 h 40; lili circle (435,922) r 27.575; red-slime-boy rect x 585 y 916 w 98 h 30; yellow girl circle (858,947) r 27.575; fisherman rect x 1301 y 728 w 98 h 8.

### 5.3 Agent acquisition

`acquireNpcAgent` (`UniversalSceneWorldController.ts:1940-1960`): the area whose `data.npcInstanceId` matches the NPC's authored instance (Phaser: `sourceNodeId.includes('/<npcInstanceId>/')`). Godot: match the NPC instance root's `metadata/instance_id` (fallback: node name, which equals the instance name). No area → **no agent → the NPC idles forever** (velocity 0, `idle`).

Bootstrap step 7 (§1.2) calls `npc.configure_wander(domain_or_null)` after the world is in the tree (Godot `_ready` runs children-first, so areas cannot be relied on inside the NPC's own `_ready`). Until configured the NPC behaves as "no agent". The first physics tick runs after the bootstrap finishes, so there is no visible difference from Phaser.

Agent wrapper behaviour:
- `random_pause() = pause_min_ms + randf() * max(0, pause_max_ms - pause_min_ms)`.
- initial state = `create_state(random_pause())`.
- after each policy step: if `result.animation == "idle"` and `result.state.phase == "pause"` and `result.state.pause_remaining_ms == 0` → replace state by `create_state(random_pause(), result.state.facing)` (arrival, stuck, or no domain all start a fresh random pause).

### 5.4 Wander state machine (`NpcWanderPolicy.ts:19-86`)

Constants (TS literals): `NPC_AREA_MARGIN 8`, `NPC_TARGET_ARRIVAL_DISTANCE 6`, `NPC_STUCK_PROGRESS_DISTANCE 2`, `NPC_STUCK_SAMPLE_MS 750`.

State: `{phase: "pause"|"move", pause_remaining_ms, target: Vector2 or null, facing: "down"|"up"|"left"|"right", stuck_sample_remaining_ms, previous_distance: float or null}`.

`create_state(pause_ms = 0, facing = "down")`: `phase = "pause" if pause_ms > 0 else "move"`, `pause_remaining_ms = max(0, pause_ms)`, target null, `stuck_sample_remaining_ms = 750`, previous_distance null.

`step(state, position, delta_ms, speed)` → `{state, velocity, animation}`:
1. Sanitize `delta_ms` (non-finite → 0, else ≥ 0) and `speed` (non-finite → 0). `speed <= 0` → return `{create_state(0, facing), 0, "idle"}`.
2. If `phase == "pause"`: `remaining = max(0, pause_remaining_ms - delta_ms)`; state ← `{phase: "pause" if remaining > 0 else "move", pause_remaining_ms: remaining, target: null, stuck_sample_remaining_ms: 750, previous_distance: null}`; if still pause → return `{state, 0, "idle"}`. (A pause that ends this tick falls through and moves in the same tick.)
3. `target = state.target ?? sample(domain)`; no domain → return `{state with phase "pause", pause 0, target null; velocity 0; "idle"}`.
4. `d = target - position`; `distance = |d|`. `distance <= 6` → arrived → `{phase "pause", pause 0, target null, stuck 750, previous null}`, velocity 0, `"idle"`.
5. `facing = (dx < 0 ? left : right) if |dx| >= |dy| else (dy < 0 ? up : down)`.
6. Stuck check: `sample_remaining = stuck_sample_remaining_ms - delta_ms`; `made_progress = previous_distance == null or previous_distance - distance >= 2`. If `sample_remaining <= 0 and not made_progress` → stuck → same result as arrival (pause 0, idle).
7. Move: `v_mag = min(speed, distance / (delta_ms/1000))` if `delta_ms > 0` else `speed` (never overshoots the target in one step). New state `{phase "move", target, facing, stuck_sample_remaining_ms: sample_remaining if sample_remaining > 0 else 750, previous_distance: (previous_distance ?? distance) if sample_remaining > 0 else distance}`; `velocity = d / distance * v_mag`; animation `"walk-" + facing`.

(Progress is measured once per 750 ms window: `previous_distance` is the distance at the window's start; ≥ 2 px closer, or a fresh window, counts as progress.)

### 5.5 `npc.gd` per physics tick (`NpcScript.ts:276-291`)

```gdscript
func _physics_process(delta: float) -> void:
	if _paused() or not _has_agent:
		body.velocity = Vector2.ZERO
		_play("idle")
	else:
		var pos := body.global_position - _anchor * body.scale   # [FEET] old root position
		var r := _step(_state, pos, delta * 1000.0, wander_speed)
		_state = r.state
		body.velocity = r.velocity
		_play(r.animation)
	ArcadeMover.move(body, delta)   # Phaser's Arcade step moves the body after scripts; here the NPC script owns the move
```

- `_anchor = body.get_meta("depth_anchor", Vector2.ZERO)`; the target and domain stay in old-root space, the direction/velocity is identical in both spaces.
- Who moves the body must match the player/enemy specs' rule (one mover call per body, `ArcadeMover.move`). The NPC root has no other script, so `npc.gd` moves it.
- `_enter_tree`/`_ready` (`:253-274`): resolve refs, add to groups `npc` and `interactable`, `_play("idle")`. `_exit_tree`: velocity 0.
- `_play(id)` (`:353-359`): skip if `animation.current_animation == id`; skip if `not animation.has_animation(id)`; else `animation.play(id)`.
- `_paused() = simulation_paused or interaction_locks > 0` [OUT: modals/dialogue set these; keep the two fields so dialogue can use them later: `set_simulation_paused(bool)` zeroes velocity; `acquire_interaction_lock() -> Callable` (increments, velocity 0, `idle`, emits signal `interaction_lock_changed({locked, lockCount})`, returned callable decrements once)].
- `get_position()` returns the old root position (other systems such as quest NPC distance [OUT] use it).

Collisions: NPC mask world|player|water; Godot CharacterBody2D vs CharacterBody2D (player) both stop, comparable to Arcade's pair collider (`infrastructure/scenes/PhaserNodeContext.ts:283-300`). A stuck NPC (pressed by the player) triggers the stuck path after ≤ 750 ms and picks a new target after a pause.

### 5.6 NPC extras [OUT]

Name tags are ported (2026-10-05, `game/ui/npc_name_tags.gd`); the rest stays OUT.

- Name tags (`features/npcs/NpcNameTags.ts`): label = displayName (table §5.1), 14 px, colour `#f5f7ff`, stroke `#081022` 4 px, origin (0.5,1) at `(sprite.x, sprite.y - displayHeight*originY - 2)` = old root y − 73.28 − 2 **[FEET]**; quest markers bob 3 px / 900 ms, 18 px above the tag. Nice for "looks like Phaser" if time allows.
- Dialogue/quests/interaction (QuestNpcController, `registerNpcPlacement :1962-1987`), story variant `chapter-1-villagers` (flag `chapter-1-complete`, unset in the trial → villagers present; the unported placeholder leaves them in, which is correct).

---

## 6. HUD [IN: minimal]

Phaser: `content/scenes/authored/ui/hud.scene.json`, `ui/health-bar.scene.json`, `features/ui/HudSurfacePort.ts`, `features/ui/PlayerHealthSurfacePort.ts`, `features/scripts/ui/UiSurfaceScript.ts`, styles in `src/styles.css:3191-3204, 3384-3394, 3786-3798`, theme `resources/ui/field-kit.theme.resource.json`.

### 6.1 Data contract

The HUD reads player state (Phaser `core/GameState.ts:177-258`; owned by the player/combat spec in Godot): `hp`, `max_hp = player.stats.maxHp (100) + gooHearts * player.gooHeart.maxHpBonus (10)`, `energy`, `max_energy = player.stats.maxEnergy (100)`, `coins` (new run 50, `InitialRun.ts:15`), all from `game-constants.json` → `player.stats`. Signals (Phaser events): `hp_changed({hp, maxHp, delta})`, `energy_changed({energy, maxEnergy, delta})`, `coins_changed`. The HUD subscribes and also reads a snapshot once on ready. If no stats autoload exists yet, the HUD must still render with the new-run defaults (hp 100/100, energy 100/100, coins 50).

### 6.2 Top-left HUD (`ui.hud`)

Phaser mechanism: `UiSurfaceScript` (`game.ui-surface`) pulls `snapshot('hud')` on enter and on every `hp/energy/coins` change, and applies `bindings` (`[{nodePath, property, model}]`, node paths relative to the script node) — `../Coins.text ← coinsLabel`, `../Health.value ← hp`, `../Health.max ← maxHp`, `../Energy.value ← energy`, `../Energy.max ← maxEnergy`. A port of `ui_surface.gd` belongs to Phase 3; for the trial either (a) instance the converted `res://game/scenes/ui/hud.tscn` on a CanvasLayer (layer 10) and drive the three nodes from `hud.gd`, or (b) build the same three controls by hand. Target look (CSS px):

- Root: position (16, 16), size 284 × 68 (`offsetMin [16,16]`, `offsetMax [300,84]`), no background/border, text shadow `0 1px 2px #081022, 0 0 6px #081022d9` (approximate with Label `font_shadow_color #081022`, offset (0,1), outline 0).
- `Coins` Label: y 0–22, full width, text `"Coins " + format(coins)` (`formatHudCount`: `<10000` → integer with `,` thousands separators; `<1e6` → `"%.1fk" % min(999.9, n/1000)`; `<1e9` → `"%.1fm"`; else `"999m+"`; negative/fraction → `max(0, floor(n))`), font 12 px bold, colour warning `#ffd277`.
- `Health` bar: y 28–46 (18 px), full width; label `HP`, tone danger fill `#ff6f88`; text `"HP %d / %d" % [ceil(hp), ceil(max_hp)]`, 11 px tabular, colour `#f5f7ff`, left-aligned with 6 px padding (`padding: 2px 6px`).
- `Energy` bar: y 50–68; label `Energy`, tone warning fill `#ffd277`; text `"Energy %d / %d"`.
- Bar style (`.game-ui--hud .scene-control--progressbar`): pill (corner radius 9), border 1 px `rgba(245,247,255,0.42)`, outer 1 px `#0810224d`, transparent background, fill width = `clamp(value/max, 0, 1)` of the inner width. In Godot: `ProgressBar` with `show_percentage = false`, StyleBoxFlat `fill` (tone colour, radius 9) and `background` (transparent, border), plus a child Label for the text; or a small custom `_draw()`.
- `mouse_filter = IGNORE` on all HUD nodes (Phaser HUD never takes clicks).

### 6.3 Floating player health bar (`ui.health-bar`) [IN, small]

`PlayerHealthSurfacePort.ts:9-57`: 56 × 8 bar, shown for `SHOW_MS = 1800` ms after any `hp_changed` (and on `flashPlayerHealthBar()` when the player is hit, `WorldScene.ts:1900`), hidden when the player is dead/inactive. Clock = real time (`scene.time.now`; keeps running while paused) → `Time.get_ticks_msec()`. Each frame:

```
anchor_world = phaser_pos(player) + (0, -48)            # [FEET] Phaser: (player.x, player.y - 48), player.y = sprite centre
screen = get_viewport().get_canvas_transform() * anchor_world
left = round(screen.x - 28); top = round(screen.y - 4)  # rect (left, top)-(left+56, top+8)
ratio = hp / max(1, max_hp); tone = danger (#ff6f88) if ratio <= 0.25, warning (#ffd277) if <= 0.5, else accent (#86f0c3)
```

Style: no text, padding 0, corner radius 4, border 1 px `#3b5c78` at 68 % alpha, background `#182b46`, fill = tone colour × `clamp(hp/max_hp,0,1)`. Uses the Arcade sprite position (not interpolated) in Phaser; using the interpolated transform in Godot is fine. CanvasLayer layer 10.

### 6.4 HUD parts [OUT]

Weapon hotbar, ability bar, boss bar, area title card, floating text, inventory/chest/crafting/quest/dialogue/world map/minimap, shell menus, control hints, player name tag ("bob", 14 px at old y − 56 **[FEET]**, `WorldScene.ts:1449-1458`, `PlayerController.ts:49`) — the name tag is a world label, may be added by the player spec.

---

## 7. FPS readout [IN]

Phaser has only a dev overlay (`dev/RenderingDiagnostics.ts`, `?renderDebug=1`): fixed panel at (10,10), padding 9/11 px, border 1 px `#72d8ff`, background `rgba(8,16,34,0.9)`, text `#d7e7f8`, 11 px monospace, refreshed every `UPDATE_INTERVAL_MS = 200` ms, line `actual fps <n.1>` (Phaser `loop.actualFps`, a 1-s smoothed average) plus camera zoom/mode/deadzone/scroll.

Trial: `fps_readout.gd` on its own CanvasLayer (layer 100), **top-right** (the HUD occupies the top-left), `mouse_filter IGNORE`, same panel style, refreshed every 200 ms with:
- `fps %.1f` = `Engine.get_frames_per_second()`
- `frame ms %.2f` (mean `_process` delta over the last 200 ms window) and `worst ms` (max in window)
- `zoom %.3f  mode gameplay|overview`, `deadzone W x H` (from the camera state)
- `draw calls` = `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)`, `objects` = `RENDER_TOTAL_OBJECTS_IN_FRAME`, `nodes` = `OBJECT_NODE_COUNT`

Visible by default in trial builds (it is the 60-fps test instrument); toggle with F3 (raw `KEY_F3` in `_unhandled_input`, or ask the integrator for an action).

---

## 8. Exits, doors and other world behaviour — recorded for later phases

**Ported since 2026-10-05:** world exits and area travel (`world_exit.gd`, `Main.request_exit` / `travel_to`, `game/world/area_travel.gd`, run state in the `RunState` autoload). Phaser reloads the page with a save handoff; the port keeps main and rebuilds the world in place, carrying the run in `RunState`. Doors and the rest below follow in their own specs (`interaction.md`, `world-objects.md`).

- **World exit** (`features/scripts/WorldExitScript.ts`): ScriptNode under an `Area2D` (level-1 `exit-1` at (3552,576), rect 64×128, layer 512, mask 130 = player|npc, monitoring). Properties `mapId`, `exitId`, `targetAreaId "gloop-forest"`, `entry "west"`, `gate {id "level-1-east-verdant-gate", requiredItemId "green-key", consumeOnUnlock true, lockedMessage "The eastern gate needs a green key."}`, `arrivalGraceMs` (default `game-constants.json worldNavigation.edgeTransitionGraceMs` = 650). Level-triggered: on `body_entered` and on every physics tick for every overlapping character body, after the grace period and until queued, call the exit service; only the player body counts (`UniversalSceneWorldController.ts:648-655`). `WorldScene.requestAuthoredExit` (`:1018-1067`): ignore if wrong map or already transitioning; gate locked and no key → floating text (throttled 900 ms) + `blocked`; key → unlock (consumes), "The Verdant Gate unlocks!"; then `transitionTo`: stop player, music fade + camera fade out 320 ms to `#0b1020`, then navigate (Phaser reloads the page with a save handoff). Emits `navigation_resolved(result)`. In the trial the exit stays the unported placeholder (inert).
- **Doors** (`DoorScript`, `doorCandidate :919-960`): interaction candidate when the player's old-root position is within `interactRadius` (home-door 90, default 96) of the door node; prompt "Enter house"; execute → `requestExit({targetDoorId})`; arrival at the door's `arrival` child.
- Arrival through an exit/door: spawn anchor = door arrival ?? entry edge marker ?? spawn marker, then `findSpawnPoint` (tile-centre search, §2.2).
- Saves/restored location, respawn (camera `pan(pos, 350 ms, 'Power2')` then follow), title mode, music director (world `MusicPlayer`/`Ambience` AudioStreamPlayers autoplay in the converted scene; Phaser's MusicDirector handles fades/boss music and audio unlock; ported since 2026-10-05, [audio.md](audio.md)), minimap, quests, dialogue, occlusion silhouettes (dropped), interaction router, collectibles/resources/chests/furniture, enemy spawn population (enemy spec), boss camp `encounter.level-1-fatty-camp`, fixed-camera interiors, hit-stop.

---

## 9. Checklist for the engineer

1. Player spawns with feet at (640, 731.56); camera starts centred on (640, 704) clamped to bounds (at 1280×720 zoom 1: centre (640, 704), no clamp needed since 640 ≥ 640 and 704 ≥ 360).
2. Walking: the camera stays still while the slime is within ±112 × ±50.4 px of the camera centre (1280×720, zoom 1), then follows smoothly; it never shows outside (0,0)-(4096,4096).
3. `=`/`-` step through 0.5 … 1.25; each step snaps the camera onto the slime; at 1.25 `=` does nothing.
4. The six NPCs idle, then walk inside their areas with `walk-<dir>` clips at their own speeds and pause with `idle`; the elder can pause up to 50 s.
5. HUD top-left shows `Coins 50`, `HP 100 / 100`, `Energy 100 / 100`; a hit shows the 56×8 bar above the slime for 1.8 s.
6. FPS panel top-right updates 5×/s.
7. The slime cannot leave the 4096×4096 world (bounds walls on layer 1).
