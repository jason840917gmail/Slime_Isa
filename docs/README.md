# Documentation

This folder contains the asset and implementation notes for the game.

## Asset Creation And Integration

All operational documentation for generating, preparing, registering, and
incorporating new art now lives in the [Asset Creation And Integration](./assets/README.md)
folder. Start there for the recommended workflow and links to every asset guide.

## Knowledge Notes

- [Knowledge index](./knowledge/README.md)

The character-sprite integration guide is now maintained in the asset folder:
[Character sprites and animated visuals](./assets/character-sprites-guide.md)

## Recommended Reading Order

1. Read [Asset Creation And Integration](./assets/README.md) first.
2. Follow the shared sheet contract and the focused art-type guide.
3. Use the generation prompt and Magnific guide when creating source art.
4. Register the finished media and integrate it into a character, object, projectile, or map.

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
