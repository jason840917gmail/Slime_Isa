# Crafting, the bag, the weapon belt and consumables: spec for the Godot port

Covers the Phase 3 game windows and the gameplay behind them that earlier specs left **[OUT]**:
recipes and the crafting service, the crafting window (portable and at stations), the inventory
window ("Bag": slots, details, use, drop, destroy, belt assignment), the weapon belt and weapon
switching (mouse wheel, HUD hotbar), consumables, the menu key and the menu tab strip.

Source of truth: the Phaser app on `feat/godot-migration` (read 2026-10-05). Paths are under
`src/game/` unless they start with `src/`, `godot/`, `scripts/` or `asset/`; `file:line` is the
current tree. Godot files are cited by function name where they were uncommitted work in progress.

Binding inputs: [ARCHITECTURE.md](../ARCHITECTURE.md), [CONVENTIONS.md](../CONVENTIONS.md),
[UI_THEME.md](../UI_THEME.md); [world-objects.md](./world-objects.md) (inventory internals §8, the
`RunState` inventory API §12.6, pile spawning §5.4), [interaction.md](./interaction.md) (the
workbench candidate §3.6, §8.6), [shell.md](./shell.md) (pause rules, `Shell.set_action`),
[audio.md](./audio.md) §5 (global cues), [combat.md](./combat.md) (`PlayerCombat.equip`).

Legend: **[IN]** port now. **[OUT]** exists in Phaser, deferred (listed so later phases know).
**[QUIRK]** the Phaser build behaves in a way its code or content probably did not intend; port it
as is unless the owner decides otherwise (§9). **[DIFF]** a deliberate Godot difference.
**[CENTRE]** a Phaser position measured from the player sprite centre (Godot: `get_centre()` =
feet − (0, 27.56)).

---

## 0. Scope and Phaser file map

| Concern | Phaser | Tag |
|---|---|---|
| Recipe table, stations, site titles, list order | `content/recipes/RecipeCatalog.ts`, `content/recipes/types.ts` | [IN] |
| Quote / craft rules | `crafting/CraftingService.ts` (the service instance and deps: `crafting/Crafting.ts:13-19`) | [IN] |
| Learned recipes | `features/progression/StoryProgress.ts:12, 34, 39` (`learnedRecipeIds` in the save) | [IN] data, [OUT] quests |
| Crafting window | `features/ui/CraftingSurfacePort.ts` + `content/scenes/authored/ui/crafting-ui.scene.json` | [IN] |
| What a craft does next (placeable, weapon to belt) | `scenes/WorldScene.ts:2295-2311` (`onCrafted`) | [IN] weapon part, [OUT] placement |
| Opening a station | `scenes/WorldScene.ts:1279-1285` (`openCraftingStation`), `features/scripts/WorkbenchScript.ts` | [IN] |
| Bag window | `features/ui/InventorySurfacePort.ts` + `ui/inventory-ui.scene.json` | [IN] |
| Bag drops (items on the ground) | `features/collectibles/InventoryDropController.ts`, `InventoryDropPlacement.ts`, `content/items/InventoryDropCatalog.ts`, `features/progression/WorldProgress.ts:444-479` | [IN] |
| Inventory storage and transactions | `systems/Inventory.ts` | [IN] (extends world-objects §8) |
| Belt rules | `systems/WeaponLoadout.ts`, `core/WeaponSlots.ts`, `core/GameState.ts:154-175` | [IN] |
| Switching, equip messages, bag/belt glue | `scenes/WorldScene.ts:1788-1793, 2157-2225` | [IN] |
| Wheel input | `features/player/WheelStepper.ts`, `features/scripts/PlayerScript.ts:100-104`, `game-constants.json` `input.weaponWheelStepLockMs` | [IN] |
| HUD hotbar | `features/ui/WeaponHotbarSurfacePort.ts` + `ui/weapon-hotbar.scene.json` | [IN] |
| Consumables | `scenes/WorldScene.ts:2005-2024` (`useItem`), `content/items/items.json` `use` | [IN] |
| Menu key, tab strip | `scenes/WorldScene.ts:2045-2080`, `features/ui/MenuTabsSurfacePort.ts` + `ui/menu-tabs.scene.json` | [IN] (Journal / Map tabs disabled until those windows exist) |
| Harvest advice text | `scenes/WorldScene.ts:2188-2203`, `features/combat/HarvestAdvice.ts` | [IN] |
| Furniture placement (placing a crafted workbench) | `features/building/FurniturePlacementController.ts`, `WorldScene.ts:1219-1253` | ported later: [furniture.md](./furniture.md) (C1 superseded) |
| Control hints (`inventory`, `crafting`, `weapon-switch`) | `features/hints/ControlHints.ts:22-24`, `WorldScene.ts:571-609` | [OUT] (interaction spec §2.10) |
| Quest hooks: `craft.completed`, `workbench.opened`, `control.used {weapon-switch}`, `furniture.placed` | `quests/QuestEventBridge.ts` | [OUT] (emit Godot signals now, §11) |
| Gulp quick wheel (eats Gulp materials from the bag) | `WorldScene.ts:913-969` | [OUT] (abilities spec §11.6) |
| `ui/CraftingUI.ts` (941 lines), `ui/InventoryUI.ts`, `ui/WeaponHotbar.ts`, `ui/CraftingLayout.ts`, `ui/WeaponThumbnail.ts` | legacy Phaser-object windows | **dead code**: imported by nothing but each other (checked with grep; `scripts/tests/scene-integration/ui-runtime-cutover.test.mjs:32` asserts `new WeaponHotbar(` is gone). Do not port anything from them; `crafting/Crafting.ts` `RECIPES`, `canCraft`, `craft`, `itemName` are only used by them |

The live windows are scene-JSON DOM surfaces: the authored Control scene renders, and a
`UiSurfacePort` (`snapshot()` model + `invoke(actionId, payload)`) owns the state. The port keeps
that split: a model builder per window (pure, testable) and a Control scene that renders it.

---

## 1. Data

### 1.1 Recipes (`RecipeCatalog.ts:3-87`, 15 entries, catalogue order = index used for sorting)

Every recipe has `tier: 1`. `U` = `uniqueOutput: true`, `Q` = `learnedByQuest: true`.

| # | id | name | station | flags | ingredients | output | description |
|---|---|---|---|---|---|---|---|
| 0 | `craft-workbench` | Workbench | portable | — | wood 40 | workbench 1 | A placeable crafting station. Place it from your bag, then use it to craft tools and weapons. |
| 1 | `craft-wooden-spear` | Wooden Spear | workbench | U Q | wood 20 | wooden-spear 1 | A light starter weapon with a visible golden thrust. |
| 2 | `craft-stone-axe` | Stone Axe | workbench | U Q | wood 10, stone 10 | stone-axe 1 | Required to harvest trees efficiently. |
| 3 | `craft-stone-pickaxe` | Stone Pickaxe | workbench | U Q | wood 10, stone 10 | stone-pickaxe 1 | Required to break stone resource nodes. |
| 4 | `craft-stone-spear` | Stone Spear | workbench | U Q | wood 20, stone 20 | stone-spear 1 | A stronger spear with a cool stone-blue thrust. |
| 5 | `craft-reinforced-pickaxe` | Reinforced Pickaxe | workbench | U Q | wood 10, stone 15, weaver-fang 3 | reinforced-pickaxe 1 | A stone pick bound with weaver fangs. Required to break iron ore nodes. |
| 6 | `craft-iron-spear` | Iron Spear | workbench | U Q | wood 10, iron-bar 4 | iron-spear 1 | An iron-headed spear: more damage and a quicker thrust than stone. |
| 7 | `craft-iron-axe` | Iron Axe | workbench | U Q | wood 10, iron-bar 3 | iron-axe 1 | Fells trees in a few strokes, and bites in a fight too. |
| 8 | `craft-slam-hammer` | Slam Hammer | workshop | U | wood 25, stone 25 | slam-hammer 1 | A slow, heavy hammer: a short reach, but it knocks enemies far back. |
| 9 | `smelt-charcoal` | Smelt Charcoal | forge | — | wood 5 | charcoal **2** | Char wood slowly in the Forge into clean-burning fuel. |
| 10 | `smelt-iron-bar` | Smelt Iron Bar | forge | — | iron-ore 2, charcoal 1 | iron-bar 1 | Melt iron ore over charcoal and cast it into a bar. |
| 11 | `brew-tonic` | Brew Slime Tonic | portable | — | purple-berry-mat 3 | hp-potion 1 | Turn meadow berries into a reliable healing tonic. |
| 12 | `cook-berry-basket` | Berry Basket | portable | — | purple-berry-mat 2, wood 5 | berry-basket 1 | A little woven basket of berries. Eat it for a quick boost of health and energy. |
| 13 | `brew-fizzy` | Brew Fizzy Brew | kitchen | — | purple-berry-mat 2, shard 1 | energy-potion 1 | Charge berry juice with crystal shards for energy recovery. |
| 14 | `weave-tonics` | Sticky Field Kit | kitchen | — | purple-berry-mat 2, silk-clump 2 | hp-potion **2** | Use spider-silk binding to pack two tonics. |

Notes: the recipe `name` is used in the list, in "Crafted 1 × <name>" and "Crafted: <name>"; the
details heading uses the **output item's** name instead (`Brew Slime Tonic` lists as "Brew Slime
Tonic" but the heading reads "Slime Tonic"). No station of kind `kitchen` exists in any world, so
recipes 13 and 14 can never be crafted [QUIRK, intended "after Release 1" per the comment at
`:76`].

### 1.2 Stations and sites (`RecipeCatalog.ts:90-154`)

A **site** is `{station, tier}`. `PORTABLE_SITE = {station: "portable", tier: 1}` (`:90`).

| station | name (`STATION_NAMES`, `:101-107`) | also crafts (`STATION_INCLUDES`, `:93-99`) | where |
|---|---|---|---|
| `portable` | Crafting | — | the Crafting tab of the menu (§5); there is **no C key** although comments at `:4, 89` and `types.ts` say "with C" [QUIRK] |
| `workbench` | Workbench | — | `object.interior-workshop-workbench(-vise)` scenes ("Use workbench", r 90, rise 76-76.85); in worlds only gloop-forest `gloop-ch2-workbench` at (1880, 1712); a placed workbench item [OUT] |
| `workshop` | Workshop | `workbench` | level-1 `level-1-workshop/station-script` at (640, 392), only in the `workshop.restored` story variant ("Use the Workshop", r 150, rise 150) |
| `forge` | Forge | — | level-1 `level-1-forge/station-script` at (1190, 1068), only in the `forge.restored` variant ("Use the Forge", r 130, rise 130) |
| `kitchen` | Kitchen | — | nowhere |

- `siteTitle(site)` (`:118-120`): `tier > 1 ? "<name> · Tier <tier>" : "<name>"` (U+00B7 with one
  space each side). Every authored site has tier 1, so titles are "Crafting", "Workbench",
  "Workshop", "Forge".
- `stationServes(station, recipeStation)` = equal, or `recipeStation in STATION_INCLUDES[station]`;
  `stationCrafts(station, recipe)` = `stationServes(station, recipe.station)` (`:123-130`).
- `upgradesOf(station)` = stations whose includes list it (`:133-135`): workbench → [workshop];
  all others → [].
- `recipesAt(site)` (`:144-154`):

```gdscript
func recipes_at(site: Dictionary) -> Array[Dictionary]:
	var upgrades := upgrades_of(site.station)
	var own := []; var teasers := []
	for index in CATALOG.size():
		var r := CATALOG[index]
		if station_crafts(site.station, r): own.append({r, index})
		elif r.station in upgrades and r.tier == 1: teasers.append({r, index})   # (a recipe can be both only if a station includes its own upgrade: never)
	# sort key: tier asc, then own-station (0) before shared (1), then catalogue index
	own.sort_custom(order); teasers.sort_custom(order)
	return own + teasers (recipes only)
```

Resulting lists (verified by importing the module in Node):

| site | recipes, in order |
|---|---|
| portable | craft-workbench, brew-tonic, cook-berry-basket |
| workbench | craft-wooden-spear, craft-stone-axe, craft-stone-pickaxe, craft-stone-spear, craft-reinforced-pickaxe, craft-iron-spear, craft-iron-axe, **craft-slam-hammer** (teaser, status `wrong-station`) |
| workshop | **craft-slam-hammer** (own first), craft-wooden-spear, craft-stone-axe, craft-stone-pickaxe, craft-stone-spear, craft-reinforced-pickaxe, craft-iron-spear, craft-iron-axe |
| forge | smelt-charcoal, smelt-iron-bar |
| kitchen | brew-fizzy, weave-tonics |

A station never lists the portable recipes (a workbench cannot brew a tonic; the player switches
to the Crafting tab, §5).

### 1.3 Learned recipes

- `StoryProgress.knowsRecipe(id)` = id in `learnedRecipeIds` (saved as `story.learnedRecipeIds`;
  Godot `RunState.story.learned_recipe_ids` already exists, empty in a new run).
- Only recipes with `learnedByQuest` check it (`CraftingService.ts:269`); every other recipe is
  known from the start (workbench, slam hammer, forge, portable consumables).
- Teachers (all quest rewards, `QuestService.ts:104`; quests are [OUT]):

| recipe | quest (file:line of the reward) |
|---|---|
| craft-stone-axe, craft-stone-pickaxe | `a-place-to-work` (`content/quests/quests/chapterOne.ts:52`) |
| craft-wooden-spear | `stone-tools` (`chapterOne.ts:144`) |
| craft-stone-spear | `worm-trouble` (`chapterOne.ts:193`) |
| craft-reinforced-pickaxe | `beyond-the-verdant-gate` (`chapterTwo.ts:50`) |
| craft-iron-spear | `rekindle-the-forge` (`chapterTwo.ts:148`) |
| craft-iron-axe | `iron-gear` (`chapterTwo.ts:188`) |

- Dev: the `recipes` cheat learns every catalogue id and shows "ALL RECIPES" (green, big) at
  [CENTRE] − 30 (`WorldScene.ts:2431-2434`).
