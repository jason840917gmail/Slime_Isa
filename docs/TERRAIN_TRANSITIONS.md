# Terrain Transitions

## Ownership

Authored maps store one logical terrain ID per cell. They do not store transition tiles, masks, texture paths, or generated edge objects.

- `TileCatalog.ts` owns transition presentation metadata.
- `TileFactory` resolves the correct texture/frame/flip for a logical tile at a map coordinate.
- `TerrainTransitionRenderer` derives visual joins from neighboring terrain IDs after base terrain is built.
- Physics, walkability, and decoration rules continue to use the original logical tile only. A visual transition never changes gameplay.

The runtime `MapBuilder` and dev `MapEditorScene` use the same renderer, so editor previews match the game.

## Current Strategy: Noisy Feather

Eligible natural ground tiles declare:

```ts
transition: {
  group: 'natural-ground',
  material: 'frozen',
  priority: 10,
  edgeWidth: 12,
  style: 'noisy-feather',
}
```

After base terrain is rendered:

1. The renderer scans east and south neighbors, processing each boundary once.
2. Tiles transition only when both belong to the same transition group and use different materials.
3. Higher-priority material feathers into lower-priority material. Equal priorities use stable tile-ID ordering.
4. Three deterministic jagged bands overlay the winning material into the neighboring cell: a wide faint band, medium band, and narrow strong band.
5. Noise is derived from map seed, tile coordinate, edge, band, and sample index. It is stable between runs and requires no saved map data.

Water and solid walls currently opt out. Highland grass A/B share the same material, so their logical ID difference does not produce a false seam.

### Limitations

- The first pass handles cardinal boundaries. Adjacent cardinal bands naturally cover most corners; dedicated diagonal/corner masks can be added if isolated diagonal contacts look sharp.
- Geometry-mask overlays add render objects near boundaries. This is appropriate for the current map sizes; larger maps may benefit from cached composite textures or chunk render textures.
- The generic mask blends any participating materials but cannot express material-specific details such as snow buildup, shoreline foam, or scattered leaves.

## Alternative Routes

### Edge Decorations

Scatter small sprites (snow dust, leaves, pebbles, crystal shards, foam) along detected boundaries.

- **Advantages:** inexpensive, easy to theme, works on top of the current feathering.
- **Disadvantages:** disguises a join rather than blending the underlying pixels; needs material-specific decoration content.
- **Best use:** secondary polish layered over noisy feather masks.

### Authored Autotiles / Wang Tiles

Artists create edge, corner, inner-corner, and junction frames. An 8-neighbor bitmask selects the correct frame (typically a 16-, 47-, or Wang-tile set).

- **Advantages:** highest intentional art-directed quality; precise shorelines,
  paths, cliffs, and biome borders.
- **Disadvantages:** significant art workload; transition pairs can grow combinatorially; requires strict atlas conventions.
- **Best use:** important recurring pairs such as grass/water or snow/stone where generic blending is insufficient.

### Shader / Splat-Map Blending

Render terrain materials through a custom WebGL pipeline using per-cell material weights and noise textures.

- **Advantages:** smooth multi-material blending, scalable edge styles, fewer per-boundary display objects.
- **Disadvantages:** substantially more complex; WebGL-specific; harder editor/runtime parity and debugging; changes the rendering architecture.
- **Best use:** much larger worlds or continuous painted terrain where the current sprite model becomes the bottleneck.

### Manual Transition Tiles in Maps

Authors place explicit edge/corner tiles as separate map content.

- **Advantages:** complete local control and simple runtime rendering.
- **Disadvantages:** tedious, fragile when neighboring terrain changes, bloats map data, and violates the goal that transitions are derived presentation.
- **Best use:** exceptional hand-composed landmarks only, not the default pipeline.

## Recommended Evolution

1. Keep noisy feather as the generic default.
2. Add material-specific edge decorations for high-value biome pairs.
3. Introduce authored Wang/autotile sets only for pairs that still need art-directed joins.
4. Consider shader blending only if map size or transition-object count becomes a measured performance problem.
