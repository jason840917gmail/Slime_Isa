# Station-Aware Crafting Design (roadmap 6.2)

## Status

Short design for roadmap task 6.2, written before the code as the task asks.
Scope: one recipe authority and one crafting popup that know which station the
player is at and how far it is upgraded. The Workshop itself (6.3), its
restoration (6.1 variants) and its upgrade (8.6) build on this.

## Today

- `RecipeDef.context` is one of `portable`, `workbench`, `forge`, `kitchen`,
  `alchemy`. Only `portable` (the C key) and `workbench` (the placeable
  workbench, `game.workbench` with `recipeContext: "workbench"`) are reachable;
  `alchemy` holds two recipes no station opens, and no scene uses `forge` or
  `kitchen`.
- `WorldScene.openCraftingStation(context)` hands the popup
  `recipesFor(context)`; the popup never knows which station it is showing.
- `CraftingService.craft(recipe, quantity)` checks learning, unique output,
  materials and space, then applies one atomic inventory transaction. It does
  not check the station: any caller could craft any recipe.
- `RecipeDef.tier` exists but nothing supplies a station tier.

## Model

```ts
type CraftingStation = 'portable' | 'workbench' | 'workshop' | 'forge' | 'kitchen';

interface CraftingSite {
  readonly station: CraftingStation;
  readonly tier: number;          // 1 for portable and the workbench
}
```

- `RecipeDef.context` becomes `RecipeDef.station` (same values minus
  `alchemy`, plus `workshop`). `brew-fizzy` and `weave-tonics` move to
  `kitchen`; no Kitchen exists in Release 1, so they are never listed.
- A station also crafts the recipes of the stations it includes:
  `workshop` includes `workbench` ("the Workshop crafts everything the
  workbench does"). Nothing else includes anything; portable recipes stay on
  C and are not repeated at stations.
- The station's tier is authored on its `game.workbench` script
  (`recipeContext` renamed `station`, plus `tier`, default 1). A restored and an
  upgraded Workshop are different variants of the same building (6.1), so the
  upgrade swaps in a station node with `tier: 2`; no extra saved state.

## Listing and locks

`recipesAt(site)` returns every recipe whose station is the site's station or
one it includes, at any tier, sorted by tier, then the station's own recipes
before shared ones, then catalog order. After them come the tier-1 recipes of
stations that build on the site (a workbench lists the Workshop's), shown
locked as `wrong-station` so the player learns where to go (added with 6.4,
2026-09-30). Each row
carries one status, and the popup explains every lock in plain words:

| Status | Shown as | Detail line |
|---|---|---|
| `ready` | Ready to craft | — |
| `station-tier` | Locked | Needs a tier N Workshop. |
| `not-learned` | Locked | Not learned yet — a quest will teach it. |
| `unique-owned` | Owned | You already have this item. |
| `missing-materials` | Materials needed | More materials are needed. |
| `inventory-full` | Ready to craft | Make room in your inventory first. |
| `wrong-station` | Locked: "At the Workshop" (workbench only) | Craft this at the Workshop. |

Order of checks: station, tier, learned, unique, materials, space, so the most
fundamental reason wins. The popup title names the site: "Crafting" (C),
"Workbench", "Workshop" / "Workshop · Tier 2".

## Validation

`CraftingService.quote(recipe, quantity, site)` and `craft(recipe, quantity,
site)` take the site. `craft` re-quotes and refuses anything but `ready`
before touching the inventory; the inventory transaction stays atomic, so a
failed craft never consumes materials. `wrong-station` and `station-tier` are
refused in the service, not only hidden by the popup.

## Tests

- A recipe crafted at the wrong station fails with `wrong-station` and leaves
  the inventory unchanged; the same recipe at its station succeeds.
- A tier-2 recipe at a tier-1 station is listed as `station-tier` and cannot
  be crafted; at tier 2 it can.
- The Workshop lists its own recipes, then the workbench recipes; the
  workbench lists the Workshop's tier-1 recipes last, locked; C lists only
  portable recipes; kitchen recipes are listed nowhere.
- Every failure reason leaves the inventory byte-for-byte unchanged.

## Out of scope

The Workshop building, its restoration quest and recipes (6.3, 6.4), the
Forge (8.5), and the Kitchen (after Release 1).
