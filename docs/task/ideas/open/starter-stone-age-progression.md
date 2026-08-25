# Starter stone-age progression

## Status

Open — wood and stone gathering exist, but starter weapons and tools are still
automatically granted for testing. This task turns those pieces into the first
intentional progression level.

Implementation is sequenced in the
[Stone and Starter Tools implementation plan](../../../superpowers/plans/2026-08-23-stone-and-starter-tools-implementation-plan.md).

## Goal

Start the player without crafted weapons or tools, teach safe collection and
basic crafting, then use a guarded green key to unlock the next authored area.

## Progression contract

1. The player begins with innate slime movement/actions but no equippable
   crafted weapon or harvesting tool.
2. Loose branches, loose stones, and edible forage can be collected by hand.
   Trees and stone nodes still require the correct crafted tool.
3. Basic survival recipes are portable and use the shared crafting popup. The
   home Workbench remains the later station for improved tools, repairs,
   storage, and building pieces.
4. The player crafts tools, gathers efficiently, then crafts a spear.
5. A small authored enemy camp guards a reward chest. The chest opens after the
   encounter and awards one persistent green key.
6. The green key unlocks the exit to the next authored region. The save records
   the unlocked gate so the key and chest cannot be duplicated after reload.

## First recipe set

| Recipe | Cost | Purpose |
|---|---:|---|
| Wooden Spear | 20 wood | First crafted combat weapon |
| Stone Axe | 10 wood + 10 stone | Efficient tree harvesting |
| Stone Pickaxe | 10 wood + 10 stone | Stone and early ore harvesting |
| Stone Spear | 20 wood + 20 stone | Stronger weapon for the guarded chest encounter |

The earlier “wood axe: 10 wood + 10 stone” note is normalized to **Stone Axe**;
otherwise its name and material requirement contradict each other.

## Safe migration from the test loadout

Do not remove automatic starter grants until loose wood/stone sources, recipe
availability, inventory capacity, and recovery from spending mistakes are all
verified. During development, a clearly labeled debug grant may remain outside
normal new-save progression.

## Acceptance criteria

- A fresh save cannot softlock before crafting its first tool.
- Starter tools and weapons come from recipes, not normal automatic grants.
- Tree and stone gates provide clear insufficient-tool feedback.
- The guarded chest rewards the green key exactly once.
- The next-area gate remains unlocked after reload and area transitions.
- The complete collect → craft → gather → fight → key → exit loop works without
  debug commands.
