#!/usr/bin/env node
// Builds the level-1 world ("Slimeshire Meadow") from a deterministic layout.
//
// Level-1 is scene-owned (Scene Studio edits it directly); this tool is the
// authoring source for its generated layer only. It keeps every hand-authored
// node and instance that tests, quests and saves depend on (NPCs, the Fatty
// camp at 2528,1472, exit-1, the starter worm camp, resources and collectibles,
// the houses and their doors, the Workshop), moves some of them into the new layout, and
// regenerates everything else:
//
//   - terrain: meadow grass, dirt roads, a cobbled town square, a river with
//     a lake and a pond, sand shores, moss under forests, an autumn grove
//   - an impassable forest-wall border (tree-forest-wall instances)
//   - Slimeshire town: plaza with the village well, market, forge yard,
//     woodcutter yard, quarry, orchard, lanterns and a south fence
//   - Fatty One Eye's hedge maze around his camp, the worm ruins (stone-wall
//     rings around the starter camp) and the Webwood spider thicket
//   - the Verdant Gate pocket in front of exit-1: the gate stays shut until the
//     green key from Fatty's chest unlocks it (game.gate)
//   - wooden footbridges, rocks, trees, choppable resources, berries, enemy
//     spawn areas, NPC wander areas and walk-over ground decals
//
// Generated instances live under grouping Node2Ds (`gen-*`) and generated area
// nodes use `area-level-1-gen-*` ids, so re-running replaces them cleanly.
//
// Usage: node scripts/maps/build-level-1.mjs [--write] [--ascii]
import { readFileSync, writeFileSync } from 'node:fs';

const SCENE_PATH = 'src/game/content/scenes/authored/worlds/level-1.scene.json';
const MAP_ID = 'level-1';
const TILE = 64;
const N = 56;
const WORLD = TILE * N;
const args = process.argv.slice(2);
const WRITE = args.includes('--write');
const ASCII = args.includes('--ascii');

// ── deterministic randomness ──────────────────────────────────────────────
function unit(x, y, salt) {
  let hash = Math.imul(Math.round(x) + 0x3c6e, 0x27d4eb2d) ^ Math.imul(Math.round(y) - 0x1f83, 0x165667b1) ^ Math.imul(salt, 0x45d9f3b);
  hash = Math.imul(hash ^ (hash >>> 15), 0x2c1b3c6d);
  hash = Math.imul(hash ^ (hash >>> 12), 0x297a2d39);
  return ((hash ^ (hash >>> 15)) >>> 0) / 4294967296;
}
function noise(x, y, salt = 7) {
  const x0 = Math.floor(x); const y0 = Math.floor(y); const fx = x - x0; const fy = y - y0;
  const sx = fx * fx * (3 - 2 * fx); const sy = fy * fy * (3 - 2 * fy);
  const a = unit(x0, y0, salt); const b = unit(x0 + 1, y0, salt);
  const c = unit(x0, y0 + 1, salt); const d = unit(x0 + 1, y0 + 1, salt);
  return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy;
}
let rngState = 0x5eed1e;
function rand() {
  rngState = (rngState + 0x6d2b79f5) | 0;
  let t = Math.imul(rngState ^ (rngState >>> 15), 1 | rngState);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pickOf = (list, roll = rand()) => list[Math.min(list.length - 1, Math.floor(roll * list.length))];
function weighted(entries, roll = rand()) {
  const total = entries.reduce((sum, [, weight]) => sum + weight, 0);
  let cursor = roll * total;
  for (const [value, weight] of entries) { cursor -= weight; if (cursor <= 0) return value; }
  return entries.at(-1)[0];
}
const round = (value) => Math.round(value * 100) / 100;
const inBounds = (x, y) => x >= 0 && y >= 0 && x < N && y < N;
const cellCenter = (x, y) => [x * TILE + TILE / 2, y * TILE + TILE / 2];

// ── layout constants (tile coordinates unless noted) ──────────────────────
const CAMP = { x: 2528, y: 1472 }; // pinned by tests (Fatty One Eye camp root)
const CAMP_TILE = { x: CAMP.x / TILE - 0.5, y: CAMP.y / TILE }; // tile 39, y 23
const MAZE = { x0: 30, y0: 14, cols: 7, rows: 7, cell: 3 }; // hedge maze around the camp
const MAZE_X1 = MAZE.x0 + MAZE.cols * MAZE.cell; // 51
const MAZE_Y1 = MAZE.y0 + MAZE.rows * MAZE.cell; // 35
// Fatty's arena: an open clearing (tiles) around the camp with nothing to hide behind.
// The camp's arena and activation circles (encounters/level-1-fatty-camp.scene.json)
// sit just inside it, so Fatty never leaps over the hedges.
const ARENA_RADIUS = 7;
/** The guarded chest waits at the north rim of the clearing (camp-relative, px). */
const CHEST_OFFSET = { x: 0, y: -395 };
const POCKET = { x0: 47, x1: 55, y0: 5, y1: 11 }; // walled pocket in front of exit-1
const GATE = { x: 51 * TILE, y: 12 * TILE }; // Verdant Gate root (bottom centre)
const RUINS = { cx: 17.7, cy: 23.7 };
const LAKE = { cx: 9.2, cy: 43.2, rx: 6.6, ry: 7.4 };
const POND = { cx: 22.4, cy: 13.9, rx: 2.3, ry: 1.9 };
const LILY_POND = { cx: 30.5, cy: 46.5, rx: 2.4, ry: 1.8 };
const RIVER = [[27.9, -1], [27.9, 6], [28.2, 13], [28.4, 19], [28.1, 26], [27.2, 29.5], [25.2, 32.8], [21.5, 35.6], [16.5, 38.5], [13.5, 40.5]];
const RIVER_WIDTH = 1.05;
const TOWN = { x0: 2, x1: 26, y0: 2, y1: 17 };
const PLAZA = { cx: 11.3, cy: 12.2, rx: 4.3, ry: 3.2 };

// ── terrain ───────────────────────────────────────────────────────────────
const terrain = Array.from({ length: N }, () => Array(N).fill('grass-a'));
const setTile = (x, y, id) => { if (inBounds(x, y)) terrain[y][x] = id; };
const tileAt = (x, y) => (inBounds(x, y) ? terrain[y][x] : 'grass-a');
const isWater = (x, y) => ['water', 'deep-water'].includes(tileAt(x, y));
const ellipse = (e, x, y, grow = 0) => (((x + 0.5 - e.cx) / (e.rx + grow)) ** 2 + ((y + 0.5 - e.cy) / (e.ry + grow)) ** 2);

function distToSegment(px, py, [ax, ay], [bx, by]) {
  const dx = bx - ax; const dy = by - ay;
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}
const distToPolyline = (px, py, points) => Math.min(...points.slice(1).map((point, index) => distToSegment(px, py, points[index], point)));

// walls: tree cells that block movement (forest border, hedge maze, pocket, thicket)
const wall = Array.from({ length: N }, () => Array(N).fill(null)); // null | 'border' | 'maze' | 'pocket' | 'thicket'
const reserved = Array.from({ length: N }, () => Array(N).fill(false)); // roads, bridges, entrances: never walled/propped
const isWall = (x, y) => inBounds(x, y) && wall[y][x] !== null;

// Roads: polylines of tile coordinates, 2 tiles wide. Painted as forest-floor dirt.
const ROADS = [
  // Verdant Road: plaza → east bridge → along the Webwood → down to the gate
  [[12, 9], [20, 9], [27, 9], [33, 9], [40, 9], [44.5, 9.2], [45, 12.4], [52.5, 12.6]],
  // mushroom house path
  [[23.3, 9.1], [23.3, 8.3]],
  // slime home door → south road
  [[16.9, 15.4], [16.9, 18.6]],
  // plaza → south gate → worm ruins north gap
  [[11.3, 14.6], [11.3, 18.4], [17.5, 18.6], [17.8, 20]],
  // ruins east gap → river bridge → maze west entrance
  [[24.5, 24.6], [31, 24.6]],
  // ruins south gap → lower bridge → south meadow
  [[17.8, 27.5], [18.2, 30.5], [22, 32.8], [29, 32.9], [30.6, 36.8], [30.4, 41]],
  // maze south exit → autumn grove
  [[37.5, 35.2], [37.8, 38.5], [44, 40.5]],
  // maze north exit → Verdant Road
  [[43.6, 13.6], [43.9, 11]],
];
const ROAD_HALF = 0.95;
const onRoad = (x, y) => ROADS.some((road) => distToPolyline(x + 0.5, y + 0.5, road) <= ROAD_HALF);

// Bridges: lanes of walkable ground across the river, covered by a footbridge.
const BRIDGES = []; // filled after the river is painted: { x, y (px root), tiles }

function paintTerrain() {
  // moss under the border forest, with a feathered inner edge
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      const edge = Math.min(x, y, N - 1 - x, N - 1 - y);
      if (edge <= 3 + Math.floor(noise(x / 4, y / 4, 11) * 2.2)) setTile(x, y, 'forest-moss');
    }
  }
  // meadow variation: patches of forest-moss deeper green in the open field
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      if (noise(x / 6, y / 6, 21) > 0.74 && tileAt(x, y) === 'grass-a') setTile(x, y, 'forest-moss');
    }
  }
  // autumn grove (south-east)
  for (let y = 34; y < N; y += 1) {
    for (let x = 38; x < N; x += 1) {
      const d = Math.hypot((x - 47) / 9.5, (y - 46) / 9);
      if (d + (noise(x / 3, y / 3, 31) - 0.5) * 0.35 < 1) setTile(x, y, 'amberleaf-ground');
    }
  }
  // Webwood (north-east): dark forest floor
  for (let y = 1; y <= 8; y += 1) {
    for (let x = 30; x <= 47; x += 1) {
      setTile(x, y, noise(x / 2.5, y / 2.5, 41) > 0.55 ? 'forest-moss' : 'forest-floor');
    }
  }
  // hedge maze: moss under the hedges, dirt corridors
  for (let y = MAZE.y0; y <= MAZE_Y1; y += 1) {
    for (let x = MAZE.x0; x <= MAZE_X1; x += 1) setTile(x, y, 'forest-moss');
  }
  // worm ruins: old cobbles inside the inner ring, dirt around it
  for (let y = 18; y <= 29; y += 1) {
    for (let x = 10; x <= 25; x += 1) {
      const d = Math.hypot((x + 0.5 - RUINS.cx) / 7.5, (y + 0.5 - RUINS.cy) / 5.6);
      if (d < 1 && noise(x / 2.5, y / 2.5, 51) > 0.62) setTile(x, y, 'forest-floor');
    }
  }
  for (let y = 21; y <= 26; y += 1) for (let x = 14; x <= 21; x += 1) setTile(x, y, noise(x / 1.5, y / 1.5, 52) > 0.78 ? 'forest-moss' : 'town-cobble');
  // lake with sand shore, deep centre and an island
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      const wobble = (noise(x / 3, y / 3, 61) - 0.5) * 0.5;
      const e = ellipse(LAKE, x, y) + wobble;
      if (e < 1) setTile(x, y, ellipse(LAKE, x, y) < 0.42 ? 'deep-water' : 'water');
      else if (ellipse(LAKE, x, y, 1.6) + wobble < 1) setTile(x, y, 'sanddessert-ground');
    }
  }
  for (const [x, y] of [[8, 43], [9, 43], [8, 44], [9, 44], [10, 44], [9, 42]]) setTile(x, y, 'sanddessert-ground');
  for (const [x, y] of [[9, 43], [8, 44], [9, 44]]) setTile(x, y, 'grass-a');
  // town pond and the lily pond
  for (const pond of [POND, LILY_POND]) {
    for (let y = 0; y < N; y += 1) {
      for (let x = 0; x < N; x += 1) {
        if (ellipse(pond, x, y) < 1) setTile(x, y, 'water');
        else if (ellipse(pond, x, y, 0.9) < 1 && !isWater(x, y)) setTile(x, y, 'sanddessert-ground');
      }
    }
  }
  // river
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      const d = distToPolyline(x + 0.5, y + 0.5, RIVER);
      if (d <= RIVER_WIDTH) setTile(x, y, 'water');
      else if (d <= RIVER_WIDTH + 0.9 && !isWater(x, y) && noise(x / 2, y / 2, 71) > 0.45) setTile(x, y, 'sanddessert-ground');
    }
  }
  // cobbled plaza
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      if (ellipse(PLAZA, x, y) + (noise(x / 2, y / 2, 81) - 0.5) * 0.3 < 1) setTile(x, y, 'town-cobble');
    }
  }
  // roads (dirt), then bridges keep walkable lanes over the water
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      if (!onRoad(x, y)) continue;
      reserved[y][x] = true;
      if (tileAt(x, y) === 'town-cobble') continue;
      setTile(x, y, isWater(x, y) ? 'grass-a' : 'forest-floor');
    }
  }
}

