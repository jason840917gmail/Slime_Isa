import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let timelineView;
let timelinePanel;
let timelineResize;
let animation;
let weaponHitboxPreview;
let weaponHitboxGuides;
let layeredWeaponHitboxControls;
let CharacterDocumentState;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({
    absWorkingDir: repositoryRoot,
    entryPoints: [entryPoint],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  const source = result.outputFiles[0].text;
  return import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
}

before(async () => {
  [timelineView, timelinePanel, timelineResize, animation, weaponHitboxPreview, weaponHitboxGuides, layeredWeaponHitboxControls] = await Promise.all([
    loadTypeScriptModule('src/game/editor/AnimationTimelineView.ts'),
    loadTypeScriptModule('src/game/editor/AnimationTimelinePanel.ts'),
    loadTypeScriptModule('src/game/editor/AnimationTimelineResize.ts'),
    loadTypeScriptModule('src/game/shared/animation/timeline.ts'),
    loadTypeScriptModule('src/game/editor/WeaponHitboxPreview.ts'),
    loadTypeScriptModule('src/game/editor/WeaponHitboxGuides.ts'),
    loadTypeScriptModule('src/game/editor/LayeredWeaponHitboxControls.ts'),
  ]);
  ({ CharacterDocumentState } = await loadTypeScriptModule('src/game/editor/CharacterDocumentState.ts'));
});

test('shared decrease and increase controls carry their own keyframe index', () => {
  const html = timelineView.renderTimelineHoldControls(2, 3);
  assert.equal((html.match(/data-keyframe-index="2"/g) ?? []).length, 2);
  assert.match(html, /data-hold-delta="-1"/);
  assert.match(html, /data-hold-delta="1"/);
});

test('shared right-edge handle and resize snapping are deterministic', () => {
  const keyframe = timelineView.createAnimationTimelineView({
    frames: [7], framesPerSecond: 24, loop: false, loopMode: 'wrap', durationSeconds: 4 / 24, keyframeTimes: [0],
  }).keyframes[0];
  const html = timelineView.renderTimelineResizeHandle(keyframe);
  assert.match(html, /role="separator"/);
  assert.match(html, /data-timeline-resize-handle/);
  assert.match(html, /data-keyframe-index="0"/);
  assert.match(html, /aria-valuenow="4"/);
  assert.equal(timelineView.renderTimelineResizeHandle(keyframe, true), '');

  assert.equal(timelineResize.roundTimelineResizeFrameDelta(49.9, 100), 0);
  assert.equal(timelineResize.roundTimelineResizeFrameDelta(50, 100), 1);
  assert.equal(timelineResize.roundTimelineResizeFrameDelta(-49.9, 100), 0);
  assert.equal(timelineResize.roundTimelineResizeFrameDelta(-50, 100), -1);
  assert.equal(timelineResize.roundTimelineResizeFrameDelta(260, 100), 3);
  assert.equal(timelineResize.timelineResizeHold(2, -8), 1);
  assert.equal(timelineResize.timelineResizeHold(2, 3), 5);
});

test('seconds-first ruler formatting and tick cadence are deterministic', () => {
  const oneFrame = timelineView.createAnimationTimelineView({
    frames: [7], framesPerSecond: 24, loop: false, loopMode: 'wrap', durationSeconds: 1 / 24, keyframeTimes: [0],
  });
  assert.equal(oneFrame.timelineFrames, 1);
  assert.equal(oneFrame.effectiveDurationSeconds, 1 / 24);
  assert.deepEqual(oneFrame.rulerTicks, [{ frame: 0, gridColumn: 1, timeLabel: '0.00s' }]);
  assert.equal(oneFrame.keyframes[0].gridColumnStart, 1);
  assert.equal(oneFrame.keyframes[0].gridColumnSpan, 1);

  assert.equal(timelineView.formatAnimationTimelineSeconds(1 / 100, 100), '0.01');
  assert.equal(timelineView.formatAnimationTimelineSeconds(1 / 101, 101), '0.010');
  assert.equal(timelineView.formatAnimationTimelineSeconds(1 / 240, 240), '0.004');

  const labelledFrames = (timelineFrames) => timelineView.createAnimationTimelineView({
    frames: [0], framesPerSecond: 10, loop: false, loopMode: 'wrap', durationSeconds: timelineFrames / 10, keyframeTimes: [0],
  }).rulerTicks.filter((tick) => tick.timeLabel).map((tick) => tick.frame);
  assert.deepEqual(labelledFrames(13), [0, 2, 4, 6, 8, 10, 12]);
  assert.deepEqual(labelledFrames(14), [0, 2, 4, 6, 8, 10, 12, 13]);
});

test('seconds-first keyframes share ruler grid geometry and timing labels', () => {
  const clip = {
    frames: [10, 20, 30], framesPerSecond: 10, loop: false, loopMode: 'wrap', durationSeconds: 0.8, keyframeTimes: [0, 2, 5],
  };
  const view = timelineView.createAnimationTimelineView(clip);
  assert.deepEqual(view.keyframes.map((keyframe) => keyframe.gridColumnStart), [1, 3, 6]);
  assert.deepEqual(view.keyframes.map((keyframe) => keyframe.gridColumnSpan), [2, 3, 3]);
  assert.equal(view.keyframes[2].tooltip, 'Keyframe 02. Start 0.50 seconds (frame 5). Hold 0.30 seconds (3 frames). Source 30.');
  assert.equal(timelineView.renderTimelineKeyframeTimingLabels(view.keyframes[2]), '<span class="timeline-frame-number">@0.50s</span><span class="timeline-frame-hold">0.30s / 3F</span>');

  const html = timelinePanel.renderAnimationTimelinePanel({
    titleHtml: 'Fixture',
    hint: 'Fixture',
    addTilesAction: 'add-fixture-tiles',
    clipTabsHtml: '',
    timelineView: view,
    renderKeyframe: (keyframe) => `<button style="grid-column:${keyframe.gridColumnStart} / span ${keyframe.gridColumnSpan}"></button>`,
  });
  assert.match(html, /--timeline-frame-count:8/);
  assert.match(html, /data-timeline-frame="5"[^>]*><b>0\.50s<\/b>/);
  assert.match(html, /grid-column:6 \/ span 3/);
});

test('duration normalization rejects invalid values and exposes frame-aligned effective time', () => {
  assert.throws(() => animation.normalizeAnimationClip({ frames: [0], framesPerSecond: 0, loop: false, durationSeconds: 1, keyframeTimes: [0] }));
  assert.throws(() => animation.normalizeAnimationClip({ frames: [0], framesPerSecond: 241, loop: false, durationSeconds: 1, keyframeTimes: [0] }));
  assert.throws(() => animation.normalizeAnimationClip({ frames: [0], framesPerSecond: 10, loop: false, durationSeconds: 0, keyframeTimes: [0] }));

  const authoredDuration = 1.05;
  const clip = animation.normalizeAnimationClip({ frames: [0], framesPerSecond: 10, loop: false, durationSeconds: authoredDuration, keyframeTimes: [0] });
  const view = timelineView.createAnimationTimelineView(clip);
  assert.equal(clip.durationSeconds, authoredDuration);
  assert.equal(view.timelineFrames, 11);
  assert.equal(view.effectiveDurationSeconds, 1.1);
});

test('Character Studio adjusts the clicked unselected keyframe without changing selection', async () => {
  const character = JSON.parse(await fs.readFile(path.join(repositoryRoot, 'src/game/content/characters/player-slime/character.json'), 'utf8'));
  const visualSet = JSON.parse(await fs.readFile(path.join(repositoryRoot, 'src/game/content/characters/player-slime/visual-set.json'), 'utf8'));
  visualSet.clips.idle = {
    frames: [0, 1, 2],
    framesPerSecond: 10,
    loop: true,
    loopMode: 'wrap',
    durationSeconds: 0.8,
    keyframeTimes: [0, 3, 5],
  };
  const state = new CharacterDocumentState({ character, visualSet }, 'fixture');
  state.selectClip('idle');
  state.selectTimelineIndex(0);

  assert.equal(state.adjustKeyframeHold(1, 1), true);
  assert.deepEqual(state.value.visualSet.clips.idle.keyframeTimes, [0, 3, 6]);
  assert.ok(Math.abs(state.value.visualSet.clips.idle.durationSeconds - 0.9) < 1e-9);
  assert.equal(state.value.selectedTimelineIndex, 0);

  assert.equal(state.adjustKeyframeHold(1, -1), true);
  assert.deepEqual(state.value.visualSet.clips.idle.keyframeTimes, [0, 3, 5]);
  assert.ok(Math.abs(state.value.visualSet.clips.idle.durationSeconds - 0.8) < 1e-9);
  assert.equal(state.value.selectedTimelineIndex, 0);

  assert.equal(state.setKeyframeHold(1, 4), true);
  assert.deepEqual(state.value.visualSet.clips.idle.keyframeTimes, [0, 3, 7]);
  assert.ok(Math.abs(state.value.visualSet.clips.idle.durationSeconds - 1) < 1e-9);
  state.undo();
  assert.deepEqual(state.value.visualSet.clips.idle.keyframeTimes, [0, 3, 5]);
  assert.ok(Math.abs(state.value.visualSet.clips.idle.durationSeconds - 0.8) < 1e-9);
  state.redo();
  assert.deepEqual(state.value.visualSet.clips.idle.keyframeTimes, [0, 3, 7]);
  assert.ok(Math.abs(state.value.visualSet.clips.idle.durationSeconds - 1) < 1e-9);
  assert.equal(state.value.selectedTimelineIndex, 0);
});

test('Weapon Studio targeting keeps hold edits and preview aligned to the clicked keyframe', () => {
  const clip = {
    frames: [10, 20, 30],
    framesPerSecond: 10,
    loop: false,
    loopMode: 'wrap',
    durationSeconds: 0.8,
    keyframeTimes: [0, 2, 5],
  };
  const selectedPositions = [0];
  const increased = animation.resizeKeyframeHold(clip, 1, animation.holdLengthAtKeyframe(clip, 1) + 1);
  const decreased = animation.resizeKeyframeHold(clip, 1, animation.holdLengthAtKeyframe(clip, 1) - 1);

  assert.deepEqual(increased.keyframeTimes, [0, 2, 6]);
  assert.deepEqual(decreased.keyframeTimes, [0, 2, 4]);
  assert.deepEqual(increased.keyframeTimes.map((start, index) => index === 0 ? start : start - clip.keyframeTimes[index]), [0, 0, 1]);
  assert.deepEqual(decreased.keyframeTimes.map((start, index) => index === 0 ? start : start - clip.keyframeTimes[index]), [0, 0, -1]);
  assert.deepEqual([0, 1, 2].map((index) => animation.holdLengthAtKeyframe({ ...clip, keyframeTimes: increased.keyframeTimes, durationSeconds: increased.durationSeconds }, index)), [2, 4, 3]);
  assert.deepEqual([0, 1, 2].map((index) => animation.holdLengthAtKeyframe({ ...clip, keyframeTimes: decreased.keyframeTimes, durationSeconds: decreased.durationSeconds }, index)), [2, 2, 3]);
  assert.ok(Math.abs(increased.durationSeconds - 0.9) < 1e-9);
  assert.ok(Math.abs(decreased.durationSeconds - 0.7) < 1e-9);

  const minimum = animation.resizeKeyframeHold({ ...clip, keyframeTimes: [0, 1, 5] }, 0, 0);
  assert.deepEqual(minimum.keyframeTimes, [0, 1, 5]);
  assert.equal(minimum.durationSeconds, clip.durationSeconds);
  const finalIncrease = animation.resizeKeyframeHold(clip, 2, 4);
  assert.deepEqual(finalIncrease.keyframeTimes, clip.keyframeTimes);
  assert.ok(Math.abs(finalIncrease.durationSeconds - 0.9) < 1e-9);
  assert.deepEqual(selectedPositions, [0]);

  const target = timelineView.previewTargetAtKeyframe(clip, 2);
  const expanded = animation.expandAnimationClip(clip);
  assert.deepEqual(target, { keyframeIndex: 2, timelineFrame: 5, sourceFrame: 30 });
  assert.equal(expanded.sourceFrames[target.timelineFrame], 30);
  assert.equal(expanded.occurrenceIndices[target.timelineFrame], 2);
});

function weaponFixture(overrides = {}) {
  const clip = { frames: [0], framesPerSecond: 10, loop: false, loopMode: 'wrap', durationSeconds: 0.4, keyframeTimes: [0] };
  return {
    version: 1,
    weaponId: 'fixture-weapon',
    displayName: 'Fixture Weapon',
    category: 'blade',
    assetId: 'weapon.fixture',
    animations: { idle: clip, attack: clip, impact: clip },
    characterActionId: 'attack-1',
    hitboxes: {
      primary: { shape: 'rectangle', width: 20, height: 10, offsetX: 12, offsetY: 3 },
    },
    baseDamage: 1,
    cooldownMs: 100,
    hitboxWidth: 20,
    hitboxHeight: 10,
    hitboxOffset: 12,
    hitboxDurationMs: 120,
    knockStrength: 1,
    vfxColor: 0xffffff,
    unlockLevel: 1,
    iconKey: 'fixture',
    description: 'Fixture',
    ...overrides,
  };
}

test('weapon hitbox preview resolves weapon-owned directional inheritance through normalization', () => {
  const clip = { frames: [2], framesPerSecond: 10, loop: false, loopMode: 'wrap', durationSeconds: 0.4, keyframeTimes: [0] };
  const rightHitbox = { shape: 'circle', width: 18, height: 18, radius: 9, offsetX: 30, offsetY: 4 };
  const track = { hitboxSpans: [{ hitboxId: 'right-edge', from: 1, through: 2 }], events: [] };
  const weapon = weaponFixture({
    directionalAttacks: {
      side: { animation: clip, hitboxes: { 'right-edge': rightHitbox }, attackTrack: track },
      left: { animation: clip },
    },
  });

  const right = weaponHitboxPreview.resolveWeaponHitboxPreview(weapon, 'right');
  const left = weaponHitboxPreview.resolveWeaponHitboxPreview(weapon, 'left');
  const up = weaponHitboxPreview.resolveWeaponHitboxPreview(weapon, 'up');

  assert.deepEqual(Object.keys(right.attack.hitboxes), ['right-edge']);
  assert.deepEqual(Object.keys(left.attack.hitboxes), ['right-edge']);
  assert.equal(left.attack.presentation, 'authored');
  assert.deepEqual(left.track.hitboxSpans, track.hitboxSpans);
  assert.deepEqual(Object.keys(up.attack.hitboxes), ['primary']);
  assert.equal(right.trackMode, 'authored');
  assert.equal(left.trackMode, 'authored');
});

test('weapon hitbox preview makes a deterministic synthetic track for legacy weapons', () => {
  const weapon = weaponFixture({
    hitboxes: {
      primary: { shape: 'rectangle', width: 20, height: 10, offsetX: 12, offsetY: 3 },
      secondary: { shape: 'circle', width: 8, height: 8, radius: 4, offsetX: 24, offsetY: 0 },
    },
  });
  const preview = weaponHitboxPreview.resolveWeaponHitboxPreview(weapon, 'down');

  assert.equal(preview.trackMode, 'synthetic');
  assert.deepEqual(preview.track.hitboxSpans, [{ hitboxId: 'primary', from: 0, through: 3 }]);
  assert.equal(weaponHitboxPreview.weaponHitboxIsActive(preview, 'primary', 3), true);
  assert.equal(weaponHitboxPreview.weaponHitboxIsActive(preview, 'primary', 4), false);
  assert.equal(weaponHitboxPreview.weaponHitboxIsActive(preview, 'secondary', 0), false);
});

test('weapon hitbox preview geometry matches static directional runtime coordinates', () => {
  assert.deepEqual(weaponHitboxPreview.weaponHitboxPreviewOffset('right', 12, 3), [12, 3]);
  assert.deepEqual(weaponHitboxPreview.weaponHitboxPreviewOffset('left', 12, 3), [-12, 3]);
  assert.deepEqual(weaponHitboxPreview.weaponHitboxPreviewOffset('up', 12, 3), [3, -12]);
  assert.deepEqual(weaponHitboxPreview.weaponHitboxPreviewOffset('down', 12, 3), [-3, 12]);

  const rectangle = weaponHitboxPreview.resolveWeaponHitboxPreviewGeometry(
    { shape: 'rectangle', width: 20, height: 10, offsetX: 12, offsetY: 3 },
    'up',
  );
  assert.deepEqual(rectangle, { shape: 'rectangle', centerX: 3, centerY: -12, width: 20, height: 10, valid: true });

  const ellipse = weaponHitboxPreview.resolveWeaponHitboxPreviewGeometry(
    { shape: 'ellipse', width: 20, height: 10, radius: 9, radiusX: 7, offsetX: 4, offsetY: 2 },
    'left',
  );
  assert.deepEqual(ellipse, { shape: 'ellipse', centerX: -4, centerY: 2, width: 14, height: 18, valid: true });
});

test('weapon sector preview handles cardinal angles and SVG edge cases', () => {
  assert.equal(weaponHitboxPreview.weaponHitboxPreviewAngle('right'), 0);
  assert.equal(weaponHitboxPreview.weaponHitboxPreviewAngle('left'), Math.PI);
  assert.equal(weaponHitboxPreview.weaponHitboxPreviewAngle('up'), -Math.PI / 2);
  assert.equal(weaponHitboxPreview.weaponHitboxPreviewAngle('down'), Math.PI / 2);

  const baseline = weaponHitboxPreview.resolveWeaponHitboxPreviewGeometry(
    { shape: 'sector', width: 20, height: 20, offsetX: 10, offsetY: 0, innerRadius: 0, outerRadius: 30 },
    'right',
  );
  assert.equal(baseline.valid, true);
  assert.equal(baseline.centerX, 10);
  assert.equal(baseline.centerY, 0);
  assert.equal(baseline.sectorViewBox, '0 0 60 60');
  assert.match(baseline.sectorAreaPath, /^M 30 30 L /);

  const offsetUp = weaponHitboxPreview.resolveWeaponHitboxPreviewGeometry(
    { shape: 'sector', width: 20, height: 20, offsetX: 10, offsetY: 3, innerRadius: 0, outerRadius: 30 },
    'up',
  );
  assert.equal(offsetUp.centerX, 3);
  assert.equal(offsetUp.centerY, -10);

  const full = weaponHitboxPreview.resolveWeaponHitboxPreviewGeometry(
    { shape: 'sector', width: 20, height: 20, offsetX: 10, offsetY: 0, innerRadius: 5, outerRadius: 30, arcWidthRad: Math.PI * 2 },
    'right',
  );
  assert.equal((full.sectorAreaPath.match(/ A /g) ?? []).length, 4);

  const zero = weaponHitboxPreview.resolveWeaponHitboxPreviewGeometry(
    { shape: 'sector', width: 20, height: 20, offsetX: 10, offsetY: 0, innerRadius: 0, outerRadius: 30, arcWidthRad: 0 },
    'down',
  );
  assert.equal(zero.sectorAreaPath, undefined);
  assert.match(zero.sectorBoundaryPath, /^M /);

  const invalid = weaponHitboxPreview.resolveWeaponHitboxPreviewGeometry(
    { shape: 'sector', width: 20, height: 20, offsetX: 10, offsetY: 0, innerRadius: 30, outerRadius: 30, arcWidthRad: 1 },
    'right',
  );
  assert.equal(invalid.valid, false);
  assert.match(invalid.invalidReason, /smaller than outer radius/);
  assert.equal(weaponHitboxPreview.weaponAttackTrackScopeLabel('down'), 'ATTACK / DOWN');
});

test('layered hitbox controls expose only the dimensions used by each runtime shape', () => {
  const sector = {
    shape: 'sector', width: 42, height: 18, offsetX: 10, offsetY: 15,
    innerRadius: 2, outerRadius: 57, arcWidthRad: Math.PI / 2,
  };
  const sectorHtml = layeredWeaponHitboxControls.renderLayeredWeaponHitboxControls('primary', sector);

  assert.match(sectorHtml, />Outer radius</);
  assert.match(sectorHtml, />Arc width</);
  assert.match(sectorHtml, /data-weapon-field="hitbox:primary:outerRadius"/);
  assert.match(sectorHtml, /data-weapon-field="hitbox:primary:arcWidthDeg"/);
  assert.match(sectorHtml, /data-weapon-field="hitbox:primary:offsetX"/);
  assert.match(sectorHtml, /data-weapon-field="hitbox:primary:offsetY"/);
  assert.doesNotMatch(sectorHtml, /data-weapon-field="hitbox:primary:width"/);
  assert.doesNotMatch(sectorHtml, /data-weapon-field="hitbox:primary:height"/);

  const rectangleHtml = layeredWeaponHitboxControls.renderLayeredWeaponHitboxControls('guard', {
    shape: 'rectangle', width: 32, height: 12, offsetX: 20, offsetY: -4,
  });
  assert.match(rectangleHtml, /data-weapon-field="hitbox:guard:width"/);
  assert.match(rectangleHtml, /data-weapon-field="hitbox:guard:height"/);
  assert.doesNotMatch(rectangleHtml, /data-weapon-field="hitbox:guard:outerRadius"/);

  const widened = layeredWeaponHitboxControls.updateWeaponHitboxControl(sector, 'outerRadius', '80');
  const halfCircle = layeredWeaponHitboxControls.updateWeaponHitboxControl(widened, 'arcWidthDeg', '180');
  assert.equal(widened.outerRadius, 80);
  assert.equal(halfCircle.arcWidthRad, Math.PI);
});

test('shared hitbox preview markup visibly follows live dimensions, offsets, and activation', () => {
  const base = {
    shape: 'sector', width: 42, height: 18, offsetX: 10, offsetY: 15,
    innerRadius: 0, outerRadius: 30, arcWidthRad: Math.PI / 2,
  };
  const options = {
    hitboxes: { primary: base },
    track: { hitboxSpans: [{ hitboxId: 'primary', from: 2, through: 4 }] },
    direction: 'right',
    timelineFrame: 3,
    selectedHitboxId: 'primary',
  };
  const baseline = weaponHitboxGuides.renderWeaponHitboxGuides(options);
  assert.match(baseline, /stage-hitbox--sector is-hot is-selected/);
  assert.match(baseline, /width:120px;height:120px/);
  assert.match(baseline, /translate\(20px,30px\)/);
  assert.match(baseline, /data-weapon-hitbox-id="primary"/);
  assert.match(baseline, /data-select-hitbox="primary"/);
  assert.match(baseline, /data-select-weapon-hitbox="primary"/);

  const resized = weaponHitboxGuides.renderWeaponHitboxGuides({
    ...options,
    hitboxes: { primary: { ...base, outerRadius: 50 } },
  });
  assert.match(resized, /width:200px;height:200px/);
  assert.notEqual(resized, baseline);

  const moved = weaponHitboxGuides.renderWeaponHitboxGuides({
    ...options,
    hitboxes: { primary: { ...base, offsetX: 18, offsetY: -6 } },
  });
  assert.match(moved, /translate\(36px,-12px\)/);

  const inactive = weaponHitboxGuides.renderWeaponHitboxGuides({ ...options, timelineFrame: 1 });
  assert.doesNotMatch(inactive, / is-hot/);
});
