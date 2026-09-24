import { expect, test } from '@playwright/test';

test('authored world map reflects discovery and owns its modal lifecycle', async ({ page }) => {
  await page.setViewportSize({ width: 760, height: 540 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);

  const root = page.locator('[data-scene-ui-root]');
  const map = root.locator('.game-ui--world-map-ui');
  const priorFocus = page.locator('#fixture-control');
  await priorFocus.focus();
  await page.keyboard.press('m');
  await expect(map).toBeVisible();
  await expect(map.locator('[data-scene-control-id$="/level1"]')).toContainText('Current area');
  await expect(map.locator('[data-scene-control-id$="/gloop-forest"]')).toContainText('Unknown');
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(true);

  await page.evaluate(() => window.sceneFixture.discoverProductionArea('gloop-forest'));
  await expect(map.locator('[data-scene-control-id$="/gloop-forest"]')).toContainText('Gloop Forest');
  await expect(map.locator('[data-scene-control-id$="/level-gloop"]')).toContainText('━━━━');
  await page.keyboard.press('Escape');
  await expect(map).toBeHidden();
  await expect(priorFocus).toBeFocused();
  await expect.poll(() => page.evaluate(() => window.sceneFixture.snapshot().universalRuntimePaused)).toBe(false);
  await page.keyboard.press('m');
  await expect(map.locator('[data-scene-control-id$="/gloop-forest"]')).toContainText('Gloop Forest');
  await page.keyboard.press('m');
  await expect(map).toBeHidden();
  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
});
