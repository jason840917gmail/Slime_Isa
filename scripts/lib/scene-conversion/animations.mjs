import { convertedOutput, readJson, requireSupportedUnit, resourcePath } from './adapter-utils.mjs';

const SUPPORTED = new Set(['visual:enemy.worm.brawler', 'visual:boss.fatty-one-eye']);

function animationDocument(visual) {
  const animations = {};
  for (const [clipId, clip] of Object.entries(visual.clips)) {
    const keyframeTimes = clip.keyframeTimes ?? clip.frames.map((_, index) => index);
    const animation = {
      durationSeconds: clip.durationSeconds ?? clip.frames.length / clip.framesPerSecond,
      framesPerSecond: clip.framesPerSecond,
      loop: clip.loop,
      tracks: [{
        binding: '../Visual',
        property: 'frame',
        keys: clip.frames.map((frame, index) => ({ at: keyframeTimes[index], value: frame })),
      }],
    };
    if (clipId === 'attack-side') animation.events = [{ at: 1, id: 'attack-active', gameplay: true }];
    if (clipId === 'contact-hop') animation.events = [{ at: keyframeTimes.at(-1), id: 'contact-hop-impact', gameplay: true }];
    animations[clipId] = animation;
  }
  if (visual.visualSetId === 'boss.fatty-one-eye') {
    animations.chase = frameAnimation([6, 7, 8, 9, 10, 11], 7.6923076923, true);
    animations.death = frameAnimation([30, 31, 32, 33, 34, 35], 7.6923076923, false);
  }
  return { version: 1, resourceId: `${visual.visualSetId}.animations`, kind: 'animation-library', animations };
}

function frameAnimation(frames, framesPerSecond, loop) {
  return {
    durationSeconds: frames.length / framesPerSecond,
    framesPerSecond,
    loop,
    tracks: [{ binding: '../Visual', property: 'frame', keys: frames.map((value, at) => ({ at, value })) }],
  };
}

export const visualSceneAdapter = {
  async convert({ units, readSource }) {
    const outputs = [];
    for (const unit of units) {
      requireSupportedUnit(unit, SUPPORTED);
      const visual = await readJson(readSource, unit.oldSourcePath);
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
      outputs.push(convertedOutput(unit, resourcePath('visuals', visual.visualSetId, 'animations'), animationDocument(visual), [
        '$.visualSetId', '$.clips',
      ], [
        { path: '$.$schema', owner: unit.oldSourcePath },
        { path: '$.version', owner: unit.oldSourcePath },
        { path: '$.defaults', owner: unit.oldSourcePath },
      ]));
    }
    return outputs;
  },
};
