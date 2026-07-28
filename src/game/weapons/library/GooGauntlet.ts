import { Weapon, type WeaponDef, type WeaponContext } from '../../combat/Weapon';

/**
 * Goo Gauntlet â€” the starter melee weapon. Short-range punch combo with
 * knockback. Unlocked from level 1.
 */
const DEFS: Record<'goo-gauntlet', WeaponDef> = {
  'goo-gauntlet': {
    id: 'goo-gauntlet',
    name: 'Goo Gauntlet',
    animKey: 'slime-trick',
    baseDamage: 12,
    cooldownMs: 320,
    hitboxWidth: 64,
    hitboxHeight: 56,
    hitboxOffset: 36,
    hitboxDurationMs: 140,
    knockStrength: 200,
    vfxColor: 0x86f0c3,
    unlockLevel: 1,
    iconKey: 'weapon-gauntlet',
    description: 'A gooey punch. Short range, solid knockback. Your starter weapon.',
  },
};

export function createGooGauntlet(ctx: WeaponContext): Weapon {
  return new Weapon(DEFS['goo-gauntlet'], ctx);
}

export const GOO_GAUNTLET_DEF = DEFS['goo-gauntlet'];
