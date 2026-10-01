/** What a tree, rock or other resource node needs to be harvested. */
export interface HarvestNeed {
  readonly targetTag: string;
  readonly minimumTier: number;
}

/** A weapon's harvest tiers by resource tag (`weapon.json` `harvestCapabilities`). */
export type HarvestCapabilities = Readonly<Record<string, number>> | undefined;

/**
 * Tools pick themselves (roadmap 4.10): the weapon to swing at a node that
 * needs harvesting. Undefined when the equipped weapon can already harvest it,
 * or when no owned weapon can (the equipped weapon swings and the node says
 * what it needs). Otherwise the owned weapon with the highest tier for the
 * node's tag.
 */
export function harvestToolFor(
  need: HarvestNeed,
  equippedWeaponId: string | null,
  ownedWeaponIds: readonly string[],
  capabilitiesOf: (weaponId: string) => HarvestCapabilities,
): string | undefined {
  const tier = (weaponId: string): number => capabilitiesOf(weaponId)?.[need.targetTag] ?? 0;
  if (equippedWeaponId && tier(equippedWeaponId) >= need.minimumTier) return undefined;
  let best: string | undefined;
  for (const weaponId of ownedWeaponIds) {
    if (tier(weaponId) < need.minimumTier) continue;
    if (!best || tier(weaponId) > tier(best)) best = weaponId;
  }
  return best;
}
