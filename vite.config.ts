import { defineConfig } from 'vite';

import { characterContentModulesPlugin } from './src/game/content/characters/characterContentModulesPlugin';
import { gameConstantsContentPlugin } from './src/game/content/gameConstantsContentPlugin';
import { sceneContentModulesPlugin } from './src/game/content/scenes/sceneContentModulesPlugin';
import { sceneStudioContentPlugin } from './src/game/infrastructure/scenes/editor/SceneStudioContentPlugin';

export default defineConfig({
  base: './',
  plugins: [
    characterContentModulesPlugin(),
    sceneContentModulesPlugin(),
    sceneStudioContentPlugin(),
    gameConstantsContentPlugin(),
  ],
  server: { open: false },
  build: {
    rollupOptions: {
      output: { manualChunks: { phaser: ['phaser'] } },
    },
  },
});