function findBridges() {
  // A bridge spans each run of road tiles that were water before the road.
  const lanes = [
    { row: 8, rows: [8, 9] },
    { row: 24, rows: [24, 25] },
    { row: 32, rows: [32, 33] },
  ];
  for (const lane of lanes) {
    const xs = [];
    for (let x = 0; x < N; x += 1) {
      const d = distToPolyline(x + 0.5, lane.rows[0] + 1, RIVER);
      if (d <= RIVER_WIDTH + 0.2) xs.push(x);
    }
    const cx = (Math.min(...xs) + Math.max(...xs) + 1) / 2;
    BRIDGES.push({ x: round(cx * TILE), y: round((lane.rows[0] + 1) * TILE + 68), rows: lane.rows, xs });
    for (const y of lane.rows) {
      for (let x = Math.min(...xs) - 1; x <= Math.max(...xs) + 1; x += 1) {
        if (isWater(x, y)) setTile(x, y, 'grass-a');
        reserved[y][x] = true;
      }
    }
  }
}

// ── walls ─────────────────────────────────────────────────────────────────
function buildWalls() {
  // forest border, 2 deep, with an irregular third row
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      const edge = Math.min(x, y, N - 1 - x, N - 1 - y);
      const extra = noise(x / 3.5, y / 3.5, 91) > 0.62 ? 1 : 0;
      if (edge <= 1 + extra) wall[y][x] = 'border';
    }
  }
  // let the river leave the map through the north border
  for (let y = 0; y < 4; y += 1) for (let x = 0; x < N; x += 1) if (isWater(x, y)) wall[y][x] = null;
  // Verdant Gate pocket in front of exit-1
  for (let y = POCKET.y0; y <= POCKET.y1; y += 1) {
    for (let x = POCKET.x0; x <= POCKET.x1; x += 1) {
      const rim = y === POCKET.y0 || y === POCKET.y1 || x === POCKET.x0;
      wall[y][x] = rim ? 'pocket' : null;
    }
  }
  for (let y = 2; y < POCKET.y0; y += 1) for (let x = POCKET.x0; x < N; x += 1) wall[y][x] = 'pocket'; // no hidden meadow behind the pocket
  for (let x = 49; x <= 52; x += 1) wall[POCKET.y1][x] = null; // gate opening (the gate pillars overlap trees at 48 and 53)
  for (let y = 7; y <= 10; y += 1) { wall[y][54] = null; wall[y][55] = null; } // exit-1 (x 55, rows 8-9)
  wall[6][55] = 'border'; wall[11][55] = 'border';
  // Webwood thicket clumps (north-east), leaving winding clearings
  for (let y = 2; y <= 6; y += 1) {
    for (let x = 30; x <= 46; x += 1) {
      const n = noise(x / 2.2, y / 2.2, 101);
      if ((n > 0.47 || unit(x, y, 102) < 0.08) && !(x >= 36 && x <= 42 && y >= 3 && y <= 6)) wall[y][x] = 'thicket';
    }
  }
  buildMaze();
  // roads, bridges and markers stay open
  for (let y = 0; y < N; y += 1) for (let x = 0; x < N; x += 1) if (reserved[y][x] && wall[y][x] !== 'pocket') wall[y][x] = null;
  for (let y = 0; y < N; y += 1) for (let x = 0; x < N; x += 1) if (isWater(x, y) && wall[y][x] !== 'border') wall[y][x] = null;
}

