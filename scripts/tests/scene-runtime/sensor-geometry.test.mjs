import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const geometry = await loadTypescriptModule('src/game/runtime/scene/physics/SensorGeometry.ts');

const rectangle = (id, x, y, width, height) => ({ shapeId: id, shape: 'rectangle', x, y, width, height });
const circle = (id, centerX, centerY, radius) => ({ shapeId: id, shape: 'circle', centerX, centerY, radius });
const ellipse = (id, centerX, centerY, radiusX, radiusY) => ({ shapeId: id, shape: 'ellipse', centerX, centerY, radiusX, radiusY });
const sector = (id, originX, originY, angleRad, arcWidthRad, innerRadius, outerRadius) => ({ shapeId: id, shape: 'sector', originX, originY, angleRad, arcWidthRad, innerRadius, outerRadius });

test('all supported unordered sensor shape pairs intersect symmetrically', () => {
  const overlapping = [
    rectangle('rect', -4, -4, 8, 8),
    circle('circle', 2, 0, 4),
    ellipse('ellipse', 1, 0, 6, 3),
    sector('sector', 0, 0, 0, Math.PI / 2, 0, 8),
  ];
  for (let first = 0; first < overlapping.length; first += 1) {
    for (let second = first; second < overlapping.length; second += 1) {
      assert.equal(geometry.sensorShapesIntersect(overlapping[first], overlapping[second]), true, `${overlapping[first].shape}/${overlapping[second].shape}`);
      assert.equal(geometry.sensorShapesIntersect(overlapping[second], overlapping[first]), true, `reverse ${overlapping[first].shape}/${overlapping[second].shape}`);
    }
  }
});

test('separated shapes reject every supported pair', () => {
  const left = [rectangle('lr', -4, -4, 8, 8), circle('lc', 0, 0, 4), ellipse('le', 0, 0, 5, 3), sector('ls', 0, 0, 0, Math.PI / 2, 0, 8)];
  const right = [rectangle('rr', 100, 96, 8, 8), circle('rc', 100, 100, 4), ellipse('re', 100, 100, 5, 3), sector('rs', 100, 100, Math.PI, Math.PI / 2, 0, 8)];
  for (const first of left) for (const second of right) assert.equal(geometry.sensorShapesIntersect(first, second), false, `${first.shape}/${second.shape}`);
});

test('sector direction, inner radius, outer radius, and arc boundaries are preserved', () => {
  const wedge = sector('wedge', 0, 0, 0, Math.PI / 2, 5, 10);
  assert.equal(geometry.sensorShapesIntersect(wedge, circle('front', 8, 0, 0.5)), true);
  assert.equal(geometry.sensorShapesIntersect(wedge, circle('back', -8, 0, 0.5)), false);
  assert.equal(geometry.sensorShapesIntersect(wedge, circle('hole', 2, 0, 0.5)), false);
  assert.equal(geometry.sensorShapesIntersect(wedge, circle('outer', 11, 0, 0.5)), false);
  assert.equal(geometry.sensorShapesIntersect(wedge, circle('arc-edge', Math.cos(Math.PI / 4) * 8, Math.sin(Math.PI / 4) * 8, 0.01)), true);
});

test('sensor boundaries include exact rectangle and circle edge contact', () => {
  assert.equal(geometry.sensorShapesIntersect(rectangle('left', 0, 0, 10, 10), rectangle('right', 10, 0, 5, 5)), true);
  assert.equal(geometry.sensorShapesIntersect(circle('first', 0, 0, 5), circle('second', 10, 0, 5)), true);
  assert.equal(geometry.sensorShapesIntersect(circle('near', 0, 0, 5), circle('far', 10.001, 0, 5)), false);
});

test('compound bounds are a deterministic union and invalid geometry is rejected', () => {
  assert.deepEqual(geometry.unionSensorBounds([rectangle('a', -3, -2, 4, 5), circle('b', 5, 4, 2)]), { x: -3, y: -2, width: 10, height: 8 });
  assert.throws(() => geometry.sensorShapeBounds(circle('bad', 0, 0, 0)), /positive radius/);
  assert.throws(() => geometry.sensorShapeBounds(sector('bad-sector', 0, 0, 0, 0, 0, 10)), /0 < arc/);
});

test('a thick swept line touches the shapes it passes and misses the ones beside it', () => {
  const from = { x: 0, y: 0 };
  const to = { x: 180, y: 0 };
  assert.equal(geometry.sensorShapeTouchesSegment(rectangle('near', 170, 10, 40, 40), from, to, 16), true, 'a box just below the tip');
  assert.equal(geometry.sensorShapeTouchesSegment(rectangle('below', 60, 30, 40, 40), from, to, 16), false, 'a box beside the line');
  assert.equal(geometry.sensorShapeTouchesSegment(circle('past', 210, 0, 12), from, to, 16), false, 'a circle past the tip');
  assert.equal(geometry.sensorShapeTouchesSegment(circle('tip', 205, 0, 12), from, to, 16), true, 'the tip reaches a circle within reach');
  assert.equal(geometry.sensorShapeTouchesSegment(ellipse('mid', 90, 20, 10, 6), from, to, 16), true, 'an ellipse just off the middle');
  assert.equal(geometry.sensorShapeTouchesSegment(sector('behind', -60, 0, 0, Math.PI / 4, 0, 20), from, to, 16), false, 'a sector behind the start');
});
