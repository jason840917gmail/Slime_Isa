import type { AssetId } from '../../infrastructure/assets/manifest';
import type { CollisionShape } from '../../shared/collisionShapes';
import type { VisualLoopMode } from '../characters/types';

export interface ProjectileDefinition {
  readonly $schema?: string;
  readonly version: 1;
  readonly projectileId: string;
  readonly displayName: string;
  readonly assetId: AssetId | string;
  readonly animation?: {
    readonly frames: readonly number[];
    readonly framesPerSecond: number;
    readonly loop: boolean;
    readonly loopMode?: VisualLoopMode;
  };
  readonly body: {
    readonly shape?: CollisionShape;
    readonly width: number;
    readonly height: number;
    readonly radius?: number;
    readonly radiusX?: number;
    readonly radiusY?: number;
    readonly centerOffsetX: number;
    readonly centerOffsetY: number;
  };
  readonly movement: {
    readonly defaultSpeed: number;
    readonly lifetimeMs: number;
    readonly rotateToVelocity: boolean;
  };
}
