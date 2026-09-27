import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { defineConfig, type Plugin } from 'vite';

import { characterContentModulesPlugin } from '../../../src/game/content/characters/characterContentModulesPlugin';
import { sceneContentModulesPlugin } from '../../../src/game/content/scenes/sceneContentModulesPlugin';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));

function readOnly(plugin: Plugin): Plugin {
  const { configureServer: _configureServer, ...safePlugin } = plugin;
  return safePlugin;
}

export default defineConfig({
  root: repositoryRoot,
  base: '/',
  plugins: [
    readOnly(characterContentModulesPlugin({
      characterRoot: path.join(repositoryRoot, 'src/game/content/characters'),
      visualRoot: path.join(repositoryRoot, 'src/game/content/visuals'),
      projectileRoot: path.join(repositoryRoot, 'src/game/content/projectiles'),
      weaponRoot: path.join(repositoryRoot, 'src/game/content/weapons'),
      effectRoot: path.join(repositoryRoot, 'src/game/content/effects'),
    })),
    readOnly(sceneContentModulesPlugin(path.join(repositoryRoot, 'src/game/content/scenes/authored'))),
  ],
  optimizeDeps: {
    entries: [
      path.join(repositoryRoot, 'scripts/tests/scene-browser/fixtures/index.html'),
      path.join(repositoryRoot, 'scripts/tests/scene-browser/fixtures/studio.html'),
    ],
  },
  server: {
    host: '127.0.0.1',
    port: 3101,
    strictPort: true,
    open: false,
  },
});
