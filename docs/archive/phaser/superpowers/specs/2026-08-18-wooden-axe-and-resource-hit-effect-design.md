# Wooden Axe and Resource Hit Effect Design

**Status: approved design; implementation pending asset generation.**

## Goal

Add a readable wooden gathering axe and a separate resource-impact effect for
the Wood Gathering milestone. The axe is a tool, not a combat weapon: it is
visual equipment used for chopping and does not own or parent the hit effect.

## Asset contract

- Generate two transparent-background PNG sprite sheets in the established
  polished, non-pixel-art game style.
- Use square 128x128 cells for both sheets. This is an intentional convention
  for these new tool/resource assets; existing weapon sheets use 120x120 or
  126x126 cells.
- Save the axe sheet at
  `asset/MAPS/weapons/128x128-tile_3x1-wooden-axe.png` and register it as
  `weapon.player.wooden-axe-tiles` with texture key
  `weapon-player-wooden-axe-tiles`, frame size 128x128, 3 columns, 1 row,
  expected image dimensions 384x128, origin `[0.5, 0.5]`, `pixelArt: false`,
  tags `weapon`, `tool`, `animated`, and `status: "ready"`. Add it to the
  `boot` bundle.
- Axe frame semantics are fixed: frame 0 is down-facing, frame 1 is the
  right-facing side pose, and frame 2 is up-facing. The runtime may mirror
  frame 1 for the left-facing side.
- Save the independent impact sheet at
  `asset/MAPS/weapons/128x128-tile_4x1-resource-impact.png` and register it as
  `effect.resource.impact-tiles` with texture key
  `effect-resource-impact-tiles`, frame size 128x128, 4 columns, 1 row,
  expected image dimensions 512x128, origin `[0.5, 0.5]`, `pixelArt: false`,
  tags `effect`, `resource`, `animated`, and `status: "ready"`. Add it to the
  `boot` bundle.
- Impact frames 0 through 3 are chronological animation frames. The effect is
  nondirectional and should eventually resolve through an effect definition’s
  `default` variant rather than requiring directional variants.
- Each axe frame is a single clean wooden hatchet pose with a dark wood handle
  and metal cutting head. Each impact frame shows a brief, restrained burst
  with wood chips/sparks; it must not contain the axe, a character, or a
  background.
- The filenames intentionally include cell dimensions and grid layout.

## Runtime intent

- The axe frames are available as directional tool visuals for the player’s
  equipped-tool layer.
- The hit effect is spawned independently at the resource collision/hit
  position and follows the existing transient-effect lifecycle. It is never
  attached to the axe sprite.
- This request creates the art assets and manifest-ready metadata only; tool
  gameplay, chopping animation timing, and resource damage balancing remain
  separate implementation work.

## Acceptance checks

1. Both PNGs have real alpha transparency and dimensions divisible into the
   declared 128x128 cells.
2. The axe sheet contains exactly three direction frames in a single row.
3. The impact sheet contains exactly four independent impact frames in a single
   row.
4. No frame includes a background, text, watermark, character, or battle-axe
   embellishment.
5. The exact manifest entries above are present and `pnpm assets:check` accepts
   both files without special casing.
