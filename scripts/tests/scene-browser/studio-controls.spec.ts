import { expect, test } from '@playwright/test';

test('real Scene Studio controls preserve focus, selection, undo, and save conflicts', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./studio.html?studio=scenes&scene=browser.studio');
  await page.waitForFunction(() => window.sceneStudioFixture?.ready() === true);
  await page.getByRole('treeitem', { name: /Scout/ }).click();
  await expect(page.getByRole('complementary', { name: 'Inspector' }).getByRole('heading', { name: 'Scout' })).toBeVisible();
  await page.getByRole('treeitem', { name: /Scout/ }).focus();
  await page.keyboard.press('ArrowDown');
  await expect(page.getByRole('treeitem', { name: /Behavior/ })).toBeFocused();
  await page.getByRole('button', { name: /Open fixtures\/Actor\.ts/ }).click();
  expect((await page.evaluate(() => window.sceneStudioFixture.snapshot())).openedSource).toBe('fixtures/Actor.ts');
  await page.getByRole('treeitem', { name: /Scout/ }).click();
  await page.getByRole('button', { name: 'Add node' }).click();
  await expect(page.getByRole('dialog', { name: 'Add a universal node' })).toBeVisible();
  await page.getByRole('dialog').getByRole('searchbox').fill('Area2D');
  await page.getByRole('option', { name: /Area2D/ }).click();
  await expect(page.getByRole('button', { name: 'Save changes' })).toBeEnabled();
  await page.keyboard.press('Control+z');
  await expect(page.getByRole('treeitem', { name: /Area2D/ })).toHaveCount(0);
  await page.keyboard.press('Control+y');
  await page.evaluate(() => window.sceneStudioFixture.setConflict(true));
  await page.getByRole('button', { name: 'Save changes' }).click();
  await expect(page.getByRole('status')).toContainText('Save conflict');
  await expect(page.getByRole('button', { name: 'Save changes' })).toBeEnabled();
  expect(errors).toEqual([]);
});

test('tile map context paints external resources with overlays, undo, and atomic save', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./studio.html?studio=scenes&scene=browser.studio');
  await page.waitForFunction(() => window.sceneStudioFixture?.ready() === true);
  await page.getByRole('treeitem', { name: /Ground/ }).click();
  await expect(page.getByRole('region', { name: 'Tile map tools' })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Tile map viewport' })).toContainText('SNAP 64px');
  await page.getByRole('button', { name: /wall solid/ }).click();
  await page.getByRole('button', { name: 'Cell 1,0 empty' }).click();
  await expect(page.getByRole('button', { name: 'Cell 1,0 wall' })).toBeVisible();
  await page.getByRole('button', { name: 'Collision' }).click();
  await expect(page.getByRole('button', { name: 'Cell 1,0 wall' })).toHaveClass(/is-collision/);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect(page.getByRole('button', { name: 'Cell 1,0 empty' })).toBeVisible();
  await page.getByRole('button', { name: /wall solid/ }).click();
  await page.getByRole('button', { name: 'Cell 1,0 empty' }).click();
  await page.getByRole('button', { name: 'Save changes' }).click();
  await expect(page.getByRole('button', { name: 'Saved' })).toBeDisabled();
  expect((await page.evaluate(() => window.sceneStudioFixture.snapshot())).tileCells).toBe(2);
  expect(errors).toEqual([]);
});

test('adding a tile layer commits the scene reference and new external resource together', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('./studio.html?studio=scenes&scene=browser.studio');
  await page.waitForFunction(() => window.sceneStudioFixture?.ready() === true);
  await page.getByRole('treeitem', { name: /Ground/ }).click();
  await page.getByRole('button', { name: '+ Layer' }).click();
  await expect(page.getByRole('treeitem', { name: /overlay-1/ })).toBeVisible();
  await page.getByRole('button', { name: 'Save changes' }).click();
  const snapshot = await page.evaluate(() => window.sceneStudioFixture.snapshot());
  expect(snapshot.lastWriteIds).toEqual(['browser.studio', 'tiles.browser.studio.overlay-1.data']);
  expect(errors).toEqual([]);
});
