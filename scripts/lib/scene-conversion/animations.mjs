import { convertedOutput, readJson, requireSupportedUnit, resourcePath } from './adapter-utils.mjs';

export const animationPackageSceneAdapter = {
  async convert({ units, readSource }) {
    return Promise.all(units.map(async (unit) => {
      const source = await readJson(readSource, unit.oldSourcePath);
      if (source.animationId !== unit.stableId || source.version !== 1 || !source.animation) {
        throw new Error(`Shared animation '${unit.key}' does not match its conversion ledger identity`);
      }
      return convertedOutput(unit, resourcePath('animations', unit.stableId, 'package'), {
        version: 1,
        resourceId: `animation.${unit.stableId}`,
        kind: 'animation-library',
        animations: { package: source },
      }, ['$.animationId', '$.displayName', '$.description', '$.animation', '$.version', '$.$schema']);
    }));
  },
};

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
    if (clip.loopMode && visual.visualSetId.startsWith('character.npc.')) animation.loopMode = clip.loopMode;
    if (clipId === 'attack-side') animation.events = [{ at: 1, id: 'attack-active', gameplay: true }];
    if (clipId === 'contact-hop') animation.events = [{ at: keyframeTimes.at(-1), id: 'contact-hop-impact', gameplay: true }];
    animations[visual.visualSetId === 'effect.enemy.worm-brawler-hit' && clipId === 'hit' ? 'right' : clipId] = animation;
  }
  if (visual.visualSetId === 'boss.fatty-one-eye') {
    animations.chase = frameAnimation([6, 7, 8, 9, 10, 11], 7.6923076923, true);
    animations['small-hop'] = frameAnimation([12, 13, 14, 15], 4 / 0.26, true);
    animations.airborne = frameAnimation([18, 19, 20, 21, 22, 23], 6, false);
    animations.landing = frameAnimation([24, 25, 26, 27], 4 / 0.36, false);
    animations.recovery = frameAnimation([28, 29], 2 / 0.7, true);
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

function enemyImpactScene(visual) {
  const prefix = visual.visualSetId;
  return {
    version: 1,
    sceneId: 'effect.enemy-worm-brawler-hit',
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'EnemyWormBrawlerHit', type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
      {
        id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'root', order: 0,
        properties: {
          texture: { resourceId: `${prefix}.sprite` }, frame: 0, origin: visual.defaults.origin,
          position: visual.defaults.sourceOffset, scale: visual.defaults.scale, rotation: 0, alpha: 1,
          depthMode: 'world-sorted', depthBand: 'reveal-effects',
        },
      },
      {
        id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'root', order: 1,
        properties: { library: { resourceId: `${prefix}.animations` }, domain: 'physics', autoplay: 'right' },
      },
      {
        id: 'script', name: 'EffectScript', type: 'ScriptNode', scriptId: 'game.effect', parentId: 'root', order: 2,
        properties: { effectId: 'enemy-worm-brawler-hit', animation: { nodeId: 'animation' }, lifetimeMs: 250 },
      },
    ],
    instances: [],
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
      if (visual.visualSetId === 'effect.enemy.worm-brawler-hit') {
        outputs.push(convertedOutput(unit, 'effects/enemy-worm-brawler-hit.scene.json', enemyImpactScene(visual), [
          '$.visualSetId', '$.assetId', '$.defaults', '$.clips',
        ], [{ path: '$.$schema', owner: unit.oldSourcePath }, { path: '$.version', owner: unit.oldSourcePath }]));
      }
    }
    return outputs;
  },
};
