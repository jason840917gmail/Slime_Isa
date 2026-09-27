import { expect, test, type Page } from '@playwright/test';

/*
 * Behaviour tests against REAL production content: the authored
 * player-slime / NPC / worm-arrow scenes, real house and tree object scenes
 * and real map wall tiles, all mounted in the running production world with
 * the production collision layer data. Every assertion is about gameplay
 * (did the body stop at the solid?), not about node counts or layer values.
 */

type Rect = { readonly x: number; readonly y: number; readonly width: number; readonly height: number };

const APPROACH_GAP = 72;

async function openProductionWorld(page: Page, map: string): Promise<string[]> {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  page.on('console', (message) => {
    const text = message.text();
    // Headless software-rendered Chromium falls behind real time; the fixed-step
    // host reports the physics time it drops. That is frame pacing, not a fault.
    if (text.includes('of accumulated physics time after')) return;
    if (message.type() === 'error' && !text.startsWith('Failed to load resource:')) pageErrors.push(text);
  });
  await page.goto(`./?mode=baseline&map=${map}`);
  await expect.poll(async () => {
    if (pageErrors[0]) throw new Error(pageErrors[0]);
    const state = await page.evaluate(() => ({ ready: window.sceneFixture?.ready() === true, error: window.sceneFixture?.snapshot().initializationError }));
    if (state.error) throw new Error(state.error);
    return state.ready;
  }, { timeout: 45_000 }).toBe(true);
  await page.evaluate(() => window.sceneFixture.disableProductionEnemySpawning());
  return pageErrors;
}

/** Polls a rectangle until it stops changing for ~300ms (after a minimum drive time). */
async function settle(page: Page, read: () => Promise<Rect>, minimumMs = 700): Promise<Rect> {
  await page.waitForTimeout(minimumMs);
  let previous = await read();
  for (let attempt = 0; attempt < 40; attempt += 1) {
    await page.waitForTimeout(300);
    const next = await read();
    if (Math.abs(next.x - previous.x) < 0.01 && Math.abs(next.y - previous.y) < 0.01) return next;
    previous = next;
  }
  throw new Error(`Body never settled: ${JSON.stringify(previous)}`);
}

async function mountInClearRegion(page: Page, sceneId: string): Promise<{ mountId: string; rect: Rect }> {
  return page.evaluate((id) => {
    const region = window.physicsProbe.findClearRegion(640, 448, 384);
    if (!region) throw new Error(`No clear region for '${id}'`);
    const mountId = window.physicsProbe.mountScene(id, region.x + region.width / 2 + 96, region.y + region.height / 2);
    return { mountId, rect: window.physicsProbe.mountRootBodyRect(mountId) };
  }, sceneId);
}

/** A collidable map tile whose left side is exposed and far from exits (map edges). */
async function exposedWallTile(page: Page, corridorWidth: number, height: number): Promise<Rect> {
  const tile = await page.evaluate(({ corridorWidth: width, height: corridorHeight }) => {
    const bounds = window.physicsProbe.worldBounds();
    return window.physicsProbe.collidableTileRects().find((candidate) => {
      if (candidate.x - width < bounds.x + 256 || candidate.x > bounds.x + bounds.width - 256) return false;
      const centerY = candidate.y + candidate.height / 2;
      const corridor = { x: candidate.x - width, y: centerY - corridorHeight / 2, width: width - 1, height: corridorHeight };
      return window.physicsProbe.bodiesIn(corridor) === 0;
    }) ?? null;
  }, { corridorWidth, height });
  if (!tile) throw new Error('The production map has no exposed wall tile');
  return tile;
}

async function expectPlayerBlockedFromLeft(page: Page, target: Rect, label: string): Promise<void> {
  const player = await page.evaluate(() => window.physicsProbe.playerBodyRect());
  const centerX = target.x - APPROACH_GAP - player.width / 2;
  const centerY = target.y + target.height / 2;
  const corridor = { x: centerX - player.width / 2, y: centerY - player.height / 2, width: target.x - (centerX - player.width / 2) - 1, height: player.height };
  expect(await page.evaluate((rect) => window.physicsProbe.bodiesIn(rect), corridor), `${label}: approach corridor is clear`).toBe(0);
  await page.evaluate(({ x, y }) => window.physicsProbe.placePlayerBody(x, y), { x: centerX, y: centerY });
  await expect.poll(async () => {
    const rect = await page.evaluate(() => window.physicsProbe.playerBodyRect());
    return Math.abs(rect.x + rect.width / 2 - centerX) + Math.abs(rect.y + rect.height / 2 - centerY);
  }).toBeLessThan(0.5);

  await page.keyboard.down('ArrowRight');
  const stopped = await settle(page, () => page.evaluate(() => window.physicsProbe.playerBodyRect()));
  await page.keyboard.up('ArrowRight');
  const right = stopped.x + stopped.width;
  expect(right, `${label}: player moved toward the solid`).toBeGreaterThan(target.x - 4);
  expect(right, `${label}: player must not enter the solid`).toBeLessThanOrEqual(target.x + 0.5);
}

