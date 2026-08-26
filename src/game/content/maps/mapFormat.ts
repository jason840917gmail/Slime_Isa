/**
 * Authored map format v1 — types and runtime structural validation.
 *
 * Maps live in `src/game/content/maps/*.json` and are content, not media:
 * they persist stable IDs only (terrain tile IDs, object archetype IDs,
 * enemy type keys, area IDs) — never paths, texture keys, or inline stats.
 *
 * Trust model: `maps:check` validates structure at check-time; `parseMapFile`
 * re-validates at load-time before any cast, so a bad map fails loudly at
 * area entry instead of corrupting runtime state. Reference validation
 * (tile/archetype/enemy/area IDs against TS catalogs) runs at load-time
 * when MapLoader lands — catalogs stay single-owned in TypeScript.
 */

export const MAP_FORMAT_VERSION = 1;

/** Distinct from AreaId: an area references a map; interiors may add more maps later. */
export type MapId = string;

export type MapDirection = 'north' | 'east' | 'south' | 'west';

export interface MapPoint {
  readonly x: number;
  readonly y: number;
}

export interface MapZone {
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;
}

/** Terrain-only layer. Rocks/trees/chests are objects, never tile rows. */
export interface MapLayer {
  readonly id: string;
  readonly encoding: 'legend-chars-v1';
  /** Maps a single row character to a terrain tile ID (WORLD_TILE_RULES key). */
  readonly legend: Readonly<Record<string, string>>;
  readonly rows: readonly string[];
}

export interface MapObjectInstance {
  /** Stable, editor-generated, unique within the map; survives object moves. */
  readonly instanceId: string;
  /** Object archetype ID from the ObjectCatalog (content/objects). */
  readonly objectId: string;
  /** Exact visual declared by the object archetype. Authored maps never randomize art. */
  readonly visualId: string;
  readonly x: number;
  readonly y: number;
  /** Authored initial state; runtime state is saved separately by mapId + instanceId. */
  readonly initialState?: Readonly<Record<string, unknown>>;
}

export interface MapEnemySpawn {
  /** Enemy type key from enemies/library/EnemyTypes.ts. */
  readonly type: string;
  readonly weight: number;
  readonly maxAlive?: number;
}

export interface MapEnemySafeZone {
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;
}

export type MapEnemyAreaShape = 'circle' | 'rectangle';

export type MapEnemyAreaPerimeter =
  | {
    readonly shape: 'circle';
    /** Circle center in world pixels. */
    readonly x: number;
    readonly y: number;
    readonly radius: number;
  }
  | {
    readonly shape: 'rectangle';
    /** Rectangle top-left in world pixels. */
    readonly x: number;
    readonly y: number;
    readonly w: number;
    readonly h: number;
  };

export interface MapEnemySpawnArea {
  /** Stable editor-generated identity, unique within the map. */
  readonly id: string;
  /** The perimeter where enemies spawn and are allowed to settle. */
  readonly stayPerimeter: MapEnemyAreaPerimeter;
  /** The larger activation/persecution perimeter around the stay perimeter. */
  readonly pursuePerimeter: MapEnemyAreaPerimeter;
  readonly enemies: readonly MapEnemySpawn[];
  readonly intervalMs: number;
  readonly maxPopulation: number;
}

export interface MapSpawns {
  readonly enemies: readonly MapEnemySpawn[];
  readonly radius: { readonly min: number; readonly max: number };
  readonly intervalMs: number;
  readonly maxPopulation: number;
  /** @deprecated Prefer map-level enemySafeZones so peaceful maps can define them too. */
  readonly safeZones: readonly MapEnemySafeZone[];
}

export interface MapExit {
  readonly zone: MapZone;
  /** Target AreaId (world/Area.ts owns the world graph). */
  readonly to: string;
  /** Entry point name in the target map's player.entries. */
  readonly entry: string;
}

