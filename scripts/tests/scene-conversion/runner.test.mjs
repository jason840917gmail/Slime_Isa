import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { StableIdMap } from '../../lib/scene-conversion/StableIdMap.mjs';
import { sha256 } from '../../lib/scene-conversion/ConversionReport.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';

async function fixture() {
  const repositoryRoot = await mkdtemp(path.join(os.tmpdir(), 'scene-conversion-source-'));
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'scene-conversion-output-'));
  await writeFile(path.join(repositoryRoot, 'actor.json'), '{"id":"actor","health":5}\n');
  const ledger = { rows: [{ key: 'character:actor', family: 'character', classification: 'convert', writerState: 'legacy', oldSourcePath: 'actor.json', sourceHash: sha256('{"id":"actor","health":5}\n') }] };
  const adapters = { character: { async convert({ units, readSource, stableIds }) { const source = JSON.parse(await readSource(units[0].oldSourcePath)); return [{ unitKey: units[0].key, path: 'actor.scene.json', content: `${JSON.stringify({ version: 1, sceneId: stableIds.resolve('character', source.id), rootNodeId: 'root', nodes: [{ id: 'root', name: 'Actor', type: 'Node', parentId: null, order: 0, properties: {} }], instances: [], subresources: [{ version: 1, resourceId: 'actor.balance', kind: 'theme', values: { health: source.health } }] }, null, 2)}\n`, consumedFieldPaths: ['$.health'], intentionallyRetainedFields: [] }]; } } };
  return { repositoryRoot, outputRoot, ledger, adapters, validateWriteSet: validateSceneWriteSet };
}

test('dry runs are byte-stable and do not write output', async () => {
  const setup = await fixture();
  const runner = new ConversionRunner({ ...setup, stableIds: new StableIdMap() });
  const first = await runner.run({ family: 'character', mode: 'dry-run' });
  const second = await runner.run({ family: 'character', mode: 'dry-run' });
  assert.deepEqual(second.outputs, first.outputs);
  await assert.rejects(() => readFile(path.join(setup.outputRoot, 'actor.scene.json')), /ENOENT/);
});

test('journaled apply installs the exact write set and check detects drift', async () => {
  const setup = await fixture();
  const runner = new ConversionRunner(setup);
  await runner.run({ family: 'character', mode: 'apply' });
  await runner.run({ family: 'character', mode: 'check' });
  await writeFile(path.join(setup.outputRoot, 'actor.scene.json'), 'drift\n');
  await assert.rejects(() => runner.run({ family: 'character', mode: 'check' }), /differs/);
  await assert.rejects(() => runner.run({ family: 'character', mode: 'apply' }), /refusing to overwrite authored content/);
});

test('missing adapters and changed source hashes stop conversion', async () => {
  const setup = await fixture();
  await assert.rejects(() => new ConversionRunner({ ...setup, adapters: {} }).run({ family: 'character' }), /Missing scene conversion adapter/);
  await writeFile(path.join(setup.repositoryRoot, 'actor.json'), '{"id":"actor","health":6}\n');
  await assert.rejects(() => new ConversionRunner(setup).run({ family: 'character' }), /Source hash changed/);
});

test('the runner requires canonical semantic validation before any write', async () => {
  const setup = await fixture();
  const withoutValidation = new ConversionRunner({ ...setup, validateWriteSet: undefined });
  await assert.rejects(() => withoutValidation.run({ family: 'character' }), /requires the canonical write-set validator/);
  setup.adapters.character.convert = async ({ units }) => [{ unitKey: units[0].key, path: 'broken.scene.json', content: '{not json}\n', consumedFieldPaths: [], intentionallyRetainedFields: [] }];
  await assert.rejects(() => new ConversionRunner(setup).run({ family: 'character' }), /malformed JSON/);
});

test('all-family conversion uses dependency order independent of ledger discovery order', async () => {
  const setup = await fixture();
  const animationUnit = { ...setup.ledger.rows[0], key: 'animation:actor', family: 'animation' };
  setup.ledger = { rows: [setup.ledger.rows[0], animationUnit].reverse() };
  const calls = [];
  setup.adapters.animation = {
    async convert({ units, stableIds }) {
      calls.push('animation');
      return [{
        unitKey: units[0].key,
        path: 'actor-animation.scene.json',
        content: `${JSON.stringify({ version: 1, sceneId: stableIds.resolve('animation', 'actor'), rootNodeId: 'root', nodes: [{ id: 'root', name: 'Animation', type: 'Node', parentId: null, order: 0, properties: {} }], instances: [] }, null, 2)}\n`,
        consumedFieldPaths: ['$'], intentionallyRetainedFields: [],
      }];
    },
  };
  const characterConvert = setup.adapters.character.convert;
  setup.adapters.character.convert = async (input) => { calls.push('character'); return characterConvert(input); };
  await new ConversionRunner(setup).run({ family: 'all' });
  assert.deepEqual(calls, ['animation', 'character']);
});

test('unit selection leaves unrelated legacy-owned units with their current writer', async () => {
  const setup = await fixture();
  setup.ledger.rows.push({ ...setup.ledger.rows[0], key: 'character:other' });
  const report = await new ConversionRunner(setup).run({ family: 'character', unitKeys: ['character:actor'] });
  assert.deepEqual(report.units, ['character:actor']);
  await assert.rejects(
    () => new ConversionRunner(setup).run({ family: 'character', unitKeys: ['character:missing'] }),
    /Unknown scene conversion units/,
  );
});
