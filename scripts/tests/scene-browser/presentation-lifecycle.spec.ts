import { expect, test } from '@playwright/test';

test('managed sprite synchronizes, detaches, re-enters, and fully tears down', async ({ page }) => {
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true);
  await page.evaluate(() => { window.sceneFixture.moveSprite(72, 48); window.sceneFixture.step(0); });
  const moved = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(moved).toMatchObject({ spriteX: 72, spriteY: 48, spriteActive: true, managedPresentationCount: 2, cameraCount: 2 });
  await page.evaluate(() => window.sceneFixture.detachSprite());
  const detached = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(detached).toMatchObject({ spriteActive: false, managedPresentationCount: 1 });
  await page.evaluate(() => { window.sceneFixture.attachSprite(); window.sceneFixture.step(0); });
  const reentered = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(reentered).toMatchObject({ spriteX: 72, spriteY: 48, spriteActive: true, managedPresentationCount: 2 });
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
  expect(await page.evaluate(() => window.sceneFixture.snapshot())).toMatchObject({ destroyed: true, managedPresentationCount: 0, cameraCount: 0 });
  expect(pageErrors).toEqual([]);
});