- Learning emits `story.changed` (no cue, no text; quest reward text "New recipe: <name>" is the
  quest UI's, `features/quests/QuestRewardText.ts:19`).

### 1.4 Items and weapons as items

Base items: world-objects §8.2 (names, categories, max stacks). Additions relevant here:

| id | `use` (`items.json`) | `placeable.sceneIds` | `worldDrop` (droppable from the bag) |
|---|---|---|---|
| hp-potion "Slime Tonic" | `{healHp: 40}` | — | `collectible.hp-potion` |
| energy-potion "Fizzy Brew" | `{healEnergy: 50}` | — | `collectible.energy-potion` |
| berry-basket "Berry Basket" | `{healHp: 20, healEnergy: 30}` | — | `collectible.berry-basket` |
| workbench "Workbench" (furniture) | — | `object.interior-workshop-workbench`, `object.interior-workshop-workbench-vise` | **none** (cannot be dropped, can be destroyed) |
| every other items.json id | — | — | its pile (`collectible.wood-pile`, `collectible.stone-pile`, `collectible.iron-ore-pile`, `collectible.charcoal-pile`, `collectible.purple-berry`, `collectible.silk-clump`, `collectible.weaver-fang`, `collectible.iron-bar`, `collectible.crystal-shard`, `collectible.green-key`, `collectible.crystal-key`) |

`ItemUse` also allows `cureStatus: StatusKind[]` (`core/types.ts:52-56`); no item sets it.

Weapons are items (`systems/Inventory.ts:34-45`): `{id: weaponId, name: displayName, category:
"weapon", icon: iconKey, iconFrame, description, maxStack: inventory.weaponMaxStack (1), equipment:
{weaponId}}`. `weaponItemFor(weaponId)` = the first registry item whose `equipment.weaponId`
matches (`:47-49`). The 13 weapons (`content/weapons/<id>/weapon.json`, definition order of
`virtual-weapon-content.ts`):

| weaponId | displayName | baseDamage | cooldownMs | harvestCapabilities | iconKey, frame | how a run gets it |
|---|---|---|---|---|---|---|
| goo-gauntlet | Goo Gauntlet | 12 | 320 | — | `weapon-gauntlet` (procedural 32×32, `ProceduralAssetScene.ts:133`), 0 | never (dev arsenal, dead code) |
| basic-sword | **Basic sword** | 20 | 1200 | — | `weapon-player-sword-tiles`, 0 | never [QUIRK: the Godot trial weapon is unobtainable in Phaser] |
| basic-spear | Basic Spear | 10 | 800 | — | `weapon-player-hammer-spear-tiles`, 0 | never |
| slam-hammer | Slam Hammer | 14 | 1300 | — | `weapon-player-hammer-spear-tiles`, 2 | craft at the Workshop |
| wooden-axe | Wooden Axe | 12 | 900 | — | `weapon-player-wooden-axe-tiles`, 1 | never |
| pickaxe | Pickaxe | 12 | 900 | — | `weapon-player-pickaxe-tiles`, 0 | never |
| wooden-spear | Wooden Spear | 5 | 760 | — | `weapon-player-starter-spears-tiles`, 0 | craft (workbench) |
| stone-spear | Stone Spear | 7 | 820 | — | `weapon-player-stone-tools-tiles`, 1 | craft (workbench); playground test chest |
| stone-axe | Stone Axe | 12 | 900 | wood 1 | `weapon-player-stone-tools-tiles`, 2 | craft (workbench); playground test chest |
| stone-pickaxe | Stone Pickaxe | 12 | 900 | stone 1 | `weapon-player-stone-tools-tiles`, 3 | craft (workbench); playground test chest |
| reinforced-pickaxe | Reinforced Pickaxe | 15 | 900 | stone 2, iron 2 | `items-chapter-2-5x2`, 2 | craft (workbench) |
| iron-spear | Iron Spear | 10 | 800 | — | `items-chapter-2-5x2`, 3 | craft (workbench) |
| iron-axe | Iron Axe | 16 | 850 | wood 2 | `items-chapter-2-5x2`, 4 | craft (workbench) |

Weapon descriptions are shown in the bag details: basic-sword reads "A reusable weapon
definition." and basic-spear "A reusable layered weapon definition." (placeholder text) [QUIRK].

### 1.5 Icons (`asset/assets.json`; `textureKey` → sheet; frame index row-major)

| textureKey | file under `res://asset/` | frame w×h, grid | used by (frame) |
|---|---|---|---|
| `resources-starter-materials-2x1` | `MAPS/resources/128x128-tile_2x1-starter-materials.webp` | 128×128, 2×1 | wood (0), stone (1) |
| `resources-4x2` | `MAPS/resources/128x128-tile_4x2-resource-piles.webp` | 128×128, 4×2 | iron-ore (6), charcoal (7) |
| `items-potions-5x2` | `MAPS/items/potions-5x2.webp` | 64×64, 5×2 | hp-potion (0), energy-potion (6) |
| `items-forage-5x2` | `MAPS/items/forage-5x2.webp` | 64×64, 5×2 | purple-berry-mat (0) |
| `items-materials-5x2` | `MAPS/items/materials-5x2.webp` | 64×64, 5×2 | silk-clump (0) |
| `items-chapter-2-5x2` | `MAPS/items/chapter-2-5x2.webp` | 64×64, 5×2 | weaver-fang (0), iron-bar (1), reinforced-pickaxe (2), iron-spear (3), iron-axe (4) |
| `items-gems-5x2` | `MAPS/items/gems-5x2.webp` | 64×64, 5×2 | shard (0) |
| `items-keys-5x4` | `MAPS/items/keys-5x4.webp` | 64×64, 5×4 | green-key (0), crystal-key (1) |
| `interior-workshop-crafting-8x8` | `MAPS/interiors/128x128-tile_8x8-interior-workshop-crafting.webp` | 128×128, 8×8 | workbench (8 → region (0,128,128,128)) |
| `interior-kitchen-hearth-8x8` | `MAPS/interiors/128x128-tile_8x8-interior-kitchen-hearth.webp` | 128×128, 8×8 | berry-basket (50 → (256,768,128,128)) |
| `weapon-player-sword-tiles` | `MAPS/weapons/120x120_9x2_swordTiles.webp` | 120×120, 9×2 | basic-sword (0) |
| `weapon-player-hammer-spear-tiles` | `MAPS/weapons/126x126_2x2_HammerAndSpear.webp` | 126×126, 2×2 | basic-spear (0), slam-hammer (2) |
| `weapon-player-wooden-axe-tiles` | `MAPS/weapons/128x128-tile_3x1-wooden-axe.webp` | 128×128, 3×1 | wooden-axe (1) |
| `weapon-player-pickaxe-tiles` | `MAPS/weapons/128x128-tile_3x1-pickaxe.webp` | 128×128, 3×1 | pickaxe (0) |
| `weapon-player-starter-spears-tiles` | `MAPS/weapons/128x128-tile_2x2-starter-spears.webp` | 128×128, 2×2 | wooden-spear (0) |
| `weapon-player-stone-tools-tiles` | `MAPS/weapons/128x128-tile_4x1-stone-tools.webp` | 128×128, 4×1 | stone-spear (1), stone-axe (2), stone-pickaxe (3) |
| `weapon-gauntlet` | procedural (no file) | 32×32 | goo-gauntlet |

The DOM draws icons with `object-fit: contain; image-rendering: pixelated` at a fixed box (bag 44,
crafting rows 36, materials 30, hotbar 30); the frame is scaled down to fit.

### 1.6 Constants

| Value | Number | Source |
|---|---|---|
| belt slots | 4 | `WEAPON_HOTBAR_SLOT_COUNT`, `core/types.ts:17` (Godot `RunState.WEAPON_SLOT_COUNT`) |
| bag slots at a new run | 20 | `inventory.initialMaxSlots` |
| weapon max stack | 1 | `inventory.weaponMaxStack` |
| input buffer | 150 ms (simulation) | `input.bufferMs` |
| wheel step lock | 150 ms (event time = real time) | `input.weaponWheelStepLockMs` |
| wheel notch | 50 px of `deltaY` | `WHEEL_NOTCH_PX`, `WheelStepper.ts:2` (literal) |
| dev arsenal | goo-gauntlet, basic-sword, basic-spear, slam-hammer, wooden-axe, pickaxe | `WeaponLoadout.ts:6` (literal) |
| arsenal preferred slots | basic-spear → index 1, slam-hammer → index 2 | `WeaponLoadout.ts:8-11` |
| crafting window max | 1080 × 660 (content 660 tall) | `CraftingSurfacePort.ts:75-76`, scene |
| bag window max | 1000 × 640 (content 640 tall), min width 320 | `InventorySurfacePort.ts:88-89`, scene |
| crafting status colours | hint `#ffd277` (WARNING), refused `#ff6f88` (DANGER), success `#86f0c3` (ACCENT) | `CraftingSurfacePort.ts:232` |
| bag status colours | in hand `#ffd277`, on belt `#86f0c3`, muted `#a9c4b4` (**not** a token; `TEXT_MUTED` is `#8fbba3`) | `InventorySurfacePort.ts:274` |
| menu-tabs coach read time | 3000 ms (wall clock) | `MenuTabsSurfacePort.ts:26` |

---

## 2. The crafting service (`crafting/CraftingService.ts`)

### 2.1 Quote (`quote(recipe, requestedQuantity, site = PORTABLE_SITE)`, `:153-202`)

```
quote(recipe, requested, site):
    output_def = item(recipe.output.itemId)
    if output_def == null or not valid(recipe, output_def):                  # 2.4
        return {recipeId, requestedQuantity 0, maxCraftable 0, outputItemId, outputQuantity 0,
                requirements [], stats [], status "invalid-recipe"}
    totals = ingredient counts summed per item id (aggregateIngredients, :92-98; no recipe repeats an id)
    ingredient_limit = min over totals of floor(bag.count(item) / per_craft)
    unique_limit = recipe.uniqueOutput ? (bag.count(output) > 0 ? 0 : 1) : MAX_SAFE_INTEGER   # :173
    candidate = max(0, min(ingredient_limit, unique_limit))
    max_craftable = largest n in [0, candidate] with bag.previewTransact(removals(n), additions(n))
                    (binary search, :246-257: low 0, high candidate, mid = ceil((low+high)/2))
    quantity = normalize_quantity(requested, max_craftable)                  # 2.2
    requirement_quantity = max(1, quantity)
    requirements = per ingredient in recipe order:
        {itemId, perCraft, required = perCraft * requirement_quantity,
         available = bag.count(itemId), missing = max(0, required - available)}
    status = resolve_status(...)                                             # 2.3
    return {recipeId, requestedQuantity: quantity, maxCraftable: max_craftable,
            outputItemId, outputQuantity: output.count * quantity, requirements,
            stats: item_stats(output_def), status}
```

`removals(n)` = `[{item, per_craft * n}]` per ingredient; `additions(n)` = `[{output, output.count
* n}]` (`transactionFor`, `:100-109`). Because the transaction removes first (§2.5), a craft can
put its output into a slot its ingredients emptied. The binary search equals "the largest n whose
transaction fits"; a closed form is not needed (n is at most a few hundred).

### 2.2 `normalizeQuantity(value, maxCraftable)` (`:83-90`)

```
max = maxCraftable if safe integer > 0 else 0
if max == 0: return 0
n = value (number, or trimmed string -> Number)
if not finite(n) or n <= 0: return 1
return clamp(trunc(n), 1, max)
```

So with nothing craftable the quantity is **0**, and "−1" from 1 gives 1, never 0.

### 2.3 Status order (`resolveStatus`, `:259-274`) — the first match wins

1. `wrong-station` — `not stationCrafts(site.station, recipe)`
2. `station-tier` — `recipe.tier > site.tier` (never happens: everything is tier 1)
3. `not-learned` — `recipe.learnedByQuest and not knowsRecipe(recipe.id)`
4. `unique-owned` — `recipe.uniqueOutput and bag.count(output) > 0`
5. `missing-materials` — any requirement with `available < perCraft` (one craft's worth)
6. `inventory-full` — `maxCraftable == 0` (output def exists, so never `invalid-recipe` here)
7. `ready`

`maxCraftable` is computed before and independently of the status, so a not-learned or
wrong-station recipe with materials quotes e.g. "MAX 1" [QUIRK, visible in §4.3].

### 2.4 Recipe validity (`isValidRecipe`, `:231-244`)

Non-empty string id; output item id a string with an item definition; `output.count` a positive
safe integer; at least one ingredient; if the output item is a weapon, the weapon definition must
exist; every ingredient: non-empty id with an item definition and a positive safe-integer count.
All 15 recipes are valid with the current content (an `invalid-recipe` row reads "Unavailable").

### 2.5 Craft (`craft(recipe, requestedQuantity, site)`, `:204-229`)

```
q = quote(recipe, requested, site)
if q.status != "ready": return {ok false, reason q.status, quote q}        # bag untouched
if not bag.transact(removals(q.requestedQuantity), additions(q.requestedQuantity)):
    q = quote(recipe, requested, site)
    return {ok false, reason ("inventory-full" if q.status == "ready" else q.status), quote q}
emit craft.completed {recipeId, itemId: output, quantity: q.outputQuantity}   # -> CraftSuccess cue
return {ok true, recipe, quote q, outputQuantity q.outputQuantity}
```

`Inventory.transact(removals, additions)` (`systems/Inventory.ts:55-64, 95-144`), all or nothing,
one `inventory.changed`:

```
draft = copy of slots
for each removal item (summed per id, first-seen order): take from the FIRST matching slot onward;
    fail if not enough
compact = draft without empty slots (order kept)
for each addition item (summed, first-seen order): def must exist with maxStack > 0;
    fill that item's slots below maxStack in slot order, then append new slots of
    min(maxStack, left) while compact.size < maxSlots; fail if anything is left
slots = compact
```

`previewTransact` is the same without installing. Every count must be a positive safe integer.

### 2.6 Stat lines (`itemStats`, `:111-151`)

| output | lines |
|---|---|
| weapon with non-empty `harvestCapabilities` | one `{Harvest, "<tag>: <level>"}` per entry, in object order: stone axe "wood: 1"; stone pickaxe "stone: 1"; reinforced pickaxe "stone: 2", "iron: 2"; iron axe "wood: 2" |
| other weapon | `{Damage, round(baseDamage)}`, `{Cooldown, (cooldownMs/1000).toFixed(1) + "s"}`: wooden spear 5 / 0.8s (760), stone spear 7 / 0.8s (820), iron spear 10 / 0.8s, slam hammer 14 / 1.3s |
| item with `use` | `{Effect, "+<healHp> HP"}` then `{Effect, "+<healEnergy> energy"}` (cureStatus is not listed) |
| anything else (workbench, charcoal, iron bar) | none |

GDScript: `"%.1f" % (ms / 1000.0)` gives the same digits as `toFixed(1)` for these values (both
round the exact double: 0.85 → "0.8").

### 2.7 Worked examples (computed with the real `CraftingService` and a copy of the bag rules)

| Bag before | Recipe, site, qty asked | Quote | After craft |
|---|---|---|---|
| empty | workbench @portable, 1 | missing-materials, max 0, qty 0, req wood 40 (missing 40) | refused |
| [wood 25, wood 10] | workbench @portable | missing-materials, max 0, wood available 35, missing 5 | refused |
| [wood 25, wood 15] | workbench @portable, 1 | ready, max 1 | [workbench 1] |
| [berry 7] | brew-tonic @portable, 5 | ready, qty **2**, max 2, output 2 | [berry 1, hp-potion 2] |
| [berry 30, hp-potion 8] | brew-tonic, 10 | ready, max 10 (8+10 → stacks of 9) | — |
| [berry 6] + 19 × [stone 25] | brew-tonic, 1 | **inventory-full**, max 0 | refused |
| [berry 3] + 19 × [stone 25] | brew-tonic, 1 | ready, max 1 (the berry slot frees) | 19 × stone, [hp-potion 1] |
| [wood 25, wood 25, stone 20] | stone axe @workbench, learned | ready, max 1 | [wood **15**, wood 25, stone 10, stone-axe 1] (taken from the first wood slot) |
| [wood 25, stone 20] | stone axe @workbench, not learned | not-learned (max 1) | — |
| [wood 5] | stone axe @workbench, learned | missing-materials, req wood missing 5, stone missing 10 | — |
| [wood 25, stone 20, stone-axe] | stone axe @workbench, learned | unique-owned, max 0 | — |
| [wood 25, stone 20] | stone axe @portable, learned | wrong-station (max 1) | — |
| [wood 25] | smelt-charcoal @forge, 99 | ready, qty 5, max 5, output 10 | [charcoal 10] |
| [berry 2, silk 2] | weave-tonics @kitchen | ready, output 2 | [hp-potion 2] |
| [wood 10, iron-bar 4] | iron spear @workshop, learned | ready (the workshop crafts workbench recipes) | — |

### 2.8 Events and cues

| Event (Phaser) | When | Global cue (`AudioEventBridge.ts`) | Other listeners |
|---|---|---|---|
| `craft.completed {recipeId, itemId, quantity}` | a craft succeeded (inside `craft`) | `CraftSuccess` (`:94`) | quests [OUT] |
| `craft.failed {recipeId, reason}` | the Craft button was refused (`CraftingSurfacePort.ts:146`); not on quote | `CraftFail` (`:80`) | quests [OUT] |

Both cues: `audio.global` `Effects/CraftSuccess` (`sfx.ui.craft-success`) and `Effects/CraftFail`
(`sfx.ui.craft-fail`), pitch randomness 0.06, `minIntervalMs` 60.

---

## 3. After a craft (`WorldScene.onCrafted`, `:2295-2311`)

Runs after `craft.completed`, with the successful result.

### 3.1 Placeable output (the workbench) [OUT with placement]

`itemRegistry.get(output).placeable` → close the crafting window, `startFurniturePlacement(output)`
(`:1219-1223`: refused while paused, travelling, dead or without the item), then "Crafted:
<recipe name>" green big at [CENTRE] − (0, 44). Placement (for later phases): a ghost of the first
scene follows the pointer snapped to 32 px (`SNAP_PX`), valid within 220 px of the player
(`REACH_PX`) on a free footprint (tints `#9dffc8` / `#ff7a7a`), the wheel cycles the scene variants,
left click places (removes 1 from the bag, records `placedFurniture`, "Placed Workbench" green
small), right click or Esc cancels (the item stays in the bag); hint "Left click to place · Mouse
wheel to switch · Right click or Esc to cancel" (`FurniturePlacementController.ts:47-90, 135-145`).
A placed bench is a `game.workbench` site with "Hold: Pick up" (interaction spec §2.3).

### 3.2 Weapon output [IN]

```
weapon_id = item(output).equipment.weaponId
if weapon_id:
    slot = loadout.ensure_assigned(weapon_id)        # its belt slot, else the first empty one, else none
    if slot != none and loadout.equipped_weapon_id() == null:
        equip_weapon_slot(slot)                       # §8.4: "<name> equipped" + EquipBlade/EquipTool
floating text "Crafted: <recipe name>", green, big, at [CENTRE] − (0, 44)
```

- A crafted weapon goes onto the first empty belt slot; it goes into the hand only when the hand
  is empty. With a full belt it stays only in the bag.
- When both texts show they overlap: "<name> equipped" at −48, "Crafted: <name>" at −44 [QUIRK].
- Both texts (and the cues) appear while the crafting window is still open (paused game; the
  floating text runs on real time behind the window).

### 3.3 Anything else

Only the "Crafted: <recipe name>" text (e.g. "Crafted: Smelt Charcoal" for 10 charcoal; the
quantity is not in the text).

---

## 4. The crafting window (`CraftingSurfacePort.ts` + `ui.crafting-ui`)

### 4.1 Opening, closing, the site

| Path | Site | Refused when | Source |
|---|---|---|---|
| Interact with a station (`game.workbench`) | the station's `{recipeContext, tier}` | the world is paused, or crafting or the bag is open | `WorldScene.ts:1279-1285`; also emits `workbench.opened {mapId, context}` [OUT: quests] |
| The Crafting tab of the menu strip (§5) | **portable** (`open()` default) | another tab window is not open (tabs only show while one is) | `MenuTabsSurfacePort.ts:74-83` |
| `toggle(site)` | — | unused | `:44` |

`open(site)` (`:47-58`): no-op when already open (or destroyed). Sets the site; keeps the
previously selected recipe id if the new site lists it, else selects the first recipe; clears the
status message; pauses (source `crafting`); pushes the modal `crafting` (MenuOpen cue); publishes.
`close()` (`:60-66`): unpauses, pops the modal (MenuClose cue). Escape (modal stack) and the Close
button close it; the menu key closes it (§5). Per-recipe quantities (`quantities` map, recipe id →
int) **persist across openings** for the life of the world; the selected recipe id persists too.

Switching tabs away and back reopens crafting at the **portable** site: a station's window cannot be
returned to through the tabs [QUIRK]. While a station window is open the Crafting tab is the
disabled current tab, so "Bag" then "Crafting" shows the portable list.

### 4.2 Layout (`crafting-ui.scene.json`; content offsets; `W` = panel width)

The ModalRoot is centred: `offsetMin/Max = ∓(round(w/2), round(h/2))` with `w = min(1080, max(1,
viewport_w − 32))`, `h = min(660, max(1, viewport_h − 32))` (`:75-80`); at 1280×720 it is 1080 ×
660. Inside: a vertical `ScrollContainer` filling the panel with a `Content` of fixed height 660.
The panel style: `.game-ui--crafting-ui` radius 12, shadow `0 18px 48px #080e1abf`
(`src/styles.css:3566-3610`) = theme `WindowPanel`. zIndex 90, inputPriority 2000.

| Node | Rect (left, top)–(right, bottom) | Text / props | Theme role |
|---|---|---|---|
| Title | (20, 12)–(W−20, 54) | site title; 24 bold, warning | `PanelTitle` |
| Recipes (ItemList, 1 column, gap 8) | (20, 66)–(0.56W−12, 640) | rows §4.3; buttons min-height 60, radius 6, padding 6/10, left-aligned, icon 36×36 + 10 px gap, 2-line label | `SlotButton` rows |
| DetailsName | (0.58W, 66)–(W−20, 96) | 22 bold, warning | `PanelTitle` @22 |
| Details | (0.58W, 100)–(W−20, 196) | 14, wrap, line-height 1.45 | `Label` |
| MaterialsTitle | (0.58W, 202)–(W−20, 226) | "You need", 15 bold, warning (static) | `PanelTitle` @15 |
| Materials (ItemList, 2 columns, gap 6) | (0.58W, 230)–(W−20, 392) | rows min-height 52, icon 30×30, label 13 px accent, line-height 1.25 | `SlotButton` (inset) |
| Status | (0.58W, 484)–(W−20, 512) | 14 bold wrap, colour from the model | `Label` + colour override |
| Quantity | (0.58W, 518)–(W−20, 544) | "Amount: …", 14, info | `InfoLabel` |
| Minus10 / Minus1 / Plus1 / Plus10 / Max | x 0.58–0.655W / 0.66–0.735W / 0.74–0.815W / 0.82–0.895W / 0.90–0.98W; y 550–590 | "-10" "-1" "+1" "+10" "MAX"; 15 bold muted | `MutedButton` |
| Craft | (0.58W, 600)–(0.79W−6, 648) | "Craft", 18 bold accent | `PrimaryButton` |
| Close | (0.79W+6, 600)–(W−20, 648) | "Close (Esc)", 16 bold muted | `MutedButton` |

At W = 1080: right column starts at x 626.4; the list ends at 592.8.

### 4.3 The model (`snapshot`, `:68-112`)

`recipes = recipes_at(site)`; `selected = index of selectedRecipeId, else 0` (and the id is
rewritten to that row's); `quote = quote(selected, stored quantity)` (§4.4).

**Rows** (one per recipe; `row_quote = service.quote(recipe, 1, site)`):

- `locked` = row status in {`not-learned`, `station-tier`, `wrong-station`}; `short` = row status
  `missing-materials`.
- Label `"<recipe name>\n<state>"`, state = `short ? "Missing " + missing_list(row_quote, 2) :
  row_state(status)`:

| status | state text (`rowState`, `:219-230`) |
|---|---|
| ready | Ready to craft |
| station-tier | Needs tier <recipe.tier> |
| not-learned | Not learned yet |
| unique-owned | Already owned |
| inventory-full | Inventory full |
| wrong-station | At the <station name of the recipe> (e.g. "At the Workshop") |
| missing-materials | (the "Missing …" text above; "Materials needed" is unreachable) |
| invalid-recipe | Unavailable |

- `missing_list(quote, limit)` (`:235-239`): requirements with `missing > 0` as `"<missing> <item
  name>"` joined by ", "; with more than `limit` the first `limit` then ", …" (U+2026). Rows use
  limit 2, the status line no limit. A row's `missing` is for **one** craft.
- Icon: the output item's icon/frame. Locked rows: opacity 0.5, icon greyscale ×0.8 brightness,
  text `#9aa6b8`; they stay **selectable**. Short rows: a 4 px inset left edge in danger and the
  label in danger (`styles.css:3604-3610`).

**Details** (right column):

| Field | Value |
|---|---|
| `detailsName` | the output **item** name (e.g. "Slime Tonic"), else the recipe name |
| `details` | recipe description; if stats: `"\n\n"` + stat lines `"<label>: <value>"` joined by `"  ·  "` (two spaces each side), e.g. "Harvest: stone: 2  ·  Harvest: iron: 2", "Damage: 5  ·  Cooldown: 0.8s", "Effect: +20 HP  ·  Effect: +30 energy" |
| `materials` | per requirement (`materialRows`, `:203-216`): id `material-<itemId>`, label `"<name>\n<available> / <required>"` + (`"  (need <missing> more)"` if missing > 0 else `"  ✓"`), short flag when missing; icon of the item. `required` uses `max(1, quantity)` crafts |
| `quantity` | `"Amount: <quote.requestedQuantity>  ·  MAX <quote.maxCraftable>"` |
| `status` | the stored message if any, else `""` when ready, else `reasonText(status)` |
| `statusColor` | the stored colour if any, else hint `#ffd277` |
| `craftDisabled` | no quote, or status not in {ready, missing-materials, inventory-full} |
| `quantityDisabled` (all five buttons) | no quote or `maxCraftable < 1` |

`reasonText` (`:242-252`):

| reason | text |
|---|---|
| invalid-recipe | This recipe is unavailable. |
| wrong-station | Craft this at the <recipe station name>. |
| station-tier | Needs a tier <recipe.tier> <**site** station name>. |
| not-learned | Not learned yet — a quest will teach it. (U+2014) |
| unique-owned | You already have this item. |
| missing-materials | `"Missing: " + missing_list(quote) + "."` (all materials, for the requested quantity), or "More materials are needed." if the list is empty |
| inventory-full | Make room in your inventory first. |

No-recipe case (unreachable): name "Nothing to craft here", details "No recipes available",
quantity "Amount: 0".

### 4.4 Actions (`invoke`, `:120-160`)

All actions except `close` are ignored while closed. The stored quantity of a recipe is
`quantities[id] ?? 1`, re-normalised against the current max on **every** quote and written back
(`quote()`, `:174-179`), so it shrinks when materials go.

| Action (source) | Effect |
|---|---|
| `select-recipe {index}` (Recipes `item_selected`; click, Enter/Space, arrows) | ignore an index without a recipe; select it; clear the status message; publish. Re-selecting the same row also clears the message |
| `quantity-minus-10/-1`, `plus-1/-10` | `max = quote(recipe, 1).maxCraftable`; `quantities[id] = normalize(current + delta, max)`; clear the message |
| `quantity-max` | `quantities[id] = max` (0 when nothing craftable); clear the message |
| `craft` (Craft button) | `service.craft(recipe, quote(recipe).requestedQuantity, site)`. Success: message `"Crafted <outputQuantity> × <recipe name>"` (U+00D7), colour success, then `onCrafted` (§3). Failure: message `reasonText(reason)`, colour refused, emit `craft.failed` (CraftFail). Pressing Craft with missing materials or a full bag is how the player hears what is wrong |
| `close` (Close button, ModalRoot `close_requested`) | `close()` |

Live updates: `inventory.changed` → if the message colour is refused, clear it; publish
(`:182-188`). So a refusal gives way to the live hint when the bag changes; a success message
stays until the selection, quantity or window changes, even after the row turns "Already owned".

### 4.5 Pause, input, focus, sounds

- Pause source `crafting` (`WorldScene.setSimulationPaused`, `:750-772`): while any source is set
  the simulation stops (physics paused, the player's and enemies' velocities zeroed,
  `PlayerScript.clearInput()`, music ducked, control hints hidden). Hit-stop is separate.
- Keyboard (DOM): on open the first enabled button gets focus = the first recipe row
  (`HtmlControlPresentationAdapter.ts:61-72`); Tab / Shift+Tab cycle inside the window
  (`trapModalTab`); in a focused list ←/→ move by 1, ↑/↓ by the column count (1 here), Home/End,
  Enter/Space select, disabled entries are skipped (`ControlNodes.ts:340-369`). Escape closes
  (`ModalStack.ts`). No other keys act on the window; game keys do not reach the player.
- Sounds (scene connections): every button press → `ClickSfx` (`sfx.ui.click`, min 40 ms); every
  `item_selected` of Recipes **and Materials** → `SelectSfx` (`sfx.ui.hover`, min 40 ms, volume
  0.8). Selecting a material does nothing else. Opening → `MenuOpen`, closing → `MenuClose`
  (`AudioEventBridge.ts:104-109`, every modal except `chest-inventory` / `furniture-placement`).

### 4.6 What the player sees at a new run (texts for tests)

Portable (`Crafting` tab), empty bag: rows "Workbench\nMissing 40 Wood", "Brew Slime
Tonic\nMissing 3 Purple Berry", "Berry Basket\nMissing 2 Purple Berry, 5 Wood" (all short);
selected Workbench: name "Workbench", details the description only, materials "Wood\n0 / 40  (need
40 more)", quantity "Amount: 0  ·  MAX 0", status "Missing: 40 Wood." in `#ffd277`, Craft
**enabled**, ± and MAX disabled. Craft → same text in `#ff6f88` + CraftFail.

Workbench (station), empty bag, nothing learned: rows "Wooden Spear\nNot learned yet" … "Iron
Axe\nNot learned yet", last "Slam Hammer\nAt the Workshop", all locked; selected Wooden Spear:
details "A light starter weapon with a visible golden thrust.\n\nDamage: 5  ·  Cooldown: 0.8s",
materials "Wood\n0 / 20  (need 20 more)" (short), status "Not learned yet — a quest will teach it."
(`#ffd277`), Craft disabled.

---

## 5. The menu key and the menu tab strip

### 5.1 The menu key (`menu` = E, `PlayerInputActions.ts:34`; `WorldScene.ts:2045-2080`)

Listened in the DOM capture phase, so it works while a window holds keyboard focus. Ignored when
`event.repeat`, in title mode, with Ctrl/Alt/Meta held, or when typing in an input field.

```
toggle_menu():
    if no world or any shell window (pause, settings, game over, ...) is open: return false
    if a tab window (bag, crafting, journal, map) is open: close it; return true
    if action-locked (swing, roll lock, eat clip...) or paused (any pause source) or placing furniture: return false
    open the bag; return true
```

Notes: the key is not refused while dead (the bag opens during the 1400 ms before the game-over
screen) [QUIRK]; it is refused during a chest window, dialogue or quest offer (they are pause
sources); during a hit-stop (not a pause source) it opens the bag. The `map` key (M) opens the map
[OUT]. The pause menu's "Inventory" button closes the pause menu and opens the bag
(`WorldScene.ts:546`).

### 5.2 The tab strip (`ui.menu-tabs`, `MenuTabsSurfacePort.ts`)

- Visible only while one of the four tab windows is open (`current()` = first open of inventory,
  crafting, journal, map). Container 360 × 36 at the top centre: `(−180, 4)–(180, 40)` from
  `(0.5, 0)`; zIndex 95 (over the windows, 90); radius 10, shadow `0 10px 28px #080e1abf`.
- Buttons Bag / Crafting / Journal / Map, each a quarter (insets 6/3 px: Bag (6,6)–(−3,−6), the
  middle ones (3,6)–(−3,−6), Map (3,6)–(−6,−6)), 13 bold centred, radius 6. The open window's tab is
  **disabled** and drawn in warning (text and border; opacity 1). Theme: `TabStripPanel` +
  `TabButton`. ClickSfx on press.
- `invoke(tab)`: ignored for the current tab or when no tab window is open; learns the coach;
  closes the current window and opens the target (`open()` with no site: crafting is portable).
  Both MenuClose and MenuOpen play.
- Coach (first time): while a tab window is open and story flag `hint.menu-tabs` is not set, a
  bubble under the strip reads "These tabs switch between your Bag, Crafting, Journal and Map.
  Click one!" (15 bold warning, centred, wrap; rect (−20, 12)–(20, 74) below the strip's bottom,
  i.e. 400 px wide; 2 px warning border, radius 10, background `#0b1528f2`, an arrow up; bobs 4 px
  over 1.1 s ease-in-out, none under reduce motion). Clicking a tab sets the flag; closing the
  menu after the bubble was visible ≥ 3000 ms (wall clock) also sets it.

---

## 6. The bag window (`InventorySurfacePort.ts` + `ui.inventory-ui`)

### 6.1 Opening and closing

Opened by the menu key, the pause menu's Inventory button, or the Bag tab. `open()` (`:48-55`):
no-op when open; validate the selection (`ensureSelectedItem`, §6.3); pause (source
`inventory`); push modal `inventory` (MenuOpen); publish. `close()` mirrors crafting. Escape, the
Close button and the menu key close it. Dropping items closes it (§6.4).

### 6.2 Layout (`inventory-ui.scene.json`; `W` = panel width)

Panel: `w = min(1000, max(320, viewport_w − 32))`, `h = min(640, max(1, viewport_h − 32))`,
centred (1000 × 640 at 1280×720); radius 12 + shadow (`WindowPanel`); ScrollContainer; Content
640 tall. Buttons radius 8, padding 4/8; hovered enabled buttons get the raised surface.

| Node | Rect | Text / props | Theme role |
|---|---|---|---|
| Title | (20, 12)–(W−150, 52) | "Bag", 26 bold warning | `PanelTitle` @26 |
| Close | (W−140, 14)–(W−20, 50) | "Close (Esc)", 15 bold muted | `MutedButton` |
| BeltTitle | (20, 58)–(W−20, 80) | "Weapon belt", 16 bold warning | `PanelTitle` @16 |
| BeltHelp | (20, 80)–(W−20, 102) | "Click a slot to hold that weapon. Drag a weapon from the bag onto a slot to put it there. Outside, the mouse wheel switches." 13 muted | `MutedLabel` @13 |
| Belt (4 columns, gap 10, drop target) | (20, 106)–(W−20, 188) | §6.3; cells min-height 78, 2 px **dashed** border (solid when filled), muted text, slot number top-left (muted), the in-hand cell: warning border + inset 1 px warning ring + glow `0 0 14px #ffd27755` and "IN HAND" (10 px, weight 800, letter-spacing 0.06em, warning) top-right | `SlotButton` + overrides |
| ItemsTitle | (20, 200)–(0.6W−8, 224) | "In the bag — click an item to see it", 15 bold warning | `PanelTitle` @15 |
| Items (5 columns, gap 8) | (20, 230)–(0.6W−8, 620) | `maxSlots` cells (20 → 4 rows), each 88 px tall: icon 44×44 above the name (12 px, 2 lines max, centred), tag top-right (12 bold warning) | `SlotButton` |
| DetailsName | (0.62W, 200)–(W−20, 228) | 21 bold warning | `PanelTitle` @21 |
| DetailsStatus | (0.62W, 230)–(W−20, 252) | 14 bold, colour from the model | `Label` + colour |
| Details | (0.62W, 258)–(W−20, 360) | 14 wrap, line-height 1.4 | `Label` |
| Primary | (0.62W, 366)–(W−20, 412) | label from the model, 17 bold accent | `PrimaryButton` |
| AssignTitle (weapons only) | (0.62W, 422)–(W−20, 444) | "Or put it on a belt slot:" 13 muted | `MutedLabel` @13 |
| HotbarSlots (weapons only; 2 columns, gap 6) | (0.62W, 448)–(W−20, 540) | rows min-height 40, 13 px, left-aligned | `SlotButton` |
| Quantity (non-weapons) | (0.62W, 422)–(W−20, 444) | "Quantity: N", 14 warning | `WarningLabel` |
| Minus10 / Minus1 / Plus1 / Plus10 (non-weapons) | x 0.62W–0.715W−2 / 0.715W+2–0.81W−2 / 0.81W+2–0.905W−2 / 0.905W+2–W−20; y 448–488 | "-10" "-1" "+1" "+10", 15 bold muted | `MutedButton` |
| Drop / Drop all (non-weapons) | (0.62W, 496)–(0.81W−4, 536) / (0.81W+4, 496)–(W−20, 536) | 15 bold accent | `PrimaryButton` |
| Remove / RemoveAll (non-weapons) | (0.62W, 544)–(0.81W−4, 584) / (0.81W+4, 544)–(W−20, 584) | "Destroy" / "Destroy all", 15 bold danger | `DangerButton` |

At W = 1000: the grid ends at x 592, the right column starts at 620. Narrow screens (≤ 760 px CSS)
shrink cells to 60 px / 10 px text / 30 px icons (`styles.css:3522-3527`) [OUT unless needed].

### 6.3 The model (`snapshot`, `:65-148`)

State: `selectedSlotIndex?`, `selectedItemId?`, `quantity` (int ≥ 1).

`ensureSelectedItem()` (`:254-264`), on open and every snapshot: if the selected index still holds
an item with the selected id, clamp `quantity` to `[1, that slot's count]`; else select slot 0 (or
nothing for an empty bag) with quantity 1.

Let `slot` = the selected bag slot, `def` its item, `equipment = def.equipment`, `belt` = the 4
slot ids, `inHand` = equipped weapon id, `assignedIndex = belt.indexOf(weaponId)` (−1 when not on
the belt), `equipped = inHand == weaponId`.

| Model key | Value |
|---|---|
| `belt[i]` | id `belt-<i+1>`; if the slot's weapon is owned: label = item name, icon, `shortcut` = "<i+1>", draggable; else label `"Slot <i+1>\nEmpty"` (no icon). Empty belt cells are **not** disabled (a click does nothing, §6.4) |
| `beltSelectedIndex` | index of the in-hand weapon on the belt, else −1 |
| `items[i]`, i in `0..maxSlots−1` | id `slot-<i+1>`; with a stack: label = item name, icon, tag: weapon → "in hand" / "belt <n>" / "" (only in the bag); other → `"×<count>"` when count > 1 else ""; weapons draggable. Without a stack: label "Empty", **disabled** |
| `selectedIndex` | `selectedSlotIndex ?? −1` |
| `detailsName` | item name, else "Your bag is empty" |
| `detailsStatus`, colour | weapon in hand: "In your hand · belt slot <n>" `#ffd277`; on the belt: "On belt slot <n> · not in your hand" `#86f0c3`; weapon only in the bag: "In the bag · not on your belt" `#a9c4b4`; other: `"<Category> · <slot count> in the bag"` (`Material`, `Consumable`, `Key`, `Collectible`, `Furniture`; the **slot's** count, not the total) `#a9c4b4`; nothing selected: "" |
| `details` | `description`, plus `"\n\n" + effects` when the item has `use`: effects = "Heal HP +<healHp>", "Energy +<healEnergy>", "Cures <list>" joined by " · " (e.g. "Heal HP +20 · Energy +30"); empty bag: "Pick things up in the world and they land here." |
| `primaryLabel` | weapon: "In your hand" (equipped) / "Hold in hand"; placeable: "Place"; else "Use" |
| `primaryDisabled` | no item, or the weapon is in hand, or (not a weapon and no `use` and not placeable) — so keys, materials and shards show a disabled "Use" |
| `hotbarVisible` (AssignTitle + HotbarSlots) | the selected item is a weapon |
| `hotbarSlots[i]` | id `assign-<i+1>`, label `"<i+1>: <weapon name or 'empty'>"` |
| `hotbarSelectedIndex` | `assignedIndex` |
| `quantity` | `"Quantity: <quantity>"` |
| `quantityVisible`, `actionsVisible` | an item is selected and it is not a weapon |
| `dropDisabled` | no item, a weapon, or not droppable (§6.5: the workbench) |
| `removeDisabled` | no item or a weapon |

The window republishes on `inventory.changed`, `weapon.loadout.changed`, `weapon.equipped` and
resize.

### 6.4 Actions (`invoke`, `:156-220`)

Ignored while closed (except `close`). The last six act on the **selected** slot and are ignored
when that slot no longer holds the selected item id.

| Action (source) | Effect |
|---|---|
| `select-item {index}` (Items `item_selected`; also a right click, which selects first) | only a non-empty slot: select it, quantity 1 |
| `hold-belt-slot {index}` (Belt `item_selected`) | `weaponAt(index)` (owned) → select that weapon's first bag slot, then `equipWeaponFromInventory(weapon)` (§8.4). Empty slot: nothing but a republish |
| `drop-on-belt {index, sourceItemId, sourceIndex}` (Belt `item_dropped`; drag from a bag cell `slot-N` or a belt cell `belt-N`) | dragged weapon = `weaponAt(sourceIndex)` for `belt-*`, or the weapon item of bag slot `sourceIndex` for `slot-*`; select it in the bag, `assignWeaponSlot(weapon, index)` (§8.4). `index ≥ 4` or a bad payload: nothing |
| `use-or-equip` (Primary) | weapon → `equipWeaponFromInventory(weaponId)`; placeable → close the bag, `startFurniturePlacement` [OUT]; `use` → `useItem(id)` (§7) |
| `assign-slot {index}` (HotbarSlots `item_selected`) | weapon only, index 0..3 → `assignWeaponSlot(weaponId, index)` |
| `quantity-minus-10/-1`, `plus-1/-10` | `quantity = clamp(quantity + delta, 1, slot.count)` |
| `drop` / `drop-all` | not a weapon and droppable: `dropFromSlot(selectedIndex, drop-all ? slot.count : quantity)` (§6.5), then **close the bag** (also when the drop failed) |
| `remove` / `remove-all` (Destroy) | not a weapon: `amount = remove-all ? slot.count : quantity`; if `amount ≥ count` clear the selection (quantity 1) else `quantity = min(quantity, count − amount)`; `removeFromSlot(selectedIndex, amount)` (`Inventory.ts:188-198`). **No confirmation**, no sound but the click, no world effect; keys and the workbench can be destroyed [QUIRK] |
| `close` | close |

Sounds: ClickSfx on every button (Close, Primary, ±, Drop, Drop all, Destroy, Destroy all);
SelectSfx on Belt, Items and HotbarSlots `item_selected`. Focus on open: the first enabled button
in tree order = **Close** (it precedes the lists). Lists: 5 columns for arrows ↑/↓ in Items, 4 in
Belt, 2 in HotbarSlots; disabled (empty) cells are skipped.

### 6.5 Dropping on the ground (`InventoryDropController.ts:52-119`, `InventoryDropPlacement.ts`)

- Droppable = `resolveInventoryDropDefinition(item)` (`InventoryDropCatalog.ts:9-18`): a base item
  (not a weapon) with `worldDrop`, whose object is a `collectible.walk-over` for the same item id
  and has the visual. Every items.json item except the workbench.
- `dropFromSlot(slotIndex, requested)`:

```
slot = bag[slotIndex]; quantity = min(slot.count, requested)          # requested must be an int > 0
source = player centre [CENTRE]
destination = find_destination(source, facing, dims, inspect)         # below
if none: text "No ground space available" (white, big, 1800 ms) at [CENTRE] − (0, 42); return false
removed = remove_from_slot(slotIndex, quantity)                        # refund on mismatch
record = createInventoryDrop(map, {itemId, amount: quantity, objectId, visualId, x, y})
    # id "inventory-drop-<next_inventory_drop_sequence>", sequence += 1, world.progress.changed
spawn pile: launch from source to destination, launch index 0, instance id = record.id,
    remaining = quantity, sourceInventoryDropId = record.id            # world-objects §5.4 flight
on a spawn error: record amount 0 (deleted), refund, "Could not drop item"
```

- `find_destination` (`InventoryDropPlacement.ts:17-67`): `ts` = tile size; source cell =
  `(floor(x/ts), floor(y/ts) − 1)` (the resource-drop convention, world-objects Q6); forward =
  facing vector (up (0,−1), down (0,1), left (−1,0), right (1,0)); left = (forward.y, −forward.x).
  For radius r = 2, 3, … max(columns, rows) (radius 1 is skipped so the landing pile is not
  re-collected at once): the ring cells with Chebyshev distance r inside the grid, sorted by
  forward component desc, |side| asc, side desc, cellY asc, cellX asc. Walk them: `blocked` →
  skip; `compatible-stack` → return that pile's (x, y); remember the first `open`. After the ring,
  an open cell → `(cellX·ts + ts/2, (cellY + 1)·ts)`. Nothing in any ring → none.
- `inspect(cell)` (`InventoryDropController.ts:68-76`, `WorldScene.ts:1673-1688`): an existing
  inventory-drop record with amount > 0 whose cell `(floor(x/ts), floor(y/ts) − 1)` is this one →
  `compatible-stack` if the same item else `blocked`; outside the world or a solid tile → blocked;
  an authored root occupies it (world-objects `occupied_cells`, nothing excluded) → blocked; a live
  collectible with remaining > 0 at `(floor(x/ts), floor((y−1)/ts))` → blocked; else open.
- A "compatible stack" does **not** merge: a second record and a second pile land on the same
  point [QUIRK].
- Examples (all cells open, ts 64, source centre (640, 704) → source cell (10, 10)): facing down →
  cell (10, 12) → **(672, 832)**; facing right → (12, 10) → (800, 704); facing up → (10, 8) →
  (672, 576); facing left → (8, 10) → (544, 704).
- Pickup of a bag pile updates its record (`onCollectibleStateChanged` → `setInventoryDropAmount`,
  `WorldProgress.ts:467-479`: floor, ≥ 0, deleted at 0). On world load every record with amount >
  0 whose item still resolves to the same object/visual is spawned **settled**
  (`restore()`, `:164-183`; `WorldScene.ts:2389`). A dropped purple berry gives no coins when
  picked up again (the Godot `collectible.gd` already skips the reaction for bag drops).
- Enemy loot (`dropLoot`, `:126-162`, origin `loot`) uses the same records; it stays with the enemy
  rewards port [OUT].

---

## 7. Consumables (`WorldScene.useItem`, `:2005-2024`)

Reached only from the bag's Use button (Q eats Gulp materials, not consumables).

```
use_item(item_id):
    def = item(item_id); if not def.use or bag.count(item_id) <= 0: return
    if def.use.healHp:
        healed = player.heal(healHp)            # GameState.heal: 0 when dead; min(maxHp, hp + n) - hp
        if healed > 0: floating "+<healed>", green, big, at [CENTRE] − (0, 30)
                       # player.heal {amount} -> Heal cue (only when healed > 0)
    if def.use.healEnergy:
        regen_energy(healEnergy)                # clamp at max; energy.changed {delta = gained}
                                                # -> EnergyRestore cue when delta >= 20; no text
    if def.use.cureStatus: remove each status    # no item has one
    bag.remove(item_id, 1)                       # from the FIRST stack of that item, not the selected one
```

| Item | Effect | At full HP/energy |
|---|---|---|
| hp-potion "Slime Tonic" | +40 HP | **consumed anyway**, no text, no cue [QUIRK] |
| energy-potion "Fizzy Brew" | +50 energy | consumed, no cue |
| berry-basket | +20 HP, then +30 energy | consumed |

Examples: HP 50/100 → 90, "+40", Heal. HP 90 → 100, "+10". Energy 70 → 100 (delta 30 → cue);
95 → 100 (delta 5, no cue). Dead (during the 1400 ms before game over): heal 0, potion consumed
[QUIRK]. Using from the second of two potion stacks shrinks the first stack [QUIRK]. Using the last
of a stack removes the slot; `ensureSelectedItem` then selects slot 0 (§6.3). The world is paused
while the bag is open, so the heal shows on the HUD at once and the floating text rises behind the
window.

---

## 8. The weapon belt (`systems/WeaponLoadout.ts`, `core/GameState.ts`)

### 8.1 State

- `equipment.weaponId: string | null` (the weapon in hand) and `equipment.weaponSlots: (string |
  null)[4]` in the run's player data. A new run: `null` and `[null, null, null, null]`
  (`InitialRun.ts:21-24`). Godot `RunState.player.equipment = {weapon_id: null, weapon_slots:
  [null × 4]}` already exists.
- **The belt holds references, not items.** Every weapon lives in the bag as a 1-stack item; a
  belt slot only names one. `ownsWeapon(id)` = `bag.count(weaponItemFor(id).id) > 0`
  (`:33-36`); `weaponAt(i)` = the slot's id when owned, else null (`:38-42`).
- `setWeaponSlots(slots)` (`GameState.ts:162-167`): normalise to 4 entries (non-strings and blank
  strings → null; `fitWeaponSlots`, `core/WeaponSlots.ts:9-20`, packs older 6/3-slot saves starting
  from the equipped weapon); emit `weapon.loadout.changed {slots}` only when something changed.
- `equipWeapon(id)` (`:169-175`): trim, blank → null; no change → false; else store and emit
  `weapon.equipped {weaponId}` → cue `EquipBlade` when the id matches `/sword|spear/`, else
  `EquipTool`; nothing for null (`AudioEventBridge.ts:60, 90-92`).
- Weapons never leave the bag in play: equipment cannot be dropped or destroyed (§6.4) and no
  recipe consumes one. "Not owned" belt entries only come from old saves or tests.

### 8.2 `reconcile()` (`:52-100`), at every world load (`WorldScene.ts:314`) and after the dev arsenal

```
slots = [slot if owned else null for the 4 slots]; drop later duplicates of an id
for id in ARSENAL: if id has a preferred index p, is on the belt at c != p and slots[p] is empty: move it to p
for id in ARSENAL: if owned and not on the belt: put it in its preferred empty slot, else the first empty one
    (stop when the belt is full)
equipped = weaponId
if equipped owned and not on the belt and an empty slot exists: put it in the first empty slot
setWeaponSlots(slots)
if equipped and not owned: equipWeapon(first owned weapon on the belt, else null)
```

Only `slam-hammer` among the arsenal ids is obtainable, so: an owned slam hammer that is not on
the belt is put back on it at every world load, and one sitting in slot 1 moves to slot 3 when
that is empty [QUIRK]. `grantDevelopmentArsenal()` (`:44-50`: add each arsenal weapon not owned,
then reconcile) has **no caller**.

### 8.3 Belt rules

`assignWeapon(slotIndex, weaponId)` (`:102-123`) → `{ok, equipAssignedWeapon}`:

```
if slotIndex not in 0..3 or not owned(weaponId) or unknown weapon: {ok false}
slots = copy; previous_target = slots[slotIndex]; previous_index = slots.find(weaponId)
if previous_index == slotIndex: {ok true, equip false}
if previous_index >= 0: slots[previous_index] = previous_target      # swap within the belt
slots[slotIndex] = weaponId; setWeaponSlots(slots)
{ok true, equip: previous_index < 0 and previous_target == equipped}   # a bag weapon replaced the hand
```

`previous_target == equipped` is also true when both are null: assigning a bag weapon to an empty
slot while the hand is empty equips it. A weapon replaced on the belt stays in the bag.

`ensureAssigned(weaponId)` (`:143-150`): not owned → none; its belt index if on the belt; else the
first empty slot (via `assignWeapon`), else none.

`cycleSlot(step)` (`:130-141`), step +1 (wheel down, `weapon-next`) or −1 (wheel up):

```
current = slots.find(equipped) if equipped else -1
start = current if current >= 0 else (3 if step > 0 else 0)
for offset in 1..4:
    i = (start + step * offset + 4 * offset) % 4
    if i == current: return none                # wrapped round to the hand: no other weapon
    if weaponAt(i): return i
return none
```

Examples: `[axe, null, pick, null]`, axe in hand: next → 2, previous → 2; pick in hand: next → 0.
`[null, sword, null, null]`, nothing in hand: next → 1 (start 3), previous → 1 (start 0). Only one
weapon, in hand: none (nothing happens, no text).

`equipSlot(slotIndex, apply)` (`:152-165`) → `{ok, weaponId, changed}` or `{ok false, reason}`:
empty slot → `empty`; not owned → `not-owned`; unknown definition → `unknown`; already in hand →
`{ok, changed false}`; `apply(weaponId)` false → `busy`; else `equipWeapon(weaponId)`, `{ok,
changed true}`. `apply` = `CombatController.equipWeapon` (`CombatController.ts:178-190`): false
while a swing is in flight; true without remounting when it is already the mounted weapon; else
mount `weapon.<id>`, play the player's `idle` (subject to the knockback priority). The weapon in
the run data is mounted when the combat controller is built at world load (`:110-114`).

### 8.4 World glue (`WorldScene.ts`)

| Function | Behaviour |
|---|---|
| `equipWeaponSlot(i)` (`:2164-2182`) → changed? | `equipSlot(i, combat.equipWeapon)`. Changed: floating `"<weapon item name> equipped"` (e.g. "Stone Axe equipped", "Basic sword equipped"), **yellow, big**, at [CENTRE] − (0, 48). Failure: white **small** text at [CENTRE] − (0, 42): `empty` "Slot <i+1> is empty", `not-owned` "Weapon not in inventory", `busy` "Finish the attack first", `unknown` "Weapon is unavailable". Already in hand: nothing |
| `switchWeaponSlot(i)` (`:2157-2161`) | `equipWeaponSlot(i)`; when the hand changed: learn hint `weapon-switch` [OUT], emit `control.used {controlId: "weapon-switch"}` [OUT: quests] |
| `equipWeaponFromInventory(id)` (`:2206-2216`) | `slot = ensureAssigned(id)`; if found → `equipWeaponSlot(slot)`. Full belt: `hand = index of the in-hand weapon` (−1 → 0); `assignWeaponSlot(id, max(0, hand))`; if the hand is still not `id`, `equipWeaponSlot(max(0, hand))` |
| `assignWeaponSlot(id, i)` (`:2218-2225`) | `assignWeapon(i, id)`; failure → "Weapon not in inventory" (white, small, −42); `equipAssignedWeapon` → `equipWeaponSlot(i)` |

The bag's "Hold in hand" and belt clicks use `equipWeaponFromInventory`; the HUD hotbar and the
wheel use `switchWeaponSlot`. The bag can be opened from the pause menu during a swing, so "Hold in
hand" there can answer "Finish the attack first" (the menu key itself is refused while
action-locked).

### 8.5 Wheel input (`PlayerScript.ts:100-104`, `WheelStepper.ts`, `WorldScene.ts:1788-1793`)

- Only wheel events over the game canvas count (`InputEvent.ts:43-46`); `deltaY` in pixels (lines ×
  `WHEEL_LINE_PX`, pages × `WHEEL_PAGE_PX`); positive → `WheelDown` → `weapon-next`, negative →
  `weapon-previous`.
- `WheelStepper.step(direction, deltaPx, timestampMs)` (event timestamps, real time):

```
if t < quiet_until: quiet_until = t + 150; accumulated = 0; return false     # any scroll extends the lock
if direction != last_direction: last_direction = direction; accumulated = 0
accumulated += max(0, deltaPx)
if accumulated < 50: return false
accumulated = 0; quiet_until = t + 150; return true                           # one step
```

  A completed step records a buffered press at the player's simulation time (same 150 ms buffer as
  every press). `clearInput()` resets the stepper.
