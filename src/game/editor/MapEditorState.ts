import type {
  MapDirection,
  MapEnemySpawn,
  MapEnemySafeZone,
  MapFile,
  MapPoint,
  MapZone,
} from '../content/maps/mapFormat';
import type { ObjectArchetypeId } from '../content/objects/ObjectCatalog';
import type { WorldTileId } from '../content/terrain/TileCatalog';
import { connectionAt, edgeEntryPoint, edgeExitZone, exitDirection, OPPOSITE_DIRECTION } from './MapConnections';

export type EditorTool = 'pan' | 'terrain' | 'object' | 'select' | 'erase' | 'safe-zone' | 'spawn' | 'entry' | 'exit';

export interface EditableObjectInstance {
  instanceId: string;
  objectId: string;
  visualId: string;
  x: number;
  y: number;
  initialState?: Record<string, unknown>;
}

export interface EditableMap {
  $schema?: string;
  version: 1;
  mapId: string;
  tileSize: number;
  size: { columns: number; rows: number };
  layers: Array<{
    id: string;
    encoding: 'legend-chars-v1';
    legend: Record<string, string>;
    rows: string[];
  }>;
  objects: EditableObjectInstance[];
  player: {
    spawn: MapPoint;
    entries: Partial<Record<MapDirection, MapPoint>>;
  };
  exits: Array<{ zone: MapZone; to: string; entry: string }>;
  enemySafeZones: MapEnemySafeZone[];
  spawns?: {
    enemies: MapEnemySpawn[];
    radius: { min: number; max: number };
    intervalMs: number;
    maxPopulation: number;
    safeZones: MapEnemySafeZone[];
  };
}

export interface EditorViewState {
  readonly map: EditableMap;
  readonly tool: EditorTool;
  readonly tileId: WorldTileId;
  readonly objectId: ObjectArchetypeId;
  readonly objectVisualId: string;
  readonly direction: MapDirection;
  readonly selectedInstanceId?: string;
  readonly selectedSafeZoneIndex?: number;
  readonly dirty: boolean;
  readonly canUndo: boolean;
  readonly canRedo: boolean;
  readonly saving: boolean;
  readonly status: string;
  readonly revision: number;
}

type Listener = (state: EditorViewState) => void;

function serialize(map: EditableMap): string {
  return JSON.stringify(map);
}

export class MapEditorState {
  private mapValue: EditableMap;
  private savedSnapshot: string;
  private undoStack: string[] = [];
  private redoStack: string[] = [];
  private listeners = new Set<Listener>();
  private toolValue: EditorTool = 'pan';
  private tileIdValue: WorldTileId;
  private objectIdValue: ObjectArchetypeId;
  private objectVisualIdValue: string;
  private directionValue: MapDirection = 'east';
  private selectedInstanceIdValue?: string;
  private selectedSafeZoneIndexValue?: number;
  private savingValue = false;
  private statusValue = 'Ready';
  private revisionValue = 0;
  /**
   * Cached dirty flag. Comparing against the saved snapshot requires a full
   * JSON.stringify of the map — doing that per state read (pointermove and
   * update handlers read `value` many times per second) churned megabytes of
   * GC per stroke. Instead we flip the flag only at mutation points:
   * mutate/undo/redo/save.
   */
  private dirtyValue = false;

  constructor(map: MapFile, initialTileId: WorldTileId, initialObjectId: ObjectArchetypeId, initialObjectVisualId: string) {
    this.mapValue = structuredClone(map) as EditableMap;
    this.mapValue.exits ??= [];
    this.mapValue.enemySafeZones ??= [...structuredClone(map.spawns?.safeZones ?? [])];
    this.savedSnapshot = serialize(this.mapValue);
    this.tileIdValue = initialTileId;
    this.objectIdValue = initialObjectId;
    this.objectVisualIdValue = initialObjectVisualId;
  }

