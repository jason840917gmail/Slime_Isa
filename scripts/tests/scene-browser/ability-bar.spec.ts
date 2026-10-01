import { expect, test } from '@playwright/test';

test('authored ability bar follows unlock, cooldown, energy, input, and cleanup state', async ({ page }) => {
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
  const bar = root.locator('.game-ui--ability-bar');
  const buttons = bar.getByRole('button');
  const jump = bar.getByRole('button', { name: 'Jump ability' });
  const slam = bar.getByRole('button', { name: 'Slam ability' });
  const teleport = bar.getByRole('button', { name: 'Teleport ability' });
  const dodge = bar.getByRole('button', { name: 'Dodge ability' });
  await expect(bar).toBeVisible();
  await expect(buttons).toHaveCount(5);
  // Dodge is learned in the story too (Stone Tools), not known from the start.
  await expect(dodge).toBeDisabled();
  await expect(dodge).toContainText('Quest');
  await expect(jump).toBeDisabled();
  // Locked abilities say how they are earned; the story teaches them, not levels.
  await expect(jump).toContainText('Quest');
  await expect(slam).toContainText('Boss');
  await expect(teleport).toContainText('Later');

  await page.evaluate(() => window.sceneFixture.learnProductionAbilities(['jump']));
  await expect(jump).toBeEnabled();
  await expect(jump).toContainText('Space');
  await expect(slam).toBeDisabled();
  await page.evaluate(() => window.sceneFixture.learnProductionAbilities(['dodge']));
  await expect(dodge).toBeEnabled();
  await expect(dodge).toContainText('1');

  await jump.click();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().jumpCooldownMs ?? 0)).toBeGreaterThan(0);
  await expect(jump).toBeDisabled();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().jumpCooldownMs ?? -1), { timeout: 10_000 }).toBe(0);
  await expect(jump).toBeEnabled();

  await jump.focus();
  await page.keyboard.press('Enter');
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().jumpCooldownMs ?? 0)).toBeGreaterThan(0);

  await page.evaluate(() => window.sceneFixture.learnProductionAbilities(['teleport']));
  await page.evaluate(() => window.sceneFixture.drainProductionEnergy());
  await expect(teleport).toBeDisabled();
  await expect(teleport).toContainText('Need 35E');
  await expect(slam).toBeDisabled();

  await page.setViewportSize({ width: 760, height: 540 });
  await expect.poll(() => bar.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    return bounds.left >= 0 && bounds.right <= window.innerWidth && bounds.top >= 0 && bounds.bottom <= window.innerHeight;
  })).toBe(true);

  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
