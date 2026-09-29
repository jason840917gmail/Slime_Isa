# Houses And World Props Guide

Art rules for buildings and reusable world props. Every persistent house, prop,
NPC, and interaction object is an instance authored in a world scene; runtime
code must not add hidden map populations.

## House art

- House frames are `320 x 320 px` (`sheet.houses.3x1`,
  `sheet.houses.mushroom.2x1` in `asset/MAPS/Houses/`), bottom-centre anchored.
- Keep the whole silhouette inside the frame with a small transparent margin.
- Put the doorway near the bottom centre, and check the art against the
  `64 x 64 px` tile grid before exporting.
- Mushroom house sources in `asset/Originals/houses/` are packed with
  `python scripts/houses/normalize-mushroom-houses.py`.

Each house is an object scene (`object.house-*`, files
`scenes/authored/objects/house-world-solid*.scene.json`) with a `StaticBody2D`
footprint and a world-sorted `Sprite2D` whose `occlusionBounds` and
`depthBounds` are set to the roof and the base.

The doorway is not part of the house scene. Author a `game.door` script node in
the world scene next to the house; it names its `targetAreaId` and
`targetDoorId`, and the player arrives at the target door's `arrival` child.
Walk-in area exits are `game.world-exit` nodes, and locked barriers are
`game.gate` object scenes (e.g. `object.gate-verdant`).

## World prop rules

- Keep props visually compatible with the surrounding tile and building scale.
- Register the sheet in `asset/assets.json`, build one object scene per
  distinct visual/footprint, and place instances in the world scene
  ([Adding Game Assets](./adding-assets.md)).
- Walk-over decorations use a `Node2D` root with no body and `depthBand`
  `ground-decals`; solid props use a `StaticBody2D` with a footprint sized to
  the base of the art, not the whole sprite.
- Keep temporary combat and feedback effects in their owning effect scene.

Run `pnpm assets:check` and `pnpm scenes:check` after adding or moving world
content.
