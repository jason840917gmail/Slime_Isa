# World objects spec: destructibles, resource nodes, collectibles, inventory

Source of truth: the Phaser app on `feat/godot-migration` (read 2026-10-05). Paths are under
`src/game/` unless they start with `src/`, `godot/` or `scripts/`. `file:line` refers to the
current tree. Godot files under `godot/game/` are cited the same way; `run_state.gd`,
`fatty.gd` and parts of `main.gd` were uncommitted work in progress when this was written, so
cite them by function name rather than line.

Binding inputs: [ARCHITECTURE.md](../ARCHITECTURE.md), [CONVENTIONS.md](../CONVENTIONS.md),
[combat.md](./combat.md) (the damage pipeline this spec plugs into) and [runtime.md](./runtime.md)
(payload filters, audio helpers).

Legend: **[IN]** port now. **[OUT]** exists in Phaser but is deferred (listed so later phases
know). **[QUIRK]** the Phaser build behaves in a way its code or content probably did not
intend; port it as is unless the owner decides otherwise (section 11).

Coordinates: none of the scenes in this spec has a `depthAnchor`. Their Godot roots sit exactly
at the old Phaser root position: the sprite bottom-centre for trees, stones and ore (Visual
origin `[0.5, 1]`), and the pickup centre for collectibles. The only feet/centre conversion in
this spec is the player (`loot-sparkle` at the player centre, 7.4).

---

## 0. Scope

### IN

| Feature | Phaser |
|---|---|
| `game.resource-node` script: health, damage reception, harvest gate, hit feedback, destruction, drops, persistence | `features/scripts/ResourceNodeScript.ts`, `DestructibleScript.ts` |
| Hit feedback: tint, damage text, hit effect, on-hit clip then idle clip, SFX via signals | `ResourceNodeScript.ts:138-151`, `UniversalSceneWorldController.ts:2133-2151` |
| Harvest-blocked text and wrong-tool SFX | `ResourceNodeScript.ts:98-118`, `UniversalSceneWorldController.ts:639-641` |
| Drop spawning: amount, cell search, scatter offsets, launch animation, depletion text | `features/resources/ResourceNodeController.ts`, `ResourceDropPlacement.ts`, `UniversalSceneWorldController.ts:1471-1574`, `collectibles/WorldDropMotion.ts` |
| Regrowth of harvested nodes (at world load, wall-clock timer) | `features/resources/ResourceRespawn.ts`, `UniversalSceneWorldController.ts:614-636` |
| `game.collectible` script: walk-over pickup, transactional, partial, inventory full, depletion | `features/scripts/CollectibleScript.ts`, `features/collectibles/CollectibleController.ts`, `features/progression/InventoryWorldTransaction.ts:51-81` |
| Player pickup handler | `features/scripts/PlayerScript.ts:52-56` |
| Inventory: slots, capacity, stacking, max stacks, item names | `systems/Inventory.ts`, `content/items/ItemCatalog.ts`, `content/items/items.json`, `game-constants.json` `inventory` |
| World records: resource and collectible state per map | `features/progression/WorldProgress.ts:386-436`, `infrastructure/persistence/SaveSchema.ts:20-43` |
| Pickup feedback: `+N Item` text, `Inventory full` text, pickup / full SFX, `loot-sparkle` particles | `CollectibleController.ts:76-99`, `scenes/WorldScene.ts:435-437` |
| Purple berry reaction: `eat` clip with action lock, +5 coins per berry (low priority) | `collectibles/CollectibleReactionController.ts:30-35`, `WorldScene.ts:1855-1877` |

### OUT

- `game.destructible` as a scene script of its own: **no scene uses it** (0 instances in all
  authored scenes). Its behaviour is IN, inside the resource node (12.2).
- Save files. The records live in the `RunState` autoload (in memory, kept across world swaps);
  writing them to `user://` is the save phase.
- ~~Inventory UI (`ui.inventory-ui`), dropping items from the bag (`InventoryDropController.dropFromSlot`),
  restoring bag drops (`InventoryDropController.restore`, `WorldScene.ts:2389`), the `recovered` flag.~~
  Done with crafting (2026-10-05, [crafting.md](./crafting.md) §6): the bag window, drops
  (`game/inventory/inventory_drops.gd`), restored with the loot records (`EnemyLoot.restore_world`).
- Enemy loot piles (`InventoryDropController.dropLoot`; worm swordsman drops a `shard` 20 % of
  the time, `enemy-types.json`). Enemy rewards are OUT in the combat spec. The collectible
  script must still accept `source_inventory_drop_id` so these piles can come later.
- Quest hooks: `collectible.collected` feeds `quests/QuestEventBridge.ts:42`; `nearestSource`
  hints (`UniversalSceneWorldController.ts:1168-1187`).
- Abilities touching these objects: Stretch Lash pulling a pile (`lashPull`, `:1350-1384`);
  Squash Slam skips every receiver tagged `resource` (`strikeArea`, `:1408`).
- ~~The belt/bag advice appended to the harvest message (`WorldScene.ts:2188-2203`)~~: done with
  the belt (crafting spec §8.8, `InventoryActions.harvest_message`); the `harvest_blocked` payload
  keeps the plain message.
- HUD coin flash (`flashHudCoins`, `UniversalSceneWorldController.ts:883-889`), occlusion
  silhouettes, the dev overlay, crafting (the stone axe and pickaxe cost 10 wood + 10 stone each
  at a workbench, `content/recipes/RecipeCatalog.ts:16-23`).

Trial consequence: the trial equips only the basic sword, which has **no harvest capability**.
Every tree and stone hit is therefore blocked ("Requires an Axe" / "Requires a Pickaxe").
Wood and stone come only from the six loose piles in level-1. Harvesting needs another weapon
(`PlayerCombat.equip("stone-axe")`), so tests equip one (12.9). An optional dev launch option
for this is in 12.8.

---

## 1. Object map and data sources

### 1.1 Scene structure (authored, converted by `pnpm godot:convert`)

| Scene family | Root | Children (converted names) | Layers |
|---|---|---|---|
| Resource node (`object.resource-*`, `object.tree-world-solid*`, `object.rock-amber-ore-mineable`) | `StaticBody2D` (collision layer 1 = world, mask 0) | `BodyShape`, `Visual` (Sprite2D, origin `[0.5,1]`), `DamageArea` (Area2D layer 8 hurtbox, mask 16, monitoring false, monitorable true) > `DamageShape` (same shape as BodyShape), optional `Animation` or `AmbientAnimation` (AnimationPlayer), `ResourceNodeScript` (Node), SFX players | Player body mask 1157 includes 1, so trees and stones block movement and (layer 1) enemy sight |
| Collectible (`object.collectible-*`) | `Node2D` | `Visual` (Sprite2D), `PickupArea` (Area2D layer 64, mask 32, monitoring false, monitorable true) > `PickupShape` (circle at (0,0)), `CollectibleScript` (Node), `PickupSfx`, `InventoryFullSfx` (berry basket: none) | — |
| Player (`character.player-slime`, Godot-owned `game/characters/player_slime.tscn`) | `CharacterBody2D` | `PickupArea` (layer 32, mask 64, monitoring true) at (0, −27.56) > `PickupShape` rect 30×26 at (0, 14.56) (same rect as the hurtbox) | connection `PickupArea.area_entered → PlayerScript.on_pickup_area_entered` (tscn line 1143) |

Until the ports exist, the converter attaches `res://game/runtime/unported_script.gd` to the
`ResourceNodeScript` and `CollectibleScript` nodes (raw `properties`, `signal_names` registered as
user signals so the SFX connections load). Example:
`godot/game/scenes/objects/tree-world-solid--tree-autumn-01.tscn`.

### 1.2 Script properties (descriptor `features/scripts/registrations.ts:370-442`) and Godot exports

The converter snake-cases JSON keys (`scripts/godot/lib/script-props.mjs:29`) and writes only
the exports the script declares. Node references become typed Node exports listed in the
`node_paths` header.

**`game.destructible`** (`registrations.ts:370-394`), inherited by the resource node:

| JSON key | Export | Type | Descriptor default | Phaser read (`DestructibleScript.ts`) |
|---|---|---|---|---|
| `mapId` | `map_id` | String | required | `:79`, `''` fallback |
| `instanceId` | `instance_id` | String | required | `:80` |
| `objectId` | `object_id` | String | required | `:81` |
| `damageArea` | `damage_area` | Area2D | required reference | `:134` (throws when missing and not destroyed) |
| `maxHealth` | `max_health` | float | 1 | `:82` `max(1, value)` |
| `initialHealth` | `initial_health` | float | 0 | `:83-84` `> 0 ? min(max, initial) : max` |
| `tags` | `tags` | Array[String] | `[]` | `:85`, strings only, authored order kept |
| `damageRule` | `damage_rule` | Dictionary | `{priority: 0, damageMultiplier: 1}` | `:187-199` (priority 0 and multiplier 1 when absent) |

**`game.resource-node`** (`registrations.ts:396-418`, `extends: 'game.destructible'`):

| JSON key | Export | Type | Default | Read |
|---|---|---|---|---|
| `drop` | `drop` | Dictionary | `{}` | `ResourceNodeScript.ts:183-188`: needs `objectId` string, `visualId` string and `pieces` number, else no drop; `pieces = max(1, floor(pieces))` |
| `idleAnimationId` | `idle_animation_id` | String | `''` | `:75-78` |
| `hitEffectId` | `hit_effect_id` | String | `''` | `:146` |
| `onHitAnimationId` | `on_hit_animation_id` | String | `''` | `:76, 139, 147` |
| `persistHealth` | `persist_health` | bool | **true** | `:134-136` |
| `depletionMessage` | `depletion_message` | String | `''` (controller falls back to `"Resource depleted"`, `ResourceNodeController.ts:52`) | `:167` |
| `harvestRequirement` | `harvest_requirement` | Dictionary | `{}` | `:173-181`: needs `targetTag` string, `minimumTier` number and `failureMessage` string, else no requirement |
| `animation` | `animation` | AnimationPlayer | none (optional reference) | `:123-125` |

**`game.collectible`** (`registrations.ts:420-442`):

| JSON key | Export | Type | Default | Read (`CollectibleScript.ts`) |
|---|---|---|---|---|
| `mapId` | `map_id` | String | required | `:48` |
| `instanceId` | `instance_id` | String | required | `:49` |
| `objectId` | `object_id` | String | required | `:50` |
| `itemId` | `item_id` | String | required | `:51` |
| `quantity` | `quantity` | int | 1 | `:52` `max(1, floor(value))` |
| `sourceResourceInstanceId` | `source_resource_instance_id` | String | `''` = none | `:53-54` |
| `sourceInventoryDropId` | `source_inventory_drop_id` | String | `''` = none | `:55-56` |
| `pickupArea` | `pickup_area` | Area2D | required reference | `:67-69` (throws when missing) |

World instances override only `position`, `mapId` and `instanceId` (e.g. `level-1.scene.json`
instance `level-1-loose-wood-01`). The one exception is `test-rectangle` (dev only):
`initialHealth = 30` on its amber ore. Runtime piles override `mapId`, `instanceId`,
`quantity` and `sourceResourceInstanceId` (`UniversalSceneWorldController.ts:1492-1502`).

### 1.3 Authored resource nodes (every `game.resource-node` scene)

All of them have `damageRule {priority: 0, damageMultiplier: 1}`.

| Scenes | `objectId` | HP | `tags` | drop (pile scene × pieces) | `hitEffectId` | on-hit / idle clip | `persistHealth` | depletion message | requirement (tag ≥ tier, message) | hurtbox (rect, at) | SFX connections |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `resource-stone-node` | `resource.stone-node` | 80 | stone, resource, solid | `collectible.stone-pile` × 3 | `stone-impact` | `""` / — | **false** | Stone broken | stone ≥ 1, "Requires a Pickaxe" | 105×48 at (−1.5, −54) | `harvest_blocked → WrongToolSfx`, `drops_requested → CrumbleSfx` (detached) |
| `resource-stone-node.big-stone-mine` | `resource.stone-node` | 80 | same | same | `stone-impact` | `""` | **false** | Stone broken | stone ≥ 1 | 100×60 at (1, 6) | same |
| `resource-iron-node` | `resource.iron-node` | 120 | iron, resource, solid | `collectible.iron-ore-pile` × 2 | `stone-impact` | `""` | **false** | Iron ore broken | iron ≥ 2, "Requires a Reinforced Pickaxe" | 100×48 at (0, −40) | `resource_hit → ClinkSfx`, `harvest_blocked → WrongToolSfx`, `drops_requested → ShatterSfx` (detached) |
| `rock-amber-ore-mineable` | `rock.amber-ore.mineable` | 30 | rock, solid, mineable (**no `resource`**) | `collectible.crystal-shard` × 1 | `""` (none) | `""` | true | Ore depleted | `{}` (**none**) | 42×16 at (1, −29) | Clink, WrongTool, Shatter |
| 45 `tree-world-solid*` variants (47 tree scenes, all but the two below) | `tree.world.solid` | 40 | wood, resource, tree, solid | `collectible.wood-pile` × 1 | `wood-impact` | `""` / — | true | Tree felled | wood ≥ 1, "Requires an Axe" | per variant, e.g. 68×40 at (−2, −34), grove-tree-04 44×42 at (0, −24) | `resource_hit → RustleSfx` (volume 0.8), `harvest_blocked → WrongToolSfx`, `drops_requested → FallSfx` (detached) |
| `tree-world-solid.snow-pine` | same | 40 | same | same | `wood-impact` | `""` / `object.tree.idle` (`animation` ref set) | true | Tree felled | wood ≥ 1 | — | same |
| `tree-world-solid.tree-autumn-01` | same | 40 | same | same | `wood-impact` | `object.tree.autumn.leaf-fall` (0.6 s, 10 fps, no loop) / `object.tree.autumn.idle` (2 s loop, autoplay, randomized start) | true | Tree felled | wood ≥ 1 | 54×41 at (0, −27.5) | same |

