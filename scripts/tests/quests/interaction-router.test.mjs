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
  active = true;

  setOrigin() { return this; }
  setScrollFactor() { return this; }
  setDepth() { return this; }
  setVisible(value) { this.visible = value; return this; }
  setText(value) { this.text = value; return this; }
  setPosition() { return this; }
  destroy() { this.destroyed = true; }
}

/** Minimal chainable stand-in for the badge graphics and container. */
class FakeObject {
  x = 0;
  y = 0;
  visible = false;
  active = true;
  constructor(children = []) { this.children = children; }
  fillStyle() { return this; }
  fillRoundedRect() { return this; }
  lineStyle() { return this; }
  strokeRoundedRect() { return this; }
  setOrigin() { return this; }
  setDepth() { return this; }
  setScale() { return this; }
  setAlpha() { return this; }
  setVisible(value) { this.visible = value; return this; }
  setPosition(x, y) { this.x = x; this.y = y; return this; }
  destroy() { this.active = false; }
}

function harness() {
  const prompt = new FakeText();
  let texts = 0;
  let badge;
  const scene = {
    cameras: { main: { width: 1280, height: 720 } },
    add: {
      // The first text is the shared prompt; later ones belong to the key badge.
      text: () => (texts++ === 0 ? prompt : new FakeObject()),
      graphics: () => new FakeObject(),
      container: (_x, _y, children) => (badge = new FakeObject(children)),
    },
    tweens: { add: () => ({ remove: () => {} }) },
    time: { now: 0 },
    scale: { on: () => {}, off: () => {} },
    events: { once: () => {} },
  };
  return { router: new InteractionRouter(scene), prompt, badge: () => badge };
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

test('a candidate anchor shows the key badge above its target and a secondary action runs on G', () => {
  const { router, prompt, badge } = harness();
  const executed = [];
  router.register('bench', {
    getCandidate: () => ({
      id: 'bench:one', prompt: '[F] Use workbench', priority: 50,
      anchor: () => ({ x: 320, y: 200 }),
      secondary: { prompt: '[G] Pick up', execute: () => { executed.push('pick-up'); return true; } },
      execute: () => { executed.push('use'); return true; },
    }),
  });

  router.update();
  assert.match(prompt.text, /\[F\] Use workbench.*\[G\] Pick up/);
  assert.equal(badge().visible, true);
  assert.equal(badge().x, 320);
  assert.equal(router.handleSecondary(), true);
  assert.deepEqual(executed, ['pick-up']);

  router.setSuppressed(true);
  assert.equal(badge().visible, false);
  assert.equal(prompt.visible, false);
  assert.equal(router.hasCandidate(), false);
  router.destroy();
});

test('WorldScene delegates authored interactions only through the shared router', () => {
  const source = fs.readFileSync(path.join(process.cwd(), 'src/game/scenes/WorldScene.ts'), 'utf8');
  const methodStart = source.indexOf('private handleActionInput');
  const methodEnd = source.indexOf('private updateMovement', methodStart);
  const method = source.slice(methodStart, methodEnd);
  const candidateCheck = method.indexOf('this.interactionRouter?.hasCandidate()');
  const routerCall = method.indexOf('this.interactionRouter.handleInteract()');
  assert.ok(candidateCheck >= 0 && routerCall > candidateCheck);
  assert.doesNotMatch(method, /houseSystem|tryOpenShopNearby|spawnFriend/);
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
