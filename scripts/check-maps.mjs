#!/usr/bin/env node
/**
 * maps:check — validates authored maps in src/game/content/maps/.
 *
 * Structural validation at check-time (mapFormat.ts re-asserts at load-time):
 *   1. Every *.json map parses; version is 1; mapId is kebab-case and unique
 *      across the repository.
 *   2. Layer rows match size; every row char is defined in the layer legend.
 *   3. instanceId values are unique within a map; object positions are in
 *      bounds.
 *   4. player spawn/entries, exits, legacy spawns, and authored enemy areas
 *      are well-formed.
 *
 * Object references and archetype-owned gameplay overrides are also checked
 * against the authored object definitions.
 *
 * Usage: `node scripts/check-maps.mjs [mapsDir]` (mapsDir defaults to
 * src/game/content/maps; overridable for fixture testing).
 */

import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const characterRoot = join(repoRoot, 'src', 'game', 'content', 'characters');
const objectRoot = join(repoRoot, 'src', 'game', 'content', 'objects');
const enemyFiles = [];
function collectEnemyFiles(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const file = join(directory, entry.name);
    if (entry.isDirectory()) collectEnemyFiles(file);
    else if (entry.name === 'character.json') enemyFiles.push(file);
  }
}
collectEnemyFiles(characterRoot);
const activeEnemyIds = new Set(enemyFiles.map((file) => JSON.parse(readFileSync(file, 'utf8'))).filter((value) => value.kind === 'enemy').map((value) => value.characterId));
const objectDefinitions = new Map();
function collectObjectDefinitions(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const file = join(directory, entry.name);
    if (entry.isDirectory()) collectObjectDefinitions(file);
    else if (entry.isFile() && entry.name.endsWith('.json') && entry.name !== 'objects.schema.json') {
      const definition = JSON.parse(readFileSync(file, 'utf8'));
      if (typeof definition.objectId === 'string') objectDefinitions.set(definition.objectId, definition);
    }
  }
}
collectObjectDefinitions(objectRoot);
const mapsDir = process.argv[2]
  ? resolve(process.cwd(), process.argv[2])
  : join(repoRoot, 'src', 'game', 'content', 'maps');

const MAP_ID_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const DIRECTIONS = new Set(['north', 'east', 'south', 'west']);

const errors = [];
const fail = (label, field, message) => errors.push(`[${label}] ${field}: ${message}`);

const isRecord = (v) => typeof v === 'object' && v !== null && !Array.isArray(v);
const isPositiveInt = (v) => Number.isInteger(v) && v > 0;
const isNumber = (v) => typeof v === 'number' && Number.isFinite(v);
const isIntegerNumber = (v) => isNumber(v) && Number.isInteger(v);

