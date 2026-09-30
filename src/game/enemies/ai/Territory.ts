import type { MapEnemyAreaPerimeter } from '../../content/maps/mapFormat';

/**
 * Enemy territory (playtest 2026-09-30): how far an ordinary enemy chases,
 * when it gives up, and how it goes home. It replaces the old "pursue
 * perimeter", which let a player stand just outside it and hit enemies that
 * had gone passive. Ideas from well-known games:
 *
 * - World of Warcraft's leash and evade: a mob pulled too far from home gives
 *   up, walks home, heals to full, and cannot be kited to death; hitting a
 *   mob always pulls it.
 * - Zelda (Breath of the Wild): a lost target is searched for where it was
 *   last seen before the enemy returns to camp.
 * - Souls-like territories: the farther an enemy is from home, the less it
 *   will chase.
 *
 * The rule of thumb is one "leash budget": an enemy keeps chasing while
 * `distance from home + (distance to the player - attack reach) <= leash`.
 * Near home it follows a player far away; at the edge of its leash it only
 * keeps going when the player is almost in reach. It notices the player by
 * sight (aggro range and a clear line of sight: walls, houses and trees block
 * it) or by being hit. Losing sight sends it to the last place it saw the
 * player for `searchMs`, then home. On the way home it ignores the player
 * unless hit from within its leash, and regenerates.
 */

export type TerritoryMode = 'home' | 'engaged' | 'searching' | 'returning';

export interface TerritoryRules {
  /** The leash budget in pixels (distance from home plus how far the player is out of reach). */
  readonly leashRange: number;
  /** How long a lost target is searched for. */
  readonly searchMs: number;
  /** Beyond aggro range times this, a player in sight is still lost. */
  readonly loseSightMultiplier: number;
  /** Walking home and to the search spot, relative to the chase speed. */
  readonly returnSpeedMultiplier: number;
  /** Health regenerated per second while going home, as a fraction of max health. */
  readonly regenPerSecond: number;
}

export const DEFAULT_TERRITORY_RULES: TerritoryRules = Object.freeze({
  leashRange: 520,
  searchMs: 3000,
  loseSightMultiplier: 1.5,
  returnSpeedMultiplier: 1.3,
  regenPerSecond: 0.35,
});

/** Rules for one enemy: the leash grows with its sight, so far-seeing enemies chase farther. */
export function territoryRulesFor(aggroRange: number, leashRange?: number): TerritoryRules {
  return { ...DEFAULT_TERRITORY_RULES, leashRange: leashRange ?? Math.max(DEFAULT_TERRITORY_RULES.leashRange, aggroRange * 2) };
}

export interface TerritoryMemory {
  mode: TerritoryMode;
  lastSeen?: { x: number; y: number };
  searchUntil: number;
}

export function createTerritoryMemory(): TerritoryMemory {
  return { mode: 'home', searchUntil: 0 };
}

export interface TerritoryInput {
  readonly now: number;
  readonly enemy: Readonly<{ x: number; y: number }>;
  /** Undefined when there is no live target. */
  readonly player?: Readonly<{ x: number; y: number }>;
  /** The camp's wander area. */
  readonly home: MapEnemyAreaPerimeter;
  readonly aggroRange: number;
  /** How close the enemy must be to hit (melee range, or a ranged enemy's firing range). */
  readonly attackReach: number;
  /** Nothing solid stands between the enemy and the player. */
  readonly seesPlayer: boolean;
  /** The enemy took damage since the last step. */
  readonly hurt: boolean;
}

export interface TerritoryDecision {
  readonly mode: TerritoryMode;
  /** Walk here instead of running the combat AI (the search spot or home). */
  readonly moveTo?: Readonly<{ x: number; y: number }>;
  /** Stand still and look around (searching, at the spot). */
  readonly hold?: boolean;
  /** The combat AI may start a chase this step. */
  readonly mayEngage: boolean;
  /** Regenerate health this step (going home). */
  readonly regenerate: boolean;
  /** Back home after giving up: health returns to full. */
  readonly restoreHealth?: boolean;
}

