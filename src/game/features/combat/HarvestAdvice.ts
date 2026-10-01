/** What a tree, rock or other resource node needs to be harvested. */
export interface HarvestNeed {
  readonly targetTag: string;
  readonly minimumTier: number;
}

/** A weapon's harvest tiers by resource tag (`weapon.json` `harvestCapabilities`). */
export type HarvestCapabilities = Readonly<Record<string, number>> | undefined;

/**
 * Where the right tool is when the weapon in hand cannot harvest a node (the
 * weapon in hand always swings since the 2026-10-01 playtest): `belt` when a
 * belt weapon can (switch to it), `bag` when only one in the bag can (put it on
 * the belt), undefined when the player owns none.
 */
export function harvestToolAdvice(
  need: HarvestNeed,
  beltWeaponIds: readonly string[],
  bagWeaponIds: readonly string[],
  capabilitiesOf: (weaponId: string) => HarvestCapabilities,
): 'belt' | 'bag' | undefined {
  const harvests = (weaponId: string): boolean => (capabilitiesOf(weaponId)?.[need.targetTag] ?? 0) >= need.minimumTier;
  if (beltWeaponIds.some(harvests)) return 'belt';
  if (bagWeaponIds.some(harvests)) return 'bag';
  return undefined;
}
