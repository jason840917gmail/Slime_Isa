#!/usr/bin/env node

import path from 'node:path';
import { createServer } from 'vite';

const repoRoot = process.cwd();
const contentRoot = path.resolve(repoRoot, 'src/game/content');
const vite = await createServer({
  configFile: false,
  root: repoRoot,
  appType: 'custom',
  resolve: {
    alias: {
      'virtual-character-content': path.join(contentRoot, 'characters/virtual-character-content.ts'),
      'virtual-projectile-content': path.join(contentRoot, 'projectiles/virtual-projectile-content.ts'),
      'virtual-weapon-content': path.join(contentRoot, 'weapons/virtual-weapon-content.ts'),
      'virtual-effect-content': path.join(contentRoot, 'effects/virtual-effect-content.ts'),
      'virtual-animation-content': path.join(contentRoot, 'animations/virtual-animation-content.ts'),
    },
  },
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false },
});

try {
  const { getQuestDefinitions } = await vite.ssrLoadModule('/src/game/content/quests/QuestCatalog.ts');
  const { getCharacterPackage } = await vite.ssrLoadModule('/src/game/content/characters/CharacterCatalog.ts');
  const { validateNpcCatalogReferences } = await vite.ssrLoadModule('/src/game/content/npcs/NpcCatalog.ts');
  validateNpcCatalogReferences((characterId) => {
    try {
      const packageValue = getCharacterPackage(characterId);
      return { characterId, kind: packageValue.character.kind };
    } catch {
      return undefined;
    }
  });
  const quests = getQuestDefinitions();
  console.log(`quests:check passed (${quests.length} quest definitions validated)`);
} catch (error) {
  console.error(`quests:check failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
} finally {
  await vite.close();
}
