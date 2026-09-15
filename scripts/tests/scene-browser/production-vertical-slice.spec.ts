import { expect, test } from '@playwright/test';

test('Level 1 spawns Worm Brawler through the universal runtime without a legacy duplicate', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.addInitScript(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true, undefined, { timeout: 45_000 });
  const authored = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(authored.managedCampCount).toBe(1);
  expect(authored.managedChestCount).toBe(1);
  expect(authored.managedNpcCount).toBe(5);
  expect(authored.legacyNpcCount).toBe(0);
  expect(authored.hasLegacyChestController).toBe(false);
  await page.evaluate(() => window.sceneFixture.teleportProductionPlayer(2_528, 1_472));
  await expect.poll(async () => {
    const snapshot = await page.evaluate(() => window.sceneFixture.snapshot());
    return snapshot.managedBossCount;
  }, { timeout: 10_000 }).toBe(1);
  await page.evaluate(() => window.sceneFixture.teleportProductionPlayer(1_200, 1_550));
  await expect.poll(async () => {
    const snapshot = await page.evaluate(() => window.sceneFixture.snapshot());
    return snapshot.managedOrdinaryEnemyCount;
  }, { timeout: 10_000 }).toBeGreaterThan(0);
  const live = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(live.legacyEnemyCount).toBe(0);
  expect(live.managedBossCount).toBe(1);
  expect(live.managedLiveCampCount).toBe(1);
  expect(live.legacyBossCount).toBe(0);
  expect(live.universalRuntimePaused).toBe(false);
  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
});

test('remaining ordinary enemy scenes mount through the production Phaser runtime', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.addInitScript(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('./?mode=baseline&map=level-1');
  await page.waitForFunction(() => window.sceneFixture?.ready() === true, undefined, { timeout: 45_000 });
  const before = await page.evaluate(() => window.sceneFixture.snapshot().managedOrdinaryEnemyCount ?? 0);
  const mounted = await page.evaluate(() => [
    window.sceneFixture.spawnManagedEnemy('worm-archer', 1_180, 1_520),
    window.sceneFixture.spawnManagedEnemy('worm-swordsman', 1_220, 1_520),
    window.sceneFixture.spawnManagedEnemy('slime-spider', 1_260, 1_520),
  ]);
  expect(mounted).toEqual([true, true, true]);
  await expect.poll(async () => (
    await page.evaluate(() => window.sceneFixture.snapshot().managedOrdinaryEnemyCount ?? 0)
  )).toBe(before + 3);
  expect((await page.evaluate(() => window.sceneFixture.snapshot())).legacyEnemyCount).toBe(0);
  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
});
