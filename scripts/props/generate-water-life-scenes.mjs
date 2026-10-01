#!/usr/bin/env node
// Generates the pond and deep-water wildlife object scenes
// (object.water-life.*) from the sheets built by
// scripts/art/build-water-life-sheets.py. None of them collide: they are
// visual only, so they never catch the Stretch Lash hook or block teleports.
//
// Depth: things under the surface (fish, water plants, kelp, the deep fish
// shadow) use an explicit depth just above the animated water surface (see
// WaterSurfaceLayer UNDERWATER_DEPTH) and read as underwater through a blue
// tint and partial transparency.
// Things on or above the surface (lily pads, frogs, bubbles, reeds) sort in
// the ground-decals or world-entities band.
//
// Movement is authored animation: a looping path on the Visual's position,
// flipX at the turns, and the tail-wiggle frames. Every clip autoplays with
// randomizeStart so copies never move in sync.
//   node scripts/props/generate-water-life-scenes.mjs [--write]
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const OBJECTS = 'src/game/content/scenes/authored/objects';
const write = process.argv.includes('--write');
const STEPS = 8;
const DEPTH_BAND_SPACING = 2_000_000_000; // presentation/WorldDepth.ts
const UNDERWATER_DEPTH = DEPTH_BAND_SPACING + 0.6; // WaterSurfaceLayer UNDERWATER_DEPTH
const IDLE = 'object.water-life.idle';
const round = (value) => Math.round(value * 100) / 100;

const SHEETS = {
  fish: { assetId: 'sheet.water.fish.8x5', w: 128, h: 64 },
  frog: { assetId: 'sheet.water.frog.8x1', w: 128, h: 128 },
  lilypads: { assetId: 'sheet.water.lilypads.8x4', w: 128, h: 128 },
  reeds: { assetId: 'sheet.water.reeds.8x4', w: 128, h: 128 },
  plants: { assetId: 'sheet.water.plants.8x5', w: 128, h: 128 },
};

/** Looping swim path: returns [x, y] offsets for t in [0, 1). */
const PATHS = {
  // back and forth with a lazy sideways drift
  lane: (rx, ry) => (t) => [rx * Math.sin(2 * Math.PI * t), ry * Math.sin(4 * Math.PI * t + 0.6)],
  // a slow oval
  oval: (rx, ry) => (t) => [rx * Math.cos(2 * Math.PI * t), ry * Math.sin(2 * Math.PI * t)],
};

function swimClip(row, path, seconds, fps = 10) {
  const count = Math.round(seconds * fps);
  const position = [];
  const flip = [];
  const frame = [];
  let facingLeft;
  for (let i = 0; i < count; i += 1) {
    const [x, y] = path(i / count);
    const [nx] = path((i + 1) / count);
    position.push({ at: i, value: [round(x), round(y)] });
    const left = nx < x;
    if (left !== facingLeft) { flip.push({ at: i, value: left }); facingLeft = left; }
    frame.push({ at: i, value: row * STEPS + (i % STEPS) });
  }
  return {
    durationSeconds: count / fps, framesPerSecond: fps, loop: true, loopMode: 'wrap',
    tracks: [
      { binding: '../Visual', property: 'position', keys: position },
      { binding: '../Visual', property: 'flipX', keys: flip },
      { binding: '../Visual', property: 'frame', keys: frame },
    ],
  };
}

function loopClip(row, fps) {
  return {
    durationSeconds: STEPS / fps, framesPerSecond: fps, loop: true, loopMode: 'wrap',
    tracks: [{ binding: '../Visual', property: 'frame', keys: Array.from({ length: STEPS }, (_, i) => ({ at: i, value: row * STEPS + i })) }],
  };
}

// Frog: sits still, blinks now and then, croaks once per loop.
function frogClip() {
  const keys = [[0, 0], [28, 1], [30, 0], [52, 2], [54, 0], [56, 2], [60, 0], [74, 1], [75, 0]];
  return {
    durationSeconds: 8.5, framesPerSecond: 10, loop: true, loopMode: 'wrap',
    tracks: [{ binding: '../Visual', property: 'frame', keys: keys.map(([at, value]) => ({ at, value })) }],
  };
}

// Within the underwater layer: the deep shadow lies lowest, plants grow above
// it, and small fish swim over the plants.
const UNDER_DEEP = { depthMode: 'explicit', depthBand: 'ground-decals', depth: UNDERWATER_DEPTH - 0.05 };
const UNDER = { depthMode: 'explicit', depthBand: 'ground-decals', depth: UNDERWATER_DEPTH };
const UNDER_SWIM = { depthMode: 'explicit', depthBand: 'ground-decals', depth: UNDERWATER_DEPTH + 0.05 };
const ON_SURFACE = { depthMode: 'world-sorted', depthBand: 'ground-decals' };
const STANDING = { depthMode: 'world-sorted', depthBand: 'world-entities' };

