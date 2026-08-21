import {
  layeredTimelineFrameCount,
  normalizeLayeredAnimation,
  type AnimationBlockTransformDocument,
  type AnimationVisualBlockDocument,
  type AnimationVisualLayerDocument,
  type LayeredAnimationDocument,
} from '../shared/animation';

export interface LayeredAnimationSelection {
  readonly layerId?: string;
  readonly blockIndex?: number;
  readonly playhead: number;
}

export interface LayeredAnimationDocumentStateValue {
  readonly animation: LayeredAnimationDocument;
  readonly selection: LayeredAnimationSelection;
  readonly hiddenLayerIds: ReadonlySet<string>;
  readonly soloLayerId?: string;
}

function clone<T>(value: T): T {
  return structuredClone(value);
}

function clampedFrame(frame: number, frameCount: number): number {
  return Math.max(0, Math.min(Math.round(frame), frameCount - 1));
}

export class LayeredAnimationDocumentState {
  private animation: LayeredAnimationDocument;
  private selection: LayeredAnimationSelection;
  private readonly hiddenLayerIds = new Set<string>();
  private soloLayerId?: string;

  constructor(animation: LayeredAnimationDocument) {
    this.animation = clone(animation);
    this.selection = {
      layerId: animation.layers[0]?.layerId,
      blockIndex: animation.layers[0]?.blocks.length ? 0 : undefined,
      playhead: 0,
    };
  }

  get value(): LayeredAnimationDocumentStateValue {
    return {
      animation: clone(this.animation),
      selection: { ...this.selection },
      hiddenLayerIds: new Set(this.hiddenLayerIds),
      ...(this.soloLayerId ? { soloLayerId: this.soloLayerId } : {}),
    };
  }

  replace(animation: LayeredAnimationDocument): void {
    this.animation = clone(animation);
    this.selection = {
      layerId: animation.layers[0]?.layerId,
      blockIndex: animation.layers[0]?.blocks.length ? 0 : undefined,
      playhead: 0,
    };
    this.hiddenLayerIds.clear();
    this.soloLayerId = undefined;
  }

  restore(value: LayeredAnimationDocumentStateValue): void {
    this.animation = clone(value.animation);
    const frameCount = layeredTimelineFrameCount(this.animation);
    const selectedLayer = this.animation.layers.find((layer) => layer.layerId === value.selection.layerId) ?? this.animation.layers[0];
    const selectedBlockIndex = selectedLayer && value.selection.blockIndex !== undefined && selectedLayer.blocks[value.selection.blockIndex]
      ? value.selection.blockIndex
      : undefined;
    this.selection = {
      layerId: selectedLayer?.layerId,
      blockIndex: selectedBlockIndex,
      playhead: clampedFrame(value.selection.playhead, frameCount),
    };
    this.hiddenLayerIds.clear();
    value.hiddenLayerIds.forEach((layerId) => this.hiddenLayerIds.add(layerId));
    this.soloLayerId = value.soloLayerId;
  }

  selectLayer(layerId: string): boolean {
    const layer = this.animation.layers.find((candidate) => candidate.layerId === layerId);
    if (!layer) return false;
    this.selection = { ...this.selection, layerId, blockIndex: undefined };
    return true;
  }

  selectBlock(layerId: string, blockIndex: number): boolean {
    const layer = this.animation.layers.find((candidate) => candidate.layerId === layerId);
    const block = layer?.blocks[blockIndex];
    if (!block) return false;
    this.selection = { layerId, blockIndex, playhead: block.from };
    return true;
  }

  setPlayhead(frame: number): void {
    this.selection = { ...this.selection, playhead: clampedFrame(frame, layeredTimelineFrameCount(this.animation)) };
  }

  addLayer(layer: AnimationVisualLayerDocument): boolean {
    if (this.animation.layers.some((candidate) => candidate.layerId === layer.layerId)) return false;
    this.animation = { ...this.animation, layers: [...this.animation.layers, clone(layer)] };
    this.selection = { layerId: layer.layerId, blockIndex: undefined, playhead: this.selection.playhead };
    return true;
  }

  renameLayer(layerId: string, displayName: string): boolean {
    const trimmed = displayName.trim();
    if (!trimmed) return false;
    return this.updateLayer(layerId, (layer) => ({ ...layer, displayName: trimmed }));
  }

  setLayerAsset(layerId: string, assetId: string): boolean {
    if (!assetId.trim()) return false;
    return this.updateLayer(layerId, (layer) => ({ ...layer, assetId }));
  }

  setLayerDepth(layerId: string, depthOffset: number): boolean {
    if (!Number.isFinite(depthOffset)) return false;
    return this.updateLayer(layerId, (layer) => ({ ...layer, depthOffset }));
  }

