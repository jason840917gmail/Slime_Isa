# Smooth Ground Sheet Rendering

00:35 - kimi

## User report

`ground-sheet-region` produces visible cuts. It picks a small seeded 6-12 cell rectangle and reflects frame indices inside it. The source sheets are already authored as one smooth 19x19 image, so reducing them to a small mirrored patch loses their intended order. More importantly, reversing frame order without flipping each frame does not match pixel edges: frame 18 followed by frame 17 still joins frame 18's right edge to frame 17's left edge, not their shared source edge.

## Implemented strategy: `sheet-order`

- First 19x19 map block uses the source exactly as authored: `(x, y) -> frame y * 19 + x` (frames 0..360 in row/column order).
- Repeated blocks are true mirrored copies of the complete sheet. Both frame order **and sprite pixels** flip horizontally/vertically. At the horizontal repeat, original frame 18 touches an X-flipped frame 18, so both touching edges are the original frame's right edge. Vertical repeats use the same rule with Y flips; corners flip both axes.
- No seeded sub-region or arbitrary offset: offsetting would move the inevitable wrap into an arbitrary visible location and stop reproducing the authored sheet.
- `TileFactory` now applies the resolved `flipX`/`flipY` to the Phaser image. Its cache key includes asset + strategy.
- Switched all smooth 19x19 sheet terrain to `sheet-order`: Highland grass A/B (and legacy rock-wall visual), Amberleaf, and Frozen ground. Kept `ground-sheet-region` available as a legacy strategy for content that intentionally wants a small repeated patch.

## Verification

- Focused Node assertions imported the TypeScript function directly: every cell in the first 19x19 block maps to exact row-major frame order; boundary cells resolve to frame 18/342/360 with the required X/Y/both flips.
- Full `pnpm check` passes: 25 assets, 9 object files, 5 maps, strict TypeScript, production build.

## Questions for Codex

1. Agree that `sheet-order` should mean full-sheet mirrored-repeat (actual pixel flips), rather than direct modulo wrap? Direct wrap preserves order but creates a hard edge at columns/rows 18 -> 0.
2. Keep legacy `ground-sheet-region`, or remove it once browser comparison confirms `sheet-order` on Highland/Amberleaf/Frozen?
3. `rock-wall` currently shares Highland visual + static inset; flip changes pixels only, not its symmetric body. Since authored obstacle rocks are objects now, should the legacy tile be deprecated instead of participating in this strategy?

00:52 - kimi

## Noisy feather transitions implemented

The coordinator approved generic noisy feathering where different ground materials touch. Implementation keeps map JSON unchanged:

- `TileCatalog.transition` now owns visual-only metadata: group, material, priority, edge width, style.
- Participating natural ground: Highland, Forest Floor/Moss, Cavern/Crystal Floor, Amberleaf, Frozen. Water and solid walls intentionally opt out. Grass A/B share material `highland`, so their logical ID difference does not create a false edge.
- New `TerrainTransitionRenderer` runs after base tiles in both `MapBuilder` and `MapEditorScene` (WYSIWYG). It scans east/south boundaries once, chooses a stable winning material (priority then tile ID), and overlays it into the adjacent cell through three deterministic jagged geometry-mask bands (wide/faint, medium, narrow/strong).
- Noise uses map seed + tile coordinate + edge + band + sample; no random runtime drift and no transition data persisted in maps.
- `TileFactory.createOverlay` resolves the neighbor material at the target world coordinate, including `sheet-order` frame and flip, so transition pixels align with the material's normal global rendering.
- Transition layers explicitly own/destroy images, masks, and off-list mask graphics; editor rebuilds them on document revisions, runtime cleans them on scene shutdown.

Documentation: `docs/TERRAIN_TRANSITIONS.md` describes ownership, current limitations, and alternatives (edge decorations, authored Wang/autotiles, shader/splat blending, manual transition tiles) with recommended adoption order.

Verification: full `pnpm check` green (25 assets, 9 object files, 5 maps, strict TS, production build). Browser visual/performance smoke test still needed. Please review geometry-mask object count and whether priority values should become pair-specific before we expand beyond current map sizes.
