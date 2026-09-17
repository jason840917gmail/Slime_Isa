import assert from 'node:assert/strict';
import test from 'node:test';

import { loadSceneTooling } from '../../lib/scene-conversion/load-scene-tooling.mjs';

const tooling = await loadSceneTooling();

const tileSet = {
  version: 1,
  resourceId: 'tiles.world',
  kind: 'tile-set',
  tiles: {
    grass: {
      assetIds: ['terrain.grass'], selection: 'seeded-hash', physics: null,
      allowsDecorations: true, tags: ['ground', 'walkable'], editor: { color: '#54a36b' },
    },
    wall: {
      assetIds: ['terrain.wall'], selection: 'seeded-hash',
      physics: { body: 'static', inset: { left: 4, right: 4, top: 6, bottom: 2 } },
      allowsDecorations: false, tags: ['wall'],
    },
  },
};

const tileData = {
  version: 1,
  resourceId: 'tiles.test-map.ground',
  kind: 'tile-data',
  tileSet: 'tiles.world',
  columns: 2,
  rows: 1,
  cells: [
    { x: 0, y: 0, tileId: 'grass' },
    { x: 1, y: 0, tileId: 'wall' },
  ],
};

test('tile resources preserve stable tile IDs, coordinates, collision, and editor metadata', () => {
  const parsedSet = tooling.parseTileSetResource(tileSet);
  const parsedData = tooling.parseTileMapDataResource(tileData);
  assert.deepEqual(parsedSet.tiles.wall.physics.inset, { left: 4, right: 4, top: 6, bottom: 2 });
  assert.deepEqual(parsedSet.tiles.grass.editor, { color: '#54a36b' });
  assert.deepEqual(parsedData.cells, [
    { x: 0, y: 0, tileId: 'grass' },
    { x: 1, y: 0, tileId: 'wall' },
  ]);
  assert.equal(parsedData.tileSet, 'tiles.world');
  assert.deepEqual({ columns: parsedData.columns, rows: parsedData.rows }, { columns: 2, rows: 1 });
});

test('tile resource validation rejects unknown media, duplicate cells, and malformed collision insets', () => {
  const context = {
    hasAsset: (assetId) => assetId === 'terrain.grass',
    hasResource: (resourceId) => resourceId === 'tiles.world',
    getResourceKind: () => 'tile-set',
  };
  const setMessages = tooling.validateSceneResourceDocument(tileSet, context).map((issue) => issue.message).join('\n');
  assert.match(setMessages, /unknown raw-media asset 'terrain.wall'/);

  const duplicateData = structuredClone(tileData);
  duplicateData.cells.push({ x: 0, y: 0, tileId: 'wall' });
  assert.match(
    tooling.validateSceneResourceDocument(duplicateData, context).map((issue) => issue.message).join('\n'),
    /duplicates cell '0,0'/,
  );

  const outOfBoundsData = structuredClone(tileData);
  outOfBoundsData.cells.push({ x: 2, y: 0, tileId: 'wall' });
  assert.match(
    tooling.validateSceneResourceDocument(outOfBoundsData, context).map((issue) => issue.message).join('\n'),
    /outside its 2x1 bounds/,
  );

  const malformedSet = structuredClone(tileSet);
  malformedSet.tiles.wall.physics.inset.left = -1;
  assert.match(
    tooling.validateSceneResourceDocument(malformedSet).map((issue) => issue.message).join('\n'),
    /invalid 'left' collision inset/,
  );
});

test('TileMapLayer2D exposes external data, collision, depth, seed, and editor-lock properties', () => {
  const descriptor = tooling.createCoreDescriptorRegistry().nodeTypes.get('TileMapLayer2D');
  assert.ok(descriptor);
  assert.deepEqual(
    descriptor.properties.map((property) => property.key),
    ['tileData', 'tileSize', 'seed', 'depth', 'collisionLayer', 'collisionMask', 'collisionEnabled', 'editorLocked'],
  );
  assert.equal(descriptor.properties[0].required, true);
  assert.deepEqual(descriptor.properties[0].value.resourceKinds, ['tile-data']);
});
