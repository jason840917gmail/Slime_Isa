import { expect, test } from '@playwright/test';

type BaselineSample = {
  mapId: string;
  viewport: string;
  renderer: string;
  warmupFrames: number;
  sampleFrames: number;
  loadTimeMs: number;
  medianFrameMs: number;
  p95FrameMs: number;
  gameObjectCount: number;
  bodyCount: number;
  managedBlockingColliderCount: number;
  managedContactParticipantCount: number;
  cleanupCount: number;
};

async function sampleMap(page: import('@playwright/test').Page, mapId: string): Promise<BaselineSample> {
  await page.goto(`./?mode=baseline&map=${encodeURIComponent(mapId)}`);
  await page.waitForFunction(() => window.sceneFixture !== undefined);
  const initial = await page.evaluate(() => window.sceneFixture.snapshot());
  expect(initial.initializationError).toBeUndefined();
  await page.waitForFunction(() => window.sceneFixture?.ready() === true, undefined, { timeout: 45_000 });
  const timing = await page.evaluate(async () => {
    const collect = (count: number) => new Promise<number[]>((resolve) => {
      const deltas: number[] = [];
      let previous = performance.now();
      const frame = (now: number): void => {
        deltas.push(now - previous);
        previous = now;
        if (deltas.length >= count) resolve(deltas);
        else requestAnimationFrame(frame);
      };
      requestAnimationFrame(frame);
    });
    await collect(120);
    const frames = await collect(300);
    frames.sort((left, right) => left - right);
    return {
      medianFrameMs: frames[Math.floor(frames.length / 2)],
      p95FrameMs: frames[Math.floor(frames.length * 0.95)],
    };
  });
  const live = await page.evaluate(() => window.sceneFixture.snapshot());
  await page.evaluate(() => window.sceneFixture.destroy());
  await expect.poll(() => page.locator('canvas').count()).toBe(0);
  return {
    mapId,
    viewport: '1280x720',
    renderer: 'Chromium/Phaser AUTO',
    warmupFrames: 120,
    sampleFrames: 300,
    loadTimeMs: live.loadedAtMs ?? -1,
    medianFrameMs: timing.medianFrameMs,
    p95FrameMs: timing.p95FrameMs,
    gameObjectCount: live.gameObjectCount,
    bodyCount: live.bodyCount,
    managedBlockingColliderCount: live.managedBlockingColliderCount ?? 0,
    managedContactParticipantCount: live.managedContactParticipantCount ?? 0,
    cleanupCount: live.gameObjectCount + live.bodyCount,
  };
}

test('records deterministic-procedure baselines for small and large authored maps', async ({ page }, testInfo) => {
  test.setTimeout(150_000);
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.addInitScript(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  const samples = [
    await sampleMap(page, 'test-rectangle'),
    await sampleMap(page, 'tiktok'),
  ];
  await testInfo.attach('universal-scene-baseline.json', {
    body: Buffer.from(`${JSON.stringify(samples, null, 2)}\n`),
    contentType: 'application/json',
  });
  console.log(`UNIVERSAL_SCENE_BASELINE=${JSON.stringify(samples)}`);
  expect(samples.every((sample) => sample.loadTimeMs > 0)).toBe(true);
  expect(samples.every((sample) => sample.medianFrameMs > 0 && sample.p95FrameMs >= sample.medianFrameMs)).toBe(true);
  expect(samples.every((sample) => sample.managedBlockingColliderCount < sample.bodyCount)).toBe(true);
  expect(pageErrors).toEqual([]);
});
