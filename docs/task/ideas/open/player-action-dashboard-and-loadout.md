# Player action dashboard and loadout assignment

## Status

Open — the runtime already has a six-slot weapon/tool belt and a separate
four-slot ability bar. This task consolidates their presentation and completes
loadout assignment without creating another equipment state model.

## Goal

Create one responsive bottom command dashboard, inspired by action RPGs, that
lets the player read weapons, tools, abilities, hotkeys, cooldowns, locks, and
the active selection at a glance.

## Decisions

- The dashboard is one visual component with two clearly separated groups:
  six assignable weapon/tool slots and fixed ability slots.
- `playerWeaponLoadout` remains the only authority for weapon ownership,
  assignment, and the equipped weapon. The dashboard never stores a second
  loadout.
- Desktop inventory supports dragging an owned weapon onto slots `1`–`6`.
- Every owned weapon also exposes an accessible **Equip to slot** control with
  slots `1`–`6`. Drag/drop and the control call the same assignment command.
- Dropping onto an occupied slot swaps assignments, matching the existing
  loadout behavior. Duplicate weapon assignments are not allowed.
- Abilities keep their existing hotkeys and unlock rules in the first version;
  ability remapping is a separate future feature.
- The dashboard responds to viewport width: one row when space allows, compact
  grouped rows on narrow screens, and no overlap with the minimap or modal UI.

## Implementation slices

1. Extract a shared slot-frame visual for selected, ready, cooling down, locked,
   unavailable, and empty states.
2. Compose the current weapon belt and ability bar into one responsive dashboard.
3. Add one loadout-assignment command used by inventory controls and drag/drop.
4. Add pointer, keyboard, and focus feedback; cancellation must leave the
   original assignment unchanged.
5. Verify save/load, weapon ownership changes, resize, and all six hotkeys.

## Acceptance criteria

- Weapons and abilities appear in one bottom dashboard without losing their
  distinct rules.
- A weapon can be assigned by drag/drop or **Equip to slot 1–6**, and both paths
  produce identical saved state.
- Reassigning or swapping never duplicates or loses a weapon.
- Active weapon, cooldown, locked level, unavailable ownership, and hotkey are
  visually distinguishable.
- The dashboard remains usable on narrow, standard, and ultrawide viewports.

