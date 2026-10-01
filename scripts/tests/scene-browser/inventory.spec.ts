import { expect, test } from '@playwright/test';

test('authored inventory owns its modal, item actions, focus, and cleanup', async ({ page }) => {
  await page.setViewportSize({ width: 760, height: 540 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) errors.push(message.text());
  });

  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);
  await page.evaluate(() => window.sceneFixture.grantProductionItem('hp-potion', 4));
  const root = page.locator('[data-scene-ui-root]');
  const inventory = root.locator('.game-ui--inventory-ui');
  await expect(inventory).toBeHidden();

  const previousFocus = page.locator('#fixture-control');
  await previousFocus.focus();
  await page.keyboard.press('e');
  await expect(inventory).toBeVisible();
  await expect(root.locator('.game-ui--menu-tabs')).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(true);
  await expect.poll(() => page.evaluate(() => document.activeElement?.closest('.game-ui--inventory-ui') !== null)).toBe(true);
  console.log('inventory bounds', await inventory.evaluate((element) => ({ box: element.getBoundingClientRect().toJSON(), viewport: element.closest('[data-scene-ui-root]')?.getBoundingClientRect().toJSON() })));
  await expect.poll(() => inventory.evaluate((element) => {
    const box = element.getBoundingClientRect();
    const viewport = element.closest('[data-scene-ui-root]')?.getBoundingClientRect();
    return Boolean(viewport && box.left >= viewport.left && box.right <= viewport.right && box.top >= viewport.top && box.bottom <= viewport.bottom);
  })).toBe(true);

  await inventory.getByRole('option', { name: /Slime Tonic/ }).click();
  await expect(inventory).toContainText('Restores 40 HP');
  await inventory.getByRole('button', { name: 'Use', exact: true }).click();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.productionItemCount('hp-potion'))).toBe(3);
  await inventory.getByRole('button', { name: '+1', exact: true }).click();
  await expect(inventory).toContainText('Quantity: 2');
  await inventory.getByRole('button', { name: 'Remove', exact: true }).click();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.productionItemCount('hp-potion'))).toBe(1);

  await page.keyboard.press('Escape');
  await expect(inventory).toBeHidden();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(false);
  await expect(previousFocus).toBeFocused();

  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
