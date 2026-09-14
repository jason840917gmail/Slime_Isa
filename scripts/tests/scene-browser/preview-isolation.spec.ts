import { expect, test } from '@playwright/test';

test('browser preview strips scripts, denies persistence, and disposes its host', async ({ page }) => {
  await page.goto('./studio.html?studio=scenes&scene=browser.studio');
  await page.waitForFunction(() => window.sceneStudioFixture?.ready() === true);
  expect(await page.evaluate(() => window.sceneStudioFixture.previewIsolation())).toEqual({ scripts: 0, persistence: false, disposed: true });
  await page.evaluate(() => window.sceneStudioFixture.destroy());
  await expect(page.locator('[data-scene-studio]')).toHaveCount(0);
});