  get value(): EditorViewState {
    return {
      map: this.mapValue,
      tool: this.toolValue,
      tileId: this.tileIdValue,
      objectId: this.objectIdValue,
      objectVisualId: this.objectVisualIdValue,
      direction: this.directionValue,
      selectedInstanceId: this.selectedInstanceIdValue,
      selectedSafeZoneIndex: this.selectedSafeZoneIndexValue,
      dirty: this.dirtyValue,
      canUndo: this.undoStack.length > 0,
      canRedo: this.redoStack.length > 0,
      saving: this.savingValue,
      status: this.statusValue,
      revision: this.revisionValue,
    };
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.value);
    return () => this.listeners.delete(listener);
  }

  setTool(tool: EditorTool): void {
    this.toolValue = tool;
    // Zones are only visible (and selectable) in the safe-zone tool, so a
    // stale zone selection must not survive switching to another tool.
    if (tool !== 'safe-zone') this.selectedSafeZoneIndexValue = undefined;
    if (tool === 'select') this.statusValue = 'Drag any highlighted object to move it';
    else if (tool === 'safe-zone') this.statusValue = 'Drag across tiles to draw a rectangular safe zone';
    else if (tool === 'terrain') this.statusValue = `Drag to paint ${this.tileIdValue}`;
    else if (tool === 'object') this.statusValue = `Drag to stamp ${this.objectIdValue} / ${this.objectVisualIdValue}`;
    else this.statusValue = `${tool} tool active`;
    this.emit();
  }

  setTile(tileId: WorldTileId): void {
    this.tileIdValue = tileId;
    this.toolValue = 'terrain';
    this.statusValue = `Painting ${tileId}`;
    this.emit();
  }

  setObject(objectId: ObjectArchetypeId, visualId: string): void {
    this.objectIdValue = objectId;
    this.objectVisualIdValue = visualId;
    this.toolValue = 'object';
    this.statusValue = `Placing ${objectId} / ${visualId}`;
    this.emit();
  }

  setDirection(direction: MapDirection): void {
    this.directionValue = direction;
    this.emit();
  }

  setConnection(direction: MapDirection, targetMapId?: string): void {
    const previousTarget = connectionAt(direction, this.mapValue)?.to;
    const label = targetMapId
      ? `Connected ${direction} to ${targetMapId}`
      : `Disconnected ${direction}${previousTarget ? ` from ${previousTarget}` : ''}`;
    this.mutate(label, (map) => {
      map.exits = map.exits.filter((exit) => exitDirection(exit, map) !== direction);
      if (!targetMapId) return;
      map.player.entries[direction] ??= edgeEntryPoint(direction, map);
      map.exits.push({
        zone: edgeExitZone(direction, map),
        to: targetMapId,
        entry: OPPOSITE_DIRECTION[direction],
      });
    });
  }

  setSpawns(spawns?: EditableMap['spawns']): void {
    this.mutate(spawns ? 'Updated monster spawning' : 'Disabled monster spawning', (map) => {
      map.spawns = spawns ? structuredClone(spawns) : undefined;
    });
  }

  selectInstance(instanceId?: string): void {
    this.selectedInstanceIdValue = instanceId;
    if (instanceId) this.selectedSafeZoneIndexValue = undefined;
    this.statusValue = instanceId ? `Selected ${instanceId} — drag to move or Delete to remove` : 'Selection cleared';
    this.emit();
  }

  selectSafeZone(index?: number): void {
    this.selectedSafeZoneIndexValue = index;
    if (index !== undefined) this.selectedInstanceIdValue = undefined;
    this.statusValue = index === undefined
      ? 'Safe-zone selection cleared'
      : `Selected safe zone ${index + 1} — drag to move or press Delete to remove`;
    this.emit();
  }

  notify(message: string): void {
    this.statusValue = message;
    this.emit();
  }

  mutate(label: string, operation: (map: EditableMap) => void): boolean {
    const before = serialize(this.mapValue);
    operation(this.mapValue);
    const after = serialize(this.mapValue);
    if (before === after) return false;
    this.undoStack.push(before);
    if (this.undoStack.length > 100) this.undoStack.shift();
    this.redoStack = [];
    this.revisionValue += 1;
    this.dirtyValue = true;
    this.statusValue = label;
    this.emit();
    return true;
  }

  undo(): void {
    const previous = this.undoStack.pop();
    if (!previous) return;
    this.redoStack.push(serialize(this.mapValue));
    this.mapValue = JSON.parse(previous) as EditableMap;
    this.selectedInstanceIdValue = undefined;
    this.selectedSafeZoneIndexValue = undefined;
    this.revisionValue += 1;
    this.dirtyValue = serialize(this.mapValue) !== this.savedSnapshot;
    this.statusValue = 'Undid last change';
    this.emit();
  }

  redo(): void {
    const next = this.redoStack.pop();
    if (!next) return;
    this.undoStack.push(serialize(this.mapValue));
    this.mapValue = JSON.parse(next) as EditableMap;
    this.selectedInstanceIdValue = undefined;
    this.selectedSafeZoneIndexValue = undefined;
    this.revisionValue += 1;
    this.dirtyValue = serialize(this.mapValue) !== this.savedSnapshot;
    this.statusValue = 'Redid change';
    this.emit();
  }

  async save(): Promise<void> {
    if (this.savingValue) return;
    this.savingValue = true;
    this.statusValue = 'Validating and saving...';
    this.emit();

    try {
      const response = await fetch('/__map-editor/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(this.mapValue),
      });
      const result = await response.json() as { ok?: boolean; error?: string };
      if (!response.ok || !result.ok) throw new Error(result.error ?? `Save failed (${response.status})`);
      this.savedSnapshot = serialize(this.mapValue);
      this.dirtyValue = false;
      this.statusValue = `Saved ${this.mapValue.mapId}.map.json`;
    } catch (error) {
      this.statusValue = error instanceof Error ? error.message : String(error);
    } finally {
      this.savingValue = false;
      this.emit();
    }
  }

  private emit(): void {
    const state = this.value;
    for (const listener of this.listeners) listener(state);
  }
}
