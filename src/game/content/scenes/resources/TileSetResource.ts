import type { TileSetResourceDocument } from './types';

export type TileFrameSelection = 'seeded-hash' | 'ground-sheet-region' | 'sheet-order';

export interface TileSetTile {
  readonly assetIds: readonly string[];
  readonly selection: TileFrameSelection;
  readonly physics: null | {
    readonly body: 'static';
    readonly inset?: Readonly<Partial<Record<'left' | 'right' | 'top' | 'bottom', number>>>;
  };
  readonly allowsDecorations: boolean;
  readonly tags: readonly string[];
  readonly editor?: Readonly<Record<string, unknown>>;
}

export interface ResolvedTileSetResource {
  readonly resourceId: TileSetResourceDocument['resourceId'];
  readonly tiles: Readonly<Record<string, TileSetTile>>;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function finiteNonNegative(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

export function parseTileSetResource(document: TileSetResourceDocument): ResolvedTileSetResource {
  const tiles: Record<string, TileSetTile> = {};
  for (const [tileId, value] of Object.entries(document.tiles)) {
    if (!tileId) throw new Error(`Tile set '${document.resourceId}' contains an empty tile ID`);
    if (!isRecord(value)) throw new Error(`Tile '${tileId}' in '${document.resourceId}' must be an object`);
    const assetIds = value.assetIds;
    if (!Array.isArray(assetIds) || assetIds.length === 0 || assetIds.some((assetId) => typeof assetId !== 'string' || assetId.length === 0)) {
      throw new Error(`Tile '${tileId}' in '${document.resourceId}' requires non-empty assetIds`);
    }
    const selection = value.selection;
    if (!['seeded-hash', 'ground-sheet-region', 'sheet-order'].includes(String(selection))) {
      throw new Error(`Tile '${tileId}' in '${document.resourceId}' has invalid frame selection`);
    }
    let physics: TileSetTile['physics'] = null;
    if (value.physics !== null) {
      if (!isRecord(value.physics) || value.physics.body !== 'static') {
        throw new Error(`Tile '${tileId}' in '${document.resourceId}' has invalid physics`);
      }
      const insetValue = value.physics.inset;
      if (insetValue !== undefined && !isRecord(insetValue)) {
        throw new Error(`Tile '${tileId}' in '${document.resourceId}' has invalid collision inset`);
      }
      const inset = insetValue as Readonly<Record<string, unknown>> | undefined;
      for (const edge of ['left', 'right', 'top', 'bottom'] as const) {
        if (inset?.[edge] !== undefined && !finiteNonNegative(inset[edge])) {
          throw new Error(`Tile '${tileId}' in '${document.resourceId}' has invalid '${edge}' collision inset`);
        }
      }
      physics = {
        body: 'static',
        ...(inset ? { inset: Object.fromEntries(
          (['left', 'right', 'top', 'bottom'] as const)
            .filter((edge) => inset[edge] !== undefined)
            .map((edge) => [edge, inset[edge] as number]),
        ) } : {}),
      };
    }
    if (typeof value.allowsDecorations !== 'boolean') {
      throw new Error(`Tile '${tileId}' in '${document.resourceId}' requires allowsDecorations`);
    }
    if (!Array.isArray(value.tags) || value.tags.some((tag) => typeof tag !== 'string')) {
      throw new Error(`Tile '${tileId}' in '${document.resourceId}' requires string tags`);
    }
    if (value.editor !== undefined && !isRecord(value.editor)) {
      throw new Error(`Tile '${tileId}' in '${document.resourceId}' has invalid editor metadata`);
    }
    tiles[tileId] = {
      assetIds: [...assetIds] as string[],
      selection: selection as TileFrameSelection,
      physics,
      allowsDecorations: value.allowsDecorations,
      tags: [...value.tags] as string[],
      ...(value.editor ? { editor: structuredClone(value.editor) } : {}),
    };
  }
  if (Object.keys(tiles).length === 0) throw new Error(`Tile set '${document.resourceId}' must contain at least one tile`);
  return { resourceId: document.resourceId, tiles };
}
