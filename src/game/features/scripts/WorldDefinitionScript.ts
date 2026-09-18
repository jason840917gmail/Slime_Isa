import type { MapFile } from '../../content/maps/mapFormat';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

/**
 * Authored world-level data that does not naturally belong to an individual
 * node. Tile cells remain external resources; placements and navigation remain
 * nodes/instances. This script makes the remaining world contract editable and
 * loadable from the scene document without consulting legacy map JSON.
 */
export class WorldDefinitionScript extends ScriptNode {
  readonly mapId: string;
  readonly tileSize: number;
  readonly columns: number;
  readonly rows: number;
  readonly worldData: Omit<MapFile, 'version' | 'mapId' | 'tileSize' | 'size' | 'layers'>;

  constructor(context: NodeConstructionContext) {
    if (!context.scriptId) throw new Error('WorldDefinitionScript requires a registered script identity.');
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: context.scriptId, exportedProperties: context.properties });
    this.mapId = typeof context.properties.mapId === 'string' ? context.properties.mapId : '';
    this.tileSize = typeof context.properties.tileSize === 'number' ? context.properties.tileSize : 0;
    this.columns = typeof context.properties.columns === 'number' ? context.properties.columns : 0;
    this.rows = typeof context.properties.rows === 'number' ? context.properties.rows : 0;
    const metadata = context.properties.metadata;
    if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) {
      throw new Error(`World definition '${context.runtimeId}' requires metadata.`);
    }
    this.worldData = structuredClone(metadata) as unknown as WorldDefinitionScript['worldData'];
  }
}
