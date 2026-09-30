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
  isBlocked(x: number, y: number): boolean;
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
}

export type PlayerAbilityRejectionReason = 'busy' | 'locked' | 'cooldown' | 'action-locked' | 'energy';

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

  tryBegin(abilityId: PlayerAbilityId, request: PlayerAbilityRequest): PlayerAbilityDecision {
    const definition = PLAYER_ABILITY_DEFINITIONS[abilityId];
    if (this.isBusy()) return { accepted: false, reason: 'busy' };
    if (!this.isUnlocked(abilityId)) return { accepted: false, reason: 'locked' };
    const nowMs = this.options.nowMs();
    if (nowMs < this.cooldownUntil[abilityId]) return { accepted: false, reason: 'cooldown' };
    if (this.options.state.isActionLocked()) return { accepted: false, reason: 'action-locked' };
    if (this.options.state.getEnergy() < definition.energyCost) return { accepted: false, reason: 'energy' };

    const direction = normalizeDirection(request.direction, request.facing, abilityId === 'stretch-lash' ? { x: 1, y: 0 } : { x: 0, y: -1 });
    const target = abilityId === 'jump' || abilityId === 'teleport'
      ? this.trace(request.position, direction, definition.distance ?? 0, abilityId === 'jump')
      : { ...request.position };
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

function normalizeDirection(direction: AbilityVector, facing: AbilityVector, fallback: AbilityVector): AbilityVector {
  const candidate = Math.hypot(direction.x, direction.y) > 0 ? direction : facing;
  const length = Math.hypot(candidate.x, candidate.y);
  return length > 0 ? { x: candidate.x / length, y: candidate.y / length } : fallback;
}
