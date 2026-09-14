import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');
const contacts = await loadTypescriptModule('src/game/runtime/scene/physics/ContactRouter.ts');

function participant(node, kind, shape, overrides = {}) {
  const events = [];
  const state = {
    runtimeId: node.runtimeId, node, kind, collisionLayer: 1, collisionMask: 0xffff_ffff,
    monitoring: kind === 'area', monitorable: true, contactActive: true,
    contactShapes: () => state.shape ? [state.shape] : [],
    contactBounds: () => undefined,
    contactEntered: (contact) => events.push(['enter', contact]),
    contactExited: (contact) => events.push(['exit', contact]),
    shape,
    ...overrides,
  };
  return { state, events };
}

const rect = (shapeId, x = 0) => ({ shapeId, shape: 'rectangle', x, y: 0, width: 10, height: 10 });

test('directional monitoring, masks, owner-pair suppression, and stable exits reconcile deterministically', () => {
  const observerNode = new t.Node({ runtimeId: 'contact/observer', name: 'Observer' });
  const targetNode = new t.Node({ runtimeId: 'contact/target', name: 'Target' });
  const observer = participant(observerNode, 'area', rect('contact/observer-shape'), { collisionMask: 0b0010 });
  const target = participant(targetNode, 'character-body', rect('contact/target-shape'), { collisionLayer: 0b0010, monitoring: false });
  const router = new contacts.ContactRouter();
  const unregisterObserver = router.register(observer.state);
  const unregisterTarget = router.register(target.state);

  router.reconcile();
  assert.equal(observer.events.length, 1);
  assert.equal(observer.events[0][0], 'enter');
  assert.deepEqual(observer.events[0][1].shapes, [{ observerShapeId: 'contact/observer-shape', otherShapeId: 'contact/target-shape' }]);
  router.reconcile();
  assert.equal(observer.events.length, 1, 'persistent overlap emits no duplicate enter');

  target.state.collisionLayer = 0b0100;
  assert.equal(router.isOverlapping(observer.state.runtimeId, target.state.runtimeId), false, 'mask changes invalidate damage queries immediately');
  router.reconcile();
  assert.equal(observer.events[1][0], 'exit');

  target.state.collisionLayer = 0b0010;
  router.reconcile();
  assert.equal(observer.events[2][0], 'enter');
  unregisterTarget();
  assert.equal(router.isOverlapping(observer.state.runtimeId, target.state.runtimeId), false, 'detached target invalidates the pair immediately');
  router.reconcile();
  assert.equal(observer.events[3][0], 'exit');
  assert.equal(observer.events[3][1].otherId, 'contact/target');
  assert.equal(observer.events[3][1].other, undefined);
  unregisterObserver();
});

test('area observation is directional and compound shapes emit one owner transition', () => {
  const first = participant(new t.Node({ runtimeId: 'areas/first', name: 'First' }), 'area', rect('areas/first-a'), { collisionLayer: 1, collisionMask: 2 });
  first.state.contactShapes = () => [rect('areas/first-a'), rect('areas/first-b', 2)];
  const second = participant(new t.Node({ runtimeId: 'areas/second', name: 'Second' }), 'area', rect('areas/second-a'), { collisionLayer: 2, collisionMask: 0 });
  const router = new contacts.ContactRouter();
  router.register(first.state); router.register(second.state);
  router.reconcile();
  assert.equal(first.events.length, 1);
  assert.equal(first.events[0][1].shapes.length, 2);
  assert.equal(second.events.length, 0, 'the observed area does not need to accept the observer');
});
