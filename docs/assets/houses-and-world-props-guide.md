# Houses And World Props Guide

This guide covers art for buildings and reusable world props. Persistent houses,
props, NPCs, and interaction objects are placed explicitly in authored map JSON.
Runtime scenes must not create an extra map population.

## House Asset Rules

- A typical house texture is `128 x 128 px`.
- Keep the main silhouette inside the canvas.
- Put the doorway near the bottom center.
- Compare the art against the `64 x 64 px` tile grid before exporting.

The reusable object definition owns collision and visual behavior. The map
instance owns placement, position, and mutable instance state. A doorway or
other interaction zone must be represented by authored content instead of being
derived from a hardcoded house position at runtime.

## World Prop Rules

- Keep small props visually compatible with the surrounding tile and building scale.
- Give every reusable prop a stable asset ID and object ID.
- Register media in `asset/assets.json` and object behavior under `src/game/content/objects/`.
- Place every persistent instance in `src/game/content/maps/`.
- Keep temporary combat and feedback effects in their owning runtime feature.

Run `pnpm assets:check`, `pnpm objects:check`, and `pnpm maps:check` after adding
or moving authored world content.
