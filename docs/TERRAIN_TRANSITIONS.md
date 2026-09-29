# Terrain Transitions

## Ownership

World scenes store one logical terrain ID per cell in a `TileMapLayer2D`. They do not store transition tiles, masks, texture paths, or generated edge objects.

- The shared terrain TileSet resource (`terrain.tiles`, `content/scenes/authored/resources/terrain/terrain.tile-set.resource.json`) owns each tile's `transition` metadata; `content/terrain/TileCatalog.ts` exposes it by stable tile ID.
- `features/world/TerrainBlendField.ts` plans the blend (pure, no Phaser).
- `features/world/TerrainTransitionLayer.ts` bakes the plan into canvas-texture chunks; `TerrainTransitionRenderer.ts` wires the two together.
- `infrastructure/phaser-nodes/TileMapLayer2DNode.ts` mounts the blend over the base tiles, so the game and Scene Studio render identical terrain.
- Physics, walkability, and decoration rules use only the logical tile. Blending never changes gameplay or map data.

## Current strategy: organic region blending

Eligible natural ground tiles declare:

```json
"transition": { "group": "natural-ground", "material": "frozen", "priority": 10, "edgeWidth": 12, "style": "noisy-feather" }
```

Only `group`, `material`, and `priority` drive rendering; `edgeWidth` and `style` are retained data from the earlier per-edge feathering.

1. The world is split into 512 px chunks (2 px gutter). Only chunks with a material border within reach are baked; single-material chunks keep the plain tile layer.
2. Every blend cell contributes a smooth radial weight for its material. Sample positions are domain-warped by deterministic value noise (seeded by the layer's `seed`), so borders wander without saved data.
3. Weights are sharpened and normalized into shares, then painted as per-material alpha masks in ascending priority. Higher priority nudges a border into the lower material; straight borders stay near the cell edge while convex corners and lone cells round off.
4. Chunks outside the camera are culled.

Tiles without a `natural-ground` transition (`rock-wall`, `wood-floor`, the `mushroom-*` floors) keep hard cell edges. `water` and `deep-water` do participate (priorities 5 and 4) while remaining solid. `grass-a`/`grass-b` share the `highland` material, so their ID difference does not produce a seam. Blending applies only to unrotated, unscaled layers.

### Limitations

- The generic mask blends any participating materials but cannot express material-specific details such as snow buildup, shoreline foam, or scattered leaves.

## Alternative routes

- **Edge decorations:** scatter small themed sprites along detected boundaries. Cheap and easy to theme, but disguises a join rather than blending pixels. Best as polish over the blend. (The existing `scripts/maps/scatter-decorations.mjs` scatters over forest ground generally, not along borders.)
- **Authored autotiles / Wang tiles:** 8-neighbor bitmask selects hand-drawn edge/corner frames. Highest art-directed quality for key pairs (grass/water, cliffs), at a significant art cost.
- **Shader / splat-map blending:** a custom WebGL pipeline with per-cell material weights. Smooth and scalable, but WebGL-specific and harder to keep in editor/runtime parity.
- **Manual transition tiles in maps:** tedious, fragile, and contradicts derived presentation. Only for exceptional hand-composed landmarks.

## Recommended evolution

1. Keep region blending as the generic default.
2. Add material-specific edge decorations for high-value biome pairs.
3. Introduce authored Wang/autotile sets only for pairs that still need art-directed joins.
4. Consider shader blending only if chunk baking becomes a measured performance problem.
