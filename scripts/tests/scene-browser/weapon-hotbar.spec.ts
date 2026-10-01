import { expect, test } from '@playwright/test';

test('authored weapon hotbar hydrates, equips by pointer and keyboard, refreshes, and cleans up', async ({ page }) => {
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
  const hotbar = root.locator('.game-ui--weapon-hotbar');
  const list = hotbar.getByRole('listbox', { name: 'Weapon hotbar' });
  const slots = list.getByRole('option');
  await expect(hotbar).toBeVisible();
  await expect(slots).toHaveCount(3);
  // Slots carry no number keys any more: the mouse wheel switches weapons (roadmap 4.10).
  await expect(slots.first()).toContainText('Empty');
  await expect.poll(() => list.locator('button:disabled').count()).toBeGreaterThan(0);

  await page.evaluate(() => window.sceneFixture.grantProductionWeapons());
  await expect.poll(() => list.locator('button:not(:disabled)').count()).toBeGreaterThan(1);
  await expect.poll(() => list.locator('img').count()).toBeGreaterThan(1);
  const pointerTarget = list.locator('button:not(:disabled):not([aria-selected="true"])').first();
  const pointerSlot = await pointerTarget.getAttribute('data-item-id');
  await pointerTarget.click();
  await expect(list.locator(`[data-item-id="${pointerSlot}"]`)).toHaveAttribute('aria-selected', 'true');
  const pointerIndex = Number(pointerSlot?.slice(5)) - 1;
  const pointerWeapon = await page.evaluate((index) => window.sceneFixture.snapshot().weaponSlots?.[index], pointerIndex);
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().equippedWeaponId)).toBe(pointerWeapon);

  await list.focus();
  await page.keyboard.press('Home');
  await expect(slots.first()).toHaveAttribute('aria-selected', 'true');
  const firstWeapon = await page.evaluate(() => window.sceneFixture.snapshot().weaponSlots?.[0]);
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().equippedWeaponId)).toBe(firstWeapon);

  await page.evaluate(() => window.sceneFixture.setProductionEquippedSlot(2));
  await expect(slots.nth(2)).toHaveAttribute('aria-selected', 'true');

  await page.setViewportSize({ width: 760, height: 540 });
  await expect.poll(() => hotbar.evaluate((element) => {
    const bounds = element.getBoundingClientRect();
    return bounds.left >= 0 && bounds.right <= window.innerWidth && bounds.top >= 0 && bounds.bottom <= window.innerHeight;
  })).toBe(true);

  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