async function expectNpcBlockedFromLeft(page: Page, npcSceneId: string, target: Rect, label: string): Promise<void> {
  const centerY = target.y + target.height / 2;
  const mountId = await page.evaluate(({ id, x, y }) => window.physicsProbe.mountScene(id, x, y), {
    id: npcSceneId, x: target.x - APPROACH_GAP - 64, y: centerY,
  });
  const size = await page.evaluate((id) => window.physicsProbe.mountRootBodyRect(id), mountId);
  const centerX = target.x - APPROACH_GAP - size.width / 2;
  await page.evaluate(({ id, x, y }) => window.physicsProbe.placeMountBody(id, x, y), { id: mountId, x: centerX, y: centerY });
  await expect.poll(async () => {
    const rect = await page.evaluate((id) => window.physicsProbe.mountRootBodyRect(id), mountId);
    return Math.abs(rect.x + rect.width / 2 - centerX) + Math.abs(rect.y + rect.height / 2 - centerY);
  }).toBeLessThan(0.5);
  const initial = await page.evaluate((id) => window.physicsProbe.mountRootBodyRect(id), mountId);
  const corridor = { x: initial.x, y: initial.y, width: target.x - initial.x - 1, height: initial.height };
  expect(await page.evaluate(({ rect, id }) => window.physicsProbe.bodiesIn(rect, [id]), { rect: corridor, id: mountId }), `${label}: NPC corridor is clear`).toBe(0);
  await page.evaluate((id) => window.physicsProbe.driveMountBody(id, 140, 0), mountId);
  const stopped = await settle(page, () => page.evaluate((id) => window.physicsProbe.mountRootBodyRect(id), mountId));
  const right = stopped.x + stopped.width;
  expect(right, `${label}: NPC moved toward the solid`).toBeGreaterThan(target.x - 4);
  expect(right, `${label}: NPC must not enter the solid`).toBeLessThanOrEqual(target.x + 0.5);
}

test('the production player is blocked by a real house, a real tree and a real wall tile', async ({ page }) => {
  const pageErrors = await openProductionWorld(page, 'gloop-forest');
  const house = await mountInClearRegion(page, 'object.house-world-solid');
  await expectPlayerBlockedFromLeft(page, house.rect, 'house');
  const tree = await mountInClearRegion(page, 'object.tree-world-solid');
  await expectPlayerBlockedFromLeft(page, tree.rect, 'tree');
  const player = await page.evaluate(() => window.physicsProbe.playerBodyRect());
  const wall = await exposedWallTile(page, APPROACH_GAP + player.width * 2, player.height);
  await expectPlayerBlockedFromLeft(page, wall, 'wall tile');
  expect(pageErrors).toEqual([]);
});

test('a production NPC is blocked by a real house, a real tree and a real wall tile', async ({ page }) => {
  const pageErrors = await openProductionWorld(page, 'gloop-forest');
  const house = await mountInClearRegion(page, 'object.house-world-solid');
  await expectNpcBlockedFromLeft(page, 'character.lili', house.rect, 'house');
  const tree = await mountInClearRegion(page, 'object.tree-world-solid');
  await expectNpcBlockedFromLeft(page, 'character.lili', tree.rect, 'tree');
  const wall = await exposedWallTile(page, APPROACH_GAP + 160, 64);
  await expectNpcBlockedFromLeft(page, 'character.lili', wall, 'wall tile');
  expect(pageErrors).toEqual([]);
});

test('a production worm-arrow stops at a wall tile instead of flying through it', async ({ page }) => {
  const pageErrors = await openProductionWorld(page, 'gloop-forest');
  const wall = await exposedWallTile(page, 220, 48);
  await page.evaluate(({ x, y }) => window.physicsProbe.launchArrow(x, y, 1, 0, 180), { x: wall.x - 160, y: wall.y + wall.height / 2 });
  await expect.poll(() => page.evaluate(() => window.physicsProbe.arrowTrace().live), { timeout: 20_000 }).toBe(0);
  const trace = await page.evaluate(() => window.physicsProbe.arrowTrace());
  expect(trace.steps).toBeGreaterThan(10);
  // Expired by the wall contact, well before its 3000ms lifetime would have carried it ~540px.
  expect(trace.steps * (1000 / 60)).toBeLessThan(2_000);
  expect(trace.maxRight).toBeGreaterThan(wall.x - 4);
  expect(trace.maxRight).toBeLessThanOrEqual(wall.x + 0.5);
  expect(pageErrors).toEqual([]);
});

test('the production player cannot leave the loaded world bounds', async ({ page }) => {
  const pageErrors = await openProductionWorld(page, 'test-rectangle');
  const bounds = await page.evaluate(() => window.physicsProbe.worldBounds());
  // The loaded world's size, not the canvas size.
  expect(bounds).toEqual({ x: 0, y: 0, width: 8 * 64, height: 5 * 64 });
  const start = await page.evaluate(() => window.physicsProbe.playerBodyRect());
  expect(await page.evaluate((rect) => window.physicsProbe.bodiesIn(rect), { x: 0, y: 0, width: start.x + start.width, height: start.y + start.height })).toBe(0);

  await page.keyboard.down('ArrowLeft');
  const left = await settle(page, () => page.evaluate(() => window.physicsProbe.playerBodyRect()));
  await page.keyboard.up('ArrowLeft');
  expect(left.x).toBeGreaterThanOrEqual(bounds.x - 0.01);
  expect(left.x).toBeLessThan(bounds.x + 1);

  await page.keyboard.down('ArrowUp');
  const top = await settle(page, () => page.evaluate(() => window.physicsProbe.playerBodyRect()));
  await page.keyboard.up('ArrowUp');
  expect(top.y).toBeGreaterThanOrEqual(bounds.y - 0.01);
  expect(top.y).toBeLessThan(bounds.y + 1);
  expect(pageErrors).toEqual([]);
});
