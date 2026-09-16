import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { formatSceneStudioRoute, parseSceneStudioRoute, redirectLegacyCharacterStudioRoute, redirectLegacyStudioRoute } = await loadTypescriptModule('src/game/editor/scene-studio/SceneStudioRoute.ts');

test('Scene Studio route round trips scene IDs and preserves unrelated query values', () => {
  assert.deepEqual(parseSceneStudioRoute('?studio=scenes&scene=character.worm-brawler'), { active: true, scene: 'character.worm-brawler' });
  assert.equal(formatSceneStudioRoute({ active: true, scene: 'object.chest' }, '?debug=1'), '?debug=1&studio=scenes&scene=object.chest');
  assert.equal(formatSceneStudioRoute({ active: false }, '?studio=scenes&scene=object.chest&debug=1'), '?debug=1');
  assert.deepEqual(parseSceneStudioRoute('?studio=characters&scene=ignored'), { active: false });
});

test('legacy combat studios redirect to their authored scene contexts', () => {
  assert.equal(redirectLegacyStudioRoute('?studio=weapons&weapon=basic-sword&animation=attack&direction=left&editor=level-1'), '?studio=scenes&editor=level-1&scene=weapon.basic-sword');
  assert.equal(redirectLegacyStudioRoute('?studio=projectiles&projectile=worm-arrow&editor=level-1'), '?studio=scenes&editor=level-1&scene=projectile.worm-arrow');
  assert.equal(redirectLegacyStudioRoute('?studio=weapons&editor=level-1'), '?studio=scenes&editor=level-1');
  assert.equal(redirectLegacyStudioRoute('?studio=animations&weapon=basic-sword'), undefined);
  assert.throws(() => redirectLegacyStudioRoute('?studio=weapons&weapon=../escape'), /SceneId/);
});

test('Scene Studio route rejects malformed stable IDs', () => {
  assert.throws(() => parseSceneStudioRoute('?studio=scenes&scene=../escape'), /SceneId/);
});

test('legacy Character Studio routes redirect to the equivalent authored character scene', () => {
  assert.equal(
    redirectLegacyCharacterStudioRoute('?studio=characters&character=worm-swordsman&editor=level-1'),
    '?studio=scenes&editor=level-1&scene=character.worm-swordsman',
  );
  assert.equal(redirectLegacyCharacterStudioRoute('?studio=characters&editor=level-1'), '?studio=scenes&editor=level-1');
  assert.equal(redirectLegacyCharacterStudioRoute('?studio=animations&character=worm-swordsman'), undefined);
  assert.throws(() => redirectLegacyCharacterStudioRoute('?studio=characters&character=../escape'), /SceneId/);
});
