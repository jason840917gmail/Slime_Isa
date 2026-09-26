import { expect, test } from '@playwright/test';

test('dynamic world drops mount collectible scenes and honor instance quantity', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./?mode=baseline&map=test-rectangle');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true, undefined, { timeout: 45_000 });
  const before = await page.evaluate(() => window.sceneFixture.productionItemCount('wood'));
  await page.evaluate(() => window.sceneFixture.spawnProductionDrop('browser-world-drop-1', 3, 384, 256));
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().managedCollectibleCount)).toBe(1);
  await page.waitForTimeout(500);
  await page.evaluate(() => window.sceneFixture.teleportProductionPlayer(384, 256));
  await expect.poll(() => page.evaluate(() => window.sceneFixture.productionItemCount('wood'))).toBe(before + 3);
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().managedCollectibleCount)).toBe(0);
  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
});
