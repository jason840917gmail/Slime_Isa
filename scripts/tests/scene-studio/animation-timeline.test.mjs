import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const model = await loadTypescriptModule('src/game/editor/scene-studio/animation/AnimationClipModel.ts');
const lanes = await loadTypescriptModule('src/game/editor/scene-studio/animation/WeaponAttackLanes.ts');
const targets = await loadTypescriptModule('src/game/editor/scene-studio/animation/AnimationTargets.ts');
const binding = await loadTypescriptModule('src/game/runtime/scene/animation/AnimationBinding.ts');

const clip = (overrides = {}) => ({ durationSeconds: 1, framesPerSecond: 10, loop: false, loopMode: 'wrap', tracks: [], events: [], ...overrides });
const frameTrack = { binding: '../Visual', property: 'frame', keys: [0, 1, 2, 3].map((at) => ({ at, value: at })) };
const positionTrack = { binding: '../Visual', property: 'position', keys: [{ at: 0, value: [10, 4] }, { at: 5, value: [20, 4] }] };

test('clip library operations keep order and reject collisions', () => {
  let clips = model.createClip({}, 'idle', { framesPerSecond: 8, frameCount: 4 });
  clips = model.createClip(clips, 'walk');
  assert.equal(model.clipFrameCount(clips.idle), 4);
  clips = model.renameClip(clips, 'idle', 'rest');
  assert.deepEqual(Object.keys(clips), ['rest', 'walk']);
  assert.throws(() => model.renameClip(clips, 'rest', 'walk'), /already exists/);
  assert.throws(() => model.createClip(clips, 'bad name!'), /letters, digits/);
  clips = model.duplicateClip(clips, 'rest', 'rest-copy');
  assert.notEqual(clips['rest-copy'], clips.rest);
  assert.equal(model.uniqueClipId(clips, 'rest'), 'rest-2');
  assert.deepEqual(Object.keys(model.deleteClip(clips, 'walk')), ['rest', 'rest-copy']);
});

test('mirroring flips positions, rotation and the matching flip flag', () => {
  const source = clip({ tracks: [positionTrack, { binding: '../Visual', property: 'rotation', keys: [{ at: 0, value: 30 }] }, { binding: '../Visual', property: 'flipX', keys: [{ at: 0, value: false }] }] });
  const mirrored = model.mirrorClip({ 'attack-right': source }, 'attack-right', 'attack-left', 'x')['attack-left'];
  assert.deepEqual(mirrored.tracks[0].keys[1].value, [-20, 4]);
  assert.equal(mirrored.tracks[1].keys[0].value, -30);
  assert.equal(mirrored.tracks[2].keys[0].value, true);
});

test('timing edits retime or trim keys, events and report a frame remap', () => {
  const source = clip({ tracks: [frameTrack], events: [{ at: 3, eventId: 'hit' }] });
  const faster = model.setFramesPerSecond(source, 20, true);
  assert.equal(model.clipFrameCount(faster.clip), 20);
  assert.deepEqual(faster.clip.tracks[0].keys.map((key) => key.at), [0, 2, 4, 6]);
  assert.equal(faster.clip.events[0].at, 6);
  assert.equal(faster.remap(3), 6);
  const sped = model.setFramesPerSecond(source, 20, false);
  assert.equal(sped.clip.durationSeconds, 0.5);
  assert.deepEqual(sped.clip.tracks[0].keys.map((key) => key.at), [0, 1, 2, 3]);
  const trimmed = model.setFrameCount(source, 3, false);
  assert.deepEqual(trimmed.clip.tracks[0].keys.map((key) => key.at), [0, 1, 2]);
  assert.equal(trimmed.clip.events.length, 0);
  const stretched = model.setFrameCount(clip({ durationSeconds: 0.4, tracks: [frameTrack] }), 7, true);
  assert.deepEqual(stretched.clip.tracks[0].keys.map((key) => key.at), [0, 2, 4, 6]);
  const inserted = model.insertFrames(source, 2, 2);
  assert.deepEqual(inserted.clip.tracks[0].keys.map((key) => key.at), [0, 1, 4, 5]);
  assert.equal(model.clipFrameCount(inserted.clip), 12);
  const removed = model.deleteFrames(source, 1, 2);
  assert.deepEqual(removed.clip.tracks[0].keys.map((key) => [key.at, key.value]), [[0, 0], [1, 3]]);
  assert.equal(removed.remap(2), undefined);
});