export interface MapFile {
  readonly version: typeof MAP_FORMAT_VERSION;
  readonly mapId: MapId;
  readonly tileSize: number;
  readonly size: { readonly columns: number; readonly rows: number };
  readonly layers: readonly MapLayer[];
  readonly objects: readonly MapObjectInstance[];
  readonly player: {
    readonly spawn: MapPoint;
    readonly entries: Partial<Readonly<Record<MapDirection, MapPoint>>>;
  };
  readonly exits?: readonly MapExit[];
  /** Areas enemies cannot enter or spawn in, independent of spawn configuration. */
  readonly enemySafeZones?: readonly MapEnemySafeZone[];
  /** Authored enemy camps. When non-empty, runtime spawning uses these areas instead of legacy spawns. */
  readonly enemySpawnAreas?: readonly MapEnemySpawnArea[];
  readonly spawns?: MapSpawns;
}

export class MapValidationError extends Error {
  constructor(
    public readonly mapLabel: string,
    public readonly issues: readonly string[],
  ) {
    super(`Invalid map '${mapLabel}':\n  - ${issues.join('\n  - ')}`);
    this.name = 'MapValidationError';
  }
}

const MAP_ID_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const DIRECTIONS: readonly string[] = ['north', 'east', 'south', 'west'];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isPositiveInt(value: unknown): value is number {
  return Number.isInteger(value) && (value as number) > 0;
}

function isNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isIntegerNumber(value: unknown): value is number {
  return isNumber(value) && Number.isInteger(value);
}

function validatePoint(value: unknown, path: string, issues: string[]): void {
  if (!isRecord(value) || !isNumber(value.x) || !isNumber(value.y)) {
    issues.push(`${path}: expected { x, y } numbers`);
  }
}

function validateZone(value: unknown, path: string, issues: string[]): void {
  if (!isRecord(value) || !isNumber(value.x) || !isNumber(value.y)
    || !isPositiveInt(value.w) || !isPositiveInt(value.h)) {
    issues.push(`${path}: expected { x, y, w, h } with positive integer w/h`);
  }
}

function validateEnemyPerimeter(
  value: unknown,
  path: string,
  issues: string[],
  pixelWidth: number | null,
  pixelHeight: number | null,
): MapEnemyAreaPerimeter | undefined {
  if (!isRecord(value) || (value.shape !== 'circle' && value.shape !== 'rectangle')) {
    issues.push(`${path}: expected a circle or rectangle perimeter`);
    return undefined;
  }

  if (!isIntegerNumber(value.x) || !isIntegerNumber(value.y)) {
    issues.push(`${path}: expected integer x/y`);
    return undefined;
  }

  const perimeter: MapEnemyAreaPerimeter = value.shape === 'circle'
    ? { shape: 'circle', x: value.x, y: value.y, radius: value.radius as number }
    : {
      shape: 'rectangle',
      x: value.x,
      y: value.y,
      w: value.w as number,
      h: value.h as number,
    };

  if (perimeter.shape === 'circle') {
    if (!isIntegerNumber(value.radius) || value.radius <= 0) {
      issues.push(`${path}.radius: expected positive integer`);
      return undefined;
    }
  } else if (!isIntegerNumber(value.w) || value.w <= 0 || !isIntegerNumber(value.h) || value.h <= 0) {
    issues.push(`${path}: expected positive integer w/h`);
    return undefined;
  }

  if (pixelWidth !== null && pixelHeight !== null) {
    const minX = perimeter.shape === 'circle' ? perimeter.x - perimeter.radius : perimeter.x;
    const minY = perimeter.shape === 'circle' ? perimeter.y - perimeter.radius : perimeter.y;
    const maxX = perimeter.shape === 'circle' ? perimeter.x + perimeter.radius : perimeter.x + perimeter.w;
    const maxY = perimeter.shape === 'circle' ? perimeter.y + perimeter.radius : perimeter.y + perimeter.h;
    if (minX < 0 || minY < 0 || maxX > pixelWidth || maxY > pixelHeight) {
      issues.push(`${path}: perimeter must fit inside ${pixelWidth}x${pixelHeight} map bounds`);
    }
  }

  return perimeter;
}

function validateEnemyEntries(value: unknown, path: string, issues: string[]): void {
  if (!Array.isArray(value) || value.length === 0) {
    issues.push(`${path}: expected a non-empty array`);
    return;
  }
  value.forEach((enemy, index) => {
    const entryPath = `${path}[${index}]`;
    if (!isRecord(enemy)) {
      issues.push(`${entryPath}: expected an object`);
      return;
    }
    if (typeof enemy.type !== 'string' || enemy.type.length === 0) {
      issues.push(`${entryPath}.type: required non-empty string (EnemyTypes key)`);
    }
    if (!isPositiveInt(enemy.weight)) {
      issues.push(`${entryPath}.weight: expected positive integer`);
    }
    if (enemy.maxAlive !== undefined && !isPositiveInt(enemy.maxAlive)) {
      issues.push(`${entryPath}.maxAlive: expected positive integer`);
    }
  });
}

