import { collisionBits } from '../../../content/physics/CollisionLayers';
import { authoredNodeId, resourceId, type AuthoredNodeId, type ResourceId } from '../../../content/scenes/identifiers';
import { parseTileMapDataResource, type TileMapCell } from '../../../content/scenes/resources/TileMapDataResource';
import { parseTileSetResource, type ResolvedTileSetResource } from '../../../content/scenes/resources/TileSetResource';
import type { TileDataResourceDocument, TileSetResourceDocument } from '../../../content/scenes/resources/types';
import type { SceneNodeDocument } from '../../../content/scenes/types';
import { brushCoordinates, tilePaintCommands, type TileCoordinate, type TilePaintCommand } from '../TilePaintCommand';

export type TilePaintTool = 'brush' | 'erase' | 'fill';

export interface TileMapEffectiveRegion {
  readonly minX: number;
  readonly minY: number;
  readonly maxX: number;
  readonly maxY: number;
}

export interface TileLayerDraft {
  readonly node: SceneNodeDocument;
  readonly data: TileDataResourceDocument;
  readonly relativePath: string;
}

interface TileHistoryEntry {
  readonly document: TileDataResourceDocument;
  readonly label: string;
}

const clone = <T>(value: T): T => structuredClone(value);

export function tileDataResourceId(node: SceneNodeDocument): ResourceId | undefined {
  const value = node.properties.tileData;
  if (value === null || Array.isArray(value) || typeof value !== 'object') return undefined;
  const id = (value as Readonly<Record<string, unknown>>).resourceId;
  return typeof id === 'string' ? resourceId(id) : undefined;
}

export function createTileLayerDraft(options: {
  readonly sceneId: string;
  readonly nodeId: string;
  readonly name: string;
  readonly parentId: AuthoredNodeId;
  readonly order: number;
  readonly columns: number;
  readonly rows: number;
  readonly tileSize: number;
  readonly tileSet: ResourceId;
  readonly seed: number;
}): TileLayerDraft {
  if (!Number.isSafeInteger(options.columns) || options.columns < 1 || !Number.isSafeInteger(options.rows) || options.rows < 1) {
    throw new Error('Tile layer dimensions must be positive integers');
  }
  if (!Number.isFinite(options.tileSize) || options.tileSize <= 0) throw new Error('Tile size must be positive');
  const nodeId = authoredNodeId(options.nodeId);
  const mapId = options.sceneId.startsWith('world.') ? options.sceneId.slice('world.'.length) : options.sceneId;
  const suffix = options.nodeId.replace(/^layer-/, '');
  const dataId = resourceId(`tiles.${mapId}.${suffix}.data`);
  return {
    node: {
      id: nodeId,
      name: options.name,
      type: 'TileMapLayer2D',
      parentId: options.parentId,
      order: options.order,
      properties: {
        position: [0, 0],
        tileData: { resourceId: dataId },
        tileSize: options.tileSize,
        seed: options.seed,
        depth: options.order,
        collisionLayer: collisionBits('world'),
        collisionMask: 0,
        collisionEnabled: true,
        editorLocked: false,
      },
    },
    data: {
      version: 1,
      resourceId: dataId,
      kind: 'tile-data',
      tileSet: options.tileSet,
      columns: options.columns,
      rows: options.rows,
      cells: [],
    },
    relativePath: `authored/resources/tiles/${mapId}.${suffix}.tile-data.resource.json`,
  };
}

export class TileMapContext {
  private documentValue: TileDataResourceDocument;
  private tileSetValue: ResolvedTileSetResource;
  private readonly past: TileHistoryEntry[] = [];
  private readonly future: TileHistoryEntry[] = [];
  private savedDocument: string;
  private toolValue: TilePaintTool = 'brush';
  private selectedTileValue: string;
  private brushSizeValue = 1;
  private showCollisionValue = false;
  private showEffectiveRegionValue = true;
  private panValue: TileCoordinate = { x: 0, y: 0 };
  private zoomValue = 1;
  private revisionValue = 0;

  constructor(
    document: TileDataResourceDocument,
    tileSet: TileSetResourceDocument,
  ) {
    const parsed = parseTileMapDataResource(document);
    const parsedSet = parseTileSetResource(tileSet);
    if (parsed.tileSet !== parsedSet.resourceId) {
      throw new Error(`Tile data '${parsed.resourceId}' requires tile set '${parsed.tileSet}', received '${parsedSet.resourceId}'`);
    }
    this.documentValue = clone(document);
    this.tileSetValue = parsedSet;
    this.revisionValue += 1;
    this.selectedTileValue = Object.keys(parsedSet.tiles)[0];
    this.savedDocument = JSON.stringify(document);
    this.assertTilesExist();
  }

  get document(): TileDataResourceDocument { return clone(this.documentValue); }
  /** Increments whenever tile data or the bound tile set changes. */
  get revision(): number { return this.revisionValue; }
  get tileSet(): ResolvedTileSetResource { return clone(this.tileSetValue); }
  get tool(): TilePaintTool { return this.toolValue; }
  get selectedTile(): string { return this.selectedTileValue; }
  get brushSize(): number { return this.brushSizeValue; }
  get showCollision(): boolean { return this.showCollisionValue; }
  get showEffectiveRegion(): boolean { return this.showEffectiveRegionValue; }
  get pan(): TileCoordinate { return this.panValue; }
  get zoom(): number { return this.zoomValue; }
  get dirty(): boolean { return JSON.stringify(this.documentValue) !== this.savedDocument; }
  get canUndo(): boolean { return this.past.length > 0; }
  get canRedo(): boolean { return this.future.length > 0; }
  get cells(): readonly TileMapCell[] { return parseTileMapDataResource(this.documentValue).cells; }

