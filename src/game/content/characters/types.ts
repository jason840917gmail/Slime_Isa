import type { AssetId } from '../../infrastructure/assets/manifest';

export type CharacterKind = 'player' | 'enemy';
export type Pair = [number, number];

export interface VisualTransformDocument {
  origin?: Pair;
  scale?: Pair;
  sourceOffset?: Pair;
}

export interface VisualDefaultsDocument {
  origin: Pair;
  scale: Pair;
  sourceOffset: Pair;
}

export interface VisualClipDocument {
  frames: number[];
  framesPerSecond: number;
  loop: boolean;
}

export interface VisualSetDocument {
  $schema?: string;
  version: 1;
  visualSetId: string;
  assetId: AssetId | string;
  defaults: VisualDefaultsDocument;
  frameVisuals?: Record<string, VisualTransformDocument>;
  clips: Record<string, VisualClipDocument>;
}

export interface CharacterBodyDocument {
  width: number;
  height: number;
  centerOffsetX: number;
  centerOffsetY: number;
}

export interface CharacterHitboxDocument {
  shape: 'rectangle';
  width: number;
  height: number;
  offsetX: number;
  offsetY: number;
  mirrorX: boolean;
}

export interface HitboxSpanDocument {
  hitboxId: string;
  from: number;
  through: number;
}

export type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue };

export interface CharacterEventDocument {
  at: number;
  eventId: string;
  payload?: JsonValue;
}

export interface AnimationTrackDocument {
  hitboxSpans?: HitboxSpanDocument[];
  events?: CharacterEventDocument[];
}

export interface PlayerGameplayDocument {
  name: string;
  movement: {
    baseSpeed: number;
    boostSpeed: number;
    dodgeSpeed: number;
    dodgeInvulnerabilityMs: number;
  };
  progression: {
    baseMaxHp: number;
    baseMaxEnergy: number;
    hpPerLevel: number;
    attackPerLevel: number;
    defensePerLevel: number;
    energyPerLevel: number;
  };
}

export interface EnemyDropItemDocument {
  itemId: string;
  chance: number;
  count?: number;
}

export interface EnemyGameplayDocument {
  maxHp: number;
  ai: {
    aggroRange: number;
    attackRange: number;
    leapRange?: number;
    fleeRange?: number;
    wanderSpeed: number;
    chaseSpeed: number;
    attackCooldownMs: number;
    attackWindupMs: number;
    attackRecoveryMs: number;
    contactDamage: number;
    knockbackStrength: number;
    isRanged: boolean;
    isLeaper?: boolean;
    projectileSpeed?: number;
    knockbackResist: number;
  };
  drop: {
    xp: number;
    coins: number;
    items?: EnemyDropItemDocument[];
  };
  projectile?: {
    assetId: AssetId | string;
    damage: number;
  };
  impactEffect?: {
    visualSetId: string;
    clipId: string;
    distance: number;
  };
}

export interface CharacterDocument {
  $schema?: string;
  version: 1;
  characterId: string;
  displayName: string;
  kind: CharacterKind;
  runtimeRole?: 'primary-player';
  visualSetId: string;
  body: CharacterBodyDocument;
  hitboxes: Record<string, CharacterHitboxDocument>;
  animationTracks: Record<string, AnimationTrackDocument>;
  player?: PlayerGameplayDocument;
  enemy?: EnemyGameplayDocument;
}

export interface CharacterPackage {
  character: CharacterDocument;
  visualSet: VisualSetDocument;
}

export interface CharacterCatalogEntry extends CharacterPackage {
  revision?: string;
}
