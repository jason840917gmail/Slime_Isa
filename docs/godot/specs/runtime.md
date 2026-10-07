# Runtime node semantics: converter reference (Phaser scene JSON → Godot 4.7.2)

This file is for the authors of `scripts/godot/convert-scenes.mjs` and of the helper scripts in `godot/game/runtime/`. For every node type, property and resource kind it gives the exact Phaser runtime behaviour and the Godot 4.7 mapping. Section 1 lists where the shared conventions file (`docs/godot/CONVENTIONS.md`) is wrong or leaves something open. The rest of this file assumes those corrections.

Sources read: `src/game/runtime/scene/**`, `src/game/infrastructure/phaser-nodes/**` (including `ui/`), `infrastructure/scenes/PhaserUniversalSceneRuntime.ts`, `presentation/WorldDepth.ts`, `content/scenes/{types,propertyDescriptors,validation,identifiers}.ts`, `scene.schema.json`, `resources/**`, `features/world/GroundSheet*.ts`, `shared/animation/{clock,timeline,types}.ts`, `styles.css` (the scene-control rules), `infrastructure/assets/AssetLoader.ts` and `config.ts`.

Usage numbers come from a survey of all 1,186 `*.scene.json` files and the 2 `*.resource.json` files (the survey scripts were throwaway). Godot defaults and behaviours marked **[probed]** were checked by running scripts in the Godot 4.7.2 binary, in a throwaway scratch project. Nothing in `godot/` was touched.

---

## 1. Corrections and open points in the conventions

Each item is marked **WRONG** (the conventions say something the code contradicts), **OPEN** (the conventions leave it undefined) or **RISK**.

1. **WRONG: Container → VBox/HBoxContainer.** No authored Container sets `direction`, `gap`, `padding`, `align` or `justify` (all 21 use the defaults). Also, every scene control is rendered `position:absolute` at the rectangle its anchors and offsets give inside the parent element (`ControlPresentationAdapter.synchronize`), so flex properties never move scene controls. All 166 children of containers carry explicit anchors and offsets. **Map Container → plain `Control`** (or `Panel` when it needs a styled background) and keep each child's anchors and offsets. A BoxContainer would override those child rects and break every layout. GridContainer → `Control` for the same reason (none are authored). ScrollContainer needs special handling (§4.15).
2. **WRONG: `texture_filter = NEAREST` when `render.pixelArt`.** No runtime code reads `render.pixelArt`. The Phaser game config sets `pixelArt: false` with `roundPixels: true`, so **every texture is drawn with LINEAR filtering and no mipmaps**. Nearest filtering would visibly alias the 2048-px player sheet, which is drawn at scale 0.28125. Leave `texture_filter` as inherit (the Godot project default is Linear **[probed]**). For `roundPixels`, consider `rendering/2d/snap/snap_2d_transforms_to_pixel = true` (integrator decision).
3. **WRONG: tile collision is "full-cell polygons".** Phaser merges same-tile solid cells into rectangles (horizontal runs per row, then equal runs stacked: `mergeCellRectangles`) and applies the tile's `inset` **only to the outer edges** of each merged rectangle. The default inset is `{left:6,right:6,top:8,bottom:8}`; `water` and `deep-water` use 10 on every side, and `rock-wall` uses 4/4/6/2. Per-cell TileSet polygons cannot express "inset only on the outer edge". **Generate `StaticBody2D` + `RectangleShape2D` children of the TileMapLayer, one per merged rectangle**, and turn off TileSet physics (§4.9). Full cells would put water edges 10 px further out than in Phaser. (Water no longer follows this since 2026-10-06: shallow water is walkable and deep water collides through a full-cell square on its tiles, see [water.md](water.md); rock wall keeps the merged bodies.)
4. **WRONG: sprite-sheet frame size from the resource.** Phaser loads every spritesheet from `asset/assets.json` `source.frame.{w,h}` (`AssetLoader.queueAssets`). The resource's `frameWidth`, `frameHeight` and `frameCount` are not used at run time and are wrong for 2 resources (`enemy.projectile.spider-web` is 24×24 in the resource but 40×40 in the asset; `enemy.projectile.worm-arrow` is 16×10 vs 40×40). Use `hframes = frame.cols`, `vframes = frame.rows`, and frame size `frame.w × frame.h` from assets.json. Every sheet is an exact multiple of its frame (0 exceptions).
5. **WRONG: `visualOffset` and `depthOffset` tracks are "dropped".** `visualOffset` is animatable (numeric) and is animated by 2 tracks (tree-autumn idle and leaf-fall). Convert those keys to `offset` keys with `offset = value − origin·frameSize`. `depthOffset` tracks (100) can be dropped, and §6.4 shows why that is safe for every authored value. The conventions give no reason.
6. **WRONG/OPEN: animation looping.** Godot value tracks default to `loop_wrap = true` **[probed]**, which interpolates from the last key back to the first key across the loop seam. Phaser never does: it holds the last key until frame 0. 13 loop clips have a numeric last key that differs from the first key. Write `tracks/N/loop_wrap = false` on every track. `loopMode: ping-pong` (11 clips, all `frame` tracks only) does not match Godot's `LOOP_PINGPONG` frame timing (Phaser shows each end frame once per cycle), so bake it into a wrap loop of `2N−2` frames (§6.4).
7. **WRONG/OPEN: animation length.** Phaser's timeline has `N = max(1, round(durationSeconds·fps))` integer frames. A non-loop clip completes at `N/fps` and a loop cycle is `N/fps` long. Use `length = N/fps`, not `durationSeconds`: they differ for 2 clips (`player-slime attack-1` 0.42 s at 12 fps gives 5 frames = 0.4167 s; `village-elder-plop walk-down` 0.86 s at 8 fps gives 7 frames = 0.875 s).
8. **OPEN (RISK): stopping or switching clips.** Phaser `play()` and `stop()` restore the **baseline** (the value captured when the clip started) of every property the outgoing clip animated. A non-loop clip that completes naturally keeps its last values. Godot never restores anything **[probed]**: a property animated by clip A keeps its value after `play("B")` or `stop()`. Phaser `play(name)` also always restarts, even for the clip that is already playing, while Godot `play(name)` on the current clip continues **[probed]**. The helper `animation_player.gd` must provide `play_clip(name)` and `stop_clip()` with Phaser semantics (§6.5). Weapon sprites depend on this: their base alpha is 0, and an interrupted swing must hide them again.
9. **OPEN: script inheritance.** Script descriptors inherit: `game.player`, `game.npc` and `game.enemy` extend `game.character`; `game.fatty` and `game.matron` extend `game.enemy`; `game.resource-node` extends `game.destructible`. Inherited properties (`body`, `visual`, `animation`, …) are authored on the leaf node. The converter must follow the GDScript `extends "res://game/scripts/<base>.gd"` chain when it collects the declared `@export`s. Reading only the leaf `.gd` would drop `body`, `visual` and `animation` from player, enemy and npc nodes.
10. **WRONG: "handlers take exactly one argument".** 21 `game.ui-surface` handlers take no payload, and the same handler is connected both to Godot signals with 0 arguments (`Button.pressed`) and to signals with 1 argument (`ItemList.item_selected(index)`, `HSlider.value_changed(value)`). Rule: **every handler and cue method declares one optional parameter**, `func on_x(_payload: Variant = null) -> void`. That accepts every connection shape.
11. **RISK: handler names that collide with Object methods.** The `game.story-flag` and `game.story-variant` scripts declare a handler named `set` (used once, in `worlds/playground`). A GDScript `func set(...)` collides with `Object.set`. The converter needs a rename table `{ set → on_set }` that it applies both to the connection's `method=` and to the expected method name. It already does this for `play` and `stop` → `play_cue` and `stop_cue`. No authored signal id collides with a Node signal.
12. **WRONG: default values.** The scene resolver fills descriptor defaults before construction, and several differ from Godot's defaults **[probed]**: audio `polyphony` 4 (Godot `max_polyphony` 1); AudioStreamPlayer2D `maxDistance` 800 (Godot 2000) and `panDistance` 400 (no Godot equivalent); Area2D `collisionMask` 2047, all defined layers (Godot 1); CharacterBody2D `motion_mode` must be FLOATING (Godot default GROUNDED; Phaser is top-down); ProgressBar `show_percentage` must be false (Godot default true); `AudioStreamRandomizer.playback_mode` must be `PLAYBACK_RANDOM = 1` (Godot default `RANDOM_NO_REPEATS = 0`, while Phaser picks uniformly with repeats). Write descriptor defaults explicitly wherever Godot's default differs (full table in §2.4).
13. **OPEN: pause and audio.** Phaser audio nodes and all Controls keep processing while the tree is paused (audio sets `processWhenPaused = true`; Controls default `processWhenPaused = true`). A Godot AudioStreamPlayer with `process_mode` INHERIT pauses its stream when the tree pauses. Set `process_mode = PROCESS_MODE_ALWAYS` (3) on every audio player node and on every Control with `processWhenPaused` true (all of them).
14. **OPEN: Control mouse filtering.** HTML scene controls have `pointer-events: none` except buttons, item-list entries, sliders and ModalRoots. Godot `Control`, `Panel` and `ProgressBar` default to `MOUSE_FILTER_STOP` **[probed]** and would swallow the player's attack clicks over HUD panels. Set `mouse_filter = IGNORE` (2) on Control (Container), Label, ProgressBar and TextureRect, and STOP on Button, ItemList, HSlider and ModalRoot. Buttons, ItemLists and Sliders outside a ModalRoot also need `focus_mode = FOCUS_NONE`: the HTML gives them `tabIndex = -1` so that arrow keys and Space keep driving the game.
15. **WRONG: depth-band names and values.** The band is `overhead-artwork`, not `overhead`. Only `world-entities` (1,126 sprites) and `ground-decals` (166 sprites, plus 2 effect layers and 14 explicit-depth sprites) are authored. **Explicit depth is not "dropped"**: the 14 water-life fish sprites use `depthMode: explicit` with `depth` 2 000 000 000.55/.6/.65. That is the ground-decals band, *below* every world-sorted decal. Map them to `z_index = -2` (§5.3). The 13 sprites with `depthBounds` sort by a line 3–37 px **above** their node origin. Shift them (§5.4) or they sort differently from Phaser.
16. **OPEN: `.. ` bindings and nested track paths.** Track `binding` is a node path relative to the **AnimationPlayer** (`player.get_node(binding)`). `..` targets the player's parent, the scene root, on 2 weapon clips. `../AttackArea/right--primary` reaches grandchildren. With Godot `root_node = ".."` the track path is `binding` with its leading `../` removed (`..` becomes `.`). Root-level keys shift only when the targeted node is a *direct child* of a re-anchored root.
17. **OPEN: world instance positions of re-anchored scenes.** The 13 character instances placed in worlds override the root `position` (the old body centre). The converter must write `position + depthAnchor·scale` into the Godot instance node. This is the same rule the conventions give for runtime spawning, but it also applies to authored overrides.
18. **RISK: ellipse bodies.** Arcade has no ellipse body, so the 4 CharacterBody2D ellipses (fatty, matron, orb-weaver, slime-spider) block as their **axis-aligned bounding rectangle** (`2rx × 2ry`). Only Area2D overlap tests use the true ellipse. Recommendation: on PhysicsBody2D parents emit `RectangleShape2D(2rx, 2ry)`; on Area2D parents emit a convex polygon (32 segments).
19. **RISK: sectors.** Only `weapons/basic-sword` uses sectors (8 shapes, all convex: arc 2.217 rad < π, innerRadius 0). Emit a `ConvexPolygonShape2D`. For a sector that is concave (arc > π or innerRadius > 0; none authored), use a `CollisionPolygon2D` with `build_mode = SOLIDS`. Build the polygon at angle 0 and put the effective angle (`angleRad` property or resource value) into the node's `rotation`. This is valid because Phaser forbids rotated shape nodes and rotated ancestors, and it keeps a future `angleRad` animation mappable to `rotation`. No `angleRad` is authored or animated today.
20. **RISK: signal payloads.** Built-in Phaser signals carry objects (`PhysicsContact`, `{index,item}`, `{control,value}`). Godot's carry nodes or ints (§7.1). Handlers that are ported by hand must be written against the Godot arguments.
21. **OPEN: `animation_event` dictionary.** Add `animation: String` (the clip name) and `at: int` to the `{event_id, payload, gameplay}` keys, to match Phaser's `AnimationEventEmission {animation, event}`. Today **no script consumes `animation_event`**: only 3 events are authored (worm-swordsman `attack-side` and fatty `contact-hop`: `hitbox-activated` and `hitbox-deactivated`).
22. **RISK: script property named `metadata`.** `game.world-definition.metadata` converts to an export called `metadata`. Lines beginning `metadata/` are meta entries in `.tscn`. A bare `metadata = {…}` should parse as a property, but rename it to `world_metadata` to be safe, with a converter key map. No other script property collides with a Node or Object member.
23. **Confirmed OK (no change needed).** Sibling names are unique (Phaser throws on duplicates, and the survey found 0). No node name contains `. : @ / " %`. Overrides only ever use an empty `sourceInstancePath`, so no nested-instance overrides exist. No authored Camera2D, font resource, GridContainer or `Control` exists. All tile layers use `tileSize` 64 at position (0,0) with `seed` ≤ 3 421 253 882.