function buildMaze() {
  const { x0, y0, cols, rows, cell } = MAZE;
  // start fully walled, carve a perfect maze with a seeded recursive backtracker
  for (let y = y0; y <= MAZE_Y1; y += 1) for (let x = x0; x <= MAZE_X1; x += 1) wall[y][x] = 'maze';
  const visited = Array.from({ length: rows }, () => Array(cols).fill(false));
  const carveCell = (i, j) => {
    for (let dy = 1; dy < cell; dy += 1) for (let dx = 1; dx < cell; dx += 1) wall[y0 + j * cell + dy][x0 + i * cell + dx] = null;
  };
  const carveBetween = (i, j, di, dj) => {
    // open the wall between cell (i,j) and its neighbour
    if (di !== 0) {
      const x = x0 + (di > 0 ? (i + 1) * cell : i * cell);
      for (let dy = 1; dy < cell; dy += 1) wall[y0 + j * cell + dy][x] = null;
    } else {
      const y = y0 + (dj > 0 ? (j + 1) * cell : j * cell);
      for (let dx = 1; dx < cell; dx += 1) wall[y][x0 + i * cell + dx] = null;
    }
  };
  const stack = [[0, 3]];
  visited[3][0] = true;
  carveCell(0, 3);
  while (stack.length > 0) {
    const [i, j] = stack.at(-1);
    const options = [[1, 0], [-1, 0], [0, 1], [0, -1]]
      .filter(([di, dj]) => i + di >= 0 && j + dj >= 0 && i + di < cols && j + dj < rows && !visited[j + dj][i + di]);
    if (options.length === 0) { stack.pop(); continue; }
    const [di, dj] = pickOf(options);
    carveBetween(i, j, di, dj);
    visited[j + dj][i + di] = true;
    carveCell(i + di, j + dj);
    stack.push([i + di, j + dj]);
  }
  // extra openings make loops so the maze is fun rather than frustrating
  for (let n = 0; n < 9; n += 1) {
    const i = Math.floor(rand() * (cols - 1)); const j = Math.floor(rand() * rows);
    if (rand() < 0.5) carveBetween(i, j, 1, 0); else carveBetween(Math.floor(rand() * cols), Math.floor(rand() * (rows - 1)), 0, 1);
  }
  // Fatty's arena: a round clearing in the middle
  for (let y = y0; y <= MAZE_Y1; y += 1) {
    for (let x = x0; x <= MAZE_X1; x += 1) {
      if (Math.hypot((x + 0.5) * TILE - CAMP.x, (y + 0.5) * TILE - CAMP.y) / TILE < ARENA_RADIUS) wall[y][x] = null;
    }
  }
  // entrances: west (to the river bridge), north (to the Verdant Road), south (to the grove)
  for (const y of [24, 25]) wall[y][x0] = null;
  for (const x of [43, 44]) wall[y0][x] = null;
  for (const x of [37, 38]) wall[MAZE_Y1][x] = null;
  // maze floor: dirt corridors, moss under hedges
  for (let y = y0; y <= MAZE_Y1; y += 1) {
    for (let x = x0; x <= MAZE_X1; x += 1) {
      if (!isWall(x, y)) setTile(x, y, Math.hypot(x - CAMP_TILE.x, y - CAMP_TILE.y) < ARENA_RADIUS - 1 ? 'forest-floor' : (noise(x / 2, y / 2, 111) > 0.35 ? 'forest-floor' : 'forest-moss'));
    }
  }
}

// ── instances ─────────────────────────────────────────────────────────────
const groups = new Map(); // id -> { name, instances: [] }
const occupied = []; // [x, y, r] solid props in px, used to keep props apart
const decalBlock = []; // [x, y, r] areas decals avoid
function group(id, name) {
  if (!groups.has(id)) groups.set(id, { id, name, instances: [] });
  return groups.get(id);
}
const counters = new Map();
function nextId(prefix) {
  const value = (counters.get(prefix) ?? 0) + 1;
  counters.set(prefix, value);
  return `${prefix}-${String(value).padStart(3, '0')}`;
}
const override = (sourceNodeId, property, value) => ({ sourceInstancePath: [], sourceNodeId, property, value });

/**
 * Adds a scene instance. `root` is the node that carries the position (`body`
 * for solid scenes, `root` for decals, rocks and collectibles). `state` adds the
 * script.mapId/instanceId overrides stateful scenes need.
 */
function place(groupId, prefix, sceneId, x, y, options = {}) {
  const instanceId = options.instanceId ?? nextId(prefix);
  const overrides = [override(options.root ?? 'body', 'position', [round(x), round(y)])];
  if (options.state) {
    overrides.push(override(options.scriptNode ?? 'script', 'mapId', MAP_ID));
    overrides.push(override(options.scriptNode ?? 'script', 'instanceId', instanceId));
  }
  for (const entry of options.overrides ?? []) overrides.push(entry);
  group(groupId).instances.push({ instanceId, name: instanceId, sceneId, persistenceKey: `${MAP_ID}.${instanceId}`, overrides });
  if (options.radius) occupied.push([x, y, options.radius]);
  decalBlock.push([x, y, options.decalRadius ?? Math.max(28, (options.radius ?? 0) + 12)]);
  return instanceId;
}
const blockedAt = (x, y, radius) => occupied.some(([ox, oy, r]) => Math.hypot(ox - x, oy - y) < r + radius);
function tileFree(x, y) {
  const tx = Math.floor(x / TILE); const ty = Math.floor(y / TILE);
  return inBounds(tx, ty) && !isWall(tx, ty) && !isWater(tx, ty) && !reserved[ty][tx];
}
function footprintFree(x, y, halfWidth, depth) {
  for (const [px, py] of [[x - halfWidth, y - 4], [x + halfWidth, y - 4], [x - halfWidth, y - depth], [x + halfWidth, y - depth], [x, y - depth / 2]]) {
    if (!tileFree(px, py)) return false;
  }
  return true;
}
function tryPlace(groupId, prefix, sceneId, x, y, options = {}) {
  const radius = options.radius ?? 40;
  if (!footprintFree(x, y, options.halfWidth ?? radius * 0.7, options.depth ?? radius) || blockedAt(x, y, radius)) return undefined;
  if (options.avoid && options.avoid(x, y)) return undefined;
  return place(groupId, prefix, sceneId, x, y, { ...options, radius });
}

