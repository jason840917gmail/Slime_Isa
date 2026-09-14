import { expect, test } from '@playwright/test';

test('real Arcade blocking, post-step sensors, disable/free exits, and teardown stay synchronized', async ({ page }) => {
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true);

  for (let step = 0; step < 30; step += 1) await page.evaluate(() => window.sceneFixture.step(1 / 60));
  const blocked = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(blocked.characterX).toBeCloseTo(48, 4);
  expect(blocked.sensorContactCount).toBe(1);
  expect(blocked.sensorEnterCount).toBe(1);
  expect(blocked.managedContactParticipantCount).toBe(3);
  expect(blocked.managedBlockingColliderCount).toBe(1);

  await page.evaluate(() => { window.sceneFixture.setWallEnabled(false); window.sceneFixture.step(1 / 60); });
  const disabled = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(disabled.sensorContactCount).toBe(0);
  expect(disabled.sensorExitCount).toBe(1);

  await page.evaluate(() => { window.sceneFixture.setWallEnabled(true); window.sceneFixture.step(1 / 60); });
  const reenabled = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(reenabled.sensorEnterCount).toBe(2);
  await page.evaluate(() => { window.sceneFixture.freeWall(); window.sceneFixture.step(1 / 60); });
  const freed = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(freed.sensorContactCount).toBe(0);
  expect(freed.sensorExitCount).toBe(2);
  expect(freed.managedContactParticipantCount).toBe(2);
  expect(freed.managedBlockingColliderCount).toBe(0);

  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
  expect(await page.evaluate(() => window.sceneFixture.snapshot())).toMatchObject({ destroyed: true, bodyCount: 0, gameObjectCount: 0 });
  expect(pageErrors).toEqual([]);
});
