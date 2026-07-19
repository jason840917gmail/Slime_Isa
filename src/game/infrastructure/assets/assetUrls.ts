/**
 * Maps manifest-relative paths (as written in `asset/assets.json`) to
 * Vite-bundled URLs.
 *
 * The glob is root-absolute so resolution does not depend on this module's
 * location, and mirrors the manifest's `ignore` patterns as negative globs
 * so source art and experiments never enter Vite's asset graph.
 */
const ASSET_URLS = import.meta.glob(
  ['/asset/**/*.png', '!/asset/Originals/**', '!/asset/MAPS/FOREST/ChatGPT*.png'],
  { eager: true, query: '?url', import: 'default' },
) as Record<string, string>;

export function resolveAssetUrl(manifestPath: string): string {
  const url = ASSET_URLS[`/asset/${manifestPath}`];

  if (!url) {
    throw new Error(
      `No bundled URL for asset path '${manifestPath}'. ` +
        `Check that the file exists, is mapped in asset/assets.json, and is not excluded by ignore/glob patterns.`,
    );
  }

  return url;
}
