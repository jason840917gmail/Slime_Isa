import { expect, test } from '@playwright/test';

test('managed host owns exactly one real Arcade step per fixed tick', async ({ page }) => {
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true);
  const before = await page.evaluate(() => window.sceneFixture.snapshot());
  await page.evaluate(() => window.sceneFixture.step(1 / 60));
  const after = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(after.stepCount - before.stepCount).toBe(1);
  expect(after.bodyX).toBeGreaterThan(before.bodyX ?? 0);
  expect(pageErrors).toEqual([]);
});
