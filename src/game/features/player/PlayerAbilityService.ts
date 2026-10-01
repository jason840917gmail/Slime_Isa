import {
  PLAYER_ABILITY_DEFINITIONS,
  type PlayerAbilityDefinition,
  type PlayerAbilityId,
} from './PlayerAbilityDefinitions';

export interface AbilityVector {
  readonly x: number;
  readonly y: number;
}

export interface PlayerAbilityStatePort {
  /** Whether the story has taught this ability (quest or boss reward). */
  isLearned(abilityId: PlayerAbilityId): boolean;
  getEnergy(): number;
  isActionLocked(): boolean;
  setActionLocked(locked: boolean): void;
  spendEnergy(amount: number): boolean;
}

export interface PlayerAbilityTerrainPort {
  /** Ground the slime cannot stand on there (water, cliffs, outside the world). */
  isBlocked(x: number, y: number): boolean;
  /** A solid object (wall, house, tree) would overlap the slime standing there. */
  isOccupied?(x: number, y: number): boolean;
}

export interface PlayerAbilityServiceOptions {
  readonly nowMs: () => number;
  readonly state: PlayerAbilityStatePort;
  readonly terrain: PlayerAbilityTerrainPort;
}

export interface PlayerAbilityRequest {
  readonly position: AbilityVector;
  readonly direction: AbilityVector;
  readonly facing: AbilityVector;
  /** Teleport only: land no farther than this (the pointer's distance), within the ability's range. */
  readonly reach?: number;
}

export type PlayerAbilityRejectionReason = 'busy' | 'locked' | 'cooldown' | 'action-locked' | 'energy' | 'blocked';

export interface PlayerAbilityIntent {
  readonly abilityId: PlayerAbilityId;
  readonly sequenceId: number;
  readonly direction: AbilityVector;
  readonly start: AbilityVector;
  readonly target: AbilityVector;
  readonly definition: PlayerAbilityDefinition;
  readonly cooldownUntilMs: number;
}

export type PlayerAbilityDecision =
  | { readonly accepted: true; readonly intent: PlayerAbilityIntent }
  | { readonly accepted: false; readonly reason: PlayerAbilityRejectionReason };

export class PlayerAbilityService {
  private readonly cooldownUntil: Record<PlayerAbilityId, number> = {
    jump: 0,
    dodge: 0,
    teleport: 0,
    'squash-slam': 0,
    'stretch-lash': 0,
  };
  private activeSequenceId?: number;
  private nextSequenceId = 1;

  constructor(private readonly options: PlayerAbilityServiceOptions) {}

  isUnlocked(abilityId: PlayerAbilityId): boolean {
    return this.options.state.isLearned(abilityId);
  }

  isBusy(): boolean {
    return this.activeSequenceId !== undefined;
  }

  /**
   * An ability with no presented sequence (the dodge roll moves the body
   * itself): checks the same rules as `tryBegin`, then only starts its
   * cooldown and spends its energy. The caller performs it.
   */
  tryInstant(abilityId: PlayerAbilityId): PlayerAbilityRejectionReason | undefined {
    const rejection = this.rejection(abilityId);
    if (rejection) return rejection;
    const definition = PLAYER_ABILITY_DEFINITIONS[abilityId];
    if (definition.energyCost > 0 && !this.options.state.spendEnergy(definition.energyCost)) return 'energy';
    this.cooldownUntil[abilityId] = this.options.nowMs() + definition.cooldownMs;
    return undefined;
  }

  private rejection(abilityId: PlayerAbilityId): PlayerAbilityRejectionReason | undefined {
    if (this.isBusy()) return 'busy';
    if (!this.isUnlocked(abilityId)) return 'locked';
    if (this.options.nowMs() < this.cooldownUntil[abilityId]) return 'cooldown';
    if (this.options.state.isActionLocked()) return 'action-locked';
    if (this.options.state.getEnergy() < PLAYER_ABILITY_DEFINITIONS[abilityId].energyCost) return 'energy';
    return undefined;
  }

