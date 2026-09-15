import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');

class Body extends t.Node2D {
  velocity = { x: 0, y: 0 };
  queued;
  queue_teleport(position) { this.queued = { ...position }; }
}

class Area extends t.Node {
  contactBounds() { return { x: 4, y: 5, width: 30, height: 26 }; }
}

class Animation extends t.Node {
  currentAnimation;
  hasAnimation(id) { return id === 'idle'; }
  play(id) { this.currentAnimation = id; }
}

test('PlayerNodePorts normalizes movement and exposes only node-backed player operations', () => {
  const body = new Body({ runtimeId: 'ports/body', name: 'Body', position: { x: 12, y: 18 } });
  const area = new Area({ runtimeId: 'ports/area', name: 'Area' });
  const animation = new Animation({ runtimeId: 'ports/animation', name: 'Animation' });
  const ports = new t.PlayerNodePorts(body, area, animation, () => true);

  assert.deepEqual(ports.getPosition(), { x: 12, y: 18 });
  assert.deepEqual(ports.getBodyBounds(), { x: 4, y: 5, width: 30, height: 26 });
  assert.equal(ports.isDodging(), true);
  ports.setVelocity({ x: 3, y: 4 }, 50);
  assert.deepEqual(body.velocity, { x: 30, y: 40 });
  ports.applyKnockback({ x: -1, y: 0 }, 80, 160);
  assert.deepEqual(body.velocity, { x: -80, y: 0 });
  ports.teleport({ x: 90, y: 100 });
  assert.deepEqual(body.queued, { x: 90, y: 100 });
  assert.equal(ports.play('missing'), false);
  assert.equal(ports.play('idle'), true);
  assert.equal(animation.currentAnimation, 'idle');
  ports.stop();
  assert.deepEqual(body.velocity, { x: 0, y: 0 });
  assert.throws(() => ports.setVelocity({ x: 1, y: 0 }, -1), /non-negative/);
  assert.throws(() => ports.teleport({ x: Number.NaN, y: 0 }), /finite/);
});
