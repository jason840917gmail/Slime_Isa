import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false },
});
const { InteractionRouter } = await vite.ssrLoadModule('/src/game/features/interaction/InteractionRouter.ts');
test.after(async () => vite.close());

class FakeText {
  text = '';
  visible = false;
  destroyed = false;

  setOrigin() { return this; }
  setScrollFactor() { return this; }
  setDepth() { return this; }
  setVisible(value) { this.visible = value; return this; }
  setText(value) { this.text = value; return this; }
  setPosition() { return this; }
  destroy() { this.destroyed = true; }
}

function harness() {
  const prompt = new FakeText();
  const scene = {
    cameras: { main: { width: 1280, height: 720 } },
    add: { text: () => prompt },
    scale: { on: () => {}, off: () => {} },
    events: { once: () => {} },
  };
  return { router: new InteractionRouter(scene), prompt };
}

test('the router displays and executes only the highest-priority candidate', () => {
  const { router, prompt } = harness();
  const executed = [];
  router.register('low', {
    getCandidate: () => ({ id: 'low:one', prompt: 'Low', priority: 10, execute: () => { executed.push('low'); return true; } }),
  });
  const unregisterHigh = router.register('high', {
    getCandidate: () => ({ id: 'high:one', prompt: 'High', priority: 20, execute: () => { executed.push('high'); return true; } }),
  });

  router.update();
  assert.equal(prompt.text, 'High');
  assert.equal(prompt.visible, true);
  assert.equal(router.handleInteract(), true);
  assert.deepEqual(executed, ['high']);

  unregisterHigh();
  router.update();
  assert.equal(prompt.text, 'Low');
  router.handleInteract();
  assert.deepEqual(executed, ['high', 'low']);
  router.destroy();
});

test('WorldScene executes the owner of the shared prompt before house fallback', () => {
  const source = fs.readFileSync(path.join(process.cwd(), 'src/game/scenes/WorldScene.ts'), 'utf8');
  const methodStart = source.indexOf('private handleActionInput');
  const methodEnd = source.indexOf('private updateMovement', methodStart);
  const method = source.slice(methodStart, methodEnd);
  const candidateCheck = method.indexOf('this.interactionRouter?.hasCandidate()');
  const routerCall = method.indexOf('this.interactionRouter.handleInteract()');
  const houseCall = method.indexOf('this.houseSystem.handleInteract()');
  assert.ok(candidateCheck >= 0 && routerCall > candidateCheck && houseCall > routerCall);
});

test('quest UI keeps failed commands visible and exposes every retry route', () => {
  const read = (relativePath) => fs.readFileSync(path.join(process.cwd(), relativePath), 'utf8');
  const modal = read('src/game/ui/QuestOfferModal.ts');
  const journal = read('src/game/ui/QuestJournal.ts');
  const npcController = read('src/game/features/interaction/QuestNpcController.ts');

  assert.match(modal, /if \(!result\.ok\)[\s\S]*this\.showError\(result\.reason\)[\s\S]*return/);
  assert.match(modal, /catch \(error\)[\s\S]*this\.showError/);
  assert.match(journal, /window\.confirm/);
  assert.match(journal, /retryFailed/);
  assert.match(journal, /retryAbandonedAutomatic/);
  assert.match(npcController, /reoffersForNpc/);
  assert.match(npcController, /questService\.reoffer/);
});

test('save installation defers quest activation until presentation listeners are ready', () => {
  const source = fs.readFileSync(path.join(process.cwd(), 'src/game/core/SaveSystem.ts'), 'utf8');
  const installStart = source.indexOf('install(data: GameSaveData)');
  const installEnd = source.indexOf('hasInstalledRun()', installStart);
  const install = source.slice(installStart, installEnd);
  assert.match(install, /questTracker\.load/);
  assert.match(install, /questTracker\.restoreKnownFacts/);
  assert.doesNotMatch(install, /questTracker\.evaluatePrerequisites/);
});
