# Keyframe Hold Control Targeting

## Problem

The shared timeline renders hold-length controls inside every keyframe tile, but click handling currently changes the selected keyframe. Clicking `−` or `+` on an unselected tile therefore edits a different tile than the one containing the control.

## Approved behavior

Each hold control targets its containing keyframe directly. Clicking `−` or `+` changes that tile's hold length without depending on or changing the current timeline selection.

## Design

- The shared hold-control renderer receives the keyframe index and writes it to the control as data.
- Character Studio passes that index to document state, which resizes the requested keyframe.
- Weapon Studio passes that index to its animation mutation helper, which resizes the requested keyframe.
- Existing minimum-hold, mirrored-direction lock, timing-shift, duration, and selection behavior remain unchanged.

Inferring the index from current selection is rejected because it caused the bug. Selecting the clicked tile before resizing is also rejected because the control should not have the unrelated side effect of changing selection.

## Verification

- Add a regression test proving an unselected keyframe can be resized by index while selection remains unchanged.
- Run both strict TypeScript checks, the production build, character and weapon validators, and existing Character Studio tests.
