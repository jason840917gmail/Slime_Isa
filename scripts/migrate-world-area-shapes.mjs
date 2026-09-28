#!/usr/bin/env node
// One-shot migration: world areas (game.world-area) used to keep their
// perimeters as raw JSON in `data`. Their geometry now comes from the
// CollisionShape2D nodes the script references (`shape`, and `stayShape` for
// enemy spawn areas), so Scene Studio's shape handles edit it directly.
//
// For each unmigrated area this script:
//   - places the existing shape exactly on the stored perimeter (data wins),
//   - adds a `stay-shape` CollisionShape2D for enemy spawn areas,
//   - points the script's `shape` / `stayShape` at those nodes,
//   - strips the geometry (and the redundant id) from `data`.
//
// Dry run by default; pass --apply to write files.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const authoredRoot = path.join(root, 'src/game/content/scenes/authored');
const apply = process.argv.includes('--apply');

function discover(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const candidate = path.join(directory, entry.name);
    return entry.isDirectory() ? discover(candidate) : entry.name.endsWith('.scene.json') ? [candidate] : [];
  }).sort();
}

function globalPosition(document, nodeId) {
  let x = 0;
  let y = 0;
  for (let node = document.nodes.find((candidate) => candidate.id === nodeId); node; node = document.nodes.find((candidate) => candidate.id === node.parentId)) {
    const { position, rotation, scale } = node.properties;
    if ((typeof rotation === 'number' && rotation !== 0) || (Array.isArray(scale) && (scale[0] !== 1 || scale[1] !== 1))) {
      throw new Error(`node '${node.id}' is rotated or scaled; migrate this area by hand`);
    }
    if (Array.isArray(position)) { x += position[0]; y += position[1]; }
  }
  return [x, y];
}

function shapeFor(perimeter, areaGlobal) {
  const rectangle = perimeter.shape === 'rectangle' || perimeter.w !== undefined;
  const center = rectangle ? [perimeter.x + perimeter.w / 2, perimeter.y + perimeter.h / 2] : [perimeter.x, perimeter.y];
  return {
    offset: [center[0] - areaGlobal[0], center[1] - areaGlobal[1]],
    value: rectangle ? { shape: 'rectangle', width: perimeter.w, height: perimeter.h } : { shape: 'circle', radius: perimeter.radius },
  };
}

function placeShape(node, offset) {
  if (offset[0] === 0 && offset[1] === 0) delete node.properties.position;
  else node.properties.position = offset;
}

function uniqueId(base, taken) {
  let id = base;
  for (let suffix = 2; taken.has(id); suffix += 1) id = `${base}-${suffix}`;
  taken.add(id);
  return id;
}

const report = [];
let changedFiles = 0;
for (const file of discover(authoredRoot)) {
  const text = readFileSync(file, 'utf8');
  const document = JSON.parse(text);
  const scripts = document.nodes.filter((node) => node.scriptId === 'game.world-area' && node.properties.shape === undefined);
  if (scripts.length === 0) continue;
  const relative = path.relative(root, file).replaceAll('\\', '/');
  const nodeIds = new Set(document.nodes.map((node) => node.id));
  const resourceIds = new Set((document.subresources ?? []).map((resource) => resource.resourceId));
  for (const script of scripts) {
    const { areaKind, areaId } = script.properties;
    const data = { ...script.properties.data };
    const where = `${relative} · ${areaId}`;
    const areaNodeId = script.properties.area?.nodeId;
    const area = document.nodes.find((node) => node.id === areaNodeId);
    if (!area) throw new Error(`${where}: area node '${areaNodeId}' is missing`);
    const shapes = document.nodes.filter((node) => node.parentId === area.id && node.type === 'CollisionShape2D');
    if (shapes.length !== 1) throw new Error(`${where}: expected exactly one CollisionShape2D, found ${shapes.length}`);
    const [primary] = shapes;
    const primaryResourceId = primary.properties.shape?.resourceId;
    const primaryResource = document.subresources?.find((resource) => resource.resourceId === primaryResourceId);
    if (!primaryResource) throw new Error(`${where}: shape resource '${primaryResourceId}' is not a local subresource`);
    const areaGlobal = globalPosition(document, area.id);

    const outerPerimeter = areaKind === 'enemy-safe-zone' ? { shape: 'rectangle', ...data }
      : areaKind === 'enemy-spawn' ? data.pursuePerimeter : data.perimeter;
    if (!outerPerimeter) throw new Error(`${where}: no stored perimeter in data`);
    const outer = shapeFor(outerPerimeter, areaGlobal);
    const before = JSON.stringify([primary.properties.position ?? [0, 0], primaryResource.value]);
    placeShape(primary, outer.offset);
    primaryResource.value = outer.value;
    const notes = [];
    if (before !== JSON.stringify([primary.properties.position ?? [0, 0], primaryResource.value])) notes.push('shape realigned to stored perimeter');
    if (data.id !== undefined && data.id !== areaId) notes.push(`data.id '${data.id}' differs from areaId; areaId kept`);

    script.properties.shape = { nodeId: primary.id };
    if (areaKind === 'enemy-spawn') {
      primary.name = 'pursue-shape';
      const stay = shapeFor(data.stayPerimeter, areaGlobal);
      const stayId = uniqueId(`${area.id}-stay-shape`, nodeIds);
      const stayResourceId = uniqueId(String(primaryResourceId).replace(/\.shape$/, '') + '.stay-shape', resourceIds);
      const stayNode = { id: stayId, name: 'stay-shape', type: 'CollisionShape2D', parentId: area.id, order: 0, properties: { shape: { resourceId: stayResourceId } } };
      placeShape(stayNode, stay.offset);
      document.nodes.splice(document.nodes.indexOf(primary) + 1, 0, stayNode);
      document.subresources.splice(document.subresources.indexOf(primaryResource) + 1, 0, { version: 1, resourceId: stayResourceId, kind: 'collision-shape', value: stay.value });
      script.properties.stayShape = { nodeId: stayId };
      delete data.stayPerimeter;
      delete data.pursuePerimeter;
    } else if (areaKind === 'npc-wander') {
      delete data.perimeter;
    } else {
      for (const key of ['x', 'y', 'w', 'h', 'shape']) delete data[key];
    }
    delete data.id;
    script.properties.data = data;

    // Dense child order under the area: shapes first, then the script, then anything else.
    const children = document.nodes.filter((node) => node.parentId === area.id);
    const rank = (node) => node.type === 'CollisionShape2D' ? (node.id === primary.id ? 0 : 1) : node.id === script.id ? 2 : 3;
    [...children].sort((left, right) => rank(left) - rank(right) || left.order - right.order).forEach((node, index) => { node.order = index; });
    report.push(`${where} (${areaKind})${notes.length ? ` — ${notes.join('; ')}` : ''}`);
  }
  const next = `${JSON.stringify(document, null, 2)}\n`;
  if (next !== text) {
    changedFiles += 1;
    if (apply) writeFileSync(file, next);
  }
}

console.log(report.join('\n'));
console.log(`${apply ? 'Migrated' : 'Would migrate'} ${report.length} world area(s) in ${changedFiles} file(s).${apply ? '' : ' Re-run with --apply to write.'}`);