Many tree variants also have an `AmbientAnimation` AnimationPlayer (autoplay
`object.ambient.idle`) that the script does not reference. Every WrongToolSfx has
`minIntervalMs` 200 and `pitchRandomness` 0.06.

Hit effects (`content/scenes/authored/effects/wood-impact.scene.json`, `stone-impact.scene.json`):
a Node2D root with `Impact1` (Sprite2D, scale 0.65, base alpha 0), clips `right/left/up/down`
(0.333 s at 12 fps), `EffectScript` with `lifetimeMs` 333.33, and `ImpactSfx` (autoplay,
detached, pitch randomness 0.07: `chop-wood` 3 variants, or `mine-stone` 4 variants). Both
are converted (`godot/game/scenes/effects/`).

### 1.4 Authored collectibles (every `game.collectible` scene)

All PickupAreas are layer 64, mask 32, monitoring false, monitorable true, with a circle at (0,0).
PickupSfx: detached, pitch 0.06, `payloadFilter "status=collected|partial"`. InventoryFullSfx:
`sfx.pickup.inventory-full`, `minIntervalMs` 600, `payloadFilter "status=rejected"`.

| Scene `object.` | `objectId` | `itemId` | quantity | pickup radius | PickupSfx sound |
|---|---|---|---|---|---|
| `collectible-wood-pile` | `collectible.wood-pile` | wood | 10 | 21.504 | pickup/wood |
| `collectible-small-wood-pile` | `collectible.small-wood-pile` | wood | 5 | 32 | pickup/wood |
| `collectible-stone-pile` | `collectible.stone-pile` | stone | 10 | 21.504 | pickup/stone |
| `collectible-small-stone-pile` | `collectible.small-stone-pile` | stone | 5 | 32 | pickup/stone |
| `collectible-iron-ore-pile` | `collectible.iron-ore-pile` | iron-ore | 5 | 32 | pickup/ore |
| `collectible-charcoal-pile` | `collectible.charcoal-pile` | charcoal | 5 | 32 | pickup/stone |
| `collectible-crystal-shard` | `collectible.crystal-shard` | shard | 1 | 12 | pickup/ore |
| `collectible-iron-bar` | `collectible.iron-bar` | iron-bar | 1 | 12 | pickup/ore |
| `collectible-weaver-fang` | `collectible.weaver-fang` | weaver-fang | 1 | 12 | pickup/ore |
| `collectible-silk-clump` | `collectible.silk-clump` | silk-clump | 1 | 12 | pickup/silk |
| `collectible-purple-berry` | `collectible.purple-berry` | purple-berry-mat | 1 | 12 | pickup/berry |
| `collectible-hp-potion` | `collectible.hp-potion` | hp-potion | 1 | 12 | pickup/potion |
| `collectible-energy-potion` | `collectible.energy-potion` | energy-potion | 1 | 12 | pickup/potion |
| `collectible-green-key` | `collectible.green-key` | green-key | 1 | 17.92 | pickup/key |
| `collectible-crystal-key` | `collectible.crystal-key` | crystal-key | 1 | 17.92 | pickup/key |
| `collectible-berry-basket` | `collectible.berry-basket` | berry-basket | 1 | 14.336 | **none** (no SFX nodes, no connections) [QUIRK] |

A resource drop's amount per pile is the drop scene's authored `quantity`
(`UniversalSceneWorldController.collectibleQuantity`, `:1517-1525`, throws if not a positive
integer): wood pile 10, stone pile 10, iron-ore pile 5, crystal shard 1.

### 1.5 Signals, payloads (camelCase keys, as in Phaser) and listeners

| Script | Signal | Payload | Emitted | Scene listeners |
|---|---|---|---|---|
| destructible | `health_changed` | `{mapId, instanceId, health, maxHealth}` | each positive hit, after the HP change (`DestructibleScript.ts:108-114`) | none |
| destructible | `damaged` | the router commit | after `health_changed` (`:115`) | none |
| destructible | `damage_feedback` | the commit | from `publishDamageFeedback` when `actualDamage > 0` (`:120-122`) | none |
| destructible | `destroyed` | `{mapId, instanceId, objectId}` | on destruction, before the drops (`:151-153`) | none |
| resource node | `resource_hit` | `{mapId, instanceId, objectId, actualDamage, x, y, effectId?, animationId?}` (optional keys only when non-empty) | each positive hit, after the hit feedback (`ResourceNodeScript.ts:138-151`) | RustleSfx (trees) / ClinkSfx (iron, amber) |
| resource node | `harvest_blocked` | `{mapId, instanceId, targetTag, minimumTier, message, x, y}` (`message` = the authored `failureMessage`) | each blocked attempt, inside `canReceiveDamage` (`:107-116`) | WrongToolSfx |
| resource node | `drops_requested` | `{mapId, instanceId, objectId, dropObjectId, dropVisualId, pieces, x, y, depletionMessage?}` | once, after the drops are spawned (`:153-171`) | FallSfx / CrumbleSfx / ShatterSfx (detached) |
| collectible | `pickup_resolved` | `{status: "collected"|"partial", moved, remaining}` or `{status: "rejected", moved: 0, remaining, reason}` | every pickup request (`CollectibleScript.ts:99`) | PickupSfx (`status=collected|partial`), InventoryFullSfx (`status=rejected`) |
| collectible | `depleted` | the pickup request `{mapId, instanceId, objectId, itemId, requested, collectorAreaNodeId, x, y, sourceResourceInstanceId?, sourceInventoryDropId?}` | when not rejected and `remaining == 0` (`:100`) | none |

`x, y` are the node's world position (resource: the script's parent `global_position`,
`ResourceNodeScript.ts:197-200`; collectible: the PickupArea's `global_position`,
`CollectibleScript.ts:77-80`). The InventoryFullSfx filter matches **every** rejection reason,
not only `inventory-full`. In Godot, `collectorAreaNodeId` = `str(area.get_path())` (the
`receiverNodeId` convention, ARCHITECTURE section 5).

### 1.6 Constants and literals

| Value | Number | Source |
|---|---|---|
| resource regrow time | 600 000 ms (10 min, wall clock) | `game-constants.json` `resources.respawnMs` |
| inventory slots at a new run | 20 | `inventory.initialMaxSlots` |
| max stack per item | table 8.2 | `inventory.maxStackByItem` (must list exactly the items.json ids, `ItemCatalog.ts:10-13`) |
| weapon max stack | 1 | `inventory.weaponMaxStack` |
| resource hit tint | `#ffd277` for 110 ms real time | literal `UniversalSceneWorldController.ts:2136-2140` |
| resource hit text | `-<round(actual)>` white small at (x, y − 54) | `:2142` |
| harvest-blocked text | message, cyan big, at (x, y − 58) | `:640` |
| depletion text | message, yellow big, at (x, y − 46) | `ResourceNodeController.ts:110` |
| pickup text | `+<moved> <item name>` yellow small at (x, y − 34) | `CollectibleController.ts:91` |
| inventory-full text | `Inventory full` white big at (x, y − 34), at most once per 1000 ms | `CollectibleController.ts:77-80` |
| loot sparkle | particles at player centre − (0, 24) | `WorldScene.ts:435` |
| drop flight | 280 ms linear, stagger 60 ms per piece, rebound 40 ms up 4 px, settle 60 ms | `collectibles/WorldDropMotion.ts:6-13` |
| drop arc height | `clamp(0.45 × distance, 28, 56)` px | `WorldDropMotion.ts:15-22` |
| scatter offsets | golden angle 2.399963229728653 rad, radius `min(0.42·ts, 0.1·ts·√k)` | `ResourceDropPlacement.ts:11-19` |
| purple berry coins | 5 per berry | `CollectibleReactionController.ts:33` |
| `eat` clip lock | clip length 0.1667 s → 167 ms | `player-slime.scene.json` animation `eat`, `WorldScene.ts:1855-1870` |

Text sizes and durations are the floating-text defaults (combat spec 12): big 22 px, 900 ms,
rise 48; small 15 px, 700 ms, rise 34. Colours: `GameFeel.TEXT_COLORS` (`cyan #72d8ff`,
`yellow #ffdf8a`).

---

## 2. Instances per world

Counted from `content/scenes/authored/worlds/*.scene.json` (top-level instances; no nested ones
exist). There are no `game.destructible` instances anywhere.

| World | Ships? | Resource nodes | Collectibles |
|---|---|---|---|
| **level-1** | yes | **58**: 48 trees + 10 stone (6 `resource-stone-node`, 4 `big-stone-mine`) | **15**: 9 purple berry, 4 wood pile, 2 stone pile |
| gloop-forest | yes (east of level-1, behind the Verdant Gate) | 3 iron nodes (`gloop-iron-1..3`) | 2 iron-ore piles, 1 berry basket (`gloop-ch2-sunny-basket` (1696, 168)) |
| gloop-cavern | yes | 0 | 3 crystal shards ((420,520), (520,700), (900,420)) |
| crystal-caverns, gloop-hut, mushroom-home, slime-home | yes | 0 | 0 |
| playground | dev | 9: trees (220,380), (520,420), (260,760), (600,820 autumn); stones (300,1080), (520,1140), big mine (400,1300); iron (200,1240), (640,980) | 8: wood pile (760,520), small wood (820,640), stone pile (760,1080), small stone (820,1200), silk ×2, lash-loot wood (2470,1296) and stone (2470,1600) |
| test-rectangle | dev | 1 amber ore (`initialHealth` 30) | 0 |
| depth-occlusion-test | dev | 3 trees | 0 |
| hot / jk / icege / girls / meadow-crossing / 236 | dev | 29 / 37 / 16 / 11 / 13 / 1 | 0 / 99 / 45 / 170 / 288 / 748 |
| tiktok / 174 / cole / emberleef / playground-cavern | dev | 131 / 0 / 0 / 0 / 0 | 812 / 356 / 679 / 505 / 3 |

Level-1 tree variants: red-tree 5; tree-autumn-01 4; green-tree-02 4; golden-tree-02 4;
ancient-bare-01 4; autumn-tree-01 3; grove-tree-04, green-tree-05, green-tree-04,
golden-tree-01 2 each; ancient-blossom, ancient-green, ancient-dark, grove-tree-01/-02/-06/-07/-09,
autumn-tree-02/-03/-04, ancient-bare-02/-05, shadow-pine-02, pine-05, pine-06 1 each.

Level-1 objects nearest the spawn (640, 704) (old Phaser positions = Godot positions):

| Instance | Scene | Position | Distance |
|---|---|---|---|
| `level-1-loose-wood-04` | wood pile | (608, 576) | 132 |
| `level-1-loose-wood-03` | wood pile | (704, 512) | 202 |
| `level-1-loose-wood-01` | wood pile | (512, 512) | 231 |
| `level-1-loose-stone-02` | stone pile | (832, 544) | 250 |
| `level-1-loose-wood-02` | wood pile | (608, 448) | 258 |
| `level-1-loose-stone-01` | stone pile | (800, 448) | 302 |
| `resource-stone-node-c64bd17b`, `-221c2835`, `-f518b5a3`, `-4c37387b` | big stone mine | (800,320), (864,320), (800,256), (864,256) | 416-501 |
| `level-1-stone-node-01`, `-02` | stone node | (1056, 352), (1184, 448) | 545, 601 |
| `level-1-tree-004` | grove-tree-04 | (527.25, 1254.95) | 562 |
| `level-1-purple-berry-03` | purple berry | (550.4, 1363.2) | 665 |
| `level-1-tree-01` | tree-autumn-01 | (281.6, 1356.8) | 745 |

In the converted `game/scenes/worlds/level-1.tscn` each instance root is a child of the
world root named after its instance id, with `metadata/instance_id` and `metadata/persistence_key`
(`"level-1.<id>"`). Phaser keys records by the script's `mapId` and `instanceId`, not by the
persistence key.

---

## 3. `game.destructible` (DestructibleScript.ts), the shared base

### 3.1 State

`health` (number), `destroyed` (bool), `maxHealth = max(1, maxHealth)`,
`health = initialHealth > 0 ? min(max, initial) : max` (`:82-84`).