test('keys move, duplicate, paste and overwrite like Godot', () => {
  let source = clip({ tracks: [structuredClone(frameTrack)] });
  const moved = model.moveKeys(source, [{ track: 0, at: 1 }], 2);
  assert.deepEqual(moved.clip.tracks[0].keys.map((key) => [key.at, key.value]), [[0, 0], [2, 2], [3, 1]]);
  assert.deepEqual(moved.refs, [{ track: 0, at: 3 }]);
  const copied = model.moveKeys(source, [{ track: 0, at: 0 }], 6, true);
  assert.equal(copied.clip.tracks[0].keys.length, 5);
  assert.throws(() => model.moveKeys(source, [{ track: 0, at: 3 }], 9), /outside the clip/);
  source = model.addTrack(source, '../Other', 'frame');
  const clipboard = model.copyKeys(source, [{ track: 0, at: 2 }, { track: 0, at: 3 }]);
  const pasted = model.pasteKeys(source, clipboard, 7, 1);
  assert.deepEqual(pasted.clip.tracks[1].keys.map((key) => [key.at, key.value]), [[7, 2], [8, 3]]);
  const eased = model.setKeyTransition(source, [{ track: 0, at: 0 }], 'ease-out');
  assert.equal(eased.tracks[0].keys[0].transition, 'ease-out');
  assert.equal(model.setKeyTransition(eased, [{ track: 0, at: 0 }], 'linear').tracks[0].keys[0].transition, undefined);
});

test('tracks toggle, reorder, retarget and reject duplicates', () => {
  let source = clip({ tracks: [frameTrack, positionTrack] });
  assert.throws(() => model.addTrack(source, '../Visual', 'frame'), /already exists/);
  source = model.setTrackEnabled(source, 0, false);
  assert.equal(source.tracks[0].enabled, false);
  assert.equal('enabled' in model.setTrackEnabled(source, 0, true).tracks[0], false);
  source = model.setTrackInterpolation(source, 1, 'nearest');
  assert.equal(source.tracks[1].interpolation, 'nearest');
  source = model.moveTrack(source, 1, -1);
  assert.equal(source.tracks[0].property, 'position');
  assert.equal(model.retargetTrack(source, 0, '../Body').tracks[0].binding, '../Body');
});

test('simplify removes repeats on step tracks and collinear keys on linear tracks', () => {
  const converted = clip({ tracks: [
    { binding: '../Visual', property: 'frame', keys: [0, 0, 0, 1, 1, 2].map((value, at) => ({ at, value })) },
    { binding: '../Visual', property: 'position', keys: [0, 1, 2, 3, 4].map((at) => ({ at, value: [at * 5, 0] })) },
  ] });
  const result = model.simplifyKeys(converted, (track) => track.property === 'position');
  assert.deepEqual(result.clip.tracks[0].keys.map((key) => key.at), [0, 3, 5]);
  assert.deepEqual(result.clip.tracks[1].keys.map((key) => key.at), [0, 4]);
  assert.equal(result.removed, 6);
  assert.deepEqual(model.sampleTrack(result.clip.tracks[1], 2, true), [10, 0]);
  assert.equal(model.sampleTrack(result.clip.tracks[0], 4, false), 1);
});

test('events stay sorted and validate their IDs', () => {
  let source = clip();
  source = model.addEvent(source, { at: 5, eventId: 'late' }).clip;
  const added = model.addEvent(source, { at: 1, eventId: 'early', gameplay: true });
  assert.equal(added.index, 0);
  const moved = model.updateEvent(added.clip, 0, { at: 8, gameplay: false });
  assert.deepEqual(moved.clip.events.map((event) => event.eventId), ['late', 'early']);
  assert.equal('gameplay' in moved.clip.events[1], false);
  assert.throws(() => model.addEvent(source, { at: 1, eventId: '' }), /Event IDs/);
  assert.equal(model.removeEvent(moved.clip, 0).events.length, 1);
});

