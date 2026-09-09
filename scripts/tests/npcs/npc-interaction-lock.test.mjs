import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { build } from 'esbuild';

// Run the actual actor, body geometry, animation tracks, and wandering policy.
// Only the renderer is replaced; it needs a browser canvas.
const compiled = await build({
  entryPoints: ['src/game/features/npcs/NpcActor.ts'],
  bundle: true,
  write: false,
  platform: 'node',
  format: 'esm',
  plugins: [{
    name: 'npc-renderer-fixture',
    setup(builder) {
      builder.onLoad({ filter: /[/\\]AnimatedVisual\.ts$/ }, () => ({
        contents: `export class AnimatedVisual {
          play(clip) { this.clip = clip; }
          setFlipX() {}
          destroy() {}
        }`,
        loader: 'js',
      }));
    },
  }],
});
const { NpcActor } = await import(`data:text/javascript;base64,${Buffer.from(compiled.outputFiles[0].text).toString('base64')}`);
const root = new URL('../../../', import.meta.url);
const readJson = (path) => JSON.parse(readFileSync(new URL(path, root), 'utf8'));

function createActor(t) {
  t.mock.method(Math, 'random', () => 0.75);
  const anchor = {
    x: 64, y: 64, displayOriginX: 114.5, displayOriginY: 114.5, active: true,
    velocity: { x: 0, y: 0 },
    body: { setSize() {}, setOffset() {} },
    setAlpha() { return this; },
    setCollideWorldBounds() { return this; },
    setData() { return this; },
    setVelocity(x, y) { this.velocity = { x, y }; return this; },
    destroy() { this.active = false; },
  };
  const character = readJson('src/game/content/characters/lili/character.json');
  character.npc.pauseMinMs = 100;
  character.npc.pauseMaxMs = 100;
  const actor = new NpcActor({
    textures: { exists: () => true },
    physics: { add: { image: () => anchor } },
  }, {
    packageValue: { character, visualSet: readJson('src/game/content/characters/lili/visual-set.json') },
    definitionId: 'lili', instanceId: 'fixture-lili', x: 64, y: 64,
    area: { id: 'npc-area-01', npcInstanceId: 'fixture-lili', perimeter: { shape: 'rectangle', x: 0, y: 0, w: 256, h: 256 } },
  });
  t.after(() => actor.destroy());
  return actor;
}

const isMoving = (actor) => Math.hypot(actor.anchor.velocity.x, actor.anchor.velocity.y) > 0;

test('ordinary talk stops an NPC and the final lock release resumes a fresh wander cycle', (t) => {
  const actor = createActor(t);
  actor.update(110);
  assert.ok(isMoving(actor));
  const releaseFirst = actor.acquireInteractionLock();
  const releaseSecond = actor.acquireInteractionLock();
  assert.equal(isMoving(actor), false);
  assert.equal(actor.visual.clip, 'idle');
  releaseFirst();
  releaseFirst();
  actor.update(1000);
  assert.equal(isMoving(actor), false, 'duplicate release must not release another interaction');
  releaseSecond();
  actor.update(50);
  assert.equal(isMoving(actor), false, 'resuming starts with the authored pause');
  actor.update(60);
  assert.ok(isMoving(actor), 'ordinary talk must not permanently set simulation pause');
});

test('talk locks and simulation pause can end in either order without an early resume', (t) => {
  for (const releaseTalkFirst of [true, false]) {
    const actor = createActor(t);
    actor.setPaused(true);
    const release = actor.acquireInteractionLock();
    if (releaseTalkFirst) release();
    else actor.setPaused(false);
    actor.update(1000);
    assert.equal(isMoving(actor), false);
    if (releaseTalkFirst) actor.setPaused(false);
    else release();
    actor.update(110);
    assert.ok(isMoving(actor));
  }
});

test('destroying an NPC with an outstanding talk lock makes late callbacks harmless', (t) => {
  const actor = createActor(t);
  const release = actor.acquireInteractionLock();
  actor.destroy();
  assert.doesNotThrow(() => { release(); release(); actor.update(1000); actor.destroy(); });
  assert.equal(actor.isActive(), false);
});
