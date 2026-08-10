import type { AssetId } from '../../infrastructure/assets/manifest';
import type { CollisionShape } from '../../shared/collisionShapes';
import type {
  AnimationClipDocument,
  AnimationEventDocument,
  AnimationJsonValue,
  AnimationLoopMode,
  AnimationTrackDocument as SharedAnimationTrackDocument,
} from '../../shared/animation';

export type CharacterKind = 'player' | 'enemy';
export type Pair = [number, number];
export type VisualLoopMode = AnimationLoopMode;

/** Core character attributes. Movement speed is intentionally not included. */
export interface CharacterAttributeSet {
  strength: number;
  vitality: number;
  agility: number;
  intellect: number;
}

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

export interface VisualClipDocument extends AnimationClipDocument {
  frames: number[];
  keyframeTimes?: number[];
  durationSeconds?: number;
  framesPerSecond: number;
  loop: boolean;
  /** Defaults to wrap for packages authored before ping-pong playback existed. */
  loopMode?: VisualLoopMode;
  /** Optional animation-wide artwork offset between the default and frame-specific offsets. */
  sourceOffset?: Pair;
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
  /** Defaults to rectangle for packages authored before shape support. */
  shape?: CollisionShape;
  width: number;
  height: number;
  radius?: number;
  radiusX?: number;
  radiusY?: number;
  centerOffsetX: number;
  centerOffsetY: number;
}

export interface CharacterHitboxDocument {
  shape: CollisionShape;
  width: number;
  height: number;
  radius?: number;
  radiusX?: number;
  radiusY?: number;
  offsetX: number;
  offsetY: number;
  mirrorX: boolean;
}

export interface HitboxSpanDocument {
  hitboxId: string;
  from: number;
  through: number;
}

export type JsonValue = AnimationJsonValue;

export interface CharacterEventDocument extends AnimationEventDocument {
  payload?: JsonValue;
}

export interface AnimationTrackDocument extends SharedAnimationTrackDocument {
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
    behavior?: 'standard' | 'slime-spider';
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
    projectileId?: string;
    assetId?: AssetId | string;
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
  attributes?: CharacterAttributeSet;
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
