import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { brushCoordinates, tilePaintCommands } = await loadTypescriptModule('src/game/editor/scene-studio/TilePaintCommand.ts');
const { TileMapContext, createTileLayerDraft, tileDataResourceId } = await loadTypescriptModule('src/game/editor/scene-studio/contexts/TileMapContext.ts');

const tileSet = {
  version: 1,
  resourceId: 'tiles.test.set',
  kind: 'tile-set',
  tiles: {
    grass: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-order', physics: null, allowsDecorations: true, tags: ['ground'] },
    wall: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-order', physics: { body: 'static' }, allowsDecorations: false, tags: ['solid'] },
  },
};

const tileData = () => ({
  version: 1,
  resourceId: 'tiles.test.data',
  kind: 'tile-data',
  tileSet: 'tiles.test.set',
  columns: 4,
  rows: 3,
  cells: [
    { x: 0, y: 0, tileId: 'grass' },
    { x: 1, y: 0, tileId: 'grass' },
    { x: 0, y: 1, tileId: 'grass' },
    { x: 1, y: 1, tileId: 'wall' },
  ],
});

test('tile paint commands stay bounded, deterministic, and preserve stable tile IDs', () => {
  assert.deepEqual(brushCoordinates({ x: 0, y: 0 }, 3, { columns: 4, rows: 3 }), [
    { x: 0, y: 0 }, { x: 1, y: 0 }, { x: 0, y: 1 }, { x: 1, y: 1 },
  ]);
  const painted = tilePaintCommands.paint([{ x: 2, y: 1 }, { x: 1, y: 0 }], 'wall').apply(tileData());
  assert.deepEqual(painted.cells.map((cell) => `${cell.x},${cell.y}:${cell.tileId}`), [
    '0,0:grass', '1,0:wall', '0,1:grass', '1,1:wall', '2,1:wall',
  ]);
  const erased = tilePaintCommands.erase([{ x: 1, y: 1 }]).apply(painted);
  assert.equal(erased.cells.some((cell) => cell.x === 1 && cell.y === 1), false);
  assert.throws(() => tilePaintCommands.paint([{ x: 4, y: 0 }], 'wall').apply(tileData()), /outside 4x3/);
});

test('fill is contiguous and tile context combines tools, overlays, navigation, and undo history', () => {
  const context = new TileMapContext(tileData(), tileSet);
  context.selectTile('wall');
  context.selectTool('fill');
  context.paint({ x: 0, y: 0 });
  assert.equal(context.cells.filter((cell) => cell.tileId === 'wall').length, 4);
  assert.equal(context.dirty, true);
  assert.equal(context.undo(), true);
  assert.equal(context.cells.filter((cell) => cell.tileId === 'wall').length, 1);
  assert.equal(context.redo(), true);
  context.toggleCollision();
  context.toggleEffectiveRegion();
  context.panBy(99, 99);
  context.setZoom(9);
  assert.equal(context.showCollision, true);
  assert.equal(context.showEffectiveRegion, false);
  assert.deepEqual(context.pan, { x: 3, y: 2 });
  assert.equal(context.zoom, 3);
  assert.deepEqual(context.snap(129, 65, 64), { x: 2, y: 1 });
  assert.equal(context.isCollisionCell({ x: 0, y: 0 }), true);
  context.markSaved();
  assert.equal(context.dirty, false);
});

test('tile-set changes reject lost IDs and layer drafts bind external tile data', () => {
  const context = new TileMapContext(tileData(), tileSet);
  assert.throws(() => context.selectTileSet({
    ...tileSet,
    resourceId: 'tiles.empty.set',
    tiles: { grass: tileSet.tiles.grass },
  }), /missing used tiles: wall/);
  const draft = createTileLayerDraft({
    sceneId: 'world.level-1',
    nodeId: 'layer-overlay',
    name: 'overlay',
    parentId: 'world',
    order: 2,
    columns: 56,
    rows: 56,
    tileSize: 64,
    tileSet: 'tiles.level-1.ground.set',
    seed: 1,
  });
  assert.equal(draft.node.type, 'TileMapLayer2D');
  assert.equal(tileDataResourceId(draft.node), 'tiles.level-1.overlay.data');
  assert.equal(draft.data.tileSet, 'tiles.level-1.ground.set');
  assert.equal(draft.relativePath, 'authored/resources/tiles/level-1.overlay.tile-data.resource.json');
});
