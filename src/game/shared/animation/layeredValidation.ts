import { layeredTimelineFrameCount } from './layered';
import type { AnimationBlockTransformDocument, LayeredAnimationDocument } from './types';

export interface LayeredAnimationAssetDescriptor {
  readonly kind: string;
  readonly frameCount: number;
}

export interface LayeredAnimationValidationOptions {
  readonly assetLookup?: (assetId: string) => LayeredAnimationAssetDescriptor | undefined;
  readonly allowLoop?: boolean;
  readonly allowEmptyDraft?: boolean;
  readonly path?: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function finitePair(value: unknown): value is readonly [number, number] {
  return Array.isArray(value)
    && value.length === 2
    && value.every((entry) => typeof entry === 'number' && Number.isFinite(entry));
}

function validateTransform(
  value: unknown,
  path: string,
  issues: string[],
  allowOrigin: boolean,
): void {
  if (value === undefined) return;
  if (!isRecord(value)) {
    issues.push(`${path}: must be an object`);
    return;
  }
  const transform = value as AnimationBlockTransformDocument & { readonly origin?: unknown };
  if (transform.offset !== undefined && !finitePair(transform.offset)) issues.push(`${path}.offset: must contain two finite numbers`);
  if (transform.scale !== undefined) {
    if (!finitePair(transform.scale)) issues.push(`${path}.scale: must contain two finite numbers`);
    else if (transform.scale.some((entry) => entry <= 0)) issues.push(`${path}.scale: values must be greater than zero`);
  }
  if (transform.rotationDeg !== undefined && !Number.isFinite(transform.rotationDeg)) issues.push(`${path}.rotationDeg: must be finite`);
  if (transform.flipX !== undefined && typeof transform.flipX !== 'boolean') issues.push(`${path}.flipX: must be boolean`);
  if (transform.flipY !== undefined && typeof transform.flipY !== 'boolean') issues.push(`${path}.flipY: must be boolean`);
  if (allowOrigin) {
    if (transform.origin !== undefined && !finitePair(transform.origin)) issues.push(`${path}.origin: must contain two finite numbers`);
  } else if (transform.origin !== undefined) {
    issues.push(`${path}.origin: blocks cannot override layer origin`);
  }
}

export function validateLayeredAnimationDocument(
  value: unknown,
  options: LayeredAnimationValidationOptions = {},
): string[] {
  const path = options.path ?? 'animation';
  const issues: string[] = [];
  if (!isRecord(value)) return [`${path}: must be an object`];
  const animation = value as unknown as LayeredAnimationDocument;

  if (animation.version !== 2) issues.push(`${path}.version: must be 2`);
  if (!Number.isInteger(animation.framesPerSecond) || animation.framesPerSecond < 1 || animation.framesPerSecond > 240) {
    issues.push(`${path}.framesPerSecond: must be an integer between 1 and 240`);
  }
  if (typeof animation.durationSeconds !== 'number' || !Number.isFinite(animation.durationSeconds) || animation.durationSeconds <= 0) {
    issues.push(`${path}.durationSeconds: must be positive and finite`);
  }
  if (typeof animation.loop !== 'boolean') issues.push(`${path}.loop: must be boolean`);
  if (animation.loop && options.allowLoop === false) issues.push(`${path}.loop: must be false`);
  if (animation.loopMode !== undefined && animation.loopMode !== 'wrap' && animation.loopMode !== 'ping-pong') {
    issues.push(`${path}.loopMode: must be 'wrap' or 'ping-pong'`);
  }

  let timelineFrames = 0;
  try {
    timelineFrames = layeredTimelineFrameCount(animation);
  } catch {
    if (
      typeof animation.durationSeconds === 'number'
      && Number.isFinite(animation.durationSeconds)
      && animation.durationSeconds > 0
      && Number.isInteger(animation.framesPerSecond)
      && animation.framesPerSecond >= 1
      && animation.framesPerSecond <= 240
    ) {
      issues.push(`${path}: durationSeconds multiplied by framesPerSecond must be a positive whole number`);
    }
  }

  if (!Array.isArray(animation.layers)) {
    issues.push(`${path}.layers: must be an array`);
    return issues;
  }
  if (!options.allowEmptyDraft && animation.layers.length === 0) issues.push(`${path}.layers: must contain at least one layer`);

  const layerIds = new Set<string>();
  animation.layers.forEach((layer, layerIndex) => {
    const layerPath = `${path}.layers[${layerIndex}]`;
    if (!isRecord(layer)) {
      issues.push(`${layerPath}: must be an object`);
      return;
    }
    if (typeof layer.layerId !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(layer.layerId)) {
      issues.push(`${layerPath}.layerId: must be a lowercase kebab-case ID`);
    } else if (layerIds.has(layer.layerId)) {
      issues.push(`${layerPath}.layerId: '${layer.layerId}' is duplicated`);
    } else {
      layerIds.add(layer.layerId);
    }
    if (typeof layer.displayName !== 'string' || !layer.displayName.trim()) issues.push(`${layerPath}.displayName: must be non-empty`);
    if (typeof layer.assetId !== 'string' || !layer.assetId.trim()) {
      issues.push(`${layerPath}.assetId: must be non-empty`);
    }
    if (typeof layer.depthOffset !== 'number' || !Number.isFinite(layer.depthOffset)) issues.push(`${layerPath}.depthOffset: must be finite`);
    validateTransform(layer.transform, `${layerPath}.transform`, issues, true);

    const asset = typeof layer.assetId === 'string' ? options.assetLookup?.(layer.assetId) : undefined;
    if (options.assetLookup) {
      if (!asset) issues.push(`${layerPath}.assetId: unknown asset '${String(layer.assetId)}'`);
      else if (asset.kind !== 'spritesheet') issues.push(`${layerPath}.assetId: '${layer.assetId}' must be a spritesheet`);
    }

    if (!Array.isArray(layer.blocks)) {
      issues.push(`${layerPath}.blocks: must be an array`);
      return;
    }
    if (!options.allowEmptyDraft && layer.blocks.length === 0) issues.push(`${layerPath}.blocks: must contain at least one block`);
    const validSpans: Array<{ readonly from: number; readonly through: number; readonly path: string }> = [];
    layer.blocks.forEach((block, blockIndex) => {
      const blockPath = `${layerPath}.blocks[${blockIndex}]`;
      if (!isRecord(block)) {
        issues.push(`${blockPath}: must be an object`);
        return;
      }
      const from = typeof block.from === 'number' ? block.from : Number.NaN;
      const through = typeof block.through === 'number' ? block.through : Number.NaN;
      const sourceFrame = typeof block.sourceFrame === 'number' ? block.sourceFrame : Number.NaN;
      if (!Number.isInteger(from) || from < 0) issues.push(`${blockPath}.from: must be a non-negative integer`);
      if (!Number.isInteger(through) || through < 0 || (Number.isInteger(from) && through < from)) {
        issues.push(`${blockPath}.through: must be an integer greater than or equal to from`);
      }
      if (timelineFrames > 0 && Number.isInteger(through) && through >= timelineFrames) {
        issues.push(`${blockPath}.through: must be inside the animation timeline`);
      }
      if (!Number.isInteger(sourceFrame) || sourceFrame < 0) {
        issues.push(`${blockPath}.sourceFrame: must be a non-negative integer`);
      } else if (asset?.kind === 'spritesheet' && sourceFrame >= asset.frameCount) {
        issues.push(`${blockPath}.sourceFrame: must be inside asset '${layer.assetId}'`);
      }
      validateTransform(block.transform, `${blockPath}.transform`, issues, false);
      if (Number.isInteger(from) && Number.isInteger(through) && from >= 0 && through >= from) {
        validSpans.push({ from, through, path: blockPath });
      }
    });
    validSpans.sort((left, right) => left.from - right.from || left.through - right.through);
    for (let index = 1; index < validSpans.length; index += 1) {
      if (validSpans[index].from <= validSpans[index - 1].through) {
        issues.push(`${validSpans[index].path}: overlaps the previous block in layer '${layer.layerId}'`);
      }
    }
  });
  return issues;
}
