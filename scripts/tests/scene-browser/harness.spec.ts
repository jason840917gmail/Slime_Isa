import { expect, test } from '@playwright/test';

test('real Phaser initializes, Arcade steps, DOM input is consumed, and teardown is complete', async ({ page }) => {
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true);

  await page.locator('#fixture-control').click();
  await page.evaluate(() => window.sceneFixture.step(1 / 60));
  const live = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(live.stepCount).toBe(1);
  expect(live.controlCount).toBe(1);
  expect(live.gameObjectCount).toBeGreaterThan(0);
  // Area2D sensors are indexed by the contact router, not by Arcade bodies.
  expect(live.bodyCount).toBe(3);
  expect(live.canvasCount).toBe(1);

  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
  const destroyed = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(destroyed).toMatchObject({ destroyed: true, gameObjectCount: 0, bodyCount: 0, canvasCount: 0 });
  expect(pageErrors).toEqual([]);
});