function validateObjectInitialState(object, definition, path, label) {
  if (object.initialState === undefined) return;
  if (!isRecord(object.initialState)) {
    fail(label, `${path}.initialState`, 'expected an object');
    return;
  }
  const state = object.initialState;
  const allowed = definition.collectible
    ? new Set(['quantity', 'remaining'])
    : definition.resourceNode
      ? new Set(['health', 'dropObjectId', 'dropVisualId', 'dropPieces'])
      : definition.destructible
        ? new Set(['health'])
      : new Set();
  for (const key of Object.keys(state)) {
    if (!allowed.has(key)) fail(label, `${path}.initialState.${key}`, `not supported by '${object.objectId}'`);
  }
  if (definition.collectible) {
    const quantity = state.quantity ?? definition.collectible.quantity;
    if (!Number.isInteger(quantity) || quantity < 1) fail(label, `${path}.initialState.quantity`, 'expected integer >= 1');
    if (state.remaining !== undefined && (!Number.isInteger(state.remaining) || state.remaining < 0 || state.remaining > quantity)) {
      fail(label, `${path}.initialState.remaining`, 'expected integer from 0 through starting quantity');
    }
    return;
  }
  if (definition.destructible) {
    if (state.health !== undefined && (!Number.isInteger(state.health) || state.health < 0 || state.health > definition.destructible.health)) {
      fail(label, `${path}.initialState.health`, `expected integer from 0 through ${definition.destructible.health}`);
    }
    return;
  }
  if (!definition.resourceNode) {
    if (Object.keys(state).length > 0) fail(label, `${path}.initialState`, 'object has no supported gameplay overrides');
    return;
  }
  if (state.health !== undefined && (!Number.isInteger(state.health) || state.health < 0 || state.health > definition.resourceNode.health)) {
    fail(label, `${path}.initialState.health`, `expected integer from 0 through ${definition.resourceNode.health}`);
  }
  const dropObjectId = state.dropObjectId ?? definition.resourceNode.drop.objectId;
  const dropDefinition = objectDefinitions.get(dropObjectId);
  if (!dropDefinition?.collectible) fail(label, `${path}.initialState.dropObjectId`, 'must reference a collectible object');
  const dropVisualId = state.dropVisualId
    ?? (state.dropObjectId !== undefined
      ? dropDefinition?.variants?.[0]?.frames?.[0]?.visualId
      : definition.resourceNode.drop.visualId);
  if (dropDefinition && !dropDefinition.variants?.some((variant) => variant.frames?.some((frame) => frame.visualId === dropVisualId))) {
    fail(label, `${path}.initialState.dropVisualId`, `unknown visual '${dropVisualId}' for '${dropObjectId}'`);
  }
  if (state.dropPieces !== undefined && (!Number.isInteger(state.dropPieces) || state.dropPieces < 1)) {
    fail(label, `${path}.initialState.dropPieces`, 'expected integer >= 1');
  }
}

function checkPoint(value, path, label) {
  if (!isRecord(value) || !isNumber(value.x) || !isNumber(value.y)) {
    fail(label, path, 'expected { x, y } numbers');
  }
}

function perimeterBounds(perimeter) {
  return perimeter.shape === 'circle'
    ? {
      minX: perimeter.x - perimeter.radius,
      minY: perimeter.y - perimeter.radius,
      maxX: perimeter.x + perimeter.radius,
      maxY: perimeter.y + perimeter.radius,
    }
    : {
      minX: perimeter.x,
      minY: perimeter.y,
      maxX: perimeter.x + perimeter.w,
      maxY: perimeter.y + perimeter.h,
    };
}

function validateEnemyPerimeter(value, path, label, pixelWidth, pixelHeight) {
  if (!isRecord(value) || (value.shape !== 'circle' && value.shape !== 'rectangle')) {
    fail(label, path, 'expected a circle or rectangle perimeter');
    return null;
  }
  if (!isIntegerNumber(value.x) || !isIntegerNumber(value.y)) {
    fail(label, path, 'expected integer x/y');
    return null;
  }
  if (value.shape === 'circle') {
    if (!isIntegerNumber(value.radius) || value.radius <= 0) {
      fail(label, `${path}.radius`, 'expected positive integer');
      return null;
    }
  } else if (!isIntegerNumber(value.w) || value.w <= 0 || !isIntegerNumber(value.h) || value.h <= 0) {
    fail(label, path, 'expected positive integer w/h');
    return null;
  }
  const bounds = perimeterBounds(value);
  if (pixelWidth !== null && pixelHeight !== null
    && (bounds.minX < 0 || bounds.minY < 0 || bounds.maxX > pixelWidth || bounds.maxY > pixelHeight)) {
    fail(label, path, `perimeter must fit inside ${pixelWidth}x${pixelHeight} map bounds`);
  }
  return value;
}

