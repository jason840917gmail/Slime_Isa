import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { loadTypescriptModule, REPOSITORY_ROOT } from '../helpers/load-typescript.mjs';

const collision = await loadTypescriptModule('src/game/shared/collisionShapes.ts');
const sensor = await loadTypescriptModule('src/game/runtime/scene/physics/SensorGeometry.ts');
const combat = await loadTypescriptModule('src/game/combat/CombatBodyGeometry.ts');

test('legacy ellipse movement converts to its exact effective rectangle', () => {
  const source = { shape: 'ellipse', width: 40, height: 16, radiusX: 23, radiusY: 7, centerOffsetX: 5, centerOffsetY: -2 };
  assert.deepEqual(collision.resolveEffectiveArcadeBodyBoundsRelativeToAnchor(source), {
    minX: -18, minY: -9, maxX: 28, maxY: 5, width: 46, height: 14,
  });
});

test('authored sword and goo-gauntlet sectors retain legacy contact decisions', async () => {
  const loadWeapon = async (id) => JSON.parse(await readFile(`${REPOSITORY_ROOT}/src/game/content/weapons/${id}/weapon.json`, 'utf8'));
  for (const id of ['basic-sword', 'goo-gauntlet']) {
    const weapon = await loadWeapon(id);
    const hitbox = Object.values(weapon.directionalAttacks.right.hitboxes).find((entry) => entry.shape === 'sector');
    const angleRad = 0;
    const originX = hitbox.offsetX;
    const originY = hitbox.offsetY;
    const sceneShape = { shapeId: `${id}/shape`, shape: 'sector', originX, originY, angleRad, arcWidthRad: hitbox.arcWidthRad, innerRadius: hitbox.innerRadius ?? 0, outerRadius: hitbox.outerRadius };
    for (const targetX of [-20, 0, 15, 40, 80]) {
      const target = { shape: 'circle', x: targetX - 4, y: -4, width: 8, height: 8, centerX: targetX, centerY: 0, radius: 4 };
      const legacy = combat.attackIntersectsCombatBody({ shape: 'sector', x: originX, y: originY, width: hitbox.width, height: hitbox.height, originX, originY, angle: angleRad, arcWidth: hitbox.arcWidthRad, innerRadius: hitbox.innerRadius ?? 0, outerRadius: hitbox.outerRadius }, target);
      const converted = sensor.sensorShapesIntersect(sceneShape, { shapeId: 'target', shape: 'circle', centerX: targetX, centerY: 0, radius: 4 });
      assert.equal(converted, legacy, `${id} target at ${targetX}`);
    }
  }
});
