import type { WorldRectangle } from '../../presentation/WorldOcclusion';
import type { WorldDimensions } from '../../world/WorldDimensions';

/**
 * Pure planning for blended terrain: which chunks need baking, and for each
 * chunk the per-material alpha masks that composite the ground textures into
 * organic, rounded material regions instead of square cells.
 *
 * Every blend cell contributes a smooth radial weight for its material around
 * its centre. Sample positions are domain-warped by deterministic value noise
 * so borders wander, weights are sharpened and normalised into shares, and the
 * shares are converted into "over" alphas for painting materials in ascending
 * priority. Straight borders stay on the cell edge; convex corners and single
 * cells round off; priority nudges a border into the lower material.
 */

/** Blend metadata for one tile ID; `undefined` keeps the cell out of blending. */
export interface TerrainBlendMaterial {
  readonly material: string;
  readonly priority: number;
}

export type TerrainBlendLookup = (tileId: string) => TerrainBlendMaterial | undefined;

export interface TerrainBlendLayer {
  readonly material: string;
  /** Most common tile of this material near the chunk; its texture paints the layer. */
  readonly tileId: string;
  /** One alpha byte per sample, row-major, `samplesX * samplesY`. */
  readonly alpha: Uint8ClampedArray;
  /** Cells whose area this layer touches (alpha > 0), for drawing texture only where needed. */
  readonly cells: readonly { readonly x: number; readonly y: number }[];
}

export interface TerrainBlendChunk extends WorldRectangle {
  /** World position of the texture's top-left pixel (chunk minus gutter). */
  readonly originX: number;
  readonly originY: number;
  readonly textureWidth: number;
  readonly textureHeight: number;
  readonly sampleStep: number;
  readonly samplesX: number;
  readonly samplesY: number;
  /** Ascending paint order; the first layer is opaque wherever blend cells exist. */
  readonly layers: readonly TerrainBlendLayer[];
  /** Non-blending cells inside the texture; they keep their base tile. */
  readonly excludedCells: readonly { readonly x: number; readonly y: number }[];
}

export interface TerrainBlendOptions {
  readonly seed: number;
  /** World pixels per mask sample; masks are upscaled with bilinear filtering. */
  readonly sampleStep?: number;
  readonly chunkSize?: number;
  readonly gutter?: number;
}

// World pixels, independent of authored tile size. Gutters hold neighbouring
// artwork so linear filtering at fractional zoom cannot sample empty seams.
export const TERRAIN_CHUNK_SIZE = 512;
export const TERRAIN_CHUNK_GUTTER = 2;
const DEFAULT_SAMPLE_STEP = 6;

/** Kernel radius in tiles: > 1/sqrt(2) so a lone cell's corners belong to its neighbours. */
const KERNEL_RADIUS = 1.05;
/** Shares are raised to this power before normalising: higher = crisper borders. */
const SHARPNESS = 4;
/** Weight bonus per priority rank, so higher materials edge into lower ones. */
const PRIORITY_BIAS = 0.14;
/** Domain warp in tiles: broad wander plus fine wiggle. */
const WARP_COARSE = { amplitude: 0.45, frequency: 0.45 } as const;
const WARP_FINE = { amplitude: 0.1, frequency: 2.2 } as const;

function hash2(x: number, y: number, seed: number): number {
  let hash = Math.imul(x, 0x27d4eb2d) ^ Math.imul(y, 0x165667b1) ^ Math.imul(seed, 0x45d9f3b);
  hash = Math.imul(hash ^ (hash >>> 15), 0x2c1b3c6d);
  hash = Math.imul(hash ^ (hash >>> 12), 0x297a2d39);
  return ((hash ^ (hash >>> 15)) >>> 0) / 4294967295;
}

/** Smooth value noise in [-1, 1]. */
function valueNoise(x: number, y: number, seed: number): number {
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const fx = x - x0;
  const fy = y - y0;
  const sx = fx * fx * (3 - 2 * fx);
  const sy = fy * fy * (3 - 2 * fy);
  const top = hash2(x0, y0, seed) + (hash2(x0 + 1, y0, seed) - hash2(x0, y0, seed)) * sx;
  const bottom = hash2(x0, y0 + 1, seed) + (hash2(x0 + 1, y0 + 1, seed) - hash2(x0, y0 + 1, seed)) * sx;
  return (top + (bottom - top) * sy) * 2 - 1;
}

function warp(u: number, v: number, seed: number): readonly [number, number] {
  const du = valueNoise(u * WARP_COARSE.frequency, v * WARP_COARSE.frequency, seed) * WARP_COARSE.amplitude
    + valueNoise(u * WARP_FINE.frequency, v * WARP_FINE.frequency, seed + 11) * WARP_FINE.amplitude;
  const dv = valueNoise(u * WARP_COARSE.frequency, v * WARP_COARSE.frequency, seed + 101) * WARP_COARSE.amplitude
    + valueNoise(u * WARP_FINE.frequency, v * WARP_FINE.frequency, seed + 131) * WARP_FINE.amplitude;
  return [u + du, v + dv];
}

