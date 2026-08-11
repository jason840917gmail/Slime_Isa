# Keyframe Hold Control Targeting

## Problem

The shared timeline renders hold-length controls inside every keyframe tile, but click handling currently changes the selected keyframe. Clicking the decrease or increase control on an unselected tile therefore edits a different tile than the one containing the control.

## Approved behavior

Each hold control targets its containing keyframe directly. Clicking decrease or increase changes that tile's hold length without depending on or changing the current timeline selection.

## Design

- The shared hold-control renderer receives the keyframe index and writes it to the control as data.
- Each studio's delegated click handler reads the index from the clicked control and returns immediately after resizing, so the containing tile's selection handler does not run.
- Character Studio passes that index to document state, which resizes the requested keyframe without changing `selectedTimelineIndex`.
- Weapon Studio passes that index to its animation mutation helper, which resizes the requested keyframe without changing `selectedAnimationPositions`.
- Existing minimum-hold, mirrored-direction lock, timing-shift, duration, and selection behavior remain unchanged.

Inferring the index from current selection is rejected because it caused the bug. Selecting the clicked tile before resizing is also rejected because the control should not have the unrelated side effect of changing selection.

## Verification

- Add Character Studio interaction regressions for decrease and increase on an unselected keyframe. Each test must prove the clicked tile changes, the selected tile does not change, and selection remains unchanged.
- Add equivalent Weapon Studio interaction regressions for decrease and increase.
- Run `pnpm typecheck`.
- Run `pnpm exec tsc --noEmit -p tsconfig.node.json`.
- Run `pnpm build`.
- Run `node scripts/check-characters.mjs` and `node scripts/check-weapons.mjs`.
- Run `node --test scripts/tests/character-studio/*.test.mjs scripts/tests/weapon-studio/*.test.mjs`.
