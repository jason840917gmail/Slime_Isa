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
 *   4. player spawn/entries, exits, and spawns blocks are well-formed.
 *
 * Reference validation (tile/archetype/enemy/area IDs against TS catalogs)
 * intentionally runs at load-time — catalogs stay single-owned in TypeScript.
 *
 * Usage: `node scripts/check-maps.mjs [mapsDir]` (mapsDir defaults to
 * src/game/content/maps; overridable for fixture testing).
 */

import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const enemyCatalog = JSON.parse(readFileSync(
  join(repoRoot, 'src', 'game', 'content', 'enemies', 'enemy-types.json'),
  'utf8',
));
const activeEnemyIds = new Set(Object.keys(enemyCatalog.types ?? {}));
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

function checkPoint(value, path, label) {
  if (!isRecord(value) || !isNumber(value.x) || !isNumber(value.y)) {
    fail(label, path, 'expected { x, y } numbers');
  }
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
      }
      if (typeof object.visualId !== 'string' || object.visualId.length === 0) {
        fail(label, `${path}.visualId`, 'required non-empty string (authored visual ID)');
      }

      if (!isNumber(object.x) || !isNumber(object.y)) {
        fail(label, path, 'expected numeric x/y');
      } else if (pixelWidth !== null && pixelHeight !== null
        && (object.x < 0 || object.x > pixelWidth || object.y < 0 || object.y > pixelHeight)) {
        fail(label, path, `position (${object.x}, ${object.y}) outside map bounds ${pixelWidth}x${pixelHeight}`);
      }

      if (object.initialState !== undefined && !isRecord(object.initialState)) {
        fail(label, `${path}.initialState`, 'expected an object');
      }
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
