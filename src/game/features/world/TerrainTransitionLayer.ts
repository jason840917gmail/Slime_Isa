import type Phaser from 'phaser';
import { DEPTH_BANDS } from '../../presentation/WorldDepth';
import { rectanglesIntersect } from '../../presentation/WorldOcclusion';
import { DisposableBag } from '../../shared/lifecycle/Disposable';
import type { TerrainBlendChunk } from './TerrainBlendField';

let nextTextureId = 0;

/** Texture frame for a tile at a cell, as the base tile layer draws it. */
export type TerrainVisualResolver = (tileId: string, cellX: number, cellY: number) => {
  readonly textureKey: string;
  readonly frame?: number;
  readonly flipX: boolean;
  readonly flipY: boolean;
};

/** Canvas factory seam; tests pass a headless double. */
export type TerrainCanvasFactory = (width: number, height: number) => HTMLCanvasElement;

const defaultCanvasFactory: TerrainCanvasFactory = (width, height) => {
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  return canvas;
};

// Phaser's scene shutdown event; a literal keeps this module free of a runtime Phaser import.
const SCENE_SHUTDOWN = 'shutdown';

/**
 * Skips chunks outside the camera. The camera has finalized its worldView
 * before Phaser calls willRender; rotated cameras keep chunks conservatively.
 */
function cullToCamera(image: Phaser.GameObjects.Image): void {
  const willRender = image.willRender.bind(image);
  image.willRender = (camera: Phaser.Cameras.Scene2D.Camera): boolean => willRender(camera)
    && (('rotation' in camera && camera.rotation !== 0) || rectanglesIntersect(image, camera.worldView));
}

function context2d(canvas: HTMLCanvasElement): CanvasRenderingContext2D {
  const context = canvas.getContext('2d');
  if (!context) throw new Error('Terrain blending requires a 2D canvas context');
  return context;
}

/**
 * Owns the baked blended-terrain chunk textures. Each chunk composites every
 * material's ground texture through its upscaled alpha mask (see
 * TerrainBlendField) on a canvas, which then becomes one cached image.
 * Chunks are laid out relative to the terrain origin and follow it.
 */
export class TerrainTransitionLayer {
  private readonly images: Phaser.GameObjects.Image[] = [];
  /** Chunk positions relative to the terrain origin, for following the tile layer. */
  private readonly localPositions: { readonly x: number; readonly y: number }[] = [];
  private readonly textureKeys: string[] = [];
  private readonly disposables = new DisposableBag();
  private destroyed = false;

  constructor(
    private readonly scene: Phaser.Scene,
    resolveVisual: TerrainVisualResolver,
    tileSize: number,
    chunks: readonly TerrainBlendChunk[],
    createCanvas: TerrainCanvasFactory = defaultCanvasFactory,
  ) {
    scene.events.once(SCENE_SHUTDOWN, this.destroy);
    this.disposables.add(() => scene.events.off(SCENE_SHUTDOWN, this.destroy));
    if (chunks.length === 0) return;
    try {
      for (const chunk of chunks) this.bakeChunk(chunk, resolveVisual, tileSize, createCanvas);
    } catch (error) {
      this.destroy();
      throw error;
    }
  }

  get chunkCount(): number { return this.images.length; }

  /** Moves every chunk with the terrain origin (the tile layer's position). */
  setOrigin(x: number, y: number): void {
    this.images.forEach((image, index) => image.setPosition(x + this.localPositions[index].x, y + this.localPositions[index].y));
  }

  setVisible(visible: boolean): void {
    for (const image of this.images) image.setVisible(visible);
  }

  destroy = (): void => {
    if (this.destroyed) return;
    this.destroyed = true;
    this.disposables.dispose();
    for (const image of this.images) image.destroy();
    this.images.length = 0;
    this.localPositions.length = 0;
    for (const key of this.textureKeys) this.scene.textures.remove(key);
    this.textureKeys.length = 0;
  };

