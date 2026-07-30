# Asset Sheet And Size Guide

This is the overview document for the asset size contract used by the game.

If you are adding new art, start here, then continue with the focused guide for the asset type you are working on.

## Asset Guides

- [Slime Sheet Guide](./slime-sheet-guide.md)
- [Terrain And Tile Guide](./terrain-tile-guide.md)
- [Friends And Houses Guide](./friends-and-houses-guide.md)

## Shared Safe Defaults

- Animated slime-style sheet: `256 x 256 px` frames on an `8 x 8` grid
- Terrain tile: `64 x 64 px`
- Friend face or accessory part: `24 x 24 px`
- House texture: `128 x 128 px`
- Small prop: around `16 x 16 px` to `48 x 20 px`

## When New Art Works Without Code Changes

New art should fit the current game immediately if it follows these rules:

- Slime or animated hero sheets keep the same `8 x 8` layout and `256 x 256 px` frame size.
- Terrain art stays on the `64 x 64 px` world tile grid.
- Friend parts stay on the `24 x 24 px` canvas with shared center alignment.
- Houses keep the entrance near the bottom-center and stay close to `128 x 128 px`.

## When Code Must Change

Update the code if any of these change:

- Slime frame size
- Slime sheet grid layout
- Terrain tile size
- Friend part size
- House art size or doorway placement
- Collision footprint for obstacle tiles

Main code locations:

- `asset/assets.json`
- `src/game/infrastructure/assets/ProceduralAssetScene.ts`
- `src/game/scenes/WorldScene.ts`
- `src/game/content/terrain/TileCatalog.ts`
- `src/game/content/objects/`
- `src/game/Friend.ts`
- `src/game/House.ts`