/** Distance from a point to the home area (0 inside it). */
export function homeDistance(home: MapEnemyAreaPerimeter, point: Readonly<{ x: number; y: number }>): number {
  if (home.shape === 'circle') return Math.max(0, Math.hypot(point.x - home.x, point.y - home.y) - home.radius);
  const dx = Math.max(home.x - point.x, 0, point.x - (home.x + home.w));
  const dy = Math.max(home.y - point.y, 0, point.y - (home.y + home.h));
  return Math.hypot(dx, dy);
}

export function homeCenter(home: MapEnemyAreaPerimeter): { x: number; y: number } {
  return home.shape === 'circle' ? { x: home.x, y: home.y } : { x: home.x + home.w / 2, y: home.y + home.h / 2 };
}

/** The leash formula: whether chasing the player is still worth it from here. */
export function withinLeash(rules: TerritoryRules, fromHome: number, distanceToPlayer: number, attackReach: number): boolean {
  return fromHome + Math.max(0, distanceToPlayer - attackReach) <= rules.leashRange;
}

const ARRIVED = 18;

/** One step of the territory rules; updates `memory` and says what the enemy should do. */
export function stepTerritory(memory: TerritoryMemory, input: TerritoryInput, rules: TerritoryRules): TerritoryDecision {
  const { player, enemy } = input;
  const fromHome = homeDistance(input.home, enemy);
  const distance = player ? Math.hypot(player.x - enemy.x, player.y - enemy.y) : Number.POSITIVE_INFINITY;
  const reachable = !!player && withinLeash(rules, fromHome, distance, input.attackReach);
  const inSight = !!player && input.seesPlayer && distance <= input.aggroRange;
  const engage = (): TerritoryDecision => {
    memory.mode = 'engaged';
    if (player) memory.lastSeen = { x: player.x, y: player.y };
    return { mode: 'engaged', mayEngage: true, regenerate: false };
  };
  const goHome = (): TerritoryDecision => {
    memory.mode = 'returning';
    return { mode: 'returning', moveTo: homeCenter(input.home), mayEngage: false, regenerate: true };
  };
  const search = (): TerritoryDecision => {
    if (memory.mode !== 'searching') memory.searchUntil = input.now + rules.searchMs;
    memory.mode = 'searching';
    const spot = memory.lastSeen;
    if (spot && Math.hypot(spot.x - enemy.x, spot.y - enemy.y) > ARRIVED && homeDistance(input.home, spot) <= rules.leashRange) {
      return { mode: 'searching', moveTo: spot, mayEngage: false, regenerate: false };
    }
    return { mode: 'searching', hold: true, mayEngage: false, regenerate: false };
  };

  switch (memory.mode) {
    case 'home': {
      if ((inSight || input.hurt) && reachable) return engage();
      // Knocked or wandered out of its area: walk back in.
      if (fromHome > ARRIVED) return goHome();
      return { mode: 'home', mayEngage: false, regenerate: false };
    }
    case 'engaged': {
      if (!player || !reachable) return goHome();
      const lost = !input.seesPlayer || distance > input.aggroRange * rules.loseSightMultiplier;
      if (lost && !input.hurt) return search();
      return engage();
    }
    case 'searching': {
      if ((inSight || input.hurt) && reachable) return engage();
      if (input.now >= memory.searchUntil) return goHome();
      return search();
    }
    case 'returning': {
      // Only a hit from within its leash turns it around; sight alone does not.
      if (input.hurt && reachable) return engage();
      if (fromHome <= 0) {
        memory.mode = 'home';
        memory.lastSeen = undefined;
        return { mode: 'home', mayEngage: false, regenerate: true, restoreHealth: true };
      }
      return goHome();
    }
  }
}
