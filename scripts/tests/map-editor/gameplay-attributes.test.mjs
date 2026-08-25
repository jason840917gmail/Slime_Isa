import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  resolve: {
    alias: {
      'virtual-character-content': path.join(contentRoot, 'characters/virtual-character-content.ts'),
      'virtual-projectile-content': path.join(contentRoot, 'projectiles/virtual-projectile-content.ts'),
      'virtual-weapon-content': path.join(contentRoot, 'weapons/virtual-weapon-content.ts'),
      'virtual-effect-content': path.join(contentRoot, 'effects/virtual-effect-content.ts'),
      'virtual-animation-content': path.join(contentRoot, 'animations/virtual-animation-content.ts'),
    },
  },
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false },
});

const { GameplayAttributeEditorState } = await vite.ssrLoadModule('/src/game/editor/GameplayAttributeEditorState.ts');
const { MapEditorState } = await vite.ssrLoadModule('/src/game/editor/MapEditorState.ts');
const { getObjectVisualChoice } = await vite.ssrLoadModule('/src/game/content/objects/ObjectCatalog.ts');
const { validateObjectInitialState } = await vite.ssrLoadModule('/src/game/content/objects/ObjectInitialState.ts');
const { objectGroup, objectChoiceMatchesQuery } = await vite.ssrLoadModule('/src/game/editor/MapEditorPanel.ts');
const mapFixture = (await vite.ssrLoadModule('/src/game/content/maps/test-rectangle.map.json')).default;

test.after(async () => vite.close());

test('gameplay drafts remain independent and survive object selection', () => {
  const state = new GameplayAttributeEditorState();
  state.select('resource.stone-node');
  state.updateDraft({ health: 21 });
  state.select('collectible.wood-pile');
  state.updateDraft({ quantity: 7 });
  state.select('resource.stone-node');
  assert.equal(state.value.draft.health, 21);
  assert.equal(state.value.dirty, true);
  assert.equal(state.value.hasDirtyDrafts, true);
  state.resetChanges();
  assert.equal(state.value.dirty, false);
  assert.equal(state.value.hasDirtyDrafts, true);
});

test('instance override validation and granular default removal are undoable', () => {
  const cleanFixture = structuredClone(mapFixture);
  const editor = new MapEditorState(cleanFixture, 'grass', 'resource.stone-node', 'stone-node');
  assert.equal(editor.updateObjectInitialState(cleanFixture.objects[0].instanceId, { health: 999 }), false);
  assert.equal(editor.updateObjectInitialState(cleanFixture.objects[0].instanceId, { health: 12 }), true);

  const legacyFixture = structuredClone(mapFixture);
  legacyFixture.objects[0].initialState.questFlag = true;
  const legacyEditor = new MapEditorState(legacyFixture, 'grass', 'resource.stone-node', 'stone-node');
  assert.equal(legacyEditor.clearObjectInitialStateKeys(legacyFixture.objects[0].instanceId, ['health']), true);
  assert.deepEqual(legacyEditor.value.map.objects[0].initialState, { questFlag: true });
  legacyEditor.undo();
  assert.equal(legacyEditor.value.map.objects[0].initialState.health, 30);
});

test('map dimensions can be resized without breaking terrain rows', () => {
  const editor = new MapEditorState(structuredClone(mapFixture), 'grass', 'resource.stone-node', 'stone-node');
  assert.equal(editor.updateMapDimensions(10, 6, 32), true);
  assert.deepEqual(editor.value.map.size, { columns: 10, rows: 6 });
  assert.equal(editor.value.map.tileSize, 32);
  assert.equal(editor.value.map.layers[0].rows.length, 6);
  assert.equal(editor.value.map.layers[0].rows.every((row) => row.length === 10), true);
  assert.deepEqual(editor.value.map.objects[0], {
    ...mapFixture.objects[0],
    x: 144,
    y: 96,
  });
  editor.undo();
  assert.deepEqual(editor.value.map.size, mapFixture.size);
  assert.equal(editor.value.map.tileSize, mapFixture.tileSize);
});

test('palette grouping and search include authored gameplay values', () => {
  const wood = getObjectVisualChoice('collectible.wood-pile', 'wood-pile');
  const smallWood = getObjectVisualChoice('collectible.small-wood-pile', 'small-wood-pile');
  const smallStone = getObjectVisualChoice('collectible.small-stone-pile', 'small-stone-pile');
  const iron = getObjectVisualChoice('collectible.iron-ore-pile', 'iron-ore-pile');
  const charcoal = getObjectVisualChoice('collectible.charcoal-pile', 'charcoal-pile');
  const stoneNode = getObjectVisualChoice('resource.stone-node', 'stone-node');
  assert.equal(objectGroup(wood.objectId), 'Collectibles');
  assert.equal(objectGroup(smallWood.objectId), 'Collectibles');
  assert.equal(objectGroup(smallStone.objectId), 'Collectibles');
  assert.equal(objectGroup(iron.objectId), 'Collectibles');
  assert.equal(objectGroup(charcoal.objectId), 'Collectibles');
  assert.equal(objectGroup(stoneNode.objectId), 'Resource Nodes');
  assert.equal(objectChoiceMatchesQuery(wood, 'wood'), true);
  assert.equal(objectChoiceMatchesQuery(wood, '10'), true);
  assert.equal(objectChoiceMatchesQuery(smallWood, 'small wood'), true);
  assert.equal(objectChoiceMatchesQuery(smallStone, 'small stone'), true);
  assert.equal(objectChoiceMatchesQuery(iron, 'iron-ore'), true);
  assert.equal(objectChoiceMatchesQuery(charcoal, 'fuel'), true);
  assert.equal(objectChoiceMatchesQuery(stoneNode, '40'), true);
});

test('archetype-aware map override validation rejects foreign and invalid fields', () => {
  assert.deepEqual(validateObjectInitialState('collectible.wood-pile', { quantity: 6, remaining: 4 }), []);
  assert.match(validateObjectInitialState('collectible.wood-pile', { itemId: 'stone' })[0], /not supported/);
  assert.match(validateObjectInitialState('resource.stone-node', { health: 999 })[0], /0 through/);
  assert.match(validateObjectInitialState('resource.stone-node', {
    dropObjectId: 'collectible.wood-pile', dropVisualId: 'stone-pile', dropPieces: 2,
  })[0], /does not belong/);
});
