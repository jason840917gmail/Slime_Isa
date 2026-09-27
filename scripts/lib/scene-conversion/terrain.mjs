import { transform } from 'esbuild';

import { canonicalJson } from './adapter-utils.mjs';

/** The project's one shared terrain TileSet, as in Godot where every map layer references the same TileSet. */
export const TERRAIN_TILE_SET_ID = 'terrain.tiles';
export const TERRAIN_TILE_SET_PATH = 'resources/terrain/terrain.tile-set.resource.json';

export function terrainTileEntry(definition) {
  return {
    assetIds: definition.visual.assetIds,
    selection: definition.visual.selection,
    physics: definition.physics,
    allowsDecorations: definition.allowsDecorations,
    ...(definition.transition ? { transition: definition.transition } : {}),
    tags: definition.tags,
  };
}

export const terrainSceneAdapter = {
  async convert({ units, readSource }) {
    const source = await readSource(units[0].oldSourcePath);
    const { code } = await transform(source, { loader: 'ts', format: 'esm', target: 'es2022' });
    const module = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
    const definitions = module.TILE_CATALOG;
    for (const unit of units) {
      if (unit.oldSourcePath !== units[0].oldSourcePath || !definitions?.[unit.stableId]) {
        throw new Error(`Terrain definition '${unit.key}' is missing from the frozen catalog`);
      }
    }
    const ordered = [...units].sort((left, right) => left.stableId.localeCompare(right.stableId));
    const tiles = Object.fromEntries(ordered.map((unit) => [unit.stableId, terrainTileEntry(definitions[unit.stableId])]));
    // Every terrain unit contributes one tile to the shared file; the first unit owns the output.
    const [owner, ...contributors] = ordered;
    return [{
      unitKey: owner.key,
      path: TERRAIN_TILE_SET_PATH,
      content: canonicalJson({ version: 1, resourceId: TERRAIN_TILE_SET_ID, kind: 'tile-set', tiles }),
      consumedFieldPaths: [`$.TILE_CATALOG.${owner.stableId}`],
      intentionallyRetainedFields: [],
      ...(contributors.length > 0 ? {
        contributions: contributors.map((unit) => ({ unitKey: unit.key, consumedFieldPaths: [`$.TILE_CATALOG.${unit.stableId}`], intentionallyRetainedFields: [] })),
      } : {}),
    }];
  },
};