  setLayerTransform(layerId: string, transform: AnimationVisualLayerDocument['transform']): boolean {
    if (transform) {
      const values = [
        ...(transform.offset ?? []),
        ...(transform.scale ?? []),
        transform.rotationDeg,
        ...(transform.origin ?? []),
      ].filter((value): value is number => value !== undefined);
      if (values.some((value) => !Number.isFinite(value))) return false;
      if (transform.scale?.some((value) => value <= 0)) return false;
    }
    return this.updateLayer(layerId, (layer) => ({ ...layer, ...(transform ? { transform: clone(transform) } : { transform: undefined }) }));
  }

  setLoop(loop: boolean): boolean {
    if (this.animation.loop === loop) return true;
    this.animation = { ...this.animation, loop };
    return true;
  }

  setLoopMode(loopMode: 'wrap' | 'ping-pong'): boolean {
    if (loopMode !== 'wrap' && loopMode !== 'ping-pong') return false;
    this.animation = { ...this.animation, loopMode };
    return true;
  }

  moveLayer(layerId: string, delta: -1 | 1): boolean {
    const layers = [...this.animation.layers];
    const index = layers.findIndex((layer) => layer.layerId === layerId);
    const target = index + delta;
    if (index < 0 || target < 0 || target >= layers.length) return false;
    [layers[index], layers[target]] = [layers[target], layers[index]];
    this.animation = { ...this.animation, layers };
    return true;
  }

  deleteLayer(layerId: string): boolean {
    const index = this.animation.layers.findIndex((layer) => layer.layerId === layerId);
    if (index < 0) return false;
    const layers = this.animation.layers.filter((layer) => layer.layerId !== layerId);
    this.animation = { ...this.animation, layers };
    this.hiddenLayerIds.delete(layerId);
    if (this.soloLayerId === layerId) this.soloLayerId = undefined;
    const selected = layers[Math.min(index, layers.length - 1)];
    this.selection = { layerId: selected?.layerId, blockIndex: undefined, playhead: this.selection.playhead };
    return true;
  }

  toggleLayerHidden(layerId: string): boolean {
    if (!this.animation.layers.some((layer) => layer.layerId === layerId)) return false;
    if (this.hiddenLayerIds.has(layerId)) this.hiddenLayerIds.delete(layerId);
    else this.hiddenLayerIds.add(layerId);
    return true;
  }

  toggleLayerSolo(layerId: string): boolean {
    if (!this.animation.layers.some((layer) => layer.layerId === layerId)) return false;
    this.soloLayerId = this.soloLayerId === layerId ? undefined : layerId;
    return true;
  }

  insertTiles(layerId: string, sourceFrames: readonly number[], from = this.selection.playhead): boolean {
    if (sourceFrames.length === 0 || sourceFrames.some((frame) => !Number.isInteger(frame) || frame < 0)) return false;
    const frameCount = layeredTimelineFrameCount(this.animation);
    const start = Math.round(from);
    const through = start + sourceFrames.length - 1;
    if (start < 0 || through >= frameCount) return false;
    let insertedIndex = -1;
    const accepted = this.updateLayer(layerId, (layer) => {
      if (layer.blocks.some((block) => block.from <= through && start <= block.through)) return layer;
      const additions = sourceFrames.map((sourceFrame, index): AnimationVisualBlockDocument => ({
        from: start + index,
        through: start + index,
        sourceFrame,
      }));
      const blocks = [...layer.blocks, ...additions].sort((left, right) => left.from - right.from);
      insertedIndex = blocks.indexOf(additions[0]);
      return { ...layer, blocks };
    });
    if (!accepted || insertedIndex < 0) return false;
    this.selection = { layerId, blockIndex: insertedIndex, playhead: start };
    return true;
  }

  /**
   * Places source tiles at the playhead without changing the authored duration.
   * Empty cells are inserted normally; occupied cells are split and replaced so
   * Add Tiles remains useful even when a lane already contains a full hold.
   */
  placeTiles(layerId: string, sourceFrames: readonly number[], from = this.selection.playhead): boolean {
    if (this.insertTiles(layerId, sourceFrames, from)) return true;
    if (sourceFrames.length === 0 || sourceFrames.some((frame) => !Number.isInteger(frame) || frame < 0)) return false;
    const frameCount = layeredTimelineFrameCount(this.animation);
    const start = Math.round(from);
    const through = start + sourceFrames.length - 1;
    if (start < 0 || through >= frameCount) return false;

    let insertedIndex = -1;
    const additions = sourceFrames.map((sourceFrame, index): AnimationVisualBlockDocument => ({
      from: start + index,
      through: start + index,
      sourceFrame,
    }));
    const accepted = this.updateLayer(layerId, (layer) => {
      const blocks = layer.blocks.flatMap((block) => {
        if (block.through < start || block.from > through) return [block];
        const split: AnimationVisualBlockDocument[] = [];
        if (block.from < start) split.push({ ...block, through: start - 1 });
        if (block.through > through) split.push({ ...block, from: through + 1 });
        return split;
      });
      const nextBlocks = [...blocks, ...additions].sort((left, right) => left.from - right.from || left.through - right.through);
      insertedIndex = nextBlocks.indexOf(additions[0]);
      return { ...layer, blocks: nextBlocks };
    });
    if (!accepted || insertedIndex < 0) return false;
    this.selection = { layerId, blockIndex: insertedIndex, playhead: start };
    return true;
  }