- Dispatch: first thing in `handleActionInput` (`:1788-1793`), both actions in order next then
  previous; each consumed press runs `cycleSlot(step)` → `switchWeaponSlot`. It does **not** end
  the step: the slime keeps walking and an attack can follow in the same step. `handleActionInput`
  is not reached while dead, sleeping, movement-suppressed (roll, knockback), action-locked (swing)
  or holding Q's wheel, so a wheel press then waits in the buffer and is dropped once older than
  150 ms [QUIRK: a scroll during a swing is usually lost].
- During furniture placement the wheel cycles the placement variant instead [OUT].
- **No number keys switch weapons**: 1-4 are the abilities (dodge, stretch lash, squash slam,
  teleport). The belt's "1"-"4" labels in the bag are positions only.

### 8.6 The HUD hotbar (`WeaponHotbarSurfacePort.ts` + `ui.weapon-hotbar`)

- Always mounted with the HUD (`UniversalSceneWorldController.ts:716`). Container 256 × 56
  anchored bottom centre: `(−128, −172)–(128, −116)` from `(0.5, 1)` (above the ability bar at
  −84…−12); zIndex 20; transparent (`.game-ui--weapon-hotbar`, no background, border or shadow;
  text shadow `0 1px 2px #081022, 0 0 6px #081022d9`). One 4-column list, gap 4 → cells 61 × 56.
