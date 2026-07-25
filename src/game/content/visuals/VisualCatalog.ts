import type { AssetId } from '../../infrastructure/assets/manifest';
import { getAsset } from '../../infrastructure/assets/manifest';
import enemyWormArcherJson from './enemy-worm-archer/visual-set.json';
import enemyWormBrawlerJson from './enemy-worm-brawler/visual-set.json';
import enemyWormBrawlerHitJson from './enemy-worm-brawler-hit/visual-set.json';
import enemyWormSwordsmanJson from './enemy-worm-swordsman/visual-set.json';
import playerSlimeJson from './player-slime/visual-set.json';
import treeWorldJson from './tree-world/visual-set.json';

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

export interface VisualClip {
  readonly runtimeKey: string;
  readonly frames: readonly number[];
  readonly frameRate: number;
  readonly repeat: number;
}

export interface VisualSetDefinition {
  readonly visualSetId: string;
  readonly assetId: AssetId;
  readonly defaults: VisualTransform;
  readonly frameVisuals?: Readonly<Record<string, VisualTransform>>;
  readonly clips: Readonly<Record<string, VisualClip>>;
}

const VISUAL_SET_FILES = [
  playerSlimeJson,
  enemyWormArcherJson,
  enemyWormSwordsmanJson,
  enemyWormBrawlerJson,
  enemyWormBrawlerHitJson,
  treeWorldJson,
] as unknown as readonly VisualSetDefinition[];

const VISUAL_SETS = new Map<string, VisualSetDefinition>();
const RUNTIME_KEYS = new Map<string, string>();

function assertPair(
  visualSetId: string,
  field: string,
  value: readonly number[] | undefined,
  predicate: (entry: number) => boolean,
): void {
  if (!value || value.length !== 2 || value.some((entry) => !Number.isFinite(entry) || !predicate(entry))) {
    throw new Error(`Visual set '${visualSetId}' has invalid ${field}`);
  }
}

function validateTransform(visualSetId: string, field: string, transform: VisualTransform): void {
  if (transform.origin) {
    assertPair(visualSetId, `${field}.origin`, transform.origin, (entry) => entry >= 0 && entry <= 1);
  }
  if (transform.scale) {
    assertPair(visualSetId, `${field}.scale`, transform.scale, (entry) => entry > 0);
  }
  if (transform.sourceOffset) {
    assertPair(visualSetId, `${field}.sourceOffset`, transform.sourceOffset, () => true);
  }
}

function getFrameCount(definition: VisualSetDefinition): number {
  const asset = getAsset(definition.assetId);
  if (asset.source.kind === 'spritesheet' && 'frame' in asset.source) {
    return 'count' in asset.source.frame && asset.source.frame.count
      ? asset.source.frame.count
      : asset.source.frame.cols * asset.source.frame.rows;
  }
  if (asset.source.kind === 'procedural' || asset.source.kind === 'image') {
    return 1;
  }
  throw new Error(
    `Visual set '${definition.visualSetId}' requires spritesheet, image, or procedural media`,
  );
}

function validateVisualSet(definition: VisualSetDefinition): void {
  const { visualSetId } = definition;
  if (VISUAL_SETS.has(visualSetId)) {
    throw new Error(`Duplicate visual set '${visualSetId}'`);
  }

  const frameCount = getFrameCount(definition);
  validateTransform(visualSetId, 'defaults', definition.defaults);
  assertPair(visualSetId, 'defaults.origin', definition.defaults.origin, (entry) => entry >= 0 && entry <= 1);
  assertPair(visualSetId, 'defaults.scale', definition.defaults.scale, (entry) => entry > 0);
  assertPair(visualSetId, 'defaults.sourceOffset', definition.defaults.sourceOffset, () => true);

  for (const [frameIndexText, transform] of Object.entries(definition.frameVisuals ?? {})) {
    const frameIndex = Number(frameIndexText);
    if (!Number.isInteger(frameIndex) || frameIndex < 0 || frameIndex >= frameCount) {
      throw new Error(
        `Visual set '${visualSetId}' frameVisuals.${frameIndexText} is outside 0..${frameCount - 1}`,
      );
    }
    validateTransform(visualSetId, `frameVisuals.${frameIndexText}`, transform);
  }

  for (const [clipId, clip] of Object.entries(definition.clips)) {
    if (clip.frames.length === 0 || clip.frames.some(
      (frame) => !Number.isInteger(frame) || frame < 0 || frame >= frameCount,
    )) {
      throw new Error(`Visual set '${visualSetId}' clip '${clipId}' has invalid frames`);
    }
    if (!Number.isFinite(clip.frameRate) || clip.frameRate <= 0) {
      throw new Error(`Visual set '${visualSetId}' clip '${clipId}' has invalid frameRate`);
    }
    if (!Number.isInteger(clip.repeat) || clip.repeat < -1) {
      throw new Error(`Visual set '${visualSetId}' clip '${clipId}' has invalid repeat`);
    }
    const previousOwner = RUNTIME_KEYS.get(clip.runtimeKey);
    if (previousOwner) {
      throw new Error(
        `Visual animation key '${clip.runtimeKey}' is shared by '${previousOwner}' and '${visualSetId}'`,
      );
    }
    RUNTIME_KEYS.set(clip.runtimeKey, visualSetId);
  }

  VISUAL_SETS.set(visualSetId, definition);
}

for (const definition of VISUAL_SET_FILES) {
  validateVisualSet(definition);
}

export type VisualSetId =
  | 'character.player.slime'
  | 'enemy.worm.archer'
  | 'enemy.worm.swordsman'
  | 'enemy.worm.brawler'
  | 'effect.enemy.worm-brawler-hit'
  | 'object.tree.world';

export function getVisualSet(visualSetId: VisualSetId): VisualSetDefinition {
  const definition = VISUAL_SETS.get(visualSetId);
  if (!definition) throw new Error(`Unknown visual set '${visualSetId}'`);
  return definition;
}

export function getVisualSetIds(): readonly VisualSetId[] {
  return [...VISUAL_SETS.keys()] as VisualSetId[];
}

export function getVisualClip(
  visualSetId: VisualSetId,
  clipId: string,
): VisualClip {
  const clip = getVisualSet(visualSetId).clips[clipId];
  if (!clip) throw new Error(`Visual set '${visualSetId}' has no clip '${clipId}'`);
  return clip;
}

export function findVisualClipByRuntimeKey(
  visualSetId: VisualSetId,
  runtimeKey: string,
): VisualClip | undefined {
  return Object.values(getVisualSet(visualSetId).clips).find(
    (clip) => clip.runtimeKey === runtimeKey,
  );
}

export function resolveFrameVisual(
  visualSetId: VisualSetId,
  frameIndex: number,
): ResolvedVisualTransform {
  const definition = getVisualSet(visualSetId);
  const frame = definition.frameVisuals?.[String(frameIndex)];
  return {
    origin: frame?.origin ?? definition.defaults.origin!,
    scale: frame?.scale ?? definition.defaults.scale!,
    sourceOffset: frame?.sourceOffset ?? definition.defaults.sourceOffset!,
  };
}