function kernel(distanceSquared: number): number {
  const ratio = distanceSquared / (KERNEL_RADIUS * KERNEL_RADIUS);
  if (ratio >= 1) return 0;
  const falloff = 1 - ratio;
  return falloff * falloff;
}

interface GridView {
  readonly columns: number;
  readonly rows: number;
  tileAt(x: number, y: number): string | undefined;
}

function gridView(grid: readonly (readonly string[])[]): GridView {
  const rows = grid.length;
  const columns = rows > 0 ? grid[0].length : 0;
  return {
    columns,
    rows,
    tileAt: (x, y) => (y >= 0 && y < rows && x >= 0 && x < columns ? grid[y][x] : undefined),
  };
}

/** True when blend cells of two different materials meet (8-neighbourhood) inside the cell range. */
function hasBorder(view: GridView, lookup: TerrainBlendLookup, minX: number, minY: number, maxX: number, maxY: number): boolean {
  for (let y = minY; y <= maxY; y += 1) {
    for (let x = minX; x <= maxX; x += 1) {
      const tileId = view.tileAt(x, y);
      const material = tileId === undefined ? undefined : lookup(tileId)?.material;
      if (material === undefined) continue;
      for (const [dx, dy] of [[1, 0], [0, 1], [1, 1], [1, -1]] as const) {
        const other = view.tileAt(x + dx, y + dy);
        const otherMaterial = other === undefined ? undefined : lookup(other)?.material;
        if (otherMaterial !== undefined && otherMaterial !== material) return true;
      }
    }
  }
  return false;
}

export function planTerrainBlendChunks(
  grid: readonly (readonly string[])[],
  lookup: TerrainBlendLookup,
  dimensions: WorldDimensions,
  options: TerrainBlendOptions,
): TerrainBlendChunk[] {
  const view = gridView(grid);
  const tileSize = dimensions.tileSize;
  const chunkSize = options.chunkSize ?? TERRAIN_CHUNK_SIZE;
  const gutter = options.gutter ?? TERRAIN_CHUNK_GUTTER;
  const step = options.sampleStep ?? DEFAULT_SAMPLE_STEP;
  const chunks: TerrainBlendChunk[] = [];
  if (view.columns === 0 || view.rows === 0) return chunks;

  for (let y = 0; y < dimensions.height; y += chunkSize) {
    for (let x = 0; x < dimensions.width; x += chunkSize) {
      const width = Math.min(chunkSize, dimensions.width - x);
      const height = Math.min(chunkSize, dimensions.height - y);
      // A border within kernel reach of the chunk (plus warp) can reshape its pixels.
      const reach = 2;
      const minCellX = Math.floor(x / tileSize) - reach;
      const minCellY = Math.floor(y / tileSize) - reach;
      const maxCellX = Math.floor((x + width - 1) / tileSize) + reach;
      const maxCellY = Math.floor((y + height - 1) / tileSize) + reach;
      if (!hasBorder(view, lookup, minCellX, minCellY, maxCellX, maxCellY)) continue;
      chunks.push(buildChunk(view, lookup, tileSize, options.seed, step, gutter, { x, y, width, height }));
    }
  }
  return chunks;
}

