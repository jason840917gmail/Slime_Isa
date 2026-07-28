export type CharacterStudioAssetKind = 'image' | 'spritesheet';
export type CharacterStudioAssetStatus = 'draft' | 'ready' | 'deprecated';

export interface CharacterStudioAssetFrame {
  readonly width: number;
  readonly height: number;
  readonly columns: number;
  readonly rows: number;
  readonly count: number;
}

export interface CharacterStudioAssetDimensions {
  readonly width: number;
  readonly height: number;
}

export interface CharacterStudioAssetEntry {
  readonly assetId: string;
  readonly kind: CharacterStudioAssetKind;
  readonly sourcePath: string;
  readonly textureKey: string;
  readonly status: CharacterStudioAssetStatus;
  readonly tags: readonly string[];
  readonly bundles: readonly string[];
  readonly dimensions: CharacterStudioAssetDimensions;
  readonly frame?: CharacterStudioAssetFrame;
  readonly characterIds: readonly string[];
}

export interface CharacterStudioAssetCatalog {
  readonly version: 1;
  readonly revision: string;
  readonly assets: readonly CharacterStudioAssetEntry[];
}

interface RecordValue {
  readonly [key: string]: unknown;
}

export interface CharacterStudioAssetManifestInput {
  readonly assets?: Record<string, unknown>;
  readonly bundles?: Record<string, unknown>;
}

export interface CharacterStudioAssetReference {
  readonly characterId: string;
  readonly assetId: string;
}

function isRecord(value: unknown): value is RecordValue {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function positiveInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value > 0;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === 'string') : [];
}

function dimensionsForSource(source: RecordValue): CharacterStudioAssetDimensions | undefined {
  const expect = isRecord(source.expect) ? source.expect : undefined;
  if (expect && positiveInteger(expect.w) && positiveInteger(expect.h)) {
    return { width: expect.w, height: expect.h };
  }

  const frame = isRecord(source.frame) ? source.frame : undefined;
  if (frame && positiveInteger(frame.w) && positiveInteger(frame.h) && positiveInteger(frame.cols) && positiveInteger(frame.rows)) {
    return { width: frame.w * frame.cols, height: frame.h * frame.rows };
  }

  return undefined;
}

function frameForSource(source: RecordValue): CharacterStudioAssetFrame | undefined {
  if (source.kind !== 'spritesheet' || !isRecord(source.frame)) return undefined;
  const { w, h, cols, rows, count } = source.frame;
  if (!positiveInteger(w) || !positiveInteger(h) || !positiveInteger(cols) || !positiveInteger(rows)) return undefined;
  const capacity = cols * rows;
  const populatedCount = count === undefined ? capacity : count;
  if (!positiveInteger(populatedCount) || populatedCount > capacity) return undefined;
  return { width: w, height: h, columns: cols, rows, count: populatedCount };
}

function sortedUnique(values: readonly string[]): string[] {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}

export function buildCharacterStudioAssetCatalog(
  manifest: CharacterStudioAssetManifestInput,
  references: readonly CharacterStudioAssetReference[],
  revision: string,
): CharacterStudioAssetCatalog {
  const assets = manifest.assets ?? {};
  const bundles = manifest.bundles ?? {};
  const referencesByAsset = new Map<string, string[]>();
  for (const reference of references) {
    const owners = referencesByAsset.get(reference.assetId) ?? [];
    owners.push(reference.characterId);
    referencesByAsset.set(reference.assetId, owners);
  }

  const entries: CharacterStudioAssetEntry[] = [];
  for (const [assetId, value] of Object.entries(assets)) {
    if (!isRecord(value) || !isRecord(value.source) || (value.source.kind !== 'image' && value.source.kind !== 'spritesheet')) continue;
    if (value.status !== 'ready' || typeof value.source.path !== 'string') continue;
    if (!isRecord(value.runtime) || typeof value.runtime.textureKey !== 'string') continue;
    const dimensions = dimensionsForSource(value.source);
    if (!dimensions) continue;
    const frame = frameForSource(value.source);
    const bundleNames = Object.entries(bundles)
      .filter(([, ids]) => Array.isArray(ids) && ids.includes(assetId))
      .map(([bundleName]) => bundleName);
    entries.push({
      assetId,
      kind: value.source.kind,
      sourcePath: value.source.path,
      textureKey: value.runtime.textureKey,
      status: 'ready',
      tags: sortedUnique(stringArray(value.tags)),
      bundles: sortedUnique(bundleNames),
      dimensions,
      ...(frame ? { frame } : {}),
      characterIds: sortedUnique(referencesByAsset.get(assetId) ?? []),
    });
  }

  entries.sort((left, right) => left.assetId.localeCompare(right.assetId));
  return { version: 1, revision, assets: entries };
}