const WALL_TREES = {
  border: ['pine-02', 'pine-03', 'pine-04', 'pine-06', 'pine-07', 'green-tree-05', 'green-tree-06', 'green-tree-07'],
  pocket: ['green-tree-05', 'green-tree-06', 'green-tree-07', 'pine-04'],
  maze: ['green-tree-05', 'green-tree-06', 'green-tree-07', 'green-tree-06', 'pine-03'],
  thicket: ['pine-02', 'pine-06', 'pine-07', 'pine-03'],
};
function placeWalls() {
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      const kind = wall[y][x];
      if (!kind) continue;
      // hidden border cells deep inside the forest are skipped (never reachable, never visible)
      const exposed = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1], [0, 2], [0, -2], [2, 0], [-2, 0]]
        .some(([dx, dy]) => inBounds(x + dx, y + dy) && !isWall(x + dx, y + dy));
      const outerRim = x === 0 || y === 0 || x === N - 1 || y === N - 1;
      if (kind === 'border' && !exposed && !outerRim) continue;
      const species = pickOf(WALL_TREES[kind], unit(x, y, 131));
      const tall = kind === 'maze' ? 0.95 : 1;
      const scale = round((0.9 + unit(x, y, 132) * 0.22) * tall);
      const extra = [
        override('visual', 'visualOffset', [round((unit(x, y, 133) - 0.5) * 20), round((unit(x, y, 134) - 0.5) * 12)]),
        override('visual', 'scale', [scale, scale]),
      ];
      if (unit(x, y, 135) < 0.5) extra.push(override('visual', 'flipX', true));
      place(`gen-${kind === 'border' ? 'forest' : kind}`, `l1-${kind}-tree`, `object.tree-forest-wall.${species}`, x * TILE + 32, y * TILE + 54, { overrides: extra, decalRadius: 30 });
    }
  }
}

// ── landmarks and props ───────────────────────────────────────────────────
const D = (name) => `object.decoration-world-solid.${name}`;
const RADIUS = {
  'lantern-post': 20, 'flower-planter': 44, 'herb-planter': 44, birdhouse: 20, 'hay-bale': 52, haystack: 44,
  'tool-bench': 50, grindstone: 40, anvil: 34, 'cooking-cauldron': 40, campfire: 52, 'canvas-tent': 52,
  'village-banner': 22, 'stone-birdbath': 28, 'stone-pedestal': 26, 'armor-statue': 28, 'wood-table': 46,
  'reinforced-fence': 50, 'palisade-cluster': 44, 'palisade-gap': 40, 'village-well': 60,
};
const prop = (groupId, name, x, y, options = {}) => tryPlace(groupId, `l1-${name}`, D(name), x, y, { radius: RADIUS[name] ?? 40, depth: 40, ...options });
const force = (groupId, name, x, y, options = {}) => place(groupId, `l1-${name}`, D(name), x, y, { radius: RADIUS[name] ?? 40, ...options });

function placeLandmarks() {
  // Verdant Gate blocks the pocket opening until the green key is used
  place('gen-landmarks', 'l1-verdant-gate', 'object.gate-verdant', GATE.x, GATE.y, { root: 'root', instanceId: 'level-1-verdant-gate', radius: 150, decalRadius: 170 });
  force('gen-landmarks', 'lantern-post', GATE.x - 200, GATE.y + 40);
  force('gen-landmarks', 'lantern-post', GATE.x + 190, GATE.y + 40);
  force('gen-landmarks', 'village-banner', GATE.x - 120, GATE.y + 96);
  force('gen-landmarks', 'village-banner', GATE.x + 120, GATE.y + 96);
  // inside the pocket: a little shrine garden before the exit
  force('gen-landmarks', 'stone-pedestal', 49.5 * TILE, 7.6 * TILE);
  force('gen-landmarks', 'flower-planter', 49 * TILE, 9.9 * TILE);
  force('gen-landmarks', 'herb-planter', 52.6 * TILE, 6.9 * TILE);
  force('gen-landmarks', 'lantern-post', 53.7 * TILE, 7.2 * TILE);
  force('gen-landmarks', 'lantern-post', 53.7 * TILE, 10.6 * TILE);
  // footbridges over the river
  for (const bridge of BRIDGES) {
    place('gen-landmarks', 'l1-footbridge', 'object.decoration-world-floor.wooden-footbridge', bridge.x, bridge.y, { root: 'root', decalRadius: 150 });
  }
  // village well on the plaza
  place('gen-town', 'l1-village-well', 'object.decoration-world-solid.village-well', 11.3 * TILE, 13.3 * TILE, { radius: 64 });
}

function placeTown() {
  const G = 'gen-town';
  // plaza ring of lanterns and planters
  for (const [x, y] of [[7.4, 10.2], [15.2, 10.4], [7.6, 15.4], [15.3, 14.9]]) force(G, 'lantern-post', x * TILE, y * TILE);
  for (const [x, y] of [[8.9, 10.6], [13.9, 10.4]]) force(G, 'flower-planter', x * TILE, y * TILE);
  force(G, 'village-banner', 10.2 * TILE, 10.35 * TILE);
  force(G, 'village-banner', 12.5 * TILE, 10.35 * TILE);
  force(G, 'stone-birdbath', 8.1 * TILE, 13.9 * TILE);
  // market corner (south-west of the plaza, beside the round mushroom house)
  force(G, 'canvas-tent', 7.4 * TILE, 16.6 * TILE);
  force(G, 'wood-table', 8.9 * TILE, 17.1 * TILE);
  force(G, 'cooking-cauldron', 5.3 * TILE, 13.4 * TILE);
  force(G, 'hay-bale', 3.6 * TILE, 11.9 * TILE);
  // forge yard next to the slime home (the red forge house)
  force(G, 'anvil', 19.6 * TILE, 15.9 * TILE);
  force(G, 'grindstone', 20.9 * TILE, 16.8 * TILE);
  force(G, 'tool-bench', 19.4 * TILE, 13.3 * TILE);
  // woodcutter yard around the loose wood piles; the ruined Workshop (hand-placed, level-1-workshop) stands behind it
  force(G, 'haystack', 3.5 * TILE, 7.7 * TILE);
  force(G, 'tool-bench', 12.9 * TILE, 7.2 * TILE);
  force(G, 'birdhouse', 3.4 * TILE, 9.6 * TILE);
  force(G, 'herb-planter', 25.4 * TILE, 11.0 * TILE);
  force(G, 'birdhouse', 25.6 * TILE, 15.3 * TILE);
  // extra homes
  place(G, 'l1-cottage', 'object.house-world-solid.cottage-blue', 5.4 * TILE, 6.6 * TILE, { radius: 150, decalRadius: 150 });
  place(G, 'l1-round-house', 'object.house-mushroom-round', 4.5 * TILE, 16.7 * TILE, { radius: 140, decalRadius: 140 });
  // road lanterns
  for (const [x, y] of [[18, 7.8], [24.8, 7.8], [31, 7.8], [37, 10.9], [42.6, 10.9], [46.3, 13.8]]) force('gen-landmarks', 'lantern-post', x * TILE, y * TILE);
  // south town fence with the south gate gap over the road
  for (let x = 2.6; x < 26; x += 1.55) {
    const tx = Math.floor(x); const y = 17.9;
    if (Math.abs(x - 11.3) < 1.9 || Math.abs(x - 16.9) < 1.3 || isWater(tx, 17) || isWater(tx + 1, 17)) continue;
    const name = unit(tx, 17, 141) < 0.72 ? 'reinforced-fence' : 'palisade-gap';
    place(G, `l1-${name}`, D(name), x * TILE + 50, y * TILE, { radius: 30 });
  }
  force(G, 'lantern-post', 9.6 * TILE, 18.5 * TILE);
  force(G, 'lantern-post', 13.1 * TILE, 18.5 * TILE);
  // quarry dressing
  for (const [x, y, n] of [[16.3, 4.6, '13'], [18.7, 5.4, '17'], [14.9, 7.1, '21']]) {
    place('gen-nature', 'l1-rock', `object.rock-world-wall-solid.field-${n}`, x * TILE, y * TILE, { radius: 40 });
  }
}

