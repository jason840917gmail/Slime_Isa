import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

import type { Plugin } from 'vite';

import { validateAnimationPackage } from './validation';
import type { AnimationPackageCatalog, AnimationPackageCatalogEntry, AnimationPackageDocument } from './types';

const VIRTUAL_ID = 'virtual-animation-content';
const RESOLVED_ID = `\0${VIRTUAL_ID}`;

export interface AnimationContentRootOptions {
  /** Frozen package fixtures for conversion and package-validation tooling. */
  readonly animationRoot?: string;
  readonly resourceRoot?: string;
}

interface DiscoveredAnimationPackage {
  readonly absolutePath: string;
  readonly relativePath: string;
  readonly folderPath: string;
  readonly value: AnimationPackageDocument;
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonical(record[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

async function filesNamed(root: string, name: string): Promise<string[]> {
  const entries = await fs.readdir(root, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  });
  const files: string[] = [];
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    const absolute = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...await filesNamed(absolute, name));
    else if (entry.isFile() && entry.name === name) files.push(absolute);
  }
  return files.sort();
}

export async function findAnimationPackageFiles(root: string): Promise<string[]> {
  return filesNamed(root, 'animation.json');
}

async function findAnimationFolders(root: string, current = root): Promise<string[]> {
  const entries = await fs.readdir(current, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  });
  const folders: string[] = [];
  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue;
    if (!/^[a-z0-9][a-z0-9-]*$/.test(entry.name)) continue;
    const absolute = path.join(current, entry.name);
    folders.push(path.relative(root, absolute).replaceAll('\\', '/'), ...await findAnimationFolders(root, absolute));
  }
  return folders.sort();
}

export async function discoverPackages(root: string): Promise<readonly DiscoveredAnimationPackage[]> {
  const packages: DiscoveredAnimationPackage[] = [];
  const byId = new Map<string, string>();
  for (const absolutePath of await findAnimationPackageFiles(root)) {
    const relativePath = path.relative(root, absolutePath).replaceAll('\\', '/');
    const folders = relativePath.split('/').slice(0, -1);
    if (folders.some((folder) => !/^[a-z0-9][a-z0-9-]*$/.test(folder))) {
      throw new Error(`Animation package '${relativePath}' folders must use lowercase kebab-case`);
    }
    let value: unknown;
    try { value = JSON.parse(await fs.readFile(absolutePath, 'utf8')); }
    catch (error) { throw new Error(`Animation package '${relativePath}' is invalid: ${String(error)}`); }
    const diagnostics = validateAnimationPackage(value);
    if (diagnostics.length > 0) {
      throw new Error(`Animation package '${relativePath}' is invalid: ${diagnostics.map((item) => item.message).join('; ')}`);
    }
    const packageValue = value as AnimationPackageDocument;
    const previous = byId.get(packageValue.animationId);
    if (previous) throw new Error(`animationId '${packageValue.animationId}' duplicates '${previous}'`);
    byId.set(packageValue.animationId, relativePath);
    packages.push({ absolutePath, relativePath, folderPath: path.posix.dirname(relativePath), value: packageValue });
  }
  return packages.sort((left, right) => left.value.animationId.localeCompare(right.value.animationId));
}

export async function readCatalog(root: string): Promise<AnimationPackageCatalog> {
  const packages = await discoverPackages(root);
  const entries: AnimationPackageCatalogEntry[] = packages.map((entry) => ({
    ...entry.value,
    packagePath: entry.relativePath,
    folderPath: entry.folderPath === '.' ? '' : entry.folderPath,
    revision: createHash('sha256').update(canonical(entry.value)).digest('hex'),
  }));
  const folders = await findAnimationFolders(root);
  const revision = createHash('sha256').update(canonical({ folders, entries })).digest('hex');
  return { version: 1, revision, folders, packages: entries };
}

async function authoredPackageFiles(root: string): Promise<string[]> {
  const entries = await fs.readdir(root, { withFileTypes: true });
  const paths = entries.filter((entry) => entry.isFile() && entry.name.endsWith('.package.resource.json'))
    .map((entry) => path.join(root, entry.name)).sort();
  const ids = new Set<string>();
  for (const file of paths) {
    const resource = JSON.parse(await fs.readFile(file, 'utf8')) as { kind?: unknown; animations?: { package?: unknown } };
    const packageValue = resource.animations?.package;
    const diagnostics = validateAnimationPackage(packageValue);
    if (resource.kind !== 'animation-library' || diagnostics.length > 0) {
      throw new Error(`Authored animation resource '${file}' is invalid: ${diagnostics.map((item) => item.message).join('; ')}`);
    }
    const animationId = (packageValue as AnimationPackageDocument).animationId;
    if (ids.has(animationId)) throw new Error(`Authored animation '${animationId}' has duplicate resources`);
    ids.add(animationId);
  }
  return paths;
}

export function animationContentModulesPlugin(options: AnimationContentRootOptions = {}): Plugin {
  const legacyRoot = options.animationRoot ? path.resolve(options.animationRoot) : undefined;
  const root = legacyRoot ?? path.resolve(options.resourceRoot ?? 'src/game/content/scenes/authored/resources/animations');
  return {
    name: 'slime-animation-content-modules',
    resolveId(id) { return id === VIRTUAL_ID ? RESOLVED_ID : undefined; },
    async load(id) {
      if (id !== RESOLVED_ID) return undefined;
      const paths = legacyRoot
        ? (await discoverPackages(legacyRoot)).map((entry) => entry.absolutePath)
        : await authoredPackageFiles(root);
      const imports = paths.map((file, index) => `import animationResource${index} from ${JSON.stringify(file)};`).join('\n');
      const values = paths.map((_, index) => legacyRoot
        ? `animationResource${index}`
        : `animationResource${index}.animations.package`).join(', ');
      return `${imports}\nexport const animationPackages = [${values}];`;
    },
    handleHotUpdate(context) {
      if (!(legacyRoot ? context.file.endsWith('animation.json') : context.file.endsWith('.package.resource.json'))
        || !path.resolve(context.file).startsWith(root + path.sep)) return undefined;
      const module = context.server.moduleGraph.getModuleById(RESOLVED_ID);
      if (module) context.server.moduleGraph.invalidateModule(module);
      context.server.ws.send({ type: 'full-reload' });
      return [];
    },
  };
}
