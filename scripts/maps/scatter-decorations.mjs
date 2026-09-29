#!/usr/bin/env node
// Scatters walk-over ground decorations (fallen leaves, twigs, roots, clover,
// moss, pebbles, small mushrooms) over a world as authored object instances.
// Grounds stay mostly plain; detail comes from these objects, which are real
// scene instances you can select, move, or delete in Scene Studio. They are
// grouped under a `decorations` Node2D in the world so the outliner stays tidy.
//
// Decorations are the mushroom-floor decal scenes (object.interior-mushroom-
// floor-*): Sprite2D only, `ground-decals` depth band, no collision. Placement
// is deterministic and clustered by value noise; cells with water, walls,
// other objects, or the player spawn/entries are left clear.
//
// Usage: node scripts/maps/scatter-decorations.mjs <world-id>... [--write]
// (dry run by default; re-running replaces the world's previous decorations)
import { readFileSync, writeFileSync } from 'node:fs';

const TILE = 64;
const GROUP_ID = 'decorations';
const ID_PREFIX = 'ground-decal-';
const DECAL = (name) => `object.interior-mushroom-floor-${name}`;

/** Palettes per ground tile: [decal name, weight]. Leaves, twigs and roots dominate forest soil. */
const PALETTES = {
  'forest-floor': {
    density: 0.3,
    decals: [
      ['leaves-fallen', 10], ['twigs', 8], ['acorns-leaves', 4], ['pinecone', 3], ['seeds', 2],
      ...[1, 2, 3, 4, 5, 6, 7, 8].map((index) => [`root-${index}`, 1.2]),
      ['pebbles-1', 1.5], ['pebbles-2', 1.5], ['pebbles-mossy', 1.5], ['rock-mossy-small', 1],
      ['fern-frond', 2.5], ['mushrooms-brown', 1.2], ['mushrooms-mixed', 0.8], ['chanterelles', 0.8], ['toadstool-tiny', 1],
      ['leaf-big', 0.6],
    ],
  },
  'forest-moss': {
    density: 0.22,
    decals: [
      ...[1, 2, 3, 4, 5, 6, 7, 8].map((index) => [`clover-${index}`, 1.5]),
      ['moss-1', 2], ['moss-2', 2], ['moss-3', 2], ['moss-4', 2], ['grass-moss-1', 2], ['grass-moss-2', 2],
      ['fern-frond', 2], ['leaves-fallen', 3], ['twigs', 2], ['flowers-white-clover', 1], ['daisy-single', 1],
      ['mushrooms-red', 0.8], ['toadstool-tiny', 1],
    ],
  },
};
/** Sprite scale range (frames are 128px; ~0.45 keeps a decal smaller than the player). */
const SCALE = [0.34, 0.52];
const CLEAR_RADIUS = 44; // px kept free around other objects and spawn points

const args = process.argv.slice(2);
const write = args.includes('--write');
const worlds = args.filter((argument) => !argument.startsWith('--'));
if (worlds.length === 0) throw new Error('Usage: node scripts/maps/scatter-decorations.mjs <world-id>... [--write]');

function unit(x, y, salt) {
  let hash = Math.imul(x + 0x3c6e, 0x27d4eb2d) ^ Math.imul(y - 0x1f83, 0x165667b1) ^ Math.imul(salt, 0x45d9f3b);
  hash = Math.imul(hash ^ (hash >>> 15), 0x2c1b3c6d);
  hash = Math.imul(hash ^ (hash >>> 12), 0x297a2d39);
  return ((hash ^ (hash >>> 15)) >>> 0) / 4294967296;
}
function valueNoise(x, y) {
  const x0 = Math.floor(x); const y0 = Math.floor(y); const fx = x - x0; const fy = y - y0;
  const sx = fx * fx * (3 - 2 * fx); const sy = fy * fy * (3 - 2 * fy);
  const top = unit(x0, y0, 99) + (unit(x0 + 1, y0, 99) - unit(x0, y0, 99)) * sx;
  const bottom = unit(x0, y0 + 1, 99) + (unit(x0 + 1, y0 + 1, 99) - unit(x0, y0 + 1, 99)) * sx;
  return top + (bottom - top) * sy;
}
const hex8 = (text) => {
  let hash = 2166136261;
  for (const char of text) hash = Math.imul(hash ^ char.charCodeAt(0), 16777619);
  return (hash >>> 0).toString(16).padStart(8, '0');
};
const round = (value) => Math.round(value * 100) / 100;
const override = (sourceNodeId, property, value) => ({ sourceInstancePath: [], sourceNodeId, property, value });
function pick(decals, roll) {
  const total = decals.reduce((sum, [, weight]) => sum + weight, 0);
  let cursor = roll * total;
  for (const [name, weight] of decals) { cursor -= weight; if (cursor <= 0) return name; }
  return decals.at(-1)[0];
}
const instancePosition = (instance) => instance.overrides.find((entry) => entry.sourceInstancePath.length === 0
  && entry.property === 'position' && ['body', 'root'].includes(entry.sourceNodeId))?.value;

