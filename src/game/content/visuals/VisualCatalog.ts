import type { AssetId } from '../../infrastructure/assets/manifest';
import { getAsset } from '../../infrastructure/assets/manifest';
import { validateVisualSetDocument } from '../characters/validation';
import { characterPackages, visualSets } from 'virtual-character-content';
import type {
  VisualClipDocument,
  VisualLoopMode,
  VisualSetDocument,
} from '../characters/types';

export interface VisualTransform {
  readonly origin?: readonly [number, number];
  readonly scale?: readonly [number, number];
  readonly sourceOffset?: readonly [number, number];
}

export interface ResolvedVisualTransform {
  readonly origin: readonly [number, number];
  readonly scale: readonly [number, number];
  readonly sourceOffset: readonly [number, number];
}

export interface VisualClip extends Omit<VisualClipDocument, 'loopMode'> {
  readonly loopMode: VisualLoopMode;
  readonly runtimeKey: string;
}

export interface VisualSetDefinition {
  readonly version: 1;
  readonly visualSetId: string;
  readonly assetId: AssetId;
  readonly defaults: {
    readonly origin: readonly [number, number];
    readonly scale: readonly [number, number];
    readonly sourceOffset: readonly [number, number];
  };
  readonly frameVisuals?: Readonly<Record<string, VisualTransform>>;
  readonly clips: Readonly<Record<string, VisualClip>>;
}

export interface VisualDefinitionResolver {
  getVisualSet(visualSetId: string): VisualSetDefinition;
  getClip(visualSetId: string, clipId: string): VisualClip;
  resolveFrameVisual(visualSetId: string, sourceFrame: number): ResolvedVisualTransform;
  runtimeKey(visualSetId: string, clipId: string): string;
}

export function visualRuntimeKey(visualSetId: string, clipId: string): string {
  return `visual:${visualSetId.length}:${visualSetId}:${clipId}`;
}

export const getVisualRuntimeKey = visualRuntimeKey;

function normalizeVisualSet(value: VisualSetDocument): VisualSetDefinition {
  const issues = validateVisualSetDocument(value);
  if (issues.length > 0) throw new Error(issues.map((entry) => `${entry.path}: ${entry.message}`).join('\n'));
  const clips = Object.fromEntries(Object.entries(value.clips).map(([clipId, clip]) => [clipId, {
    ...clip,
    loopMode: clip.loopMode ?? 'wrap',
    runtimeKey: visualRuntimeKey(value.visualSetId, clipId),
  }])) as Record<string, VisualClip>;
  return {
    version: 1,
    visualSetId: value.visualSetId,
    assetId: value.assetId as AssetId,
    defaults: {
      origin: value.defaults.origin,
      scale: value.defaults.scale,
      sourceOffset: value.defaults.sourceOffset,
    },
    frameVisuals: value.frameVisuals,
    clips,
  };
}

const VISUAL_SETS = new Map<string, VisualSetDefinition>();
for (const rawVisualSet of visualSets) {
  const visualSet = normalizeVisualSet(rawVisualSet as unknown as VisualSetDocument);
  if (VISUAL_SETS.has(visualSet.visualSetId)) throw new Error(`Duplicate visual set '${visualSet.visualSetId}'`);
  getAsset(visualSet.assetId);
  VISUAL_SETS.set(visualSet.visualSetId, visualSet);
}

const CHARACTER_VISUAL_IDS = new Set(characterPackages.map((entry) => entry.visualSet.visualSetId));

export type VisualSetId = string;

export function getVisualSet(visualSetId: VisualSetId): VisualSetDefinition {
  const definition = VISUAL_SETS.get(visualSetId);
  if (!definition) throw new Error(`Unknown visual set '${visualSetId}'`);
  return definition;
}

export function getVisualSetIds(): readonly VisualSetId[] {
  return [...VISUAL_SETS.keys()];
}

export function getCharacterVisualSetIds(): readonly string[] {
  return [...CHARACTER_VISUAL_IDS];
}

export function getVisualClip(visualSetId: VisualSetId, clipId: string): VisualClip {
  const clip = getVisualSet(visualSetId).clips[clipId];
  if (!clip) throw new Error(`Visual set '${visualSetId}' has no clip '${clipId}'`);
  return clip;
}

export function findVisualClipByRuntimeKey(visualSetId: VisualSetId, runtimeKey: string): VisualClip | undefined {
  return Object.values(getVisualSet(visualSetId).clips).find((clip) => clip.runtimeKey === runtimeKey);
}

export function resolveFrameVisual(visualSetId: VisualSetId, frameIndex: number): ResolvedVisualTransform {
  const definition = getVisualSet(visualSetId);
  const frame = definition.frameVisuals?.[String(frameIndex)];
  return {
    origin: frame?.origin ?? definition.defaults.origin,
    scale: frame?.scale ?? definition.defaults.scale,
    sourceOffset: frame?.sourceOffset ?? definition.defaults.sourceOffset,
  };
}

export const visualCatalogResolver: VisualDefinitionResolver = {
  getVisualSet,
  getClip: getVisualClip,
  resolveFrameVisual,
  runtimeKey: visualRuntimeKey,
};
