import { expect, test } from '@playwright/test';

test('production mounts the authored global audio root without phantom playback', async ({ page }) => {
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().audioCompositionMounted)).toBe(true);
  // Idle audio nodes own no Phaser sound: the global root alone authors dozens of UI, combat and
  // quest cues. A sound exists only for requested playback, here Slimeshire Meadow's autoplay music,
  // the area.enter arrival cue and the world's ambient loops (campfires, forge, meadow, roadmap 3.9).
  const { productionAudioKeys = [] } = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(productionAudioKeys.filter((key) => !/^(music-level-1-|sfx-world-)/.test(key))).toEqual([]);
  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  expect((await page.evaluate(() => window.sceneFixture.snapshot())).destroyed).toBe(true);
});