---

## 2. Scene document → `.tscn`

### 2.1 Structure

- `SceneDocument { version:1, sceneId, rootNodeId, nodes[], instances[], connections?[], subresources?[] }`. Exactly one node has `parentId: null`.
- **Children**: the children of node P are `nodes[parentId=P] ∪ instances[parentNodeId=P]`, sorted by `order` (validation guarantees the dense sequence 0..n-1 across both lists). Emit them in that order; Godot child index equals file order. Phaser processes, enters and readies nodes in preorder and readies them in postorder, which matches Godot.
- **Names**: node `name`, or instance `name` for an instance root. Phaser enforces unique sibling names and forbids empty, `.`, `..` and `/` in names. Keep the conventions' sanitizer as a guard; it never fires today.
- **Ids**: authored `id` and `instanceId` match `^[a-z0-9]+(?:[._-][a-z0-9]+)*$`. Runtime id = `encodeURIComponent` of `namespace/…instancePath…/nodeId`. Gameplay looks instances up by `instanceId` (for example `world-area.data.npcInstanceId = "level-1-npc-lili"`), so write `metadata/instance_id` on every instance root (already in the conventions). Optionally also write `metadata/node_id` on non-instance nodes. No script reads authored node ids at run time today; references are resolved for them.
- `persistenceKey` (9,250 instances) → `metadata/persistence_key` on the instance root. A runtime spawn can also pass a persistence key, which Godot gameplay code sets the same way.

### 2.2 Instances and overrides

- An instance becomes `[node name="<instance.name>" parent="…" instance=ExtResource(<scene>)]`, with `metadata/instance_id` and `metadata/persistence_key` set on that line.
- Override `{ sourceInstancePath: [], sourceNodeId, property, value }` (23,344 authored; `sourceInstancePath` is always empty):
  - `sourceNodeId` = the instanced scene's root → properties go on the instance node itself (`position` 5,756 on Node2D roots and 3,483 on StaticBody2D roots; 13 on CharacterBody2D roots, which need the +anchor rule).
  - otherwise → a `[node name="<child name>" parent="<path to instance>/<path inside the scene>"]` entry with the converted property. The properties and counts: Sprite2D `scale` 2,989, `flipX` 1,590, `visualOffset` 1,350; ScriptNode `mapId`, `instanceId`, `initialContents`, `doorId`, … 4,099. Emit `[editable path="<instance path>"]` once per instance that has sub-node overrides, so the editor shows them. Godot applies the stored properties either way.
  - The value converts as described for that node type and property. A Sprite2D `visualOffset` override needs the child's `origin` and frame size **from the instanced scene** (`offset = vo − origin·frameSize`).
- Phaser rules worth keeping as converter checks: an override targets a serialized, overridable descriptor property, and a stale override (target missing) is an error. Node-reference overrides would resolve in the scope of the scene that authored the override (`propertyScopes`), but none are authored.

### 2.3 Connections

- `{ source:{nodeId, instancePath?}, signal, target:{nodeId, instancePath?}, handler }` → `[connection signal="<signal>" from="<path>" to="<path>" method="<method>"]`. Paths are relative to the scene root, and an `instancePath` walks into instances by instance name. One connection uses a source inside an instance: `worlds/playground`, `playground-end-card-plate/script.pressed → story-flag.set`.
- Method mapping: `play` → `play_cue`, `stop` → `stop_cue` (audio targets), `set` → `on_set`. Every other handler id is unchanged.
- Phaser emits synchronously, in connection order, and only while the source and target are both `ready` and inside the tree. Godot behaves the same way for the purposes of the conversion.

### 2.4 Defaults the resolver applies (write them when Godot's default differs)

