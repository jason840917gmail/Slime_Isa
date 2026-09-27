import path from 'node:path';

import { convertedOutput, effectIdForVisualSet, readJson, requireSupportedUnit, resourcePath } from './adapter-utils.mjs';

const SUPPORTED = new Set([
  'visual:boss.fatty-one-eye',
  'visual:character.player.slime',
  'visual:character.npc.lili',
  'visual:character.npc.mossy-scout',
  'visual:character.npc.red-slime-boy',
  'visual:character.npc.village-elder-plop',
  'visual:character.npc.yellow-blond-slime-girl',
  'visual:enemy.slime.spider',
  'visual:enemy.worm.archer',
  'visual:enemy.worm.brawler',
  'visual:enemy.worm.swordsman',
  'visual:effect.enemy.worm-brawler-hit',
]);

/** Timeline frames of a frame clip, as `normalizeAnimationClip` samples it. */
function clipTimelineFrames(clip) {
  return clip.durationSeconds === undefined ? clip.frames.length : Math.max(1, Math.round(clip.durationSeconds * clip.framesPerSecond));
}

/**
 * Gameplay events come from the character's authored animation track for the
 * clip: its events verbatim, plus one activation/deactivation event per hitbox
 * span (what `CharacterAnimationTrackRunner` used to dispatch).
 */
function clipEvents(track, timelineFrames) {
  if (!track) return [];
  const events = (track.events ?? []).map((event) => ({
    at: event.at, eventId: event.eventId ?? event.id, ...(event.payload === undefined ? {} : { payload: event.payload }), gameplay: true,
  }));
  (track.hitboxSpans ?? []).forEach((span, spanIndex) => {
    events.push({ at: span.from, eventId: 'hitbox-activated', payload: { hitboxId: span.hitboxId, spanIndex }, gameplay: true });
    if (span.through + 1 < timelineFrames) {
      events.push({ at: span.through + 1, eventId: 'hitbox-deactivated', payload: { hitboxId: span.hitboxId, spanIndex }, gameplay: true });
    }
  });
  return events.sort((left, right) => left.at - right.at);
}

/**
 * Effect visual sets play their single clip for whichever direction the effect
 * is spawned with; the effect scene's animation ids are the effect directions.
 */
const EFFECT_DIRECTIONS = ['right', 'left', 'up', 'down'];

const samePair = (left, right) => left[0] === right[0] && left[1] === right[1];

/**
 * Per-frame visual transforms (`frameVisuals`, clip `sourceOffset`) resolved
 * like the old `resolveFrameVisual`. Returns scale/position tracks for the
 * Visual sprite only when some frame differs from the visual-set defaults.
 */
function frameVisualTracks(visual, clip, keyframeTimes) {
  const defaults = visual.defaults;
  const resolved = clip.frames.map((frame) => {
    const override = visual.frameVisuals?.[String(frame)];
    const origin = override?.origin ?? defaults.origin;
    if (!samePair(origin, defaults.origin)) throw new Error(`Visual '${visual.visualSetId}' frame ${frame} changes origin, which Sprite2D cannot animate`);
    return { scale: override?.scale ?? defaults.scale, offset: override?.sourceOffset ?? clip.sourceOffset ?? defaults.sourceOffset };
  });
  const tracks = [];
  if (resolved.some(({ scale }) => !samePair(scale, defaults.scale))) {
    tracks.push({ binding: '../Visual', property: 'scale', keys: resolved.map(({ scale }, index) => ({ at: keyframeTimes[index], value: scale })) });
  }
  if (resolved.some(({ offset }) => !samePair(offset, defaults.sourceOffset))) {
    tracks.push({ binding: '../Visual', property: 'position', keys: resolved.map(({ offset }, index) => ({ at: keyframeTimes[index], value: offset })) });
  }
  return tracks;
}

