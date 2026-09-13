export const ENEMY_EFFECT_IMMUNITIES = ['knockback'] as const;

export type EnemyEffectImmunity = typeof ENEMY_EFFECT_IMMUNITIES[number];

export function isEnemyEffectImmunity(value: unknown): value is EnemyEffectImmunity {
  return typeof value === 'string'
    && (ENEMY_EFFECT_IMMUNITIES as readonly string[]).includes(value);
}

export function normalizeEnemyEffectImmunities(
  value: readonly EnemyEffectImmunity[] | undefined,
): readonly EnemyEffectImmunity[] {
  return value ? [...new Set(value)] : [];
}

export function isEnemyEffectImmune(
  immunities: readonly EnemyEffectImmunity[] | undefined,
  effect: EnemyEffectImmunity,
): boolean {
  return immunities?.includes(effect) ?? false;
}