function validateEnemyEntries(value, path, label) {
  if (!Array.isArray(value) || value.length === 0) {
    fail(label, path, 'expected a non-empty array');
    return;
  }
  value.forEach((enemy, index) => {
    const enemyPath = `${path}[${index}]`;
    if (!isRecord(enemy)) {
      fail(label, enemyPath, 'expected an object');
      return;
    }
    if (typeof enemy.type !== 'string' || enemy.type.length === 0) {
      fail(label, `${enemyPath}.type`, 'required non-empty string (EnemyTypes key)');
    } else if (!activeEnemyIds.has(enemy.type)) {
      fail(label, `${enemyPath}.type`, `unknown active enemy ID '${enemy.type}'`);
    }
    if (!isPositiveInt(enemy.weight)) fail(label, `${enemyPath}.weight`, 'expected positive integer');
    if (enemy.maxAlive !== undefined && !isPositiveInt(enemy.maxAlive)) {
      fail(label, `${enemyPath}.maxAlive`, 'expected positive integer');
    }
  });
}

function validateMap(data, label) {
  if (!isRecord(data)) {
    fail(label, 'root', 'expected an object');
    return null;
  }

  if (data.version !== 1) {
    fail(label, 'version', `expected 1, got ${JSON.stringify(data.version)}`);
  }

  let mapId = null;
  if (typeof data.mapId !== 'string' || !MAP_ID_PATTERN.test(data.mapId)) {
    fail(label, 'mapId', 'expected kebab-case string (e.g. meadow-crossing)');
  } else {
    mapId = data.mapId;
  }

  if (!isPositiveInt(data.tileSize)) {
    fail(label, 'tileSize', 'expected positive integer');
  }

  const size = data.size;
  const columns = isRecord(size) && isPositiveInt(size.columns) ? size.columns : null;
  const rows = isRecord(size) && isPositiveInt(size.rows) ? size.rows : null;
  if (columns === null || rows === null) {
    fail(label, 'size', 'expected { columns, rows } positive integers');
  }

  const pixelWidth = columns !== null && isPositiveInt(data.tileSize) ? columns * data.tileSize : null;
  const pixelHeight = rows !== null && isPositiveInt(data.tileSize) ? rows * data.tileSize : null;

  // ── layers ──
  if (!Array.isArray(data.layers) || data.layers.length === 0) {
    fail(label, 'layers', 'expected a non-empty array');
  } else {
    const layerIds = new Set();

    data.layers.forEach((layer, index) => {
      const path = `layers[${index}]`;
      if (!isRecord(layer)) {
        fail(label, path, 'expected an object');
        return;
      }

      if (typeof layer.id !== 'string' || layer.id.length === 0) {
        fail(label, `${path}.id`, 'required non-empty string');
      } else if (layerIds.has(layer.id)) {
        fail(label, `${path}.id`, `duplicate layer id '${layer.id}'`);
      } else {
        layerIds.add(layer.id);
      }

      if (layer.encoding !== 'legend-chars-v1') {
        fail(label, `${path}.encoding`, `expected 'legend-chars-v1'`);
      }

      const legend = isRecord(layer.legend) ? layer.legend : null;
      if (legend === null) {
        fail(label, `${path}.legend`, 'expected an object mapping char -> tile ID');
      } else {
        for (const [char, tileId] of Object.entries(legend)) {
          if (char.length !== 1) fail(label, `${path}.legend`, `key '${char}' must be a single character`);
          if (typeof tileId !== 'string' || tileId.length === 0) {
            fail(label, `${path}.legend['${char}']`, 'tile ID must be a non-empty string');
          }
        }
      }

      if (!Array.isArray(layer.rows)) {
        fail(label, `${path}.rows`, 'expected an array of strings');
      } else {
        if (rows !== null && layer.rows.length !== rows) {
          fail(label, `${path}.rows`, `expected ${rows} rows, got ${layer.rows.length}`);
        }
        layer.rows.forEach((row, rowIndex) => {
          if (typeof row !== 'string') {
            fail(label, `${path}.rows[${rowIndex}]`, 'expected a string');
            return;
          }
          if (columns !== null && row.length !== columns) {
            fail(label, `${path}.rows[${rowIndex}]`, `expected ${columns} chars, got ${row.length}`);
          }
          if (legend !== null && [...row].some((char) => !(char in legend))) {
            fail(label, `${path}.rows[${rowIndex}]`, 'contains a char missing from legend');
          }
        });
      }
    });
  }

  // ── objects ──
  if (!Array.isArray(data.objects)) {
    fail(label, 'objects', 'expected an array');
  } else {
    const instanceIds = new Set();

    data.objects.forEach((object, index) => {
      const path = `objects[${index}]`;
      if (!isRecord(object)) {
        fail(label, path, 'expected an object');
        return;
      }

      if (typeof object.instanceId !== 'string' || object.instanceId.length === 0) {
        fail(label, `${path}.instanceId`, 'required non-empty string');
      } else if (instanceIds.has(object.instanceId)) {
        fail(label, `${path}.instanceId`, `duplicate '${object.instanceId}'`);
      } else {
        instanceIds.add(object.instanceId);
      }

      if (typeof object.objectId !== 'string' || object.objectId.length === 0) {
        fail(label, `${path}.objectId`, 'required non-empty string (archetype ID)');
      } else if (!objectDefinitions.has(object.objectId)) {
        fail(label, `${path}.objectId`, `unknown object '${object.objectId}'`);
      }
      if (typeof object.visualId !== 'string' || object.visualId.length === 0) {
        fail(label, `${path}.visualId`, 'required non-empty string (authored visual ID)');
      } else {
        const definition = objectDefinitions.get(object.objectId);
        if (definition && !definition.variants?.some((variant) => variant.frames?.some((frame) => frame.visualId === object.visualId))) {
          fail(label, `${path}.visualId`, `unknown visual '${object.visualId}' for '${object.objectId}'`);
        }
      }

      if (!isNumber(object.x) || !isNumber(object.y)) {
        fail(label, path, 'expected numeric x/y');
      } else if (pixelWidth !== null && pixelHeight !== null
        && (object.x < 0 || object.x > pixelWidth || object.y < 0 || object.y > pixelHeight)) {
        fail(label, path, `position (${object.x}, ${object.y}) outside map bounds ${pixelWidth}x${pixelHeight}`);
      }

      const definition = objectDefinitions.get(object.objectId);
      if (definition) validateObjectInitialState(object, definition, path, label);
    });
  }

  // ── player ──
  if (!isRecord(data.player)) {
    fail(label, 'player', 'expected an object with spawn and entries');
  } else {
    checkPoint(data.player.spawn, 'player.spawn', label);

    if (!isRecord(data.player.entries)) {
      fail(label, 'player.entries', 'expected an object keyed by direction');
    } else {
      for (const [direction, point] of Object.entries(data.player.entries)) {
        if (!DIRECTIONS.has(direction)) {
          fail(label, 'player.entries', `unknown direction '${direction}'`);
          continue;
        }
        checkPoint(point, `player.entries.${direction}`, label);
      }
    }
  }

  // ── exits ──
  if (data.exits !== undefined) {
    if (!Array.isArray(data.exits)) {
      fail(label, 'exits', 'expected an array');
    } else {
      data.exits.forEach((exit, index) => {
        const path = `exits[${index}]`;
        if (!isRecord(exit)) {
          fail(label, path, 'expected an object');
          return;
        }

        const zone = exit.zone;
        if (!isRecord(zone) || !isNumber(zone.x) || !isNumber(zone.y)
          || !isPositiveInt(zone.w) || !isPositiveInt(zone.h)) {
          fail(label, `${path}.zone`, 'expected { x, y, w, h } with positive integer w/h');
        }
        if (typeof exit.to !== 'string' || exit.to.length === 0) {
          fail(label, `${path}.to`, 'required non-empty string (target area ID)');
        }
        if (typeof exit.entry !== 'string' || exit.entry.length === 0) {
          fail(label, `${path}.entry`, 'required non-empty string (target entry point name)');
        }
      });
    }
  }

  // ── spawns ──
  if (data.spawns !== undefined) {
    const spawns = data.spawns;

    if (!isRecord(spawns)) {
      fail(label, 'spawns', 'expected an object');
    } else {
      if (!Array.isArray(spawns.enemies) || spawns.enemies.length === 0) {
        fail(label, 'spawns.enemies', 'expected a non-empty array');
      } else {
        spawns.enemies.forEach((enemy, index) => {
          const path = `spawns.enemies[${index}]`;
          if (!isRecord(enemy)) {
            fail(label, path, 'expected an object');
            return;
          }
          if (typeof enemy.type !== 'string' || enemy.type.length === 0) {
            fail(label, `${path}.type`, 'required non-empty string (EnemyTypes key)');
          } else if (!activeEnemyIds.has(enemy.type)) {
            fail(label, `${path}.type`, `unknown active enemy ID '${enemy.type}'`);
          }
          if (!isNumber(enemy.weight) || enemy.weight <= 0) {
            fail(label, `${path}.weight`, 'expected number > 0');
          }
          if (enemy.maxAlive !== undefined && !isPositiveInt(enemy.maxAlive)) {
            fail(label, `${path}.maxAlive`, 'expected positive integer');
          }
        });
      }

      const radius = spawns.radius;
      if (!isRecord(radius) || !isNumber(radius.min) || !isNumber(radius.max)
        || radius.min < 0 || radius.max <= radius.min) {
        fail(label, 'spawns.radius', 'expected { min, max } with 0 <= min < max');
      }

      if (!isNumber(spawns.intervalMs) || spawns.intervalMs <= 0) {
        fail(label, 'spawns.intervalMs', 'expected number > 0');
      }
      if (!isPositiveInt(spawns.maxPopulation)) {
        fail(label, 'spawns.maxPopulation', 'expected positive integer');
      }
      if (!Array.isArray(spawns.safeZones)) {
        fail(label, 'spawns.safeZones', 'expected an array (may be empty)');
      } else {
        spawns.safeZones.forEach((zone, index) => {
          if (!isRecord(zone) || !isNumber(zone.x) || !isNumber(zone.y)
            || !isPositiveInt(zone.w) || !isPositiveInt(zone.h)) {
            fail(label, `spawns.safeZones[${index}]`, 'expected { x, y, w, h } with positive integer w/h');
          } else if (pixelWidth !== null && pixelHeight !== null
            && (zone.x < 0 || zone.y < 0 || zone.x + zone.w > pixelWidth || zone.y + zone.h > pixelHeight)) {
            fail(label, `spawns.safeZones[${index}]`, `rectangle must fit inside ${pixelWidth}x${pixelHeight} map bounds`);
          }
        });
      }
    }
  }

  if (data.enemySafeZones !== undefined) {
    if (!Array.isArray(data.enemySafeZones)) {
      fail(label, 'enemySafeZones', 'expected an array (may be empty)');
    } else {
      data.enemySafeZones.forEach((zone, index) => {
        if (!isRecord(zone) || !isNumber(zone.x) || !isNumber(zone.y)
          || !isPositiveInt(zone.w) || !isPositiveInt(zone.h)) {
          fail(label, `enemySafeZones[${index}]`, 'expected { x, y, w, h } with positive integer w/h');
        } else if (pixelWidth !== null && pixelHeight !== null
          && (zone.x < 0 || zone.y < 0 || zone.x + zone.w > pixelWidth || zone.y + zone.h > pixelHeight)) {
          fail(label, `enemySafeZones[${index}]`, `rectangle must fit inside ${pixelWidth}x${pixelHeight} map bounds`);
        }
      });
    }
  }

  if (data.enemySpawnAreas !== undefined) {
    if (!Array.isArray(data.enemySpawnAreas)) {
      fail(label, 'enemySpawnAreas', 'expected an array (may be empty)');
    } else {
      const areaIds = new Set();
      data.enemySpawnAreas.forEach((area, index) => {
        const path = `enemySpawnAreas[${index}]`;
        if (!isRecord(area)) {
          fail(label, path, 'expected an object');
          return;
        }
        if (typeof area.id !== 'string' || area.id.length === 0) {
          fail(label, `${path}.id`, 'required non-empty stable ID');
        } else if (areaIds.has(area.id)) {
          fail(label, `${path}.id`, `duplicate '${area.id}'`);
        } else {
          areaIds.add(area.id);
        }

        const stay = validateEnemyPerimeter(area.stayPerimeter, `${path}.stayPerimeter`, label, pixelWidth, pixelHeight);
        const pursue = validateEnemyPerimeter(area.pursuePerimeter, `${path}.pursuePerimeter`, label, pixelWidth, pixelHeight);
        if (stay && pursue) {
          if (stay.shape !== pursue.shape) {
            fail(label, path, 'stayPerimeter and pursuePerimeter must use the same shape');
          } else if (stay.shape === 'circle' && pursue.shape === 'circle') {
            if (Math.hypot(stay.x - pursue.x, stay.y - pursue.y) + stay.radius > pursue.radius) {
              fail(label, path, 'stayPerimeter must fit inside pursuePerimeter');
            }
          } else if (stay.shape === 'rectangle' && pursue.shape === 'rectangle'
            && (stay.x < pursue.x || stay.y < pursue.y
              || stay.x + stay.w > pursue.x + pursue.w
              || stay.y + stay.h > pursue.y + pursue.h)) {
            fail(label, path, 'stayPerimeter must fit inside pursuePerimeter');
          }
        }
        validateEnemyEntries(area.enemies, `${path}.enemies`, label);
        if (!isPositiveInt(area.intervalMs)) fail(label, `${path}.intervalMs`, 'expected positive integer');
        if (!isPositiveInt(area.maxPopulation)) fail(label, `${path}.maxPopulation`, 'expected positive integer');
      });
    }
  }

  return mapId;
}