function placeFattyCamp() {
  // The clearing stays empty: nothing to hide behind and nothing to pull focus
  // from Fatty (playtest 2026-09-29). Only the maze entrances are marked.
  const G = 'gen-maze';
  // maze entrance markers
  force(G, 'lantern-post', (MAZE.x0 - 0.6) * TILE, 23.6 * TILE);
  force(G, 'lantern-post', (MAZE.x0 - 0.6) * TILE, 26.7 * TILE);
  force(G, 'lantern-post', 42.4 * TILE, (MAZE.y0 - 0.2) * TILE);
  force(G, 'lantern-post', 36.4 * TILE, (MAZE_Y1 + 1.5) * TILE);
}

function placeRuins() {
  // two broken stone-wall rings around the worm camp (straight runs + corners, no T-junctions)
  const G = 'gen-ruins';
  const pieces = new Map();
  const ring = (x0, y0, x1, y1, gaps) => {
    for (let x = x0; x <= x1; x += 1) for (const y of [y0, y1]) pieces.set(`${x},${y}`, { x, y });
    for (let y = y0; y <= y1; y += 1) for (const x of [x0, x1]) pieces.set(`${x},${y}`, { x, y });
    for (const [x, y] of gaps) pieces.delete(`${x},${y}`);
  };
  ring(13, 20, 22, 27, [[17, 20], [18, 20], [22, 24], [22, 25], [17, 27], [18, 27], [13, 23], [13, 24]]);
  ring(10, 18, 25, 30, [[17, 18], [18, 18], [25, 24], [25, 25], [17, 30], [18, 30], [10, 23], [10, 24], [14, 18], [21, 30], [25, 20], [10, 28]]);
  const has = (x, y) => pieces.has(`${x},${y}`);
  for (const { x, y } of pieces.values()) {
    if (reserved[y]?.[x]) continue;
    const l = has(x - 1, y); const r = has(x + 1, y); const u = has(x, y - 1); const d = has(x, y + 1);
    let piece;
    if (r && d && !l && !u) piece = 'corner-01';
    else if (l && d && !r && !u) piece = 'corner-03';
    else if (r && u && !l && !d) piece = 'corner-06';
    else if (l && u && !r && !d) piece = 'corner-07';
    else if (l && r) piece = `horizontal-0${2 + Math.floor(unit(x, y, 151) * 6)}`;
    else if (r && !l) piece = null; // left end cap is the base scene
    else if (l && !r && !u && !d) piece = 'horizontal-08';
    else if (u && d) piece = `vertical-0${2 + Math.floor(unit(x, y, 152) * 6)}`;
    else if (u && !d) piece = 'vertical-08';
    else piece = 'vertical-02';
    const sceneId = piece === null ? 'object.wall-stone-solid' : `object.wall-stone-solid.${piece}`;
    place(G, 'l1-ruin-wall', sceneId, x * TILE + 32, (y + 1) * TILE, { radius: 30, decalRadius: 40 });
  }
  force(G, 'armor-statue', 16.2 * TILE, 21.9 * TILE);
  force(G, 'armor-statue', 19.4 * TILE, 21.9 * TILE);
  force(G, 'stone-pedestal', 14.8 * TILE, 26.3 * TILE);
  force(G, 'stone-pedestal', 20.9 * TILE, 26.3 * TILE);
  force(G, 'campfire', 14.9 * TILE, 22.2 * TILE);
  for (const [x, y, n] of [[11.4, 19.4, '11'], [23.6, 28.8, '14'], [11.6, 29.2, '07'], [24, 19.3, '20']]) {
    place(G, 'l1-rock', `object.rock-world-wall-decorative.field-${n}`, x * TILE, y * TILE, { root: 'root', decalRadius: 40 });
  }
}

