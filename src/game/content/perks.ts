export const PERK_IDS = [
  'tanky-goo',
  'sharp-fangs',
  'thick-skin',
  'quick-steps',
  'lucky-crit',
  'deep-well',
  'quick-recovery',
  'vampiric-goo',
] as const;

export type PerkId = typeof PERK_IDS[number];

export interface PerkDef {
  id: PerkId;
  title: string;
  description: string;
  icon: string;
  maxRank: number;
}

export const PERK_DEFS: Readonly<Record<PerkId, PerkDef>> = {
  'tanky-goo': { id: 'tanky-goo', title: 'Tanky Goo', description: '+15 max HP per rank', icon: 'perk-tanky', maxRank: 3 },
  'sharp-fangs': { id: 'sharp-fangs', title: 'Sharp Fangs', description: '+15% attack per rank', icon: 'perk-fangs', maxRank: 3 },
  'thick-skin': { id: 'thick-skin', title: 'Thick Skin', description: '-8% damage taken per rank', icon: 'perk-skin', maxRank: 3 },
  'quick-steps': { id: 'quick-steps', title: 'Quick Steps', description: '+25 move speed per rank', icon: 'perk-quick', maxRank: 3 },
  'lucky-crit': { id: 'lucky-crit', title: 'Lucky Crit', description: '+8% crit chance per rank', icon: 'perk-crit', maxRank: 3 },
  'deep-well': { id: 'deep-well', title: 'Deep Well', description: '+20 max energy per rank', icon: 'perk-well', maxRank: 3 },
  'quick-recovery': { id: 'quick-recovery', title: 'Quick Recovery', description: '+50% energy regen per rank', icon: 'perk-recovery', maxRank: 3 },
  'vampiric-goo': { id: 'vampiric-goo', title: 'Vampiric Goo', description: '+6% life steal per rank on enemy hits', icon: 'perk-lifesteal', maxRank: 3 },
};

export const PERK_BALANCE = {
  maxHpPerTankyGooRank: 15,
  attackMultiplierPerSharpFangsRank: 0.15,
  damageReductionPerThickSkinRank: 0.08,
  speedPerQuickStepsRank: 25,
  critChancePerLuckyCritRank: 0.08,
  maxEnergyPerDeepWellRank: 20,
  energyRegenMultiplierPerQuickRecoveryRank: 0.5,
  lifeStealPerVampiricGooRank: 0.06,
} as const;
