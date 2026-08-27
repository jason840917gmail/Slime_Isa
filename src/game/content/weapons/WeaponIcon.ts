export interface WeaponIconDefinitionLike {
  readonly iconKey?: unknown;
  readonly iconFrame?: unknown;
}

export interface WeaponIconSelection {
  readonly iconKey: string;
  readonly iconFrame: number;
}

export interface WeaponIconAssetLike {
  readonly textureKey: string;
}

export function resolveWeaponIcon(definition: WeaponIconDefinitionLike): WeaponIconSelection | undefined {
  const iconKey = typeof definition.iconKey === 'string' ? definition.iconKey.trim() : '';
  if (!iconKey || typeof definition.iconFrame !== 'number' || !Number.isInteger(definition.iconFrame) || definition.iconFrame < 0) {
    return undefined;
  }
  return { iconKey, iconFrame: definition.iconFrame };
}

export function weaponIconSelection(entry: WeaponIconAssetLike, frame: number): WeaponIconSelection {
  const selection = resolveWeaponIcon({ iconKey: entry.textureKey, iconFrame: frame });
  if (!selection) throw new Error('Weapon icon selection requires a texture key and non-negative integer frame');
  return selection;
}
