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

// A self-contained placeholder keeps both Phaser and the browser studios usable
// when authored content outlives a deleted source image. Asset validation still
// reports the stale manifest entry during development.
const FALLBACK_ASSET_URL = `data:image/svg+xml,${encodeURIComponent(`
  <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
    <rect width="128" height="128" rx="24" fill="#17263a"/>
    <path d="M37 47h15V30c0-7 11-7 11 0v17h7V26c0-7 11-7 11 0v21h7V33c0-7 11-7 11 0v31c0 25-15 40-38 40S24 87 24 65V53c0-12 13-18 21-9l8 10V47H37z" fill="#86f0c3" stroke="#4b844b" stroke-width="7" stroke-linejoin="round"/>
    <circle cx="55" cy="38" r="5" fill="#fff" opacity=".45"/>
  </svg>
`)}`;

const warnedPaths = new Set<string>();

export function tryResolveAssetUrl(manifestPath: string): string | undefined {
  return ASSET_URLS[`/asset/${manifestPath}`];
}

export function resolveAssetUrl(manifestPath: string): string {
  const url = tryResolveAssetUrl(manifestPath);

  if (!url) {
    if (!warnedPaths.has(manifestPath)) {
      warnedPaths.add(manifestPath);
      console.warn(
      `No bundled URL for asset path '${manifestPath}'. ` +
          'Using the default gauntlet placeholder. Check that the file exists, is mapped in asset/assets.json, and is not excluded by ignore/glob patterns.',
      );
    }
    return FALLBACK_ASSET_URL;
  }

  return url;
}