const fishNames = ['koi', 'carp', 'minnow', 'perch'];
const CATALOG = [
  ...fishNames.flatMap((name, row) => [
    { name: `fish-${name}-lane`, sheet: 'fish', frame: row * STEPS, scale: 0.42, alpha: 0.72, tint: '#b9dcef', depth: UNDER_SWIM,
      clip: swimClip(row, PATHS.lane(78, 12), 9 + row), origin: [0.5, 0.5] },
    { name: `fish-${name}-oval`, sheet: 'fish', frame: row * STEPS, scale: 0.42, alpha: 0.72, tint: '#b9dcef', depth: UNDER_SWIM,
      clip: swimClip(row, PATHS.oval(56, 26), 8 + row * 0.5), origin: [0.5, 0.5] },
  ]),
  { name: 'deep-fish-shadow-lane', sheet: 'fish', frame: 4 * STEPS, scale: 1.1, alpha: 0.75, depth: UNDER_DEEP,
    clip: swimClip(4, PATHS.lane(150, 24), 20, 8), origin: [0.5, 0.5] },
  { name: 'deep-fish-shadow-oval', sheet: 'fish', frame: 4 * STEPS, scale: 1.25, alpha: 0.75, depth: UNDER_DEEP,
    clip: swimClip(4, PATHS.oval(100, 44), 22, 8), origin: [0.5, 0.5] },
  { name: 'frog-lilypad', sheet: 'frog', frame: 0, scale: 0.46, depth: ON_SURFACE, clip: frogClip() },
  ...['pink', 'white', 'single', 'small'].map((name, row) => ({
    name: `lilypad-${name}`, sheet: 'lilypads', frame: row * STEPS, scale: 0.52, depth: ON_SURFACE, clip: loopClip(row, 3),
  })),
  ...['cattails', 'reeds', 'rushes', 'sedge'].map((name, row) => ({
    name: `reeds-${name}`, sheet: 'reeds', frame: row * STEPS, scale: 0.62, depth: STANDING, clip: loopClip(row, 4),
  })),
  { name: 'waterweed-eelgrass', sheet: 'plants', frame: 0, scale: 0.55, alpha: 0.6, tint: '#a9d2e3', depth: UNDER, clip: loopClip(0, 4) },
  { name: 'waterweed-bushy', sheet: 'plants', frame: STEPS, scale: 0.55, alpha: 0.6, tint: '#a9d2e3', depth: UNDER, clip: loopClip(1, 4) },
  { name: 'kelp-olive', sheet: 'plants', frame: 2 * STEPS, scale: 0.9, alpha: 0.5, tint: '#7ea4bf', depth: UNDER, clip: loopClip(2, 3) },
  { name: 'kelp-teal', sheet: 'plants', frame: 3 * STEPS, scale: 0.9, alpha: 0.5, tint: '#7ea4bf', depth: UNDER, clip: loopClip(3, 3) },
  { name: 'bubbles', sheet: 'plants', frame: 4 * STEPS, scale: 0.7, alpha: 0.9, depth: ON_SURFACE, clip: loopClip(4, 6) },
];

function sceneFor(entry) {
  const sheet = SHEETS[entry.sheet];
  const prefix = `water-life.${entry.name}`;
  return {
    version: 1,
    sceneId: `object.water-life.${entry.name}`,
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: entry.name, type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
      {
        id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'root', order: 0,
        properties: {
          texture: { resourceId: `${prefix}.sprite` },
          frame: entry.frame,
          origin: entry.origin ?? [0.5, 1],
          scale: [entry.scale, entry.scale],
          visualOffset: [0, 0],
          ...(entry.alpha !== undefined && entry.alpha !== 1 ? { alpha: entry.alpha } : {}),
          ...(entry.tint ? { tint: entry.tint } : {}),
          ...entry.depth,
        },
      },
      {
        id: 'ambient-animation', name: 'AmbientAnimation', type: 'AnimationPlayer', parentId: 'root', order: 1,
        properties: { library: { resourceId: `${prefix}.animations` }, domain: 'render', autoplay: IDLE, randomizeStart: true },
      },
    ],
    instances: [],
    subresources: [
      { version: 1, resourceId: `${prefix}.sprite`, kind: 'sprite-sheet', assetId: sheet.assetId, frameWidth: sheet.w, frameHeight: sheet.h },
      { version: 1, resourceId: `${prefix}.animations`, kind: 'animation-library', animations: { [IDLE]: entry.clip } },
    ],
  };
}

let changed = 0;
for (const entry of CATALOG) {
  const path = join(OBJECTS, `water-life--${entry.name}.scene.json`);
  const text = `${JSON.stringify(sceneFor(entry), null, 2)}\n`;
  if (existsSync(path) && readFileSync(path, 'utf8') === text) continue;
  changed += 1;
  if (write) writeFileSync(path, text);
}
console.log(`${write ? 'Wrote' : 'Would write'} ${changed} of ${CATALOG.length} water-life scene(s)`);
