/**
 * Worlds that exist only for development and testing (roadmap 10.2: Release 1
 * ships only reachable worlds). `pnpm dev` opens them with `?map=<id>`;
 * production builds leave their world scenes out entirely. The playground
 * worlds have no legacy `.map.json`, so a named save made inside one cannot be
 * loaded back; the older test and biome maps keep theirs.
 */
export const DEV_ONLY_WORLD_IDS: readonly string[] = [
  // Mechanics testbeds (3.7).
  'playground',
  'playground-cavern',
  // Old test, experiment and unconnected biome maps: no exit leads to them.
  '174',
  '236',
  'cole',
  'girls',
  'jk',
  'tiktok',
  'test-rectangle',
  'depth-occlusion-test',
  'meadow-crossing',
  'icege',
  'emberleef',
  'hot',
];

export function isDevOnlyWorld(mapId: string): boolean {
  return DEV_ONLY_WORLD_IDS.includes(mapId);
}

/** True for the world scene file of a dev-only world (`.../worlds/<id>.scene.json`). */
export function isDevOnlyWorldSceneFile(file: string): boolean {
  const match = /[\\/]worlds[\\/]([^\\/]+)\.scene\.json$/.exec(file);
  return match !== null && isDevOnlyWorld(match[1]);
}