- Cells: transparent, 1 px border `#f5f7ff` at 38 % + `0 0 0 1px #08102240`, radius 5, padding 2/3,
  10 px text; an owned weapon shows only its icon (30 × 30, pixelated, centred; the name is the
  tooltip); an empty or unowned slot shows its label as text ("Empty", or the stale weapon's name)
  and is **disabled**. The in-hand cell: 1 px warning border + 1 px warning outline at 55 %, offset
  2 px, and a 5 px warning triangle under it (selection never by colour alone). Narrow screens ≤ 420
  px scale 0.92 [OUT].
- Model: `weapons[i] = {id "slot-<i+1>", label: item name ?? id ?? "Empty", disabled: not owned,
  icon when owned}`; `selectedIndex` = the slot holding the in-hand weapon (owned), else −1. Refresh
  on `inventory.changed`, `weapon.loadout.changed`, `weapon.equipped`.
- Click (`item_selected` → `equip-slot {index}`): ignored unless 0..3 and owned; `switchWeaponSlot`
  (§8.4); then republish (a refused equip restores the real selection). SelectSfx on click. HUD
  controls never take keyboard focus (`tabIndex −1`, mousedown keeps focus). Clicking it never
  attacks (the press is not on the canvas). It is not blocked while dead or during a swing (→ "Finish
  the attack first"), nor under an open window that does not cover it (K16).

### 8.7 How the player gets weapons

- **Phaser**: a new run has no weapon (attacks do nothing; the `attack` hint waits for one). The
  first weapons are crafted: 40 loose wood → Workbench (portable) → place it [OUT] → the quest
  `a-place-to-work` teaches the stone axe and pickaxe → craft at the bench → onto the belt, the
  first into the hand (§3.2). Chests can hold weapons (the playground's `playground-test-chest`:
  stone-spear, stone-axe, stone-pickaxe, wood 20, stone 20, silk 10, hp-potion 5, weaver-fang 3);
  a chest transfer only adds to the bag, it never assigns the belt (`ChestInventorySurfacePort`,
  `InventoryWorldTransaction.transferChestStack`). The dev arsenal is dead code; the dev panel has
  no weapon grant.
- **Godot today**: `main.equip_trial_weapon()` builds `PlayerCombat` every world and equips
  `basic-sword` (or the `weapon` launch option), writing only `RunState.player.equipment.weapon_id`;
  the sword is not in the bag and the belt is empty (owner decision O5).

### 8.8 Harvest advice (`WorldScene.ts:2188-2203`, `HarvestAdvice.ts:16-26`) [IN with the belt]

When a tree, stone or ore blocks the weapon in hand (world-objects §4.2), the cyan message at
`(node.x, node.y − 58)` becomes:

```
belt = owned weapons on the belt; bag = every owned weapon (registry order)
if any belt weapon has harvestCapabilities[targetTag] >= minimumTier: "<message>: switch with the mouse wheel"
elif any bag weapon has it: "<message>: put yours on the belt (E)"
else: "<message>"
```

The labels come from the bindings (`controlLabel('weapon-next').toLowerCase()` = "mouse wheel",
`controlLabel('menu')` = "E"). Example: holding the sword with a stone axe on the belt → "Requires
an Axe: switch with the mouse wheel".

---

## 9. Quirks (port as is unless the owner decides otherwise)

| # | Quirk | Where |
|---|---|---|
| K1 | No C key: portable crafting opens only from the Crafting tab, although code comments say "C" | §1.2 |
| K2 | Kitchen recipes (Fizzy Brew, Sticky Field Kit) are uncraftable: no kitchen exists | §1.1 |
| K3 | Locked recipes still quote a MAX and enable the quantity buttons | §2.3 |
| K4 | Returning to Crafting through the tabs loses the station (portable list) | §4.1 |
| K5 | A craft success message stays after the row becomes "Already owned" | §4.4 |
| K6 | "<name> equipped" (−48) and "Crafted: <name>" (−44) overlap | §3.2 |
| K7 | Destroy has no confirmation and works on keys and the workbench | §6.4 |
| K8 | A failed drop still closes the bag | §6.4 |
| K9 | Dropping next to a same-item bag pile adds a second pile at the same point | §6.5 |
| K10 | Potions are consumed at full HP/energy (and while dead) | §7 |
| K11 | Use takes from the first stack of the item, not the selected one | §7 |
| K12 | Bag status muted colour `#a9c4b4` is not a theme token | §1.6 |
| K13 | An owned slam hammer returns to the belt (slot 3 if free) at every world load (dev-arsenal reconcile) | §8.2 |
| K14 | A wheel scroll during a swing/roll is buffered then usually dropped | §8.5 |
| K15 | The menu key opens the bag while dead | §5.1 |
| K16 | Game windows have no backdrop: where the centred panel does not cover the hotbar (viewports at least 984 px tall for the bag, 1004 px for crafting) the hotbar stays clickable, equipping while paused | §8.6 |
| K17 | Basic sword / basic spear descriptions are placeholders; "Basic sword" is lower-case | §1.4 |
| K18 | The basic sword (the Godot trial weapon), basic spear, wooden axe, pickaxe and gauntlet cannot be obtained in a Phaser run | §1.4 |

---

## 10. Data the port needs in `generated/data/`

### 10.1 Recipes: a `TS_DATA_EXPORTS` entry [IN]

`content/recipes/RecipeCatalog.ts` has only an `import type` (erased by Node 24's type stripping),
so it imports cleanly; checked: `import('…/RecipeCatalog.ts')` exposes `RECIPE_CATALOG` (15
entries) and the functions. Add to `scripts/godot/lib/inputs.mjs`:

```js
export const TS_DATA_EXPORTS = [
  ['npcs/NpcDefinitions.ts', 'NPC_DEFINITIONS', 'npc-definitions.json'],
  ['recipes/RecipeCatalog.ts', 'RECIPE_CATALOG', 'recipes.json'],
];
```

and reword its comment to "no runtime imports (`import type` is erased)". Output: a JSON array of
`{id, name, station, tier, description, ingredients: [{itemId, count}], output: {itemId, count},
uniqueOutput?, learnedByQuest?}` in catalogue order (camelCase, as every data file). The station
tables `STATION_INCLUDES` / `STATION_NAMES` are module-private; keep them as constants in
`recipe_catalog.gd` with a `RecipeCatalog.ts:93-107` reference (exporting them would mean editing
`RecipeCatalog.ts`, a scene-conversion input whose ledger then needs re-hashing, AGENTS.md).

### 10.2 Weapon names, descriptions, icons, stats: `weapons.json` [IN]

`virtual-weapon-content.ts` imports 13 JSON files without import attributes, so it cannot be a
TS export. Add a small reader in `inputs.mjs` (`readWeaponCatalog()`): take the weapon directory
order from the `import … from './<dir>/weapon.json'` lines of `virtual-weapon-content.ts`, read
each `content/weapons/<dir>/weapon.json` and write `data/weapons.json`:

```json
[{"weaponId": "goo-gauntlet", "displayName": "Goo Gauntlet", "description": "…", "category": "melee",
  "iconKey": "weapon-gauntlet", "iconFrame": 0, "baseDamage": 12, "cooldownMs": 320}, …,
 {"weaponId": "stone-axe", …, "harvestCapabilities": {"wood": 1}}]
```

(`convert-scenes.mjs:147-148` sets `outputs` for data; add one line for it.) The converted weapon
scenes already carry the combat numbers; this file is for names, descriptions, icons and the
crafting stat lines. `ItemCatalog` then defines weapon items from it (§11.4), replacing the
scene-index test and the id-as-name fallback.

### 10.3 Item icons: `item-icons.json` [IN]

From `asset/assets.json` (the converter already loads it, `loadAssetManifest`), for every distinct
`icon` in items.json and `iconKey` in weapons.json: `{"<textureKey>": {"path":
"res://asset/<source.path>", "frame": [w, h], "columns": c, "rows": r}}` (an `image` asset is one
frame of its `expect` size); a key in `content/weapons/procedural-weapon-icons.json` writes
`{"procedural": true}`; any other unknown key fails the conversion. The textures are already
copied by `pnpm godot:sync`. Values: §1.5.

---

## 11. Godot port plan

### 11.1 Integration facts from the current Godot code

- `RunState` (`game/autoload/run_state.gd`): bag `inventory = {max_slots, slots: [{item_id,
  count}]}`; `item_count`, `item_capacity`, `add_item` (**all or nothing**, unlike Phaser's partial
  `Inventory.add`), `remove_item` (first slot onward, bool), `collect_world_item`,
  `transfer_chest_stack`, signal `inventory_changed({})`; `player.equipment = {weapon_id: null,
  weapon_slots: [null ×4]}`, `WEAPON_SLOT_COUNT := 4`; `story.learned_recipe_ids` (unused yet);
  map records with `inventory_drops`, `next_inventory_drop_sequence`; `debug_active_quests` is the
  precedent for a quest stand-in.
- `ItemCatalog` (`game/world_objects/item_catalog.gd`): items.json + max stacks; a weapon is any
  `weapon.<id>` scene id; `item_name` falls back to the id for weapons.
- `PlayerCombat.equip(weapon_id)` (`game/combat/player_combat.gd`): refused while attacking;
  always remounts (no "same weapon" short cut); `get_weapon()`, `unequip()`, `is_attacking()`.
- `main.gd`: `equip_trial_weapon()` per world build (§8.7); `Interaction` child made once in
  `_ready`; `_teardown_world()` on travel; `launch_option(name)`.
- `InteractionController._use_workbench(_bench)` returns false (stub); `WorkbenchScript.site()`
  returns `{"station", "tier"}` (group `crafting_station`).
- `player.gd`: `heal(amount) -> int` (0 when dead/full, emits `health_changed`, no cue),
  `spend_energy`, `set_energy`, `_regen_energy`, signal `energy_changed {"energy", "maxEnergy",
  "delta"}`, `clear_input()`, `_update_modal_pause()` (ALWAYS `_process`: on the `modal` reason's
  rising edge clears input and stops), `_handle_action_input()` (interact, abilities, attack,
  eat), `play_animation(clip, force)`. `PlayerInputBuffer.ACTIONS` lacks `weapon_next/previous`.
- `WorldService.set_pause_reason(reason, active)`; `PAUSE_MODAL := &"modal"`. `MusicDirector.
  is_menu_paused()` already treats `modal` (and any non-hit-stop reason) as a menu pause and ducks.
- `Shell`: `set_action(&"inventory", callable)` for the pause menu button; `is_any_open()`;
  Escape is handled in `Shell._unhandled_input` after main's nodes (main gets unhandled input
  first); its windows pause with `shell:<id>` and clear the player's input when the last closes.
- `GameFeel.floating_text(pos, text, color, big)` (ALWAYS, CanvasLayer 8), `audio_cue(cue)`
  (searches `GlobalAudio`); colours `white, yellow, orange, green, red, cyan, blue`.
- `ResourceDrops.spawn_pile(object_id, pile_id, map_id, amount, source_id, destination,
  launch_from, launch_index)` sets `source_resource_instance_id = source_id` only;
  `occupied_cells`, `pile_position`; the flight is ported. `collectible.gd` exports
  `source_inventory_drop_id`.
- UI: the theme (`UiTokens.theme()`, variations in UI_THEME.md) is not yet the project theme, so a
  screen root sets `theme` itself, like the shell scenes. `ControlLabels.control_label(&"menu")` =
  "E", `(&"weapon_next")` = "Mouse wheel". Layers: arrival fade 5, floating text 8, interaction
  prompt 9, HUD 10, Shell 50.

### 11.2 Files

| File | Kind | Content |
|---|---|---|
| `game/crafting/recipe_catalog.gd` | static (`RecipeCatalog`) | `recipes.json`; `all()`, `find(id)`, `PORTABLE_SITE`, `STATION_NAMES`, `STATION_INCLUDES`, `is_station`, `station_name`, `site_title`, `station_serves`, `station_crafts`, `recipes_at(site)` (§1.2) |
| `game/crafting/crafting_service.gd` | static (`CraftingService`) | `normalize_quantity`, `quote`, `craft`, `item_stats`, status order (§2); emits through `RunState.recipe_crafted` |
| `game/inventory/weapon_catalog.gd` | static (`WeaponCatalog`) | `weapons.json`: `find(id)`, `ids()` (definition order), `display_name`, `harvest_capabilities` |
| `game/inventory/item_icons.gd` | static (`ItemIcons`) | `icon(item_id) -> Texture2D`: cached `AtlasTexture` (region = frame cell) from `item-icons.json`; a 32×32 placeholder for procedural/unknown keys |
| `game/inventory/inventory_drops.gd` | static (`InventoryDrops`) | `can_drop(item_id)`, `find_destination(source, facing, dims, inspect)`, `drop_from_slot(index, qty) -> bool`, `restore(map_id)`, `on_pile_changed(map_id, drop_id, remaining)` (§6.5) |
| `game/player/weapon_loadout.gd` | static (`WeaponLoadout`) | pure belt rules on `RunState` (§8.2-8.3); `WheelStepper` as an inner class or `game/player/wheel_stepper.gd` |
| `game/inventory/inventory_actions.gd` | Node (`InventoryActions`), child "InventoryActions" of main, made once, group `inventory_actions`, PROCESS_MODE_ALWAYS | the `WorldScene` glue: `switch_weapon_slot`, `equip_weapon_slot`, `equip_weapon_from_bag`, `assign_weapon_slot`, `use_item`, `on_crafted`, `harvest_message(payload)`, `equip_run_weapon()`; signal `message_shown({"text","color","x","y"})` (test hook, as `InteractionController`) |
| `game/ui/screens/game_windows.gd` | CanvasLayer (`GameWindows`), child "GameWindows" of main, layer **40**, ALWAYS, group `game_windows` | owns the bag, crafting window and tab strip; menu key; Escape; pause reason; MenuOpen/Close cues; `Shell.set_action(&"inventory")`; `open_bag()`, `open_crafting(site)`, `open_station(site) -> bool`, `close_all()`, `is_any_open()`, `current_tab()` |
| `game/ui/screens/game_window.gd` | Control base (`GameWindow`) | full-screen mouse-stopping root + centred `WindowPanel` sized from the viewport; `surface_id`, `open()/close()/is_open()`, `refresh()`, focus of the first enabled button, ClickSfx/SelectSfx players (`sfx.ui.click` 40 ms; `sfx.ui.hover` 40 ms, −1.94 dB = volume 0.8) |
| `game/ui/screens/crafting_screen.gd` + `.tscn` | `GameWindow` | §4 (model built by `crafting_model.gd`) |
| `game/ui/screens/crafting_model.gd` | static | `snapshot(state) -> Dictionary` with the exact keys/texts of §4.3; `reason_text`, `row_state`, `missing_list` |
| `game/ui/screens/inventory_screen.gd` + `.tscn` | `GameWindow` | §6 (model by `inventory_model.gd`) |
| `game/ui/screens/inventory_model.gd` | static | `snapshot(state) -> Dictionary`, §6.3 |
| `game/ui/screens/menu_tabs.gd` | Control | §5.2 |
| `game/ui/screens/item_cell.gd` | Button (`SlotButton`) | icon `TextureRect` (expand, keep aspect, nearest filter), name `Label`, corner tag `Label`; `toggle_mode` for selection; drag source/target (`_get_drag_data`, `_can_drop_data`, `_drop_data`) |
| `game/ui/weapon_hotbar.gd` | Control in the HUD | §8.6; built by `hud.gd` |
| `godot/tests/test_crafting.gd`, `test_inventory.gd`, `test_loadout.gd` | tests | §11.9 |

All new files are outside `game/scripts/` (no scene-script ids). The windows are Godot-owned
scenes built by hand on the theme (like the shell), loaded by path; the converted
`generated/scenes/ui/crafting-ui.tscn`, `inventory-ui.tscn`, `weapon-hotbar.tscn`,
`menu-tabs.tscn` stay unused (list them in CONVENTIONS "Scenes Godot owns").

### 11.3 RunState additions (owner: world objects; snake_case keys)

```gdscript
signal weapon_loadout_changed(payload: Dictionary)   # {"slots": Array} (weapon.loadout.changed)
signal weapon_equipped(payload: Dictionary)          # {"weapon_id": String or null} (weapon.equipped)
signal recipes_learned(payload: Dictionary)          # {"recipe_ids": Array[String]} (new ids only)
signal recipe_crafted(payload: Dictionary)           # {"recipeId", "itemId", "quantity"} (craft.completed)
signal craft_failed(payload: Dictionary)             # {"recipeId", "reason"} (craft.failed)

## Inventory.transact / previewTransact (§2.5): all or nothing, one inventory_changed.
## removals/additions: Array of {"item_id", "count"} (counts > 0). False for unknown items.
func transact_items(removals: Array, additions: Array, preview: bool = false) -> bool
## Inventory.removeFromSlot: removes min(count, slot.count) from slot `index`; drops it at 0.
func remove_from_slot(index: int, count: int) -> int
func slots() -> Array                                  # read-only view for the windows

# --- belt (GameState equipment) ---
func weapon_slots() -> Array                           # copy, 4 entries (String or null)
func set_weapon_slots(slots: Array) -> void            # normalise (blank -> null, size 4); signal only on change
func equipped_weapon_id() -> Variant                   # String or null
func set_equipped_weapon(weapon_id: Variant) -> bool   # trim, "" -> null; false when unchanged; signal

# --- recipes (StoryProgress) ---
func knows_recipe(recipe_id: String) -> bool           # id in learned_recipe_ids or debug_all_recipes_known
func learn_recipes(recipe_ids: Array) -> int           # appends new ids; recipes_learned when > 0
var debug_all_recipes_known: bool = false              # stand-in until quests (owner question C2); new_run() resets it

# --- bag drops (WorldProgress.ts:444-479) ---
func inventory_drops(map_id: String) -> Array          # copies of {"id","item_id","amount","object_id","visual_id","x","y","origin"?}
func create_inventory_drop(map_id: String, drop: Dictionary) -> Dictionary   # id "inventory-drop-<seq>", seq += 1
func set_inventory_drop_amount(map_id: String, drop_id: String, amount: int) -> void   # floor, >= 0, erase at 0
```

Fold the `RunState.player.energy` copy as today (the player owns live energy). `capture_player`
already keeps the equipment dictionary untouched.

### 11.4 Catalogues and the service (pseudo-code)

```gdscript
# item_catalog.gd additions
static func definition(item_id: String) -> Dictionary:
	# items.json entry; else for a weapon a synthesized {"id", "name": displayName, "category": "weapon",
	# "icon": iconKey, "iconFrame", "description", "equipment": {"weaponId": id}}; else {}
static func is_weapon(item_id) -> bool: return WeaponCatalog.find(item_id) != {}   # scene index as fallback
static func item_name(item_id) -> String: definition(item_id).get("name", item_id)

# crafting_service.gd
static func quote(recipe: Dictionary, requested: Variant, site: Dictionary = RecipeCatalog.PORTABLE_SITE) -> Dictionary
static func craft(recipe: Dictionary, requested: Variant, site: Dictionary = RecipeCatalog.PORTABLE_SITE) -> Dictionary
	# {"ok": true, "recipe", "quote", "output_quantity"} | {"ok": false, "recipe", "quote", "reason"}
	# on success: Services.run().recipe_crafted.emit({...}); Services.feel().audio_cue(&"CraftSuccess")
```

Quote dictionaries keep Phaser's camelCase keys (`recipeId`, `requestedQuantity`, `maxCraftable`,
`outputItemId`, `outputQuantity`, `requirements: [{itemId, perCraft, required, available,
missing}]`, `stats: [{label, value}]`, `status`), like scene payloads, so tests read like the TS.

### 11.5 `weapon_loadout.gd` (static, on RunState)

```gdscript
const SLOT_COUNT := 4                                   # RunState.WEAPON_SLOT_COUNT
const ARSENAL: PackedStringArray = ["goo-gauntlet", "basic-sword", "basic-spear", "slam-hammer", "wooden-axe", "pickaxe"]
const PREFERRED := {"basic-spear": 1, "slam-hammer": 2}

static func owns_weapon(id) -> bool: return ItemCatalog.is_weapon(id) and run.item_count(id) > 0
static func weapon_at(index) -> String                  # "" when empty/unowned/out of range
static func reconcile() -> void                          # §8.2, exactly (keeps K13)
static func grant(ids: Array) -> void                    # add each weapon not owned (add_item 1), then reconcile
static func assign_weapon(index, id) -> Dictionary      # {"ok", "equip_assigned_weapon"} §8.3
static func ensure_assigned(id) -> int                   # -1 = none
static func cycle_slot(step: int) -> int                 # -1 = none
static func equip_slot(index, apply: Callable) -> Dictionary   # {"ok": true, "weapon_id", "changed"} | {"ok": false, "reason"}
```

`WheelStepper` (RefCounted): `step(direction: StringName, delta_px: float, t_ms: float) -> bool`,
`reset()`; notch 50, lock `GameConstants.number("input.weaponWheelStepLockMs")` (150).

### 11.6 `inventory_actions.gd` (WorldScene glue)

```gdscript
const EQUIP_TEXT_RISE := 48.0; const FAIL_TEXT_RISE := 42.0; const CRAFTED_TEXT_RISE := 44.0
const HEAL_TEXT_RISE := 30.0; const ENERGY_CUE_MIN_DELTA := 20.0
const BLADE := ["sword", "spear"]                        # /sword|spear/ (AudioEventBridge.ts:60)

func equip_weapon_slot(index: int) -> bool:
	var combat := _combat()                              # Services.world().player.get_combat()
	var apply := func(id: String) -> bool:
		if combat == null: return false
		if combat.get_weapon() != null and combat.get_weapon().weapon_id == id: return not combat.is_attacking()
		if not combat.equip(id): return false
		_player().play_animation("idle")                 # CombatController.equipWeapon: idle
		return true
	var result := WeaponLoadout.equip_slot(index, apply)
	if result.ok:
		if result.changed: _text(centre - (0, 48), "%s equipped" % ItemCatalog.item_name(id), &"yellow", true)
		return result.changed
	_text(centre - (0, 42), FAIL_TEXTS[result.reason] % (index + 1), &"white", false)
	return false

# RunState.weapon_equipped -> audio_cue(EquipBlade if the id contains "sword" or "spear" else EquipTool); none for null
func switch_weapon_slot(index)                          # §8.4 + emit control_used({"controlId": "weapon-switch"}) for quests later
func equip_weapon_from_bag(id); func assign_weapon_slot(id, index)   # §8.4 verbatim
func use_item(id)                                        # §7: player.heal, then player.restore_energy(n) (new, see 11.8),
                                                         # Heal cue when healed > 0, EnergyRestore when gained >= 20,
                                                         # then RunState.remove_item(id, 1)
func on_crafted(result)                                  # §3.2-3.3 (placeable: see owner question C1)
func harvest_message(payload: Dictionary) -> String      # §8.8, used by resource_node.gd
func equip_run_weapon() -> void                          # world build: WeaponLoadout.reconcile(); mount
                                                         # RunState.equipped_weapon_id() if any (CombatController ctor)
```

The `<name> equipped` text, failure texts and Crafted text go through `GameFeel.floating_text`
**and** `message_shown`, so tests can read them.

### 11.7 The windows: pause, input, theme

- **Pause**: `GameWindows` sets `WorldService.set_pause_reason(PAUSE_MODAL, true)` while any of its
  windows is open and clears it when the last closes (a tab switch closes then opens inside one
  call, so the tree never runs in between). Later Phase 3 windows (chest, dialogue, journal, map)
  join the same owner, so one `modal` reason is enough. Effects: the tree pauses (simulation,
  enemies, tweens), `player.gd._update_modal_pause` clears input and stops the body, MusicDirector
  ducks. On the last close also call `player.clear_input()` (as the Shell does). [DIFF] Enemy
  velocities are frozen, not zeroed (Phaser `stopMovingBodies`); they resume their motion.
- **Process**: `GameWindows`, its windows and the hotbar are `PROCESS_MODE_ALWAYS`.
- **Menu key**: `GameWindows._input` (before the GUI, standing in for the DOM capture phase):
  `event.is_action_pressed(&"menu")` and not echo and no Ctrl/Alt/Meta → `toggle_menu()` (§5.1)
  with the Godot conditions: `Shell.is_any_open()` → nothing; a tab window open → close it; else
  refused while `player.is_action_locked()`, the tree is paused by a reason other than hit-stop
  (`modal` or `shell:*`), `main.is_transitioning()` [DIFF, safety], or no player; else `open_bag()`.
  Mark the event handled when it acted.
- **Escape**: `GameWindows._unhandled_input` (main's child, so before the Shell): while a window is
  open, `ui_cancel` / `pause` closes the top one and is marked handled (the pause menu does not
  open). While open, every other key and mouse-button event that reaches `_unhandled_input` is
  marked handled (the DOM modal key trap), so the player buffers nothing.
- **Mouse**: each `GameWindow` root is a full-screen Control with `MOUSE_FILTER_STOP` (clicks and
  the wheel never reach the world or the HUD). [DIFF] K16: the hotbar cannot be clicked under an
  open window.
- **Focus**: on open focus the first enabled, visible button in tree order (crafting: the first
  recipe row; bag: Close). Lists of `item_cell` buttons in a `GridContainer`; arrow keys move by
  1 / by the column count with Godot focus neighbours (set `focus_neighbor_*` on the cells to
  reproduce ←→↑↓, Home/End; skip disabled cells); Enter/Space press the focused cell (= select).
  Tab cycles inside the open window (nothing else is focusable: HUD cells use `FOCUS_NONE`).
- **Theme** (UI_THEME.md): root `theme = UiTokens.theme()` until it is the project theme. Roles as
  in the layout tables (§4.2, §6.2, §5.2): `WindowPanel`, `PanelTitle` (+ font-size overrides 26 /
  22 / 21 / 16 / 15), `MutedLabel`, `WarningLabel`, `InfoLabel`, `PrimaryButton`, `MutedButton`,
  `DangerButton`, `SlotButton` (cells and rows; `button_pressed` = selected), `TabStripPanel` +
  `TabButton`, `InsetPanel` for empty cells, `BarePanel` for the hotbar wrapper. Per-node overrides
  only for what changes at run time: the status colours (`UiTokens.WARNING`, `DANGER`, `ACCENT`;
  `#a9c4b4` for the muted bag status, K12), locked rows (`modulate.a = 0.5`, label `#9aa6b8`,
  icon greyscale via a shader or `self_modulate` grey), short rows (danger label + a 4 px danger
  `StyleBoxFlat` left border). Ask the theme owner for two variations: `HotbarSlot` (transparent,
  1 px `#f5f7ff` at 38 % border, radius 5; selected = warning border) and `BeltSlot` (2 px dashed
  border, solid when filled; Godot `StyleBoxFlat` has no dashes, so a solid 2 px border at 60 %
  stands in) [DIFF].
- **Icons**: `ItemIcons.icon(id)` in a `TextureRect` (`STRETCH_KEEP_ASPECT_CENTERED`,
  `TEXTURE_FILTER_NEAREST`) of 44 / 36 / 30 / 30 px as listed.
- **Sounds**: ClickSfx on every `BaseButton.pressed` (`ShellMenu` does the same), SelectSfx when
  a list cell is selected, `GameFeel.audio_cue(&"MenuOpen")` on open and `&"MenuClose"` on close.
- **World teardown**: `main._teardown_world()` calls `game_windows.close_all()` (no travel can
  start while paused, so this is a safeguard).

### 11.8 Changes to existing files

| File | Change |
|---|---|
| `game/main.gd` | create `InventoryActions` and `GameWindows` once in `_ready` (after `Interaction`); in `_build_world` replace `equip_trial_weapon()` by: create PlayerCombat as today, then `inventory_actions.equip_run_weapon()`; a new run (`RunState.started` just set, first build) runs the trial grant (owner question C3): `WeaponLoadout.grant([TRIAL_WEAPON_ID or ?weapon])` → `ensure_assigned` → equip. Keep the `weapon` launch option (grant + equip that weapon). New dev options: `arsenal` (grant the 6 arsenal ids), `recipes` (`debug_all_recipes_known = true`). After `register_world`: `InventoryDrops.restore(map_id)`. `_teardown_world`: `game_windows.close_all()` |
| `game/scripts/player.gd` | `_unhandled_input`: wheel `InputEventMouseButton` (index `MOUSE_BUTTON_WHEEL_DOWN/UP`, pressed) and `InputEventAction` `weapon_next/previous` (tests) go through `WheelStepper.step(action, 50 × (factor if factor > 0 else 1), Time.get_ticks_msec())`; a step marks a buffered press (`PlayerInputBuffer.mark_pressed(action, now_sim)`, new). `_handle_action_input`: first consume `weapon_next` then `weapon_previous` → `WeaponLoadout.cycle_slot(±1)` → `InventoryActions.switch_weapon_slot`; **do not return**. `clear_input()` also resets the stepper. New `restore_energy(amount) -> float` (clamp, `energy_changed` with the gained delta, returns it). |
| `game/player/player_input_buffer.gd` | `mark_pressed(action, now)`; leave the wheel actions out of `ACTIONS` (they bypass `capture`) |
| `game/interaction/interaction_controller.gd` | `_use_workbench(bench)`: refuse when the tree is paused or `game_windows.is_any_open()`; else `game_windows.open_station(bench.site())` and emit `workbench_opened({"mapId", "context"})` (quests later); return the result |
| `game/scripts/resource_node.gd` | the blocked text uses `InventoryActions.harvest_message(blocked)` when present (§8.8); the `harvest_blocked` payload keeps the plain authored message |
| `game/world_objects/resource_drops.gd` | `spawn_pile(...)` gains `inventory_drop_id: String = ""` (sets `source_inventory_drop_id`, leaves the resource source empty) |
| `game/scripts/collectible.gd` | on a pickup of a pile with `source_inventory_drop_id`, `RunState.set_inventory_drop_amount(map_id, id, remaining)` (Phaser `onCollectibleStateChanged`) |
| `game/ui/hud.gd` | build `WeaponHotbar` (bottom centre, §8.6); bind it to `RunState` signals |
| `game/world_objects/item_catalog.gd` | weapons from `WeaponCatalog` (§11.4); `icon(item_id)` delegates to `ItemIcons` |
| `scripts/godot/lib/inputs.mjs`, `convert-scenes.mjs` | §10 |

### 11.9 Tests (expected values)

Helpers as in `test_interaction.gd`: `t.main.get_node("GameWindows")`, `Services.run()`. Reset the
bag with `run.inventory.slots = [...]` then `run.inventory_changed.emit({})`. Read texts from
`InventoryActions.message_shown`, cues from `GameFeel` `GlobalAudio/Effects/<Cue>.playing`
(`test_audio.gd::_global_cue`). Static tests need no world. Tests that start from "nothing in
hand" first undo the trial grant (C3): `set_weapon_slots([null, null, null, null])`,
`set_equipped_weapon(null)`, remove the granted weapon from the bag, `PlayerCombat.unequip()`.

`test_crafting.gd`:

| Test | Setup | Expected |
|---|---|---|
| `test_recipe_data` | — | 15 recipes; `recipes_at(PORTABLE_SITE)` ids = [craft-workbench, brew-tonic, cook-berry-basket]; workbench = the 8 ids of §1.2 ending with craft-slam-hammer; workshop starts with craft-slam-hammer; forge = [smelt-charcoal, smelt-iron-bar]; `site_title({"station": "workshop", "tier": 2}) == "Workshop · Tier 2"`, `site_title(PORTABLE_SITE) == "Crafting"` |
| `test_normalize_quantity` | — | `(5, 0) → 0`; `(0, 3) → 1`; `(-4, 3) → 1`; `(2.9, 3) → 2`; `("7", 3) → 3`; `("x", 3) → 1` |
| `test_workbench_from_wood` | bag [wood 25, wood 15] | quote ready, max 1; craft ok, output 1; slots `[{workbench 1}]`; `recipe_crafted` `{"recipeId": "craft-workbench", "itemId": "workbench", "quantity": 1}`; CraftSuccess plays |
| `test_status_order` | §2.7 rows | wrong-station (portable), not-learned, unique-owned, missing-materials (wood missing 5, stone missing 10), inventory-full (berry 6 + 19 × stone 25), ready (berry 3 + 19 × stone 25 → last slot `{hp-potion 1}`) |
| `test_quantity_and_max` | [berry 7], brew-tonic, ask 5 | requested 2, max 2, output 2; after craft [berry 1, hp-potion 2]. [wood 25] smelt-charcoal ask 99 at the forge → requested 5, output 10, bag [charcoal 10] |
| `test_first_slot_consumed` | [wood 25, wood 25, stone 20], stone axe learned, workbench site | after craft: [wood 15, wood 25, stone 10, stone-axe 1] |
| `test_crafted_weapon_to_belt_and_hand` | as above, nothing equipped | belt `["stone-axe", null, null, null]`; equipped `stone-axe`; `PlayerCombat.get_weapon().weapon_id == "stone-axe"`; messages "Stone Axe equipped" (yellow, centre − (0,48)) then "Crafted: Stone Axe" (green, centre − (0,44)); EquipTool and CraftSuccess play |
| `test_crafted_weapon_keeps_hand` | holding stone-axe on slot 0, learn + craft stone pickaxe | belt [stone-axe, stone-pickaxe, null, null]; equipped still stone-axe; only "Crafted: Stone Pickaxe" |
| `test_portable_window_new_run` | `open_crafting(PORTABLE)` | title "Crafting"; rows "Workbench\nMissing 40 Wood", "Brew Slime Tonic\nMissing 3 Purple Berry", "Berry Basket\nMissing 2 Purple Berry, 5 Wood" (short); status "Missing: 40 Wood." colour WARNING; "Amount: 0  ·  MAX 0"; Craft enabled, ± and MAX disabled; tree paused with `modal`; Craft → same status in DANGER, CraftFail plays, `craft_failed {"recipeId": "craft-workbench", "reason": "missing-materials"}` |
| `test_refusal_clears_on_bag_change` | after the refused Craft, add 40 wood | status "" ; row "Workbench\nReady to craft"; materials "Wood\n40 / 40  ✓"; "Amount: 1  ·  MAX 1" |
| `test_success_message_stays` | learned stone axe, materials, workbench site, Craft | status "Crafted 1 × Stone Axe" (ACCENT); row "Stone Axe\nAlready owned"; Craft disabled; the status text unchanged after `inventory_changed` |
| `test_station_window_rows` | `open_station({"station": "workbench", "tier": 1})` | title "Workbench"; 8 rows; row 0 "Wooden Spear\nNot learned yet" locked; row 7 "Slam Hammer\nAt the Workshop" locked; details "A light starter weapon with a visible golden thrust.\n\nDamage: 5  ·  Cooldown: 0.8s"; status "Not learned yet — a quest will teach it."; Craft disabled |
| `test_station_refused_when_open` | bag open; `open_station(...)` | returns false; crafting closed |
| `test_quantity_buttons` | [berry 30] portable, select Brew Slime Tonic | +10 → "Amount: 10  ·  MAX 10"; +1 → 10; −10 → 1; −1 → 1; MAX → 10; quantity kept after close/reopen |
| `test_escape_and_menu_key` | open crafting via `open_bag()` + tab | Escape closes, tree unpaused, Shell pause menu not open; `menu` closes an open crafting tab |

`test_inventory.gd`:

| Test | Setup | Expected |
|---|---|---|
| `test_menu_key_opens_bag` | fresh level-1, 2 steps, tap `menu` | bag open; tree paused (`has_pause_reason(&"modal")`); the menu tabs visible with Bag disabled; tap `menu` → closed, unpaused |
| `test_menu_key_refused` | during a swing (`attack`, 2 steps) | `menu` does nothing; with the Shell pause menu open: nothing |
| `test_bag_model_new_run` | empty bag | 20 cells, all "Empty" disabled; name "Your bag is empty"; details "Pick things up in the world and they land here."; Use disabled; quantity and actions hidden |
| `test_bag_model_items` | [wood 25, hp-potion 3, stone-axe 1], belt [stone-axe,…], axe in hand | cell 0 "Wood" tag "×25"; cell 2 "Stone Axe" tag "in hand"; selected cell 0; status "Material · 25 in the bag" `#a9c4b4`; Use disabled; Drop enabled; select cell 2 → status "In your hand · belt slot 1" WARNING, primary "In your hand" disabled, assign rows "1: Stone Axe", "2: empty", "3: empty", "4: empty", assign index 0 |
| `test_use_potion` | HP 50, select hp-potion ×3, Use | HP 90; message "+40" green big at centre − (0, 30); Heal plays; count 2. At HP 100: HP 100, count 1, no message, no Heal (K10) |
| `test_berry_basket_and_energy` | HP 90, energy 50; berry basket | HP 100 ("+10"), energy 80, EnergyRestore plays; energy potion at 95 → 100, no EnergyRestore |
| `test_use_takes_first_stack` | [hp-potion 9, hp-potion 2] select slot 1, Use | [hp-potion 8, hp-potion 2] (K11) |
| `test_quantity_clamp` | wood 25 selected | +10, +10, +10 → 25; −10 → 15; −10, −10 → 1 |
| `test_destroy` | wood 25, quantity 5, Destroy | wood 20, quantity 5; Destroy all → slot gone, selection moves to slot 0 |
| `test_drop_destination_static` | `find_destination((640, 704), facing, {ts 64, 56×56}, all open)` | down (672, 832); right (800, 704); up (672, 576); left (544, 704); with (10, 12) blocked and facing down → the next sorted cell (11, 12) or (9, 12) per §6.5 order (side desc: left = (1, 0) → (11, 12)) → (736, 832) |
| `test_drop_from_bag` | level-1 at the spawn, face down, wood 25 selected, quantity 5, Drop | bag wood 20; bag closed; record `inventory-drop-1` `{item_id "wood", amount 5, object_id "collectible.wood-pile", visual_id "wood-pile"}` at `find_destination` with the world's `inspect`; a wood pile with `source_inventory_drop_id "inventory-drop-1"`, `quantity 5`; walking onto it → record erased, wood 25 |
| `test_drop_disabled_for_workbench` | [workbench 1] | Drop disabled, Destroy enabled, primary "Place" (C1: disabled until placement) |
| `test_pause_menu_inventory_action` | `Shell.set_action(&"inventory")` registered; open pause, press Inventory | pause closed, bag open |

`test_loadout.gd`:

| Test | Setup | Expected |
|---|---|---|
| `test_cycle_slot` | belt [stone-axe, null, stone-pickaxe, null], axe in hand | `cycle_slot(1) == 2`, `cycle_slot(-1) == 2`; with the pickaxe in hand `cycle_slot(1) == 0`; belt [null, stone-axe, null, null] and nothing in hand: `cycle_slot(1) == 1`, `cycle_slot(-1) == 1`; one weapon in hand: −1 |
| `test_wheel_switches` | as above, tap `weapon_next` | pickaxe in hand after ≤ 2 steps; message "Stone Pickaxe equipped" (yellow); EquipTool plays; the player still walks (hold `move_right` during the step: velocity unchanged) |
| `test_wheel_stepper` | `WheelStepper` | step(next, 50, 0) true; (next, 50, 100) false (lock); (next, 50, 200) false (the lock was extended to 250); (next, 50, 400) true; (next, 30, 1000) false, (next, 30, 1001) true; a direction change resets the sum |
| `test_assign_swap_and_replace_hand` | belt [stone-axe, stone-pickaxe, null, null], axe in hand; `assign_weapon(0, "stone-pickaxe")` | belt [stone-pickaxe, stone-axe, …]; `equip_assigned_weapon` false; hand still axe. Belt [stone-axe, null, null, null], axe in hand, stone-spear in the bag: `assign_weapon_slot("stone-spear", 0)` → belt [stone-spear, null, null, null], hand stone-spear, "Stone Spear equipped", EquipBlade |
| `test_empty_hand_assign_equips` | nothing in hand, stone-axe in the bag, assign to slot 2 | hand stone-axe |
| `test_hold_from_full_belt` | belt [a, b, c, d] (four owned weapons), b in hand, e in the bag; `equip_weapon_from_bag(e)` | belt [a, e, c, d]; hand e; b still in the bag |
| `test_busy_refusal` | mid-swing, hotbar click on another slot | message "Finish the attack first" (white, small, centre − (0, 42)); hand unchanged; hotbar selection back on the hand |
| `test_reconcile` | belt ["stone-axe", "stone-axe", "ghost", null], hand "iron-spear" (owned, off-belt) | belt [stone-axe, iron-spear, null, null]; hand iron-spear. Hand "ghost" (not owned) → hand = first owned belt weapon. Owned slam-hammer off-belt → placed at index 2 (K13) |
| `test_hotbar_model` | belt [stone-axe, null, null, null], hand axe | 4 cells; cell 0 icon + tooltip "Stone Axe", cells 1-3 "Empty" disabled; selected 0 |
| `test_harvest_advice` | sword in hand, stone-axe on the belt, hit `level-1-tree-004` | text "Requires an Axe: switch with the mouse wheel"; axe only in the bag → "Requires an Axe: put yours on the belt (E)"; none → "Requires an Axe" |
| `test_weapon_names` | — | `ItemCatalog.item_name("basic-sword") == "Basic sword"`, `("stone-axe") == "Stone Axe"`, `max_stack("iron-axe") == 1`; `ItemIcons.icon("stone-axe")` region (256, 0, 128, 128) |
| `test_travel_keeps_weapon` | stone-axe in hand, travel to slime-home | the new player's `PlayerCombat` holds stone-axe; belt unchanged |

Existing tests that call `PlayerCombat.equip("stone-axe")` directly keep working (the loadout only
drives `PlayerCombat`); `test_world_objects` harvest-message expectations change only where a
weapon that can harvest is owned.

### 11.10 Deferred [OUT]

Furniture placement and picking benches up (§3.1); quests (teaching recipes, `craft.completed`,
`workbench.opened`, `control.used`); control hints; the Gulp quick wheel; enemy loot drops; the
chest window (a separate Phase 3 window that joins `GameWindows`); journal and map windows (their
tabs stay disabled); narrow-screen CSS; drag-and-drop if time is short (the "Or put it on a belt
slot" list covers assignment); saves (`RunState` already holds every value).

### 11.11 Owner questions

| # | Question | Recommendation |
|---|---|---|
| C1 | Placement is not ported: what does crafting a Workbench do? | Keep it in the bag with "Crafted: Workbench", the crafting window stays open (status "Crafted 1 × Workbench"), the bag's Place button disabled; port placement next, since Chapter 1 depends on it |
| C2 | Quests are not ported: how are workbench recipes learned? | `RunState.debug_all_recipes_known` (launch option `recipes`) for play, `learn_recipes` in tests; parity rules unchanged |
| C3 | The trial sword (O5) vs Phaser's empty hand | Grant `basic-sword` into the bag and slot 1 at a new run while the trial lasts, so the belt, bag and hotbar show it; parity (no weapon) once quests and placement land |
| C4 | Fix K10 (potions at full HP) and K11 (first stack)? | Fix K10 in the port (refuse with "Already at full health"? needs a text decision); keep K11 |
| C5 | Keep K13 (slam hammer reconcile) and K4 (tabs lose the station)? | Drop K13 (arsenal logic is dead-code residue); keep K4 for parity |
| C6 | Add number keys for the belt? | No for parity (1-4 are abilities) |

Owner decisions (2026-10-05), as ported: **C1** superseded the same day by the furniture port
([furniture.md](./furniture.md)): crafting a Workbench closes the window and starts placement, and
the bag's "Place" is enabled. **C2** launch
option `recipes` (`?recipes` / `-- --recipes`) sets `debug_all_recipes_known`; tests use
`learn_recipes`. **C3** a new run gets the trial weapon (`basic-sword` or `?weapon=<id>`) in the
bag, on belt slot 1 and in hand (`RunState.trial_weapon_pending`, `InventoryActions.
grant_trial_weapon`); every world build reconciles the belt and mounts the hand. **C4** parity:
K10 and K11 kept. **C5** K13 dropped (`reconcile` only cleans the belt and the hand; `arsenal`
launch option grants the six ids into the bag and empty belt slots), K4 kept. **C6** no number
keys. Port notes: the windows are built in code (no `.tscn`); `BeltSlot` / `HotbarSlot` theme
variations do not exist yet, so the hotbar uses per-node StyleBoxes and the belt cells the
`SlotButton` look (no dashed border); drag and drop onto the belt is ported; arrow keys use
Godot's default focus navigation (no Home / End).

### 11.12 Docs to update with the port

- ARCHITECTURE.md: §1 tree (main's `InventoryActions`, `GameWindows` layer 40, the HUD hotbar);
  §2 RunState API (belt, recipes, transactions, drops); §7 bootstrap step 6 (`equip_run_weapon`)
  and the drop restore; §10 file map rows for every file of §11.2; §11 call map (crafting →
  RunState, PlayerCombat; interaction → GameWindows).
- CONVENTIONS.md: `generated/data/` gains `recipes.json`, `weapons.json`, `item-icons.json`,
  `npc-definitions.json`; "Scenes Godot owns" gains `ui.inventory-ui`, `ui.crafting-ui`,
  `ui.weapon-hotbar`, `ui.menu-tabs`; the `arsenal` / `recipes` launch options.
- interaction.md §3.6 / §8.6: the workbench opens the crafting window.
- world-objects.md §0 OUT list: bag drops, the inventory UI and the belt advice are done.
- GODOT_MIGRATION.md "Not yet": crafting, the bag and the belt move to done.
