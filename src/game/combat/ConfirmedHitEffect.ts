import type { DamageApplicationResult } from './DamageableTarget';

export function shouldSpawnConfirmedHitEffect(effectId: string | undefined, result: DamageApplicationResult): boolean {
  return Boolean(effectId && result.status === 'accepted' && result.actualDamage > 0);
}
