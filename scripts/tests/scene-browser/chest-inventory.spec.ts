import { expect, test } from '@playwright/test';

test('authored chest panel inspects and transfers a stack through ChestScript', async ({ page }) => {
  await page.setViewportSize({ width: 760, height: 540 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) errors.push(message.text());
  });

  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);
  const root = page.locator('[data-scene-ui-root]');
  const chest = root.locator('.game-ui--chest-inventory-panel');
  await expect(chest).toBeHidden();
  const priorFocus = page.locator('#fixture-control');
  await priorFocus.focus();
  const opened = await page.evaluate(() => window.sceneFixture.openProductionChestForUi());
  const itemCountBefore = await page.evaluate((id) => window.sceneFixture.productionItemCount(id), opened.itemId);
  await expect(chest).toBeVisible();
  await expect(chest.getByRole('listbox', { name: 'Chest contents' })).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(true);
  await expect.poll(() => chest.evaluate((element) => {
    const box = element.getBoundingClientRect();
    const viewport = element.closest('[data-scene-ui-root]')?.getBoundingClientRect();
    return Boolean(viewport && box.left >= viewport.left && box.right <= viewport.right && box.top >= viewport.top && box.bottom <= viewport.bottom);
  })).toBe(true);

  const slot = chest.getByRole('option').first();
  await slot.click();
  await expect(chest.getByRole('button', { name: 'Take Stack' })).toBeEnabled();
  await slot.click({ button: 'right' });
  await expect.poll(() => page.evaluate((id) => window.sceneFixture.productionItemCount(id), opened.itemId)).toBeGreaterThan(itemCountBefore);
  await expect.poll(() => page.evaluate(({ instanceId, itemId }) => window.sceneFixture.productionChestRemaining(instanceId, itemId), opened)).toBeLessThan(opened.count);
  await expect(chest).toContainText('Moved');

  await page.keyboard.press('Escape');
  await expect(chest).toBeHidden();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(false);
  await expect(priorFocus).toBeFocused();
  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
