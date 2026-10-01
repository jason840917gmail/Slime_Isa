import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { loadAnimationSampling } from '../../lib/scene-conversion/load-animation-sampling.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
/**
 * Fatty's blocking body was raised to fit the blob in Scene Studio; it still
 * sorts by its old runtime body bottom, which is where its sprite's feet are.
 */
const SORTS_BY_LEGACY_BODY = new Set(['fatty-one-eye']);

test('every character scene sorts by the bottom of its collision body, like the old runtime', async () => {
  const sampling = await loadAnimationSampling();
  const charactersRoot = path.join(repositoryRoot, 'src/game/content/characters');
  const characterIds = (await readdir(charactersRoot, { withFileTypes: true })).filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort();
  assert.ok(characterIds.length >= 10);
  for (const characterId of characterIds) {
    const character = JSON.parse(await readFile(path.join(charactersRoot, characterId, 'character.json'), 'utf8'));
    const scene = JSON.parse(await readFile(path.join(repositoryRoot, `src/game/content/scenes/authored/characters/${characterId}.scene.json`), 'utf8'));
    const root = scene.nodes.find((node) => node.id === scene.rootNodeId);
    // Old runtime: resolveWorldDepth(resolveBodyBottom(arcadeBody)). The scene's
    // body is its single enabled CollisionShape2D, which Scene Studio may reshape.
    const shapes = scene.nodes.filter((node) => node.type === 'CollisionShape2D' && node.parentId === root.id && !node.properties.disabled);
    assert.equal(shapes.length, 1, `${characterId} has one blocking shape`);
    const [x, y] = shapes[0].properties.position ?? [0, 0];
    const shape = scene.subresources.find((resource) => resource.resourceId === shapes[0].properties.shape.resourceId).value;
    const body = SORTS_BY_LEGACY_BODY.has(characterId) ? character.body : { ...shape, centerOffsetX: x, centerOffsetY: y };
    const bounds = sampling.resolveEffectiveArcadeBodyBoundsRelativeToAnchor(body);
    assert.deepEqual(root.properties.depthAnchor, [body.centerOffsetX ?? 0, bounds.maxY], `${characterId} depth anchor`);
    const visuals = scene.nodes.filter((node) => node.type === 'Sprite2D' && node.parentId === root.id);
    assert.ok(visuals.length > 0, `${characterId} has a visual`);
    for (const visual of visuals) assert.equal(visual.properties.depthMode, 'relative', `${characterId} ${visual.name} draws at its body's depth`);
  }
});
