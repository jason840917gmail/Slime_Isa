import { promises as fs } from 'node:fs';
import path from 'node:path';

import type { Plugin } from 'vite';

import type { CharacterDocument, VisualSetDocument } from './types';

const CHARACTER_ID = 'virtual-character-content';
const PROJECTILE_ID = 'virtual-projectile-content';
const WEAPON_ID = 'virtual-weapon-content';
const EFFECT_ID = 'virtual-effect-content';
const VIRTUAL_IDS = [CHARACTER_ID, PROJECTILE_ID, WEAPON_ID, EFFECT_ID] as const;
const resolved = (id: string): string => `\0${id}`;

export interface CharacterContentRootOptions {
  readonly characterRoot?: string;
  readonly visualRoot?: string;
  readonly projectileRoot?: string;
  readonly weaponRoot?: string;
  readonly effectRoot?: string;
}

export interface CharacterContentModule {
  readonly characterId: string;
  readonly character: CharacterDocument;
  readonly visualSet: VisualSetDocument;
}

async function findFiles(root: string, filename: string): Promise<string[]> {
  const files: string[] = [];
  const entries = await fs.readdir(root, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  });
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    const absolute = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...await findFiles(absolute, filename));
    else if (entry.isFile() && entry.name === filename) files.push(absolute);
  }
  return files.sort();
}

function moduleSource(files: readonly string[], exportName: string, itemName: string): string {
  const imports = files.map((file, index) => `import ${itemName}${index} from ${JSON.stringify(file)};`).join('\n');
  const values = files.map((_, index) => `${itemName}${index}`).join(',');
  return `${imports}\nexport const ${exportName} = [${values}];`;
}

export function characterContentModulesPlugin(options: CharacterContentRootOptions = {}): Plugin {
  const roots = {
    character: path.resolve(options.characterRoot ?? 'src/game/content/characters'),
    visual: path.resolve(options.visualRoot ?? 'src/game/content/visuals'),
    projectile: path.resolve(options.projectileRoot ?? 'src/game/content/projectiles'),
    weapon: path.resolve(options.weaponRoot ?? 'src/game/content/weapons'),
    effect: path.resolve(options.effectRoot ?? 'src/game/content/effects'),
  };
  return {
    name: 'slime-character-content-modules',
    resolveId(id) {
      return VIRTUAL_IDS.includes(id as typeof VIRTUAL_IDS[number]) ? resolved(id) : undefined;
    },
    async load(id) {
      if (id === resolved(PROJECTILE_ID)) return moduleSource(await findFiles(roots.projectile, 'projectile.json'), 'projectileDefinitions', 'projectile');
      if (id === resolved(WEAPON_ID)) return moduleSource(await findFiles(roots.weapon, 'weapon.json'), 'weaponDefinitions', 'weapon');
      if (id === resolved(EFFECT_ID)) return moduleSource(await findFiles(roots.effect, 'effect.json'), 'effectDefinitions', 'effect');
      if (id !== resolved(CHARACTER_ID)) return undefined;

      const characters = await findFiles(roots.character, 'character.json');
      const visualPaths = new Set(await findFiles(roots.character, 'visual-set.json'));
      const pairs = characters.flatMap((characterPath) => {
        const visualPath = path.join(path.dirname(characterPath), 'visual-set.json');
        return visualPaths.has(visualPath) ? [{ characterPath, visualPath, id: path.basename(path.dirname(characterPath)) }] : [];
      });
      const loose = await findFiles(roots.visual, 'visual-set.json');
      const characterImports = pairs.map((entry, index) => `import character${index} from ${JSON.stringify(entry.characterPath)};`).join('\n');
      const visualImports = pairs.map((entry, index) => `import visual${index} from ${JSON.stringify(entry.visualPath)};`).join('\n');
      const looseImports = loose.map((file, index) => `import looseVisual${index} from ${JSON.stringify(file)};`).join('\n');
      const entries = pairs.map((entry, index) => `{ characterId: ${JSON.stringify(entry.id)}, character: character${index}, visualSet: visual${index} }`).join(',');
      const looseValues = loose.map((_, index) => `looseVisual${index}`).join(',');
      return `${characterImports}\n${visualImports}\n${looseImports}\nexport const characterPackages = [${entries}];\nexport const visualSets = [...characterPackages.map((entry) => entry.visualSet), ...[${looseValues}]];`;
    },
    handleHotUpdate(context) {
      if (!/(?:character|visual-set|projectile|weapon|effect)\.json$/.test(context.file)) return undefined;
      for (const id of VIRTUAL_IDS) {
        const module = context.server.moduleGraph.getModuleById(resolved(id));
        if (module) context.server.moduleGraph.invalidateModule(module);
      }
      return [];
    },
  };
}

export { CHARACTER_ID as CHARACTER_CONTENT_MODULE_ID };
