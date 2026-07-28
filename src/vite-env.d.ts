interface CharacterStudioVisualSet {
  version: 1;
  visualSetId: string;
  assetId: string;
  defaults: { origin: [number, number]; scale: [number, number]; sourceOffset: [number, number] };
  frameVisuals?: Record<string, { origin?: [number, number]; scale?: [number, number]; sourceOffset?: [number, number] }>;
  clips: Record<string, { frames: number[]; framesPerSecond: number; loop: boolean }>;
}

interface CharacterStudioCharacter {
  version: 1;
  characterId: string;
  displayName: string;
  kind: 'player' | 'enemy';
  runtimeRole?: 'primary-player';
  visualSetId: string;
  body: { width: number; height: number; centerOffsetX: number; centerOffsetY: number };
  hitboxes: Record<string, { shape: 'rectangle'; width: number; height: number; offsetX: number; offsetY: number; mirrorX: boolean }>;
  animationTracks: Record<string, { hitboxSpans?: Array<{ hitboxId: string; from: number; through: number }>; events?: Array<{ at: number; eventId: string; payload?: unknown }> }>;
  player?: { name: string; movement: { baseSpeed: number; boostSpeed: number; dodgeSpeed: number; dodgeInvulnerabilityMs: number }; progression: { baseMaxHp: number; baseMaxEnergy: number; hpPerLevel: number; attackPerLevel: number; defensePerLevel: number; energyPerLevel: number } };
  enemy?: { maxHp: number; ai: { aggroRange: number; attackRange: number; wanderSpeed: number; chaseSpeed: number; attackCooldownMs: number; attackWindupMs: number; attackRecoveryMs: number; contactDamage: number; knockbackStrength: number; isRanged: boolean; knockbackResist: number; leapRange?: number; fleeRange?: number; isLeaper?: boolean; projectileSpeed?: number }; drop: { xp: number; coins: number; items?: Array<{ itemId: string; chance: number; count?: number }> }; projectile?: { assetId: string; damage: number }; impactEffect?: { visualSetId: string; clipId: string; distance: number } };
}

declare module 'virtual-character-content' {
  export const characterPackages: ReadonlyArray<{ readonly characterId: string; readonly character: CharacterStudioCharacter; readonly visualSet: CharacterStudioVisualSet }>;
  export const visualSets: readonly CharacterStudioVisualSet[];
}
