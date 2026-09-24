import { expect, test } from '@playwright/test';

test('production mounts the authored global audio root without phantom playback', async ({ page }) => {
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().audioCompositionMounted)).toBe(true);
  expect((await page.evaluate(() => window.sceneFixture.snapshot())).productionAudioObjectCount).toBe(0);
  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  expect((await page.evaluate(() => window.sceneFixture.snapshot())).destroyed).toBe(true);
});
