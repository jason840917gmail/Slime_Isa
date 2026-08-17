import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

async function load(entry) {
  const result = await build({
    absWorkingDir: root,
    entryPoints: [entry],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

const rectangleBody = (overrides = {}) => ({
  active: true,
  body: {
    enable: true,
    isCircle: false,
    x: 0,
    y: 0,
    width: 40,
    height: 20,
    ...overrides,
  },
});

const circleBody = (centerX, centerY, radius, overrides = {}) => ({
  active: true,
  body: {
    enable: true,
    isCircle: true,
    x: centerX - radius,
    y: centerY - radius,
    width: radius * 2,
    height: radius * 2,
    halfWidth: radius,
    center: { x: centerX, y: centerY },
    ...overrides,
  },
});

test('only active targets with enabled, valid collision bodies resolve', async () => {
  const geometry = await load('src/game/combat/CombatBodyGeometry.ts');

  assert.deepEqual(geometry.resolveCombatBodyGeometry(rectangleBody()), {
    shape: 'rectangle',
    x: 0,
    y: 0,
    width: 40,
    height: 20,
  });
  assert.equal(geometry.resolveCombatBodyGeometry({ ...rectangleBody(), active: false }), null);
  assert.equal(geometry.resolveCombatBodyGeometry(rectangleBody({ enable: false })), null);
  assert.equal(geometry.resolveCombatBodyGeometry({ active: true }), null);
  assert.equal(geometry.resolveCombatBodyGeometry(rectangleBody({ width: 0 })), null);
  assert.equal(geometry.resolveCombatBodyGeometry(rectangleBody({ x: Number.NaN })), null);
});

test('rectangle attacks use the full rectangular body, never tiny visual bounds', async () => {
  const geometry = await load('src/game/combat/CombatBodyGeometry.ts');
  const target = geometry.resolveCombatBodyGeometry(rectangleBody({ x: 100, y: 100, width: 60, height: 40 }));

  assert.equal(geometry.attackIntersectsCombatBody({ shape: 'rect', x: 156, y: 120, width: 12, height: 8 }, target), true);
  assert.equal(geometry.attackIntersectsCombatBody({ shape: 'rect', x: 167, y: 120, width: 12, height: 8 }, target), false);
});

test('rectangle attacks reject the corners outside a native circle body', async () => {
  const geometry = await load('src/game/combat/CombatBodyGeometry.ts');
  const target = geometry.resolveCombatBodyGeometry(circleBody(0, 0, 10));

  assert.equal(geometry.attackIntersectsCombatBody({ shape: 'rect', x: 9, y: 9, width: 2, height: 2 }, target), false);
  assert.equal(geometry.attackIntersectsCombatBody({ shape: 'rect', x: 9, y: 0, width: 2, height: 2 }, target), true);
});

test('ellipse attacks preserve long thin rectangles and native circles exactly', async () => {
  const geometry = await load('src/game/combat/CombatBodyGeometry.ts');
  const thinRectangle = geometry.resolveCombatBodyGeometry(rectangleBody({ x: -40, y: 20, width: 100, height: 2 }));
  const nearCircle = geometry.resolveCombatBodyGeometry(circleBody(0, 5.5, 1));
  const farCircle = geometry.resolveCombatBodyGeometry(circleBody(0, 7, 1));
  const circleAttack = { shape: 'ellipse', x: 0, y: 0, width: 20, height: 20, radiusX: 10, radiusY: 10 };
  const flatAttack = { shape: 'ellipse', x: 0, y: 0, width: 40, height: 10, radiusX: 20, radiusY: 5 };

  assert.equal(geometry.attackIntersectsCombatBody(circleAttack, thinRectangle), false);
  assert.equal(geometry.attackIntersectsCombatBody(flatAttack, nearCircle), true);
  assert.equal(geometry.attackIntersectsCombatBody(flatAttack, farCircle), false);
});

test('sector attacks preserve long thin rectangles and circle bodies', async () => {
  const geometry = await load('src/game/combat/CombatBodyGeometry.ts');
  const thinRectangle = geometry.resolveCombatBodyGeometry(rectangleBody({ x: -40, y: 20, width: 100, height: 2 }));
  const nearCircle = geometry.resolveCombatBodyGeometry(circleBody(10, 1, 1));
  const farCircle = geometry.resolveCombatBodyGeometry(circleBody(10, 10, 1));
  const sector = {
    shape: 'sector',
    x: 0,
    y: 0,
    width: 60,
    height: 60,
    originX: 0,
    originY: 0,
    angle: 0,
    arcWidth: 0.4,
    innerRadius: 0,
    outerRadius: 30,
  };

  assert.equal(geometry.attackIntersectsCombatBody(sector, thinRectangle), false);
  assert.equal(geometry.attackIntersectsCombatBody(sector, nearCircle), true);
  assert.equal(geometry.attackIntersectsCombatBody(sector, farCircle), false);
});

test('full annular sectors respect their inner hole', async () => {
  const geometry = await load('src/game/combat/CombatBodyGeometry.ts');
  const annulus = {
    shape: 'sector',
    x: 0,
    y: 0,
    width: 40,
    height: 40,
    originX: 0,
    originY: 0,
    angle: 0,
    arcWidth: Math.PI * 2,
    innerRadius: 10,
    outerRadius: 20,
  };

  assert.equal(geometry.attackIntersectsCombatBody(annulus, geometry.resolveCombatBodyGeometry(circleBody(0, 0, 5))), false);
  assert.equal(geometry.attackIntersectsCombatBody(annulus, geometry.resolveCombatBodyGeometry(circleBody(8, 0, 3))), true);
});

test('resolved body snapshots remain stable after a body is disabled', async () => {
  const geometry = await load('src/game/combat/CombatBodyGeometry.ts');
  const target = rectangleBody({ x: 10, y: 20, width: 40, height: 30 });
  const snapshot = geometry.resolveCombatBodyGeometry(target);

  target.body.enable = false;

  assert.deepEqual(snapshot, { shape: 'rectangle', x: 10, y: 20, width: 40, height: 30 });
  assert.equal(geometry.resolveCombatBodyGeometry(target), null);
});
