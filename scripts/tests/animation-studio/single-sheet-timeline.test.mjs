import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let timelineModule;
let stateModule;
let compatibilityModule;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  [timelineModule, stateModule, compatibilityModule] = await Promise.all([
    loadTypeScriptModule('src/game/editor/CharacterTimeline.ts'),
    loadTypeScriptModule('src/game/editor/CharacterDocumentState.ts'),
    loadTypeScriptModule('src/game/editor/CharacterSourceSheetCompatibility.ts'),
  ]);
});

function packageFixture() {
  return {
    character: {
      characterId: 'npc.test', displayName: 'Test NPC', kind: 'npc', visualSetId: 'visual.npc.test',
      body: { width: 16, height: 16, centerOffsetX: 0, centerOffsetY: 0 }, hitboxes: {},
      animationTracks: { idle: { events: [{ eventId: 'npc.wave', at: 3 }], hitboxSpans: [] } }, npc: { interactionId: 'test' },
    },
    visualSet: {
      version: 1, visualSetId: 'visual.npc.test', assetId: 'sheet.test', defaults: { origin: [0, 0], scale: [1, 1], sourceOffset: [0, 0] },
      clips: { idle: { frames: [1, 2, 3], keyframeTimes: [0, 2, 5], durationSeconds: 2, framesPerSecond: 4, loop: true } },
    },
  };
}

test('duplicate inserts an adjacent occurrence with the selected hold and shifts metadata', () => {
  const pkg = packageFixture();
  pkg.character.animationTracks.idle.hitboxSpans = [{ hitboxId: 'talk', from: 1, through: 5 }];
  const result = timelineModule.duplicateTimelineFrame(pkg.character, pkg.visualSet, 'idle', 1);
  assert.equal(result.insertedIndex, 2);
  assert.deepEqual(pkg.visualSet.clips.idle.frames, [1, 2, 2, 3]);
  assert.deepEqual(pkg.visualSet.clips.idle.keyframeTimes, [0, 2, 5, 8]);
  assert.equal(pkg.visualSet.clips.idle.durationSeconds, 2.75);
  assert.deepEqual(pkg.character.animationTracks.idle.events, [{ eventId: 'npc.wave', at: 3 }]);
  assert.deepEqual(pkg.character.animationTracks.idle.hitboxSpans, [{ hitboxId: 'talk', from: 1, through: 4 }, { hitboxId: 'talk', from: 8, through: 8 }]);
});

test('source-sheet compatibility reports clip occurrences and unused overrides', () => {
  const pkg = packageFixture();
  pkg.visualSet.frameVisuals = { '2': {}, '3': {}, nope: {} };
  const issues = compatibilityModule.collectCharacterSourceSheetIssues(pkg.visualSet, 3);
  assert.deepEqual(issues.map((issue) => issue.path), ['visualSet.clips.idle.frames[2]', 'visualSet.frameVisuals.3', 'visualSet.frameVisuals.nope']);
});

test('character state keeps frame selection through duplicate undo and redo', () => {
  const state = new stateModule.CharacterDocumentState(packageFixture(), 'r1');
  state.selectTimelineIndex(1);
  assert.equal(state.duplicateSelectedFrame(), true);
  assert.equal(state.value.selectedTimelineIndex, 2);
  state.undo();
  assert.equal(state.value.selectedTimelineIndex, 1);
  state.redo();
  assert.equal(state.value.selectedTimelineIndex, 2);
});
