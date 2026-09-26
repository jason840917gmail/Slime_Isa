import { expect, test } from '@playwright/test';

test('player pickup area collects a scene-owned wood pile through its monitorable area', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.addInitScript(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true, undefined, { timeout: 45_000 });
  const before = await page.evaluate(() => window.sceneFixture.productionItemCount('wood'));
  await page.evaluate(() => window.sceneFixture.teleportProductionPlayer(512, 512));
  await expect.poll(() => page.evaluate(() => window.sceneFixture.productionItemCount('wood'))).toBeGreaterThan(before);
  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
});
