import { expect, test } from '@playwright/test';

test('authored quest journal shows active objectives and restores focus', async ({ page }) => {
  await page.setViewportSize({ width: 760, height: 540 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);

  const root = page.locator('[data-scene-ui-root]');
  const journal = root.locator('.game-ui--quest-journal');
  const priorFocus = page.locator('#fixture-control');
  await priorFocus.focus();
  // One menu (roadmap 4.10): E opens the bag, and its Journal tab switches to the quests.
  await page.keyboard.press('e');
  await root.locator('.game-ui--menu-tabs').getByRole('button', { name: 'Journal tab' }).click();
  await expect(journal).toBeVisible();
  await expect(journal.getByRole('listbox', { name: 'Quests' })).toContainText('A Place to Work');
  await expect(journal).toContainText('Craft a Workbench (40 wood): 0/1');
  await expect(journal.getByRole('button', { name: 'No action' })).toBeDisabled();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(true);

  await page.keyboard.press('Escape');
  await expect(journal).toBeHidden();
  await expect(priorFocus).toBeFocused();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(false);
  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});

test('authored quest turn-in retains service errors and releases its modal session', async ({ page }) => {
  await page.setViewportSize({ width: 760, height: 540 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);

  const root = page.locator('[data-scene-ui-root]');
  const offer = root.locator('.game-ui--quest-offer-modal');
  const priorFocus = page.locator('#fixture-control');
  await priorFocus.focus();
  await page.evaluate(() => window.sceneFixture.openProductionQuestTurnInForUi());
  await expect(offer).toBeVisible();
  await expect(offer).toContainText('A Place to Work');
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(true);
  await offer.getByRole('button', { name: 'Turn in and claim reward' }).click();
  await expect(offer).toBeVisible();
  await expect(offer).toContainText('cannot be turned in');
  await page.keyboard.press('Escape');
  await expect(offer).toBeHidden();
  await expect(priorFocus).toBeFocused();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(false);
  expect(await page.evaluate(() => window.sceneFixture.productionQuestTurnInClosedCount())).toBe(1);
  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
