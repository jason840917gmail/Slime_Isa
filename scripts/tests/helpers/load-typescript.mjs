import { build } from 'esbuild';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPOSITORY_ROOT = fileURLToPath(new URL('../../..', import.meta.url));
const GUARDED_IMPORTS = new Set([
  'phaser',
  'virtual-animation-content',
  'virtual-character-content',
  'virtual-effect-content',
  'virtual-projectile-content',
  'virtual-scene-content',
  'virtual-weapon-content',
]);

/**
 * Bundles one TypeScript entry graph and imports it once. Tests should export
 * collaborators from that entry instead of loading files independently, which
 * prevents duplicate class and singleton identities inside one suite.
 */
export async function loadTypescriptModule(entryPoint, options = {}) {
  const virtualModules = options.virtualModules ?? {};
  const allowedImports = new Set(options.allowedImports ?? []);
  const result = await build({
    absWorkingDir: options.repositoryRoot ?? REPOSITORY_ROOT,
    entryPoints: [entryPoint],
    bundle: true,
    format: 'esm',
    platform: 'node',
    target: 'node20',
    write: false,
    sourcemap: 'inline',
    logLevel: 'silent',
    plugins: [{
      name: 'pure-scene-test-boundary',
      setup(buildContext) {
        buildContext.onResolve({ filter: /.*/ }, (args) => {
          if (Object.hasOwn(virtualModules, args.path)) {
            return { path: args.path, namespace: 'scene-test-virtual' };
          }
          if (GUARDED_IMPORTS.has(args.path) && !allowedImports.has(args.path)) {
            return {
              errors: [{
                text: `Pure Node test imported guarded dependency '${args.path}'. Inject an explicit fixture or allow it deliberately.`,
              }],
            };
          }
          return undefined;
        });
        buildContext.onLoad({ filter: /.*/, namespace: 'scene-test-virtual' }, (args) => ({
          contents: String(virtualModules[args.path]),
          loader: 'js',
        }));
      },
    }],
  });

  const output = result.outputFiles?.find((file) => file.path.endsWith('.js')) ?? result.outputFiles?.[0];
  if (!output) throw new Error(`esbuild produced no JavaScript for '${entryPoint}'`);
  const sourceUrl = `scene-test:${path.basename(entryPoint)}`;
  const encoded = Buffer.from(`${output.text}\n//# sourceURL=${sourceUrl}`).toString('base64');
  return import(`data:text/javascript;base64,${encoded}`);
}

export { REPOSITORY_ROOT };