  private bakeChunk(
    chunk: TerrainBlendChunk,
    resolveVisual: TerrainVisualResolver,
    tileSize: number,
    createCanvas: TerrainCanvasFactory,
  ): void {
    const canvas = createCanvas(chunk.textureWidth, chunk.textureHeight);
    const target = context2d(canvas);
    const layerCanvas = createCanvas(chunk.textureWidth, chunk.textureHeight);
    const layer = context2d(layerCanvas);
    const maskCanvas = createCanvas(chunk.samplesX, chunk.samplesY);
    const mask = context2d(maskCanvas);

    for (const blendLayer of chunk.layers) {
      layer.globalCompositeOperation = 'source-over';
      layer.clearRect(0, 0, chunk.textureWidth, chunk.textureHeight);
      for (const cell of blendLayer.cells) {
        this.drawTile(layer, resolveVisual, blendLayer.tileId, cell.x, cell.y, tileSize, chunk);
      }
      const pixels = mask.createImageData(chunk.samplesX, chunk.samplesY);
      for (let index = 0; index < blendLayer.alpha.length; index += 1) {
        pixels.data[index * 4 + 3] = blendLayer.alpha[index];
      }
      mask.putImageData(pixels, 0, 0);
      layer.globalCompositeOperation = 'destination-in';
      layer.imageSmoothingEnabled = true;
      layer.drawImage(maskCanvas, 0, 0, chunk.samplesX * chunk.sampleStep, chunk.samplesY * chunk.sampleStep);
      target.drawImage(layerCanvas, 0, 0);
    }
    // Cells outside the blend group keep their own base tile underneath.
    for (const cell of chunk.excludedCells) {
      target.clearRect(cell.x * tileSize - chunk.originX, cell.y * tileSize - chunk.originY, tileSize, tileSize);
    }

    let key: string;
    do { key = `terrain-transition-chunk:${nextTextureId++}`; }
    while (this.scene.textures.exists(key));
    // A plain texture over the canvas: a CanvasTexture would read every pixel
    // back (getImageData) for pixel queries these chunks never use.
    const texture = this.scene.textures.create(key, canvas, chunk.textureWidth, chunk.textureHeight);
    if (!texture) throw new Error(`Could not allocate terrain transition chunk '${key}'`);
    this.textureKeys.push(key);
    const gutterX = chunk.x - chunk.originX;
    const gutterY = chunk.y - chunk.originY;
    texture.add('interior', 0, gutterX, gutterY, chunk.width, chunk.height);
    const cachedImage = this.scene.add.image(chunk.x, chunk.y, key, 'interior')
      .setOrigin(0)
      .setDepth(DEPTH_BANDS['ground-decals'] + 0.2)
      .setName('terrain-transition-chunk')
      .setData('textureBytes', chunk.textureWidth * chunk.textureHeight * 4);
    cullToCamera(cachedImage);
    this.images.push(cachedImage);
    this.localPositions.push({ x: chunk.x, y: chunk.y });
  }

  private drawTile(
    layer: CanvasRenderingContext2D,
    resolveVisual: TerrainVisualResolver,
    tileId: string,
    cellX: number,
    cellY: number,
    tileSize: number,
    chunk: TerrainBlendChunk,
  ): void {
    const visual = resolveVisual(tileId, cellX, cellY);
    const frame = this.scene.textures.getFrame(visual.textureKey, visual.frame);
    if (!frame) return;
    const source = frame.source.image as CanvasImageSource;
    const x = cellX * tileSize - chunk.originX;
    const y = cellY * tileSize - chunk.originY;
    if (!visual.flipX && !visual.flipY) {
      layer.drawImage(source, frame.cutX, frame.cutY, frame.cutWidth, frame.cutHeight, x, y, tileSize, tileSize);
      return;
    }
    layer.save();
    layer.translate(x + (visual.flipX ? tileSize : 0), y + (visual.flipY ? tileSize : 0));
    layer.scale(visual.flipX ? -1 : 1, visual.flipY ? -1 : 1);
    layer.drawImage(source, frame.cutX, frame.cutY, frame.cutWidth, frame.cutHeight, 0, 0, tileSize, tileSize);
    layer.restore();
  }
}
