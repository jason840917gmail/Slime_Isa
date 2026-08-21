import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let treeModule;

before(async () => {
  const result = await build({
    absWorkingDir: repositoryRoot,
    entryPoints: ['src/game/editor/StudioLibraryTree.ts'],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  treeModule = await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
});

function animation(animationId, folderPath, displayName) {
  return {
    packagePath: `${folderPath}/animation.json`,
    folderPath,
    animationId,
    displayName,
    description: `${displayName} description`,
    revision: animationId,
    version: 1,
    animation: { version: 2, durationSeconds: 0.5, framesPerSecond: 8, loop: false, loopMode: 'wrap', layers: [] },
  };
}

test('animation packages render as a real nested explorer instead of repeated flat paths', () => {
  const html = treeModule.renderStudioLibraryTree({
    weapons: [{ weaponId: 'basic-spear', displayName: 'Basic Spear', description: 'Spear', category: 'melee', version: 2 }],
    animations: [
      animation('weapon.basic-spear.attack.down', 'weapons/basic-spear/attack-down', 'Basic Spear down attack'),
      animation('weapon.basic-spear.attack.right', 'weapons/basic-spear/attack-right', 'Basic Spear right attack'),
    ],
    search: '',
    expandedFolders: new Set(['weapons', 'animations', 'animations/weapons', 'animations/weapons/basic-spear']),
    selectedAnimationId: 'weapon.basic-spear.attack.down',
    footerHtml: '',
  });

  assert.equal((html.match(/data-library-folder="animations\/weapons"/g) ?? []).length, 1);
  assert.equal((html.match(/data-library-folder="animations\/weapons\/basic-spear"/g) ?? []).length, 1);
  assert.doesNotMatch(html, />weapons\/basic-spear\/attack-/);
  assert.match(html, />attack-down</);
  assert.match(html, />attack-right</);
  assert.match(html, /studio-tree-folder-icon/);
  assert.match(html, /studio-tree-file-icon--animation/);
  assert.match(html, /data-animation-id="weapon\.basic-spear\.attack\.down"/);
  assert.doesNotMatch(html, /studio=animations/);
});

test('search keeps matching leaves in their folder hierarchy', () => {
  const html = treeModule.renderStudioLibraryTree({
    weapons: [],
    animations: [
      animation('weapon.basic-spear.attack.down', 'weapons/basic-spear/attack-down', 'Basic Spear down attack'),
      animation('object.tree.idle', 'objects/tree/idle', 'Snow pine idle'),
    ],
    search: 'snow pine',
    expandedFolders: new Set(),
    footerHtml: '',
  });

  assert.match(html, />objects</);
  assert.match(html, />tree</);
  assert.match(html, />idle</);
  assert.doesNotMatch(html, />basic-spear</);
});
