import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { loadAnimationSampling } from '../../lib/scene-conversion/load-animation-sampling.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));

test('every character scene sorts by the bottom of its collision body, like the old runtime', async () => {
  const sampling = await loadAnimationSampling();
  const charactersRoot = path.join(repositoryRoot, 'src/game/content/characters');
  const characterIds = (await readdir(charactersRoot, { withFileTypes: true })).filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort();
  assert.ok(characterIds.length >= 10);
  for (const characterId of characterIds) {
    const character = JSON.parse(await readFile(path.join(charactersRoot, characterId, 'character.json'), 'utf8'));
    const scene = JSON.parse(await readFile(path.join(repositoryRoot, `src/game/content/scenes/authored/characters/${characterId}.scene.json`), 'utf8'));
    const root = scene.nodes.find((node) => node.id === scene.rootNodeId);
    // Old runtime: resolveWorldDepth(resolveBodyBottom(arcadeBody)).
    const bounds = sampling.resolveEffectiveArcadeBodyBoundsRelativeToAnchor(character.body);
    assert.deepEqual(root.properties.depthAnchor, [character.body.centerOffsetX ?? 0, bounds.maxY], `${characterId} depth anchor`);
    const visuals = scene.nodes.filter((node) => node.type === 'Sprite2D' && node.parentId === root.id);
    assert.ok(visuals.length > 0, `${characterId} has a visual`);
    for (const visual of visuals) assert.equal(visual.properties.depthMode, 'relative', `${characterId} ${visual.name} draws at its body's depth`);
  }
});