function placeNature() {
  const G = 'gen-nature';
  // ancient landmark trees (choppable resources with state)
  place(G, 'level-1-tree', 'object.tree-world-solid.ancient-blossom', 9.1 * TILE, 44.4 * TILE, { state: true, radius: 90, instanceId: 'level-1-ancient-blossom' });
  place(G, 'level-1-tree', 'object.tree-world-solid.ancient-green', 24.6 * TILE, 44.2 * TILE, { state: true, radius: 90, instanceId: 'level-1-ancient-green' });
  place(G, 'level-1-tree', 'object.tree-world-solid.ancient-dark', 34.2 * TILE, 40.6 * TILE, { state: true, radius: 90, instanceId: 'level-1-ancient-dark' });

  // choppable trees: groves in the west meadow, south meadow and the autumn grove
  const grove = (x0, y0, x1, y1, species, count, salt) => {
    let placed = 0;
    for (let attempt = 0; attempt < count * 30 && placed < count; attempt += 1) {
      const x = (x0 + rand() * (x1 - x0)) * TILE; const y = (y0 + rand() * (y1 - y0)) * TILE;
      if (noise(x / 200, y / 200, salt) < 0.35) continue;
      const id = tryPlace(G, 'level-1-tree', `object.tree-world-solid.${pickOf(species)}`, x, y, { radius: 58, depth: 44, state: true });
      if (id) placed += 1;
    }
  };
  grove(3, 19, 9.5, 32, ['green-tree-01', 'green-tree-02', 'green-tree-03', 'grove-tree-01', 'grove-tree-04'], 7, 161);
  grove(18, 38, 28, 52, ['green-tree-04', 'green-tree-05', 'grove-tree-02', 'grove-tree-06', 'pine-01'], 6, 162);
  grove(38, 37, 53, 53, ['autumn-tree-01', 'autumn-tree-02', 'autumn-tree-03', 'autumn-tree-04', 'golden-tree-01', 'golden-tree-02', 'red-tree'], 17, 163);
  // Webwood: dead ancient trees and dark pines make the spider thicket spooky
  place(G, 'level-1-tree', 'object.tree-world-solid.ancient-bare-02', 34.6 * TILE, 5.2 * TILE, { state: true, radius: 90, instanceId: 'level-1-webwood-dead-tree-1' });
  place(G, 'level-1-tree', 'object.tree-world-solid.ancient-bare-05', 44.8 * TILE, 7.3 * TILE, { state: true, radius: 90, instanceId: 'level-1-webwood-dead-tree-2' });
  grove(30.5, 2.5, 46.5, 7.5, ['shadow-pine-02', 'pine-05', 'pine-06', 'ancient-bare-01'], 7, 165);
  grove(19, 1.5, 26, 7, ['grove-tree-07', 'grove-tree-09', 'green-tree-06'], 3, 164);

  // rock outcrops (solid, not mineable) and pebble fields (decorative)
  const outcrop = (cx, cy, count, spread) => {
    for (let n = 0; n < count; n += 1) {
      const x = (cx + (rand() - 0.5) * spread) * TILE; const y = (cy + (rand() - 0.5) * spread) * TILE;
      const solid = rand() < 0.55;
      const variant = solid ? pickOf(['13', '15', '17', '18', '19', '20', '21', '22', '23', '24', '09', '11', '12']) : pickOf(['13', '15', '17', '18', '19', '20', '21', '22', '23', '24']);
      if (solid) tryPlace(G, 'l1-rock', `object.rock-world-wall-solid.field-${variant}`, x, y, { radius: 38, depth: 30 });
      else if (tileFree(x, y) && !blockedAt(x, y, 20)) place(G, 'l1-rock-small', `object.rock-world-wall-decorative.field-${variant}`, x, y, { root: 'root', overrides: [override('visual', 'scale', [0.7, 0.7])], decalRadius: 34 });
    }
  };
  outcrop(35, 43.5, 9, 5);
  outcrop(22, 48.5, 7, 5);
  outcrop(5.5, 29, 5, 4);
  outcrop(45.5, 50.5, 5, 4);
  outcrop(33, 3.5, 6, 5);
  outcrop(44, 4, 5, 3);
  outcrop(49, 33, 4, 3);
  // small clumps of (non-choppable) trees break up the open meadows
  const clump = (cx, cy, count, species) => {
    for (let n = 0; n < count; n += 1) {
      // forest-wall trees stay on the cell grid (their footprints tile without gaps); the visual offset keeps clumps organic
      const x = Math.floor(cx + (rand() - 0.5) * 2.6) * TILE + 32; const y = Math.floor(cy + (rand() - 0.5) * 2.2) * TILE + 54;
      const scale = round(0.85 + rand() * 0.25);
      const offset = [round((rand() - 0.5) * 28), round((rand() - 0.5) * 16)];
      tryPlace(G, 'l1-meadow-tree', `object.tree-forest-wall.${pickOf(species)}`, x, y, { radius: 44, depth: 40, overrides: [override('visual', 'visualOffset', offset), override('visual', 'scale', [scale, scale]), ...(rand() < 0.5 ? [override('visual', 'flipX', true)] : [])] });
    }
  };
  const leafy = ['green-tree-05', 'green-tree-06', 'green-tree-07'];
  const piney = ['pine-02', 'pine-03', 'pine-04', 'pine-06'];
  for (const [cx, cy, count, kind] of [
    [21.5, 38.8, 3, leafy], [27.5, 38.2, 2, piney], [19.5, 45.5, 3, piney], [29, 51.6, 4, leafy], [36.2, 49.6, 3, piney],
    [33.8, 37.8, 2, leafy], [14.2, 51.8, 3, piney], [3.8, 34.2, 2, piney], [12.5, 30.8, 3, leafy], [8.6, 18.8, 2, leafy],
    [48.5, 30.5, 2, piney], [52, 37, 3, piney], [25.2, 20.8, 2, leafy], [31.5, 11, 2, piney], [37.5, 11.2, 2, leafy],
    [32, 4.5, 3, piney], [36.5, 6.5, 2, piney], [41.5, 2.8, 3, piney], [45.5, 5, 2, piney], [43, 50, 3, piney], [50.5, 42.5, 2, leafy],
  ]) clump(cx, cy, count, kind);
  place(G, 'l1-rock-large', 'object.rock-world-wall-solid.large-02', 36.8 * TILE, 44.8 * TILE, { radius: 60 });
  place(G, 'l1-rock-large', 'object.rock-world-wall-solid.large-03', 20.2 * TILE, 50.6 * TILE, { radius: 60 });

  // new mining spots
  for (const [x, y] of [[33.4, 42.5], [38.8, 46.2], [23.4, 47.4], [44.6, 3.6]]) {
    place(G, 'level-1-stone-node', 'object.resource-stone-node', x * TILE, y * TILE, { state: true, radius: 60 });
  }
  // berry bushes around the groves
  for (const [x, y] of [[16.2, 40.6], [5.6, 33.4], [26.2, 51.2], [42.5, 44.2], [48.8, 47.3], [45.2, 51.3]]) {
    place(G, 'level-1-purple-berry', 'object.collectible-purple-berry', x * TILE, y * TILE, { root: 'root', state: true, radius: 30 });
  }
  // lakeside dock-like dressing and flowers
  force('gen-nature', 'hay-bale', 17.8 * TILE, 42.6 * TILE);
  force('gen-nature', 'campfire', 18.8 * TILE, 44.8 * TILE);
  force('gen-nature', 'canvas-tent', 20.6 * TILE, 43.2 * TILE);
}

// ── decals ────────────────────────────────────────────────────────────────
const DECAL = (name) => `object.interior-mushroom-floor-${name}`;
const clovers = [1, 2, 3, 4, 5, 6, 7, 8].map((index) => [`clover-${index}`, 1]);
const PALETTES = {
  'grass-a': { density: 0.2, decals: [...clovers, ['grass-tuft-1', 4], ['grass-tuft-2', 4], ['daisy-single', 2], ['pebbles-1', 1], ['pebbles-2', 0.8], ['petals', 0.6]] },
  flowers: { density: 0.55, decals: [['flowers-buttercup', 3], ['flowers-daisy', 3], ['flowers-forget-me-not', 2], ['flowers-mixed', 3], ['flowers-pink', 2], ['flowers-violet', 2], ['flowers-white-clover', 2], ['daisy-single', 2], ['petals', 1]] },
  'forest-moss': { density: 0.26, decals: [...clovers, ['moss-1', 2], ['moss-2', 2], ['moss-3', 2], ['moss-4', 2], ['grass-moss-1', 2], ['grass-moss-2', 2], ['fern-frond', 3], ['mushrooms-red', 0.8], ['mushrooms-brown', 0.8], ['toadstool-tiny', 1], ['leaves-fallen', 1]] },
  'forest-floor': { density: 0.2, decals: [['leaves-fallen', 6], ['twigs', 5], ['pebbles-1', 3], ['pebbles-2', 3], ['pebbles-mossy', 2], ['rock-small', 1.5], ['pinecone', 1.5], ['root-1', 0.8], ['root-3', 0.8], ['mushrooms-brown', 0.6], ['seeds', 1]] },
  'amberleaf-ground': { density: 0.34, decals: [['leaves-fallen', 6], ['leaf-big', 2], ['acorns-leaves', 4], ['mushrooms-red', 2], ['chanterelles', 2], ['mushrooms-mixed', 1.5], ['toadstool-tiny', 1.5], ['twigs', 2], ['mushrooms-ring', 0.4], ['pinecone', 1]] },
  'sanddessert-ground': { density: 0.16, decals: [['pebbles-1', 4], ['pebbles-2', 4], ['pebbles-3', 3], ['rock-small', 2], ['rock-half-buried', 1.5], ['seeds', 1]] },
  'town-cobble': { density: 0.06, decals: [['pebbles-mossy', 2], ['moss-2', 1], ['grass-tuft-1', 1.5], ['petals', 0.5]] },
};
const ROAD_PALETTE = { density: 0.1, decals: [['pebbles-1', 3], ['pebbles-2', 3], ['pebbles-3', 2], ['twigs', 1], ['stepping-stone-3', 0.6], ['stepping-stone-5', 0.6]] };
const NO_DECAL_POINTS = [];
function placeDecals() {
  let count = 0;
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      if (isWall(x, y) || isWater(x, y)) continue;
      const tile = tileAt(x, y);
      let palette = PALETTES[tile];
      if (onRoad(x, y) && tile === 'forest-floor') palette = ROAD_PALETTE;
      if (tile === 'grass-a' && noise(x / 4, y / 4, 171) > 0.62) palette = PALETTES.flowers;
      if (!palette) continue;
      for (let k = 0; k < 2; k += 1) {
        const cluster = 0.35 + noise(x / 5, y / 5, 172 + k) * 1.3;
        if (unit(x, y, 173 + k * 10) >= palette.density * cluster) continue;
        const px = round(x * TILE + 8 + unit(x, y, 174 + k * 10) * (TILE - 16));
        const py = round(y * TILE + 12 + unit(x, y, 175 + k * 10) * (TILE - 16));
        if (decalBlock.some(([bx, by, r]) => Math.hypot(bx - px, by - py) < r)) continue;
        if (NO_DECAL_POINTS.some(([bx, by]) => Math.hypot(bx - px, by - py) < 60)) continue;
        const name = weighted(palette.decals, unit(x, y, 176 + k * 10));
        const size = round(0.34 + unit(x, y, 177 + k * 10) * 0.18 * (name === 'leaf-big' ? 0.5 : 1));
        const overrides = [override('visual', 'scale', [size, size])];
        if (unit(x, y, 178 + k * 10) < 0.5) overrides.push(override('visual', 'flipX', true));
        place('gen-decals', 'l1-decal', DECAL(name), px, py, { root: 'root', overrides, decalRadius: 20 });
        count += 1;
      }
    }
  }
  return count;
}

