# Visual-set editor

## Status

- [x] Implemented in Character Studio

## Goal

Character Studio creates and edits `visual-set.json` files without placing
animation data inside map files.

## Implemented workflow

1. Select a stable asset from `asset/assets.json`.
2. Create or open a visual set.
3. Preview source frames and named clips.
4. Edit default and per-frame origin, source offset, and scale.
5. Edit frame order, frame rate, and repeat behavior.
6. Validate with the same schema and catalog rules used by the game.
7. Save the visual-set JSON beside related visual definitions.
8. Avility to see the animations in action.

Maps continue to reference stable object or archetype IDs. Object definitions reference `visualSetId` and clip IDs, so changing animation artwork does not rewrite authored maps.

## Guardrails

- Show the physics anchor while previewing offsets.
- Distinguish source-art pixels from world units.
- Reject duplicate runtime keys and invalid frame indices before saving.
- Preserve unknown fields when opening files from a newer format version.
- Use atomic writes and expose validation errors with the exact JSON field.
