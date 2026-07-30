# Slime Sheet Guide

This guide defines the exact format for the player slime sheet and any future animated character sheet that wants to reuse the same animation system.

## Required Sheet Format

- Runtime sheet key: `slime`
- Loaded from: `asset/slime_normalized.png`
- Full sheet size: `2048 x 2048 px`
- Grid layout: `8 columns x 8 rows`
- Frame size: `256 x 256 px`
- Index rule: `frame = row * 8 + column`
- Default art facing: left
- Runtime display scale: `0.28`

## Runtime Measurements

- Physics body size: `108 x 80`
- Physics body offset: `74, 140`

These values mean the visible slime should stay grounded in the lower-middle of each frame. If the character shifts too far up, down, or sideways inside the frame, the collision body will stop matching the art.

## Frame Placement Rules

- Use a uniform grid only.
- Keep every frame inside its own `256 x 256` cell.
- Keep the slime bottom-aligned across frames.
- Keep the body visually centered.
- Use transparent padding instead of changing frame size.
- Keep squash and stretch poses inside the same frame bounds.

## Animation Row Layout

Current row usage:

- Row 0: idle and expressions
- Row 1: walk or scoot
- Row 2: hop
- Row 3: squash or landing
- Row 4: stretch
- Row 5: roll or boost
- Row 6: trick or attack
- Row 7: special actions

If you change this layout, update `src/game/slimeAnimations.ts` to match the new frame map.

## Orientation Rules

- Draw the source art facing left.
- The game flips the sprite horizontally for right movement.
- If the source art faces right, movement direction will look wrong until code is updated.

## Authoring Tips

- Keep a shared baseline guide visible while animating.
- Keep the widest and tallest poses inside the same `256 x 256` frame.
- Test idle, walk, and special frames together before exporting the full sheet.
- Avoid frame-to-frame anchor drift in the feet or lower body.

## Safe Template

Use this template if you want the sheet to work immediately:

- Canvas: `2048 x 2048 px`
- Grid: `8 x 8`
- Cell size: `256 x 256 px`
- Character anchor: bottom-centered in each cell