/**
 * Structural validation + cast. Throws MapValidationError listing every
 * issue found, each prefixed with its field path.
 */
export function parseMapFile(data: unknown, mapLabel = 'unknown'): MapFile {
  const issues: string[] = [];

  if (!isRecord(data)) {
    throw new MapValidationError(mapLabel, ['root: expected an object']);
  }

  if (data.version !== MAP_FORMAT_VERSION) {
    issues.push(`version: expected ${MAP_FORMAT_VERSION}, got ${JSON.stringify(data.version)}`);
  }

  if (typeof data.mapId !== 'string' || !MAP_ID_PATTERN.test(data.mapId)) {
    issues.push(`mapId: expected kebab-case string (e.g. level-1)`);
  }

  if (!isPositiveInt(data.tileSize)) {
    issues.push(`tileSize: expected positive integer`);
  }

  const size = data.size;
  const columns = isRecord(size) && isPositiveInt(size.columns) ? size.columns : null;
  const rows = isRecord(size) && isPositiveInt(size.rows) ? size.rows : null;
  if (columns === null || rows === null) {
    issues.push(`size: expected { columns, rows } positive integers`);
  }

  const pixelWidth = columns !== null && isPositiveInt(data.tileSize) ? columns * data.tileSize : null;
  const pixelHeight = rows !== null && isPositiveInt(data.tileSize) ? rows * data.tileSize : null;

  // ── layers ──
  if (!Array.isArray(data.layers) || data.layers.length === 0) {
    issues.push(`layers: expected a non-empty array`);
  } else {
    const layerIds = new Set<string>();

    data.layers.forEach((layer, index) => {
      const path = `layers[${index}]`;

      if (!isRecord(layer)) {
        issues.push(`${path}: expected an object`);
        return;
      }

      if (typeof layer.id !== 'string' || layer.id.length === 0) {
        issues.push(`${path}.id: required non-empty string`);
      } else if (layerIds.has(layer.id)) {
        issues.push(`${path}.id: duplicate layer id '${layer.id}'`);
      } else {
        layerIds.add(layer.id);
      }

      if (layer.encoding !== 'legend-chars-v1') {
        issues.push(`${path}.encoding: expected 'legend-chars-v1'`);
      }

      const legend = isRecord(layer.legend) ? layer.legend : null;
      if (legend === null) {
        issues.push(`${path}.legend: expected an object mapping char -> tile ID`);
      } else {
        for (const [char, tileId] of Object.entries(legend)) {
          if (char.length !== 1) {
            issues.push(`${path}.legend: key '${char}' must be a single character`);
          }
          if (typeof tileId !== 'string' || tileId.length === 0) {
            issues.push(`${path}.legend['${char}']: tile ID must be a non-empty string`);
          }
        }
      }

      if (!Array.isArray(layer.rows)) {
        issues.push(`${path}.rows: expected an array of strings`);
      } else {
        if (rows !== null && layer.rows.length !== rows) {
          issues.push(`${path}.rows: expected ${rows} rows, got ${layer.rows.length}`);
        }

        layer.rows.forEach((row, rowIndex) => {
          if (typeof row !== 'string') {
            issues.push(`${path}.rows[${rowIndex}]: expected a string`);
            return;
          }
          if (columns !== null && row.length !== columns) {
            issues.push(`${path}.rows[${rowIndex}]: expected ${columns} chars, got ${row.length}`);
          }
          if (legend !== null) {
            for (const char of row) {
              if (!(char in legend)) {
                issues.push(`${path}.rows[${rowIndex}]: char '${char}' missing from legend`);
                break;
              }
            }
          }
        });
      }
    });
  }

  // ── objects ──
  if (!Array.isArray(data.objects)) {
    issues.push(`objects: expected an array`);
  } else {
    const instanceIds = new Set<string>();

    data.objects.forEach((object, index) => {
      const path = `objects[${index}]`;

      if (!isRecord(object)) {
        issues.push(`${path}: expected an object`);
        return;
      }

      if (typeof object.instanceId !== 'string' || object.instanceId.length === 0) {
        issues.push(`${path}.instanceId: required non-empty string`);
      } else if (instanceIds.has(object.instanceId)) {
        issues.push(`${path}.instanceId: duplicate '${object.instanceId}'`);
      } else {
        instanceIds.add(object.instanceId);
      }

      if (typeof object.objectId !== 'string' || object.objectId.length === 0) {
        issues.push(`${path}.objectId: required non-empty string (archetype ID)`);
      }

      if (typeof object.visualId !== 'string' || object.visualId.length === 0) {
        issues.push(`${path}.visualId: required non-empty string (authored visual ID)`);
      }

      if (!isNumber(object.x) || !isNumber(object.y)) {
        issues.push(`${path}: expected numeric x/y`);
      } else if (pixelWidth !== null && pixelHeight !== null
        && (object.x < 0 || object.x > pixelWidth || object.y < 0 || object.y > pixelHeight)) {
        issues.push(`${path}: position (${object.x}, ${object.y}) outside map bounds ${pixelWidth}x${pixelHeight}`);
      }

      if (object.initialState !== undefined && !isRecord(object.initialState)) {
        issues.push(`${path}.initialState: expected an object`);
      }
    });
  }

  // ── player ──
  if (!isRecord(data.player)) {
    issues.push(`player: expected an object with spawn and entries`);
  } else {
    validatePoint(data.player.spawn, 'player.spawn', issues);

    if (!isRecord(data.player.entries)) {
      issues.push(`player.entries: expected an object keyed by direction`);
    } else {
      for (const [direction, point] of Object.entries(data.player.entries)) {
        if (!DIRECTIONS.includes(direction)) {
          issues.push(`player.entries: unknown direction '${direction}'`);
          continue;
        }
        validatePoint(point, `player.entries.${direction}`, issues);
      }
    }
  }

  // ── exits ──
  if (data.exits !== undefined) {
    if (!Array.isArray(data.exits)) {
      issues.push(`exits: expected an array`);
    } else {
      data.exits.forEach((exit, index) => {
        const path = `exits[${index}]`;

        if (!isRecord(exit)) {
          issues.push(`${path}: expected an object`);
          return;
        }

        validateZone(exit.zone, `${path}.zone`, issues);

        if (typeof exit.to !== 'string' || exit.to.length === 0) {
          issues.push(`${path}.to: required non-empty string (target area ID)`);
        }
        if (typeof exit.entry !== 'string' || exit.entry.length === 0) {
          issues.push(`${path}.entry: required non-empty string (target entry point name)`);
        }
      });
    }
  }

  // ── spawns ──
  if (data.spawns !== undefined) {
    const spawns = data.spawns;

    if (!isRecord(spawns)) {
      issues.push(`spawns: expected an object`);
    } else {
      if (!Array.isArray(spawns.enemies) || spawns.enemies.length === 0) {
        issues.push(`spawns.enemies: expected a non-empty array`);
      } else {
        spawns.enemies.forEach((enemy, index) => {
          const path = `spawns.enemies[${index}]`;

          if (!isRecord(enemy)) {
            issues.push(`${path}: expected an object`);
            return;
          }
          if (typeof enemy.type !== 'string' || enemy.type.length === 0) {
            issues.push(`${path}.type: required non-empty string (EnemyTypes key)`);
          }
          if (!isNumber(enemy.weight) || enemy.weight <= 0) {
            issues.push(`${path}.weight: expected number > 0`);
          }
          if (enemy.maxAlive !== undefined && !isPositiveInt(enemy.maxAlive)) {
            issues.push(`${path}.maxAlive: expected positive integer`);
          }
        });
      }

      const radius = spawns.radius;
      if (!isRecord(radius) || !isNumber(radius.min) || !isNumber(radius.max)
        || radius.min < 0 || radius.max <= radius.min) {
        issues.push(`spawns.radius: expected { min, max } with 0 <= min < max`);
      }

      if (!isNumber(spawns.intervalMs) || spawns.intervalMs <= 0) {
        issues.push(`spawns.intervalMs: expected number > 0`);
      }
      if (!isPositiveInt(spawns.maxPopulation)) {
        issues.push(`spawns.maxPopulation: expected positive integer`);
      }
      if (!Array.isArray(spawns.safeZones)) {
        issues.push(`spawns.safeZones: expected an array (may be empty)`);
      } else {
        spawns.safeZones.forEach((zone, index) => {
          if (!isRecord(zone) || !isNumber(zone.x) || !isNumber(zone.y)
            || !isPositiveInt(zone.w) || !isPositiveInt(zone.h)) {
            issues.push(`spawns.safeZones[${index}]: expected { x, y, w, h } with positive integer w/h`);
          } else if (pixelWidth !== null && pixelHeight !== null
            && (zone.x < 0 || zone.y < 0 || zone.x + zone.w > pixelWidth || zone.y + zone.h > pixelHeight)) {
            issues.push(`spawns.safeZones[${index}]: rectangle must fit inside ${pixelWidth}x${pixelHeight} map bounds`);
          }
        });
      }
    }
  }

  if (data.enemySafeZones !== undefined) {
    if (!Array.isArray(data.enemySafeZones)) {
      issues.push(`enemySafeZones: expected an array (may be empty)`);
    } else {
      data.enemySafeZones.forEach((zone, index) => {
        if (!isRecord(zone) || !isNumber(zone.x) || !isNumber(zone.y)
          || !isPositiveInt(zone.w) || !isPositiveInt(zone.h)) {
          issues.push(`enemySafeZones[${index}]: expected { x, y, w, h } with positive integer w/h`);
        } else if (pixelWidth !== null && pixelHeight !== null
          && (zone.x < 0 || zone.y < 0 || zone.x + zone.w > pixelWidth || zone.y + zone.h > pixelHeight)) {
          issues.push(`enemySafeZones[${index}]: rectangle must fit inside ${pixelWidth}x${pixelHeight} map bounds`);
        }
      });
    }
  }

  if (data.enemySpawnAreas !== undefined) {
    if (!Array.isArray(data.enemySpawnAreas)) {
      issues.push(`enemySpawnAreas: expected an array (may be empty)`);
    } else {
      const areaIds = new Set<string>();
      data.enemySpawnAreas.forEach((area, index) => {
        const path = `enemySpawnAreas[${index}]`;
        if (!isRecord(area)) {
          issues.push(`${path}: expected an object`);
          return;
        }
        if (typeof area.id !== 'string' || area.id.length === 0) {
          issues.push(`${path}.id: required non-empty stable ID`);
        } else if (areaIds.has(area.id)) {
          issues.push(`${path}.id: duplicate '${area.id}'`);
        } else {
          areaIds.add(area.id);
        }

        const stay = validateEnemyPerimeter(area.stayPerimeter, `${path}.stayPerimeter`, issues, pixelWidth, pixelHeight);
        const pursue = validateEnemyPerimeter(area.pursuePerimeter, `${path}.pursuePerimeter`, issues, pixelWidth, pixelHeight);
        if (stay && pursue) {
          if (stay.shape !== pursue.shape) {
            issues.push(`${path}: stayPerimeter and pursuePerimeter must use the same shape`);
          } else if (stay.shape === 'circle' && pursue.shape === 'circle') {
            if (Math.hypot(stay.x - pursue.x, stay.y - pursue.y) + stay.radius > pursue.radius) {
              issues.push(`${path}: stayPerimeter must fit inside pursuePerimeter`);
            }
          } else if (stay.shape === 'rectangle' && pursue.shape === 'rectangle'
            && (stay.x < pursue.x || stay.y < pursue.y
              || stay.x + stay.w > pursue.x + pursue.w
              || stay.y + stay.h > pursue.y + pursue.h)) {
            issues.push(`${path}: stayPerimeter must fit inside pursuePerimeter`);
          }
        }

        validateEnemyEntries(area.enemies, `${path}.enemies`, issues);
        if (!isPositiveInt(area.intervalMs)) {
          issues.push(`${path}.intervalMs: expected positive integer`);
        }
        if (!isPositiveInt(area.maxPopulation)) {
          issues.push(`${path}.maxPopulation: expected positive integer`);
        }
      });
    }
  }

  if (issues.length > 0) {
    throw new MapValidationError(mapLabel, issues);
  }

  return data as unknown as MapFile;
}
