import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const result = await build({
  absWorkingDir: root,
  entryPoints: ['src/game/features/bosses/FattyOneEyeBehavior.ts'],
  bundle: true,
  format: 'esm',
  platform: 'node',
  write: false,
});
const behavior = await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
const geometryResult = await build({
  absWorkingDir: root,
  entryPoints: ['src/game/features/characters/characterHitboxGeometry.ts'],
  bundle: true,
  format: 'esm',
  platform: 'node',
  write: false,
});
const geometry = await import(`data:text/javascript;base64,${Buffer.from(geometryResult.outputFiles[0].text).toString('base64')}`);

test('contact hop accepts only chase requests at or after the start-time cooldown', () => {
  const base = { alive: true, destroyed: false, phase: 'chase', time: 1000, nextContactHopAt: 1000 };
  assert.equal(behavior.canRequestContactHop(base), true);
  assert.equal(behavior.canRequestContactHop({ ...base, time: 999 }), false);
  assert.equal(behavior.canRequestContactHop({ ...base, alive: false }), false);
  assert.equal(behavior.canRequestContactHop({ ...base, destroyed: true }), false);
  for (const phase of ['return-to-center', 'contact-hop', 'small-hop', 'airborne', 'landing', 'recovery', 'dead']) {
    assert.equal(behavior.canRequestContactHop({ ...base, phase }), false);
  }
});

test('300ms progress is normalized and produces a rise-and-fall visual', () => {
  assert.equal(behavior.contactHopProgress(10, 10, 300), 0);
  assert.equal(behavior.contactHopProgress(160, 10, 300), 0.5);
  assert.equal(behavior.contactHopProgress(310, 10, 300), 1);
  assert.equal(behavior.contactHopVisualHeight(0), 0);
  assert.equal(behavior.contactHopVisualHeight(1), 0);
  assert.equal(behavior.contactHopVisualHeight(0.5), 48);
});

test('landing radius is inclusive and dodge/inactive player reject the one landing hit', () => {
  const center = { x: 10, y: 20 };
  assert.equal(behavior.landingRadiusContains(center, { x: 74, y: 20 }, 64), true);
  assert.equal(behavior.landingRadiusContains(center, { x: 74.001, y: 20 }, 64), false);
  assert.equal(behavior.shouldApplyContactHopLandingHit({ center, player: { x: 74, y: 20, active: true }, radius: 64, dodging: false }), true);
  assert.equal(behavior.shouldApplyContactHopLandingHit({ center, player: { x: 74, y: 20, active: true }, radius: 64, dodging: true }), false);
  assert.equal(behavior.shouldApplyContactHopLandingHit({ center, player: { x: 10, y: 20, active: false }, radius: 64, dodging: false }), false);
});

test('contact-hop completion preserves an overdue large-special deadline', () => {
  assert.deepEqual(behavior.contactHopCompletion(5000), { phase: 'chase', nextLeapAt: 5000 });
});

test('arena return helpers detect an escaped boss and target the authored center', () => {
  const circle = { shape: 'circle', x: 100, y: 80, radius: 20 };
  assert.deepEqual(behavior.bossArenaCenter(circle), { x: 100, y: 80 });
  assert.equal(behavior.bossAnchorOutsideArena(circle, { x: 120, y: 80 }), false);
  assert.equal(behavior.bossAnchorOutsideArena(circle, { x: 121, y: 80 }), true);
  const rectangle = { shape: 'rectangle', x: 10, y: 20, w: 80, h: 40 };
  assert.deepEqual(behavior.bossArenaCenter(rectangle), { x: 50, y: 40 });
  assert.equal(behavior.bossAnchorOutsideArena(rectangle, { x: 90, y: 60 }), false);
  assert.equal(behavior.bossAnchorOutsideArena(rectangle, { x: 91, y: 60 }), true);
});

test('an outside player forces return and re-entry resumes pursuit on the inclusive boundary', () => {
  const circle = { shape: 'circle', x: 100, y: 80, radius: 20 };
  assert.equal(behavior.shouldBossReturnToArenaCenter(circle, { x: 130, y: 80 }), true);
  assert.equal(behavior.shouldBossReturnToArenaCenter(circle, { x: 110, y: 80 }), false);
  assert.equal(behavior.shouldBossReturnToArenaCenter(circle, { x: 120, y: 80 }), false);
  assert.equal(behavior.canBossBeginAttack(circle, { x: 130, y: 80 }), false);
  assert.equal(behavior.canBossBeginAttack(circle, { x: 120, y: 80 }), true);
  assert.equal(behavior.shouldResumePursuitFromReturn(circle, { x: 120, y: 80 }), true);
  assert.equal(behavior.shouldResumePursuitFromReturn(circle, { x: 120.01, y: 80 }), false);
});

