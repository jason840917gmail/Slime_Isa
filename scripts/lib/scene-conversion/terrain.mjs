import { transform } from 'esbuild';

import { convertedOutput, resourcePath } from './adapter-utils.mjs';

export const terrainSceneAdapter = {
  async convert({ units, readSource }) {
    const source = await readSource(units[0].oldSourcePath);
    const { code } = await transform(source, { loader: 'ts', format: 'esm', target: 'es2022' });
    const module = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
    const definitions = module.TILE_CATALOG;
    return units.map((unit) => {
      if (unit.oldSourcePath !== units[0].oldSourcePath || !definitions?.[unit.stableId]) {
        throw new Error(`Terrain definition '${unit.key}' is missing from the frozen catalog`);
      }
      const definition = definitions[unit.stableId];
      return convertedOutput(unit, resourcePath('terrain', unit.stableId, 'tile-set'), {
        version: 1,
        resourceId: `terrain.${unit.stableId}`,
        kind: 'tile-set',
        tiles: { [unit.stableId]: {
          assetIds: definition.visual.assetIds,
          selection: definition.visual.selection,
          physics: definition.physics,
          allowsDecorations: definition.allowsDecorations,
          ...(definition.transition ? { transition: definition.transition } : {}),
          tags: definition.tags,
        } },
      }, [`$.TILE_CATALOG.${unit.stableId}`]);
    });
  },
};
