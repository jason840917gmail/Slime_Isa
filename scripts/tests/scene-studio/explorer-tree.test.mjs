import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { buildExplorerTree, explorerFolderKeysFor, familyFileName, renderExplorerTree } = await loadTypescriptModule('src/game/editor/scene-studio/ExplorerTree.ts');

const scene = (relativePath) => ({ kind: 'scene', id: `scene.${relativePath}`, relativePath });
const resource = (relativePath) => ({ kind: 'resource', id: `resource.${relativePath}`, relativePath });

const catalog = [
  scene('objects/tree-world-solid--02.scene.json'),
  scene('objects/tree-world-solid--01.scene.json'),
  scene('objects/house-world-solid--01.scene.json'),
  scene('objects/house-world-solid--02.scene.json'),
  scene('objects/house-world-solid.scene.json'),
  scene('objects/chest-wooden.scene.json'),
  scene('objects/resource-stone-node--01.scene.json'),
  scene('characters/lili.scene.json'),
  resource('resources/tiles/ground.tile-set.resource.json'),
  resource('resources/animations/slime.animation.resource.json'),
  scene('root-level.scene.json'),
];

const shape = (folder) => ({
  key: folder.key,
  family: folder.family,
  total: folder.total,
  folders: folder.folders.map(shape),
  items: folder.items.map((item) => item.relativePath),
});

test('explorer groups documents by folder and variant families', () => {
  const tree = buildExplorerTree(catalog);
  assert.equal(tree.total, catalog.length);
  assert.deepEqual(shape(tree), {
    key: '', family: false, total: 11, items: ['root-level.scene.json'],
    folders: [
      { key: 'characters', family: false, total: 1, folders: [], items: ['characters/lili.scene.json'] },
      {
        key: 'objects', family: false, total: 7,
        folders: [
          // The base file named exactly like the family joins it and leads the variants.
          { key: 'objects/house-world-solid', family: true, total: 3, folders: [], items: ['objects/house-world-solid.scene.json', 'objects/house-world-solid--01.scene.json', 'objects/house-world-solid--02.scene.json'] },
          { key: 'objects/tree-world-solid', family: true, total: 2, folders: [], items: ['objects/tree-world-solid--01.scene.json', 'objects/tree-world-solid--02.scene.json'] },
        ],
        // A single variant stays a plain file instead of a one-item group.
        items: ['objects/chest-wooden.scene.json', 'objects/resource-stone-node--01.scene.json'],
      },
      {
        key: 'resources', family: false, total: 2, items: [],
        folders: [
          { key: 'resources/animations', family: false, total: 1, folders: [], items: ['resources/animations/slime.animation.resource.json'] },
          { key: 'resources/tiles', family: false, total: 1, folders: [], items: ['resources/tiles/ground.tile-set.resource.json'] },
        ],
      },
    ],
  });
});

test('explorer reveals every folder containing a document', () => {
  const tree = buildExplorerTree(catalog);
  assert.deepEqual(explorerFolderKeysFor(tree, 'objects/house-world-solid--02.scene.json'), ['objects', 'objects/house-world-solid']);
  assert.deepEqual(explorerFolderKeysFor(tree, 'resources/tiles/ground.tile-set.resource.json'), ['resources', 'resources/tiles']);
  assert.deepEqual(explorerFolderKeysFor(tree, 'root-level.scene.json'), []);
  assert.deepEqual(explorerFolderKeysFor(tree, 'missing.scene.json'), []);
});

test('explorer renders collapsible folders with open state, counts, and escaped rows', () => {
  const tree = buildExplorerTree([...catalog, scene('characters/<odd>.scene.json')]);
  const escape = (value) => String(value).replace(/[&<>"']/g, (character) => `&#${character.charCodeAt(0)};`);
  const html = renderExplorerTree(tree, {
    isOpen: (key) => key === 'objects',
    isCurrent: (item) => item.relativePath === 'characters/lili.scene.json',
    escape,
  });
  assert.match(html, /data-explorer-folder="objects" data-explorer-total="7"><button[^>]*aria-expanded="true"/);
  assert.match(html, /class="scene-explorer-folder is-family" data-explorer-folder="objects\/house-world-solid"[^>]*><button[^>]*aria-expanded="false"/);
  assert.match(html, /data-scene-id="scene\.characters\/lili\.scene\.json"[^>]*class="scene-explorer-item is-current"/);
  assert.match(html, /data-resource-id="resource\.resources\/tiles\/ground\.tile-set\.resource\.json"/);
  assert.ok(!html.includes('<odd>'), 'document names are escaped');
  // Rows show file names; family members show only their variant part.
  assert.match(html, /data-scene-id="scene\.characters\/lili\.scene\.json"[^>]*><span>◫<\/span><strong>lili<\/strong>/);
  assert.match(html, /data-scene-id="scene\.objects\/house-world-solid--01\.scene\.json"[^>]*><span>◫<\/span><strong>01<\/strong>/);
  assert.match(html, /data-scene-id="scene\.objects\/house-world-solid\.scene\.json"[^>]*><span>◫<\/span><strong>house-world-solid<\/strong>/);
});

test('explorer rows are draggable and folders name the folder a drop moves into', () => {
  const html = renderExplorerTree(buildExplorerTree(catalog), { isOpen: () => true, isCurrent: () => false, escape: String });
  assert.match(html, /<button type="button" draggable="true" data-scene-id="scene\.characters\/lili\.scene\.json"/);
  assert.match(html, /<button type="button" draggable="true" data-resource-id="resource\.resources\/tiles\/ground\.tile-set\.resource\.json"/);
  assert.match(html, /data-explorer-folder-toggle="resources\/tiles" data-explorer-drop="resources\/tiles"/);
  // Family groups are not folders on disk: dropping on one targets the folder holding the family.
  assert.match(html, /data-explorer-folder-toggle="objects\/house-world-solid" data-explorer-drop="objects" data-explorer-family="house-world-solid"/);
  assert.doesNotMatch(html, /data-explorer-folder-toggle="objects" data-explorer-drop="objects" data-explorer-family/);
});

test('a file dropped on a family group is renamed into that family', () => {
  assert.equal(familyFileName('objects/house-mushroom.scene.json', 'house-world-solid'), 'house-world-solid--house-mushroom.scene.json');
  assert.equal(familyFileName('objects/houses/house-world-solid--02.scene.json', 'house-world-solid'), 'house-world-solid--02.scene.json');
  assert.equal(familyFileName('objects/house-world-solid.scene.json', 'house-world-solid'), 'house-world-solid.scene.json');
  assert.equal(familyFileName('resources/tiles/ground.tile-set.resource.json', 'tiles'), 'tiles--ground.tile-set.resource.json');
  // the renamed file joins the group in the tree
  const tree = buildExplorerTree([...catalog, scene('objects/house-world-solid--house-mushroom.scene.json')]);
  const objects = tree.folders.find((folder) => folder.key === 'objects');
  const family = objects.folders.find((folder) => folder.key === 'objects/house-world-solid');
  assert.ok(family.items.some((item) => item.relativePath === 'objects/house-world-solid--house-mushroom.scene.json'));
});
