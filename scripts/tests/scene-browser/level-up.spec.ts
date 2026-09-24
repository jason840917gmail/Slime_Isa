import { expect, test } from '@playwright/test';

test('authored level-up keeps pending choices and accepts pointer and number keys', async ({ page }) => {
  await page.setViewportSize({ width: 760, height: 540 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);

  const root = page.locator('[data-scene-ui-root]');
  const modal = root.locator('.game-ui--level-up-modal');
  const priorFocus = page.locator('#fixture-control');
  await priorFocus.focus();
  await page.evaluate(() => window.sceneFixture.triggerProductionLevelUp());
  await expect(modal).toBeVisible();
  await expect(modal.getByRole('listbox', { name: 'Upgrade choices' }).getByRole('option')).toHaveCount(3);
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(true);
  const firstChoice = modal.getByRole('option').first();
  const firstChoiceId = await firstChoice.getAttribute('data-item-id');
  const firstChoiceText = await firstChoice.textContent();
  expect(firstChoiceId).toBeTruthy();
  expect(await page.evaluate(() => window.sceneFixture.productionSkillPoints())).toBe(1);

  await page.keyboard.press('Escape');
  await expect(modal).toBeHidden();
  await expect(priorFocus).toBeFocused();
  expect(await page.evaluate(() => window.sceneFixture.productionSkillPoints())).toBe(1);
  await page.keyboard.press('p');
  await expect(modal).toBeVisible();
  await expect(modal.getByRole('option').first()).toHaveText(firstChoiceText ?? '');
  await modal.getByRole('option').first().click();
  await expect(modal).toBeHidden();
  expect(await page.evaluate(() => window.sceneFixture.productionSkillPoints())).toBe(0);
  expect(await page.evaluate((id) => window.sceneFixture.productionPerkRank(id), firstChoiceId!)).toBe(1);

  await page.evaluate(() => window.sceneFixture.triggerProductionLevelUp());
  await expect(modal).toBeVisible();
  const keyboardChoiceId = await modal.getByRole('option').first().getAttribute('data-item-id');
  await page.keyboard.press('1');
  await expect(modal).toBeHidden();
  expect(await page.evaluate(() => window.sceneFixture.productionSkillPoints())).toBe(0);
  expect(await page.evaluate((id) => window.sceneFixture.productionPerkRank(id), keyboardChoiceId!)).toBeGreaterThan(0);
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(false);
  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
