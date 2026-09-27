import { expect, test } from '@playwright/test';

test('Scene Studio renders the scene through the embedded runtime with pan, zoom, framing and selection', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.setViewportSize({ width: 1400, height: 820 });
  await page.goto('./studio.html?studio=scenes&scene=browser.studio');
  await page.waitForFunction(() => window.sceneStudioFixture?.ready() === true);
  await expect.poll(() => page.evaluate(() => window.sceneStudioFixture.diagnostics().preview?.status), { timeout: 20_000 }).toBe('ready');
  const diagnostics = await page.evaluate(() => window.sceneStudioFixture.diagnostics());
  // The 4×3 tile layer (64px cells) is mounted by TileMapLayer2DNode, so the rendered bounds come from the runtime.
  expect(diagnostics.preview?.contentBounds).toEqual({ x: 0, y: 0, width: 64, height: 64 });
  await expect(page.locator('.scene-viewport-stage canvas')).toHaveCount(1);
  // Layout stays inside the window: the status bar and viewport are on screen.
  await expect(page.getByRole('status')).toBeInViewport();
  await expect(page.locator('.scene-live-viewport')).toBeInViewport();

  // The canvas survives Studio re-renders.
  await page.evaluate(() => { (window as unknown as { studioCanvas?: Element }).studioCanvas = document.querySelector('.scene-viewport-stage canvas') ?? undefined; });
  await page.getByRole('treeitem', { name: /Behavior/ }).click();
  expect(await page.evaluate(() => document.querySelector('.scene-viewport-stage canvas') === (window as unknown as { studioCanvas?: Element }).studioCanvas)).toBe(true);

  // Wheel zoom around the cursor, drag pan, and frame all.
  const overlay = page.locator('.scene-viewport-overlay');
  const box = (await overlay.boundingBox())!;
  const before = (await page.evaluate(() => window.sceneStudioFixture.diagnostics().camera))!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.wheel(0, 300);
  await expect.poll(async () => (await page.evaluate(() => window.sceneStudioFixture.diagnostics().camera))!.zoom).toBeLessThan(before.zoom);
  const zoomed = (await page.evaluate(() => window.sceneStudioFixture.diagnostics().camera))!;
  await page.mouse.move(box.x + 40, box.y + 40);
  await page.mouse.down({ button: 'middle' });
  await page.mouse.move(box.x + 140, box.y + 90, { steps: 4 });
  await page.mouse.up({ button: 'middle' });
  const panned = (await page.evaluate(() => window.sceneStudioFixture.diagnostics().camera))!;
  expect(panned.centerX).toBeCloseTo(zoomed.centerX - 100 / zoomed.zoom, 3);
  await page.getByRole('button', { name: 'Frame all' }).click();
  const framed = (await page.evaluate(() => window.sceneStudioFixture.diagnostics().camera))!;
  expect(framed.centerX).toBeCloseTo(32, 0);

  // Viewport markers select tree rows; composed positions include the parent chain.
  await page.getByRole('button', { name: 'Select Scout' }).click();
  await expect(page.getByRole('treeitem', { name: /Scout/ })).toHaveAttribute('aria-selected', 'true');

  // Explorer search filters scenes and resources without re-rendering the input.
  const search = page.getByRole('searchbox', { name: 'Filter scenes and resources' });
  await search.fill('ground.set');
  await expect(page.locator('[data-resource-id="tiles.browser.ground.set"]')).toBeVisible();
  await expect(page.locator('[data-resource-id="tiles.browser.ground.data"]')).toBeHidden();
  await expect(page.locator('[data-scene-id="browser.studio"]')).toBeHidden();
  await expect(search).toBeFocused();
  expect(errors).toEqual([]);
});

test('Scene Studio copies and pastes node subtrees with the clipboard', async ({ page }) => {
  await page.goto('./studio.html?studio=scenes&scene=browser.studio');
  await page.waitForFunction(() => window.sceneStudioFixture?.ready() === true);
  await page.getByRole('treeitem', { name: /Scout/ }).click();
  await page.getByRole('button', { name: 'Copy node' }).click();
  await page.getByRole('button', { name: 'Paste node' }).click();
  await expect(page.getByRole('treeitem', { name: /Scout/ })).toHaveCount(2);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect(page.getByRole('treeitem', { name: /Scout/ })).toHaveCount(1);
});
