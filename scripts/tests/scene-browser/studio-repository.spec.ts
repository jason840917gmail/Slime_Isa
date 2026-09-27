import { expect, test } from '@playwright/test';

test('Scene Studio repository default constructor calls the browser fetch with a valid receiver', async ({ page }) => {
  await page.route('**/__scene-studio/content?action=list', (route) => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ items: [{ kind: 'scene', id: 'world.default-fetch', relativePath: 'default.scene.json' }] }),
  }));
  await page.goto('./studio.html?studio=scenes&scene=browser.studio');
  await expect.poll(() => page.evaluate(() => Boolean(window.sceneStudioFixture?.ready()))).toBe(true);
  expect(await page.evaluate(() => window.sceneStudioFixture.defaultRepositoryList())).toEqual(['world.default-fetch']);
});