test('contact hop is a Character Studio boss animation with an authored landing hit layer', async () => {
  const { readFile } = await import('node:fs/promises');
  const character = JSON.parse(await readFile(new URL('../../../src/game/content/characters/fatty-one-eye/character.json', import.meta.url), 'utf8'));
  const visualSet = JSON.parse(await readFile(new URL('../../../src/game/content/characters/fatty-one-eye/visual-set.json', import.meta.url), 'utf8'));
  const definition = JSON.parse(await readFile(new URL('../../../src/game/content/bosses/fatty-one-eye.json', import.meta.url), 'utf8'));
  assert.equal(character.kind, 'boss');
  assert.deepEqual(visualSet.clips['contact-hop'], {
    frames: [12, 13, 14, 15], keyframeTimes: [0, 1, 3, 5], durationSeconds: 0.3,
    framesPerSecond: 20, loop: false, loopMode: 'wrap',
  });
  assert.deepEqual(character.animationTracks['contact-hop'].hitboxSpans, [{ hitboxId: 'contact-hop-impact', from: 5, through: 5 }]);
  assert.equal(character.hitboxes['contact-hop-impact'].radius, 80);
  assert.equal(definition.characterId, character.characterId);
  assert.equal(definition.contactHop.clipId, 'contact-hop');
  assert.equal(definition.contactHop.hitboxId, 'contact-hop-impact');
  assert.equal('durationMs' in definition.contactHop, false);
  assert.equal('radius' in definition.contactHop, false);
});

test('authored contact-hop circle hits an overlapping player body even when its center is outside', () => {
  const hitbox = { shape: 'circle', width: 160, height: 160, radius: 80, offsetX: 0, offsetY: 0, mirrorX: false };
  const overlappingPlayer = { active: true, body: { enable: true, x: 78, y: -12, width: 24, height: 24 } };
  const separatedPlayer = { active: true, body: { enable: true, x: 81, y: 81, width: 20, height: 20 } };
  assert.equal(geometry.characterHitboxIntersectsCombatBody(hitbox, { x: 0, y: 0 }, 1, overlappingPlayer), true);
  assert.equal(geometry.characterHitboxIntersectsCombatBody(hitbox, { x: 0, y: 0 }, 1, separatedPlayer), false);
});

test('runtime wiring uses the blocking collider and has no direct overlap damage poll', async () => {
  const { readFile } = await import('node:fs/promises');
  const bossSource = await readFile(new URL('../../../src/game/features/bosses/FattyOneEyeBoss.ts', import.meta.url), 'utf8');
  const campSource = await readFile(new URL('../../../src/game/features/bosses/BossCampController.ts', import.meta.url), 'utf8');
  assert.match(campSource, /add\.collider\(ctx\.player, this\.targets/);
  assert.match(campSource, /requestContactHop\(ctx\.scene\.time\.now\)/);
  assert.doesNotMatch(campSource, /enteredArena/);
  assert.match(bossSource, /this\.leapTarget\.set\(player\.x, player\.y\)/);
  assert.match(bossSource, /this\.phase = 'return-to-center'/);
  assert.match(bossSource, /shouldBossReturnToArenaCenter\(this\.ctx\.arena, this\.ctx\.getPlayer\(\)\)/);
  assert.match(bossSource, /shouldResumePursuitFromReturn\(this\.ctx\.arena, this\.ctx\.getPlayer\(\)\)[\s\S]*this\.beginChase\(time, true\)[\s\S]*this\.updateChase\(time\)/);
  const chaseMethod = bossSource.slice(bossSource.indexOf('private updateChase'), bossSource.indexOf('private beginReturning'));
  assert.ok(chaseMethod.indexOf('canBossBeginAttack') < chaseMethod.indexOf('time >= this.nextLeapAt'));
  const contactMethod = bossSource.slice(bossSource.indexOf('requestContactHop'), bossSource.indexOf('private updateChase'));
  assert.ok(contactMethod.indexOf('canBossBeginAttack') < contactMethod.indexOf("this.phase = 'contact-hop'"));
  const returnMethod = bossSource.slice(bossSource.indexOf('private updateReturning'), bossSource.indexOf('private beginSmallHops'));
  const centerBranch = returnMethod.slice(returnMethod.indexOf('if (remaining <='), returnMethod.indexOf('velocity.setLength'));
  assert.doesNotMatch(centerBranch, /beginChase|beginSmallHops|beginAirborne/);
  assert.match(bossSource, /characterHitboxIntersectsCombatBody/);
  assert.match(bossSource, /CharacterAnimationTrackRunner/);
  assert.doesNotMatch(bossSource, /physics\.overlap/);
  assert.doesNotMatch(bossSource, /applyContactDamage/);
});
