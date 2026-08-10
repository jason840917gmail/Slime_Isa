# Weapon Inventory and Five-Slot Loadout

## Status

Approved and implemented on 2026-08-08.

## Outcome

Weapons are unique inventory items rather than an unrestricted global default. The player has five persistent field-tool slots, selects them with number keys 1–5, and can only equip a slot when its weapon item is owned. The initial test loadout is:

1. Goo Gauntlet — starter/basic attack.
2. Basic Sword — authored sword animation package.
3. Empty.
4. Empty.
5. Empty.

Slam Hammer remains a valid weapon definition for future acquisition, but it is not granted or assigned by default because it does not yet have authored weapon visuals.

The data model also accepts equipment items categorized as tools when they resolve to a weapon definition, allowing future axes, mining tools, or utility implements to use the same bar.

## Ownership and assignment

- Every reusable weapon definition is registered in the item registry as a unique, non-stacking equipment item.
- Inventory count is the authority: an unowned weapon cannot be assigned or equipped even if an old save references its ID.
- Inventory details expose five numbered assignment buttons and an Equip Now action.
- Assigning a weapon already on the bar swaps the two slots. A newly acquired sixth weapon must replace one of the five assignments.
- Equipment items cannot be deleted through the current inventory UI, guaranteeing that the starter/basic attack remains available.

## Runtime switching

`WeaponLoadout` validates the requested slot and ownership. `WorldScene` asks `CombatController` to replace the current `Weapon` and `WeaponVisual`; only after successful replacement does the persistent equipped ID change. Switching is rejected during an active attack so attack timers, hitboxes, and animation locks cannot be split across two weapons.

The replacement path destroys the old weapon runner and visual, creates the selected normalized weapon definition, starts its idle presentation, and leaves enemy/combo ownership in the existing combat controller.

## Input and interface

- Plain 1–5: equip owned hotbar slots.
- Shift+1–Shift+8: development cheats, moved to avoid gameplay conflicts.
- Tab: inventory; weapon details can assign slots or equip immediately.
- The bottom-center field-tool belt sits above the ability bar. Amber double borders identify the active weapon, mint borders identify available assignments, and empty slots remain visibly numbered.

## Persistence and migration

Save envelope version 3 persists `equipment.weaponId` and `equipment.weaponSlots`. Older saves receive the five-slot starter defaults, then reconcile against actual inventory ownership. Area-transition handoff already serializes the complete player state and inventory, so equipped weapon and assignments survive map changes.

## Verification

- Content validation must accept all starter weapon definitions.
- TypeScript must validate inventory categories, loadout events, save fields, UI callbacks, and combat replacement.
- Live testing must confirm keys 1 and 2 switch Goo Gauntlet and Basic Sword; slots 3–5 remain unavailable until inventory-owned weapons are assigned; inventory assignment changes the numbered bar; and attacks use the newly selected definition.
