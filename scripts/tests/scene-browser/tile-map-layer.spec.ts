import { expect, test } from '@playwright/test';

test('TileMapLayer2D renders external cells, registers collision, and tears down cleanly', async ({ page }) => {
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./?tiles=1');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true);

  const live = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(live.tileCount).toBe(3);
  expect(live.tileCollisionBodyCount).toBe(1);
  expect(live.bodyCount).toBe(5);
  expect(live.managedBlockingColliderCount).toBe(2);
  expect(pageErrors).toEqual([]);

  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
  expect(await page.evaluate(() => window.sceneFixture.snapshot())).toMatchObject({
    destroyed: true, bodyCount: 0, gameObjectCount: 0,
  });
});
