import { expect, test } from '@playwright/test';

test('authored area title presents biome color, replaces announcements, and cleans up', async ({ page }) => {
  await page.setViewportSize({ width: 760, height: 540 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) pageErrors.push(message.text());
  });

  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);
  const root = page.locator('[data-scene-ui-root]');
  const card = root.locator('.game-ui--area-title-card');
  await page.evaluate(() => window.sceneFixture.showProductionAreaTitle('Meadow Crossing', '#a3f0c0'));
  await expect(card).toBeVisible();
  await expect(card).toContainText('Meadow Crossing');
  await expect(card.locator('.scene-control--label')).toHaveCSS('color', 'rgb(163, 240, 192)');

  await page.evaluate(() => window.sceneFixture.showProductionAreaTitle('Crystal Caverns', '#9ad8ff'));
  await expect(card).toContainText('Crystal Caverns');
  await expect(card.locator('.scene-control--label')).toHaveCSS('color', 'rgb(154, 216, 255)');
  await expect.poll(() => card.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    return bounds.left >= 0 && bounds.right <= window.innerWidth;
  })).toBe(true);
  await expect(card).toBeHidden({ timeout: 5_000 });

  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
