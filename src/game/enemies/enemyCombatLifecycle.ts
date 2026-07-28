export interface EnemyDamageResult {
  readonly hp: number;
  readonly actualDamage: number;
  readonly defeated: boolean;
}

export interface EnemyAttackLifecycleState {
  readonly active: boolean;
  readonly readyAt: number;
  readonly sequenceId: number;
}

export interface EnemyAttackStartResult {
  readonly started: boolean;
  readonly state: EnemyAttackLifecycleState;
  readonly sequenceId?: number;
}

export function applyEnemyDamage(hp: number, maxHp: number, amount: number): EnemyDamageResult {
  const safeHp = Math.max(0, Math.min(maxHp, hp));
  const nextHp = Math.max(0, safeHp - Math.max(0, amount));
  return {
    hp: nextHp,
    actualDamage: safeHp - nextHp,
    defeated: nextHp <= 0,
  };
}

export function tryBeginEnemyAttack(
  state: EnemyAttackLifecycleState,
  time: number,
  cooldownMs: number,
): EnemyAttackStartResult {
  if (state.active || time < state.readyAt) return { started: false, state };
  const sequenceId = state.sequenceId + 1;
  return {
    started: true,
    sequenceId,
    state: { active: true, readyAt: time + cooldownMs, sequenceId },
  };
}

export function canResolveEnemyAttack(state: EnemyAttackLifecycleState, sequenceId: number): boolean {
  return state.active && state.sequenceId === sequenceId;
}

export function cancelEnemyAttack(state: EnemyAttackLifecycleState): EnemyAttackLifecycleState {
  return { ...state, active: false, sequenceId: state.sequenceId + 1 };
}

export function finishEnemyAttack(
  state: EnemyAttackLifecycleState,
  sequenceId: number,
): EnemyAttackLifecycleState {
  return canResolveEnemyAttack(state, sequenceId)
    ? { ...state, active: false }
    : state;
}
