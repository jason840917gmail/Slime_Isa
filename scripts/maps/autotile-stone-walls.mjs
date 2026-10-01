#!/usr/bin/env node
// Picks the right stone wall piece for every `object.wall-stone-solid.*`
// instance in a world from its neighbours on the 64 px wall grid:
// straight runs, end caps, corners (┌ ┐ └ ┘), T-junctions (┬ ┴ ├ ┤) and
// crossings (┼). Straight pieces keep their art variant. Instances stacked on
// the same spot are kept (legacy map placements own them) but always show the
// same piece as the first one there. Dry run by default.
//   node scripts/maps/autotile-stone-walls.mjs <world-id>... [--write]
import { readFileSync, writeFileSync } from 'node:fs';

const GRID = 64;
const PREFIX = 'object.wall-stone-solid.';
const args = process.argv.slice(2);
const write = args.includes('--write');
const worlds = args.filter((arg) => !arg.startsWith('--'));
if (worlds.length === 0) {
  console.error('usage: node scripts/maps/autotile-stone-walls.mjs <world-id>... [--write]');
  process.exit(1);
}

const TEES = { LRD: 'junction-01', LRU: 'junction-02', DRU: 'junction-03', DLU: 'junction-04', DLRU: 'junction-05' };
const CORNERS = { DR: 'corner-01', DL: 'corner-03', RU: 'corner-05', LU: 'corner-07' };
const MID_HORIZONTAL = /^horizontal-0[2-7]$/;
const MID_VERTICAL = /^vertical-0[1-7]$/;

function piece(current, links) {
  const key = [...links].sort().join('');
  if (TEES[key]) return TEES[key];
  if (CORNERS[key]) return CORNERS[key];
  const horizontal = links.has('L') || links.has('R');
  const vertical = links.has('U') || links.has('D');
  if (horizontal && !vertical) {
    if (!links.has('R')) return 'horizontal-08'; // right end cap
    return MID_HORIZONTAL.test(current) ? current : 'horizontal-02';
  }
  if (vertical && !horizontal) {
    if (!links.has('D')) return 'vertical-08'; // bottom end cap
    return MID_VERTICAL.test(current) ? current : 'vertical-02';
  }
  return current; // isolated piece: leave as authored
}

function positionOf(instance) {
  return instance.overrides?.find((override) => override.sourceNodeId === 'body' && override.property === 'position' && override.sourceInstancePath.length === 0)?.value;
}

for (const world of worlds) {
  const path = `src/game/content/scenes/authored/worlds/${world}.scene.json`;
  const before = readFileSync(path, 'utf8');
  const scene = JSON.parse(before);
  const walls = new Map();
  const stacked = [];
  for (const instance of scene.instances) {
    if (!instance.sceneId.startsWith(PREFIX)) continue;
    const position = positionOf(instance);
    if (!position) continue;
    const spot = `${position[0]},${position[1]}`;
    if (walls.has(spot)) stacked.push([spot, instance]);
    else walls.set(spot, instance);
  }
  const changes = [];
  for (const [spot, instance] of walls) {
    const [x, y] = spot.split(',').map(Number);
    const links = new Set();
    if (walls.has(`${x - GRID},${y}`)) links.add('L');
    if (walls.has(`${x + GRID},${y}`)) links.add('R');
    if (walls.has(`${x},${y - GRID}`)) links.add('U');
    if (walls.has(`${x},${y + GRID}`)) links.add('D');
    const current = instance.sceneId.slice(PREFIX.length);
    const next = piece(current, links);
    if (next !== current) {
      changes.push(`${spot}: ${current} -> ${next}`);
      instance.sceneId = PREFIX + next;
    }
  }
  let aligned = 0;
  for (const [spot, instance] of stacked) {
    const sceneId = walls.get(spot).sceneId;
    if (instance.sceneId !== sceneId) { instance.sceneId = sceneId; aligned += 1; }
  }
  // Sibling order must stay the dense sequence 0..n-1 per parent.
  const parents = new Set(scene.instances.filter((instance) => instance.sceneId.startsWith(PREFIX)).map((instance) => instance.parentNodeId));
  let reordered = 0;
  for (const parent of parents) {
    const siblings = [
      ...scene.nodes.filter((node) => node.parentId === parent),
      ...scene.instances.filter((instance) => instance.parentNodeId === parent),
    ].sort((left, right) => left.order - right.order);
    siblings.forEach((child, index) => { if (child.order !== index) { child.order = index; reordered += 1; } });
  }
  console.log(`${world}: ${changes.length} piece change(s), ${aligned} stacked instance(s) aligned`);
  for (const change of changes) console.log(`  ${change}`);
  if (write && (changes.length || aligned || reordered)) writeFileSync(path, `${JSON.stringify(scene, null, 2)}\n`);
}