test('weapon hitbox lanes paint frames and follow clip timing', () => {
  const plans = {
    right: { animationId: 'attack-right', durationMs: 500, framesPerSecond: 10, hitboxSpans: [{ hitboxId: 'primary', from: 2, through: 3, damageMultiplier: 1, knockbackMultiplier: 1 }], events: [], mirrored: { x: false, y: false } },
    left: { animationId: 'attack-left', durationMs: 500, framesPerSecond: 10, hitboxSpans: [], events: [], mirrored: { x: true, y: false } },
  };
  const found = lanes.attackLanes(plans, 'attack-right', ['right--primary', 'right--tip', 'left--primary']);
  assert.deepEqual(found.map((lane) => `${lane.direction}:${lane.hitboxId}:${lane.spans.length}`), ['right:primary:1', 'right:tip:0']);
  let next = lanes.setHitboxFrame(plans, 'right', 'primary', 4, true);
  assert.deepEqual(next.right.hitboxSpans.map((span) => [span.from, span.through]), [[2, 4]]);
  next = lanes.setHitboxFrame(next, 'right', 'primary', 3, false);
  assert.deepEqual(next.right.hitboxSpans.map((span) => [span.from, span.through]), [[2, 2], [4, 4]]);
  assert.equal(lanes.hitboxActiveAt(next, 'right', 'primary', 4), true);
  const retimed = model.setFramesPerSecond(clip({ durationSeconds: 0.5 }), 20, true);
  const synced = lanes.syncPlansWithClip(plans, 'attack-right', retimed.clip, retimed.remap);
  assert.equal(synced.right.framesPerSecond, 20);
  assert.equal(synced.right.durationMs, 500);
  assert.deepEqual(synced.right.hitboxSpans.map((span) => [span.from, span.through]), [[4, 6]]);
  assert.equal(synced.left, plans.left);
  assert.equal(lanes.renamePlanClip(plans, 'attack-right', 'swing').right.animationId, 'swing');
  assert.throws(() => lanes.updateHitboxSpan(plans, 'right', 0, { through: 9 }, 5), /through < 5/);
});

test('bindings are Godot-style relative node paths', () => {
  const nodes = [
    { key: ':root', name: 'Sword', type: 'Node2D' },
    { key: ':visual', name: 'Base1', type: 'Sprite2D', parentKey: ':root' },
    { key: ':area', name: 'AttackArea', type: 'Area2D', parentKey: ':root' },
    { key: ':shape', name: 'right--primary', type: 'CollisionShape2D', parentKey: ':area' },
    { key: ':anim', name: 'Animation', type: 'AnimationPlayer', parentKey: ':root' },
  ];
  const byKey = new Map(nodes.map((node) => [node.key, node]));
  assert.equal(targets.relativeBinding(byKey, ':anim', ':visual'), '../Base1');
  assert.equal(targets.relativeBinding(byKey, ':anim', ':shape'), '../AttackArea/right--primary');
  assert.equal(targets.resolveBinding(nodes, ':anim', '../AttackArea/right--primary')?.key, ':shape');
  assert.equal(targets.resolveBinding(nodes, ':anim', '/Sword/Base1')?.key, ':visual');
  assert.equal(targets.resolveBinding(nodes, ':anim', '../Missing'), undefined);
});

test('runtime bindings apply key transitions, track interpolation overrides and reject blended steps', () => {
  const numeric = { key: 'alpha', label: 'Alpha', value: { kind: 'number' }, serialized: true, inspector: 'number', animation: { interpolation: 'numeric', domains: ['render'] }, overridable: true };
  const step = { ...numeric, key: 'frame', animation: { interpolation: 'step', domains: ['render'] } };
  const target = { name: 'Visual', alpha: 0, frame: 0, get_path: () => '/Visual' };
  const alpha = new binding.AnimationBinding(target, 'alpha', numeric);
  alpha.acquire({}, 'render');
  alpha.apply(5, [{ at: 0, value: 0, transition: 'ease-in' }, { at: 10, value: 1 }]);
  assert.equal(target.alpha, 0.25);
  alpha.apply(5, [{ at: 0, value: 0 }, { at: 10, value: 1 }], 'nearest');
  assert.equal(target.alpha, 0);
  assert.throws(() => binding.trackInterpolation(step, 'linear'), /nearest/);
  assert.equal(binding.easeAnimationRatio(0.5, 'ease-in-out'), 0.5);
});

test('value fields show angles in degrees and pick editors from descriptors', async () => {
  const fields = await loadTypescriptModule('src/game/editor/scene-studio/animation/AnimationValueFields.ts');
  assert.equal(fields.formatAnimationValue('rotation', Math.PI / 2), '90°');
  assert.equal(fields.formatAnimationValue('position', [55.123, 10]), '55.12, 10');
  assert.equal(fields.animationValueKind('rotation', undefined, 0.5), 'angle');
  assert.equal(fields.animationValueKind('frame', { value: { kind: 'number', integer: true } }, 1), 'integer');
  assert.equal(fields.animationValueKind('position', { value: { kind: 'vector2' } }), 'vector');
  assert.match(fields.renderAnimationValueFields('angle', Math.PI, { disabled: false, label: 'Rotation' }), /value="180"/);
});
