import Phaser from 'phaser';

import {
  getVisualSet,
  getVisualSetIds,
  type VisualSetDefinition,
  type VisualSetId,
} from '../../content/visuals/VisualCatalog';
import { getAsset } from '../../infrastructure/assets/manifest';

const registeredByManager = new WeakMap<Phaser.Animations.AnimationManager, Set<string>>();

function registeredKeys(scene: Phaser.Scene): Set<string> {
  const existing = registeredByManager.get(scene.anims);
  if (existing) return existing;
  const keys = new Set<string>();
  registeredByManager.set(scene.anims, keys);
  return keys;
}

export function registerVisualSetAnimations(
  scene: Phaser.Scene,
  visualSetId: VisualSetId,
): void {
  const definition: VisualSetDefinition = getVisualSet(visualSetId);
  const asset = getAsset(definition.assetId);
  const textureKey = asset.runtime.textureKey;
  const ownedKeys = registeredKeys(scene);

  for (const clip of Object.values(definition.clips)) {
    if (scene.anims.exists(clip.runtimeKey)) {
      if (!ownedKeys.has(clip.runtimeKey)) {
        throw new Error(
          `Visual set '${visualSetId}' cannot register '${clip.runtimeKey}': ` +
          'the Phaser animation key is already owned outside the visual catalog',
        );
      }
      continue;
    }

    const frames = asset.source.kind === 'spritesheet'
      ? clip.frames.map((frame) => ({ key: textureKey, frame }))
      : clip.frames.map(() => ({ key: textureKey }));

    scene.anims.create({
      key: clip.runtimeKey,
      frames,
      frameRate: clip.framesPerSecond,
      repeat: clip.loop ? -1 : 0,
      yoyo: clip.loop && clip.loopMode === 'ping-pong',
    });
    ownedKeys.add(clip.runtimeKey);
  }
}

export function registerAllVisualSetAnimations(scene: Phaser.Scene): void {
  for (const visualSetId of getVisualSetIds()) {
    registerVisualSetAnimations(scene, visualSetId);
  }
}
