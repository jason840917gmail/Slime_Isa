import { expect, test } from '@playwright/test';

test('authored crafting quotes materials and commits a recipe transaction', async ({ page }) => {
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
  const workbench = root.locator('.game-ui--crafting-ui');
  const priorFocus = page.locator('#fixture-control');
  await priorFocus.focus();
  // One menu (roadmap 4.10): E opens the bag, and its Crafting tab crafts the portable recipes.
  await page.keyboard.press('e');
  await root.locator('.game-ui--menu-tabs').getByRole('button', { name: 'Crafting tab' }).click();
  await expect(workbench).toBeVisible();
  await expect(root.locator('.game-ui--inventory-ui')).toBeHidden();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(true);
  await expect.poll(() => workbench.evaluate((element) => {
    const box = element.getBoundingClientRect();
    const viewport = element.closest('[data-scene-ui-root]')?.getBoundingClientRect();
    return Boolean(viewport && box.left >= viewport.left && box.right <= viewport.right && box.top >= viewport.top && box.bottom <= viewport.bottom);
  })).toBe(true);
  await expect(workbench.getByRole('listbox', { name: 'Crafting recipes' })).toBeVisible();
  // The portable recipes; the first is the workbench itself.
  await expect(workbench).toContainText('Crafting');
  await expect(workbench).not.toContainText('Wooden Spear');
  // Short of materials, Craft stays pressable and answers with exactly what is missing (playtest 2026-09-29).
  await expect(workbench.getByRole('button', { name: 'Craft', exact: true })).toBeEnabled();
  await expect(workbench).toContainText('Missing: 40 Wood');
  await workbench.getByRole('button', { name: 'Craft', exact: true }).click();
  await expect(workbench).toContainText('Missing: 40 Wood');
  await expect.poll(() => page.evaluate(() => window.sceneFixture.productionItemCount('workbench'))).toBe(0);

  await page.evaluate(() => window.sceneFixture.grantProductionItem('wood', 40));
  await expect(workbench.getByRole('button', { name: 'Craft', exact: true })).toBeEnabled();
  await expect(workbench).toContainText('Wood: 40 / 40');
  await workbench.getByRole('button', { name: 'Craft', exact: true }).click();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.productionItemCount('workbench'))).toBe(1);
  await expect.poll(() => page.evaluate(() => window.sceneFixture.productionItemCount('wood'))).toBe(0);
  await expect(workbench).toContainText('Crafted 1 × Workbench');

  await page.keyboard.press('Escape');
  await expect(workbench).toBeHidden();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(false);
  await expect(priorFocus).toBeFocused();
  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
