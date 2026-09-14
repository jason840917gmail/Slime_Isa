import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { formatSceneStudioRoute, parseSceneStudioRoute } = await loadTypescriptModule('src/game/editor/scene-studio/SceneStudioRoute.ts');

test('Scene Studio route round trips scene IDs and preserves unrelated query values', () => {
  assert.deepEqual(parseSceneStudioRoute('?studio=scenes&scene=character.worm-brawler'), { active: true, scene: 'character.worm-brawler' });
  assert.equal(formatSceneStudioRoute({ active: true, scene: 'object.chest' }, '?debug=1'), '?debug=1&studio=scenes&scene=object.chest');
  assert.equal(formatSceneStudioRoute({ active: false }, '?studio=scenes&scene=object.chest&debug=1'), '?debug=1');
  assert.deepEqual(parseSceneStudioRoute('?studio=characters&scene=ignored'), { active: false });
});

test('Scene Studio route rejects malformed stable IDs', () => {
  assert.throws(() => parseSceneStudioRoute('?studio=scenes&scene=../escape'), /SceneId/);
});
