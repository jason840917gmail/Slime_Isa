#!/usr/bin/env node
// Smooths noisy authored terrain in world scenes so materials form readable
// regions instead of single-cell speckle. Only ever makes terrain MORE
// walkable: floor cells may switch to a neighbouring floor material, and
// isolated wall/water cells become their surrounding floor. It never creates
// walls or water, so spawns, exits and objects can never become blocked.
//
// Usage: node scripts/maps/smooth-terrain.mjs <world-id>... [--write]
// (dry run by default; prints what would change)
import { readFileSync, writeFileSync } from 'node:fs';

const TILE_SET_PATH = 'src/game/content/scenes/authored/resources/terrain/terrain.tile-set.resource.json';
const FLOOR_PASSES = 3;
const FLOOR_MAJORITY = 5; // of 8 neighbours
const ISOLATED_MAX_SAME = 1; // wall/water cells with at most this many same neighbours are removed

const args = process.argv.slice(2);
const write = args.includes('--write');
const worlds = args.filter((argument) => !argument.startsWith('--'));
if (worlds.length === 0) throw new Error('Usage: node scripts/maps/smooth-terrain.mjs <world-id>... [--write]');

const tiles = JSON.parse(readFileSync(TILE_SET_PATH, 'utf8')).tiles;
const isBlocker = (tileId) => tiles[tileId]?.physics !== null;
const isWater = (tileId) => tiles[tileId]?.tags.includes('water');
const isFloor = (tileId) => Boolean(tiles[tileId]) && !isBlocker(tileId) && !isWater(tileId);

const NEIGHBOURS = [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]];

function neighbourCounts(grid, x, y) {
  const counts = new Map();
  for (const [dx, dy] of NEIGHBOURS) {
    const tileId = grid[y + dy]?.[x + dx];
    if (tileId !== undefined) counts.set(tileId, (counts.get(tileId) ?? 0) + 1);
  }
  return counts;
}

function mostCommon(counts, accept) {
  return [...counts.entries()].filter(([tileId]) => accept(tileId))
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))[0];
}

function smooth(grid) {
  const changes = new Map();
  const apply = (next) => {
    for (let y = 0; y < grid.length; y += 1) {
      for (let x = 0; x < grid[y].length; x += 1) {
        if (next[y][x] === grid[y][x]) continue;
        const key = `${x},${y}`;
        const from = changes.get(key)?.from ?? grid[y][x];
        changes.set(key, { x, y, from, to: next[y][x] });
      }
    }
    return next;
  };

  // Isolated blockers (walls, water) dissolve into their surrounding floor.
  grid = apply(grid.map((row, y) => row.map((tileId, x) => {
    if (isFloor(tileId)) return tileId;
    const counts = neighbourCounts(grid, x, y);
    if ((counts.get(tileId) ?? 0) > ISOLATED_MAX_SAME) return tileId;
    return mostCommon(counts, isFloor)?.[0] ?? tileId;
  })));

  // Floor cells follow a clear floor majority (majority filter, repeated).
  for (let pass = 0; pass < FLOOR_PASSES; pass += 1) {
    grid = apply(grid.map((row, y) => row.map((tileId, x) => {
      if (!isFloor(tileId)) return tileId;
      const best = mostCommon(neighbourCounts(grid, x, y), (candidate) => isFloor(candidate) && candidate !== tileId);
      return best && best[1] >= FLOOR_MAJORITY ? best[0] : tileId;
    })));
  }
  return { grid, changes: [...changes.values()].filter((change) => change.from !== change.to) };
}

for (const world of worlds) {
  const path = `src/game/content/scenes/authored/worlds/${world}.scene.json`;
  const text = readFileSync(path, 'utf8');
  const crlf = text.includes('\r\n');
  const scene = JSON.parse(text);
  const data = (scene.subresources ?? []).find((resource) => resource.kind === 'tile-data');
  if (!data) throw new Error(`${world}: no tile-data subresource`);
  const grid = Array.from({ length: data.rows }, () => Array(data.columns).fill(undefined));
  for (const cell of data.cells) grid[cell.y][cell.x] = cell.tileId;

  const { grid: smoothed, changes } = smooth(grid);
  for (const change of changes) {
    if (isFloor(change.from) ? !isFloor(change.to) : !isFloor(change.to) && change.to !== change.from) {
      throw new Error(`${world}: refusing non-walkable change at ${change.x},${change.y}`);
    }
  }
  const summary = {};
  for (const change of changes) summary[`${change.from} -> ${change.to}`] = (summary[`${change.from} -> ${change.to}`] ?? 0) + 1;
  console.log(world, `${changes.length} cells`, summary);

  if (write && changes.length > 0) {
    for (const cell of data.cells) cell.tileId = smoothed[cell.y][cell.x];
    const output = `${JSON.stringify(scene, null, 2)}\n`;
    writeFileSync(path, crlf ? output.replace(/\n/g, '\r\n') : output);
  }
}
if (!write) console.log('dry run: pass --write to apply');
