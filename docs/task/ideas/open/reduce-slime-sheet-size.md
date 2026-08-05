# Reduce slime sheet size

## Status

Open — optimization candidate. The current player sheet uses 256 × 256 source
frames, so this should be measured before changing source art or runtime scale.

## Goal

Reduce memory and texture-upload cost by authoring or preprocessing the player
slime at a smaller source frame size while preserving the current in-game
appearance and animation readability.

## Proposed approach

1. Produce a 64 × 64 frame test sheet with the same 8 × 8 animation layout.
2. Compare silhouette quality, edge readability, collider alignment, and UI
   previews at the game's actual zoom levels.
3. Register the candidate as a separate asset ID so the current sheet remains a
   rollback option.
4. Run asset validation, Character Studio previews, gameplay smoke checks, and
   a production build before switching the source of truth.
5. Remove the larger source only after the smaller sheet passes visual review.

## Constraints

- Do not change world tile size or physics coordinates as part of this asset
  optimization.
- Keep frame count, animation IDs, anchors, offsets, and collider dimensions
  stable.
- Do not accept a smaller sheet that introduces visible shimmer or changes the
  player's perceived collision footprint.

## Acceptance criteria

- The smaller sheet produces no visible gameplay regression at default zoom.
- Asset validation confirms dimensions, frame counts, and paths.
- Character Studio and map previews use the same registered source.
- Measured memory or load-time improvement justifies the migration.