// ── areas ─────────────────────────────────────────────────────────────────
const AREAS = [];
function area(key, kind, position, shape, extra = {}) {
  AREAS.push({ key, kind, position, shape, ...extra });
}
function defineAreas() {
  const cellRect = (i, j) => ({ x: (MAZE.x0 + i * MAZE.cell + 2) * TILE, y: (MAZE.y0 + j * MAZE.cell + 2) * TILE });
  // The maze is Fatty's alone: no spawns inside it, so nothing joins his fight.
  area('webwood', 'enemy-spawn', [39.5 * TILE, 4.8 * TILE], { shape: 'rectangle', width: 260, height: 150 }, {
    pursue: { position: [38.5 * TILE, 5.6 * TILE], shape: { shape: 'rectangle', width: 17 * TILE, height: 8 * TILE } },
    data: { enemies: [{ type: 'slime-spider', weight: 1, maxAlive: 3 }], intervalMs: 5000, maxPopulation: 3 },
  });
  area('autumn-grove', 'enemy-spawn', [46.5 * TILE, 45.5 * TILE], { shape: 'rectangle', width: 300, height: 220 }, {
    pursue: { position: [46 * TILE, 45 * TILE], shape: { shape: 'rectangle', width: 16 * TILE, height: 17 * TILE } },
    data: { enemies: [{ type: 'worm-archer', weight: 1, maxAlive: 2 }, { type: 'worm-brawler', weight: 2, maxAlive: 2 }], intervalMs: 6000, maxPopulation: 4 },
  });
  area('south-meadow', 'enemy-spawn', [27.5 * TILE, 49.5 * TILE], { shape: 'rectangle', width: 200, height: 150 }, {
    pursue: { position: [28 * TILE, 46 * TILE], shape: { shape: 'rectangle', width: 16 * TILE, height: 14 * TILE } },
    data: { enemies: [{ type: 'worm-brawler', weight: 2, maxAlive: 2 }, { type: 'slime-spider', weight: 1, maxAlive: 1 }], intervalMs: 7000, maxPopulation: 3 },
  });
}

// Existing nodes/instances that move into the new layout (ids are pinned, positions are not).
const MOVES = {
  instances: {
    'object-house-mushroom': [23.3 * TILE, 7.9 * TILE],
    'level-1-npc-village-elder-plop': [8.2 * TILE, 11.2 * TILE],
    'level-1-npc-mossy-scout': [13.4 * TILE, 10.9 * TILE],
    'level-1-npc-lili': [6.8 * TILE, 14.4 * TILE],
    'level-1-npc-red-slime-boy': [9.9 * TILE, 14.7 * TILE],
    'level-1-npc-yellow-blond-slime-girl': [13.4 * TILE, 14.8 * TILE],
    // the old orchard moves out to the west meadow grove
    'level-1-tree-01': [4.4 * TILE, 21.2 * TILE],
    'level-1-tree-02': [7.3 * TILE, 23.1 * TILE],
    'level-1-tree-03': [4.1 * TILE, 26.3 * TILE],
    'tree-world-solid-70613972': [7.6 * TILE, 28.7 * TILE],
    'level-1-purple-berry-01': [3.4 * TILE, 23.9 * TILE],
    'level-1-purple-berry-02': [6.1 * TILE, 30.4 * TILE],
    'level-1-purple-berry-03': [8.6 * TILE, 21.3 * TILE],
    'level-1-npc-fisherman-slime': [21.1 * TILE, 11.6 * TILE],
  },
  nodes: {
    'player-entry-east': [52.5 * TILE, 8.9 * TILE],
  },
};
const NPC_AREAS = {
  'area-npc-area-01': { at: 'level-1-npc-village-elder-plop', shape: { shape: 'circle', radius: 80 } },
  'area-npc-area-02': { at: 'level-1-npc-mossy-scout', shape: { shape: 'rectangle', width: 120, height: 80 } },
  'area-npc-area-03': { at: 'level-1-npc-lili', shape: { shape: 'circle', radius: 64 } },
  'area-npc-area-04': { at: 'level-1-npc-red-slime-boy', shape: { shape: 'rectangle', width: 150, height: 70 } },
  'area-npc-area-05': { at: 'level-1-npc-yellow-blond-slime-girl', shape: { shape: 'circle', radius: 64 } },
  'area-npc-area-06': { at: 'level-1-npc-fisherman-slime', shape: { shape: 'rectangle', width: 150, height: 48 } },
};
const SAFE_ZONE = { position: [14 * TILE, 10 * TILE], shape: { shape: 'rectangle', width: 24 * TILE, height: 16 * TILE } };
// Instances the new layout drops (hand-placed enemies bypass spawn areas: no XP, no respawn, no quest credit).
const REMOVE_INSTANCES = new Set(['character-slime-spider', 'character-worm-archer', 'object-decoration-world-solid']);

