import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'vite';

const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  server: { middlewareMode: true, hmr: false },
});

const {
  MAX_VISIBLE_COUNT,
  clampOffset,
  ensureVisible,
  getCraftingLayout,
  moveSelection,
  rowHeightFor,
  visibleRange,
  visibleCapacity,
} = await vite.ssrLoadModule('/src/game/ui/CraftingLayout.ts');

test.after(async () => {
  await vite.close();
});

test('normal layouts cap six compact rows and center the capped list', () => {
  const layout = getCraftingLayout(9, 1_440);

  assert.equal(MAX_VISIBLE_COUNT, 6);
  assert.equal(layout.capacityCount, 6);
  assert.equal(layout.windowCount, 6);
  assert.equal(layout.rowHeight, 46);
  assert.equal(layout.listHeight, 306);
  assert.equal(layout.maxOffset, 3);
});

test('compact layouts reduce the visible capacity instead of clipping rows', () => {
  const layout = getCraftingLayout(9, 170);

  assert.equal(layout.capacityCount, 3);
  assert.equal(layout.windowCount, 3);
  assert.equal(layout.rowHeight, 42);
  assert.equal(layout.listHeight, 138);
  assert.equal(layout.maxOffset, 6);
});

test('short catalogs render only their rows', () => {
  const layout = getCraftingLayout(4, 720);

  assert.equal(layout.capacityCount, 6);
  assert.equal(layout.windowCount, 4);
  assert.equal(layout.listHeight, 202);
  assert.equal(layout.maxOffset, 0);
});

test('non-finite and negative inputs normalize to safe layout values', () => {
  const empty = getCraftingLayout(Number.NaN, Number.POSITIVE_INFINITY);
  assert.equal(empty.windowCount, 0);
  assert.equal(empty.maxOffset, 0);
  assert.equal(empty.rowHeight, 40);
  assert.equal(visibleCapacity(Number.NaN), 1);
  assert.equal(rowHeightFor(Number.POSITIVE_INFINITY), 40);
  assert.equal(clampOffset(Number.NaN, -4, 8), 0);
  assert.equal(clampOffset(Number.POSITIVE_INFINITY, 20, 8), 0);
});

test('selection movement wraps while visibility keeps the selected row reachable', () => {
  assert.equal(moveSelection(0, -1, 4), 3);
  assert.equal(moveSelection(3, 1, 4), 0);
  assert.equal(moveSelection(Number.NaN, 1, 4), 1);
  assert.equal(ensureVisible(8, 0, 8, 9), 3);
  assert.equal(ensureVisible(0, 5, 8, 20), 0);
  assert.equal(ensureVisible(19, 0, 8, 20), 14);
});

test('visible ranges map window rows back to absolute recipe indices', () => {
  assert.deepEqual(visibleRange(9, 1, 8), { start: 1, end: 7 });
  assert.deepEqual(visibleRange(4, 99, 8), { start: 0, end: 4 });
  assert.deepEqual(visibleRange(20, Number.POSITIVE_INFINITY, 8), { start: 0, end: 6 });
});