### 3.2 Entering the tree (`_enter_tree`, `:124-138`)

1. Get the router and the world-object state port (`WORLD_OBJECT_STATE_SERVICE`, provided by
   `UniversalSceneWorldController.ts:614-636`).
2. `saved = state.load(mapId, instanceId, regrows())`. The port reads the map record, applies
   the regrow resolution when `regrows` is true (section 6), writes the record back if that
   changed it, and returns `{health: record.value, destroyed: record.stage != "node"}`, or
   nothing when there is no record.
3. If saved: `destroyed = saved.destroyed`; `health = destroyed ? 0 : clamp(saved.health, 0, max)`.
4. Destroyed: return. The area is **not registered**, so nothing can hit it; the world controller
   then frees the owner (4.7).
5. Else: the `damageArea` reference is required (throw otherwise); `router.registerArea(this,
   rule)` with the rule from `damageRule` (`:187-199`: `priority ?? 0`, `damageMultiplier ?? 1`,
   plus `acceptedSources`, `blockedWeaponTags`, `damageTypeMultipliers`, `effectResponses` passed
   through). It is unregistered on exit.

`_exit_tree` (`:140-142`) drops the state port. The router entry goes with the entry disposables.

### 3.3 Receiver API (combat spec 7.1)

```
getDamageState()      = {hp: health, maxHp: maxHealth, dead: destroyed}         :92-94
canReceiveDamage(in)  = destroyed ? {accepted: false, reason: "dead"} : {accepted: true}   :96-100
mitigateDamage        = none (raw scaled damage)
commitDamage(commit):                                                            :102-118
  if destroyed or commit.result.actualDamage <= 0: return       # 0-damage accepted hits do nothing
  health = max(0, health - actualDamage)
  if shouldPersistHealth(): state.saveHealth(mapId, instanceId, health)  # record {stage:"node", value: health}
  emit health_changed {mapId, instanceId, health, maxHealth}
  emit damaged(commit)
  onPositiveDamage(commit)                                       # resource node: hit feedback (4.3)
  if commit.result.defeated or health <= 0: destroyObject()
publishDamageFeedback(commit):                                                   :120-122
  if actualDamage > 0: emit damage_feedback(commit)
destroyObject():                                                                 :179-185
  if destroyed: return
  destroyed = true; health = 0
  state.markDestroyed(mapId, instanceId, regrows())
      # record {stage:"depleted", value:0, respawnReadyAtEpochMs: now + 600000 when regrows}
  onDestroyed({mapId, instanceId, objectId})                     # base: emit destroyed
```

Base hooks: `shouldPersistHealth() = true`, `regrows() = false`, `onPositiveDamage` = nothing.
A plain destructible is therefore destroyed for good. Nothing frees a plain destructible's owner
(only resource nodes are tracked by the controller, 4.7), so if one is ever authored, its owner
stays in the world, unhittable, until the next load.

---

## 4. `game.resource-node` (ResourceNodeScript.ts)

Overrides: `regrows() = true` (`:82`); `shouldPersistHealth() = persistHealth ?? true` (`:134-136`).

### 4.1 Entering the tree (`:120-126`)

The resource port (`RESOURCE_NODE_SERVICE`) is taken **before** the base `_enter_tree` (3.2).
Then the `animation` reference is resolved; if it is an AnimationPlayer, its `animation_finished`
is connected to the handler `on_animation_finished(animationId)` (`:75-78`): when `animationId ==
onHitAnimationId` (including `""`), play `idleAnimationId`.
`playAnimation(id)` (`:202-204`) does nothing when `id` is empty or the player lacks the clip;
otherwise it restarts the clip.

### 4.2 Harvest gate (`canReceiveDamage`, `:98-118`)

```
base = super.canReceiveDamage(input)           # "dead" when destroyed
if not base.accepted: return base
req = harvestRequirement()                     # {} or invalid -> none
if no req: return accepted
capability = max over request.weaponTags of harvestTier(tag, req.targetTag), starting at 0
harvestTier(tag, target) (:190-195):
    prefix = "harvest:" + target + ":"
    tag must start with prefix; tier = Number(rest); valid iff safe integer and > 0, else 0
if capability >= req.minimumTier: return accepted
blocked = {mapId, instanceId, targetTag, minimumTier, message: failureMessage, x, y}
port.publishHarvestBlocked(blocked)            # cyan big text at (x, y - 58) (below)
emit harvest_blocked(blocked)                  # -> WrongToolSfx (min interval 200 ms)
return {accepted: false, reason: "state-blocked"}   # retryable
```

The weapon tags come from `CombatController.tryAttack` (`CombatController.ts:167-170`):
`["spear"|"weapon", "harvest:<tag>:<tier>" for each weapon.json harvestCapabilities entry]`.
Godot's `PlayerCombat.try_attack` already builds them from the weapon scene's
`harvest_capabilities` (`player_combat.gd:140-142`, `_js_number` writes `1` and not `1.0`).

Harvest message text (`WorldScene.ts:2188-2203`): `message`, plus the belt/bag advice since the
belt was ported (crafting spec §8.8). Phaser adds `": switch with the mouse wheel"` when a belt weapon could harvest,
and `": put yours on the belt (E)"` when one is in the bag (labels from
`player/ControlLabels.ts`: `weapon-next` = WheelDown = "Mouse wheel", lowercased; `menu` = KeyE).

Because the rejection is `state-blocked` (retryable), the activation records nothing
(combat 7.1 step 7). The sword's per-window receiver set (combat 6.1) still limits it to **one
attempt, one text and one sound per swing window**. Everything after the router sees a
rejection: no feel, no effect, no crit sting (`CombatController.ts:202-210`).

Who can harvest what (weapon scenes, identical to `weapon.json` for these keys):

| Weapon | harvestCapabilities | Trees (wood ≥ 1) | Stone (stone ≥ 1) | Iron (iron ≥ 2) |
|---|---|---|---|---|
| basic-sword, spears, goo-gauntlet, slam-hammer | none | blocked | blocked | blocked |
| wooden-axe | **none** [QUIRK] | blocked | blocked | blocked |
| pickaxe | **none** [QUIRK] | blocked | blocked | blocked |
| stone-axe | wood 1 | yes | blocked | blocked |
| iron-axe | wood 2 | yes | blocked | blocked |
| stone-pickaxe | stone 1 | blocked | yes | blocked |
| reinforced-pickaxe | stone 2, iron 2 | blocked | yes | yes |
| any weapon vs amber ore | (no requirement) | — | — | — (always accepted) |

### 4.3 A positive hit: order of operations (one weapon contact on a tree, stone or ore)

Phaser order inside one fixed step (`PhaserSceneTreeHost.ts:100-111`; the weapon resolves in
the script `_physics_process` or in the contact pass):

1. Weapon: `transformManagedWeaponDamage(payload.damage × span.damageMultiplier, target)` =
   `max(0, round(damage × modifier(targetTags) × combo.registerHit()))`
   (`CombatController.ts:196-199`). `targetTags` = the node's authored `tags`
   (`managedTargetTags`, `UniversalSceneWorldController.ts:2195-2198`). Modifier = the first
   target tag in the node's order that has a weapon entry (`combat/DamageModifiers.ts`). The
   combo counts this hit **even if it is then blocked** [QUIRK].
2. Router: validate, activation, duplicate check (combat 7.1), then `resolveDamage`: dead check,
   scaled = base × 1, `canReceiveDamage` (4.2), no mitigation, `actual = min(hp, round(scaled))`,
   effects (the knockback potency is applied and ignored), `defeated = actual >= hp`.
3. `commitDamage` (3.3): HP, then (trees only, `persistHealth`) the record `{stage:"node", value:
   hp}`, `health_changed`, `damaged`, then `onPositiveDamage` (`:138-151`):
   1. `playAnimation(onHitAnimationId)` (only the autumn tree: `leaf-fall`, restarted on every
      hit; when it finishes, `object.tree.autumn.idle` restarts from frame 0).
   2. Build `request = {mapId, instanceId, objectId, actualDamage, x, y, effectId?, animationId?}`.
   3. `port.publishHit(request)` = `publishResourceHit` (`UniversalSceneWorldController.ts:2133-2151`):
      - the first Sprite2D under the owner (the `Visual`) gets a solid fill `#ffd277`
        (`setTintFill`); `scene.time.delayedCall(110)` clears it unless the owner was freed
        (real time, so it keeps running through a hit-stop);
      - floating text `-<round(actualDamage)>`, white, small, at `(x, y − 54)`;
      - if `effectId`: `spawnEffect({effectId, direction: "right", x, y})`: the effect root sits
        at the node root, with no explicit depth (`:1599-1635`).
   4. emit `resource_hit(request)` → RustleSfx / ClinkSfx (stone nodes: no sound here; their
      `stone-impact` effect has its own `mine-stone` ImpactSfx).
   5. If `defeated` or `hp <= 0` → `destroyObject()` (4.4).
4. Router: `publishDamageFeedback` → `damage_feedback` when `actual > 0`.
5. Weapon: `onManagedWeaponOutcome(outcome, target)`: target tags include `resource` → return
   (`CombatController.ts:212`). So **no hit-stop, no shake, no hit-spark, no weapon impact
   effect and no crit sting** on trees and stones. The crit flag survives for a creature later
   in the same swing.
   - Exception: the amber ore has no `resource` tag. It gets the creature treatment (`hit`
     feel = 65 ms hit-stop, `hit-spark` at (x, y − 12), the weapon's `onHitEffectId` in front,
     the crit sting) [QUIRK].
6. After the step (`afterFixedStep`, `UniversalSceneWorldController.ts:698-704`):
   `finishDestroyedResources` (`:2153-2160`) frees the owner of every destroyed node.

### 4.4 Destruction (`destroyObject` → `onDestroyed`, `ResourceNodeScript.ts:153-171`)

1. `destroyed = true`, `health = 0`, record `{stage:"depleted", value:0,
   respawnReadyAtEpochMs: Date.now() + 600000}` (`UniversalSceneWorldController.ts:630-635`).
2. emit `destroyed {mapId, instanceId, objectId}` (no listener).
3. If drops were already published, or the drop configuration is invalid, stop. Otherwise set
   `dropsPublished = true` and build `request = {mapId, instanceId, objectId, dropObjectId,
   dropVisualId, pieces, x, y, depletionMessage?}`.
4. `port.spawnDrops(request)` → `ResourceNodeController.spawnManagedResourceDrops`
   (`ResourceNodeController.ts:42-54`, wired at `WorldScene.ts:2330`). Section 5 covers the
   pile records, the pile spawn and the depletion text.
5. emit `drops_requested(request)` → FallSfx / CrumbleSfx / ShatterSfx (detached, so they
   outlive the free).
6. The owner is freed after the step (4.3 step 6). The router entry goes with it. Until then,
   further hits in the same step are rejected `dead`.

The killing blow therefore shows, in order: the tint, `-N` at y − 54, the hit effect, the rustle
(cut short by the free), the drops, `Tree felled` at y − 46, and the fall sound.

### 4.5 Numbers (attack stat 12 → ×1.2; attributes 10 → no scaling; no crit)

Payload damage = `round(base × 1.2)` (combat 4.2). The port fixes the combo off-by-one (owner
decision O3: a lone hit is ×1.0). Phaser's live build multiplies a lone hit by ×1.15. All tools
have cooldowns of 850 ms or more (> the 600 ms combo window), so every swing is a lone hit.

| Tool → target | Modifier (first matching tag) | Godot per hit (crit) | Hits to break (Godot) | Phaser per hit | Hits (Phaser) |
|---|---|---|---|---|---|
| stone-axe (base 12 → 14) → tree 40 | wood ×1 | 14 (crit round(24.5) = 25) | 3 (14, 14, 12) | 16 | 3 (16, 16, 8) |
| iron-axe (16 → 19) → tree 40 | wood ×1 | 19 (crit 33) | 3 (19, 19, 2) | 22 | 2 (22, 18) |
| stone-pickaxe (12 → 14) → stone 80 | stone ×1 | 14 | 6 (5 × 14 = 70, then 10) | 16 | 5 |
| reinforced-pickaxe (15 → 18) → stone 80 | stone ×1 | 18 (crit round(31.5) = 32) | 5 (4 × 18 = 72, then 8) | 21 | 4 (63, then 17) |
| reinforced-pickaxe → iron 120 | iron ×1 | 18 | 7 (6 × 18 = 108, then 12) | 21 | 6 (105, then 15) |
| basic sword (20 → 24) → amber ore 30 | none match → ×1 | 24 | 2 (24, 6) | 28 | 2 (28, 2) |
| any non-harvesting weapon → tree / stone / iron | — | blocked | never | blocked | never |

Yield per node: tree 1 pile × 10 wood; stone node or big mine 3 piles × 10 stone = 30; iron node
2 piles × 5 iron ore = 10; amber ore 1 pile × 1 shard.

### 4.6 Edge cases

- Hit during the 110 ms tint: a new tint is applied and a second timer starts, so the first timer
  clears the tint early [QUIRK, invisible with cooldowns ≥ 850 ms].
