# Keyframe Control and Preview Targeting

## Problem

The shared timeline renders hold-length controls inside every keyframe tile, but click handling currently changes the selected keyframe. Clicking the decrease or increase control on an unselected tile therefore edits a different tile than the one containing the control.

Weapon Studio also assigns the selected keyframe's ordinal index directly to the preview playhead. Once keyframes have different hold lengths, that index no longer equals the keyframe's authored timeline start, so selection and preview become out of phase.

## Approved behavior

Each hold control targets its containing keyframe directly. Clicking decrease or increase changes that tile's hold length without depending on or changing the current timeline selection.

Selecting a Weapon Studio keyframe moves the preview playhead to that keyframe's authored `keyframeTimes[index]` start. The preview therefore shows the selected source tile and its transform immediately, then playback continues from the same timeline position.

## Design

- The shared hold-control renderer receives the keyframe index and writes it to the control as data.
- Each studio's delegated click handler reads the index from the clicked control and returns immediately after resizing, so the containing tile's selection handler does not run.
- Character Studio passes that index to document state, which resizes the requested keyframe without changing `selectedTimelineIndex`.
- Weapon Studio passes that index to its animation mutation helper, which resizes the requested keyframe without changing `selectedAnimationPositions`.
- Weapon Studio keeps keyframe selection and timeline playback position as separate concepts. Its selection handler stores the clicked keyframe index in `selectedAnimationPositions` and stores the corresponding authored start in `previewStep`.
- Existing minimum-hold, mirrored-direction lock, timing-shift, duration, and selection behavior remain unchanged.

Inferring the index from current selection is rejected because it caused the bug. Selecting the clicked tile before resizing is also rejected because the control should not have the unrelated side effect of changing selection.

## Verification

- Add Character Studio interaction regressions for decrease and increase on an unselected keyframe. Each test must prove the clicked tile changes, the selected tile does not change, and selection remains unchanged.
- Add equivalent Weapon Studio interaction regressions for decrease and increase.
- Add a Weapon Studio regression with uneven keyframe holds proving that selecting a later keyframe sets `previewStep` to its authored timeline start and renders that keyframe's source tile and transform.
- Run `pnpm typecheck`.
- Run `pnpm exec tsc --noEmit -p tsconfig.node.json`.
- Run `pnpm build`.
- Run `node scripts/check-characters.mjs` and `node scripts/check-weapons.mjs`.
- Run `node --test scripts/tests/character-studio/*.test.mjs scripts/tests/weapon-studio/*.test.mjs`.
