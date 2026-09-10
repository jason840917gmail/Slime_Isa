import Phaser from 'phaser';
import { DEPTH_BANDS } from '../../presentation/WorldDepth';
import { rectanglesIntersect } from '../../presentation/WorldOcclusion';
import { DisposableBag } from '../../shared/lifecycle/Disposable';
import type { TileFactory } from './TileFactory';
import {
  TERRAIN_CHUNK_GUTTER,
  type TerrainTransitionChunk,
} from './TerrainTransitionChunks';

let nextTextureId = 0;

/** The camera has finalized its worldView before Phaser calls willRender. */
class TerrainChunkImage extends Phaser.GameObjects.Image {
  override willRender(camera: Phaser.Cameras.Scene2D.Camera): boolean {
    return super.willRender(camera)
      // Retain chunks conservatively when the camera's view is rotated.
      && (('rotation' in camera && camera.rotation !== 0) || rectanglesIntersect(this, camera.worldView));
  }
}

/** Owns baked terrain textures. No geometry masks survive construction. */
export class TerrainTransitionLayer {
  private readonly images: Phaser.GameObjects.Image[] = [];
  private readonly textureKeys: string[] = [];
  private readonly disposables = new DisposableBag();
  private destroyed = false;

  constructor(
    private readonly scene: Phaser.Scene,
    tileFactory: TileFactory,
    tileSize: number,
    chunks: readonly TerrainTransitionChunk[],
  ) {
    scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.destroy);
    this.disposables.add(() => scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.destroy));
    if (chunks.length === 0) return;

    // Detached scratch objects are reused for every command and never enter
    // the scene display/update lists or its collision groups.
    const scratch = new DisposableBag();
    try {
      const image = new Phaser.GameObjects.Image(scene, 0, 0, '__WHITE').setOrigin(0);
      scratch.add(() => image.destroy());
      const graphics = scene.make.graphics({}, false);
      scratch.add(() => graphics.destroy());
      const mask = graphics.createGeometryMask();
      scratch.add(() => mask.destroy());
      image.setMask(mask);
      scratch.add(() => image.clearMask(false));
      for (const chunk of chunks) {
        this.bakeChunk(chunk, tileFactory, tileSize, image, graphics);
      }
    } catch (error) {
      this.destroy();
      throw error;
    } finally {
      scratch.dispose();
    }
  }

  destroy = (): void => {
    if (this.destroyed) return;
    this.destroyed = true;
    this.disposables.dispose();
    for (const image of this.images) image.destroy();
    this.images.length = 0;
    for (const key of this.textureKeys) this.scene.textures.remove(key);
    this.textureKeys.length = 0;
  };

  private bakeChunk(
    chunk: TerrainTransitionChunk,
    tileFactory: TileFactory,
    tileSize: number,
    image: Phaser.GameObjects.Image,
    graphics: Phaser.GameObjects.Graphics,
  ): void {
    let key: string;
    do { key = `terrain-transition-chunk:${nextTextureId++}`; }
    while (this.scene.textures.exists(key));
    const gutter = TERRAIN_CHUNK_GUTTER;
    const texture = this.scene.textures.addDynamicTexture(key, chunk.width + gutter * 2, chunk.height + gutter * 2);
    if (!texture) throw new Error(`Could not allocate terrain transition chunk '${key}'`);
    this.textureKeys.push(key);
    texture.camera.setScroll(chunk.x - gutter, chunk.y - gutter);
    texture.clear();
    texture.beginDraw();
    try {
      for (const command of chunk.commands) {
        const visual = tileFactory.resolveVisual(command.tileId, command.tileX, command.tileY);
        image.setTexture(visual.textureKey, visual.frame)
          .setPosition(command.tileX * tileSize, command.tileY * tileSize)
          .setFlip(visual.flipX, visual.flipY)
          .setAlpha(command.alpha);
        graphics.clear().fillStyle(0xffffff, 1).fillPoints([...command.polygon], true);
        // The baking camera translates BOTH the world-space image and mask.
        // Passing draw offsets instead would move only the image.
        texture.batchDraw(image);
      }
    } finally {
      texture.endDraw();
    }
    texture.add('interior', 0, gutter, gutter, chunk.width, chunk.height);
    const cachedImage = new TerrainChunkImage(this.scene, chunk.x, chunk.y, key, 'interior')
      .setOrigin(0)
      .setDepth(DEPTH_BANDS['ground-decals'] + 0.2)
      .setName('terrain-transition-chunk')
      .setData('textureBytes', texture.width * texture.height * 4);
    this.images.push(cachedImage);
    this.scene.add.existing(cachedImage);
  }
}