| Type | Property | Phaser default | Godot default | Action |
|---|---|---|---|---|
| Node2D | position, scale, rotation, visible | (0,0), (1,1), 0, true | same | none |
| Sprite2D | origin | (0.5, 0.5) | n/a | always compute `offset` (§4.3) |
| Sprite2D | frame, alpha, tint, flipX/Y | 0, 1, #ffffff, false | same | none |
| PhysicsBody2D | collisionLayer, collisionMask | 1, 1 | 1, 1 | none |
| CharacterBody2D | (motion) | top-down | GROUNDED | write `motion_mode = 1` |
| Area2D | collisionLayer, collisionMask | 1, **2047** | 1, 1 | write the mask (all 208 authored anyway) |
| Area2D | monitoring, monitorable | true, true | true, true | none |
| CollisionShape2D | disabled | false | false | none |
| AnimationPlayer | domain | `render` | IDLE | physics → `callback_mode_process = 0` |
| Audio* | volume, pitch, bus | 1, 1, effects | 0 dB, 1, Master | always write `bus` |
| Audio* | polyphony | **4** | 1 | always write `max_polyphony` |
| Audio* | minIntervalMs, pitchRandomness, payloadFilter | 0, 0, "" | n/a | helper exports |
| AudioStreamPlayer2D | maxDistance, panDistance | **800**, **400** | 2000, n/a | write `max_distance`; helper handles pan |
| TileMapLayer2D | tileSize, seed, depth, collisionLayer | 64, 0, 0, 1 | n/a | converter input |
| Control | anchors and offsets | all 0 | all 0 | none |
| Control | processWhenPaused | **true** | INHERIT | `process_mode = 3` |
| Control | inputPriority, zIndex | 1000, 0 | n/a | see §4.14 |
| Label | fontSize, fontWeight, textAlign, tone | 14, 400, left, default | theme | theme overrides |
| Button | textAlign | **center** | center | none |
| ProgressBar | max, tone, showValue | 1, accent, false | 100, n/a, `show_percentage` true | write `max_value`, `show_percentage = false` |
| Slider | min, max, step, value | 0, 1, 0.05, 0 | 0, 100, 1, 0 | write all four |
| ItemList | columns, gap, selectedIndex | 1, 8, −1 | n/a | custom script |
| ModalRoot | open | false | n/a | `visible = open` |

For **script nodes**, the resolver also fills script-descriptor defaults (for example `enemy.maxHealth = 1` and `door.interactRadius = 96`). Either write the resolved value (descriptor default overlaid with the authored value) for every declared export, or require the GDScript defaults to equal the descriptor defaults. The descriptors are loadable from Node: `loadSceneTooling()` in `scripts/lib/scene-conversion/load-scene-tooling.mjs` provides `createGameDescriptorRegistry()` and `propertiesForNode(type, scriptId, registry)`, which return the inherited chain with `value.kind` and `defaultValue`. Use those kinds instead of guessing from the value's shape.

---

## 3. Node references and script properties

