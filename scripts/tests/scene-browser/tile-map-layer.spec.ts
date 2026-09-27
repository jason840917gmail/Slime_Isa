import { expect, test } from '@playwright/test';

test('TileMapLayer2D renders external cells, registers collision, and tears down cleanly', async ({ page }) => {
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./?tiles=1');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true);

  const live = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(live.tileCount).toBe(3);
  expect(live.tileCollisionBodyCount).toBe(1);
  // The tile-set collision inset (left 2, right 2, top 3, bottom 1) survives body placement.
  expect(live.tileCollisionBounds).toEqual([{ x: 7 * 16 + 2, y: 16 + 3, width: 12, height: 12 }]);
  await page.evaluate(() => { for (let step = 0; step < 3; step += 1) window.sceneFixture.step(1 / 60); });
  expect((await page.evaluate(() => window.sceneFixture.snapshot())).tileCollisionBounds).toEqual([{ x: 7 * 16 + 2, y: 16 + 3, width: 12, height: 12 }]);
  // Area2D sensors are indexed by the contact router, not by Arcade bodies.
  expect(live.bodyCount).toBe(4);
  expect(live.managedBlockingColliderCount).toBe(1);
  expect(pageErrors).toEqual([]);

  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
  expect(await page.evaluate(() => window.sceneFixture.snapshot())).toMatchObject({
    destroyed: true, bodyCount: 0, gameObjectCount: 0,
  });
});
