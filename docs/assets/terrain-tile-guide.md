# Terrain And Tile Guide

This guide covers ground tiles, obstacle tiles, and small decorative props.

## Base Grid Contract

- Standard world tile size: `64 x 64 px`
- Production maps currently use `54 x 54` tiles, but each authored map owns its dimensions.
- A current production map is `3456 x 3456 px`.

Any texture that is meant to behave like a terrain tile should be designed around `64 x 64 px` first.

## Terrain Rules

- Ground and obstacle textures are treated as single tiles.
- Keep tile edges clean so repeated placement does not show seams.
- Design repeatable tiles so they can sit next to copies of themselves.
- Avoid blurry antialiasing because the game uses pixel-art rendering.

## Collision Rules

Walkable tiles usually have no collision body. Terrain collision belongs to `TileCatalog.ts`; reusable object collision belongs to the object's own JSON definition.

Default solid tile inset values:

- Left: `6`
- Right: `6`
- Top: `8`
- Bottom: `8`

Current `rock-wall` inset values:

- Left: `4`
- Right: `4`
- Top: `6`
- Bottom: `2`

Use tighter insets when the visible art has rounded tops, uneven edges, or a base that is narrower than the full tile.

## Decorative Prop Sizes

Current examples:

- Flower: `16 x 16 px`
- Purple berry: `16 x 16 px`
- Stone: `32 x 18 px`

Small props should remain readable when placed on top of a `64 x 64` terrain tile.

## Authoring Tips

- Test tiles in a checker pattern before importing them.
- Compare props against a `64 x 64` tile mockup, not in isolation.
- Keep obstacle silhouettes visually aligned with the collision area players will feel.
- If terrain needs a different footprint, update its `TileCatalog.ts` definition. If a reusable object needs one, create or update that object's content file.

## Safe Template

- Terrain tile: `64 x 64 px`
- Small prop: `16 x 16 px` to `32 x 18 px`
- Obstacle tile: `64 x 64 px` plus matching collision inset values in code