function animationDocument(visual, character) {
  const animations = {};
  const isEffect = visual.visualSetId.startsWith('effect.');
  const clips = Object.entries(visual.clips);
  if (isEffect && clips.length !== 1) throw new Error(`Effect visual set '${visual.visualSetId}' must have exactly one clip`);
  for (const [clipId, clip] of clips) {
    const keyframeTimes = clip.keyframeTimes ?? clip.frames.map((_, index) => index);
    const timelineFrames = clipTimelineFrames(clip);
    const animation = {
      durationSeconds: clip.durationSeconds ?? clip.frames.length / clip.framesPerSecond,
      framesPerSecond: clip.framesPerSecond,
      loop: clip.loop,
      ...(clip.loopMode ? { loopMode: clip.loopMode } : {}),
      tracks: [{
        binding: '../Visual',
        property: 'frame',
        keys: clip.frames.map((frame, index) => ({ at: keyframeTimes[index], value: frame })),
      }, ...frameVisualTracks(visual, clip, keyframeTimes)],
    };
    const events = clipEvents(character?.animationTracks?.[clipId], timelineFrames);
    if (events.length > 0) animation.events = events;
    if (isEffect) for (const direction of EFFECT_DIRECTIONS) animations[direction] = animation;
    else animations[clipId] = animation;
  }
  return { version: 1, resourceId: `${visual.visualSetId}.animations`, kind: 'animation-library', animations };
}

function effectVisualScene(visual) {
  const prefix = visual.visualSetId;
  const effectId = effectIdForVisualSet(visual.visualSetId);
  const [clip] = Object.values(visual.clips);
  const lifetimeMs = Math.round((clip.durationSeconds ?? clip.frames.length / clip.framesPerSecond) * 1000);
  return {
    version: 1,
    sceneId: `effect.${effectId}`,
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: effectId.split('-').map((part) => `${part[0]?.toUpperCase() ?? ''}${part.slice(1)}`).join(''), type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0], depthAnchor: [0, 0] } },
      {
        id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'root', order: 0,
        properties: {
          texture: { resourceId: `${prefix}.sprite` }, frame: 0, origin: visual.defaults.origin,
          position: visual.defaults.sourceOffset, scale: visual.defaults.scale, rotation: 0, alpha: 1,
          depthMode: 'relative', depthBand: 'world-entities',
        },
      },
      {
        id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'root', order: 1,
        properties: { library: { resourceId: `${prefix}.animations` }, domain: 'physics', autoplay: 'right' },
      },
      {
        id: 'script', name: 'EffectScript', type: 'ScriptNode', scriptId: 'game.effect', parentId: 'root', order: 2,
        properties: { effectId, animation: { nodeId: 'animation' }, lifetimeMs },
      },
    ],
    instances: [],
  };
}

async function characterForVisual(readSource, visual, visualPath) {
  const characterPath = `${path.posix.dirname(visualPath)}/character.json`;
  let character;
  try {
    character = await readJson(readSource, characterPath);
  } catch (error) {
    if (error?.code === 'ENOENT') return undefined;
    throw error;
  }
  return character.visualSetId === visual.visualSetId ? { character, characterPath } : undefined;
}

export const visualSceneAdapter = {
  async convert({ units, readSource }) {
    const outputs = [];
    for (const unit of units) {
      requireSupportedUnit(unit, SUPPORTED);
      const visual = await readJson(readSource, unit.oldSourcePath);
      const owner = await characterForVisual(readSource, visual, unit.oldSourcePath);
      const manifest = await readJson(readSource, 'asset/assets.json');
      const frame = manifest.assets[visual.assetId]?.source?.frame;
      if (!frame) throw new Error(`Visual '${visual.visualSetId}' uses non-spritesheet asset '${visual.assetId}'`);
      outputs.push(convertedOutput(unit, resourcePath('visuals', visual.visualSetId, 'sprite'), {
        version: 1,
        resourceId: `${visual.visualSetId}.sprite`,
        kind: 'sprite-sheet',
        assetId: visual.assetId,
        frameWidth: frame.w,
        frameHeight: frame.h,
        frameCount: frame.count,
      }, ['$.assetId']));
      outputs.push(convertedOutput(unit, resourcePath('visuals', visual.visualSetId, 'animations'), animationDocument(visual, owner?.character), [
        '$.visualSetId', '$.clips',
      ], [
        { path: '$.$schema', owner: unit.oldSourcePath },
        { path: '$.version', owner: unit.oldSourcePath },
        { path: '$.defaults', owner: unit.oldSourcePath },
      ]));
      if (visual.visualSetId.startsWith('effect.')) {
        outputs.push(convertedOutput(unit, `effects/${effectIdForVisualSet(visual.visualSetId)}.scene.json`, effectVisualScene(visual), [
          '$.visualSetId', '$.assetId', '$.defaults', '$.clips',
        ], [{ path: '$.$schema', owner: unit.oldSourcePath }, { path: '$.version', owner: unit.oldSourcePath }]));
      }
    }
    return outputs;
  },
};
