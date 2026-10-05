/**
 * `asset/assets.json` lookups. Phaser loads every spritesheet with the frame
 * grid from the manifest (`source.frame`), never from the scene resource's
 * `frameWidth`/`frameHeight`, so the converter does the same.
 */
import { gd } from './tscn.mjs';

export class AssetCatalog {
  constructor(manifest) {
    this.assets = manifest.assets;
  }

  require(assetId) {
    const asset = this.assets[assetId];
    if (!asset) throw new Error(`Unknown asset '${assetId}'`);
    return asset;
  }

  has(assetId) {
    return Object.hasOwn(this.assets, assetId);
  }

  resPath(assetId) {
    return `res://asset/${this.require(assetId).source.path}`;
  }

  /** Texture2D ext resource for an image or spritesheet asset. */
  texture(assetId) {
    return gd.ext('Texture2D', this.resPath(assetId));
  }

  /** Audio stream ext resource; the type follows the file extension. */
  audioStream(assetId) {
    const path = this.resPath(assetId);
    const extension = path.slice(path.lastIndexOf('.') + 1).toLowerCase();
    const type = { wav: 'AudioStreamWAV', ogg: 'AudioStreamOggVorbis', mp3: 'AudioStreamMP3' }[extension];
    if (!type) throw new Error(`Audio asset '${assetId}' has unsupported extension '.${extension}'`);
    return gd.ext(type, path);
  }

  /**
   * Frame grid of an image or spritesheet:
   * { frameW, frameH, cols, rows, count } (an image is one frame).
   */
  grid(assetId) {
    const source = this.require(assetId).source;
    if (source.kind === 'spritesheet') {
      const { w, h, cols, rows, count } = source.frame;
      return { frameW: w, frameH: h, cols, rows, count: count ?? cols * rows };
    }
    if (source.kind === 'image') {
      if (!source.expect) throw new Error(`Image asset '${assetId}' has no expect size`);
      return { frameW: source.expect.w, frameH: source.expect.h, cols: 1, rows: 1, count: 1 };
    }
    throw new Error(`Asset '${assetId}' (${source.kind}) is not a texture`);
  }
}
