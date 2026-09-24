import { expect, test } from '@playwright/test';

test('authored player and boss health bars track damage, encounters, and cleanup', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) pageErrors.push(message.text());
  });

  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);

  const root = page.locator('[data-scene-ui-root]');
  const playerBar = root.locator('.game-ui--health-bar');
  const bossBar = root.locator('.game-ui--boss-health-bar');
  await expect(playerBar).toBeHidden();
  await expect(bossBar).toBeHidden();

  const hpBefore = await page.evaluate(() => window.sceneFixture.snapshot().playerHp ?? 0);
  await page.evaluate(() => window.sceneFixture.damageProductionPlayer(10));
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().playerHp ?? 0)).toBeLessThan(hpBefore);
  await expect(playerBar).toBeVisible();
  await expect(playerBar.getByRole('progressbar')).toHaveAttribute('aria-valuenow', String(hpBefore - 10));
  await expect.poll(() => playerBar.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    const viewport = element.closest('[data-scene-ui-root]')?.getBoundingClientRect();
    return Boolean(viewport && bounds.left >= viewport.left && bounds.right <= viewport.right
      && bounds.top >= viewport.top && bounds.bottom <= viewport.bottom);
  })).toBe(true);
  await expect(playerBar).toBeHidden({ timeout: 5_000 });

  await page.evaluate(() => window.sceneFixture.teleportProductionPlayer(2_528, 1_472));
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().managedBossCount ?? 0), { timeout: 10_000 }).toBe(1);
  await expect(bossBar).toBeVisible();
  await expect(bossBar).toContainText('Fatty One Eye');
  await expect(bossBar.getByRole('progressbar')).toHaveAttribute('aria-valuenow', /\d+/);
  const separated = await page.evaluate(() => {
    const boss = document.querySelector('.game-ui--boss-health-bar')?.getBoundingClientRect();
    const weapons = document.querySelector('.game-ui--weapon-hotbar')?.getBoundingClientRect();
    return Boolean(boss && weapons && boss.bottom < weapons.top);
  });
  expect(separated).toBe(true);
  await page.setViewportSize({ width: 375, height: 540 });
  await expect.poll(() => bossBar.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    const viewport = element.closest('[data-scene-ui-root]')?.getBoundingClientRect();
    return Boolean(viewport && bounds.left >= viewport.left && bounds.right <= viewport.right);
  })).toBe(true);

  await page.evaluate(() => window.sceneFixture.resetProductionBossFight());
  await expect(bossBar).toBeHidden();
  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
