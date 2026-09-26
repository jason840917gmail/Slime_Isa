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

test('Scene Studio route selects a resource without retaining a stale scene selection', () => {
  assert.deepEqual(parseSceneStudioRoute('?studio=scenes&resource=character.player.slime.animations'), { active: true, resource: 'character.player.slime.animations' });
  assert.equal(formatSceneStudioRoute({ active: true, resource: 'character.player.slime.animations' }, '?studio=scenes&scene=world.level-1'), '?studio=scenes&resource=character.player.slime.animations');
  assert.throws(() => parseSceneStudioRoute('?studio=scenes&resource=../escape'), /ResourceId/);
});

test('legacy combat studios redirect to their authored scene contexts', () => {
  assert.equal(redirectLegacyStudioRoute('?studio=weapons&weapon=basic-sword&animation=attack&direction=left&editor=level-1'), '?studio=scenes&scene=weapon.basic-sword');
  assert.equal(redirectLegacyStudioRoute('?studio=projectiles&projectile=worm-arrow&editor=level-1'), '?studio=scenes&scene=projectile.worm-arrow');
  assert.equal(redirectLegacyStudioRoute('?studio=weapons&editor=level-1'), '?studio=scenes');
  assert.equal(redirectLegacyStudioRoute('?studio=animations&weapon=basic-sword'), '?studio=scenes&scene=weapon.basic-sword');
  assert.equal(redirectLegacyStudioRoute('?studio=animations&animation=object.tree.autumn.idle'), '?studio=scenes');
  assert.throws(() => redirectLegacyStudioRoute('?studio=weapons&weapon=../escape'), /SceneId/);
});

test('legacy Map Studio routes redirect to the authored world scene without retaining a second editor mode', () => {
  assert.equal(redirectLegacyStudioRoute('?editor=level-1'), '?studio=scenes&scene=world.level-1');
  assert.equal(redirectLegacyStudioRoute('?editor=gloop-forest&debug=1'), '?debug=1&studio=scenes&scene=world.gloop-forest');
  assert.equal(redirectLegacyStudioRoute('?studio=scenes&editor=icege'), '?studio=scenes&scene=world.icege');
  assert.equal(redirectLegacyStudioRoute('?studio=scenes&scene=weapon.basic-sword&editor=level-1'), '?studio=scenes&scene=weapon.basic-sword');
  assert.throws(() => redirectLegacyStudioRoute('?editor=../escape'), /SceneId/);
});

test('Scene Studio route rejects malformed stable IDs', () => {
  assert.throws(() => parseSceneStudioRoute('?studio=scenes&scene=../escape'), /SceneId/);
});

test('legacy Character Studio routes redirect to the equivalent authored character scene', () => {
  assert.equal(
    redirectLegacyCharacterStudioRoute('?studio=characters&character=worm-swordsman&editor=level-1'),
    '?studio=scenes&scene=character.worm-swordsman',
  );
  assert.equal(redirectLegacyCharacterStudioRoute('?studio=characters&editor=level-1'), '?studio=scenes');
  assert.equal(redirectLegacyCharacterStudioRoute('?studio=animations&character=worm-swordsman'), undefined);
  assert.throws(() => redirectLegacyCharacterStudioRoute('?studio=characters&character=../escape'), /SceneId/);
});
