export interface SourceFrameDimensions {
  readonly width: number;
  readonly height: number;
}

export interface SourceOcclusionBounds {
  readonly width: number;
  readonly height: number;
  readonly offsetX: number;
  readonly offsetY: number;
}

export interface RenderSpriteGeometry {
  readonly x: number;
  readonly y: number;
  readonly originX: number;
  readonly originY: number;
  readonly scaleX: number;
  readonly scaleY: number;
  readonly flipX: boolean;
  readonly flipY: boolean;
}

export interface WorldRectangle {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface SourceAlphaRun {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface SourceAlphaMask {
  readonly runs: readonly SourceAlphaRun[];
  readonly opaqueArea: number;
}

export function resolveRenderedFrameTopLeft(
  sprite: RenderSpriteGeometry,
  sourceFrame: SourceFrameDimensions,
): { readonly x: number; readonly y: number; readonly scaleX: number; readonly scaleY: number } {
  const scaleX = Math.abs(sprite.scaleX);
  const scaleY = Math.abs(sprite.scaleY);
  return {
    x: sprite.x - sprite.originX * sourceFrame.width * scaleX,
    y: sprite.y - sprite.originY * sourceFrame.height * scaleY,
    scaleX,
    scaleY,
  };
}

/** Converts source-frame pixels into a world-space occlusion rectangle. */
export function resolveWorldOcclusionRectangle(
  sprite: RenderSpriteGeometry,
  sourceFrame: SourceFrameDimensions,
  bounds: SourceOcclusionBounds,
): WorldRectangle {
  const topLeft = resolveRenderedFrameTopLeft(sprite, sourceFrame);
  const sourceX = sprite.flipX
    ? sourceFrame.width - bounds.offsetX - bounds.width
    : bounds.offsetX;
  const sourceY = sprite.flipY
    ? sourceFrame.height - bounds.offsetY - bounds.height
    : bounds.offsetY;
  return {
    x: topLeft.x + sourceX * topLeft.scaleX,
    y: topLeft.y + sourceY * topLeft.scaleY,
    width: bounds.width * topLeft.scaleX,
    height: bounds.height * topLeft.scaleY,
  };
}

/**
 * Builds a compact source-space mask from an asset's alpha channel. Runs are
 * intentionally row-based so static artwork can be transformed once and
 * reused by every actor that overlaps it.
 */
export function buildSourceAlphaMask(
  sourceFrame: SourceFrameDimensions,
  alphaAt: (x: number, y: number) => number,
  bounds?: SourceOcclusionBounds,
  alphaThreshold = 1,
): SourceAlphaMask {
  const startX = Math.max(0, Math.floor(bounds?.offsetX ?? 0));
  const startY = Math.max(0, Math.floor(bounds?.offsetY ?? 0));
  const endX = Math.min(sourceFrame.width, startX + Math.floor(bounds?.width ?? sourceFrame.width));
  const endY = Math.min(sourceFrame.height, startY + Math.floor(bounds?.height ?? sourceFrame.height));
  const runs: SourceAlphaRun[] = [];
  let opaqueArea = 0;

  for (let y = startY; y < endY; y += 1) {
    let runStart = -1;
    for (let x = startX; x <= endX; x += 1) {
      const opaque = x < endX && alphaAt(x, y) >= alphaThreshold;
      if (opaque && runStart < 0) runStart = x;
      if (!opaque && runStart >= 0) {
        const width = x - runStart;
        runs.push({ x: runStart, y, width, height: 1 });
        opaqueArea += width;
        runStart = -1;
      }
    }
  }

  const compactRuns: SourceAlphaRun[] = [];
  const lastByShape = new Map<string, { index: number; lastY: number }>();
  for (const run of runs) {
    const shape = `${run.x}:${run.width}`;
    const previous = lastByShape.get(shape);
    if (previous && previous.lastY + 1 === run.y) {
      const merged = compactRuns[previous.index];
      compactRuns[previous.index] = { ...merged, height: merged.height + 1 };
      previous.lastY = run.y;
    } else {
      lastByShape.set(shape, { index: compactRuns.length, lastY: run.y });
      compactRuns.push(run);
    }
  }

  return { runs: compactRuns, opaqueArea };
}

export function resolveWorldAlphaMaskRuns(
  sprite: RenderSpriteGeometry,
  sourceFrame: SourceFrameDimensions,
  mask: SourceAlphaMask,
): readonly WorldRectangle[] {
  return mask.runs.map((run) => resolveWorldOcclusionRectangle(
    sprite,
    sourceFrame,
    {
      width: run.width,
      height: run.height,
      offsetX: run.x,
      offsetY: run.y,
    },
  ));
}

export function rectanglesIntersect(a: WorldRectangle, b: WorldRectangle): boolean {
  return a.x < b.x + b.width
    && a.x + a.width > b.x
    && a.y < b.y + b.height
    && a.y + a.height > b.y;
}

export function expandRectangle(rectangle: WorldRectangle, margin: number): WorldRectangle {
  return {
    x: rectangle.x - margin,
    y: rectangle.y - margin,
    width: rectangle.width + margin * 2,
    height: rectangle.height + margin * 2,
  };
}