function buildChunk(
  view: GridView,
  lookup: TerrainBlendLookup,
  tileSize: number,
  seed: number,
  step: number,
  gutter: number,
  rect: WorldRectangle,
): TerrainBlendChunk {
  const originX = rect.x - gutter;
  const originY = rect.y - gutter;
  const textureWidth = rect.width + gutter * 2;
  const textureHeight = rect.height + gutter * 2;
  const samplesX = Math.ceil(textureWidth / step);
  const samplesY = Math.ceil(textureHeight / step);

  // Materials near the chunk, ascending priority, and each one's most common tile.
  const minCellX = Math.floor(originX / tileSize) - 2;
  const minCellY = Math.floor(originY / tileSize) - 2;
  const maxCellX = Math.floor((originX + textureWidth - 1) / tileSize) + 2;
  const maxCellY = Math.floor((originY + textureHeight - 1) / tileSize) + 2;
  const tileCounts = new Map<string, Map<string, number>>();
  const priorities = new Map<string, number>();
  for (let y = minCellY; y <= maxCellY; y += 1) {
    for (let x = minCellX; x <= maxCellX; x += 1) {
      const tileId = view.tileAt(x, y);
      const blend = tileId === undefined ? undefined : lookup(tileId);
      if (!tileId || !blend) continue;
      priorities.set(blend.material, blend.priority);
      const counts = tileCounts.get(blend.material) ?? new Map<string, number>();
      counts.set(tileId, (counts.get(tileId) ?? 0) + 1);
      tileCounts.set(blend.material, counts);
    }
  }
  const materials = [...priorities.keys()].sort((left, right) => (
    priorities.get(left)! - priorities.get(right)! || left.localeCompare(right)
  ));
  const rank = new Map(materials.map((material, index) => [material, index]));
  const alphas = materials.map(() => new Uint8ClampedArray(samplesX * samplesY));
  const weights = new Float64Array(materials.length);

  for (let sy = 0; sy < samplesY; sy += 1) {
    for (let sx = 0; sx < samplesX; sx += 1) {
      const worldX = originX + (sx + 0.5) * step;
      const worldY = originY + (sy + 0.5) * step;
      const cellX = Math.floor(worldX / tileSize);
      const cellY = Math.floor(worldY / tileSize);
      const ownTile = view.tileAt(cellX, cellY);
      if (ownTile === undefined || !lookup(ownTile)) continue; // excluded cell keeps its base tile
      const [u, v] = warp(worldX / tileSize, worldY / tileSize, seed);
      weights.fill(0);
      const baseX = Math.floor(u);
      const baseY = Math.floor(v);
      for (let cy = baseY - 1; cy <= baseY + 1; cy += 1) {
        for (let cx = baseX - 1; cx <= baseX + 1; cx += 1) {
          const tileId = view.tileAt(cx, cy);
          const blend = tileId === undefined ? undefined : lookup(tileId);
          if (!blend) continue;
          const du = u - (cx + 0.5);
          const dv = v - (cy + 0.5);
          weights[rank.get(blend.material)!] += kernel(du * du + dv * dv);
        }
      }
      let total = 0;
      for (let index = 0; index < weights.length; index += 1) {
        const biased = weights[index] * (1 + PRIORITY_BIAS * index);
        weights[index] = biased ** SHARPNESS;
        total += weights[index];
      }
      if (total <= 0) {
        // Warp pushed the sample beyond every blend cell: keep the cell's own material.
        weights.fill(0);
        weights[rank.get(lookup(ownTile)!.material)!] = 1;
        total = 1;
      }
      // Over-compositing in ascending order: alpha_m = share_m / sum(shares <= m).
      const sampleIndex = sy * samplesX + sx;
      let cumulative = 0;
      for (let index = 0; index < weights.length; index += 1) {
        const share = weights[index] / total;
        cumulative += share;
        if (share <= 0) continue;
        alphas[index][sampleIndex] = Math.round((cumulative > 0 ? share / cumulative : 0) * 255);
      }
    }
  }

  const layers: TerrainBlendLayer[] = [];
  materials.forEach((material, index) => {
    const alpha = alphas[index];
    const cells = cellsTouched(alpha, samplesX, samplesY, step, originX, originY, tileSize);
    if (cells.length === 0) return;
    const counts = [...tileCounts.get(material)!.entries()].sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]));
    layers.push({ material, tileId: counts[0][0], alpha, cells });
  });

  const excludedCells: { x: number; y: number }[] = [];
  for (let y = Math.floor(originY / tileSize); y <= Math.floor((originY + textureHeight - 1) / tileSize); y += 1) {
    for (let x = Math.floor(originX / tileSize); x <= Math.floor((originX + textureWidth - 1) / tileSize); x += 1) {
      const tileId = view.tileAt(x, y);
      if (tileId === undefined || !lookup(tileId)) excludedCells.push({ x, y });
    }
  }

  return {
    ...rect,
    originX,
    originY,
    textureWidth,
    textureHeight,
    sampleStep: step,
    samplesX,
    samplesY,
    layers,
    excludedCells,
  };
}

function cellsTouched(
  alpha: Uint8ClampedArray,
  samplesX: number,
  samplesY: number,
  step: number,
  originX: number,
  originY: number,
  tileSize: number,
): { x: number; y: number }[] {
  const seen = new Set<string>();
  const cells: { x: number; y: number }[] = [];
  for (let sy = 0; sy < samplesY; sy += 1) {
    for (let sx = 0; sx < samplesX; sx += 1) {
      if (alpha[sy * samplesX + sx] === 0) continue;
      // Bilinear upscaling spreads a sample half a step, so include its footprint.
      for (const [ox, oy] of [[-step, -step], [step, -step], [-step, step], [step, step]] as const) {
        const cellX = Math.floor((originX + (sx + 0.5) * step + ox) / tileSize);
        const cellY = Math.floor((originY + (sy + 0.5) * step + oy) / tileSize);
        const key = `${cellX},${cellY}`;
        if (seen.has(key)) continue;
        seen.add(key);
        cells.push({ x: cellX, y: cellY });
      }
    }
  }
  return cells;
}
