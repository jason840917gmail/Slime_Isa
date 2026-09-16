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

test('Level 1 spawns Worm Brawler through the universal runtime without a legacy duplicate', async ({ page }) => {
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
  const authored = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(authored.managedCampCount).toBe(1);
  expect(authored.managedChestCount).toBe(1);
  expect(authored.managedNpcCount).toBe(5);
  expect(authored.managedPlayerCount).toBe(1);
  expect(authored.managedResourceCount).toBe(6);
  expect(authored.legacyNpcCount).toBe(0);
  expect(authored.hasLegacyChestController).toBe(false);
  await page.keyboard.down('ArrowRight');
  await expect.poll(async () => (
    await page.evaluate(() => window.sceneFixture.snapshot().managedPlayerX ?? 0)
  )).toBeGreaterThan((authored.managedPlayerX ?? 0) + 10);
  await page.keyboard.up('ArrowRight');
  const moved = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(Math.abs((moved.managedPlayerX ?? 0) - (moved.legacyPlayerX ?? 0))).toBeLessThan(2);
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
  page.on('console', (message) => {
    if (message.type() === 'error' && !message.text().startsWith('Failed to load resource:')) pageErrors.push(message.text());
  });
  await page.goto('./?mode=baseline&map=level-1');
  await waitForProductionReady(page, pageErrors);
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

test('managed projectile and impact effect scenes complete their production lifecycles', async ({ page }) => {
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
  await page.evaluate(() => window.sceneFixture.disableProductionEnemySpawning());
  await page.evaluate(() => window.sceneFixture.teleportProductionPlayer(1_200, 1_550));
  const before = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(before.playerHp).toBeGreaterThan(0);
  expect(await page.evaluate(() => window.sceneFixture.spawnManagedEnemy('worm-archer', 1_000, 1_550))).toBe(true);
  await expect.poll(async () => (
    await page.evaluate(() => window.sceneFixture.snapshot().managedProjectileSpawnCount ?? 0)
  ), { timeout: 10_000 }).toBeGreaterThan(0);
  await expect.poll(async () => (
    await page.evaluate(() => window.sceneFixture.snapshot().playerHp ?? Number.POSITIVE_INFINITY)
  ), { timeout: 5_000 }).toBe(before.playerHp! - 20);
  await expect.poll(async () => (
    await page.evaluate(() => window.sceneFixture.snapshot().managedProjectileCount ?? -1)
  ), { timeout: 5_000 }).toBe(0);
  expect((await page.evaluate(() => window.sceneFixture.snapshot())).managedProjectileSpawnCount).toBe(1);
  expect(await page.evaluate(() => window.sceneFixture.spawnManagedEffect('basic-sword-impact', 'left', 1_200, 1_550))).toBe(true);
  expect((await page.evaluate(() => window.sceneFixture.snapshot())).managedEffectCount).toBe(1);
  await expect.poll(async () => (
    await page.evaluate(() => window.sceneFixture.snapshot().managedEffectCount ?? -1)
  ), { timeout: 5_000 }).toBe(0);
  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
});

test('equipped weapons mount under the managed player and own the attack lifecycle', async ({ page }) => {
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
  expect(await page.evaluate(() => window.sceneFixture.equipProductionWeapon('basic-sword'))).toBe(true);
  let snapshot = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(snapshot.managedWeaponId).toBe('basic-sword');
  expect(await page.evaluate(() => window.sceneFixture.equipProductionWeapon('slam-hammer'))).toBe(true);
  snapshot = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(snapshot.managedWeaponId).toBe('slam-hammer');
  expect(await page.evaluate(() => window.sceneFixture.attackWithProductionWeapon())).toBe(true);
  expect((await page.evaluate(() => window.sceneFixture.snapshot())).managedWeaponAttacking).toBe(true);
  await expect.poll(async () => (
    await page.evaluate(() => window.sceneFixture.snapshot().managedWeaponAttacking)
  )).toBe(false);
  expect(pageErrors).toEqual([]);
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
});
