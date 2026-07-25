# General visual animation system

## Status

- [x] Implemented

## Goal

Replace the player-only animation wiring with a reusable, editor-friendly visual-set system for players, enemies, and world objects.

The system must keep animation clips, source-frame visual offsets, and source-frame visual scales together so an artist or future editor can review the complete visual behavior in one place.

## Current limitations

- `WorldScene.makeAnimation()` always reads frames from the `slime` texture.
- `WorldScene.playAnimation()` always targets the player.
- Slime clips live in `src/game/slimeAnimations.ts`, while the player's scale and body alignment live elsewhere.
- Enemies use procedural static textures and do not register animation clips.
- Authored trees are created as `Image` objects, which cannot play Phaser animations.
- Applying frame-specific position or scale directly to a physics sprite risks moving or resizing its collision body.

## Proposed content structure

```text
src/game/content/visuals/
├── visual-set.schema.json
├── VisualCatalog.ts
├── player-slime/
│   └── visual-set.json
├── enemy-blob/
│   └── visual-set.json
└── tree-world/
    └── visual-set.json
```

Each visual-set JSON file owns:

- a stable `visualSetId`;
- the stable manifest `assetId`;
- default origin, scale, and source-frame offset;
- optional overrides for individual source frames;
- named clips with frame order, frame rate, and repeat behavior;
- stable runtime animation keys while existing callers are migrated.

Media paths and sheet dimensions remain in `asset/assets.json`. Collision bodies, hitboxes, stats, AI, and other gameplay semantics remain in their owning content or feature.

## Example format

```json
{
  "$schema": "../visual-set.schema.json",
  "visualSetId": "character.player.slime",
  "assetId": "character.player.slime",
  "defaults": {
    "origin": [0.5, 0.5],
    "scale": [0.28, 0.28],
    "sourceOffset": [0, 0]
  },
  "frameVisuals": {
    "0": {
      "sourceOffset": [0, 2],
      "scale": [0.28, 0.28]
    }
  },
  "clips": {
    "idle": {
      "runtimeKey": "slime-idle",
      "frames": [0, 1, 2, 1],
      "frameRate": 6,
      "repeat": -1
    }
  }
}
```

`sourceOffset` uses source-frame pixels. Runtime rendering multiplies it by the resolved frame scale. Frame values override visual-set defaults.

## Runtime ownership

An animated entity has two responsibilities:

```text
Stable physics anchor
├── world position and velocity
├── collision body
└── AnimatedVisual
    ├── render sprite
    ├── animation playback
    ├── source-frame offset
    ├── source-frame scale
    ├── origin
    ├── flip
    └── tint/effects
```

`AnimatedVisual` follows the physics anchor and applies resolved visual transforms to a separate render sprite. Frame changes must never move or resize the physics body.

## Player migration

- Move all clips from `src/game/slimeAnimations.ts` into `player-slime/visual-set.json`.
- Move player visual scale out of `PLAYER_CONFIG` and into the visual set.
- Keep player body dimensions and body offset in player gameplay content.
- Keep current runtime keys such as `slime-idle` and `slime-walk` during migration.
- Route player animation, flipping, tinting, and temporary ability scale effects through `AnimatedVisual`.
- Keep the physics anchor as the position used by combat, camera, collision, minimap, and persistence.

## Enemy example

- Give the procedural blob texture a stable manifest asset ID.
- Add `enemy-blob/visual-set.json`.
- Register and play a looping one-frame `enemy-blob-idle` clip.
- The one-frame clip proves the generic path without pretending that static artwork contains multiple animation frames.

## Tree example

- Add a tree visual set referencing the existing stable tree-sheet asset ID.
- Configure one authored tree visual to use a looping one-frame clip.
- `ObjectFactory` creates an animated render sprite only for visuals that opt into a visual set.
- Static collision remains attached to the authored object anchor.
- Rocks, walls, houses, and non-animated trees remain regular images.

## Future editor direction

The map editor may later gain a visual-set editor that can:

- create and edit visual-set JSON files;
- select a manifest asset and preview its frames;
- adjust default and per-frame origin, offset, and scale;
- create clips and preview frame timing;
- validate missing assets, invalid frame indices, and duplicate runtime keys.

Authored maps should reference stable visual or object IDs. They should not embed copies of global animation definitions.

## Validation and errors

- Reject unknown manifest asset IDs.
- Treat frame `0` as the base frame for image and procedural assets; validate numbered source frames against spritesheet bounds.
- Reject frame indices outside the declared sheet bounds.
- Reject duplicate visual-set IDs and runtime animation keys.
- Reject zero or negative scale values and frame rates.
- Reject malformed offsets, origins, and repeat values.
- Fail during boot or content validation with the visual-set ID and exact invalid field.

## Decisions made during implementation

- Physics anchors use stable world-unit geometry; source-art dimensions do not leak into collision configuration.
- Transform composition is defaults, then per-frame overrides, then temporary runtime effects. Horizontal source offsets mirror with facing.
- Player visual playback, facing, tint, alpha, and ability scale effects all target `AnimatedVisual`; camera, combat, persistence, and movement continue to target the anchor.
- Enemy health labels, hit flashes, telegraphs, and death effects use rendered visual bounds or effects when a visual set is configured.
- `AnimatedVisual` owns its animation listeners, tweens, render sprite, and scene/anchor cleanup.
- The map editor keeps animated visuals disabled until it has a dedicated visual-set preview and persistence workflow.
- Maps and object definitions reference stable `visualSetId` and clip IDs rather than embedding clip definitions.

## Acceptance criteria

- No player animation registration hardcodes the `slime` texture key in `WorldScene`.
- Player clips and frame visual transforms are loaded from JSON.
- Per-frame player visual offset and scale do not alter the player collision body.
- A blob enemy plays a registered one-frame animation through the same runtime.
- One authored tree plays a registered one-frame animation through the same runtime.
- Non-animated objects stay on the existing lightweight image path.
- The schema and catalog are suitable for a future visual-set editor.
- Asset, object, map, type, build, and browser smoke checks pass.