for (const world of worlds) {
  const path = `src/game/content/scenes/authored/worlds/${world}.scene.json`;
  const text = readFileSync(path, 'utf8');
  const crlf = text.includes('\r\n');
  const scene = JSON.parse(text);
  const data = (scene.subresources ?? []).find((resource) => resource.kind === 'tile-data');
  if (!data) throw new Error(`${world}: no tile-data subresource`);

  // Re-running replaces the previous decorations.
  scene.instances = (scene.instances ?? []).filter((instance) => !instance.instanceId.startsWith(ID_PREFIX));
  if (!scene.nodes.some((node) => node.id === GROUP_ID)) {
    const order = Math.max(-1,
      ...scene.nodes.filter((node) => node.parentId === 'world').map((node) => node.order),
      ...scene.instances.filter((instance) => instance.parentNodeId === 'world').map((instance) => instance.order)) + 1;
    scene.nodes.push({ id: GROUP_ID, name: 'Decorations', type: 'Node2D', parentId: 'world', order, properties: { position: [0, 0] } });
  }

  const blocked = [
    ...scene.instances.map(instancePosition).filter(Boolean),
    ...scene.nodes.filter((node) => /^player-(spawn|entry)/.test(node.id)).map((node) => node.properties.position),
  ];
  const added = [];
  const counts = {};
  for (const cell of data.cells) {
    const palette = PALETTES[cell.tileId];
    if (!palette) continue;
    const cluster = 0.35 + valueNoise(cell.x / 5, cell.y / 5) * 1.3; // clumps: sparse to about 1.65x
    if (unit(cell.x, cell.y, 1) >= palette.density * cluster) continue;
    const x = round(cell.x * TILE + 8 + unit(cell.x, cell.y, 2) * (TILE - 16));
    const y = round(cell.y * TILE + 12 + unit(cell.x, cell.y, 3) * (TILE - 16));
    if (blocked.some(([bx, by]) => Math.hypot(bx - x, by - y) < CLEAR_RADIUS)) continue;
    const name = pick(palette.decals, unit(cell.x, cell.y, 4));
    const size = SCALE[0] + unit(cell.x, cell.y, 5) * (SCALE[1] - SCALE[0]) * (name === 'leaf-big' ? 0.5 : 1);
    const instanceId = `${ID_PREFIX}${hex8(`${world}:${cell.x}:${cell.y}`)}`;
    counts[name] = (counts[name] ?? 0) + 1;
    added.push({
      instanceId,
      name: instanceId,
      sceneId: DECAL(name),
      parentNodeId: GROUP_ID,
      order: added.length,
      persistenceKey: `${world}.${instanceId}`,
      overrides: [
        override('root', 'position', [x, y]),
        override('visual', 'scale', [round(size), round(size)]),
        ...(unit(cell.x, cell.y, 6) < 0.5 ? [override('visual', 'flipX', true)] : []),
      ],
    });
  }
  console.log(world, `${added.length} decorations`, Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([k, v]) => `${k}:${v}`).join(' '));
  if (write) {
    scene.instances = [...scene.instances, ...added];
    const output = `${JSON.stringify(scene, null, 2)}\n`;
    writeFileSync(path, crlf ? output.replace(/\n/g, '\r\n') : output);
  }
}
if (!write) console.log('dry run: pass --write to apply');
