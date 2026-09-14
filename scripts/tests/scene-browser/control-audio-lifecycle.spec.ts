import { expect, test } from '@playwright/test';

test('shared handled input suppresses gameplay and a real Phaser sound follows gesture and node cleanup', async ({ page }) => {
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true);

  const before = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(before).toMatchObject({ controlCount: 0, gameplayInputCount: 0, audioUnlocked: false, audioObjectCount: 1, audioIsPlaying: false });

  await page.locator('#fixture-control').click();
  await page.evaluate(() => window.sceneFixture.step(0));
  const handled = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(handled).toMatchObject({ controlCount: 1, gameplayInputCount: 0, audioUnlocked: true, audioObjectCount: 1, audioIsPlaying: true });

  await page.evaluate(() => window.sceneFixture.detachAudio());
  const detached = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(detached).toMatchObject({ audioObjectCount: 0, audioIsPlaying: false });

  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
  expect(pageErrors).toEqual([]);
});