- A property whose descriptor kind is `node-reference` has the value `{nodeId, instancePath?}`. It resolves to key `[...scope, ...(instancePath ?? []), nodeId]`, where `scope` is the instance path of the scene that authored the value (the node's own scene in every authored case). Emit a `NodePath` **relative to the script node**, computed in the converted tree (instance roots are named by instance name).
  - 53 reference properties are authored. One uses an `instancePath`: `game.boss-camp.guardedChest` → a node inside an instance in the encounter scene.
  - Phaser treats a reference whose target is outside the tree or not yet `ready` as `undefined` (`NodeReference.resolve`). In Godot, use `get_node_or_null`.
  - Capability filters from the descriptors are validation only: `area`, `character-body`, `collision-shape`.
- Kinds and encoding (from the descriptors: string 70, number 69, node-reference 38, json 22, boolean 8, enum 4, vector2 3, scene-reference 1):
  - `vector2` → `Vector2` (only `bed.sleepPoint`, `bed.wakePoint` and `boss-camp.spawn`; all are Phaser positions, see the anchor note in §8).
  - `scene-reference` → `String` scene id (`boss-camp.bossScene = {sceneId}`, marked `dynamic`).
  - `json` → `Dictionary` or `Array`, with keys kept verbatim (camelCase or kebab-case, for example `"iron-ore"`). Two-number arrays *inside* json stay arrays.
  - `enum` and `string` → `String`; `number` → `float`, or `int` if the GDScript export is int; `boolean` → `bool`.
- Snake-case rule: `key.replace(/([a-z0-9])([A-Z])/g,'$1_$2').toLowerCase()`. No authored key contains digit-to-capital or acronym runs that would make this ambiguous. Rename `metadata` → `world_metadata` (item 22 of §1).
- `game.ui-surface.bindings` is a JSON array of `{nodePath, property, model}`. `nodePath` is relative to the script node (`..`, `../Coins`) and is valid in Godot as is, because names are kept. `property` uses **Phaser** property names. The gameplay port needs this mapping:

| Phaser binding property (count) | Godot |
|---|---|
| Label/Button `text` (77) | `text` (for an unwrapped label, Phaser collapses newlines, see §4.16) |
| Button/Slider `disabled` (32) | `disabled` / `editable = !disabled` |
| Label `color` (8) | `add_theme_color_override("font_color", …)` |
| `visible` (32) | `visible` |
| Container `opacity` (3) | `modulate.a` |
| `offsetMin` / `offsetMax` (32) | (`offset_left`, `offset_top`) / (`offset_right`, `offset_bottom`) |
| ProgressBar `value` / `max` / `tone` (9) | `value` / `max_value` / fill stylebox colour |
| ItemList `items` / `selectedIndex` (15) | custom list script |
| ModalRoot `open` (15) | `visible` (plus modal focus) |
| Label `fontSize` (1) | `add_theme_font_size_override("font_size", …)` |
| Container `scale` (1) | `scale` with `pivot_offset = size/2` (CSS `scale` scales around the centre) |
| Slider `value` / `label` (8) | `HSlider.set_value_no_signal` / caption Label `text` |

---

## 4. Node types

### 4.1 Node → `Node`
No properties. `ScriptNode` (326 nodes, 32 script ids) → `Node` with the script described in the conventions. Phaser constructs it from the script registry, with the exported properties frozen and services injected (`service(id)`), and enforces `exclusiveCapabilities` between sibling scripts (a validation detail).

### 4.2 Node2D → `Node2D`
- `position` `[x,y]` → `Vector2`. `rotation` (radians) → `rotation`. `scale` `[x,y]` → `Vector2`; validation requires it to be positive (negative mirroring is forbidden). `visible` → `visible`.
- Transform composition: Phaser's `get_global_transform` is `parent.pos + R(parent.rot)·(parent.scale ∘ local.pos)`, rotation adds, scale multiplies component-wise. That is Godot's composition without skew. Equivalent for every authored case (no rotated ancestors under scaled ones).
- **Visibility does NOT inherit in Phaser.** `Sprite2DNode.syncPresentation` shows a sprite according to *its own* `visible` only; a hidden parent Node2D does not hide child sprites. In Godot it does. No authored Node2D has `visible: false` (the only `visible` animation keys are `true`), so conversion is unaffected, but gameplay ports that hide a body must hide its `Visual`, or rely on Godot inheritance on purpose.
- `depthAnchor` `[x,y]` (on 14 CharacterBody2D roots and 9 Node2D effect roots, all `[0,0]` on effects): the local ground point a depth source sorts by. Handled by re-anchoring (§5.2). Write it to `metadata/depth_anchor`.
- `depthOverride` is a runtime-only absolute depth that effect spawns can request. Not serialized.

### 4.3 Sprite2D → `Sprite2D` (1,141 nodes)
Phaser draws one `Phaser.GameObjects.Sprite` at node position `+ R(rot)·(visualOffset ∘ globalScale)`, with `setOrigin(origin)`, scale, rotation and flip. Its alpha is `alpha × effects.alpha`; tint is applied with `setTint`.

| JSON | Godot |
|---|---|
| `texture` {resourceId} (sprite-sheet 1,134 / texture 3 resources) | `texture = ExtResource(res://asset/<path>)`; `hframes = frame.cols`, `vframes = frame.rows` from **assets.json**. A `texture` resource with `frame` on a spritesheet asset (none authored for sprites) → `AtlasTexture`. |
| `frame` (int ≥ 0) | `frame` |
| `origin` (default 0.5,0.5; values 0.5/0.5, 0.5/1, 0.5/0.75, 0.5/0.762712, 0.5/0, …) | `centered = false`; `offset = visualOffset − (origin.x·fw, origin.y·fh)` with fw and fh from assets.json `source.frame`, or `expect.w/h` for an image asset |
| `visualOffset` (default 0,0) | folded into `offset` (local, pre-scale, rotated with the node: equivalent) |
| `alpha` (0..1) | `self_modulate.a` |
| `tint` `#rrggbb` (14 sprites) | `self_modulate.rgb` (Phaser `setTint` multiplies, as `self_modulate` does) |
| `flipX` / `flipY` | `flip_h` / `flip_v`. Both engines mirror the image **inside the unflipped frame rectangle**; neither mirrors origin or offset (Phaser batch code; Godot `get_rect()` unchanged when flipped **[probed]**). |
| `depthMode`, `depthBand`, `depth`, `depthOffset`, `depthBounds` | draw order, §5 |
| `occlusionBounds` (143) | dropped (occlusion silhouettes are retired) |

Runtime-only Phaser API that gameplay ports must replace: `effects {scaleX, scaleY, alpha, offsetX, offsetY}` (squash, fades and hop offsets layered on top of the authored values), `setTintFill` and `setTint` (hit flash; use `modulate` or a shader), `clearTint` (back to the authored `tint`), `setSkin(textureKey)` (swap texture, same frame grid), `mirrorTo`.

### 4.4 CollisionShape2D → `CollisionShape2D` (1,010)
- Allowed parents: CharacterBody2D, StaticBody2D, Area2D. `position` sets the shape centre. A rectangle is centred on the node, as in Godot.
- `shape` {resourceId} → shape sub-resource (§6.3: rectangle → `RectangleShape2D(size = w,h)`; circle → `CircleShape2D(radius)`; ellipse and sector, see §1 items 18 and 19).
- `disabled` → `disabled` (63 authored true; animatable in physics).
- `angleRad` (optional override of a sector's angle): none authored. If present, map to `rotation` (§1 item 19).
- `rotation` is authored on 56 nodes, all 0. Phaser **throws** if the shape node or any ancestor is rotated, and requires uniform world scale for circles and sectors. World-space geometry: rectangle `w·sx × h·sy`; circle `r·sx`; ellipse `rx·sx, ry·sy`; sector radii `·sx`. Godot scales shapes by the node transform the same way.

### 4.5 Area2D → `Area2D` (208)
- `collisionLayer` and `collisionMask` → `collision_layer` and `collision_mask` (same bits). `monitoring` and `monitorable` → same names. `monitoring` is animatable (physics domain).
- Phaser contact rule (`ContactRouter.reconcile`, run once per physics step): observer = an area with `monitoring`; candidates = any participant that is `monitorable`. A body counts as monitorable while its `collisionEnabled` is true. A pair is accepted when `observer.mask & other.layer`, and the enabled shapes intersect, **edges included** (ε = 1e-9). Same layer rule as Godot, including area–area needing `other.monitorable`.
- **Tile bodies are not contact participants in Phaser.** No authored Area2D mask includes `world` (1) or `water` (1024), so Godot tile colliders cannot add contacts.
- Differences: (a) Phaser emits **no** exit when the observer's `monitoring` turns off, and re-emits enter when it turns back on. Godot emits `*_exited` on disable **[probed]**. No authored connection uses `*_exited`. (b) Signal payload, §7.1.

### 4.6 PhysicsBody2D (CharacterBody2D, StaticBody2D)
- `collisionLayer`, `collisionMask` → same. A static body's mask is ignored by blocking (all 724 StaticBody2D have mask 0).
- `collisionEnabled` (default true; never authored false). When false at run time the Arcade body is disabled and drops out of contacts. Godot equivalent: disable the child shape (`set_deferred("disabled", true)`), or set layer and mask to 0.
- **Exactly one enabled CollisionShape2D** is required while collision is enabled, and sectors are not allowed on bodies. Holds for all 740 bodies.
- Blocking rule (`blockingPairAccepts`): a mover is blocked when `mover.mask & other.layer`. Two dynamic bodies interact when *either* mask accepts the other, and Arcade **pushes both apart** (default pushable bodies). Godot CharacterBody2D does not push other kinematic bodies, so player ↔ enemy contact no longer shoves the enemy. This is a feel difference for the gameplay port.

### 4.7 CharacterBody2D → `CharacterBody2D` (16: 14 characters, 2 projectiles)
- `velocity` → `velocity` (all authored [0,0]). **Arcade integrates the velocity by itself every physics step.** Godot scripts must move the body from `_physics_process` with `ArcadeMover.move(body, delta)` (`game/shared/arcade_mover.gd`). Phaser reads the post-step velocity back with the blocked component zeroed; floating-mode `move_and_slide()` does not (it keeps the velocity and slides at full speed), so it must not be used.
- Write `motion_mode = 1` (MOTION_MODE_FLOATING).
- `collideWorldBounds` (10 authored; projectiles false) is dropped. Runtime world bounds clamp only bodies whose flag was true, so carry it as `metadata/collide_world_bounds` to let the world builder skip projectiles.
- `allowWorldPassThrough` is never authored and is validation only.
- `queue_teleport(pos)` in Phaser applies before the next physics sync. In Godot, set `global_position` directly.
- Ellipse shapes block as AABB rectangles (§1 item 18).

### 4.8 StaticBody2D → `StaticBody2D` (724; 718 are scene roots of object scenes)
All are rectangles on layer 1 with mask 0. No movement.

### 4.9 TileMapLayer2D → `TileMapLayer` (21, one per world)
Phaser draws one image per cell at `(x·tileSize, y·tileSize)`, origin (0,0), at the asset's **native frame size**, in cell order (row-major in every world). It adds the visual-only terrain blend and water surface (out of scope for the trial).

- `tileData` {resourceId} → the inline `tile-data` sub-resource of the world (§6.9). `tileSize` 64. `seed` (int, up to 3 421 253 882).
- `depth` (always 0 = `ground-terrain` band) → `z_index = -2` (§5.3). `position` is always (0,0). `collisionEnabled` is always true. `collisionMask` is always 0 (unused). `editorLocked` is editor only.
- Phaser requires zero rotation and unit scale on collidable layers.
- **Cell visuals**, for each cell `{x, y, tileId}` with tile `T = tiles[tileId]`:
  - `assetId = T.assetIds[tileHash(x, y, seed) % T.assetIds.length]` (the hash is used for every selection mode).
  - `seeded-hash` (interior floors) → the whole image at frame 0, no flip.
  - `sheet-wrap` (every ground) → `frame = (y mod rows)·cols + (x mod cols)`, i.e. atlas coords `(x mod 19, y mod 19)`, no flip.
  - `sheet-order` and `ground-sheet-region` are defined (`GroundSheetRegion.ts`; sheet-order flips odd blocks with `TRANSFORM_FLIP_H=4096` / `FLIP_V=8192` **[probed]** in the alternative-tile argument) but unused.
  - `tileHash(x,y,seed) = (imul(x + seed·17, 374761393) ^ imul(y − seed·31, 668265263)) >>> 0`. `imul` is the 32-bit wrapping multiply of the operands' low 32 bits (ToInt32). In GDScript (64-bit ints): `i32(v) = ((v & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000`; `imul(a,b) = i32(i32(a) * i32(b))`; `hash = (imul(x + seed*17, 374761393) ^ imul(y - seed*31, 668265263)) & 0xFFFFFFFF`. Because the converter computes this in Node, only the chosen asset ends up in the `.tscn`. Do it in JS with `Math.imul`, exactly like Phaser.
  - **Interior floors** (`wood-floor`, `mushroom-*`) are 128×128 images on a 64 grid. Each image overlaps the next cells, and since later cells draw on top, every cell ends up showing the **top-left 64×64 quadrant** of its own image. Images in the last column or row also overhang 64 px outside the map. Godot: give these atlas sources `texture_region_size = 64` over a 2×2 grid and always use atlas coords (0,0) (the top-left quadrant). The overhang is lost, which is acceptable (it lies under the walls or outside the camera).
- **Collision**: see §1 item 3. For each tile id with `physics != null`: rectangles = `mergeCellRectangles(cells of that tile id)`; body rect = `(rx·64 + inset.left, ry·64 + inset.top, rw·64 − left − right, rh·64 − top − bottom)`. The layer is the tile's `physics.layer` name (water and deep-water → `water`, bit 1024), otherwise the node's `collisionLayer` (1). Emit `StaticBody2D` children (for example under a `Collision` Node2D child) with `collision_mask = 0` and a centred `RectangleShape2D` per rectangle.
- TileSet: one atlas source per tile id, as in the conventions. grass-a, grass-b and rock-wall share `sheet.grounds.19x19.highland-green`. The ground sheets are 64-px frames on a 19×19 grid (1216²). The interior images are 128×128 single images. Keep `use_texture_padding` (default) against bleeding with LINEAR filtering. Optionally add a custom data layer `tile_id` (String) so gameplay can ask what ground a cell is.

### 4.10 Camera2D → `Camera2D` (0 authored)
For completeness: `zoom` (number) → `zoom = Vector2(z, z)`; `roundPixels` → project snap setting; the camera centres on the node position (Godot `DRAG_CENTER`); camera rotation follows the node (Godot `ignore_rotation = false`); `visible` → `enabled`. The game creates its camera in code (`ResponsiveCameraController`).

### 4.11 AnimationPlayer → `AnimationPlayer` + `animation_player.gd` (122)
See §6. Properties: `library` {resourceId} (always an inline animation-library sub-resource) → `libraries = {"": AnimationLibrary}`; `domain` (`physics` 40 / `render` 82) → `callback_mode_process` 0 or 1; `autoplay` (all 122) → see §6.6; `randomizeStart` (84) → helper export. Signals: `animation_finished(name)` → Godot `animation_finished(anim_name: StringName)`; `animation_event` → helper signal. The player is always a direct child of the scene root (CharacterBody2D 16, Node2D 55, StaticBody2D 51).

### 4.12 AudioStreamPlayer (90) and AudioStreamPlayer2D (235) → same types + `sfx_player.gd` / `sfx_player_2d.gd`
Phaser semantics (`AudioPlaybackController`):
- **Voices.** A loop owns one voice. A one-shot allocates up to `polyphony` voices; when all are busy, the **oldest** is cut, which is Godot's `max_polyphony` behaviour. Voices are created lazily.
- **One-shot play.** Picks `[assetId, ...variants]` uniformly (repeats allowed) and sets `rate = pitch · (1 + U(−r, +r))` with `r = pitchRandomness` (multiplicative and uniform; Godot's `random_pitch` is a different distribution, so set `pitch_scale` per play in the helper and leave `AudioStreamRandomizer.random_pitch = 1`).
- **Variants.** `AudioStreamRandomizer` with `playback_mode = 1` (PLAYBACK_RANDOM) and equal weights. 140 resources have variants; no looped stream does.
- **minIntervalMs.** For non-loop plays only, a play requested less than `minIntervalMs` after the previous **accepted** play is dropped. Measured on wall-clock time (`Date.now()`), so it keeps running during pause: use `Time.get_ticks_msec()`.
- **loop.** Plays `loop: true` on one voice, and a repeated `play` while it is playing is ignored. Godot: the loop flag belongs to the stream. The looped files are wav ×6, ogg ×2 and mp3 ×2 (`audio.music.level-1-home-town`, `gloop-forest`, `gloop-forest-ambience`, `audio.sfx.world.*-loop.1`, `meadow-ambience`, `interior-ambience`, `player.sleep-breath`), and they are only ever used looped. Either set the loop import parameter for those files in `sync-assets` (`.import`: wav `edit/loop_mode=2`, ogg and mp3 `loop=true`), or have the helper `stream = stream.duplicate()` at `_ready` and set `loop = true` (Ogg/MP3) or `loop_mode = LOOP_FORWARD` with `loop_end = int(get_length() * mix_rate)` (WAV).
- **autoplay** (7 + 14): starts on tree enter, after the Web Audio unlock. 14 AudioStreamPlayer2D one-shots with autoplay sit in effect scenes. Let the **helper** start autoplay (`play_cue()` in `_ready`) so that pitch randomness and variants apply. Set Godot's own `autoplay = false`.
- **volume** → `volume_db = linear_to_db(volume)`, clamped to ≥ −80 for volume 0. `pitch` → `pitch_scale` base. `bus` `effects|music|ambience` → `Effects|Music|Ambience`.
- **Tree exit.** Non-loop voices stop unless `detached` (83, all 2D). Loop voices always stop. Loop playing state survives re-entry (`desiredPlaying`). `detached: true` means a one-shot keeps playing to completion after its node leaves the tree. In Godot the helper must, on `tree_exiting` while playing, re-parent itself (or spawn a clone at the same global position) under a persistent node and `queue_free` on `finished`.
- **playback_finished** is emitted per completed non-loop voice. Godot `finished` fires when the player stops. No authored connection uses it.
- **Handlers.** `play(payload)` and `stop(payload)` run only if `payloadFilter` accepts the payload. Connections: 71 `Button.pressed`, 8 `ItemList.item_selected`, 4 `Slider.value_changed` and ~150 script signals.
- **payloadFilter** grammar `^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*=[^=]+$`, i.e. `field.path=v1|v2`. Walk the payload by keys. It matches only if the leaf is a string, number or bool and `String(leaf)` is in the set. A non-object payload never matches a non-empty filter. Authored filters: `phase=…` on fatty and matron `phase_changed`, `status=…` on collectible `pickup_resolved`. In GDScript, stringify integral floats without `.0` (JS `String(2)` = `"2"`). Ported scripts must emit Dictionary payloads with those exact keys (`phase`, `status`).
- **2D spatial** (Phaser computes this against the **main camera centre**): `attenuation = max(0, 1 − dist/maxDistance)` (linear) and `pan = (x − camX)/panDistance` clamped to ±1, applied as a StereoPanner. Godot AudioStreamPlayer2D with `max_distance = maxDistance` and `attenuation = 1.0` gives exactly `(1 − d/max)^1` **[probed defaults]**. Godot's pan is `clamp(dx_screen/screen_w, −1, 1) · panning_strength`, with a linear left/right split, so the helper should set `panning_strength = viewport_width_px / (panDistance · camera_zoom)` each frame (or once per resize). Authored `maxDistance` values: 420, 1400, 1600 (11 nodes); otherwise the default 800.
- **Pause.** Both keep processing while paused: `process_mode = ALWAYS` (§1 item 13). Bus preference volume and mute are Phaser `AudioPreferences`, which become Godot buses. `setGain` (music crossfade) is a runtime-only multiplier.

### 4.13 Control family (UI scenes: 26 roots, 11 Container and 15 ModalRoot)
Rendering model: each control is an HTML element **absolutely positioned inside its parent control's element** (the root goes inside the full-screen `.scene-ui-root`): `left = W·anchorMin.x + offsetMin.x`, `top = H·anchorMin.y + offsetMin.y`, `right = W·anchorMax.x + offsetMax.x`, `bottom = H·anchorMax.y + offsetMax.y`, where W and H are the parent element's client size. **This is exactly Godot's anchor and offset model**: `anchor_left/top/right/bottom = anchorMin.x, anchorMin.y, anchorMax.x, anchorMax.y`; `offset_left/top/right/bottom = offsetMin.x, offsetMin.y, offsetMax.x, offsetMax.y`. Write anchors before offsets. (Godot measures from the parent rect. CSS measures from the parent's padding box, offset by its 1-px border on bordered panels; ignore that.)

Common properties (all Control types):

| JSON | Godot |
|---|---|
| `visible` | `visible` (ModalRoot: `= open`) |
| `focused` (15, all false) | nothing (call `grab_focus` at ready if true) |
| `modal`, `consumeInput` | `mouse_filter = STOP` (ModalRoot forces both) |
| `processWhenPaused` (default true) | `process_mode = 3` |
| `inputPriority` (ModalRoot 2000–2200) | no equivalent. UI input order = tree and draw order; the UI manager orders roots |
| `zIndex` (roots only: 18–98) | `z_index` on the root, and the runtime UI manager should insert roots ordered by it (Godot GUI picking ignores `z_index`) |
| `styleClass` (`game-ui game-ui--hud`, `inventory-items`, …) | `metadata/style_class` (and/or `theme_type_variation` from the last `game-ui--*` token); styling is redone in the Theme |
| `ariaLabel`, `tooltip` | `accessibility_name` (exists in 4.7 **[probed]**), `tooltip_text` |
| `theme` {resourceId: `ui.field-kit.theme`} (26 roots) | `theme = <generated Theme>` (§6.10) |
| `opacity`, `scale` (runtime only) | `modulate.a`, `scale` with centre pivot |

### 4.14 Container → `Control` (or `Panel` for `game-ui` styled roots)
`direction`, `gap`, `padding`, `align` and `justify` are never authored and are inert anyway. Report them if they ever appear. CSS gives `.scene-control--container.game-ui` and `.scene-control--modalroot` a panel look (border `border-standard` 74 %, background `surface-base` 94 %), so `Panel` with a theme StyleBox suits those roots. Set `mouse_filter = IGNORE` (HUD panels must not block world clicks).

### 4.15 ScrollContainer → `ScrollContainer` (5; all vertical, anchors full rect)
HTML: `overflow-y: auto`, and the child is absolutely positioned. Every authored child is one Container with anchors (0,0)-(1,0) and `offsetMax.y = H` (for example 640): full width, fixed height. Godot ScrollContainer lays out its child itself, so emit the child with `size_flags_horizontal = SIZE_EXPAND_FILL` and `custom_minimum_size = Vector2(0, offsetMax.y − offsetMin.y)`, and drop its anchors. `scrollAxis` vertical → `horizontal_scroll_mode = DISABLED`; horizontal → `vertical_scroll_mode = DISABLED`.

### 4.16 Label (75) → `Label`; Button (71) → `Button`
- `text` → `text`. CSS `white-space` is `pre-line` when `wrap` is set (newlines kept, word wrap on) and `nowrap` otherwise (**newlines collapse into spaces**). So: `wrap` → `autowrap_mode = AUTOWRAP_WORD_SMART`; no wrap → `autowrap_mode = OFF` and replace whitespace runs containing a newline with a single space. Five ability Buttons rely on `"Lv 2\nJump"` with `wrap: true`.
- `tone` → font colour from the theme: default → `text-primary`, muted → `text-muted`, accent, info, warning, danger, special.
- `fontSize` → `theme_override_font_sizes/font_size`. `fontWeight` (700/800) → a bold font or `FontVariation.variation_embolden`.
- `textAlign` left/center/right → `horizontal_alignment` 0/1/2 (Button default center). Labels are flex boxes with `align-items: center`, so Label `vertical_alignment = CENTER`.
- `color` (runtime, binding) → `font_color` override.
- Button `disabled` → `disabled`. `pressed` emits only when not disabled and visible: Godot `pressed()` (0 arguments). Enter and Space activate a focused button (Godot `ui_accept`). Label default `mouse_filter` is IGNORE; Button keeps STOP.

### 4.17 ProgressBar (4) → `ProgressBar`
`value` → `value`; `max` → `max_value`; `show_percentage = false`; `step = 0` (Phaser keeps `ceil` only for display). The text drawn inside the bar is `showValue ? "<label> <ceil(value)> / <ceil(max)>" : label` → a child Label (or a script). `tone` → fill StyleBox colour. Height is authored as 18 px, with 11 px tabular-numerals text. `mouse_filter = IGNORE`.

### 4.18 Slider (4, settings) → `Control` holding a caption `Label` and an `HSlider`
The HTML is a column: caption (`label`, 14 px) above a range input. `min`, `max`, `step`, `value` → HSlider `min_value`, `max_value`, `step`, `value`. `disabled` → `editable = false`. `value_changed` is emitted **only for user changes**, with payload `{control: <node name>, value}`. Godot `HSlider.value_changed(value: float)` also fires on code changes, so model writes must use `set_value_no_signal`. Phaser clamps and snaps values with `round((v−min)/step)·step`, as Godot's step does.

### 4.19 ItemList (8) → custom list (recommended) or `ItemList`
Phaser renders a CSS grid of `<button>`s (`columns`, `gap`), item `{id, label, disabled?, metadata?}`. The metadata keys are `iconKey`, `iconFrame`, `showLabel`, `shortcut`, `locked`, `short` and `draggable`. Signals: `item_selected {index, item}` (click, Enter or Space), `item_secondary {index, item}` (right-click, ContextMenu or Shift+F10; also selects), `item_dropped {index, item, sourceItemId, sourceIndex}` (HTML5 drag between lists, only when `dropTarget`). Arrow keys move by ±1 / ±columns and skip disabled items. Godot `ItemList` has `max_columns`, icons and `item_selected(index)` / `item_clicked(index, pos, button)`, but no drag-drop or per-item badges. Phase 3 should use a GridContainer of Buttons with a list script that keeps the Phaser payloads. For the trial only the weapon hotbar (HUD) needs it.

### 4.20 TextureRect (3) → `TextureRect`
`texture` (texture or sprite-sheet; `frame` selects an `AtlasTexture` region). `fit`: contain → `expand_mode = IGNORE_SIZE` + `stretch_mode = KEEP_ASPECT_CENTERED`; cover → `KEEP_ASPECT_COVERED`; fill → `SCALE`; none → `KEEP_CENTERED`. `alt` → `accessibility_name`. `mouse_filter = IGNORE`.

### 4.21 ModalRoot (15) → `Control` (`Panel`) + modal behaviour
Construction forces `modal = consumeInput = processWhenPaused = true`; `visible = open`. `setOpen(o)` sets both. Escape while open emits `close_requested` (0 arguments; 12 connections → `ui-surface.on_close_action`). Opening focuses the first enabled button; Tab is trapped inside; closing restores focus. Godot: a root Control with `mouse_filter = STOP`, a small script for `ui_cancel`, `close_requested` and the focus trap, and `focus_mode = ALL` on its buttons and lists.

---

## 5. Draw order (depth)

### 5.1 Phaser model
`resolveWorldDepth(y, {band, stableId})` returns `BAND[band] + round(clamp(y, 0, 65536)·16)·1024 + hash(stableId)%32·16 + attachmentSlot`, with band spacing 2·10⁹: ground-terrain 0, ground-decals 1, world-entities 2, overhead-artwork 3, reveal-effects 4, screen-ui 5, editor bands 6–9. Bands always dominate Y, Y has 1/16 px resolution, and ties break by a stable id hash.
- `world-sorted` (default; 1,085 object sprites): the sprite sorts by its **own** global Y, or by its depthBounds line (§5.4), in its own band.
- `relative` (39: 14 character visuals, 9 effect layers, 16 weapon layers): `depth = base(depthSource) + depthOffset`, where depthSource is the sprite itself or its nearest Node2D ancestor with a `depthAnchor` (or a runtime `depthOverride`). `base = depthOverride ?? resolveWorldDepth(source.globalAnchorY, {band: this sprite's band, stableId: source})`. Every relative sprite under one source sorts as a unit at the source's feet.
- `explicit` (14 water-life sprites): `depth` taken literally.

### 5.2 Godot mapping (y-sort)
- `y_sort_enabled = true` on the world root and **on every Node2D-derived node that is not a depth source**: world containers, object roots (Node2D or StaticBody2D), encounter roots and projectile roots. Godot 4 merges nested y-sorted children into the ancestor's sort, so each world-sorted sprite sorts by its own global Y, as in Phaser.
- Depth sources (nodes with `depthAnchor`: the 14 character roots and 9 effect roots): `y_sort_enabled = false`, re-anchored as the conventions describe (root origin = anchor, direct children and their position keys shifted by −anchor), so the subtree draws as one unit at the feet. Inside the unit, draw order is child order. Sort relative sprites stably by `depthOffset` (all authored offsets keep tree order, §6.4).
- The weapon is mounted at run time under the player body (Phaser: `mount.reparent(playerBody)` at (0,0) = the old body centre). In Godot, add it as the **last** child of the player root at `position = -depth_anchor` (weapon layers have `depthOffset` 0.01 > the body's 0, so they always draw above the slime).

### 5.3 Bands → `z_index`
| Band / case | z_index |
|---|---|
| ground-terrain (the TileMapLayer, `depth` 0) | −2 |
| explicit depth in the ground-decals band (`floor(depth/2e9) = 1`; the fish) | −2 (they draw below all world-sorted decals; the tile layer sorts first because its y = 0) |
| ground-decals (world-sorted or relative) | −1 |
| world-entities | 0 |
| overhead-artwork (unused) | 1 |
| reveal-effects (unused) | 2 |
General explicit rule: band index `b = floor(depth / 2e9)` → `z = Z(b) − 1`. Keep `z_as_relative = true`; parents stay at 0. Godot sorts by Y only within one z_index, which matches "band dominates Y".

### 5.4 depthBounds sort line (13 sprites: houses, forge, flower planter, …)
The sort Y is `nodeY + Δ` with `Δ = (bounds.offsetY + bounds.height − frameH·origin.y)·|scale.y|`. The authored Δ values range from −3 to −37 px. Godot: add Δ to the Sprite2D's `position.y` and subtract `Δ/scale.y` from `offset.y`. The image stays put and the sprite sorts at the line (the object root is y-sorted, §5.2). `depthBounds.offsetX` and `width` do not affect sorting. Δ uses the frame height from assets.json.

### 5.5 Dropped
`occlusionBounds`, the occlusion pipeline, `attachmentSlot`, and stable-id ties (Godot breaks ties by tree order).

---

## 6. Resources

### 6.1 `texture` {assetId, frame?} (3, UI only)
Image asset → `Texture2D` (`res://asset/<source.path>`). `frame` on a spritesheet asset → `AtlasTexture(region = frame grid cell)`.

### 6.2 `sprite-sheet` {assetId, frameWidth, frameHeight, frameCount?} (1,134)
Only `assetId` matters. The grid comes from assets.json (§1 item 4). `frameCount` (for example 38 on a 4×10 sheet) is informational; frames beyond it are blank.

### 6.3 `collision-shape` {value} (947)
`rectangle {width,height}` → `RectangleShape2D(size)`; `circle {radius}` → `CircleShape2D`; `ellipse {radiusX,radiusY}` (25) → body parent: `RectangleShape2D(2rx, 2ry)`, area parent: `ConvexPolygonShape2D` (32 points `(rx·cos θ, ry·sin θ)`); `sector {angleRad, arcWidthRad, innerRadius, outerRadius}` (8) → points: apex (0,0) when innerRadius = 0, plus `max(8, ceil(96·arc/2π))+1` points on the outer arc from `−arc/2` to `+arc/2` (built at angle 0, node `rotation = angleRad`; y-down, so a positive angle turns clockwise on screen, as in Phaser `atan2`). Validation: rectangle and radii > 0; `0 < arc ≤ 2π`; `0 ≤ inner < outer`. Shapes are per-scene sub-resources, so one shape resource can back both a body and an area (fatty), and the converter emits a variant per parent type.

### 6.4 `animation-library` {animations} (122, all inline)
Each clip: `{ durationSeconds, framesPerSecond, loop, loopMode?, tracks[], events? }`. `loopMode` is `wrap` (default) or `ping-pong`. Each track: `{ binding, property, keys[{at, value, transition?}], enabled?, interpolation? }`. `enabled` and `interpolation` are never authored. fps values: 1–24, including non-integers (11.11, 15.38, 5.56, 7.69, 9.09).

**Timeline semantics** (`AnimationClock`):
- `N = max(1, round(duration·fps))` frames. The clock advances **whole frames**: `step = floor(elapsed/frameDuration)`, and it visits every intermediate step (each step applies tracks and fires events).
- Non-loop: when `step ≥ N`, every remaining step up to `N−1` is applied, playback stops, the clip completes and `animation_finished` is emitted. Keys at `at ≥ N` (11 authored, for example an alpha key at 13 of 13) are never reached on their own; they only shape the interpolation before them.
- Loop wrap: frame = `step mod N`. Ping-pong (N > 1): cycle `2N − 2`, frame `= s < N ? s : 2N−2−s`, so the end frames are not repeated.
- Track value at frame f: keys sorted by `at`; `left` = last key with `at ≤ f` (the first key if f precedes them all), `right` = first key with `at ≥ f`. Linear interpolation applies when the property is numeric (number, Vector2) and `right.at > left.at`, with ratio `ease((f − left.at)/(right.at − left.at), left.transition)`. Otherwise the value is `left.value`. **No wrap interpolation across the loop seam.** The first key is at `at > 0` in 8 tracks (spear position): the value before it is the first key's value, which Godot also holds.

**Godot emission:**
- `length = N/fps` (wrap or non-loop); `loop_mode = LOOP_LINEAR` if `loop` else `LOOP_NONE`.
- Ping-pong (11 clips: the idle clips of orb-weaver, matron, slime-spider and village-elder-plop, and spider-web `move`; **all contain only discrete `frame` tracks and no events**): bake into LOOP_LINEAR of length `(2N−2)/fps` by **sampling**: for each step `s` in `0..2N−3`, `frame(s) = s < N ? s : 2N−2−s` and value = the Phaser track value at that frame. Emit a discrete key at `s/fps` whenever the value changes. Exact, and simpler than mirroring keys. A held key's reverse span starts at `2N−1−nextKey.at`, not at `2N−2−at`. If a ping-pong clip ever gets numeric tracks or events, sample those per step too (events fire whenever `frame(s) == at`).
- Key time `= at/fps`. `transitions`: linear or absent → 1.0, `ease-in` → 2.0, `ease-out` → 0.5, `ease-in-out` → −2.0. These are exact: Godot `ease(x, c)` equals the Phaser quadratics **[probed]** (20 authored keys: rotation and alpha on ambient webs).
- Every value track: `interp = 1` (linear) and `loop_wrap = false`. `update = 0` (continuous) for numeric properties and `update = 1` (discrete) for step properties (frame, flipX, flipY, visible, disabled, monitoring). Phaser steps numeric tracks at the clip fps; Godot's continuous mode is smoother. That is accepted for the trial. If exact Phaser stepping is ever wanted, bake numeric tracks to one discrete key per frame.
- Track path = `<binding without leading "../">:<godot property>` with the AnimationPlayer's `root_node = ".."`. Property mapping:

| JSON property (tracks) | target | Godot path suffix | update | key conversion |
|---|---|---|---|---|
| `frame` (336) | Sprite2D | `:frame` | discrete | int |
| `flipX` / `flipY` (110/100) | Sprite2D | `:flip_h` / `:flip_v` | discrete | bool |
| `alpha` (104) | Sprite2D | `:self_modulate:a` | continuous | float |
| `position` (110 sprite, 16 shape, 2 root) | Node2D-derived | `:position` | continuous | Vector2, minus the anchor if the target is a direct child of a re-anchored root |
| `scale` (102+2) | Node2D | `:scale` | continuous | Vector2 |
| `rotation` (107+2) | Node2D | `:rotation` | continuous | float rad (plain linear, not angle-wrapped) |
| `visible` (2, root) | Node2D | `:visible` | discrete | bool |
| `visualOffset` (2) | Sprite2D | `:offset` | continuous | `value − origin·frameSize`, plus the depthBounds Δ correction if any |
| `depthOffset` (100) | Sprite2D | dropped | | values 0, 0.01, 0.3, 1.011, constant within each track; they never reorder siblings differently from tree order (basic-sword `Layer22` 0.01 vs 1.011 stays above `Base1` either way) |
| `disabled` | CollisionShape2D | `:disabled` | discrete | (animatable, none authored) |
| `monitoring` | Area2D | `:monitoring` | discrete | (animatable, none authored) |
| `angleRad` | CollisionShape2D | `:rotation` | continuous | (none authored) |

- Domains: a property must allow the player's domain. `monitoring`, `disabled` and `angleRad` are physics only. A clip with `gameplay` events must run in the physics domain (Phaser throws otherwise).
- **Events** `{at, eventId, payload?, gameplay?}` (3 authored) → a method track (path `"."` to the AnimationPlayer itself) with key `{method: &"emit_animation_event", args: [eventId, payload ?? {}, gameplay ?? false]}` at `at/fps`. Phaser fires an event when the clock *enters* the frame, including frame 0 at `play()`. Godot fires a method key at t = 0 on the first process after `play()` **[probed]**. Seeking (`randomizeStart`, scrub) fires no events in Phaser: use `seek(t, true)`, which skips method keys in Godot as long as no time passes. Loop clips fire their events every cycle in both engines.

### 6.5 Baseline restore and play semantics (helper `animation_player.gd`)
Phaser contract, to be reproduced by `play_clip(name)`, `stop_clip()`, `seek_frame(f)`, `pause_clip()`, `resume_clip()`, `has_clip(name)`, `clip_length_ms(name)` and `current_clip`:
1. `play_clip(name)`: run `stop_clip()` first, which restores every property the previous clip animated to the baseline captured when that clip started. Then capture the current value of every property the new clip animates, then start from frame 0 **even if `name` is already playing**: `stop(); play(name); seek(0, true)`.
2. Natural completion of a non-loop clip: forget the baselines without restoring them (values hold the last frame), clear `current_clip` (Phaser's `currentAnimation` becomes undefined) and emit `animation_finished`.
3. `stop_clip()` and `_exit_tree`: restore the baselines.
4. A property can have only one active writer at a time (Phaser throws on a second one). The helper can ignore this.
The Phaser call sites guard re-entry themselves (`EnemyScript`: `if (restart || current !== name) play(name)`; `PlayerNodePorts.forceRestart`), so ported scripts should call `play_clip`, never `play` directly.

### 6.6 autoplay and randomizeStart
Phaser `_ready`: `play(autoplay)`; then if `randomizeStart` and the clip loops, `seek(floor(random()·N))` (frames, no events). Recommendation: keep `autoplay` out of Godot's native property (native autoplay bypasses baseline capture) and give the helper `@export var autoplay_clip: String`, which it plays in `_ready` through `play_clip`, followed by `seek(randi_range(0, N−1)/fps, true)` when randomizing. If the conventions keep native `autoplay`, the helper's `_ready` must still capture baselines and apply the random seek. `randomizeStart` is authored on 84 players, all ambient objects.

### 6.7 `audio` {assetId, variants?} (324)
`assetId` and `variants` are asset ids → `res://asset/<path>` (wav 362, ogg 113, mp3 2 files). No variants → a plain stream. Variants → `AudioStreamRandomizer` (`streams_count`, `stream_N/stream`, `stream_N/weight = 1`, `playback_mode = 1`).

### 6.8 `tile-set` {tiles} (1 external: `terrain.tiles`, 18 tile ids)
Tile: `{ assetIds[], selection, physics: null | {body:'static', inset?, layer?}, allowsDecorations, tags[], transition?, editor? }`. `transition` (blend group, material, priority, edgeWidth, style) feeds the terrain blend (out of scope). `allowsDecorations`, `tags` and `editor` are authoring data; put them in custom data if gameplay ever needs them. Selections used: `sheet-wrap` (13), `seeded-hash` (4 interior floors). Physics-bearing tiles: `water` and `deep-water` (layer water, inset 10) and `rock-wall` (world, inset 4/4/6/2; used in world `174`).

### 6.9 `tile-data` {tileSet, columns, rows, cells[{x,y,tileId}]} (21, inline in worlds)
Every world is full (`cells = columns·rows`) except `mushroom-home` (165 of 192), and cells are row-major and unique. Godot: `tile_map_data` (or `set_cell` at conversion time) using source = the tile id's atlas and atlas coords from §4.9.

### 6.10 `theme` {values} (1 external: `ui.field-kit.theme`)
Every value becomes a CSS variable `--scene-<key>` on the control's element, inherited by its descendants. Keys: `font-family` ("Trebuchet MS, Segoe UI Variable, sans-serif"), the colours `surface-base #101a31`, `surface-raised #192642`, `surface-inset #182b46`, `border-standard #3b5c78`, `shadow #081022`, `text-primary #f5f7ff`, `text-secondary #c7e8d6`, `text-tertiary #a7bbd6`, `text-muted #8fbba3`, `accent #86f0c3`, `info #72d8ff`, `warning #ffd277`, `danger #ff6f88`, `special #a78bfa`, and `spacing-unit 4` and `focus-width 2`. Godot: a generated `Theme` (default font, `Label/colors/font_color = text-primary`, the Button and Panel StyleBoxFlat colours from the CSS rules, and `theme_type_variation`s per tone). `SystemFont` does not work on the web export, so bundle a TTF.

### 6.11 `font` {assetId}
Defined in the schema; 0 authored. Would map to `FontFile`.

---

## 7. Signals

### 7.1 Built-in signal payloads: Phaser → Godot
| Phaser signal (connections) | Phaser payload | Godot signal and arguments |
|---|---|---|
| Area2D `body_entered` / `body_exited` (11 → world-exit) | `PhysicsContact {observerId, otherId, observerKind, otherKind, observer, other, shapes[{observerShapeId, otherShapeId}]}` | `body_entered(body: Node2D)`; `other` = body. Shape ids → `body_shape_entered` if a port needs them. |
| Area2D `area_entered` / `area_exited` (16 → weapon, projectile, player pickup) | same | `area_entered(area: Area2D)` |
| AnimationPlayer `animation_finished` | clip name | `animation_finished(anim_name: StringName)` |
| AnimationPlayer `animation_event` | `{animation, event{at,eventId,payload,gameplay}, context{previousTimelineFrame,timelineFrame,direction,cycle,isScrub}}` | helper `animation_event(event: Dictionary)`, keys `animation, at, event_id, payload, gameplay` |
| Audio `playback_finished` | none | `finished()` (no authored connection) |
| Button `pressed` (101) | none | `pressed()` |
| Slider `value_changed` (8) | `{control, value}` | `value_changed(value: float)`; handlers needing `control` use the node name |
| ItemList `item_selected`, `item_secondary`, `item_dropped` (17) | `{index, item}` / `{index, item, sourceItemId, sourceIndex}` | custom list signals emitting the same Dictionary (recommended) |
| ModalRoot `close_requested` (12) | none | custom `signal close_requested` |

### 7.2 Script signals
They keep the TS names (descriptor list: player `health_changed`, `damaged`, `damage_feedback`, `defeated`; enemy adds `reward_requested`, `alerted`, `attack_started`; weapon `attack_started`, `attack_finished`; …) and emit one Dictionary payload (conventions). Authored connections to audio cues use `phase_changed`, `pickup_resolved`, `damaged`, `defeated`, `alerted`, `attack_started`, `launched`, `expired`, `drops_requested`, `harvest_blocked`, `resource_hit`, `closed`, `guard_blocked`, `open_requested`, `stack_transferred`, `boss_spawn_requested` and `torn`, plus `pressed` → `story-flag.set`.

---

## 8. Behaviour differences script porters must know

1. Bodies move on their own in Arcade (velocity integration). Godot needs `ArcadeMover.move(body, delta)` (not `move_and_slide()`).
2. Arcade pushes dynamic bodies apart symmetrically. Godot CharacterBody2D does not push.
3. Phaser Node2D visibility is not inherited; Godot's is.
4. Phaser `AnimationPlayer.play(name)` always restarts and stop or switch restores baselines; use `play_clip` and `stop_clip`.
5. Turning off Area2D monitoring emits exits in Godot only.
6. Contacts in Phaser include touching edges; Godot needs real overlap (sub-pixel edge cases only).
7. Positions: re-anchored roots put the feet at the origin. Old body centre = `global_position − depth_anchor·scale`. Every Phaser position used as a body position (spawn points, `bed.sleepPoint`/`wakePoint` if they place the body, `boss-camp.spawn`, world-definition `player.spawn` and `entries`, world-exit entries) needs `+ depth_anchor·scale` when it places a re-anchored root.
8. `minIntervalMs` uses wall-clock time and keeps counting through pause.
9. HUD buttons must not take keyboard focus (`FOCUS_NONE`), or Space and the arrow keys stop reaching the game. Read world clicks in `_unhandled_input` so that GUI controls with `STOP` consume their own clicks.
10. The `effects` presentation layer on sprites (scale, alpha, offset multipliers and offsets) is runtime only. Implement it in gameplay on `Visual` (for example with a tween on `scale` or `modulate`), not through the converter.
11. Effect spawns (`spawnEffect`) can request an explicit depth and follow another node. In Godot that is a `z_index` or child order, set by the effects service.

---

## 9. Survey totals (coverage checklist)

- **Node types**: Sprite2D 1141, CollisionShape2D 1010, StaticBody2D 724, Node2D 539, ScriptNode 326, AudioStreamPlayer2D 235, Area2D 208, AnimationPlayer 122, AudioStreamPlayer 90, Label 75, Button 71, TileMapLayer2D 21, Container 21, CharacterBody2D 16, ModalRoot 15, ItemList 8, ScrollContainer 5, ProgressBar 4, Slider 4, TextureRect 3. Not authored: Camera2D, GridContainer, Control, PhysicsBody2D.
- **Properties authored per type**:
  - Sprite2D: texture, frame, origin, visualOffset, alpha, tint, flipX, flipY (via overrides), position, rotation, scale, depthMode, depthBand, depth, depthOffset, depthBounds, occlusionBounds.
  - CollisionShape2D: shape, position, rotation (0), disabled.
  - Area2D: collisionLayer, collisionMask, monitoring, monitorable, position.
  - CharacterBody2D: collisionLayer, collisionMask, collideWorldBounds, depthAnchor, position, scale, velocity.
  - StaticBody2D: collisionLayer, collisionMask, position.
  - Node2D: position, depthAnchor.
  - AnimationPlayer: library, domain, autoplay, randomizeStart.
  - AudioStreamPlayer: stream, bus, volume, pitch, pitchRandomness, polyphony, minIntervalMs, loop, autoplay. AudioStreamPlayer2D: the same plus detached, maxDistance and payloadFilter.
  - TileMapLayer2D: position, tileData, tileSize, seed, depth, collisionLayer, collisionMask, collisionEnabled, editorLocked.
  - Controls: as listed in §4.13–4.21.
- **Instances**: 9,252 (object 9,237, character 13, encounter 2). Overrides: 23,344 (always `sourceInstancePath: []`). Persistence keys: 9,250.
- **Connections**: 443, in 120 scenes (the signal → handler pairs are in §2.3 and §7).
- **Sub-resources**: sprite-sheet 1,134, collision-shape 947, audio 324, animation-library 122, tile-data 21, texture 3. External: tile-set 1, theme 1.
- **Animation**: 332 clips, 1,095 tracks, 8,678 keys, 20 key transitions, 3 events; loop wrap 165, ping-pong 11, non-loop 156.
- **Level-1 closure** (the trial): 190 scenes (the world, 6 NPC characters, `encounter.level-1-fatty-camp` → `character.fatty-one-eye`, 181 objects). Worm swordsmen are spawned at run time from the `world-area` enemy-spawn data (`level-1-starter-camp`), not instanced.

## 10. Godot 4.7.2 facts probed
- `AudioStreamRandomizer.playback_mode` default 0 (RANDOM_NO_REPEATS); `PLAYBACK_RANDOM = 1`.
- AudioStreamPlayer2D: `max_distance 2000`, `attenuation 1`, `panning_strength 1`, `max_polyphony 1`. AudioStreamPlayer `max_polyphony 1`.
- AnimationPlayer: `deterministic false`, `callback_mode_process 1` (idle). Value tracks default `interp 1`, `update 0`, `loop_wrap true`. tscn keys: `tracks/N/{type,imported,enabled,path,interp,loop_wrap,keys}`; method keys `{"times","transitions","values":[{"args":[…],"method":&"…"}]}`.
- `ease(x, 2)`, `ease(x, 0.5)` and `ease(x, −2)` match Phaser ease-in, ease-out and ease-in-out exactly.
- `play(current)` does not restart. Switching clips or `stop()` leaves properties at their last values. A method key at t = 0 fires on the first process after `play`.
- `Area2D.monitoring = false` emits `body_exited`; re-enabling emits `body_entered`.
- `CharacterBody2D.motion_mode` default 0 (GROUNDED). Area2D layer and mask default 1/1.
- Control `accessibility_name` and `accessibility_description` exist.
- Default `mouse_filter`: Control, Panel, Button, ProgressBar, HSlider, ItemList → STOP; Label → IGNORE; ScrollContainer, TextureRect, GridContainer → PASS. ProgressBar `show_percentage` true. Buttons, HSlider and ItemList `focus_mode` ALL.
- `Sprite2D.get_rect()` is unchanged by `flip_h` (it flips in place).
- `TileSetAtlasSource.TRANSFORM_FLIP_H = 4096`, `FLIP_V = 8192`. Project default canvas texture filter = Linear; `snap_2d_transforms_to_pixel` default false.
- Not probed (verify in the editor): nested y-sort merging (documented in `CanvasItem.y_sort_enabled`), and the sign of `TileData.texture_origin` (only relevant if the interior 128-px tiles are drawn whole instead of quadrant-cropped as §4.9 recommends).
