import { expect, test } from '@playwright/test';

test('authored floating text handles concurrent messages, animation, reuse, and cleanup', async ({ page }) => {
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
  const messages = root.locator('.game-ui--floating-text');
  await page.evaluate(() => {
    window.sceneFixture.spawnProductionFloatingText('FIRST', 'cyan', false, 1600);
    window.sceneFixture.spawnProductionFloatingText('SECOND', 'yellow', true, 1600);
  });
  await expect(messages).toHaveCount(2);
  const first = messages.filter({ hasText: 'FIRST' });
  const second = messages.filter({ hasText: 'SECOND' });
  await expect(first).toBeVisible();
  await expect(second).toBeVisible();
  await expect(first.locator('.scene-control--label')).toHaveCSS('color', 'rgb(114, 216, 255)');
  await expect(second.locator('.scene-control--label')).toHaveCSS('font-size', '22px');
  const initialTop = await first.evaluate((element) => element.getBoundingClientRect().top);
  await expect.poll(() => first.evaluate((element) => element.getBoundingClientRect().top)).toBeLessThan(initialTop - 4);
  await expect(first).toBeHidden({ timeout: 5_000 });
  await expect(second).toBeHidden();

  await page.evaluate(() => window.sceneFixture.spawnProductionFloatingText('REUSED', 'green', false, 1300));
  await expect(messages).toHaveCount(2);
  await expect(messages.filter({ hasText: 'REUSED' })).toBeVisible();
  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
