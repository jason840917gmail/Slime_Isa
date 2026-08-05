import type { AssetId } from '../../infrastructure/assets/manifest';
import type { CollisionShape } from '../../shared/collisionShapes';
import type { VisualLoopMode } from '../characters/types';

export interface ProjectileDefinition {
  readonly $schema?: string;
  readonly version: 1;
  readonly projectileId: string;
  readonly displayName: string;
  readonly assetId: AssetId | string;
  /** Legacy single-clip shape retained for authored packages from before v2. */
  readonly animation?: ProjectileAnimationDocument;
  readonly animations?: ProjectileAnimationSet;
  /** Render-only artwork alignment. It never changes the projectile body anchor. */
  readonly visual?: ProjectileVisualDocument;
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

export interface ProjectileVisualDocument {
  readonly sourceOffset: readonly [number, number];
  readonly frameOffsets?: Readonly<Record<string, readonly [number, number]>>;
}

export interface ProjectileAnimationDocument {
  readonly frames: readonly number[];
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: VisualLoopMode;
}

export interface ProjectileAnimationSet {
  readonly move: ProjectileAnimationDocument;
  readonly impact: ProjectileAnimationDocument;
}
