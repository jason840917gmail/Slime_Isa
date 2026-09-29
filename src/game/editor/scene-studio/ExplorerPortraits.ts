import { ASSET_MANIFEST } from '../../infrastructure/assets/manifest';
import { tryResolveAssetUrl } from '../../infrastructure/assets/assetUrls';
import type { SceneStudioPortrait } from '../../infrastructure/scenes/editor/SceneStudioRepository';

/** Edge of the square explorer thumbnail, in CSS pixels; keep in sync with `.scene-explorer-portrait`. */
const PORTRAIT_SIZE = 32;

interface AssetGeometry {
  readonly path?: string;
  readonly frame?: { readonly w: number; readonly h: number; readonly cols?: number };
  readonly expect?: { readonly w: number; readonly h: number };
}

function geometry(assetId: string): AssetGeometry | undefined {
  const entry = (ASSET_MANIFEST.assets as Readonly<Record<string, { readonly source?: AssetGeometry }>>)[assetId];
  return entry?.source;
}

const px = (value: number): string => `${Math.round(value * 100) / 100}px`;

/**
 * Inline style for the thumbnail's inner image: one frame of the portrait's
 * sheet, scaled to fit the box. Undefined when the asset has no bundled
 * image (procedural or missing), so the row keeps its glyph.
 */
export function explorerPortraitStyle(portrait: SceneStudioPortrait): string | undefined {
  const source = geometry(portrait.assetId);
  const url = source?.path ? tryResolveAssetUrl(source.path) : undefined;
  if (!source || !url) return undefined;
  const background = `background-image:url("${url}")`;
  const frameWidth = portrait.frameWidth ?? source.frame?.w;
  const frameHeight = portrait.frameHeight ?? source.frame?.h;
  const imageWidth = source.expect?.w;
  const imageHeight = source.expect?.h;
  if (!frameWidth || !frameHeight || !imageWidth || !imageHeight) return `${background};background-size:contain`;
  const columns = Math.max(1, Math.floor(imageWidth / frameWidth));
  const column = portrait.frame % columns;
  const row = Math.floor(portrait.frame / columns);
  const scale = PORTRAIT_SIZE / Math.max(frameWidth, frameHeight);
  // Sized to exactly one frame (the box centers it) so neighbouring frames never bleed in.
  return `${background};width:${px(frameWidth * scale)};height:${px(frameHeight * scale)};`
    + `background-size:${px(imageWidth * scale)} ${px(imageHeight * scale)};background-position:${px(-column * frameWidth * scale)} ${px(-row * frameHeight * scale)}`;
}
