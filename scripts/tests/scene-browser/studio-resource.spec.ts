import { expect, test } from '@playwright/test';

test('Scene Studio opens an external resource, edits it, undoes, redoes, and saves', async ({ page }) => {
  await page.goto('./studio.html?studio=scenes&resource=tiles.browser.ground.set');
  await expect(page.locator('.scene-resource-inspector h2')).toHaveText('tiles.browser.ground.set');
  const tiles = page.locator('[data-resource-field="tiles"]');
  const original = await tiles.inputValue();
  const edited = JSON.parse(original) as Record<string, unknown>;
  edited.sand = { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-order', physics: null, allowsDecorations: true, tags: ['ground'] };
  await tiles.fill(JSON.stringify(edited));
  await tiles.blur();
  await expect(page.getByRole('button', { name: 'Save changes' })).toBeEnabled();
  await page.getByRole('button', { name: 'Undo' }).click();
  expect(JSON.parse(await tiles.inputValue())).not.toHaveProperty('sand');
  await page.getByRole('button', { name: 'Redo' }).click();
  expect(JSON.parse(await tiles.inputValue())).toHaveProperty('sand');
  await page.getByRole('button', { name: 'Save changes' }).click();
  await expect.poll(() => page.evaluate(() => window.sceneStudioFixture.snapshot().tileSetTiles)).toBe(3);
  await expect.poll(() => page.evaluate(() => window.sceneStudioFixture.snapshot().lastWriteIds)).toEqual(['tiles.browser.ground.set']);
  await expect(page).toHaveURL(/resource=tiles\.browser\.ground\.set/);
});
