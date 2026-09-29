import type Phaser from 'phaser';

import type { WorldDimensions } from '../../world/WorldDimensions';
import { planTerrainBlendChunks, type TerrainBlendLookup } from './TerrainBlendField';
import { TerrainTransitionLayer, type TerrainCanvasFactory, type TerrainVisualResolver } from './TerrainTransitionLayer';

export { TerrainTransitionLayer } from './TerrainTransitionLayer';

/** The subset of tile-set tile metadata blending needs. */
interface BlendableTile {
  readonly transition?: Readonly<Record<string, unknown>>;
}

/** Tiles in the shared `natural-ground` group blend; everything else keeps hard cell edges. */
export function terrainBlendLookup(tiles: Readonly<Record<string, BlendableTile>>): TerrainBlendLookup {
  return (tileId) => {
    const transition = tiles[tileId]?.transition;
    if (transition?.group !== 'natural-ground') return undefined;
    if (typeof transition.material !== 'string' || typeof transition.priority !== 'number') return undefined;
    return { material: transition.material, priority: transition.priority };
  };
}

export interface TerrainBlendRenderRequest {
  readonly scene: Phaser.Scene;
  readonly grid: readonly (readonly (string | undefined)[])[];
  readonly lookup: TerrainBlendLookup;
  readonly resolveVisual: TerrainVisualResolver;
  readonly dimensions: WorldDimensions;
  readonly seed: number;
  readonly createCanvas?: TerrainCanvasFactory;
}

/**
 * Visual-only pass over authored terrain: chunks containing a material border
 * are re-painted as blended, organic material regions (see TerrainBlendField).
 * Chunks of one material keep the plain tile layer underneath.
 */
export function renderTerrainBlend(request: TerrainBlendRenderRequest): TerrainTransitionLayer {
  const grid = request.grid.map((row) => row.map((tileId) => tileId ?? ''));
  const chunks = planTerrainBlendChunks(grid, (tileId) => (tileId ? request.lookup(tileId) : undefined), request.dimensions, { seed: request.seed });
  return new TerrainTransitionLayer(request.scene, request.resolveVisual, request.dimensions.tileSize, chunks, request.createCanvas);
}
