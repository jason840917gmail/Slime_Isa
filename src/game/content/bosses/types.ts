import type { EnemyEffectImmunity } from '../enemies/EnemyEffects';
import type { AssetId } from '../../infrastructure/assets/manifest';

export interface BossEditorPreview {
  readonly assetId: AssetId;
  readonly textureKey: string;
  readonly frame: number;
  readonly origin: readonly [number, number];
  readonly scale: number;
}

export interface BossDefinition {
  readonly id: string;
  readonly displayName: string;
  readonly characterId: string;
  readonly visualSetId: string;
  readonly visualScale: number;
  readonly editorPreview: {
    readonly assetId: AssetId;
    readonly idleFrame: number;
  };
  readonly maxHp: number;
  readonly body: {
    readonly width: number;
    readonly height: number;
    readonly centerOffsetX: number;
    readonly centerOffsetY: number;
  };
  readonly eye: {
    readonly width: number;
    readonly height: number;
    readonly offsetX: number;
    readonly offsetY: number;
  };
  readonly chaseSpeed: number;
  readonly contactHop: {
    readonly clipId: string;
    readonly hitboxId: string;
    readonly damage: number;
    readonly cooldownMs: number;
    readonly knockbackStrength: number;
  };
  readonly leap: {
    readonly cadenceMs: number;
    readonly smallHopCount: number;
    readonly smallHopDurationMs: number;
    readonly betweenHopsMs: number;
    readonly airTimeMs: number;
    readonly landingRadius: number;
    readonly landingDamage: number;
    readonly landingKnockbackStrength: number;
    readonly recoveryMs: number;
    readonly crackFadeMs: number;
  };
  readonly allowedWeaponIds: readonly string[];
  readonly effectImmunities?: readonly EnemyEffectImmunity[];
}
