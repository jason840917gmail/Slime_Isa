import { expect, test } from '@playwright/test';

test('authored minimap draws player and camera into its canvas host', async ({ page }) => {
  await page.setViewportSize({ width: 760, height: 540 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await expect.poll(() => page.evaluate(() => window.sceneFixture?.ready() === true), { timeout: 45_000 }).toBe(true);

  const root = page.locator('[data-scene-ui-root]');
  const minimap = root.locator('.game-ui--minimap');
  const canvas = minimap.locator('canvas.scene-minimap-canvas');
  await expect(canvas).toBeVisible();
  await expect(minimap.locator('img.scene-minimap-frame')).toHaveAttribute('src', /^data:image\/png/);
  await expect.poll(() => canvas.evaluate((element) => {
    const image = element as HTMLCanvasElement;
    const pixels = image.getContext('2d')?.getImageData(0, 0, image.width, image.height).data;
    if (!pixels) return false;
    for (let index = 3; index < pixels.length; index += 4) if (pixels[index] > 0) return true;
    return false;
  })).toBe(true);

  const previousPosition = await canvas.getAttribute('aria-label');
  await page.evaluate(() => window.sceneFixture.teleportProductionPlayer(100, 100));
  await expect.poll(() => canvas.getAttribute('aria-label')).not.toBe(previousPosition);
  await expect(canvas).toHaveAttribute('aria-label', /Player at 1\d\d, 1\d\d/);
  await expect.poll(() => minimap.evaluate((element) => {
    const box = element.getBoundingClientRect();
    const viewport = element.closest('[data-scene-ui-root]')?.getBoundingClientRect();
    return Boolean(viewport && box.left >= viewport.left && box.right <= viewport.right && box.top >= viewport.top && box.bottom <= viewport.bottom);
  })).toBe(true);
  expect(errors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect(root.locator('.scene-control')).toHaveCount(0);
  await expect(root.locator('canvas.scene-minimap-canvas')).toHaveCount(0);
});