  tryBegin(abilityId: PlayerAbilityId, request: PlayerAbilityRequest): PlayerAbilityDecision {
    const definition = PLAYER_ABILITY_DEFINITIONS[abilityId];
    const rejection = this.rejection(abilityId);
    if (rejection) return { accepted: false, reason: rejection };
    const nowMs = this.options.nowMs();

    const direction = normalizeDirection(request.direction, request.facing, abilityId === 'stretch-lash' ? { x: 1, y: 0 } : { x: 0, y: -1 });
    const moving = Math.hypot(request.direction.x, request.direction.y) > 0;
    let target: AbilityVector = { ...request.position };
    if (abilityId === 'jump' && moving) {
      target = this.trace(request.position, direction, definition.distance ?? 0, true);
    } else if (abilityId === 'teleport') {
      const range = definition.distance ?? 0;
      const reach = request.reach === undefined || !Number.isFinite(request.reach) ? range : Math.min(range, Math.max(0, request.reach));
      const landing = this.safeLanding(request.position, direction, reach);
      if (!landing) return { accepted: false, reason: 'blocked' };
      target = landing;
    }
    if (definition.energyCost > 0 && !this.options.state.spendEnergy(definition.energyCost)) {
      return { accepted: false, reason: 'energy' };
    }

    const sequenceId = this.nextSequenceId++;
    const cooldownUntilMs = nowMs + definition.cooldownMs;
    this.cooldownUntil[abilityId] = cooldownUntilMs;
    this.activeSequenceId = sequenceId;
    this.options.state.setActionLocked(true);
    return {
      accepted: true,
      intent: {
        abilityId,
        sequenceId,
        direction,
        start: { ...request.position },
        target,
        definition,
        cooldownUntilMs,
      },
    };
  }

  complete(sequenceId: number): boolean {
    if (this.activeSequenceId !== sequenceId) return false;
    this.activeSequenceId = undefined;
    this.options.state.setActionLocked(false);
    return true;
  }

  cancel(): void {
    if (this.activeSequenceId === undefined) return;
    this.activeSequenceId = undefined;
    this.options.state.setActionLocked(false);
  }

  readyAt(abilityId: PlayerAbilityId): number {
    return this.cooldownUntil[abilityId];
  }

  /**
   * The farthest spot along `direction`, up to `maxDistance`, where the slime
   * can stand: walkable ground with no solid object in the way. What lies in
   * between (a river, a thin wall) does not matter. Undefined when there is
   * no such spot at least `MIN_TELEPORT_PX` away.
   */
  private safeLanding(start: AbilityVector, direction: AbilityVector, maxDistance: number): AbilityVector | undefined {
    for (let distance = maxDistance; distance >= MIN_TELEPORT_PX; distance -= 8) {
      const x = start.x + direction.x * distance;
      const y = start.y + direction.y * distance;
      if (this.options.terrain.isBlocked(x, y) || this.options.terrain.isOccupied?.(x, y)) continue;
      return { x, y };
    }
    return undefined;
  }

  private trace(start: AbilityVector, direction: AbilityVector, maxDistance: number, ensureJumpMovement: boolean): AbilityVector {
    const steps = Math.ceil(maxDistance / 8);
    let lastValid = { ...start };
    for (let step = 1; step <= steps; step += 1) {
      const distance = (step / steps) * maxDistance;
      const x = start.x + direction.x * distance;
      const y = start.y + direction.y * distance;
      if (this.options.terrain.isBlocked(x, y)) break;
      lastValid = { x, y };
    }
    if (ensureJumpMovement && Math.hypot(lastValid.x - start.x, lastValid.y - start.y) < 8) {
      return { x: start.x + direction.x * 12, y: start.y + direction.y * 12 };
    }
    return lastValid;
  }
}

/** A teleport shorter than this is not worth it: the spell fails instead. */
const MIN_TELEPORT_PX = 32;

function normalizeDirection(direction: AbilityVector, facing: AbilityVector, fallback: AbilityVector): AbilityVector {
  const candidate = Math.hypot(direction.x, direction.y) > 0 ? direction : facing;
  const length = Math.hypot(candidate.x, candidate.y);
  return length > 0 ? { x: candidate.x / length, y: candidate.y / length } : fallback;
}
