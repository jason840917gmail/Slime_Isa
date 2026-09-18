import { expect, test } from '@playwright/test';

test('authored HUD mounts, hydrates, resizes, and cleans up in production', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.addInitScript(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) pageErrors.push(message.text());
  });

  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);

  const root = page.locator('[data-scene-ui-root]');
  const hud = root.locator('.game-ui--hud');
  await expect(hud).toBeVisible();
  await expect(hud.getByText('Level 1')).toBeVisible();
  await expect(hud.getByText(/^Coins /)).toBeVisible();
  await expect(hud.getByRole('progressbar')).toHaveCount(3);
  await expect(hud.getByRole('progressbar', { name: 'HP' })).toContainText('HP');

  await page.setViewportSize({ width: 760, height: 540 });
  await expect.poll(async () => hud.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    const viewport = element.ownerDocument.defaultView;
    return Boolean(viewport && bounds.left >= 0 && bounds.right <= viewport.innerWidth && bounds.bottom <= viewport.innerHeight);
  })).toBe(true);

  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
