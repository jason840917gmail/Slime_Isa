import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');
const contacts = await loadTypescriptModule('src/game/runtime/scene/physics/ContactRouter.ts');
const geometry = await loadTypescriptModule('src/game/runtime/scene/physics/SensorGeometry.ts');

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

test('grid broadphase reports exactly the contacts and order of an exhaustive scan', () => {
  let seed = 0x5eed;
  const random = () => { seed = (seed * 1_103_515_245 + 12_345) % 2 ** 31; return seed / 2 ** 31; };
  // Positions snap to a coarse lattice so many shapes touch exactly on grid-cell edges (128px).
  const coordinate = () => Math.round(random() * 40) * 32 - 160;
  const shapeAt = (shapeId) => {
    const kind = Math.floor(random() * 4);
    const x = coordinate(); const y = coordinate();
    if (kind === 0) return { shapeId, shape: 'rectangle', x, y, width: 32 + Math.floor(random() * 4) * 32, height: 32 + Math.floor(random() * 3) * 32 };
    if (kind === 1) return { shapeId, shape: 'circle', centerX: x, centerY: y, radius: 16 + Math.floor(random() * 4) * 16 };
    if (kind === 2) return { shapeId, shape: 'ellipse', centerX: x, centerY: y, radiusX: 24, radiusY: 12 + Math.floor(random() * 3) * 8 };
    return { shapeId, shape: 'sector', originX: x, originY: y, angleRad: random() * Math.PI * 2, arcWidthRad: Math.PI / 2, innerRadius: 0, outerRadius: 64 };
  };
  const log = [];
  const entries = [];
  const router = new contacts.ContactRouter();
  for (let index = 0; index < 160; index += 1) {
    const kind = index % 3 === 0 ? 'area' : 'character-body';
    const node = new t.Node({ runtimeId: `grid/p${index}`, name: `P${index}` });
    const shapes = kind === 'area' && index % 2 === 0
      ? [shapeAt(`grid/p${index}-a`), shapeAt(`grid/p${index}-b`)]
      : [shapeAt(`grid/p${index}-a`)];
    const state = {
      runtimeId: node.runtimeId, node, kind,
      collisionLayer: 1 << (index % 3), collisionMask: index % 5 === 0 ? 0b011 : 0b111,
      monitoring: kind === 'area', monitorable: index % 7 !== 0, contactActive: index % 11 !== 0,
      shapes,
      contactShapes: () => state.shapes,
      contactBounds: () => undefined,
      contactEntered: (contact) => log.push(`enter ${contact.observerId}>${contact.otherId}`),
      contactExited: (contact) => log.push(`exit ${contact.observerId}>${contact.otherId}`),
    };
    entries.push(state);
    router.register(state);
  }
  // Oversized sensors bypass the grid index and must still be found and find others.
  entries[3].shapes = [{ shapeId: 'grid/p3-huge', shape: 'rectangle', x: -10_000, y: -10_000, width: 20_000, height: 20_000 }];
  entries[4].shapes = [{ shapeId: 'grid/p4-huge', shape: 'rectangle', x: -10_000, y: -10_000, width: 20_000, height: 20_000 }];

  const exhaustive = () => {
    const expected = [];
    for (const observer of entries) {
      if (observer.kind !== 'area' || !observer.contactActive || !observer.monitoring) continue;
      const bounds = geometry.unionSensorBounds(observer.shapes);
      for (const other of entries) {
        if (other === observer || !other.contactActive || !other.monitorable || (observer.collisionMask & other.collisionLayer) === 0) continue;
        if (!geometry.sensorBoundsIntersect(bounds, geometry.unionSensorBounds(other.shapes))) continue;
        if (observer.shapes.some((mine) => other.shapes.some((theirs) => geometry.sensorShapesIntersect(mine, theirs)))) {
          expected.push(`${observer.runtimeId}>${other.runtimeId}`);
        }
      }
    }
    return expected;
  };

  router.reconcile();
  const expected = exhaustive();
  assert.ok(expected.length > 40, `workload should produce many contacts, got ${expected.length}`);
  assert.deepEqual(log, expected.map((pair) => `enter ${pair}`), 'same pairs in the same emission order');

  for (const entry of entries) if (Number(entry.runtimeId.slice(6)) % 4 === 1) entry.shapes = [shapeAt(`${entry.runtimeId}-moved`)];
  log.length = 0;
  router.reconcile();
  const next = exhaustive();
  const previous = new Set(expected);
  const current = new Set(next);
  assert.deepEqual(
    log,
    [
      ...expected.filter((pair) => !current.has(pair)).map((pair) => `exit ${pair}`),
      ...next.filter((pair) => !previous.has(pair)).map((pair) => `enter ${pair}`),
    ],
    'moved shapes produce the exhaustive exits then enters',
  );
});
