import assert from 'node:assert/strict';
import test from 'node:test';

import {
  CAMERA_ZOOM_LEVELS,
  DEFAULT_CAMERA_ZOOM,
  cameraRenderingMode,
  closestCameraZoomIndex,
  formatCameraZoom,
  isIntegerCameraZoom,
  nextCameraZoom,
} from '../../../src/game/presentation/CameraZoom.ts';
import {
  cameraCenterFromScroll,
  exponentialDampingFactor,
  interpolatePhysicsPosition,
  resolveDeadzoneCenter,
  responsiveDeadzoneSize,
} from '../../../src/game/presentation/CameraMotion.ts';
test('development tools format the current zoom as a compact multiplier', () => {
  assert.equal(formatCameraZoom(1), '1×');
  assert.equal(formatCameraZoom(0.75), '0.75×');
  assert.equal(formatCameraZoom(1.125), '1.125×');
});

test('camera center follows Phaser scroll semantics at every zoom', () => {
  // Zoom changes displayWidth, but Phaser centerOn and scroll keep using the
  // unzoomed viewport midpoint. This must not be divided by zoom again.
  assert.deepEqual(cameraCenterFromScroll(360, 240, 1280, 720), { x: 1000, y: 600 });
});

test('normal play defaults to integer 1x and fractional levels are overview mode', () => {
  assert.equal(DEFAULT_CAMERA_ZOOM, 1);
  assert.equal(cameraRenderingMode(1), 'gameplay');
  assert.equal(cameraRenderingMode(0.75), 'overview');
  assert.equal(isIntegerCameraZoom(1), true);
  assert.equal(isIntegerCameraZoom(1.25), false);
  assert.deepEqual(CAMERA_ZOOM_LEVELS, [0.5, 0.625, 0.75, 0.875, 1, 1.125, 1.25]);
});

test('zoom stepping is deterministic and clamps at both ends', () => {
  assert.equal(nextCameraZoom(1, -1), 1.125);
  assert.equal(nextCameraZoom(1, 1), 0.875);
  assert.equal(nextCameraZoom(1.25, -1), 1.25);
  assert.equal(nextCameraZoom(0.5, 1), 0.5);
  assert.equal(nextCameraZoom(0.75, 0), 0.75);
  assert.equal(closestCameraZoomIndex(0.76), 2);
});

test('responsive deadzone scales within safe bounds', () => {
  assert.deepEqual(responsiveDeadzoneSize(320, 240), { width: 128, height: 96 });
  assert.deepEqual(responsiveDeadzoneSize(1920, 1080), { width: 224, height: 151.20000000000002 });
  assert.deepEqual(responsiveDeadzoneSize(4000, 3000), { width: 224, height: 160 });
});

test('deadzone only asks the camera to move after the target crosses an edge', () => {
  const center = { x: 100, y: 100 };
  assert.deepEqual(resolveDeadzoneCenter(center, { x: 120, y: 90 }, 30, 20), center);
  assert.deepEqual(resolveDeadzoneCenter(center, { x: 150, y: 70 }, 30, 20), { x: 120, y: 90 });
});

test('camera damping is frame-rate independent over equal elapsed time', () => {
  const advance = (frames, deltaMs) => {
    let value = 0;
    for (let i = 0; i < frames; i += 1) {
      value += (100 - value) * exponentialDampingFactor(deltaMs);
    }
    return value;
  };
  assert.ok(Math.abs(advance(60, 1000 / 60) - advance(120, 1000 / 120)) < 1e-9);
});

test('physics interpolation bridges the previous and current fixed-step position', () => {
  assert.deepEqual(interpolatePhysicsPosition({ x: 20, y: 10 }, { x: 4, y: -2 }, 0), { x: 16, y: 12 });
  assert.deepEqual(interpolatePhysicsPosition({ x: 20, y: 10 }, { x: 4, y: -2 }, 0.5), { x: 18, y: 11 });
  assert.deepEqual(interpolatePhysicsPosition({ x: 20, y: 10 }, { x: 4, y: -2 }, 1), { x: 20, y: 10 });
});
