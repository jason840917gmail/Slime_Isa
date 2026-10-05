# Furniture placement: spec for the Godot port

Placing furniture from the bag (today only the Workbench), the placed bench as a crafting station,
picking it back up, putting placed furniture back on world load, and the `furniture.placed` quest
event that ends the first main quest's second stage ("A Place to Work").

Source of truth: the Phaser app on `feat/godot-migration` (read 2026-10-05). Paths are under
`src/game/` unless they start with `src/`, `godot/`, `scripts/` or `docs/`; `file:line` is the
current tree. Godot files are cited by function name, because several were uncommitted work in
progress when this was written (the crafting, bag and quest agents were editing them).

Binding inputs: [ARCHITECTURE.md](../ARCHITECTURE.md), [CONVENTIONS.md](../CONVENTIONS.md);
[crafting.md](./crafting.md) §3.1 (placeable output), §6.3-6.4 (the bag's Place button) and owner
decision C1; [interaction.md](./interaction.md) §2.2-2.7 (candidates, prompt, the interact press),
§3.6 and §8.6 (the workbench); [quests.md](./quests.md) §7.6 (a-place-to-work is blocked on this).

**Port status (2026-10-05):** ported as planned in §11: `game/building/furniture_placement.gd`
(child "FurniturePlacement" of main), `game/building/placed_furniture.gd`, the RunState records,
the player's placement branch and interact hold, the interaction controller's hold actions
("Hold: Pick up"), crafting / the bag starting placement, and `test_furniture.gd` (12 tests).
Owner questions: F1 applied as recommended (placement ends on defeat); F2-F6 kept as Phaser. The
map key and `Shell.can_open_pause` checks while placing belong to the map and shell owners.

Legend: **[IN]** port now. **[OUT]** exists in Phaser, not ported (reason given). **[QUIRK]** the
Phaser build does something its code or content probably did not intend; port it as is unless the
owner decides otherwise (§12). **[DIFF]** a deliberate Godot difference. **[CENTRE]** an old
Phaser position measured from the player sprite centre (Godot `player.get_centre()` = feet −
(0, 27.56)).

---

## 0. Scope and Phaser file map

| Concern | Phaser | Tag |
|---|---|---|
| Placement mode: ghost, snap, reach, tints, outline, variants, place press | `features/building/FurniturePlacementController.ts:1-176` | [IN] |
| Wiring: describe, free test, commit, modal handle, hint | `scenes/WorldScene.ts:1199-1253` | [IN] |
| Who may start it; the two entry points | `WorldScene.ts:1219-1223`, `:2295-2301` (`onCrafted`), `:2313` (`onPlaceInventoryItem`), `features/ui/InventorySurfacePort.ts:135-136, 195-200` | [IN] |
| Input while placing | `WorldScene.ts:1773-1786`; the caller and the move `:878-885` | [IN] |
| What placing blocks | `WorldScene.ts:543-544` (pause menu), `:820` (interaction), `:2077` (menu key); `features/ui/WorldMapSurfacePort.ts:101` (map key, via the modal stack) | [IN] |
| Pick-up | `WorldScene.ts:1255-1277`; `features/world/UniversalSceneWorldController.ts:1003-1008` (`pickUpAction`), `:1010-1035` (bench candidate) | [IN] |
| Mount, unmount, restore, describe | `UniversalSceneWorldController.ts:435-438, 1784, 1788-1844, 1846-1880` | [IN] |
| Script-less furniture provider (`placed-furniture`, priority 40) | `UniversalSceneWorldController.ts:1073-1095` | [OUT] no such content (§8.5) |
| Records and ids | `features/progression/WorldProgress.ts:84-89, 162-171, 201-208, 481-509`; `infrastructure/persistence/SaveSchema.ts:45-52, 79-81, 269-276`; `SaveRepository.ts:102-109, 153-156, 186-188` | [IN] |
| Content | `content/items/items.json` (`workbench`), `content/recipes/RecipeCatalog.ts:4-9`, `content/scenes/authored/objects/interiors/workshop/interior-workshop-workbench{,-vise}.scene.json` | [IN] (data) |
| Station script | `features/scripts/WorkbenchScript.ts` (interaction spec §3.6) | ported (`workbench.gd`) |
| Quest event | `content/quests/types.ts:272-279`, `quests/QuestEventBridge.ts:22, 78-80`, `quests/matchers/ObjectiveMatchers.ts:105-107, 126`, `content/quests/quests/chapterOne.ts:20-66` | Godot side ported (`quest_objectives.gd`) |
| `furniture.picked-up` event | `core/EventBus.ts:45-46`, emitted `WorldScene.ts:1274` | [IN] as a signal (nobody listens in Phaser) |
| Placed beds (bed ids, respawn) | `features/rest/RespawnDestination.ts:5-12, 24-35`, `WorldScene.ts:1267-1273` | [OUT] no placeable bed; hooks noted in §8.4 |
| Preloading the placeable scenes | `config.ts:75-76` | [IN] (warm the PackedScenes) |
| Controls text | `features/shell/ControlsSurfacePort.ts:13` | already in `game/shell/control_labels.gd` |

---

## 1. Content

### 1.1 The item and its recipe

`items.json` `workbench`: name "Workbench", category `furniture`, icon
`interior-workshop-crafting-8x8` frame 8, `placeable.sceneIds` =
`["object.interior-workshop-workbench", "object.interior-workshop-workbench-vise"]` (variant 0 and 1,
in this order). Max stack **1** (`game-constants.json` `inventory.maxStackByItem.workbench`), so every
bench needs its own bag slot (20 slots, `inventory.initialMaxSlots`). It is the only placeable item.

Recipe `craft-workbench` "Workbench": station `portable` (craftable from the bag's Crafting tab
anywhere), tier 1, 40 wood → 1 workbench (`RecipeCatalog.ts:4-9`).

### 1.2 The two object scenes

Both are a `StaticBody2D` root at (0, 0), `collisionLayer 1` (world), `collisionMask 0`, with one
rectangle `CollisionShape2D`, one `Sprite2D` and one `game.workbench` ScriptNode.

| | `object.interior-workshop-workbench` | `object.interior-workshop-workbench-vise` |
|---|---|---|
| Sprite | sheet `sheet.interiors.workshop-crafting.8x8` (128 × 128 frames, 8 × 8), **frame 8** | same sheet, **frame 9** |
| Sprite origin, scale | (0.5, 1), 0.85 × 0.85 → drawn 108.8 × 108.8, bottom centre on the root | same |
| Depth | `world-sorted`, band `world-entities` (sorts by the root y) | same |
| Collider centre (rel. root) | (0, −17.1445) | (−0.425, −16.966) |
| Collider size | 79.288 × 27.489 | 80.036 × 27.132 |
| Script `game.workbench` | prompt "Use workbench", recipeContext `workbench`, interactRadius 90, badgeRise 76.85 | same, badgeRise 76 |

Converted (`godot/game/scenes/objects/interiors/workshop/interior-workshop-workbench{,-vise}.tscn`,
through `WorldService.scene_path`): root `StaticBody2D` "workbench" / "workbench-vise",
`y_sort_enabled`, `collision_mask = 0` (layer 1 by default); `BodyShape` with a
`RectangleShape2D` of the sizes above at the positions above; `Visual` `Sprite2D`
`centered = false`, `offset (−64, −128)`, `scale 0.85`, `hframes 8`, `vframes 8`, `frame 8/9`;
`WorkbenchScript` (`workbench.gd`, group `crafting_station`) with the exports above. **No
`depth_anchor`**: the Godot root position equals the old Phaser position.

### 1.3 Placeable visual and footprint (`describePlaceable`, `UniversalSceneWorldController.ts:1846-1880`)

From the scene document, not from a mounted instance:
- the **first** `Sprite2D` node in document order; its texture subresource's `assetId` must exist in
  the asset manifest, else the scene is not placeable (`undefined`);
- `frame` (default 0), `scale` (default (1, 1)), `origin` (default (0.5, 1)), `rotation` (default 0)
  of that sprite; `visualOffset` and the sprite's own `position` are ignored;
- the footprint: the **first** `CollisionShape2D` in document order (whatever body it belongs to)
  whose shape subresource has numeric `width` and `height` → `{x, y}` = the shape node's `position`,
  `{width, height}`. A circle (no width/height) or no shape → **no footprint** (walk-over art).

Footprint rectangle for a root at (X, Y) (`FurniturePlacementController.ts:166-175`):
`(X + fx − w/2, Y + fy − h/2, w, h)`.

| Root at (704, 640) | x | y | w | h | right | bottom |
|---|---|---|---|---|---|---|
| workbench | 664.356 | 609.111 | 79.288 | 27.489 | 743.644 | 636.6 |
| workbench-vise | 663.557 | 609.468 | 80.036 | 27.132 | 743.593 | 636.6 |

---

## 2. Starting placement

### 2.1 Entry points
1. **Crafting a placeable** (`WorldScene.ts:2295-2301`, crafting spec §3.1): after a successful
   craft whose output item has `placeable`: close the crafting window, `startFurniturePlacement(output)`,
   then "Crafted: <recipe name>" green **big** at [CENTRE] − (0, 44). Nothing else (no belt logic).
   The crafting window's MenuClose cue plays; the placement itself makes no sound.
2. **The bag's Place button** (`InventorySurfacePort.ts:135-136, 195-200`, crafting spec §6.3-6.4):
   the primary button reads "Place" for a placeable item and is **enabled** (`primaryDisabled` is
   false for a placeable). `use-or-equip` on a placeable: close the bag, then
   `startFurniturePlacement(def.id)`.

### 2.2 `startFurniturePlacement(itemId)` (`WorldScene.ts:1219-1223`)

Silently does nothing when: no controller, the game is paused (any pause source), a travel runs
(`transitioning`), the slime is dead, or the bag holds no `itemId`. Otherwise
`controller.start(itemId, item.placeable.sceneIds ?? [])`.

`start` (`FurniturePlacementController.ts:73-90`):
1. no scene ids → false;
2. `cancel()` any running placement (so a second start replaces the first);
3. remember the item, the ids, `variantIndex = 0` (always the first variant);
4. build the ghost for variant 0 (§3.2); if the scene cannot be described → `cancel()`, false
   (nothing shown, the item stays in the bag) [QUIRK: silent];
5. `onActiveChange(true)`: opens the modal handle `furniture-placement` (§2.4);
6. the controls hint as small white floating text at [CENTRE] − (0, 56) (`WorldScene.ts:1210`),
   700 ms like every small text:
   - more than one variant (the Workbench): **`Left click to place · Mouse wheel to switch · Right click or Esc to cancel`**
   - one variant: **`Left click to place · Right click or Esc to cancel`**
   The labels come from the bindings (`controlLabel('attack')`, `'weapon-next'`, `'interact'`,
   `'pause'`); the separator is " · " (U+00B7 with spaces).

### 2.3 Cancel (`:92-102`)

Forgets the item, the visual and the target, destroys the ghost and the outline and, if it was
active, `onActiveChange(false)` (closes the modal handle). No text, no sound. **The item was never
taken**, so it simply stays in the bag.

### 2.4 What "active" changes elsewhere

| Effect | Where |
|---|---|
| The interaction router is suppressed: no candidate, prompt and badge hidden | `WorldScene.ts:820` (`setSuppressed(sleeping \|\| placing)`) |
| The pause menu cannot open (`canOpen` false) | `:543-544` |
| The menu key does not open the bag | `toggleMenu`, `:2077` |
| The map key does not open the map (a modal surface is active) | `WorldMapSurfacePort.ts:101` |
| Esc closes the top modal = cancels placement (DOM capture listener, works during hit-stop) | `ui/ModalStack.ts` `handleKeyDown`, `closeTopmost` |
| Picking up furniture is refused | `:1258` |
| No MenuOpen / MenuClose cue for this modal | `AudioEventBridge.ts:54` (`SILENT_MODALS`), `:104-109` |
| The game is **not** paused, the music does not duck | the handle is registered without a pause |

Not blocked [QUIRK]: the HUD ability bar still fires abilities (`activateAbilityFromUi`,
`WorldScene.ts:1705-1709`, only checks paused / dead / movement suppressed), and the HUD weapon
hotbar still switches weapons (`switchWeaponSlot`, `:2157-2161`). Zoom keys work.

---

## 3. Each step while placing

### 3.1 `update()` (`FurniturePlacementController.ts:105-124`)

Runs every fixed step from `updateGameplay` (`WorldScene.ts:823`), **before** the player's input is
handled the same step, never while paused (menus, hit-stop), and **also while the slime is dead**
(the dead check comes after it, `:840-846`).

```
world   = camera.getWorldPoint(activePointer.x, activePointer.y)   # the last pointer position
x       = round(world.x / 32) * 32          # SNAP_PX 32 (:47); JS Math.round: halves go up
y       = round(world.y / 32) * 32
reach   = distance(player centre, (x, y)) <= 220                    # REACH_PX (:49); player.x/y = [CENTRE]
rect    = footprint at (x, y)  (§1.3), or none
valid   = reach and (rect == none or isAreaFree(rect))              # §4
target  = {x, y, valid}
ghost.position = (x, y); ghost.tint = valid ? 0x9dffc8 : 0xff7a7a
outline.clear(); if rect: lineStyle(2, same colour, 0.9); strokeRect(rect)
```

Reach is measured from the player centre to the bench root (the sprite's bottom centre), not to
the footprint. Examples from the level-1 spawn, centre (640, 704):

| Pointer (world) | Target | Distance | Reach |
|---|---|---|---|
| (700, 650) | (704, 640) | 90.51 | yes |
| (640, 740) | (640, 736) | 32 | yes (but the footprint covers the player, §4) |
| (900, 704) | (896, 704) | 256 | **no** |
| (800, 650) | (800, 640) | 172.33 | yes |

### 3.2 The ghost and the outline (`:151-164`)

- Ghost: an image of the variant's texture and frame, origin, scale and rotation from §1.3, alpha
  **0.65**, multiplied by the tint (`setTint` is a multiply tint). Depth = the `overhead-artwork`
  band base exactly (`DEPTH_BANDS['overhead-artwork']` = 3·10⁹, `presentation/WorldDepth.ts:33-34`):
  above every world entity (`world-entities` = 2·10⁹ + y-quanta) and below every overhead sprite
  with a ground y > 0 (canopies are 3·10⁹ + y-quanta).
- Outline: a Graphics at band + 1, a **2 px** stroke (centred on the rectangle's edge) in the tint
  colour at alpha **0.9**, around the footprint only (no outline for walk-over art).
- The ghost is created at (0, 0) and moved on the first `update()`, one step later [QUIRK,
  invisible]. A variant switch destroys and recreates the ghost, keeps the outline.

Colours as Godot modulates: valid `Color(0.6157, 1.0, 0.7843, 0.65)` (`#9dffc8`, α 0.65), invalid
`Color(1.0, 0.4784, 0.4784, 0.65)` (`#ff7a7a`).

### 3.3 Variants (`cycleVariant`, `:127-132`)

With fewer than two scene ids nothing happens. Else `variantIndex = (index + step + count) % count`
and the ghost is rebuilt. Wheel down (`weapon-next`) = +1, wheel up (`weapon-previous`) = −1. The
Workbench toggles bench (frame 8) ↔ bench with vise (frame 9). There is no text.

---

## 4. The free-area test (`WorldScene.isFootprintFree`, `:1225-1235`)

```
if rect.x < 0 or rect.y < 0 or rect.x + rect.w > world width or rect.y + rect.h > world height: false
if physics.overlapRect(rect, includeDynamic = false, includeStatic = true) is not empty: false
false if rect overlaps the player's Arcade body rect (strict: touching edges do not overlap)
true
```

What counts as blocking:
- **every Arcade static body in the static tree**, whatever its collision layer: each
  `StaticBody2D` (walls, trees, houses, rocks, chests, beds, benches, **other placed benches**) and
  every merged tile body of the ground layer (`water`, `deep-water`, `rock-wall`, with Phaser's
  outer-edge inset). Every authored `StaticBody2D` is on layer 1; water tile bodies are on the
  water layer (11), rock walls on layer 1;
- the player's body: 30 × 26 centred at [CENTRE] + (0, 14.56) (at the spawn: x 625-655,
  y 705.56-731.56).

What does **not** count: dynamic bodies other than the player (enemies, NPCs, projectiles), every
`Area2D` (pickup piles, exits, door and story triggers, plates, gulp spots), decals and other
art without a static body.

Edge rules: Phaser's static-tree search (`OverlapRect.js`, rbush) is inclusive, so a footprint that
only touches a static body's edge is refused. `overlapRect` does not look at `body.enable`, and a
static body whose collision is switched off stays in the tree at its last rectangle
(`PhysicsBody2DNode.ts:84, 169` only clear `enable`; `PhaserNodeContext.sightBlocked :96-103` has
to skip `!body.enable` for the same reason), so an opened gate's old body very likely still blocks
placement [QUIRK]. The comment on `isAreaFree` says "terrain, objects, actors", but the only actor
checked is the player [QUIRK].

Example (level-1): near the spawn there is no static body or solid tile within 320 px (only wood
and stone piles, which are areas), so (704, 640) and (800, 640) are free. The pond south-east of
the spawn holds the water body `water_21_12` (centre (1440, 800), 172 × 44 → x 1354-1526,
y 778-822): a bench at (1440, 832) (footprint y 801.111-828.6) is refused.

---

## 5. Input while placing (`WorldScene.handleActionInput`, `:1773-1786`)

The placement branch is the **first** thing `handleActionInput` checks, before the weapon wheel,
the interact hold, interact, the abilities, attack and eat:

```
if placement.active:
    if consume('attack'):          placement.handlePointerDown()   # §6
    if consume('weapon-next'):     placement.cycleVariant(+1)
    if consume('weapon-previous'): placement.cycleVariant(-1)
    if consume('interact'):        placement.cancel()
    for a in [jump, dodge, stretch-lash, squash-slam, teleport, eat]: consume(a)   # dropped
    return false
```

- **Returning false means the slime keeps walking**: the step continues to
  `squashOnMoveStart` + `playerController.move(direction)` (`:883-884`). Sprint (a held key) works.
  The reach follows the slime.
- Attack never swings while placing; the wheel never switches weapons; abilities and eat presses
  are thrown away (not buffered for later). All presses are the usual buffered presses (150 ms,
  `input.bufferMs`), consumed in this order within one step: a step with both attack and interact
  places first, then the interact cancels an already finished placement (no-op).
- When `handleActionInput` is not reached (paused, dead, sleeping, roll or knockback, action
  locked, eat wheel open) the presses wait in the buffer and die after 150 ms.
- **Esc** (`pause`) is not a player action: the modal stack's capture listener cancels (§2.4).

| Input | Effect |
|---|---|
| Left click (`attack`) | place at the target (§6); refused → hint text |
| Right click (`interact`) | cancel |
| Esc (`pause`) | cancel; the pause menu does not open |
| Wheel down / up | next / previous variant |
| WASD + Shift | walk / sprint as usual |
| Space, 1-4, Q | ignored (consumed) |
| E (menu), M (map) | nothing |
| HUD ability bar / hotbar clicks | still act [QUIRK, §2.4] |

---

## 6. Placing

### 6.1 The press (`handlePointerDown`, `:135-145`)

```
if not active: return false
if target is none or not target.valid or no item:
    hint(target and not target.valid ? "Can't place it there" : "Aim at a free spot")   # white small, [CENTRE] − (0, 56)
    return true                           # the press is used up; placement stays active
if place({itemId, sceneId: sceneIds[variantIndex], x: target.x, y: target.y}): cancel()
return true
```

"Aim at a free spot" needs a press before the first `update()`; in practice it is never seen.
Every refused click spawns another text.

### 6.2 The commit (`WorldScene.placeFurniture`, `:1237-1253`)

```
mapId = loaded map id; name = item name ("Workbench")
1. inventory.transact(remove [{itemId, 1}], add [])             → false: return false (silently)
2. record = worldProgress.placeFurniture(mapId, request)          # id + sequence, world.progress.changed (autosave)
3. if not world.mountPlacedFurniture(record):                     # §7.1
       worldProgress.removePlacedFurniture(mapId, record.id)       # the sequence stays used [QUIRK]
       inventory.transact([], add [{itemId, 1}])
       text "<name> could not be placed" white BIG at (x, y − 48)
       return false                                                # placement stays active
4. emit 'furniture.placed' {mapId, placementId: record.id, itemId, sceneId, x, y}   # §9
5. text "Placed <name>" green small at (x, y − 48)
6. return true                                                     # → cancel()
```

The bench is taken from the bag's first matching slot. No sound plays.

### 6.3 The record

Phaser (`SaveSchema.ts:45-52`, in `MapRuntimeStateData.placedFurniture`, keyed by id):
`{id, itemId, sceneId, x, y}` with `nextPlacedFurnitureSequence` beside it.

Godot (RunState, snake_case like the other map records; the keys already exist in
`RunState.map_record`):

```
map_record(map_id)["placed_furniture"] = {
    "placed-furniture-1": {"id": "placed-furniture-1", "item_id": "workbench",
                           "scene_id": "object.interior-workshop-workbench", "x": 704.0, "y": 640.0},
}
map_record(map_id)["next_placed_furniture_sequence"] = 2
```

Ids: `placed-furniture-<n>`, `n` = the map's sequence (starting at 1), which then grows by one;
removing a record never lowers it. `x`, `y` are the snapped target (multiples of 32, old Phaser
space = the Godot root position for these scenes). Records are kept in insertion order (JS object
string keys; Godot Dictionaries keep order and JSON round-trips keep it).

Loading a Phaser save (`WorldProgress.ts:162-171, 201-208`, `SaveRepository.ts:102-109`): records
that fail `isPlacedFurniture` (string id/itemId/sceneId, finite x/y) are dropped, the key wins over
the stored `id`, and the sequence is `max(stored sequence ≥ 1, 1 + the highest numeric id)`.
[QUIRK] `cloneMapState` (`WorldProgress.ts:84-89`) and the repository (`:186-188`) write
`placedFurniture` **and the sequence** only when at least one record exists, so after picking
everything up and saving, the next placement in that map reuses `placed-furniture-1`. Harmless
today (quest facts are per objective and the objective is done by then). **[DIFF]** Godot keeps
the sequence (the record always carries it); ids are never reused.

---

## 7. Mounting and restoring

### 7.1 `mountPlacedFurniture(record)` (`UniversalSceneWorldController.ts:1810-1827`)

1. Already mounted (same id) → true.
2. `runtime.mountScene(sceneId(record.sceneId), {runtimeNamespace: "placed-furniture-" + id,
   position: (x, y)})` (the namespace reads `placed-furniture-placed-furniture-1`, harmless). A
   throw → `console.error`, false.
3. `registerInteractables(root, placementId)` (`:1788-1808`): every door, gate, bed, gulp spot,
   workbench and restoration-site script under the root joins its provider set and is mapped to
   the placement id (`scriptPlacement`).
4. Remember `{record, mount, scripts}`; flush.

The bench is then an ordinary world object: its `StaticBody2D` blocks the player, enemies and
NPCs (and other placements, §4), it blocks enemy sight (79 × 27 is over the 20 px minimum), and its
sprite sorts with the world entities by its root y (the sprite's bottom). Placed furniture is
**not** an authored root, so resource drop cells ignore it (`isAuthoredCellOccupied` uses
`authoredRoots`, filled only from the world scene, `:1780-1783`) [QUIRK: piles can land under a
bench].

### 7.2 Unmount (`:1829-1844`)

Remove each of the placement's scripts from every provider set and from `scriptPlacement`, forget
the placement, dispose the mount, flush.

### 7.3 Restore on world load

`mountAuthoredWorld` (`:1784`): after the world scene and its authored instances are mounted,
every record of the map from `worldProgress.placedFurniture(mapId)` is mounted, in record order.
A record whose scene is unknown logs an error, mounts nothing and **stays in the save** (the bench
is lost to the player: it cannot be seen or picked up) [QUIRK]. Teardown clears the maps
(`:1735-1736`). The scenes are preloaded with every world because `config.ts:75-76` adds each
placeable scene id to the load list.

---

## 8. The placed bench and picking it up

### 8.1 The station

The mounted bench's `WorkbenchScript` is an ordinary `world-workbenches` candidate (interaction
spec §2.3, `UniversalSceneWorldController.ts:1010-1035`): reach 90 from the root, priority **88**,
id `world-workbenches:<runtimeId>`, prompt "Use workbench", badge at root − (0, 76.85) (76 for the
vise), pointer pick point root − (0, 24). Execute: `openCraftingStation({station: "workbench",
tier: 1})` (`WorldScene.ts:1279-1285`: refused while paused or with crafting / the bag open; emits
`workbench.opened {mapId, context}`).

Because its script belongs to a placement, the candidate also carries
`secondary = {prompt: "Pick up", execute: pickUpFurniture(placementId)}` (`pickUpAction`,
`:1003-1008`). The prompt line becomes **`Right-click: Use workbench     Hold: Pick up`** (five
spaces, `InteractionRouter.ts:27-31`).

At the spawn (640, 704) a bench at (704, 640) is 90.51 px away: just out of reach. At (704, 700)
it is 60 px away.

### 8.2 The hold (`WorldScene.ts:151, 1794-1806, 1836-1853`)

In `handleActionInput`, after the placement branch and the weapon wheel:

```
if updateInteractHold(): return true
if consume('interact'):
    if router.hasCandidate():
        hints.learn('interact')
        if router.hasSecondary(): interactHold = {since: simulationNow}
        else: router.handleInteract()
    return true

updateInteractHold():
    if no hold: return false
    if not router.hasSecondary(): hold = none; return false          # target changed: nothing runs
    if simulationNow − since >= 450: hold = none; router.handleSecondary(); return true   # INTERACT_HOLD_MS
    if interact still held: return true
    hold = none; router.handleInteract(); return true                  # released early: the main action
```

So on a **placed** bench the crafting window opens on the **release** of the right button (an
authored bench opens on the press), and holding 450 ms of simulation time picks it up instead.
While the button is held `handleActionInput` returns true, so `move()` is skipped and the body
keeps its last velocity for up to 27 steps [QUIRK, interaction spec §2.7]. The hold time stops
during hit-stop and menus (simulation clock).

### 8.3 `pickUpFurniture(placementId)` (`WorldScene.ts:1255-1277`)

```
record = this map's record with that id; false if none, if paused, or while placing
name = item name
if not inventory.previewTransact([], [{record.itemId, 1}]):
    text "Inventory full" white BIG at (record.x, record.y − 56); return false
worldProgress.removePlacedFurniture(mapId, id)          # world.progress.changed (autosave)
world.unmountPlacedFurniture(id)
inventory.transact([], [{itemId, 1}])
respawn = worldProgress.respawnPoint
if respawn and respawn.mapId == mapId and (respawn.bedId is set
        ? respawn.bedId == "placed-furniture:" + id
        : distance(respawn, record) < 128):
    worldProgress.clearRespawnPoint()                    # a picked-up bed cannot be woken in
emit 'furniture.picked-up' {mapId, placementId, itemId} # no listener in Phaser
text "Picked up <name>" cyan small at (record.x, record.y − 56)
return true
```

With the workbench the bag needs one free slot (max stack 1). [QUIRK] The legacy branch (a respawn
point without `bedId`, only in old saves) clears the respawn point when **any** furniture, a bench
included, is picked up within 128 px of it.

### 8.4 Placed beds [OUT]

No placeable bed exists. For one: the bed's id is `placed-furniture:<placementId>`
(`RespawnDestination.ts:10-12`, used by `bedCandidate` `:1127-1132` and by `worldHasBed`), and
the bed candidate gets the same "Pick up" secondary. Godot `bed.gd bed_id()` would have to return
that form when its root carries the `placement_id` meta (§11.6).

### 8.5 Script-less furniture provider [OUT]

`furnitureCandidate` (`:1073-1095`) offers placed furniture **without** any interactable script:
nearest record within 90 px (literal) of the player centre, id `placed-furniture:<placementId>`,
prompt "Pick up", priority **40**, badge at (x, y − 72), pick point (x, y − 24), a plain press picks
it up. The workbench has a script, so this never fires today; port it with the first such item.

---

## 9. The quest event

`furniture.placed` payload (`content/quests/types.ts:272-279`): `{mapId, placementId, itemId,
sceneId, x, y}`, emitted only after a successful mount (§6.2 step 4). The bridge hands it to the
quest service (`QuestEventBridge.ts:22, 78-80`). Matcher `place-item` (`ObjectiveMatchers.ts:105-107`):
matches when `itemIds` contains `itemId`, amount 1, fact id = `placementId` (counted once per
objective). The map is not checked.

"A Place to Work" (`chapterOne.ts:20-66`, quests spec §7.1 row 1): given by the Village Elder;
stage `build-workbench` (`craft-workbench`, craft-item `workbench` × 1, "Craft a Workbench (40
wood)"), then stage `place-workbench` (`place-workbench`, place-item `workbench` × 1, "Place the
Workbench"); turn in to the Elder for 20 wood and the stone axe and pickaxe recipes. The craft
completes stage 1 before `onCrafted` starts placement, so the usual flow is craft → place → done.

Not retroactive: there is no "known fact" for place-item, so a bench placed before the stage is
active does not count; picking it up and placing it again does (a new placement id). Quests spec
test `test_place_fact_counts_once` covers the dedupe; Godot's `quest_objectives.gd` already maps
`place-item` → `furniture.placed` with fact `placementId`.

---

## 10. Quirks (port as is unless §12 decides otherwise)

| # | Quirk | Where |
|---|---|---|
| K1 | Placement stays active when the slime dies; the ghost keeps following the pointer, and after the respawn the bench can still be placed | `update` runs before the dead check (`WorldScene.ts:823, 840`); nothing cancels on death |
| K2 | Only the player is checked among actors: a bench can go on an NPC, an enemy, a pickup pile, a pressure plate, a gulp spot, an exit trigger or a door approach; bodies inside it are pushed out by the physics | §4 |
| K3 | An opened gate's (switched-off) static body very likely still blocks placement; touching edges block | §4 |
| K4 | The controls hint is a 700 ms floating text, then gone | §2.2 |
| K5 | The HUD ability bar and weapon hotbar still act while placing | §2.4 |
| K6 | A placed bench opens on release; holding keeps the walking velocity for up to 450 ms | §8.2 |
| K7 | A failed mount uses up a sequence number; an unknown scene in a saved record hides the bench for good | §6.2, §7.3 |
| K8 | Phaser drops the sequence with the last record on save, so ids restart at 1 ([DIFF] in Godot) | §6.3 |
| K9 | Resource drop piles ignore placed benches | §7.1 |
| K10 | A respawn point without a bed id (old saves) is cleared by picking up any furniture within 128 px | §8.3 |
| K11 | A silent no-op when the scene cannot be described or the game is paused; crafting a Workbench while dead closes the crafting window and only shows "Crafted" | §2.1-2.2 |
| K12 | A bench placed on the spawn or an arrival point makes the slime arrive inside it (pushed out by the next move) | spawn and travel never check furniture |

---

## 11. Godot port plan

### 11.1 Files

| File | Kind | Content |
|---|---|---|
| `game/building/furniture_placement.gd` (new) | `class_name FurniturePlacement extends Node2D`; child "FurniturePlacement" of main, made once in `_ready`, kept across worlds; group `furniture_placement` | Placement mode (start, cancel, variants, per-step target, ghost and outline, free test, commit), pick-up, world restore and teardown. The Phaser controller plus the `WorldScene` glue |
| `game/building/placed_furniture.gd` (new) | `class_name PlacedFurniture extends RefCounted`, static | `describe(scene_id)` (§1.3 from the PackedScene), `mount(record)`, `find(placement_id)`, `unmount(placement_id)`, `mounted_ids()` |
| `godot/tests/test_furniture.gd` (new) | tests | §11.10 |

No new scene script: the benches use the ported `workbench.gd`.

### 11.2 RunState additions (`game/autoload/run_state.gd`)

```gdscript
## Copies of the map's placed-furniture records ({"id", "item_id", "scene_id", "x", "y"}), in
## placement order (WorldProgress.placedFurniture).
func placed_furniture(map_id: String) -> Array[Dictionary]
## WorldProgress.placeFurniture: records {item_id, scene_id, x, y} as "placed-furniture-<n>" with
## n = max(next_placed_furniture_sequence, 1 + highest numeric id); the sequence becomes n + 1;
## emits world_progress_changed {"map_id"}. Returns a copy of the record.
func place_furniture(map_id: String, item_id: String, scene_id: String, x: float, y: float) -> Dictionary
## WorldProgress.removePlacedFurniture: the removed record (copy), {} when there was none; never
## lowers the sequence; emits world_progress_changed when something was removed.
func remove_placed_furniture(map_id: String, placement_id: String) -> Dictionary
## WorldProgress.clearRespawnPoint: respawn_point becomes {}.
func clear_respawn_point() -> void
```

`map_record` already creates `placed_furniture: {}` and `next_placed_furniture_sequence: 1`; read
them with `get_or_add` so a record from an older Godot save without the keys still works.
`serialize`/`install` need no change (the record rides in `world.maps`).

### 11.3 `PlacedFurniture` (static helpers)

```gdscript
const META := &"placement_id"
const GROUP := &"placed_furniture"

## §1.3 from the converted scene: {} when the scene is unknown or has no Sprite2D. Else
## {"scene_id", "sprite": Sprite2D (a detached duplicate of the first Sprite2D in tree order,
## keeping texture, hframes/vframes, frame, centered, offset, flip, scale, rotation, position),
## "footprint": Rect2 relative to the root (the first CollisionShape2D whose shape is a
## RectangleShape2D: Rect2(position − size/2, size)) or null, "depth_anchor": Vector2}.
## Instantiates the cached PackedScene (WorldService.packed_scene), reads it, frees the instance.
static func describe(scene_id: String) -> Dictionary

## WorldService.spawn_at_phaser_position(record.scene_id, Vector2(x, y)) under entities_root();
## then name = record.id, set_meta(META, record.id), add_to_group(GROUP). Null (push_warning, the
## record stays) when the scene id is unknown or the root is not a Node2D. Already mounted → the
## existing node.
static func mount(record: Dictionary) -> Node2D
static func find(placement_id: String) -> Node2D               # group GROUP + meta
static func unmount(placement_id: String) -> void              # remove_child + queue_free
```

Mounting under the y-sorted world root gives everything §7.1 needs with no extra code: the
converted `StaticBody2D` (layer 1, mask 0) blocks the player (mask 1157), enemies and NPCs and stops
projectiles and enemy sight (`line_of_sight` mask 1); the root's `y_sort_enabled` and the
`Visual` at (0, 0) sort the bench by its root y against the player's feet, as in Phaser;
`workbench.gd` joins `crafting_station` in `_enter_tree`, so the interaction controller offers it
at once; `spawn_at_phaser_position` resets physics interpolation. The placed root has no `owner`
and no `instance_id` meta, so `ResourceDrops.occupied_cells` ignores it, as Phaser does (K9).

### 11.4 `FurniturePlacement` API

```gdscript
const SNAP_PX := 32.0                       # FurniturePlacementController.ts:47
const REACH_PX := 220.0                     # :49
const VALID_TINT := Color("#9dffc8")        # :50
const INVALID_TINT := Color("#ff7a7a")      # :51
const GHOST_ALPHA := 0.65                   # :160
const OUTLINE_WIDTH := 2.0                  # :121
const OUTLINE_ALPHA := 0.9                  # :121
const HINT_RISE := 56.0                     # WorldScene.ts:1210 (above [CENTRE])
const PLACED_TEXT_RISE := 48.0              # :1245, :1251 (above the target)
const PICK_UP_TEXT_RISE := 56.0             # :1261, :1275 (above the record)
const RESPAWN_CLEAR_PX := 128.0             # :1271
## Blocking layers for the query: world (1) | player (2) | water (11) = 1 | 2 | 1024.
const BLOCKING_MASK := 1027

signal placement_changed(payload: Dictionary)   # {"active": bool, "item_id": String}
signal message_shown(payload: Dictionary)       # {"text", "color", "big", "x", "y"} (test hook)
signal placed(payload: Dictionary)              # the record (after the mount)
signal picked_up(payload: Dictionary)           # {"mapId", "placementId", "itemId"} (furniture.picked-up)

var aim_override: Variant = null            # test hook: a world point used instead of the mouse

func is_active() -> bool
func item_id() -> String
func scene_ids() -> PackedStringArray
func variant_index() -> int
## {} before the first step, else {"x", "y", "valid": bool, "footprint": Rect2 or null}.
func target() -> Dictionary
## startFurniturePlacement + controller.start (§2.2). False when refused.
func start(item_id: String) -> bool
func cancel() -> void
func cycle_variant(step: int) -> void
## handlePointerDown (§6.1): true when active (the press is used), false otherwise.
func press_place() -> bool
## One update() (§3.1) for `pointer` (world point). _physics_process calls it every step.
func update_target(pointer: Vector2) -> void
func is_footprint_free(rect: Rect2) -> bool
## The commit (§6.2). False when nothing was placed.
func place(item_id: String, scene_id: String, point: Vector2) -> bool
## pickUpFurniture (§8.3).
func pick_up(placement_id: String) -> bool
## Mounts every record of `map_id` (§7.3). main._build_world calls it.
func restore_world(map_id: String) -> void
## World teardown: cancel (no text); the mounted benches go with the world root.
func clear() -> void
static func snap(value: float) -> float     # floor(value / SNAP_PX + 0.5) * SNAP_PX (JS Math.round)
```

Process: `PROCESS_MODE_ALWAYS` (so Esc reaches it during a hit-stop, like the DOM modal stack),
`process_physics_priority = -5` (after SimClock −1000 and the interaction controller −10, before
the player 0, so the attack press of a step sees that step's target). `_physics_process` returns
while `get_tree().paused`; otherwise, when active, `update_target(aim_override if set else
get_global_mouse_position())`. Main is a plain `Node2D` at the origin under the camera, so the
mouse position is already in world space.

`snap` uses `floor(v / 32 + 0.5)` rather than GDScript `round()`: they differ only for negative
halves (`round(-0.5)` is −1, JS gives −0), which matters only outside the world.

Texts and colours go through `GameFeel.floating_text(point, text, colour, big)` (small 700 ms, big
900 ms) and `message_shown`; there are no audio cues.

### 11.5 The ghost, the outline and the free test

- **Ghost**: a Node2D "Ghost" child holding the `describe()` sprite, placed at the target +
  `depth_anchor` (zero for the benches), `modulate = Color(tint, 0.65)`, hidden until the first
  `update_target`. Rebuilt on a variant switch.
- **Outline**: a Node2D "Outline" child whose `_draw` does `draw_rect(footprint, Color(tint, 0.9),
  false, 2.0)` (Godot centres an unfilled rect's stroke on the edge, as Phaser does); no footprint →
  nothing drawn.
- **Depth**: `z_index 0` on the FurniturePlacement node, which is a child of main **after** `World`.
  Godot sorts by z first, then by tree order, so the ghost draws after every `z 0` world item
  (entities, y-sorted) and before every `z 1` world item (the converter puts `overhead-artwork` at
  z 1, `scripts/godot/lib/sprite.mjs:17`): exactly Phaser's band base. The outline is the next
  sibling, so it draws over the ghost.
- Both use `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF`: they jump in 32 px steps
  set in `_physics_process`, and interpolation would smear the jumps.

**Free test: recommend a physics shape query** (`PhysicsDirectSpaceState2D.intersect_shape`):

```gdscript
func is_footprint_free(rect: Rect2) -> bool:
	var world := Services.world()
	if world == null or not world.world_rect().encloses(rect):       # Phaser's four bound checks
		return false
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, rect.get_center())
	query.collision_mask = BLOCKING_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 32):
		var collider: Object = hit.get("collider")
		if collider == world.player_body:
			return false
		if collider is StaticBody2D and (collider as Node).name != &"WorldBounds":
			return false
	return true
```

| | Shape query (recommended) | Tile grid (`is_solid_tile` per covered cell) |
|---|---|---|
| Props, houses, trees, chests | their real colliders, as Phaser | missed (they are not tiles) |
| Water and rock walls | the converter's merged tile bodies with Phaser's inset, as Phaser | whole 64 px cells: refuses spots Phaser allows next to water |
| Other placed benches | yes (they are StaticBody2Ds) | missed unless tracked separately |
| The player | yes (`player_body` is on layer 2) | missed |
| Enemies, NPCs, projectiles | filtered out (CharacterBody2D), as Phaser | — |
| Cost | one query per step while placing | a few cell lookups |

Notes: run it only from the physics step (`update_target` is called there). The mask keeps
character and area hits out of the 32 results. `WorldBounds` lies outside the world rect and can
only touch an enclosed footprint, so it is skipped by name. [DIFF] Godot's query skips disabled
shapes (an opened gate no longer blocks, K3) and probably does not report a pure edge touch; at a
32 px snap neither is reachable with the benches' footprints. A body added this step may only be
seen by the query after the next physics step; tests wait 2 steps after a placement.

### 11.6 Changes to existing files

| File | Change |
|---|---|
| `game/main.gd` | `_ready`: `add_child(FurniturePlacement.new())` (named "FurniturePlacement"; any time after `World`, i.e. with the other runtime children). `_build_world`: `furniture.restore_world(target_map_id)` right after `WorldBounds.build` (synchronous, so the benches exist before the first step and before the player spawns, as in Phaser). `_teardown_world`: `furniture.clear()` before the world root is freed. `warm_runtime_scenes`: `packed_scene()` every `placeable.sceneIds` entry of every item (Phaser `config.ts:75-76`). Header comment: the new child |
| `game/scripts/player.gd` `_handle_action_input` | New order: (1) placement branch (§5): when `FurniturePlacement.is_active()`, consume `attack` → `press_place()`, `weapon_next` → `cycle_variant(1)`, `weapon_previous` → `cycle_variant(-1)`, `interact` → `cancel()`, then consume and drop `jump, dodge, stretch_lash, squash_slam, teleport, eat`; **return false** (the step walks). (2) the existing wheel loop. (3) the interact hold (§8.2, `INTERACT_HOLD_MS := 450.0` on `Services.now_ms()`, `_input.is_held(&"interact")`). (4) the interact press: with a candidate → hold when `has_secondary()`, else `handle_interact()`; return true. (5) abilities, attack, eat as now. Find the node by group `furniture_placement` (cache it like `_interaction`) |
| `game/interaction/interaction_controller.gd` | Candidates may carry `"secondary": {"prompt", "execute"}`. `_nearest` adds `{"prompt": "Pick up", "execute": pick_up(id)}` for a workbench (and a bed) whose parent root has the `placement_id` meta. `prompt_text`: `"<verb>: <prompt>     Hold: <secondary prompt>"` (5 spaces). New `has_secondary()`, `handle_secondary() -> bool` (emits `interacted` like `handle_interact`). `_physics_process`: `set_suppressed(sleeping or placing)`. Docs: priorities list unchanged (benches stay 88) |
| `game/inventory/inventory_actions.gd` `on_crafted` | A placeable output: close the crafting window (`menu_windows` group → `crafting.close()`), `FurniturePlacement.start(output)`, then "Crafted: <recipe name>" green big at centre − 44 (`WorldScene.ts:2296-2300`); remove the C1 note |
| `game/ui/screens/inventory_model.gd` | `primary_disabled` no longer includes `placeable` (Phaser `:136`) |
| `game/ui/screens/inventory_screen.gd` `use_or_equip` | placeable → `close()` the bag, then `FurniturePlacement.start(item_id)`; return (no refresh) |
| `game/ui/screens/menu_windows.gd` `can_open_menu` | false while placing (`toggleMenu :2077`) |
| `game/ui/map/map_ui.gd` `can_open_from_key` | false while placing (Phaser: an active modal surface) |
| `game/shell/shell.gd` `can_open_pause` | false while placing (`WorldScene.ts:543-544`); placement already eats Esc first, this covers other openers |
| `game/scripts/bed.gd` `bed_id` | [OUT, no placeable bed] when the bed's root has `placement_id`: `"placed-furniture:" + id` |

Esc: `FurniturePlacement._unhandled_input`: while active, a non-echo press of `pause` or `ui_cancel`
→ `cancel()` and `set_input_as_handled()`. Main's children hear unhandled input before the Shell
autoload (the same rule GameWindows relies on), so the pause menu never opens; GameWindows only
eats input while a window is open, which never coincides with placing.

Quest event: in `place` after the mount, `QuestEvents.emit(QuestEvents.FURNITURE_PLACED, {"mapId":
map_id, "placementId": id, "itemId": item_id, "sceneId": scene_id, "x": x, "y": y})` (camelCase keys,
ARCHITECTURE §5). Nothing else is needed on the quest side.

Pick-up in Godot: `pick_up` refuses while `get_tree().paused` or active; preview with
`run.transact_items([], [{"item_id": id, "count": 1}], true)`; then `remove_placed_furniture`,
`PlacedFurniture.unmount`, `transact_items([], [...])`, the respawn rule of §8.3 on
`run.respawn_point()` (Godot always writes `bed_id`, so the 128 px branch only runs for an empty
one), `picked_up` signal, the cyan text. Call `interaction.refresh()` afterwards so the freed
bench is not offered for another step.

Docs to update in the same change (AGENTS.md "keep docs truthful"): ARCHITECTURE.md (tree diagram,
file map row "building", call map), crafting.md §3.1 / §6.4 / C1 / `test_drop_disabled_for_workbench`
(Place is enabled), interaction.md §2.2, §2.7 steps 1 and 3, §3.6 ("Hold: Pick up" [IN]), quests.md
§7.6 and §10.4 (furniture placement no longer blocked), GODOT_MIGRATION.md status.

### 11.7 Behaviour checklist for the port

1. Placing never pauses; the slime walks and sprints; reach follows it.
2. One target per step, computed before the player's press handling.
3. Refused press: hint, placement continues. Success: placement ends.
4. The bag item is taken only on a successful commit; cancel and failure keep it.
5. Records persist through `world_progress_changed` → autosave, and come back on load and travel.
6. The bench is a priority 88 station; release opens it, a 450 ms hold picks it up.
7. `furniture.placed` once per successful placement.

### 11.8 Owner-independent [DIFF]s

- Ids are never reused (K8).
- Disabled bodies and edge touches (K3).
- Esc also cancels during a hit-stop (Phaser does the same through the DOM, so this is parity, not
  a difference; noted because the Godot node must be `PROCESS_MODE_ALWAYS` for it).

### 11.9 Risks

- `player.gd`, `interaction_controller.gd`, `inventory_actions.gd`, the bag and the menu windows
  are being edited by the crafting agent; land this after that work, and re-read their current
  shapes (the wheel loop and `_capture_wheel` in `player.gd` are new).
- The hold changes when a placed bench's crafting window opens (release, not press); the crafting
  tests that open a station should use an authored bench or tap and release.

### 11.10 Tests (`godot/tests/test_furniture.gd`)

Helpers: the controller is `t.tree.get_first_node_in_group(&"furniture_placement")`; the run is
`Services.run()`. A fresh level-1 has the player centre at (640, 704) and the trial sword in the
bag (1 slot used). Give benches with `run.add_item("workbench", n)`. Tests never move the mouse:
set `placement.aim_override` and wait 1 step. Wheel steps need 160 ms between taps
(`input.weaponWheelStepLockMs` 150). Wait 2 steps after a placement before querying physics.

| Test | Setup and action | Expected |
|---|---|---|
| `test_describe_and_helpers` | static | `snap(700) == 704`, `snap(650) == 640`, `snap(16) == 32`, `snap(-16) == 0`, `snap(-17) == -32`; `describe("object.interior-workshop-workbench")`: sprite frame 8, hframes 8, vframes 8, scale (0.85, 0.85), offset (−64, −128), footprint `Rect2(-39.644, -30.889, 79.288, 27.489)` (±0.001); the vise: frame 9, footprint `Rect2(-40.443, -30.532, 80.036, 27.132)`; `describe("object.nope") == {}` |
| `test_start_shows_ghost_hint_and_blocks` | 1 workbench; `start("workbench")` | true, `is_active()`, `variant_index() == 0`; `message_shown` text `Left click to place · Mouse wheel to switch · Right click or Esc to cancel`, white, small, at centre − (0, 56) = (640, 648); interaction has no candidate; `menu_windows.can_open_menu()`, `map_ui.can_open_from_key()` and `Shell.can_open_pause()` false; the tree is not paused. Without a bench: `start` false, nothing shown |
| `test_valid_target_in_reach` | active; aim (700, 650), 1 step | `target() == {x 704, y 640, valid true, footprint Rect2(664.356, 609.111, 79.288, 27.489)}`; ghost at (704, 640), visible, modulate ≈ (0.6157, 1, 0.7843, 0.65) |
| `test_invalid_targets` | aim (900, 704) | target (896, 704) invalid, ghost modulate ≈ (1, 0.4784, 0.4784, 0.65); tap `attack` → text `Can't place it there` white small at (640, 648), still active, `item_count("workbench") == 1`, no swing (`is_action_locked()` false). Aim (640, 740) → (640, 736) invalid (covers the player). Teleport (1440, 700), aim (1440, 832) → invalid (pond water body). Teleport (120, 704), aim (16, 704) → (32, 704) invalid (footprint x −7.644 < 0) |
| `test_place_commits_record_and_event` | aim (700, 650), tap `attack`, 2 steps | not active; `item_count("workbench") == 0`; `placed_furniture("level-1") == [{"id": "placed-furniture-1", "item_id": "workbench", "scene_id": "object.interior-workshop-workbench", "x": 704.0, "y": 640.0}]`; `next_placed_furniture_sequence == 2`; `PlacedFurniture.find("placed-furniture-1")` is a StaticBody2D at global (704, 640), collision layer 1, in group `crafting_station` through its WorkbenchScript; text `Placed Workbench` green small at (704, 592); the quest service received `furniture.placed` `{"mapId": "level-1", "placementId": "placed-furniture-1", "itemId": "workbench", "sceneId": "object.interior-workshop-workbench", "x": 704.0, "y": 640.0}` (spy via a stub node in group `quests` with `handle_event`) |
| `test_wheel_cancel_and_esc` | 1 bench, active; tap `weapon_next` | `variant_index() == 1`, ghost frame 9, equipped weapon unchanged; 160 ms, tap `weapon_previous` → 0; tap `interact` → inactive, bench still in the bag, the press opened nothing; start again, tap `pause` → inactive and no Shell window open; start again, 160 ms + tap `weapon_next`, aim (700, 650), tap `attack` → record `scene_id == "object.interior-workshop-workbench-vise"` |
| `test_player_walks_while_placing` | active, aim (700, 650); press `move_right` 500 ms | centre x grew by about 100 px (base speed 200 px/s; check > 90) and placement is still active; tap `jump` → no jump started (ability not busy) and still active |
| `test_second_bench_blocked_by_first` | 2 benches; place at (704, 640); 2 steps; start; aim (700, 650) | invalid; aim (800, 650) → (800, 640) valid (172.33 px, footprint x 760.356-839.644 clear of the first); place → id `placed-furniture-2`, sequence 3 |
| `test_bench_station_and_hold_pick_up` | place at (704, 640); teleport (704, 700); 2 steps | candidate id starts with `world-workbenches:` and ends with `placed-furniture-1/WorkbenchScript`, priority 88, prompt `Right-click: Use workbench     Hold: Pick up`, candidate `anchor()` (704, 563.15). Then press `interact`, `sim_wait(460)`, release: node gone after 1 step, `placed_furniture("level-1") == []`, sequence still 2, `item_count("workbench") == 1`, text `Picked up Workbench` cyan small at (704, 584), `picked_up` `{"mapId": "level-1", "placementId": "placed-furniture-1", "itemId": "workbench"}`; with a fresh placement a tap (press + release in one step) runs the station instead and picks nothing up |
| `test_pick_up_refused_when_bag_full` | place; fill the bag (`add_item("wood", item_capacity("wood"))`); teleport (704, 700); hold 460 ms | text `Inventory full` white **big** at (704, 584); the record and the node remain; no `picked_up` |
| `test_restore_on_load` | place at (704, 640); `run.save_slot(SLOT)`; `t.main.load_run(SLOT)`; 3 steps | `PlacedFurniture.find("placed-furniture-1")` at (704, 640) with meta `placement_id`; the player cannot walk through it (teleport (704, 700), press `move_up` 600 ms: the centre stops at y ≈ 635.04, the body top 1.56 px below the centre against the footprint bottom 636.6); a record with an unknown scene id mounts nothing and stays in the run |
| `test_place_completes_a_place_to_work_stage` | quests: `accept("a-place-to-work", "village-elder-plop")`, `handle_event("craft.completed", {"recipeId": "craft-workbench", "itemId": "workbench", "quantity": 1})`; give 1 bench; `inventory_actions.on_crafted({"recipe": {"name": "Workbench", "output": {"itemId": "workbench", "count": 1}}})` | placement active; text `Crafted: Workbench` green big at (640, 660); place at (704, 640) → `view("a-place-to-work").ready_to_turn_in`, consumed facts of `place-workbench` == `["placed-furniture-1"]` |

---

## 12. Owner questions

| # | Question | Recommendation |
|---|---|---|
| F1 | Placement survives the slime's death (K1): the ghost keeps following a dead slime and the bench can be placed after the respawn. Keep, or cancel on death? | Cancel on death (the item never left the bag, so nothing is lost); a one-line `defeated` hook |
| F2 | Only the player is checked among actors (K2): benches can cover NPCs, enemies, piles, plates, gulp spots, exits and door approaches. Keep? | Keep (parity). If it bites, also refuse overlaps with `trigger`-layer areas (exits) and NPC bodies |
| F3 | The controls hint is gone after 0.7 s (K4). Keep the floating text, or show it on the interaction prompt line (hidden anyway while placing) for as long as placement lasts? | Keep parity first; the prompt line is a cheap follow-up |
| F4 | On a placed bench the crafting window opens on release, and a 450 ms hold picks it up (K6). Keep the hold, or offer "Pick up" inside the crafting window instead? | Keep (parity; the Controls window already says "hold to pick up placed furniture") |
| F5 | HUD ability bar and hotbar act while placing (K5). Keep? | Keep (parity); trivial to gate later |
| F6 | A bench may be placed on the level-1 spawn or an arrival point (K12). Refuse spots within some distance of the spawn marker, door arrivals and bed wake points? | Keep; the mover pushes the slime out |
