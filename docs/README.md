# Documentation

This folder contains the asset and implementation notes for the game.

## Asset Docs

- [Asset Sheet Overview](./asset-sheet-spec.md)
- [Slime Sheet Guide](./slime-sheet-guide.md)
- [Terrain And Tile Guide](./terrain-tile-guide.md)
- [Friends And Houses Guide](./friends-and-houses-guide.md)

## Recommended Reading Order

1. Read the overview first to understand the shared size contract used by the game.
2. Read the slime guide when preparing animated character sheets.
3. Read the terrain guide when preparing ground, wall, and prop textures.
4. Read the friends and houses guide when preparing NPC parts, buildings, and interaction props.

## Current Safe Defaults

- Slime-style animated sheet: `8 x 8` grid, `256 x 256 px` per frame
- Terrain tile: `64 x 64 px`
- Friend face or accessory part: `24 x 24 px`
- House texture: `128 x 128 px`
- Small world prop: around `16 x 16 px` to `48 x 20 px`

Tile size: 64×64
Slime sprite: 48×48 or 64×64
Tools: 16×16 to 32×32
Buildings: multiples of 64×64

Example:

Tree: 1 tile wide, 2 tiles tall
Small rock: 1 tile
House: 3×3 tiles
Storage: 2×2 tiles
Farm plot: 1×1 or 2×2 tiles

If new art stays inside those measurements, it should work with the current code with little or no adjustment.