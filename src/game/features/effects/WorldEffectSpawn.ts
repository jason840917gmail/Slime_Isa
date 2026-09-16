import type { EffectDirection } from '../../content/effects/types';
import type { WorldEffectPositionTarget } from './WorldEffectPositionAttachment';

export interface WorldEffectSpawnRequest {
  readonly effectId: string;
  readonly direction: EffectDirection;
  readonly x: number;
  readonly y: number;
  readonly depth: number;
  readonly followPositionOf?: WorldEffectPositionTarget;
  readonly followDepthOffset?: number;
}

export type ManagedWorldEffectSpawner = (request: WorldEffectSpawnRequest) => boolean;
