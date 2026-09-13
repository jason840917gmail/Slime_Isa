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

1. The player begins with movement and non-combat interactions, but no attack,
   equipped weapon, crafted weapon, or harvesting tool.
2. Loose branches, loose stones, and edible forage can be collected by hand.
   Trees and stone nodes still require the correct crafted tool.
3. Basic survival recipes are portable and use the shared crafting popup. The
   home Workbench remains the later station for improved tools, repairs,
   storage, and building pieces.
4. The player crafts tools, gathers efficiently, then crafts a spear.
5. The ordinary worm camp keeps its refill behavior. A separate authored boss
   camp contains Fatty One Eye and a guarded chest. Only Wooden or Stone Spear
   strikes that reach Fatty's exact-center eye deal damage. Body collision
   triggers a stationary 300 ms contact hop whose single 64 px landing hit can
   be dodged or escaped; collision itself deals no damage. The chest unlocks on
   defeat and opens an inventory-style panel containing one green key; partial
   loot remains in the chest.
6. Fatty's camp uses an authored three-minute wall-clock respawn. If the chest
   is not empty when Fatty respawns, it relocks; once emptied, it remains visibly
   open. The green key unlocks the exit to the next authored region, is consumed
   only once, and the permanent gate state survives reload.

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
- The guarded chest exposes the green key exactly once without duplicating
  partial transfers or reloads.
- Map Studio keeps Fatty visible and can independently edit both circular camp
  radii, optional chest ownership, and the complete camp save/reload record.
- The next-area gate remains unlocked after reload and area transitions.
- The complete collect → craft → gather → fight → chest → key → exit loop works
  without debug commands.