// ── scene assembly ────────────────────────────────────────────────────────
function assemble(scene) {
  const GEN_GROUP = (id) => id.startsWith('gen-');
  const genNodeIds = new Set(scene.nodes.filter((node) => GEN_GROUP(node.id) || node.id.startsWith('area-level-1-gen-')).map((node) => node.id));
  // descendants of generated area nodes
  let grew = true;
  while (grew) {
    grew = false;
    for (const node of scene.nodes) if (node.parentId && genNodeIds.has(node.parentId) && !genNodeIds.has(node.id)) { genNodeIds.add(node.id); grew = true; }
  }
  scene.nodes = scene.nodes.filter((node) => !genNodeIds.has(node.id));
  scene.instances = scene.instances.filter((instance) => !genNodeIds.has(instance.parentNodeId) && !REMOVE_INSTANCES.has(instance.instanceId));
  scene.subresources = scene.subresources.filter((resource) => !resource.resourceId.startsWith('level-1.area-level-1-gen-'));

  // terrain
  const tileData = scene.subresources.find((resource) => resource.kind === 'tile-data');
  tileData.cells = [];
  for (let y = 0; y < N; y += 1) for (let x = 0; x < N; x += 1) tileData.cells.push({ x, y, tileId: terrain[y][x] });

  // moved instances and nodes
  const positionOverride = (instance) => instance.overrides.find((entry) => entry.sourceInstancePath.length === 0 && entry.property === 'position');
  for (const [id, [x, y]] of Object.entries(MOVES.instances)) {
    const instance = scene.instances.find((entry) => entry.instanceId === id);
    if (!instance) throw new Error(`missing instance ${id}`);
    positionOverride(instance).value = [round(x), round(y)];
  }
  for (const [id, [x, y]] of Object.entries(MOVES.nodes)) scene.nodes.find((node) => node.id === id).properties.position = [round(x), round(y)];
  // the mushroom house door and its arrival follow the house (door sits 16px above the house base)
  const mushroom = MOVES.instances['object-house-mushroom'];
  const mushroomDoor = scene.nodes.find((node) => node.name === 'mushroom-door-level-1');
  mushroomDoor.properties.position = [round(mushroom[0] + 1), round(mushroom[1] - 16)];
  const metadata = scene.nodes.find((node) => node.id === 'world-definition').properties.metadata;
  metadata.player.entries.east = { x: MOVES.nodes['player-entry-east'][0], y: MOVES.nodes['player-entry-east'][1] };

  // NPC wander areas follow their NPCs; the enemy safe zone covers the town
  for (const [nodeId, spec] of Object.entries(NPC_AREAS)) {
    const node = scene.nodes.find((entry) => entry.id === nodeId);
    node.properties.position = positionOverride(scene.instances.find((entry) => entry.instanceId === spec.at)).value.slice();
    scene.subresources.find((resource) => resource.resourceId === `level-1.${nodeId}.shape`).value = spec.shape;
  }
  scene.nodes.find((node) => node.id === 'area-enemy-safe-1').properties.position = SAFE_ZONE.position;
  scene.subresources.find((resource) => resource.resourceId === 'level-1.area-enemy-safe-1.shape').value = SAFE_ZONE.shape;

  // generated area nodes
  const music = scene.nodes.find((node) => node.id === 'sfx-music-player');
  scene.nodes = scene.nodes.filter((node) => node !== music);
  const musicResource = scene.subresources.find((resource) => resource.resourceId === 'music.level-1-home-town');
  scene.subresources = scene.subresources.filter((resource) => resource !== musicResource);
  for (const spec of AREAS) {
    const id = `area-level-1-gen-${spec.key}`;
    const areaId = `level-1-${spec.key}`;
    const pursueOffset = [round(spec.pursue.position[0] - spec.position[0]), round(spec.pursue.position[1] - spec.position[1])];
    scene.nodes.push(
      { id, name: `level-1-${spec.key}`, type: 'Area2D', parentId: 'world', order: 0, properties: { position: spec.position.map(round), collisionLayer: 512, collisionMask: 0, monitoring: false, monitorable: false } },
      { id: `${id}-shape`, name: 'pursue-shape', type: 'CollisionShape2D', parentId: id, order: 0, properties: { shape: { resourceId: `level-1.${id}.shape` }, position: pursueOffset } },
      { id: `${id}-stay-shape`, name: 'stay-shape', type: 'CollisionShape2D', parentId: id, order: 1, properties: { shape: { resourceId: `level-1.${id}.stay-shape` } } },
      { id: `${id}-script`, name: 'world-area-script', type: 'ScriptNode', scriptId: 'game.world-area', parentId: id, order: 2, properties: {
        areaKind: spec.kind, areaId, area: { nodeId: id }, data: spec.data, shape: { nodeId: `${id}-shape` }, stayShape: { nodeId: `${id}-stay-shape` },
      } },
    );
    scene.subresources.push(
      { version: 1, resourceId: `level-1.${id}.shape`, kind: 'collision-shape', value: spec.pursue.shape },
      { version: 1, resourceId: `level-1.${id}.stay-shape`, kind: 'collision-shape', value: spec.shape },
    );
  }

  // grouping nodes
  const groupOrder = ['gen-forest', 'gen-pocket', 'gen-thicket', 'gen-maze', 'gen-ruins', 'gen-town', 'gen-nature', 'gen-landmarks', 'gen-decals'];
  const names = { 'gen-forest': 'Forest Border', 'gen-pocket': 'Gate Pocket', 'gen-thicket': 'Webwood', 'gen-maze': 'Fatty Maze', 'gen-ruins': 'Worm Ruins', 'gen-town': 'Slimeshire', 'gen-nature': 'Nature', 'gen-landmarks': 'Landmarks', 'gen-decals': 'Ground Decals' };
  for (const id of groupOrder) {
    const entry = groups.get(id);
    if (!entry) continue;
    scene.nodes.push({ id, name: names[id], type: 'Node2D', parentId: 'world', order: 0, properties: { position: [0, 0] } });
    entry.instances.forEach((instance, index) => scene.instances.push({ ...instance, parentNodeId: id, order: index }));
  }

  // dense sibling order under world (nodes and instances together); the world's
  // audio players (music, then ambience beds from audio:wire) come last
  scene.nodes.push(music);
  const audioPlayers = [music, ...scene.nodes.filter((node) => node.parentId === 'world' && node !== music && node.id.startsWith('sfx-'))];
  const worldChildren = [
    ...scene.nodes.filter((node) => node.parentId === 'world' && !audioPlayers.includes(node)),
    ...scene.instances.filter((instance) => instance.parentNodeId === 'world'),
  ];
  worldChildren.forEach((child, index) => { child.order = index; });
  audioPlayers.forEach((node, index) => { node.order = worldChildren.length + index; });
  scene.subresources.push(musicResource);
  // instance entries: keep the documented key order
  scene.instances = scene.instances.map(({ instanceId, name, sceneId, parentNodeId, order, persistenceKey, overrides }) => ({ instanceId, name, sceneId, parentNodeId, order, persistenceKey, overrides }));
  return scene;
}

// ── run ───────────────────────────────────────────────────────────────────
const text = readFileSync(SCENE_PATH, 'utf8');
const crlf = text.includes('\r\n');
const scene = JSON.parse(text);

paintTerrain();
findBridges();
buildWalls();
// keep the pinned markers, houses and key spots clear of walls/props
const KEEP_CLEAR = [[640, 704, 90], [512, 512, 60], [CAMP.x, CAMP.y, ARENA_RADIUS * TILE], [CAMP.x + CHEST_OFFSET.x, CAMP.y + CHEST_OFFSET.y, 60], [1200, 1550, 60], [1081, 990, 60],
  [MOVES.nodes['player-entry-east'][0], MOVES.nodes['player-entry-east'][1], 70]];
for (const [x, y, r] of KEEP_CLEAR) { occupied.push([x, y, r]); NO_DECAL_POINTS.push([x, y]); }
// existing solid instances also block new props
for (const instance of scene.instances) {
  const position = MOVES.instances[instance.instanceId] ?? instance.overrides.find((entry) => entry.property === 'position')?.value;
  if (!position || REMOVE_INSTANCES.has(instance.instanceId) || instance.parentNodeId?.startsWith('gen-')) continue;
  const big = /house|workshop/.test(instance.sceneId) ? 170 : /fatty-camp/.test(instance.sceneId) ? 0 : 48;
  if (big) { occupied.push([position[0], position[1] - (big > 100 ? 90 : 0), big]); decalBlock.push([position[0], position[1] - (big > 100 ? 80 : 0), big + 10]); }
}
placeLandmarks();
placeWalls();
placeTown();
placeFattyCamp();
placeRuins();
placeNature();
defineAreas();
const decalCount = placeDecals();
assemble(scene);

const counts = [...groups.values()].map((entry) => `${entry.id}:${entry.instances.length}`).join(' ');
console.log(`instances ${scene.instances.length} (decals ${decalCount}) ${counts}`);
if (ASCII) {
  const glyph = { 'grass-a': '.', 'forest-moss': ',', 'forest-floor': ':', 'cavern-floor': 'o', water: '~', 'deep-water': 'W', 'sanddessert-ground': 's', 'amberleaf-ground': 'a' };
  for (let y = 0; y < N; y += 1) {
    console.log(Array.from({ length: N }, (_, x) => (wall[y][x] ? '#' : glyph[terrain[y][x]] ?? '?')).join(''));
  }
}
if (WRITE) {
  const output = `${JSON.stringify(scene, null, 2)}\n`;
  writeFileSync(SCENE_PATH, crlf ? output.replace(/\n/g, '\r\n') : output);
  console.log(`wrote ${SCENE_PATH}`);
} else {
  console.log('dry run: pass --write to apply');
}