  get effectiveRegion(): TileMapEffectiveRegion | undefined {
    const cells = this.cells;
    if (cells.length === 0) return undefined;
    return {
      minX: Math.min(...cells.map((cell) => cell.x)),
      minY: Math.min(...cells.map((cell) => cell.y)),
      maxX: Math.max(...cells.map((cell) => cell.x)),
      maxY: Math.max(...cells.map((cell) => cell.y)),
    };
  }

  execute(command: TilePaintCommand): void {
    const next = command.apply(this.documentValue);
    this.assertDocument(next);
    this.past.push({ document: clone(this.documentValue), label: command.label });
    this.documentValue = next;
    this.revisionValue += 1;
    this.future.length = 0;
  }

  paint(coordinate: TileCoordinate): void {
    if (this.toolValue === 'fill') {
      this.execute(tilePaintCommands.fill(coordinate, this.selectedTileValue));
      return;
    }
    const coordinates = brushCoordinates(coordinate, this.brushSizeValue, this.documentValue);
    this.execute(this.toolValue === 'erase'
      ? tilePaintCommands.erase(coordinates)
      : tilePaintCommands.paint(coordinates, this.selectedTileValue));
  }

  selectTool(tool: TilePaintTool): void { this.toolValue = tool; }

  selectTile(tileId: string): void {
    if (!Object.hasOwn(this.tileSetValue.tiles, tileId)) throw new Error(`Tile set '${this.tileSetValue.resourceId}' has no tile '${tileId}'`);
    this.selectedTileValue = tileId;
    this.toolValue = 'brush';
  }

  setBrushSize(size: number): void {
    brushCoordinates({ x: 0, y: 0 }, size, { columns: 1, rows: 1 });
    this.brushSizeValue = size;
  }

  selectTileSet(document: TileSetResourceDocument): void {
    const parsed = parseTileSetResource(document);
    const missing = [...new Set(this.cells.map((cell) => cell.tileId).filter((tileId) => !Object.hasOwn(parsed.tiles, tileId)))];
    if (missing.length > 0) throw new Error(`Tile set '${parsed.resourceId}' is missing used tiles: ${missing.join(', ')}`);
    this.tileSetValue = parsed;
    this.revisionValue += 1;
    this.execute(tilePaintCommands.selectTileSet(parsed.resourceId));
    if (!Object.hasOwn(parsed.tiles, this.selectedTileValue)) this.selectedTileValue = Object.keys(parsed.tiles)[0];
  }

  toggleCollision(): void { this.showCollisionValue = !this.showCollisionValue; }
  toggleEffectiveRegion(): void { this.showEffectiveRegionValue = !this.showEffectiveRegionValue; }

  panBy(x: number, y: number): void {
    this.panValue = {
      x: Math.max(0, Math.min(this.documentValue.columns - 1, this.panValue.x + x)),
      y: Math.max(0, Math.min(this.documentValue.rows - 1, this.panValue.y + y)),
    };
  }

  setZoom(zoom: number): void { this.zoomValue = Math.max(0.5, Math.min(3, zoom)); }

  snap(worldX: number, worldY: number, tileSize: number): TileCoordinate {
    if (!Number.isFinite(tileSize) || tileSize <= 0) throw new Error('Tile size must be positive');
    return {
      x: Math.max(0, Math.min(this.documentValue.columns - 1, Math.floor(worldX / tileSize))),
      y: Math.max(0, Math.min(this.documentValue.rows - 1, Math.floor(worldY / tileSize))),
    };
  }

  isCollisionCell(coordinate: TileCoordinate): boolean {
    const tileId = this.cells.find((cell) => cell.x === coordinate.x && cell.y === coordinate.y)?.tileId;
    return Boolean(tileId && this.tileSetValue.tiles[tileId]?.physics);
  }

  undo(): boolean {
    const previous = this.past.pop();
    if (!previous) return false;
    this.future.push({ document: clone(this.documentValue), label: previous.label });
    this.documentValue = previous.document;
    this.revisionValue += 1;
    return true;
  }

  redo(): boolean {
    const next = this.future.pop();
    if (!next) return false;
    this.past.push({ document: clone(this.documentValue), label: next.label });
    this.documentValue = next.document;
    this.revisionValue += 1;
    return true;
  }

  markSaved(): void { this.savedDocument = JSON.stringify(this.documentValue); }

  private assertTilesExist(): void {
    const missing = [...new Set(this.cells.map((cell) => cell.tileId).filter((tileId) => !Object.hasOwn(this.tileSetValue.tiles, tileId)))];
    if (missing.length > 0) throw new Error(`Tile data '${this.documentValue.resourceId}' uses unknown tiles: ${missing.join(', ')}`);
  }

  private assertDocument(document: TileDataResourceDocument): void {
    parseTileMapDataResource(document);
    const missing = document.cells
      .map((cell) => (cell as { tileId?: unknown }).tileId)
      .filter((tileId): tileId is string => typeof tileId === 'string' && !Object.hasOwn(this.tileSetValue.tiles, tileId));
    if (missing.length > 0) throw new Error(`Tile set '${this.tileSetValue.resourceId}' has no tile '${missing[0]}'`);
  }
}
