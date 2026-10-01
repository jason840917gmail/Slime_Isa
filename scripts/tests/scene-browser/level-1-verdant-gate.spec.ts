import { expect, test } from '@playwright/test';

async function waitForProductionReady(page: import('@playwright/test').Page, pageErrors: readonly string[]): Promise<void> {
  await expect.poll(async () => {
    if (pageErrors[0]) throw new Error(pageErrors[0]);
    const state = await page.evaluate(() => ({
      ready: window.sceneFixture?.ready() === true,
      error: window.sceneFixture?.snapshot().initializationError,
    }));
    if (state.error) throw new Error(state.error);
    return state.ready;
  }, { timeout: 45_000 }).toBe(true);
}

const playerY = (page: import('@playwright/test').Page) => page.evaluate(() => window.sceneFixture.snapshot().managedPlayerY ?? 0);

/** Right click over the game: interacts with the target in reach (the gate). */
async function interact(page: import('@playwright/test').Page): Promise<void> {
  await page.locator('canvas').first().click({ button: 'right' });
}

async function walkNorth(page: import('@playwright/test').Page, ms: number): Promise<void> {
  await page.keyboard.down('ArrowUp');
  await page.waitForTimeout(ms);
  await page.keyboard.up('ArrowUp');
}

test('the Verdant Gate blocks the way east until the green key unlocks it', async ({ page }) => {
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
  await waitForProductionReady(page, pageErrors);

  // South of the closed gate: walking north stops at the doors.
  await page.evaluate(() => window.sceneFixture.teleportProductionPlayer(3_264, 860));
  await walkNorth(page, 1_200);
  expect(await playerY(page)).toBeGreaterThan(730);

  // Without the key the gate stays shut.
  await interact(page);
  await walkNorth(page, 600);
  expect(await playerY(page)).toBeGreaterThan(730);

  // With the key, interacting opens the gate and consumes the key.
  await page.evaluate(() => window.sceneFixture.grantProductionItem('green-key', 1));
  await interact(page);
  await expect.poll(() => page.evaluate(() => window.sceneFixture.productionItemCount('green-key'))).toBe(0);
  await walkNorth(page, 1_400);
  expect(await playerY(page)).toBeLessThan(700);

  // The exit behind the gate shares the unlocked record and leads to Gloop Forest.
  await page.evaluate(() => window.sceneFixture.teleportProductionPlayer(3_540, 576));
  await expect.poll(() => new URL(page.url()).searchParams.get('area'), { timeout: 15_000 }).toBe('gloop-forest');
  await waitForProductionReady(page, pageErrors);
  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
});
