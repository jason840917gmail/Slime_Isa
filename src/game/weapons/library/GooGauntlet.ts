import { Weapon, type WeaponContext } from '../../combat/Weapon';
import { getWeaponDefinition } from '../../content/weapons/WeaponCatalog';

/** Goo Gauntlet — the starter melee weapon. */
export function createGooGauntlet(ctx: WeaponContext): Weapon {
  return new Weapon(getWeaponDefinition('goo-gauntlet'), ctx);
}

export const GOO_GAUNTLET_DEF = getWeaponDefinition('goo-gauntlet');
