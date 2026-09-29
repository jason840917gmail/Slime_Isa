#!/usr/bin/env node
// Converts wall TILES into placed wall OBJECTS: every `crystal-wall` /
// `tree-wall` cell becomes its surrounding floor tile plus one authored
// instance of a wall prop scene (scripts/props/generate-wall-prop-scenes.py).
// Ground stays ground; walls become selectable, movable objects in Scene
// Studio with their own collision.
//
// Bodies sit on the cell grid (so neighbouring 48x44 footprints leave gaps
// smaller than the player) while each instance gets a deterministic visual
// offset, flip, size and variant for an organic look.
//
// Usage: node scripts/maps/convert-wall-tiles.mjs <world-id>... [--write]
// (dry run by default)
import { readFileSync, writeFileSync } from 'node:fs';

const TILE = 64;
/** Body anchor inside the cell: footprint (44px tall, centred 22px above) spans y+10..y+54. */
const ANCHOR = [32, 54];
const RULES = {
  'crystal-wall': {
    family: 'crystal-cluster-wall',
    variants: Array.from({ length: 16 }, (_, index) => String(index + 1).padStart(2, '0')),
    fallbackFloor: 'cavern-floor',
    scale: [0.95, 1.25],
    offset: [10, 6],
  },
  'tree-wall': {
    family: 'tree-forest-wall',
    variants: ['pine-02', 'pine-03', 'pine-04', 'pine-06', 'pine-07', 'green-tree-05', 'green-tree-06', 'green-tree-07'],
    fallbackFloor: 'forest-floor',
    scale: [0.9, 1.1],
    offset: [10, 6],
  },
};

const args = process.argv.slice(2);
const write = args.includes('--write');
const worlds = args.filter((argument) => !argument.startsWith('--'));
if (worlds.length === 0) throw new Error('Usage: node scripts/maps/convert-wall-tiles.mjs <world-id>... [--write]');

const tiles = JSON.parse(readFileSync('src/game/content/scenes/authored/resources/terrain/terrain.tile-set.resource.json', 'utf8')).tiles;
const isFloor = (tileId) => Boolean(tiles[tileId]) && tiles[tileId].physics === null && !tiles[tileId].tags.includes('water') && !RULES[tileId];

function unit(x, y, salt) {
  let hash = Math.imul(x + 0x9e37, 0x27d4eb2d) ^ Math.imul(y - 0x7f4a, 0x165667b1) ^ Math.imul(salt, 0x45d9f3b);
  hash = Math.imul(hash ^ (hash >>> 15), 0x2c1b3c6d);
  hash = Math.imul(hash ^ (hash >>> 12), 0x297a2d39);
  return ((hash ^ (hash >>> 15)) >>> 0) / 4294967296;
}
const hex8 = (world, x, y) => {
  let hash = 2166136261;
  for (const char of `${world}:${x}:${y}`) hash = Math.imul(hash ^ char.charCodeAt(0), 16777619);
  return (hash >>> 0).toString(16).padStart(8, '0');
};
const round = (value) => Math.round(value * 100) / 100;
const override = (sourceNodeId, property, value) => ({ sourceInstancePath: [], sourceNodeId, property, value });

for (const world of worlds) {
  const path = `src/game/content/scenes/authored/worlds/${world}.scene.json`;
  const text = readFileSync(path, 'utf8');
  const crlf = text.includes('\r\n');
  const scene = JSON.parse(text);
  const data = (scene.subresources ?? []).find((resource) => resource.kind === 'tile-data');
  if (!data) throw new Error(`${world}: no tile-data subresource`);
  const grid = new Map(data.cells.map((cell) => [`${cell.x},${cell.y}`, cell.tileId]));
  const existing = new Set((scene.instances ?? []).map((instance) => instance.instanceId));
  // Child order is one dense sequence across the world's nodes and instances.
  let order = Math.max(-1,
    ...scene.nodes.filter((node) => node.parentId === 'world').map((node) => node.order),
    ...(scene.instances ?? []).filter((instance) => instance.parentNodeId === 'world').map((instance) => instance.order)) + 1;
  const added = [];
  const counts = {};

  for (const cell of data.cells) {
    const rule = RULES[cell.tileId];
    if (!rule) continue;
    const floorCounts = new Map();
    for (let dy = -1; dy <= 1; dy += 1) for (let dx = -1; dx <= 1; dx += 1) {
      const neighbour = grid.get(`${cell.x + dx},${cell.y + dy}`);
      if (neighbour && isFloor(neighbour)) floorCounts.set(neighbour, (floorCounts.get(neighbour) ?? 0) + 1);
    }
    const floor = [...floorCounts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0] ?? rule.fallbackFloor;
    counts[`${cell.tileId} -> ${floor} + ${rule.family}`] = (counts[`${cell.tileId} -> ${floor} + ${rule.family}`] ?? 0) + 1;
    cell.tileId = floor;

    const instanceId = `${rule.family}-${hex8(world, cell.x, cell.y)}`;
    if (existing.has(instanceId)) throw new Error(`${world}: instance '${instanceId}' already exists`);
    const variant = rule.variants[Math.floor(unit(cell.x, cell.y, 1) * rule.variants.length)];
    const size = rule.scale[0] + unit(cell.x, cell.y, 2) * (rule.scale[1] - rule.scale[0]);
    const flip = unit(cell.x, cell.y, 3) < 0.5;
    added.push({
      instanceId,
      name: instanceId,
      sceneId: `object.${rule.family}.${variant}`,
      parentNodeId: 'world',
      order: order++,
      persistenceKey: `${world}.${instanceId}`,
      overrides: [
        override('body', 'position', [cell.x * TILE + ANCHOR[0], cell.y * TILE + ANCHOR[1]]),
        override('visual', 'visualOffset', [
          round((unit(cell.x, cell.y, 4) * 2 - 1) * rule.offset[0]),
          round((unit(cell.x, cell.y, 5) * 2 - 1) * rule.offset[1]),
        ]),
        // Node2D scale must stay positive; mirroring uses Sprite2D flipX.
        override('visual', 'scale', [round(size), round(size)]),
        ...(flip ? [override('visual', 'flipX', true)] : []),
      ],
    });
  }

  console.log(world, `${added.length} wall props`, counts);
  if (write && added.length > 0) {
    scene.instances = [...(scene.instances ?? []), ...added];
    const output = `${JSON.stringify(scene, null, 2)}\n`;
    writeFileSync(path, crlf ? output.replace(/\n/g, '\r\n') : output);
  }
}
if (!write) console.log('dry run: pass --write to apply');
