const TILE_SIZE = 64;
const COLUMNS = 54;
const ROWS = 54;
const EDGE_TRANSITION_SIZE = 32;

const AREA_DEFINITIONS = {
  'gloop-forest': {
    biome: 'gloop-forest',
    seed: 37,
    neighbors: { west: 'level-1', east: 'crystal-caverns' },
    enemies: [
      { type: 'worm-brawler', weight: 65 },
      { type: 'worm-swordsman', weight: 20 },
      { type: 'worm-archer', weight: 15 },
    ],
  },
  'crystal-caverns': {
    biome: 'crystal-caverns',
    seed: 81,
    neighbors: { west: 'gloop-forest' },
    enemies: [
      { type: 'worm-brawler', weight: 30 },
      { type: 'worm-swordsman', weight: 40 },
      { type: 'worm-archer', weight: 30 },
    ],
  },
};

const OPPOSITE_DIRECTION = {
  north: 'south',
  east: 'west',
  south: 'north',
  west: 'east',
};

const TILE_TOKENS = {
  meadow: {
    legend: { a: 'grass-a', b: 'grass-b' },
    tokenByTile: { 'grass-a': 'a', 'grass-b': 'b' },
  },
  'gloop-forest': {
    legend: { f: 'forest-floor', m: 'forest-moss', t: 'tree-wall', w: 'deep-water' },
    tokenByTile: { 'forest-floor': 'f', 'forest-moss': 'm', 'tree-wall': 't', 'deep-water': 'w' },
  },
  'crystal-caverns': {
    legend: { c: 'cavern-floor', r: 'crystal-floor', x: 'crystal-wall', w: 'deep-water' },
    tokenByTile: { 'cavern-floor': 'c', 'crystal-floor': 'r', 'crystal-wall': 'x', 'deep-water': 'w' },
  },
};

function sample(tileX, tileY) {
  const value = Math.sin(tileX * 12.9898 + tileY * 78.233) * 43758.5453;
  const fraction = value - Math.floor(value);
  const wave = (Math.sin(tileX * 0.25) + Math.cos(tileY * 0.32) + 2) / 4;
  return Math.max(0, Math.min(1, fraction * 0.45 + wave * 0.55));
}

function biomeSample(tileX, tileY, seed) {
  return sample(tileX + seed * 17, tileY - seed * 23);
}

function resolveTile(tileX, tileY, biome, seed) {
  const edgeLane = tileX < 6 || tileX > 47 || tileY < 6 || tileY > 47;
  const noise = biomeSample(tileX, tileY, seed);
  const ridge = biomeSample(tileX - 13, tileY + 17, seed);
  const shelf = biomeSample(tileX + 7, tileY - 19, seed);

  if (biome === 'gloop-forest') {
    if (edgeLane) return 'forest-floor';
    if (ridge > 0.78 && shelf > 0.48) return 'tree-wall';
    if (noise > 0.78) return 'deep-water';
    return noise > 0.42 ? 'forest-moss' : 'forest-floor';
  }

  if (biome === 'crystal-caverns') {
    if (edgeLane) return 'cavern-floor';
    if (ridge > 0.7 || shelf > 0.84) return 'crystal-wall';
    if (noise > 0.76) return 'deep-water';
    return noise > 0.46 ? 'crystal-floor' : 'cavern-floor';
  }

  if (!edgeLane && noise > 0.73) return 'rock-wall';
  return noise > 0.38 ? 'grass-b' : 'grass-a';
}

function entryPoint(direction, width, height) {
  const inset = TILE_SIZE * 4;
  switch (direction) {
    case 'west': return { x: inset, y: height / 2 };
    case 'east': return { x: width - inset, y: height / 2 };
    case 'north': return { x: width / 2, y: inset };
    case 'south': return { x: width / 2, y: height - inset };
    default: throw new Error(`Unknown direction '${direction}'`);
  }
}

function exitZone(direction, width, height) {
  switch (direction) {
    case 'west': return { x: 0, y: 0, w: EDGE_TRANSITION_SIZE, h: height };
    case 'east': return { x: width - EDGE_TRANSITION_SIZE, y: 0, w: EDGE_TRANSITION_SIZE, h: height };
    case 'north': return { x: 0, y: 0, w: width, h: EDGE_TRANSITION_SIZE };
    case 'south': return { x: 0, y: height - EDGE_TRANSITION_SIZE, w: width, h: EDGE_TRANSITION_SIZE };
    default: throw new Error(`Unknown direction '${direction}'`);
  }
}

export function getProductionMapIds() {
  return Object.keys(AREA_DEFINITIONS);
}

export function bakeProductionMap(mapId) {
  const area = AREA_DEFINITIONS[mapId];
  if (!area) throw new Error(`Unknown production map '${mapId}'`);

  const width = COLUMNS * TILE_SIZE;
  const height = ROWS * TILE_SIZE;
  const tokens = TILE_TOKENS[area.biome];
  const rows = [];
  const objects = [];

  for (let tileY = 0; tileY < ROWS; tileY += 1) {
    let row = '';
    for (let tileX = 0; tileX < COLUMNS; tileX += 1) {
      let tileId = resolveTile(tileX, tileY, area.biome, area.seed);
      if (
        area.biome === 'meadow'
        && (tileId === 'grass-a' || tileId === 'grass-b')
        && biomeSample(tileX, tileY, area.seed) > 0.45
        && biomeSample(tileX + 5, tileY + 3, area.seed) > 0.86
      ) {
        const offsetX = 20 + Math.floor(biomeSample(tileX + 101, tileY - 67, area.seed) * 25);
        const offsetY = 20 + Math.floor(biomeSample(tileX - 43, tileY + 89, area.seed) * 25);
        objects.push({
          instanceId: `purple-berry-${tileX}-${tileY}`,
          objectId: 'collectible.purple-berry',
          visualId: 'purple-berry',
          x: tileX * TILE_SIZE + offsetX,
          y: tileY * TILE_SIZE + offsetY,
        });
      }
      if (tileId === 'rock-wall') {
        objects.push({
          instanceId: `world-rock-${tileX}-${tileY}`,
          objectId: 'rock.world-wall.solid',
          visualId: `field-${String(1 + Math.floor(biomeSample(tileX + 31, tileY - 17, area.seed) * 24)).padStart(2, '0')}`,
          x: tileX * TILE_SIZE + TILE_SIZE / 2,
          y: tileY * TILE_SIZE + TILE_SIZE,
        });
        tileId = 'grass-a';
      }
      row += tokens.tokenByTile[tileId];
    }
    rows.push(row);
  }

  const entries = Object.fromEntries(
    Object.keys(area.neighbors).map((direction) => [direction, entryPoint(direction, width, height)]),
  );
  const exits = Object.entries(area.neighbors).map(([direction, targetArea]) => ({
    zone: exitZone(direction, width, height),
    to: targetArea,
    entry: OPPOSITE_DIRECTION[direction],
  }));

  return {
    $schema: './maps.schema.json',
    version: 1,
    mapId,
    tileSize: TILE_SIZE,
    size: { columns: COLUMNS, rows: ROWS },
    layers: [{
      id: 'ground',
      encoding: 'legend-chars-v1',
      legend: tokens.legend,
      rows,
    }],
    objects,
    player: {
      spawn: { x: width / 2, y: height / 2 },
      entries,
    },
    exits,
    enemySafeZones: [],
    spawns: {
      enemies: area.enemies,
      radius: { min: 200, max: 500 },
      intervalMs: 1500,
      maxPopulation: 16,
      safeZones: [],
    },
  };
}