  moveBlock(layerId: string, blockIndex: number, requestedFrom: number): boolean {
    const frameCount = layeredTimelineFrameCount(this.animation);
    return this.updateBlock(layerId, blockIndex, (block, siblings) => {
      const hold = block.through - block.from;
      const from = Math.round(requestedFrom);
      const through = from + hold;
      if (from < 0 || through >= frameCount || siblings.some((candidate) => candidate.from <= through && from <= candidate.through)) return undefined;
      return { ...block, from, through };
    });
  }

  resizeBlock(layerId: string, blockIndex: number, requestedThrough: number): boolean {
    const frameCount = layeredTimelineFrameCount(this.animation);
    return this.updateBlock(layerId, blockIndex, (block, siblings) => {
      const through = Math.round(requestedThrough);
      if (through < block.from || through >= frameCount || siblings.some((candidate) => candidate.from <= through && block.from <= candidate.through)) return undefined;
      return { ...block, through };
    });
  }

  adjustBlockHold(layerId: string, blockIndex: number, delta: number): boolean {
    const layer = this.animation.layers.find((candidate) => candidate.layerId === layerId);
    const block = layer?.blocks[blockIndex];
    return block ? this.resizeBlock(layerId, blockIndex, block.through + Math.round(delta)) : false;
  }

  duplicateBlock(layerId: string, blockIndex: number): boolean {
    const frameCount = layeredTimelineFrameCount(this.animation);
    const layer = this.animation.layers.find((candidate) => candidate.layerId === layerId);
    const block = layer?.blocks[blockIndex];
    if (!layer || !block) return false;

    const hold = block.through - block.from;
    const from = block.through + 1;
    const through = from + hold;
    if (from < 0 || through >= frameCount) return false;
    if (layer.blocks.some((candidate, index) => index !== blockIndex && candidate.from <= through && from <= candidate.through)) return false;

    const duplicate: AnimationVisualBlockDocument = {
      ...clone(block),
      from,
      through,
    };
    let duplicatedIndex = -1;
    const accepted = this.updateLayer(layerId, (current) => {
      const blocks = [...current.blocks, duplicate].sort((left, right) => left.from - right.from);
      duplicatedIndex = blocks.indexOf(duplicate);
      return { ...current, blocks };
    });
    if (!accepted || duplicatedIndex < 0) return false;
    this.selection = { layerId, blockIndex: duplicatedIndex, playhead: from };
    return true;
  }

  setBlockTransform(
    layerId: string,
    blockIndex: number,
    transform?: AnimationBlockTransformDocument,
  ): boolean {
    if (transform) {
      const values = [
        ...(transform.offset ?? []),
        ...(transform.scale ?? []),
        transform.rotationDeg,
      ].filter((value): value is number => value !== undefined);
      if (values.some((value) => !Number.isFinite(value))) return false;
      if (transform.scale?.some((value) => value <= 0)) return false;
    }
    return this.updateBlock(layerId, blockIndex, (block) => transform
      ? { ...block, transform: clone(transform) }
      : { from: block.from, through: block.through, sourceFrame: block.sourceFrame });
  }

  deleteBlock(layerId: string, blockIndex: number): boolean {
    let deleted = false;
    const accepted = this.updateLayer(layerId, (layer) => {
      if (!layer.blocks[blockIndex]) return layer;
      deleted = true;
      return { ...layer, blocks: layer.blocks.filter((_, index) => index !== blockIndex) };
    });
    if (accepted && deleted) this.selection = { layerId, blockIndex: undefined, playhead: this.selection.playhead };
    return accepted && deleted;
  }

  setFramesPerSecond(framesPerSecond: number): boolean {
    if (!Number.isInteger(framesPerSecond) || framesPerSecond < 1 || framesPerSecond > 240) return false;
    if (framesPerSecond === this.animation.framesPerSecond) return true;
    const previousFramesPerSecond = this.animation.framesPerSecond;
    const frameCount = Math.round(this.animation.durationSeconds * framesPerSecond);
    if (frameCount < 1) return false;
    // FPS changes the editor's sampling grid. It never changes authored clip duration.
    const layers = this.animation.layers.flatMap((layer) => {
      const blocks = reprojectBlocks(layer.blocks, previousFramesPerSecond, framesPerSecond, frameCount);
      return blocks.length > 0 || layer.blocks.length === 0 ? [{ ...layer, blocks }] : [];
    });
    this.animation = { ...this.animation, framesPerSecond, layers };
    this.reconcileSelection(
      Math.round(this.selection.playhead / previousFramesPerSecond * framesPerSecond),
      this.selection.layerId,
      this.selection.blockIndex,
    );
    return true;
  }

