import Phaser from 'phaser';

import { interpolatePhysicsPosition } from './CameraMotion';

type PhysicsWorldTiming = Phaser.Physics.Arcade.World & {
  readonly _elapsed?: number;
  readonly _frameTimeMS?: number;
};

export type PhysicsPresentationTarget = Phaser.GameObjects.GameObject & {
  readonly x: number;
  readonly y: number;
  readonly body?: unknown;
};

export function physicsPresentationAlpha(scene: Phaser.Scene): number {
  const world = scene.physics?.world as PhysicsWorldTiming | undefined;
  if (!world || !world.fixedStep || world.isPaused) return 1;
  const frameTimeMs = world._frameTimeMS;
  const elapsed = world._elapsed;
  if (!Number.isFinite(frameTimeMs) || !frameTimeMs || !Number.isFinite(elapsed)) return 1;
  return Phaser.Math.Clamp((elapsed ?? 0) / frameTimeMs, 0, 1);
}

export function resolvePhysicsPresentationPosition(
  scene: Phaser.Scene,
  target: PhysicsPresentationTarget,
  out = new Phaser.Math.Vector2(),
): Phaser.Math.Vector2 {
  const body = target.body;
  if (!(body instanceof Phaser.Physics.Arcade.Body) || !body.enable || !body.moves) {
    return out.set(target.x, target.y);
  }

  const position = interpolatePhysicsPosition(
    target,
    { x: body.deltaX(), y: body.deltaY() },
    physicsPresentationAlpha(scene),
  );
  return out.set(position.x, position.y);
}