// ── Run ──

if (!existsSync(mapsDir)) {
  console.log(`maps:check OK — maps directory does not exist yet (${mapsDir}), nothing to validate.`);
  process.exit(0);
}

const mapFiles = readdirSync(mapsDir).filter(
  (name) => name.endsWith('.json') && !name.endsWith('.schema.json'),
);

const seenMapIds = new Map();
const mapsById = new Map();

for (const fileName of mapFiles) {
  const filePath = join(mapsDir, fileName);
  let data;

  try {
    data = JSON.parse(readFileSync(filePath, 'utf8'));
  } catch (error) {
    fail(fileName, 'json', `cannot parse: ${error.message}`);
    continue;
  }

  const mapId = validateMap(data, fileName);

  if (mapId !== null) {
    if (seenMapIds.has(mapId)) {
      fail(fileName, 'mapId', `duplicate of ${seenMapIds.get(mapId)}`);
    } else {
      seenMapIds.set(mapId, fileName);
      mapsById.set(mapId, data);
    }
  }
}

const productionMapIds = ['icege', 'meadow-crossing', 'gloop-forest', 'crystal-caverns'];
for (const mapId of productionMapIds) {
  if (!mapsById.has(mapId)) {
    fail('<production>', mapId, `required production map '${mapId}.map.json' is missing`);
  }
}

for (const [mapId, map] of mapsById) {
  for (const [exitIndex, exit] of (map.exits ?? []).entries()) {
    const target = mapsById.get(exit.to);
    if (!target) {
      fail(`${mapId}.map.json`, `exits[${exitIndex}].to`, `target map '${exit.to}' does not exist`);
      continue;
    }
    if (!isRecord(target.player?.entries) || !(exit.entry in target.player.entries)) {
      fail(
        `${mapId}.map.json`,
        `exits[${exitIndex}].entry`,
        `target map '${exit.to}' has no '${exit.entry}' player entry`,
      );
    }
  }
}

if (errors.length > 0) {
  console.error(`maps:check failed with ${errors.length} error(s):`);
  for (const error of errors) {
    console.error(`  ✗ ${error}`);
  }
  process.exit(1);
}

console.log(`maps:check OK — ${mapFiles.length} map(s) validated.`);
