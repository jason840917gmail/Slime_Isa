// Writes the spider web decoration object scenes (playtest 2026-10-01) over
// sheet.props.web-decor.4x3 (scripts/props/pack-web-decor.py). Things that
// move in real life move (docs/assets/AMBIENT_ANIMATION.md, motion-only tier):
// ground webs glint, tree webs sway, hanging victim cocoons sway and struggle,
// ground cocoons wriggle now and then. Egg sacs stay still. No collision:
// decorations never block a path.
//
// Usage: node scripts/props/generate-web-decor-scenes.mjs [--check]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const outDir = path.join(root, 'src/game/content/scenes/authored/objects');
const ASSET_ID = 'sheet.props.web-decor.4x3';

const sway = (amplitude, frames) => ({
  durationSeconds: frames / 20,
  framesPerSecond: 20,
  loop: true,
  loopMode: 'wrap',
  tracks: [{
    binding: '../Visual',
    property: 'rotation',
    keys: [
      { at: 0, value: -amplitude, transition: 'ease-in-out' },
      { at: frames / 2, value: amplitude, transition: 'ease-in-out' },
      { at: frames, value: -amplitude },
    ],
  }],
});

/** A slow sway, then a short burst of struggling, then the sway again. */
const struggleHanging = {
  durationSeconds: 4,
  framesPerSecond: 20,
  loop: true,
  loopMode: 'wrap',
  tracks: [{
    binding: '../Visual',
    property: 'rotation',
    keys: [
      { at: 0, value: -0.05, transition: 'ease-in-out' },
      { at: 20, value: 0.05, transition: 'ease-in-out' },
      { at: 40, value: -0.05 },
      { at: 43, value: 0.11 },
      { at: 46, value: -0.09 },
      { at: 49, value: 0.1 },
      { at: 52, value: -0.07 },
      { at: 55, value: 0.05, transition: 'ease-in-out' },
      { at: 68, value: -0.03, transition: 'ease-in-out' },
      { at: 80, value: -0.05 },
    ],
  }],
};

/** Lies still, then wriggles: something inside wants out. */
const wriggleGround = {
  durationSeconds: 3.5,
  framesPerSecond: 20,
  loop: true,
  loopMode: 'wrap',
  tracks: [{
    binding: '../Visual',
    property: 'rotation',
    keys: [
      { at: 0, value: 0 },
      { at: 40, value: 0 },
      { at: 43, value: 0.07 },
      { at: 46, value: -0.06 },
      { at: 49, value: 0.05 },
      { at: 52, value: -0.03 },
      { at: 56, value: 0 },
      { at: 70, value: 0 },
    ],
  }],
};

/** Dew catching the light. */
const glint = {
  durationSeconds: 4,
  framesPerSecond: 10,
  loop: true,
  loopMode: 'wrap',
  tracks: [{
    binding: '../Visual',
    property: 'alpha',
    keys: [
      { at: 0, value: 0.86, transition: 'ease-in-out' },
      { at: 20, value: 1, transition: 'ease-in-out' },
      { at: 40, value: 0.86 },
    ],
  }],
};

const PIECES = [
  { id: 'web-ground-01', frame: 0, origin: [0.5, 0.5], scale: 0.55, band: 'ground-decals', offset: [0, 0], animation: glint },
  { id: 'web-ground-02', frame: 1, origin: [0.5, 0.5], scale: 0.55, band: 'ground-decals', offset: [0, 0], animation: glint },
  { id: 'web-tree-01', frame: 2, origin: [0.5, 0], scale: 0.5, band: 'world-entities', offset: [0, -118], animation: sway(0.035, 72) },
  { id: 'web-tree-02', frame: 3, origin: [0.5, 0], scale: 0.5, band: 'world-entities', offset: [0, -118], animation: sway(0.03, 80) },
  { id: 'web-cocoon-hanging-01', frame: 4, origin: [0.5, 0], scale: 0.36, band: 'world-entities', offset: [0, -150], animation: struggleHanging },
  { id: 'web-cocoon-hanging-02', frame: 5, origin: [0.5, 0], scale: 0.36, band: 'world-entities', offset: [0, -150], animation: struggleHanging },
  { id: 'web-cocoon-hanging-03', frame: 6, origin: [0.5, 0], scale: 0.36, band: 'world-entities', offset: [0, -150], animation: struggleHanging },
  { id: 'web-cocoon-ground-01', frame: 7, origin: [0.5, 1], scale: 0.38, band: 'world-entities', offset: [0, 0], animation: wriggleGround },
  { id: 'web-cocoon-ground-02', frame: 8, origin: [0.5, 1], scale: 0.38, band: 'world-entities', offset: [0, 0], animation: wriggleGround },
  { id: 'web-egg-sacs-01', frame: 9, origin: [0.5, 1], scale: 0.42, band: 'world-entities', offset: [0, 0] },
  { id: 'web-egg-sacs-02', frame: 10, origin: [0.5, 1], scale: 0.42, band: 'world-entities', offset: [0, 0] },
];

function scene(piece) {
  const prefix = `decoration-world-ambient.${piece.id}`;
  const nodes = [
    { id: 'root', name: piece.id, type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
    {
      id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'root', order: 0,
      properties: {
        texture: { resourceId: `${prefix}.sprite` },
        frame: piece.frame,
        origin: piece.origin,
        scale: [piece.scale, piece.scale],
        visualOffset: piece.offset,
        depthMode: 'world-sorted',
        depthBand: piece.band,
      },
    },
  ];
  const subresources = [
    { version: 1, resourceId: `${prefix}.sprite`, kind: 'sprite-sheet', assetId: ASSET_ID, frameWidth: 256, frameHeight: 256 },
  ];
  if (piece.animation) {
    nodes.push({
      id: 'ambient-animation', name: 'AmbientAnimation', type: 'AnimationPlayer', parentId: 'root', order: 1,
      properties: { library: { resourceId: `${prefix}.ambient-animations` }, domain: 'render', autoplay: 'object.ambient.idle', randomizeStart: true },
    });
    subresources.push({ version: 1, resourceId: `${prefix}.ambient-animations`, kind: 'animation-library', animations: { 'object.ambient.idle': piece.animation } });
  }
  return { version: 1, sceneId: `object.decoration-world-ambient.${piece.id}`, rootNodeId: 'root', nodes, instances: [], subresources };
}

const check = process.argv.includes('--check');
let stale = 0;
for (const piece of PIECES) {
  const file = path.join(outDir, `decoration-world-ambient--${piece.id}.scene.json`);
  const text = `${JSON.stringify(scene(piece), null, 2)}\n`;
  const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n') : undefined;
  if (current === text) continue;
  stale += 1;
  if (check) console.error(`stale: ${path.relative(root, file)}`);
  else fs.writeFileSync(file, text);
}
console.log(check ? `${stale} stale web decoration scene(s)` : `wrote ${stale} web decoration scene(s)`);
if (check && stale) process.exit(1);