  setDurationSeconds(durationSeconds: number): boolean {
    if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) return false;
    const previousFrameCount = layeredTimelineFrameCount(this.animation);
    const requestedFrames = Math.round(durationSeconds * this.animation.framesPerSecond);
    if (requestedFrames < 1) return false;
    // Duration owns the timeline length. Rescale every authored occurrence just
    // like the weapon editor rescales its timed keyframes; FPS only changes the
    // sampling grid while this authored duration remains exact.
    const layers = this.animation.layers.flatMap((layer) => {
      const blocks = reprojectBlocksByTimeline(layer.blocks, previousFrameCount, requestedFrames);
      return blocks.length > 0 || layer.blocks.length === 0 ? [{ ...layer, blocks }] : [];
    });
    this.animation = { ...this.animation, durationSeconds, layers };
    this.reconcileSelection(
      Math.round(this.selection.playhead / previousFrameCount * requestedFrames),
      this.selection.layerId,
      this.selection.blockIndex,
    );
    return true;
  }

  normalizedAnimation() {
    return normalizeLayeredAnimation(this.animation);
  }

  private updateLayer(layerId: string, update: (layer: AnimationVisualLayerDocument) => AnimationVisualLayerDocument): boolean {
    const index = this.animation.layers.findIndex((layer) => layer.layerId === layerId);
    if (index < 0) return false;
    const layers = [...this.animation.layers];
    const previous = layers[index];
    layers[index] = update(previous);
    if (layers[index] === previous) return false;
    this.animation = { ...this.animation, layers };
    return true;
  }

  private updateBlock(
    layerId: string,
    blockIndex: number,
    update: (
      block: AnimationVisualBlockDocument,
      siblings: readonly AnimationVisualBlockDocument[],
    ) => AnimationVisualBlockDocument | undefined,
  ): boolean {
    let nextIndex = blockIndex;
    const accepted = this.updateLayer(layerId, (layer) => {
      const block = layer.blocks[blockIndex];
      if (!block) return layer;
      const next = update(block, layer.blocks.filter((_, index) => index !== blockIndex));
      if (!next) return layer;
      const blocks = layer.blocks.map((candidate, index) => index === blockIndex ? next : candidate)
        .sort((left, right) => left.from - right.from);
      nextIndex = blocks.indexOf(next);
      return { ...layer, blocks };
    });
    if (accepted) this.selection = { layerId, blockIndex: nextIndex, playhead: this.animation.layers.find((layer) => layer.layerId === layerId)?.blocks[nextIndex]?.from ?? this.selection.playhead };
    return accepted;
  }

  private reconcileSelection(playhead: number, layerId?: string, blockIndex?: number): void {
    const selectedLayer = this.animation.layers.find((layer) => layer.layerId === layerId) ?? this.animation.layers[0];
    const nextBlockIndex = selectedLayer?.blocks.length && blockIndex !== undefined
      ? Math.min(blockIndex, selectedLayer.blocks.length - 1)
      : undefined;
    this.selection = {
      layerId: selectedLayer?.layerId,
      blockIndex: nextBlockIndex,
      playhead: clampedFrame(playhead, layeredTimelineFrameCount(this.animation)),
    };
  }
}

function reprojectBlocks(
  blocks: readonly AnimationVisualBlockDocument[],
  previousFramesPerSecond: number,
  framesPerSecond: number,
  frameCount: number,
): AnimationVisualBlockDocument[] {
  return reprojectBlocksByTimeline(blocks, previousFramesPerSecond, framesPerSecond, frameCount);
}

function reprojectBlocksByTimeline(
  blocks: readonly AnimationVisualBlockDocument[],
  previousTimelineFrames: number,
  timelineFrames: number,
  frameCount = timelineFrames,
): AnimationVisualBlockDocument[] {
  let previousThrough = -1;
  return [...blocks]
    .sort((left, right) => left.from - right.from || left.through - right.through)
    .flatMap((block) => {
      const projectedFrom = Math.round(block.from / previousTimelineFrames * timelineFrames);
      const projectedThrough = Math.round((block.through + 1) / previousTimelineFrames * timelineFrames) - 1;
      const from = Math.max(projectedFrom, previousThrough + 1);
      const through = Math.min(projectedThrough, frameCount - 1);
      if (from > through) return [];
      previousThrough = through;
      return [{ ...block, from, through }];
    });
}
