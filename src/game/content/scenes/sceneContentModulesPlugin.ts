import { promises as fs } from 'node:fs';
import path from 'node:path';

import type { Plugin } from 'vite';

const VIRTUAL_ID = 'virtual-scene-content';
const RESOLVED_ID = `\0${VIRTUAL_ID}`;

async function discover(directory: string, suffix: string): Promise<string[]> {
  const output: string[] = [];
  const visit = async (current: string): Promise<void> => {
    let entries;
    try { entries = await fs.readdir(current, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const candidate = path.join(current, entry.name);
      if (entry.isDirectory()) await visit(candidate);
      else if (entry.isFile() && entry.name.endsWith(suffix)) output.push(candidate);
    }
  };
  await visit(directory);
  return output.sort();
}

function isContentFile(file: string): boolean {
  return file.endsWith('.scene.json') || file.endsWith('.resource.json');
}

export function sceneContentModulesPlugin(contentRoot = path.resolve(process.cwd(), 'src/game/content/scenes/authored')): Plugin {
  return {
    name: 'slime-scene-content-modules',
    resolveId(id) { return id === VIRTUAL_ID ? RESOLVED_ID : undefined; },
    async load(id) {
      if (id !== RESOLVED_ID) return undefined;
      const scenes = await discover(contentRoot, '.scene.json');
      const resources = await discover(contentRoot, '.resource.json');
      const imports = [
        ...scenes.map((file, index) => `import scene${index} from ${JSON.stringify(file)};`),
        ...resources.map((file, index) => `import resource${index} from ${JSON.stringify(file)};`),
      ];
      return `${imports.join('\n')}\nexport const sceneDocuments = [${scenes.map((_, index) => `scene${index}`).join(',')}];\nexport const sceneResourceDocuments = [${resources.map((_, index) => `resource${index}`).join(',')}];`;
    },
    // Vite only reports edits to files it already imports; a scene file that is
    // added or deleted must also rebuild the discovered list, or open pages keep
    // the old catalog until the dev server restarts.
    configureServer(server) {
      const refresh = (file: string): void => {
        if (!isContentFile(file) || !path.resolve(file).startsWith(path.resolve(contentRoot))) return;
        const module = server.moduleGraph.getModuleById(RESOLVED_ID);
        if (module) server.moduleGraph.invalidateModule(module);
        server.ws.send({ type: 'full-reload' });
      };
      server.watcher.on('add', refresh);
      server.watcher.on('unlink', refresh);
    },
    handleHotUpdate(context) {
      if (!isContentFile(context.file)) return undefined;
      const module = context.server.moduleGraph.getModuleById(RESOLVED_ID);
      if (module) context.server.moduleGraph.invalidateModule(module);
      context.server.ws.send({ type: 'full-reload' });
      return [];
    },
  };
}

export { VIRTUAL_ID as SCENE_CONTENT_MODULE_ID };