- Accepted hit with 0 damage (only possible with a ×0 modifier on a tool that passes the gate;
  no such weapon/node pair exists in the content): nothing happens at all (3.3), and the weapon
  outcome returns early (resource tag).
- Two weapon windows on the same node (multi-span weapons): each window may hit once.
- `persistHealth false` (stone, iron): damage is not saved. A half-mined stone is whole again
  after a world reload. Its destruction is still saved.
- Trees keep their damage forever: a record `{stage:"node", value: 26}` is never healed.
- Enemies, projectiles and abilities never hit resources: enemy activations target only the
  player, projectiles target only the player area (`UniversalSceneWorldController.ts:2109`), and
  the slam skips `resource` tags.

### 4.7 World mount (`mountAuthoredWorld`, `UniversalSceneWorldController.ts:1756-1772`)

After the world scene is mounted (every node script's `_enter_tree` has run), for each
ResourceNodeScript in tree order:
1. no drop definition → throw `Resource '<id>' requires an authored drop definition.`;
2. `registerManagedResource({instanceId, dropObjectId, dropVisualId})`
   (`ResourceNodeController.ts:33-40`): remember the drop; if the record's stage is `"destroyed"`,
   restore its piles **settled** (5.5);
3. destroyed → `owner.queue_free()`; else track it (tags lookup, hit tint, `nearestSource`).

Then for each CollectibleScript in the world mount: `remaining <= 0` → `owner.queue_free()`,
else track it (`:1768-1772`).

---

## 5. Drops (ResourceNodeController.ts, ResourceDropPlacement.ts)

### 5.1 `spawnManagedResourceDrops(request)` (`:42-54`, `:81-111`)

```
amount = collectibleQuantity(request.dropObjectId)   # authored quantity of object.<id with "." -> "-">
sourceCell = (floor(x / ts), floor(y / ts) - 1)       # cellForAnchor :193-195 (ts = tile size, 64)
cells = findDropCells(sourceCell, instanceId, pieces) # 5.2
placements = completeDropPlacements(cells, sourceCell, pieces, ts)   # 5.3
piles = for each placement i: {
    id: "<instanceId>-drop-<i+1>", cellX, cellY,
    offsetX (only if != 0), offsetY (only if != 0),
    amount, objectId: dropObjectId, visualId: dropVisualId }
record(mapId, instanceId) = {stage:"destroyed", value: Σ amount, piles}   # timer kept (9.2)
for each pile i: createDynamicDrop(pile, launch from (x, y), launchIndex i)   # 5.4
floating text depletionMessage ?? "Resource depleted", yellow, big, at (x, y - 46)
```

### 5.2 Cell search (`findDropCells`, `:179-191`)

Every grid cell `(cx, cy)`, `0 ≤ cx < columns`, `0 ≤ cy < rows`, is a candidate unless it is:
- the source cell;
- reserved (a cell holding a pile spawned or restored this session whose amount is still > 0,
  `reservedCells`, `:164`, cleared at `:61`);
- blocked (`WorldScene.isResourceDropCellBlocked`, `WorldScene.ts:1673-1681`): outside the
  world, a solid ground tile (water, deep-water, rock-wall), or a cell occupied by an **authored
  root** other than the source node (`isAuthoredCellOccupied`, `UniversalSceneWorldController.ts:1576-1585`).
  Authored roots are the world's top-level instance roots (`directAuthoredInstanceRoots`,
  `:2233-2241`): trees, stones, houses, props, NPCs (at their current position), authored
  collectibles, everything placed in the world scene, except freed ones. A root occupies
  `(floor(x / ts), floor((y − 1) / ts))` of its Phaser root position. Runtime piles, the player
  and enemies never block (piles count through `reserved` only).

Sort by Chebyshev distance `max(|dx|, |dy|)`, then `cellY`, then `cellX`. Take the first `pieces`.
For a free neighbourhood around source cell (sx, sy) the order is (sx−1, sy−1), (sx, sy−1),
(sx+1, sy−1), (sx−1, sy), (sx+1, sy), (sx−1, sy+1), (sx, sy+1), (sx+1, sy+1), then distance 2.
So a tree's single pile goes **up-left**, and a stone's three piles go into the row above
[QUIRK, see 11].

Phaser scans the whole grid for every destruction, and each cell test loops over every authored
root: 3 136 cells × 1 668 roots in level-1. The port must precompute an occupied-cell set once
per destruction and walk rings outward (12.7). The result is the same.

### 5.3 Placement completion and scatter (`completeDropPlacements`, `ResourceDropPlacement.ts:21-38`)

```
cells = availableCells[0 .. pieces-1]; pad with the source (fallback) cell until pieces long
for each cell in order: k = how many earlier entries used the same cell (0 for the first)
    offset = stableOffset(ts, k):  k == 0 -> (0, 0)
        angle = k × 2.399963229728653; r = min(0.42·ts, 0.1·ts·√k)
        offset = (round(cos(angle)·r), round(sin(angle)·r))
```

For ts = 64: k = 1 → (−5, 4); k = 2 → (1, −9); k = 3 → (7, 9); k = 4 → (−13, −2); k = 5 → (12, −8).
Offsets only appear when fewer free cells than pieces exist (a boxed-in node).

Pile world position (`createDynamicDrop`, `ResourceNodeController.ts:141-142`):
`(cellX·ts + ts/2 + offsetX, (cellY + 1)·ts + offsetY)`, the bottom-centre of the cell. Example:
cell (9, 9) → (608, 640).

### 5.4 Spawning a pile (`UniversalSceneWorldController.spawnWorldDrop`, `:1471-1515`)

1. Validate: finite points, launch index ≥ 0 integer, positive remaining, no collectible with that
   instance id mounted yet (throw otherwise).
2. Mount `object.<objectId with "." → "-">` (e.g. `object.collectible-wood-pile`) at the **source**
   (launch) or the destination (settled). Script overrides: `mapId` = current map, `instanceId` =
   pile id, `quantity` = pile amount, `sourceResourceInstanceId` = node instance id.
3. The scene must have a CollectibleScript with that `objectId` and a `PickupArea` (throw otherwise).
4. Launch mode: `PickupArea.monitorable = false`, then animate (`animateWorldDrop`, `:1527-1574`,
   scene tweens, so it pauses in hit-stop and in modal pauses):

| Phase | Duration / delay | Ease | Position | Visual scale (× authored) |
|---|---|---|---|---|
| wait | `launchIndex × 60` ms delay | — | at the source | 1, 1 |
| flight | 280 ms | Linear | `source + (dest − source)·t − (0, 4·h·t·(1 − t))`, `h = clamp(0.45·|dest − source|, 28, 56)` | 1, 1 |
| land | instant | — | dest | 1.12, 0.82 |
| rebound | 40 ms | Sine.Out | `dest − (0, 4·p)` | x 1.12 − 0.16p → 0.96, y 0.82 + 0.22p → 1.04 |
| settle | 60 ms | Sine.In | `dest − (0, 4·(1 − p))` | x 0.96 + 0.04p → 1, y 1.04 − 0.04p → 1 |
| finish | — | — | dest | 1, 1; `PickupArea.monitorable = true` |

A pile can be picked up 380 ms (+60 ms per launch index) after the blow. If the player already
stands on the spot, the contact appears when `monitorable` turns on, and the pickup happens on
that step (`ContactRouter.reconcile` creates the contact, `ContactRouter.ts:165-167`).

### 5.5 Restoring piles at load (`restoreDynamicDrops`, `ResourceNodeController.ts:113-125`)

Only for stage `"destroyed"`: `active` = piles with `amount > 0`. If none, write `{stage:"depleted",
value:0}` (the timer is kept) and stop. Otherwise spawn each active pile in **settled** mode at its
saved cell and offset, with `quantity` = the saved amount, and reserve its cell. `objectId`/`visualId`
come from the pile, falling back to the node's drop definition.

### 5.6 Pile bookkeeping after a pickup (`onCollectibleStateChanged`, `:56-74`)

Called by the collectible controller after every successful move (7.2 step 8) with
`{instanceId: pileId, remaining, sourceResourceInstanceId}`:

```
if no sourceResourceInstanceId: return
state = record(map, source); if not state or stage != "destroyed" or no piles: return
if the pile is found and remaining <= 0: unreserve its cell
piles = piles with this pile's amount = remaining, then keep amount > 0
if none: record = {stage:"depleted", value:0}     # timer kept -> may regrow on a later load
else:    record = {stage:"destroyed", value: Σ amount, piles}
```

---

## 6. Regrowth (`resolveResourceRespawn`, `features/resources/ResourceRespawn.ts:17-28`)

Run only when a resource node enters the tree (world load), with `now = Date.now()` (wall clock,
so it also counts while the game is closed) and `respawnMs = 600 000`:

| Saved record | Result | Written back |
|---|---|---|
| none | none (node as authored) | no |
| `stage "node"` | unchanged (damaged node keeps its HP) | no |
| no `respawnReadyAtEpochMs` (old saves) | same record + `respawnReadyAtEpochMs = now + 600000` | yes |
| `stage "depleted"` and `now ≥ ready` | none: **the node grows back** (`clearResourceState`, which also forgets the collectible records of its piles, `WorldProgress.ts:407-419`) | yes |
| `stage "depleted"` and `now < ready` | unchanged (stays gone) | no |
| `stage "destroyed"` (piles still lie around), any time | unchanged: never regrows while a pile is uncollected | no |

The timer starts **at destruction** (4.4 step 1). `setResourceState` keeps an existing timer
whenever the new stage is not `"node"` (`WorldProgress.ts:396-399`), so the `"destroyed"` and
`"depleted"` rewrites keep it. In-world regrowth never happens: the node returns only on the next
load of its map after the timer, and only after all its piles were collected. Authored
collectibles never come back.

---

## 7. `game.collectible` (CollectibleScript.ts + CollectibleController.ts)

### 7.1 Entering the tree

`_enter_tree` (`CollectibleScript.ts:63-70`): `port.ensureInitialized(mapId, instanceId, quantity)`.
The controller (`CollectibleController.ts:46-49`) remembers `quantity` as the initial amount when
`mapId` equals the loaded map and `quantity` is a positive integer. A missing `pickupArea` throws.

`remaining(mapId, id)` (`:51-56`): `0` when `mapId` is not the loaded map; else the saved record's
`remaining`; else the initial amount; else `0`.

At world mount, authored collectibles with `remaining ≤ 0` are freed (4.7). There is no
respawn.

**Godot addition (owner decision 2026-10-05): the pickup bounce.** A collectible that is not
already taken hops about 6 world px (`BOUNCE_HEIGHT`) up and back down, with a small squash on
landing, then rests 1.1-1.9 s and hops again; the first hop comes 0.2-1.6 s after it appears, and a
pile still flying in (not monitorable yet) waits. The tween moves the `Visual`'s offset and scale
relative to their own values, on the Visual (it pauses with the tree and ends with the pile).
Resource nodes never move, so a pile that can be picked up reads apart from the node it came from.
`bounce = false` on the CollectibleScript turns it off. Test: `test_world_objects.gd`
`test_pickups_bounce_and_resource_nodes_stay_still`.

### 7.2 Pickup flow (walk-over, edge-triggered)

1. Contact pass after physics: the player's `PickupArea` (monitoring) gains a contact with a
   collectible `PickupArea` (monitorable, layer 64). `area_entered` fires **once** when the
   contact begins (`ContactRouter.ts:160-168`). Standing still on a pile does not retry.
