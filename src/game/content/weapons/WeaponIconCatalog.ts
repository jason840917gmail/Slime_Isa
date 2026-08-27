import proceduralWeaponIcons from './procedural-weapon-icons.json';
import { buildCharacterStudioAssetCatalog, type CharacterStudioAssetManifestInput } from '../characters/characterAssetCatalog';
import { resolveWeaponIcon, type WeaponIconDefinitionLike } from './WeaponIcon';

export type WeaponIconCatalogKind = 'image' | 'spritesheet' | 'procedural';

export interface WeaponIconCatalogEntry {
  readonly textureKey: string;
  readonly kind: WeaponIconCatalogKind;
  readonly frameCount: number;
}

export type WeaponIconCatalog = ReadonlyMap<string, WeaponIconCatalogEntry>;

export interface StudioWeaponIconAssetEntry {
  readonly kind: 'image' | 'spritesheet';
  readonly textureKey: string;
  readonly tags: readonly string[];
  readonly status?: string;
  readonly frame?: { readonly count: number };
}

interface UnknownRecord {
  readonly [key: string]: unknown;
}

export const proceduralWeaponIconChoices = Object.freeze(
  Object.entries(proceduralWeaponIcons).map(([id, textureKey]) => Object.freeze({ id, textureKey })),
);
const proceduralKeys = proceduralWeaponIconChoices.map((choice) => choice.textureKey);

function isRecord(value: unknown): value is UnknownRecord {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function positiveInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value > 0;
}

function withProceduralEntries(entries: Map<string, WeaponIconCatalogEntry>): WeaponIconCatalog {
  for (const textureKey of proceduralKeys) {
    if (!entries.has(textureKey)) entries.set(textureKey, { textureKey, kind: 'procedural', frameCount: 1 });
  }
  return entries;
}

export function weaponIconCatalogFromStudio(entries: readonly StudioWeaponIconAssetEntry[]): WeaponIconCatalog {
  const catalog = new Map<string, WeaponIconCatalogEntry>();
  for (const entry of entries) {
    if (!entry.textureKey.trim() || !entry.tags.includes('weapon') || (entry.status !== undefined && entry.status !== 'ready')) continue;
    const frameCount = entry.kind === 'image' ? 1 : entry.frame?.count;
    if (!positiveInteger(frameCount)) continue;
    catalog.set(entry.textureKey, { textureKey: entry.textureKey, kind: entry.kind, frameCount });
  }
  return withProceduralEntries(catalog);
}

export function weaponIconCatalogFromManifest(manifest: unknown): WeaponIconCatalog {
  if (!isRecord(manifest) || !isRecord(manifest.assets)) return withProceduralEntries(new Map());
  const input: CharacterStudioAssetManifestInput = {
    assets: manifest.assets,
    bundles: isRecord(manifest.bundles) ? manifest.bundles : {},
  };
  const normalized = buildCharacterStudioAssetCatalog(input, [], 'manifest');
  return weaponIconCatalogFromStudio(normalized.assets);
}

export function isProceduralWeaponIconKey(textureKey: string): boolean {
  return proceduralKeys.includes(textureKey);
}

export function validateWeaponIconAgainstCatalog(
  definition: WeaponIconDefinitionLike,
  catalog: WeaponIconCatalog,
): string[] {
  const iconKey = typeof definition.iconKey === 'string' ? definition.iconKey.trim() : '';
  if (!iconKey) return ['weapon.iconKey: choose a UI icon before saving'];
  if (typeof definition.iconFrame !== 'number' || !Number.isInteger(definition.iconFrame) || definition.iconFrame < 0) {
    return ['weapon.iconFrame: choose a valid UI icon frame before saving'];
  }
  const selection = resolveWeaponIcon({ iconKey, iconFrame: definition.iconFrame });
  if (!selection) return ['weapon.iconFrame: choose a valid UI icon frame before saving'];
  const entry = catalog.get(selection.iconKey);
  if (!entry) return [`weapon.iconKey: '${selection.iconKey}' is not an available weapon icon texture`];
  if (entry.kind === 'spritesheet') {
    return selection.iconFrame < entry.frameCount
      ? []
      : [`weapon.iconFrame: frame ${selection.iconFrame} is outside '${selection.iconKey}' (${entry.frameCount} frames)`];
  }
  return selection.iconFrame === 0
    ? []
    : [`weapon.iconFrame: ${entry.kind} texture '${selection.iconKey}' must use frame 0`];
}