2. `PlayerScript.on_pickup_area_entered(contact)` (`PlayerScript.ts:52-56`): among the children
   of `contact.other`'s parent, the first CollectibleScript → `requestPickup(contact.observerId)`
   (the player's PickupArea id). There is no dead, dodge or pause check.
3. `requestPickup(collector)` (`CollectibleScript.ts:76-102`): position = the PickupArea's
   global position; `requested = remaining`; build the request (1.5). `port.pickup(request)`; with
   no port → `{rejected, moved 0, remaining: requested, reason "unavailable"}`.
4. `pickupCollectible` (`UniversalSceneWorldController.ts:2162-2172`): the collector must be the
   player's PickupArea → else `{rejected, 0, remaining, "invalid-collector"}`.
5. `CollectibleController.pickup` (`:58-105`):
   1. `remaining = remaining(map, id)`; wrong map → `"wrong-map"`; `remaining ≤ 0` →
      `{rejected, 0, 0, "depleted"}`.
   2. `recovered` = has `sourceInventoryDropId` and that bag drop's origin is not `"loot"` (OUT).
   3. `moved = transaction.collectWorldItem({mapId, instanceId, itemId, remaining, requested,
      source ids})` (8.3).
   4. `moved ≤ 0`: if `scene.time.now ≥ inventoryHintReadyAt` → set it to now + 1000 and show
      `Inventory full` (white, big, (x, y − 34)). Return `{rejected, 0, remaining, "inventory-full"}`.
   5. `next` = the saved record (written by the transaction); `onStateChanged({instanceId,
      remaining: next.remaining, source ids})` → `ResourceNodeController.onCollectibleStateChanged`
      (5.6) and `InventoryDropController.onCollectibleStateChanged` (bag drops, OUT).
   6. Text `+<moved> <item name>` (yellow, small, (x, y − 34)); item name = items.json `name`,
      falling back to the id (`WorldScene.ts:1367`).
   7. `publishCollected({mapId, instanceId, objectId, itemId, quantity: moved, recovered?})` →
      event `collectible.collected`. Listeners: `loot-sparkle` particles at the player centre
      − (0, 24) (`WorldScene.ts:435-437`); the purple-berry reaction (7.3); quests (OUT).
   8. Return `{status: next.remaining == 0 ? "collected" : "partial", moved, remaining: next.remaining}`.
6. Back in `requestPickup`: emit `pickup_resolved(result)` → PickupSfx or InventoryFullSfx (by the
   `status` filter). If not rejected and `remaining == 0` → emit `depleted(request)`.
7. After the step: `finishDepletedCollectibles` (`:2174-2181`) frees every tracked collectible
   with `remaining ≤ 0`.

Results the port must produce:

| Situation | Result | Pile | Record | Text | Sound |
|---|---|---|---|---|---|
| room for all | `collected`, moved = remaining, remaining 0 | freed after the step | `{remaining: 0, source?}` | `+10 Wood` | PickupSfx |
| room for some | `partial`, moved = room, remaining > 0 | stays (same look) | `{remaining: rest}` | `+5 Wood` | PickupSfx |
| no room | `rejected "inventory-full"` | stays | unchanged | `Inventory full` (throttled 1 s) | InventoryFullSfx (min 600 ms) |
| already empty | `rejected "depleted"` | — | — | none | InventoryFullSfx |

To retry after a partial or full pickup, the player must step off the pile and back on [QUIRK].

### 7.3 Purple berry reaction (`CollectibleReactionController.ts:30-35`) [IN, low priority]

For `itemId == "purple-berry-mat"` and not `recovered`:
1. `playActionAnimation("slime-eat")` (`WorldScene.ts:1855-1870`): skipped while dead or during
   knockback. Otherwise emit `player.action {anim: "eat"}`, set the action lock, stop the
   player, play `eat`, and unlock after the clip length (167 ms of simulation time), then play
   `idle` (`:1872-1877`).
2. `gameState.addCoins(5 × quantity)` (+5 per berry), which runs even when step 1 was skipped.
3. HUD coin flash (OUT).

### 7.4 Loot sparkle preset (`features/feel/ParticlePresets.ts:31-34`)

`loot-sparkle`: texture `fx-sparkle` 16×16 (`ProceduralAssetScene.ts:104-111`: four triangles in
`#ffe89a` forming a 4-point star, (8,0)-(10,8)-(6,8), (8,16)-(10,8)-(6,8), (0,8)-(8,6)-(8,10),
(16,8)-(8,6)-(8,10), plus a white circle r 2 at (8,8)); count 6; lifespan 520 ms; speed 20-60;
angle 220-320° (upward fan, y down); scale 0.9 → 0; alpha 1 → 0; rotate 0-180; normal blend;
layer "over". Played on every collection, at player centre − 24 = **feet − (0, 51.56)** in Godot.

---

## 8. Inventory (`systems/Inventory.ts`, `content/items/*`)

### 8.1 Shape

`{maxSlots: 20, slots: [{itemId, count}]}` (`SaveSchema.ts:111-114`); a new run starts empty
(`content/initial-state/InitialRun.ts:47-49`). Slots are an ordered list with no holes: empty
slots are removed and new stacks are appended at the end.

### 8.2 Item definitions

`items.json` (copied to `godot/game/data/items.json`) plus `maxStack` from
`inventory.maxStackByItem`. Weapons are items too (`Inventory.ts:35-45`: id = weaponId,
category `weapon`, maxStack `weaponMaxStack` 1). An unknown id has no definition.

| id | name | category | max stack | use |
|---|---|---|---|---|
| wood | Wood | material | 25 | — |
| stone | Stone | material | 25 | — |
| iron-ore | Iron Ore | material | 99 | — |
| charcoal | Charcoal | material | 99 | — |
| hp-potion | Slime Tonic | consumable | 9 | heal 40 HP |
| energy-potion | Fizzy Brew | consumable | 9 | +50 energy |
| purple-berry-mat | Purple Berry | material | 99 | — |
| silk-clump | Sticky Silk | material | 99 | — |
| weaver-fang | Weaver Fang | material | 99 | — |
| iron-bar | Iron Bar | material | 99 | — |
| shard | Crystal Shard | collectible | 99 | — |
| green-key | Verdant Key | key | 1 | — |
| crystal-key | Crystal Key | key | 1 | — |
| workbench | Workbench | furniture | 1 | placeable |
| berry-basket | Berry Basket | consumable | 9 | heal 20 HP, +30 energy |

### 8.3 Adding (`createTransactionDraft`, `Inventory.ts:95-144`; `collectWorldItem`, `InventoryWorldTransaction.ts:51-81`)

The transaction is all-or-nothing for a given count. `collectWorldItem` binary-searches the
largest count that fits, which equals this closed form:

```
capacity(item) = 0 if no definition or maxStack <= 0
               = Σ over slots of item with count < maxStack: (maxStack - count)
                 + max(0, maxSlots - slots.size) × maxStack
collectWorldItem(input):
    remaining = savedRecord.remaining ?? input.remaining
    requested = input.requested ?? remaining
    if remaining <= 0 or requested <= 0: return 0
    moved = min(remaining, requested, capacity(itemId))
    if moved <= 0: return 0
    add: fill existing stacks of itemId in slot order up to maxStack, then append
         new slots of min(maxStack, left) while slots.size < maxSlots
    record(map, id) = {remaining: remaining - moved,
                       sourceResourceInstanceId: saved ?? input, sourceInventoryDropId: saved ?? input}
    emit inventory.changed, then world.progress.changed          # commit, :104-122
    return moved
```

Examples (20 empty slots):

| Start | Pickup | Moved | Slots after |
|---|---|---|---|
| empty | wood pile 10 | 10 | [wood 10] |
| [wood 10] | wood pile 10 | 10 | [wood 20] |
| [wood 20] | wood pile 10 | 10 | [wood 25, wood 5] |
| [wood 25, wood 5] | wood pile 10 | 10 | [wood 25, wood 15] (the four level-1 piles = 40 wood) |
| 19 × [stone 25] + [wood 20] | wood pile 10 | 5 (partial, pile keeps 5) | wood slot 25 |
| 20 × [stone 25] | wood pile 10 | 0 → Inventory full | unchanged |
| 20 × [stone 25] | stone pile 10 | 0 (all stone stacks full) | unchanged |
| any | item id not in the registry | 0 → "Inventory full" [QUIRK] | unchanged |

Removing (`Inventory.remove`, `:174-186`, and transaction removals `:106-117`) takes from the
**first** matching slot onward and drops emptied slots. (The current Godot draft
`RunState.remove_item` walks from the **last** slot; align it, 12.6.)

---

## 9. World-object records (`WorldProgress`, `SaveSchema.ts:20-43, 74-88`)

### 9.1 Shapes (Phaser camelCase; RunState stores the snake_case equivalent)

```
maps[mapId].resources[instanceId] = {
    stage: "node" | "destroyed" | "depleted",
    value: number >= 0,                 # node: current HP; destroyed: Σ pile amounts; depleted: 0
    piles?: [{id, cellX, cellY, amount >= 0, offsetX?, offsetY?, objectId?, visualId?}],  # omitted when empty
    respawnReadyAtEpochMs?: number }
maps[mapId].collectibles[instanceId] = {
    remaining: integer >= 0 (floored),
    sourceResourceInstanceId?, sourceInventoryDropId? }
```

### 9.2 Write rules

- `setResourceState` (`WorldProgress.ts:392-404`): `respawnReadyAtEpochMs = new ?? (stage != "node"
  ? previous : none)`; values clamped ≥ 0; no write (and no change event) when the JSON is
  unchanged.
- `clearResourceState` (`:407-419`): delete the resource record **and** every collectible record
  whose `sourceResourceInstanceId` is that node or whose id starts with `"<node>-drop-"`. Without
  this, the regrown node's next piles (same ids) would read as already empty.
- `setCollectibleState` (`:427-436`) and the transaction snapshot (`:291-306`): floor and clamp
  `remaining`.

### 9.3 Lifecycle of one tree (`level-1-tree-004`, stone axe, 14 per hit)

| Moment | `resources["level-1-tree-004"]` | `collectibles["level-1-tree-004-drop-1"]` |
|---|---|---|
| authored | — | — |
| hit 1 | `{node, 26}` | — |
| hit 2 | `{node, 12}` | — |
| hit 3 (fell), `depleted` write | `{depleted, 0, ready = T + 600000}` | — |
| same call, drops | `{destroyed, 10, piles [{id "level-1-tree-004-drop-1", cell, amount 10, objectId "collectible.wood-pile", visualId "wood-pile"}], ready}` | — |
| pile picked up (room) | `{depleted, 0, ready}` | `{remaining 0, source "level-1-tree-004"}` |
| load before T + 10 min | unchanged: node freed, no pile | unchanged |
| load at/after T + 10 min | removed: the tree is back at 40 HP | removed |

A stone node (persistHealth false) has no record until it breaks; then
`{destroyed, 30, piles × 3 (10 each)}`.

---

## 10. What the player sees and hears (summary)

| Event | Visual | Text | Sound | Camera / hit-stop |
|---|---|---|---|---|
| non-tool weapon on a tree or stone | none | cyan big message at (x, y − 58), every swing | WrongToolSfx (min 200 ms) | none (the swing's crit feel at swing start still happens) |
| tool hit | Visual solid `#ffd277` 110 ms; hit effect (wood/stone impact, 333 ms); autumn tree leaf-fall then idle | `-N` white small at (x, y − 54) | trees: rustle + chop; stone: mine; iron: clink + mine | none |
| tool hit on the amber ore | as above, no hit effect, plus `hit-spark` and the weapon impact effect | `-N` | clink (+ sword impact sound) | 65 ms hit-stop (crit sting if crit) |
| node breaks | node disappears at the end of the step; piles arc out (280 ms + rebound) | depletion message yellow big at (x, y − 46) | fall / crumble / shatter (detached) | none |
| a pile waiting | hops about 6 px every 1-2 s (Godot addition, 7.1) | | | |
| pickup | pile disappears; `loot-sparkle` over the slime; berry: `eat` clip | `+N Item` yellow small at (x, y − 34) | per-item pickup sound (detached; berry basket silent) | none |
| bag full | none | `Inventory full` white big (≤ 1 per s) | inventory-full (min 600 ms) | none |

---

## 11. Quirks (port as is unless the owner decides otherwise)

| # | Quirk | Where |
|---|---|---|
| Q1 | A sword (or any non-tool) swing that touches a tree or stone shows "Requires an Axe/Pickaxe" every swing, even when aimed at an enemy beside it | 4.2 |
| Q2 | `wooden-axe` and `pickaxe` have no `harvestCapabilities`: holding them, the player still reads "Requires an Axe/Pickaxe". Their `wood ×1` / `stone ×1` modifiers never apply to resources | weapon scenes and weapon.json |
| Q3 | The combo counts resource hits and blocked hits (`registerHit` runs before routing) | 4.3 step 1 |
| Q4 | Amber ore: no `resource` tag and no requirement, so it takes any weapon at ×1 and gets creature feel (hit-stop, spark, sword impact effect) | 1.3, 4.3 step 5 |
| Q5 | Stone and iron forget damage on reload (`persistHealth false`); trees remember it forever (no healing) | 4.6 |
| Q6 | Drop source cell = `floor(y/ts) − 1`, while authored roots occupy `floor((y−1)/ts)`. For a node not standing on a cell edge, its own cell is not the source cell and is not blocked (the source is skipped), so a pile can land in the node's own cell. Free piles go up-left / into the row above, where y-sorting usually draws them **behind** the tree that dropped them | 5.1-5.2 |
| Q7 | Regrowth: the timer counts from destruction in wall-clock time (also while the game is closed); the node returns only on a later world load, and never while a pile lies uncollected | 6 |
| Q8 | Pickup is edge-triggered: after a partial or full-bag pickup the player must step off and on again | 7.2 |
| Q9 | "Inventory full" also appears for an item id missing from the registry | 8.3 |
| Q10 | A partial pickup plays the pickup sound (filter `collected|partial`); every rejection reason plays the inventory-full sound | 1.5 |
| Q11 | The berry basket collectible has no sounds | 1.4 |
| Q12 | Second hit inside 110 ms: the first timer clears the second tint early | 4.6 |
| Q13 | `health_changed`, `damaged`, `damage_feedback`, `destroyed` and `depleted` have no listeners | 1.5 |
| Q14 | A collectible whose `mapId` is not the loaded map reads `remaining 0` and is freed at load (only template values `"map-template"` would hit this) | 7.1 |
| Q15 | Reserved cells are keyed by cell: depleting one of two stacked fallback piles unreserves the cell while the other pile still lies there | 5.6 |
| Q16 | (cross-area) Spear scenes say `baseDamage` 30 / 20 / 10 (basic / iron / stone) while `weapon.json` says 10 / 10 / 7. Phaser's CombatController uses weapon.json; Godot's PlayerCombat uses the scene. Only the amber ore (×1) among world objects would notice | combat |

---

## 12. Godot port plan

### 12.1 Integration facts from the current Godot code

- **Router** (`game/combat/damage_router.gd`): `register_area(area, receiver, rule, tags)`
  (`:53-60`) keys by the hurtbox Area2D. Tags must be the node's authored `tags` in order:
  `weapon.gd:320` passes `router.tags_for_area(area)` as `target.tags`, which
  `PlayerCombat.transform_damage` uses for modifiers (`player_combat.gd:196-203`) and
  `PlayerCombat.on_outcome` uses to skip feel on `resource` targets (`:214-216`). Both already
  match Phaser. `route()` (`:114-170`) calls `can_receive_damage(input)` (input
  `{scaled_damage, request (normalized; weapon_tags sorted), rule, area, state, simulation_time}`),
  then `commit_damage(commit)` and `publish_damage_feedback(commit)` with
  `commit = {request, rule, area, result, simulation_time, receiver}`. A decision
  `{accepted: false, reason: "state-blocked"}` becomes a retryable rejection
  (`damage_resolver.gd:166-173`). `get_damage_state()` must return
  `{hp, max_hp, dead}` with `0 ≤ hp ≤ max_hp` (`_valid_state`).
- **Weapon** (`game/scripts/weapon.gd:287-351`): any registered hurtbox in the sector is
  resolved once per window. The target position is `area.global_position`, the tree's base,
  because the DamageArea sits at the root. Today tree hurtboxes are unregistered and ignored;
  once `resource_node.gd` registers them, sword swings near trees produce Q1.
- **PlayerCombat** already emits `harvest:<tag>:<tier>` weapon tags and the correct outcome
  filter; `equip(weapon_id)` can mount any converted weapon (`weapon.stone-axe`, `.iron-axe`,
  `.stone-pickaxe`, `.reinforced-pickaxe`). `_target_feet` reads `receiver.get("body")`; a
  resource node has none, so the amber ore's impact holder falls back to the hurtbox position
  (`player_combat.gd:297-303`). That is fine.
- **Player** (`game/scripts/player.gd:518-520`): `on_pickup_area_entered(_area)` is a no-op stub
  and is already connected by `player_slime.tscn`. PlayerScript runs `PROCESS_MODE_ALWAYS`, but
  physics signals only fire while the tree runs, so no pickup can happen in hit-stop (as in
  Phaser).
- **Feel** (`game/feel/game_feel.gd`): `floating_text(pos, text, color_name, big, duration_ms)`
  with `cyan`, `yellow`, `white` (`:40-44, 125-129`); `particles(preset, pos)` supports only
  `hit-spark`, `slime-splash`, `dodge-dust` (`particle_fx.gd:23, 37-50`). `loot-sparkle` must
  be added (12.8).
- **Effects**: `EffectSpawner.spawn_in_front(effect_id, direction, centre, feet)`
  (`effect_spawner.gd:21-51`) puts a holder at `feet + (0, 1)`. For a resource hit call it with
  `pos, pos` so the impact draws just in front of the node's base. Phaser gives no explicit depth
  (ties at the same y); "in front" is the intended look.
- **Hit flash**: `HitFlash.flash(visual, Color("#ffd277"))` / `HitFlash.clear(visual)`
  (`game/feel/hit_flash.gd`) give the solid fill. `flash` installs the material on first use,
  so untouched trees keep the shared default material and batching.
- **Run state**: the `RunState` autoload (`game/autoload/run_state.gd`, uncommitted; "Owner: world
  objects"), reached by `Services.run()`, holds `inventory = {max_slots, slots: [{item_id, count}]}`,
  `player.coins` and `map_record(map_id)` with `resources` and `collectibles` dictionaries. It
  already has `item_count`, `remove_item` and `unlock_gate`. Tests reset it with `new_run()`
  before each test (`tests/run_tests.gd`).
- **World service**: `instantiate_scene(scene_id)`, `entities_root()` (the y-sorted world root),
  `dimensions()` (level-1: ts 64, 56 × 56), `is_solid_tile(tx, ty)` (outside → true),
  `world_root`, `player`. `entities_root()` and `is_solid_tile` work only after
  `register_world`, which runs **after** the world's `_ready` calls (main.gd `load_world`), so
  anything a node does at load that needs them must be deferred.
- **Animation helper** (`game/runtime/animation_player.gd`): `play_clip(name)` restarts like
  Phaser's `play`; `animation_finished(name)` is Godot's signal. The helper has no `class_name`;
  call `play_clip` through `has_method` / `call`, or `play` as a fallback.
- **SFX helper** (`runtime/sfx_player_2d.gd`): `play_cue(payload)` honours `payload_filter`
  (`status=…`, runtime spec), `min_interval_ms` and `detached`. Payloads must be Dictionaries
  with the camelCase keys of 1.5.

### 12.2 Script structure and the converter (inheritance)

- `game.enemy` "extends" `game.character` only in the TS descriptors: `enemy.gd` is
  `extends Node` and declares `body`, `visual`, `animation` itself. ARCHITECTURE section 1 says
  "No inheritance between scene scripts … the converter reads only the target file's
  `@export var` lines".
- That reason is **out of date**: `scripts/godot/lib/gdscript.mjs:157-177` (`ScriptIndex.describe`)
  merges `@export`s, signals and methods along the `extends` chain (a `res://` path or a
  `class_name`), and `script-props.mjs:52-73` uses that merged list. The uncommitted
  `game/scripts/fatty.gd` already does `extends "res://game/scripts/enemy.gd"`. runtime spec
  item 9 asked for exactly this.
- **Recommendation**: no scene uses `game.destructible`, and ARCHITECTURE says to add a file to
  `game/scripts/` only when porting a script that scenes use. So write `resource_node.gd` as a
  flat `extends Node` script that declares **all 16 exports** (the 8 destructible keys + the 8
  resource-node keys of 1.2), and put the destructible logic in a RefCounted helper
  `game/world_objects/destructible_health.gd`. A future `game/scripts/destructible.gd` would
  wrap the same helper.
  - Alternative, if the architect accepts inheritance (as fatty.gd does): `destructible.gd`
    declares the 8 base exports and signals, and `resource_node.gd` uses
    `extends "res://game/scripts/destructible.gd"`. The converter then writes every inherited
    property too. Either way, update ARCHITECTURE section 1 so the rule and the converter agree.
- Exact export names (the converter matches `snakeCase(key)`): `map_id, instance_id, object_id,
  damage_area, max_health, initial_health, tags, damage_rule, drop, idle_animation_id,
  hit_effect_id, on_hit_animation_id, persist_health, depletion_message, harvest_requirement,
  animation` and `map_id, instance_id, object_id, item_id, quantity, source_resource_instance_id,
  source_inventory_drop_id, pickup_area`. Types: `damage_area`/`pickup_area: Area2D` and
  `animation: AnimationPlayer` (typed Node exports → `node_paths`); `max_health`/`initial_health:
  float`; `quantity: int`; `tags: Array[String]`; `drop`, `damage_rule`, `harvest_requirement:
  Dictionary` (camelCase keys kept); `persist_health: bool = true`. Defaults must equal the
  descriptor defaults (1.2), because the converter writes only authored keys
  (`idleAnimationId` and `animation` are authored on two scenes only).
- Signals must be declared in the files (`health_changed, damaged, damage_feedback, destroyed,
  resource_hit, harvest_blocked, drops_requested`; `pickup_resolved, depleted`), or the converted
  connections to the SFX fail to load.
- After adding the files: `pnpm godot:convert`. Check that `conversion_report.json` has no
  `undeclared-script-property` / `script-property-type-mismatch` warnings for these ids, and that
  `game/scenes/objects/tree-world-solid--tree-autumn-01.tscn` now attaches
  `res://game/scripts/resource_node.gd` with `node_paths=PackedStringArray("damage_area", "animation")`.

### 12.3 Files

| File | Kind | Role |
|---|---|---|
| `game/scripts/resource_node.gd` (`class_name ResourceNodeScript`) | scene script `game.resource-node` | 3 + 4: receiver, harvest gate, hit feedback, destruction, load / restore |
| `game/scripts/collectible.gd` (`class_name CollectibleScript`) | scene script `game.collectible` | 7: pickup |
| `game/world_objects/destructible_health.gd` | RefCounted | HP, load with regrowth, save HP, mark destroyed (3.2-3.3) |
| `game/world_objects/resource_respawn.gd` | static | `resolve(record, now_epoch_ms, respawn_ms) -> {record, changed}` (6), `now_epoch_ms()` with a test override |
| `game/world_objects/resource_drops.gd` | static | cell search, scatter, pile position, spawn/launch, restore, pile bookkeeping (5) |
| `game/world_objects/item_catalog.gd` | static | `max_stack(id)`, `item_name(id)`, `is_known(id)` from `game/data/items.json` + `inventory.*` constants |
| `game/autoload/run_state.gd` (additions) | autoload | inventory add/capacity, world records, change signals (12.6) |
| `game/scripts/player.gd` (edit) | — | `on_pickup_area_entered`, `get_pickup_area()`, optional eat reaction |
| `game/feel/particle_fx.gd` (edit, combat owner) | — | `loot-sparkle` preset + `fx-sparkle` texture |
| `game/main.gd` (edit) | — | warm the drop and hit-effect scenes (12.8) |
| `tests/test_world_objects.gd` | test | 12.9 |

### 12.4 `resource_node.gd` (pseudo-code)

```gdscript
extends Node
class_name ResourceNodeScript
## Scene script `game.resource-node` (Phaser ResourceNodeScript.ts + DestructibleScript.ts).
## World-objects spec sections 3-6. Child "ResourceNodeScript" of the StaticBody2D root
## (root = old Phaser root = sprite bottom-centre; no depth anchor).

const Services := preload("res://game/shared/services.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")
const EffectSpawner := preload("res://game/combat/effect_spawner.gd")
const DestructibleHealth := preload("res://game/world_objects/destructible_health.gd")
const ResourceDrops := preload("res://game/world_objects/resource_drops.gd")

# game.destructible (registrations.ts:378-387)
@export var map_id: String = ""
@export var instance_id: String = ""
@export var object_id: String = ""
@export var damage_area: Area2D
@export var max_health: float = 1.0
@export var initial_health: float = 0.0
@export var tags: Array[String] = []
@export var damage_rule: Dictionary = {"priority": 0, "damageMultiplier": 1}
# game.resource-node (registrations.ts:403-412)
@export var drop: Dictionary = {}
@export var idle_animation_id: String = ""
@export var hit_effect_id: String = ""
@export var on_hit_animation_id: String = ""
@export var persist_health: bool = true
@export var depletion_message: String = ""
@export var harvest_requirement: Dictionary = {}
@export var animation: AnimationPlayer

signal health_changed(payload: Dictionary)   # {mapId, instanceId, health, maxHealth}
signal damaged(commit: Dictionary)
signal damage_feedback(commit: Dictionary)
signal destroyed(payload: Dictionary)        # {mapId, instanceId, objectId}
signal resource_hit(payload: Dictionary)     # -> RustleSfx / ClinkSfx
signal harvest_blocked(payload: Dictionary)  # -> WrongToolSfx
signal drops_requested(payload: Dictionary)  # -> FallSfx / CrumbleSfx / ShatterSfx

## UniversalSceneWorldController.ts:2136-2142, :640 (literals, presentation).
const HIT_TINT := Color("#ffd277")
const HIT_TINT_MS := 110.0
const HIT_TEXT_RISE := 54.0
const BLOCKED_TEXT_RISE := 58.0
const RESOURCE_GROUP := &"resource_node"

var _health: DestructibleHealth
var _drops_published := false
var _registered_area: Area2D


func _ready() -> void:
	add_to_group(RESOURCE_GROUP)
	_health = DestructibleHealth.new(map_id, instance_id, max_health, initial_health, true)
	var saved := _health.load()            # 3.2 steps 2-3, regrowth resolved (section 6)
	if animation != null:
		animation.animation_finished.connect(_on_animation_finished)
	if _health.destroyed:
		# Phaser: registerManagedResource restores piles, then the owner is freed (4.7).
		# Deferred: entities_root() exists only after WorldService.register_world.
		_restore_and_free.call_deferred(saved)
		return
	if damage_area == null:
		push_error("ResourceNodeScript '%s' requires its damage_area reference" % instance_id)
		return
	Services.router().register_area(damage_area, self, _rule(), tags)
	_registered_area = damage_area


func _exit_tree() -> void:
	if _registered_area != null and Services.router() != null:
		Services.router().unregister_area(_registered_area)
	_registered_area = null


# --- receiver API (combat spec 7.1) ---
func get_damage_state() -> Dictionary:
	return {"hp": _health.health, "max_hp": _health.max_health, "dead": _health.destroyed}


func can_receive_damage(input: Dictionary) -> Dictionary:
	if _health.destroyed:
		return {"accepted": false, "reason": "dead"}
	var req := _harvest_requirement()      # {} when invalid (4.2)
	if req.is_empty():
		return {"accepted": true}
	var capability := 0
	for tag: Variant in (input["request"] as Dictionary).get("weapon_tags", []):
		capability = maxi(capability, _harvest_tier(str(tag), req["targetTag"]))
	if capability >= float(req["minimumTier"]):
		return {"accepted": true}
	var pos := world_position()
	var blocked := {"mapId": map_id, "instanceId": instance_id, "targetTag": req["targetTag"],
		"minimumTier": req["minimumTier"], "message": req["failureMessage"], "x": pos.x, "y": pos.y}
	Services.feel().floating_text(pos - Vector2(0, BLOCKED_TEXT_RISE), blocked["message"], &"cyan", true)
	harvest_blocked.emit(blocked)
	return {"accepted": false, "reason": "state-blocked"}


func commit_damage(commit: Dictionary) -> void:
	var result: Dictionary = commit["result"]
	var actual := int(result.get("actual_damage", 0))
	if _health.destroyed or actual <= 0:
		return
	_health.apply(actual)                  # health = max(0, health - actual)
	if persist_health:
		_health.save()                     # record {stage "node", value health}
	health_changed.emit({"mapId": map_id, "instanceId": instance_id,
		"health": _health.health, "maxHealth": _health.max_health})
	damaged.emit(commit)
	_on_positive_damage(actual)
	if bool(result.get("defeated", false)) or _health.health <= 0.0:
		_destroy()


func publish_damage_feedback(commit: Dictionary) -> void:
	if int((commit["result"] as Dictionary).get("actual_damage", 0)) > 0:
		damage_feedback.emit(commit)


# --- 4.3 / 4.4 ---
func _on_positive_damage(actual: int) -> void:
	_play(on_hit_animation_id)
	var pos := world_position()
	var request := {"mapId": map_id, "instanceId": instance_id, "objectId": object_id,
		"actualDamage": actual, "x": pos.x, "y": pos.y}
	if not hit_effect_id.is_empty(): request["effectId"] = hit_effect_id
	if not on_hit_animation_id.is_empty(): request["animationId"] = on_hit_animation_id
	_tint_visual()                          # #ffd277, cleared after 110 ms real time
	Services.feel().floating_text(pos - Vector2(0, HIT_TEXT_RISE), "-%d" % actual, &"white", false)
	if not hit_effect_id.is_empty():
		EffectSpawner.spawn_in_front(hit_effect_id, "right", pos, pos)
	resource_hit.emit(request)


func _destroy() -> void:
	if not _health.mark_destroyed():       # false when already destroyed
		return                             # writes {stage "depleted", value 0, ready = now + respawnMs}
	destroyed.emit({"mapId": map_id, "instanceId": instance_id, "objectId": object_id})
	var definition := _drop_definition()   # {} unless objectId/visualId strings + pieces number
	if not _drops_published and not definition.is_empty():
		_drops_published = true
		var pos := world_position()
		var request := {"mapId": map_id, "instanceId": instance_id, "objectId": object_id,
			"dropObjectId": definition["objectId"], "dropVisualId": definition["visualId"],
			"pieces": definition["pieces"], "x": pos.x, "y": pos.y}
		if not depletion_message.is_empty(): request["depletionMessage"] = depletion_message
		ResourceDrops.spawn_for(request)   # record "destroyed" + piles, launch, depletion text
		drops_requested.emit(request)
	# Stays registered until freed: later hits this frame are rejected "dead" (4.4 step 6).
	get_parent().queue_free()              # Phaser: finishDestroyedResources after the step


func _on_animation_finished(clip: StringName) -> void:
	if String(clip) == on_hit_animation_id:
		_play(idle_animation_id)


func _restore_and_free(saved: Dictionary) -> void:
	if str(saved.get("stage", "")) == "destroyed":
		ResourceDrops.restore(map_id, instance_id, saved, _drop_definition())
	get_parent().queue_free()
```

Helpers: `world_position()` = `(get_parent() as Node2D).global_position`. `_tint_visual()`:
take the first Sprite2D under the root (`get_parent().find_children("*", "Sprite2D", true,
false)[0]`, i.e. `Visual`), call `HitFlash.flash(visual, HIT_TINT)`, then
`get_tree().create_timer(HIT_TINT_MS / 1000.0, true)` (process_always: real time, keeps
running through a hit-stop) → `HitFlash.clear(visual)` if it is still valid. `_play(id)`:
skip an empty id or a missing clip, else `animation.call(&"play_clip", id)`. `_harvest_tier`:
the tag must start with `"harvest:<target>:"` and the rest must parse as a finite integral
number > 0 (JS `Number`), else 0. `_rule()`: `damage_rule` with `priority` 0 and
`damageMultiplier` 1 filled in when absent. Do not port `game.destructible`'s throw on a missing
`damage_area`: `push_error` and stay unregistered.

`destructible_health.gd` (RefCounted): fields `map_id, instance_id, max_health (max(1, x)),
health, destroyed, regrows`. `load()` resolves the record through `ResourceRespawn` when
`regrows`, rewrites or clears it on change, applies it (3.2 step 3) and returns the record ({}
when none). `apply(actual)`. `save()` → `RunState.set_resource_record(map, id, {"stage": "node",
"value": health})`. `mark_destroyed() -> bool` sets the flags and writes `{"stage": "depleted",
"value": 0}` plus `respawn_ready_at_epoch_ms = ResourceRespawn.now_epoch_ms() + respawnMs` when
`regrows`.

### 12.5 `collectible.gd` (pseudo-code)

```gdscript
extends Node
class_name CollectibleScript
## Scene script `game.collectible` (Phaser CollectibleScript.ts + CollectibleController.ts).
## World-objects spec section 7. Child "CollectibleScript" of the pile's Node2D root.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ResourceDrops := preload("res://game/world_objects/resource_drops.gd")

@export var map_id: String = ""
@export var instance_id: String = ""
@export var object_id: String = ""
@export var item_id: String = ""
@export var quantity: int = 1
@export var source_resource_instance_id: String = ""
@export var source_inventory_drop_id: String = ""
@export var pickup_area: Area2D

signal pickup_resolved(payload: Dictionary)   # {status, moved, remaining, reason?}
signal depleted(payload: Dictionary)          # the pickup request

## CollectibleController.ts:77-91, WorldScene.ts:435 (literals).
const TEXT_RISE := 34.0
const INVENTORY_HINT_MS := 1000.0
const SPARKLE_RISE := 24.0
## One throttle for every collectible (Phaser: one per world controller; real time).
static var _inventory_hint_ready_at_ms: float = 0.0


func _ready() -> void:
	add_to_group(&"collectible")
	if pickup_area == null:
		push_error("CollectibleScript '%s' requires its pickup_area reference" % instance_id)
	if remaining() <= 0:
		get_parent().queue_free()               # authored and already taken (4.7)


## Saved record remaining, else the authored / spawned quantity (CollectibleController.remaining).
func remaining() -> int:
	var record := Services.run().collectible_record(map_id, instance_id)
	return int(record["remaining"]) if record.has("remaining") else maxi(1, quantity)


## PlayerScript.on_pickup_area_entered calls this with its own PickupArea.
func request_pickup(collector: Area2D) -> Dictionary:
	var pos := pickup_area.global_position if pickup_area != null else Vector2.ZERO
	var request := {"mapId": map_id, "instanceId": instance_id, "objectId": object_id,
		"itemId": item_id, "requested": remaining(),
		"collectorAreaNodeId": str(collector.get_path()) if collector != null else "",
		"x": pos.x, "y": pos.y}
	if not source_resource_instance_id.is_empty(): request["sourceResourceInstanceId"] = source_resource_instance_id
	if not source_inventory_drop_id.is_empty(): request["sourceInventoryDropId"] = source_inventory_drop_id
	var result := _pickup(request, collector, pos)
	pickup_resolved.emit(result)
	if result["status"] != "rejected" and int(result["remaining"]) == 0:
		depleted.emit(request)
		pickup_area.set_deferred(&"monitorable", false)
		get_parent().queue_free()               # Phaser: finishDepletedCollectibles
	return result


func _pickup(request: Dictionary, collector: Area2D, pos: Vector2) -> Dictionary:
	var player := Services.world().player
	if player == null or collector == null or collector != player.get_pickup_area():
		return _rejected(remaining(), "invalid-collector")
	var rem := remaining()
	if rem <= 0:
		return _rejected(0, "depleted")
	var run := Services.run()
	var moved := run.collect_world_item(map_id, instance_id, item_id, rem, int(request["requested"]),
		source_resource_instance_id, source_inventory_drop_id)
	var feel := Services.feel()
	if moved <= 0:
		var now := float(Time.get_ticks_msec())
		if now >= _inventory_hint_ready_at_ms:
			_inventory_hint_ready_at_ms = now + INVENTORY_HINT_MS
			feel.floating_text(pos - Vector2(0, TEXT_RISE), "Inventory full", &"white", true)
		return _rejected(rem, "inventory-full")
	var next := run.collectible_record(map_id, instance_id)
	var left := int(next.get("remaining", rem - moved))
	var source := str(next.get("source_resource_instance_id", source_resource_instance_id))
	if not source.is_empty():
		ResourceDrops.on_pile_changed(map_id, source, instance_id, left)   # 5.6
	feel.floating_text(pos - Vector2(0, TEXT_RISE), "+%d %s" % [moved, ItemCatalog.item_name(item_id)], &"yellow", false)
	_on_collected(moved)   # loot-sparkle at player centre - 24; purple berry: eat + 5 coins each
	return {"status": "collected" if left == 0 else "partial", "moved": moved, "remaining": left}


func _rejected(left: int, reason: String) -> Dictionary:
	return {"status": "rejected", "moved": 0, "remaining": left, "reason": reason}
```

`_on_collected(moved)`: `Services.feel().particles(&"loot-sparkle", player.get_centre() −
Vector2(0, 24))`. If `item_id == "purple-berry-mat"` and the pile is not a recovered bag drop
(always true while bag drops are OUT): `player.play_action_clip("eat")` (12.8) and
`run.add_coins(5 * moved)`. Skip the map-mismatch rule (Q14): `WorldService.map_id()` is empty
during `_ready`.

### 12.6 RunState additions (owner: world objects)

Keys stay snake_case like the rest of RunState. Signals carry one Dictionary payload.

```gdscript
signal inventory_changed(payload: Dictionary)        # {} (Phaser inventory.changed)
signal world_progress_changed(payload: Dictionary)   # {} (Phaser world.progress.changed)
signal coins_changed(payload: Dictionary)            # {"coins": int, "delta": int} (GameState.addCoins)

# --- inventory (systems/Inventory.ts) ---
func item_capacity(item_id: String) -> int          # 8.3 closed form; 0 for unknown ids
func add_item(item_id: String, count: int) -> int   # Inventory.add: fill stacks, append slots; returns added
func collect_world_item(map_id: String, instance_id: String, item_id: String, remaining: int,
		requested: int, source_resource_instance_id: String = "",
		source_inventory_drop_id: String = "") -> int   # 8.3; writes the collectible record; emits both signals
func add_coins(amount: int) -> void                  # max(0, coins + amount); coins_changed
# remove_item(): take from the FIRST matching slot onward (Inventory.remove), not the last.

# --- world records (WorldProgress.ts:386-436) ---
func resource_record(map_id: String, instance_id: String) -> Dictionary      # {} when none (a copy)
func set_resource_record(map_id: String, instance_id: String, record: Dictionary) -> void
	# keep respawn_ready_at_epoch_ms from the previous record when the new stage != "node" and
	# the new record has none; clamp value and pile amounts >= 0; omit empty piles;
	# no change -> no signal
func clear_resource_record(map_id: String, instance_id: String) -> void
	# also erase collectibles whose source_resource_instance_id == instance_id or whose key
	# begins with instance_id + "-drop-"
func collectible_record(map_id: String, instance_id: String) -> Dictionary   # {} when none
func set_collectible_record(map_id: String, instance_id: String, record: Dictionary) -> void
	# remaining = max(0, floor(remaining))
```

Record shapes: resource `{"stage", "value", "piles": [{"id", "cell_x", "cell_y", "amount",
"offset_x"?, "offset_y"?, "object_id"?, "visual_id"?}], "respawn_ready_at_epoch_ms"?}`;
collectible `{"remaining", "source_resource_instance_id"?, "source_inventory_drop_id"?}`.
`ItemCatalog.max_stack(id)`: `inventory.maxStackByItem[id]` for items.json ids,
`inventory.weaponMaxStack` for weapon ids, else 0. `ItemCatalog.item_name(id)`: items.json
`name`, else the id.

### 12.7 `resource_drops.gd` and `resource_respawn.gd` (static)

```gdscript
# resource_respawn.gd
static var epoch_override_ms: float = -1.0          # tests set it
static func now_epoch_ms() -> float                 # override, else Time.get_unix_time_from_system() * 1000
static func resolve(record: Dictionary, now_ms: float, respawn_ms: float) -> Dictionary
	# -> {"record": Dictionary ({} = regrow / none), "changed": bool}; table of section 6

# resource_drops.gd
static func source_cell(anchor: Vector2, ts: int) -> Vector2i       # (floori(x/ts), floori(y/ts) - 1)
static func occupied_cells(source_instance_id: String, ts: int) -> Dictionary   # Vector2i -> true
	# every node with owner == WorldService.world_root and meta "instance_id" (direct world
	# instances, like Phaser's directAuthoredInstanceRoots), inside the tree, not queued for
	# deletion, meta != source; cell of FeetAnchor.phaser_position(node):
	# (floori(x/ts), floori((y - 1)/ts)). Use phaser_position: NPC roots are re-anchored.
static func reserved_cells(map_id: String, ts: int) -> Dictionary
	# cells of piles with amount > 0 in this map's "destroyed" records (equivalent to Phaser's
	# session set, Q15 aside)
static func find_drop_cells(source: Vector2i, limit: int, blocked: Callable, columns: int, rows: int) -> Array[Vector2i]
	# rings d = 1, 2, ... up to max(columns, rows); each ring sorted by (y, x); skip out-of-grid,
	# skip the source cell, skip blocked; stop at limit. Same order as Phaser's full-grid sort.
static func stable_offset(ts: int, occurrence: int) -> Vector2i     # 5.3
static func complete_placements(cells: Array[Vector2i], fallback: Vector2i, pieces: int, ts: int) -> Array[Dictionary]
	# [{"cell": Vector2i, "offset": Vector2i}]
static func pile_position(cell: Vector2i, offset: Vector2i, ts: int) -> Vector2   # 5.3
static func spawn_for(request: Dictionary) -> void                  # 5.1; launch mode
static func restore(map_id: String, source_id: String, record: Dictionary, drop_def: Dictionary) -> void   # 5.5
static func on_pile_changed(map_id: String, source_id: String, pile_id: String, remaining: int) -> void    # 5.6
static func spawn_pile(object_id: String, pile_id: String, map_id: String, amount: int,
		source_id: String, destination: Vector2, launch_from: Variant, launch_index: int) -> Node2D
	# instantiate "object." + object_id.replace(".", "-"); find its CollectibleScript (must match
	# object_id, push_error otherwise); set map_id, instance_id, quantity = amount,
	# source_resource_instance_id BEFORE add_child; root.position = launch_from (Vector2) or
	# destination; in launch mode pickup_area.monitorable = false before entering the tree;
	# add to Services.world().entities_root(); reset_physics_interpolation(); start the flight
	# tween (5.4) with root.create_tween() (pausable: stops in hit-stop like Phaser tweens),
	# ending with pickup_area.set_deferred("monitorable", true)
static func authored_quantity(object_id: String) -> int
	# the drop scene's authored `quantity` (instantiate once through WorldService's PackedScene
	# cache, read CollectibleScript.quantity, free it; or cache per object id); push_error if <= 0
```

`blocked(cell)` for `spawn_for` = `WorldService.is_solid_tile(cell.x, cell.y)` (true outside the
grid) or `occupied.has(cell)` or `reserved.has(cell)`. Compute `occupied` and `reserved` once per
call. Spawn the piles inside the weapon's `_physics_process` or deferred resolve; never in a
physics signal callback (Godot blocks adding Area2Ds there). The weapon already defers
`on_area_entered` resolves (`weapon.gd:198-209`). The depletion text goes after the spawns
(`floating_text(pos − (0, 46), message, &"yellow", true)`).

### 12.8 Cross-area changes

- `player.gd` (player owner):
  ```gdscript
  func on_pickup_area_entered(area: Node) -> void:   # PlayerScript.ts:52-56
  	var root := area.get_parent() if area != null else null
  	if root == null:
  		return
  	for child in root.get_children():
  		if child is CollectibleScript:
  			(child as CollectibleScript).request_pickup(get_pickup_area())
  			return

  func get_pickup_area() -> Area2D:                    # the body's "PickupArea" child
  	return body.get_node_or_null(^"PickupArea") as Area2D if body != null else null
  ```
  Optional `play_action_clip(clip)` for the berry `eat` (7.3): skipped while dead or while the
  knockback animation has priority; action lock, `stop_movement()`, `play_animation("eat")`,
  unlock after `animation.clip_length_ms` on SimClock, then `idle`. `CollectibleScript` is a
  preload cycle with player.gd's preloads, which is fine (ARCHITECTURE section 1).
- `particle_fx.gd` (combat owner): add `&"loot-sparkle"` to `PRESET_IDS` and `PRESETS` (7.4
  numbers; `"layer": LAYER_OVER`, `"additive": false`, `"rotate_min": 0, "rotate_max": 180`) and
  draw the `fx-sparkle` texture.
- `hud.gd` (world owner): show `RunState.player.coins` and refresh on `coins_changed` once
  berries award coins. The HUD still renders the new-run 50.
- `main.gd` (world owner): in `warm_runtime_scenes()`, warm `effect.<hit_effect_id>` and
  `object.<drop objectId with "." → "-">` for every node in group `resource_node`. Today that is
  `effect.wood-impact`, `effect.stone-impact`, `object.collectible-wood-pile`,
  `object.collectible-stone-pile` in level-1, plus `object.collectible-iron-ore-pile` in
  gloop-forest. Optional dev launch option `--weapon=<id>` / `?weapon=<id>` for
  `equip_run_start()` (the `weapon` launch option), so harvesting can be tried by hand (tests use `PlayerCombat.equip`).
- Enemy sight and movement: trees and stones are layer 1, so felling one opens sight lines
  (`WorldService.line_of_sight` mask 1) and paths, as in Phaser. Nothing to do.

### 12.9 Tests (`godot/tests/test_world_objects.gd`)

The style follows `tests/test_combat.gd`. The runner gives each test a fresh `main.tscn`
(level-1) and calls `RunState.new_run()`. Find nodes with
`t.world().world_root.get_node(NodePath(<instance id>))` (instance roots are named by instance
id) and its child `ResourceNodeScript` / `CollectibleScript`. Router-level tests make an
activation with a stand-in source `Node` and `Area2D`, built as in the existing combat tests:
`router.begin_activation(src, [area])`, then requests `{activation_id, source, attack_area,
target_area: node.damage_area, weapon_id, weapon_tags, damage_types: ["physical"], base_damage,
effects: [], impact: {position: base, knock: Vector2.RIGHT}}`, one activation per hit.

| Test | Setup | Expected |
|---|---|---|
| `test_inventory_capacity_and_stacking` | empty run | `item_capacity("wood") == 500`; four `collect_world_item` of 10 wood → slots `[wood 25, wood 15]`; `item_capacity("unknown") == 0`; `item_capacity("green-key") == 20` |
| `test_partial_collect` | 19 × `{stone, 25}` + `{wood, 20}` | collecting 10 wood moves **5**; record `remaining 5`; wood slot 25; second call moves 0 |
| `test_respawn_resolution` | `ResourceRespawn.resolve` | the six rows of section 6 (e.g. `{depleted, ready: now − 1}` → `{}`, changed; `{destroyed, piles, ready: past}` → unchanged; no timer → `ready = now + 600000`, changed) |
| `test_drop_placement_helpers` | static | `stable_offset(64, 1..5)` = (−5,4), (1,−9), (7,9), (−13,−2), (12,−8); `find_drop_cells((10,10), 3, none blocked)` = (9,9), (10,9), (11,9); with (9,9) blocked = (10,9), (11,9), (9,10); `complete_placements([], (5,5), 3, 64)` offsets (0,0), (−5,4), (1,−9); `pile_position((9,9), (0,0), 64)` = (608, 640); `source_cell((281.6, 1356.8), 64)` = (4, 20) |
| `test_sword_is_blocked_by_tree` | `level-1-tree-004` (527.25, 1254.95); request `weapon_tags ["weapon"]`, base 24 | result rejected `state-blocked`, retryable; HP 40; `harvest_blocked` payload `{targetTag "wood", minimumTier 1, message "Requires an Axe", x 527.25, y 1254.95}`; no record; tree not paused / no hit-stop |
| `test_axe_fells_tree_and_drops_wood` | same tree; 3 requests `["harvest:wood:1", "weapon"]`, base 14 | HP 26 → record `{node, 26}`; 12 → `{node, 12}`; third: actual 12, defeated; record `{destroyed, value 10, piles: 1 × {id "level-1-tree-004-drop-1", amount 10, object_id "collectible.wood-pile"}}` with `respawn_ready_at_epoch_ms == override + 600000`; `drops_requested` once with `pieces 1`; tree root queued for deletion; a CollectibleScript `instance_id "level-1-tree-004-drop-1"`, `quantity 10`, `source_resource_instance_id "level-1-tree-004"` exists; its `monitorable` false at first and true ≤ 400 ms of sim time later, at `pile_position` of the first free ring cell |
| `test_stone_needs_pickaxe_and_forgets_damage` | `level-1-stone-node-01` (1056, 352) | `["harvest:wood:2"]` blocked ("Requires a Pickaxe"); `["harvest:stone:1"]` base 14 → HP 66, **no record** (`persistHealth false`); breaking it (6 hits: 5 × 14, then 10) → 3 piles × 10 stone, ids `-drop-1..3` |
| `test_iron_needs_tier_2` | instantiate `object.resource-iron-node` under the world root with `map_id "level-1"`, `instance_id "test-iron"` | `["harvest:stone:2", "harvest:iron:1"]` blocked ("Requires a Reinforced Pickaxe"); `["harvest:iron:2"]` accepted |
| `test_walk_over_pickup` | teleport the player centre to (608, 561.44) (pickup rect on `level-1-loose-wood-04`) | `pickup_resolved {status "collected", moved 10, remaining 0}`; slots `[wood 10]`; record `{remaining 0}`; pile root freed; a yellow `+10 Wood` text |
| `test_inventory_full_keeps_pile` | 20 × `{stone, 25}`, same pile | `{status "rejected", moved 0, remaining 10, reason "inventory-full"}`; pile still there; no record; the `Inventory full` text once even if re-entered within 1 s |
| `test_partial_pickup_needs_reentry` | 19 × stone + `{wood, 20}` | `partial`, moved 5, remaining 5; record 5; standing still → no second request; step off and on → `rejected inventory-full` |
| `test_collected_pile_updates_node_record` | after felling `level-1-tree-004`, walk onto its pile | node record `{depleted, 0}` with the same `respawn_ready_at_epoch_ms`; pile record `{remaining 0, source "level-1-tree-004"}` |
| `test_records_restore_on_reload` | after the hit-1 state, instantiate a second copy of `object.tree-world-solid.grove-tree-04` with the same ids (free the original tree and its spawned pile first, so ids do not repeat) | its `get_damage_state().hp == 26`. After felling (piles uncollected), a fresh copy frees itself and restores 1 settled pile (`monitorable` true). After the pile is collected and the override clock is moved past `ready`, a fresh copy stands at 40 HP and the pile record is gone |
| `test_stone_axe_swing_end_to_end` | `t.player().get_combat().equip("stone-axe")`; player centre = tree base + (−60, −30), face right, tap attack | one routed accepted hit of **14** (or 25 on a crit) on `level-1-tree-004`; the tree is never paused by a hit-stop; HP 26 (or 15) |
| `test_purple_berry_coins` (low priority) | walk onto `level-1-purple-berry-03` (550.4, 1363.2) | `+1 Purple Berry`; coins 50 → 55 |

(Phaser parity for reference: the stone axe does 16 per hit there, because of the O3 combo
off-by-one.)

### 12.10 Deferred (OUT for this port)

- `game/scripts/destructible.gd` (no scenes); bag drops, loot drops and the `recovered` flag; the
  inventory UI; quests (`collectible.collected`); Stretch Lash pulls; the belt/bag advice text;
  saving RunState to disk; the HUD coin flash; occlusion; the dev overlay.
- Q1-Q16 stay as Phaser behaves. Owner questions worth asking: Q2 (give `wooden-axe` wood 1 and
  `pickaxe` stone 1?), Q4 (should the amber ore be a `resource`?), Q6 (place piles below or
  beside the node so they are not hidden behind it?), Q8 (retry while standing on a pile?).

### 12.11 Docs to update with the port

- ARCHITECTURE.md section 6: rows for `game.resource-node → scripts/resource_node.gd` and
  `game.collectible → scripts/collectible.gd` (exports, signals, the `request_pickup` API); remove
  "collectibles and resource nodes" from the unported sentence (line 109); fix the "no
  inheritance … converter reads only the target file" rule (12.2); add `RunState` to the autoload
  table and section 1's diagram; add the `game/world_objects/*` files to section 10.
- CONVENTIONS.md: nothing (the export and signal rules already cover it).
- GODOT_MIGRATION.md "Not yet": resource nodes and collectibles move to done.
