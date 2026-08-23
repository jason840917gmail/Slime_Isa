import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { Plugin, ViteDevServer } from 'vite';
import { validateAnimationPackage } from './validation';
import type {
  AnimationPackageCatalog,
  AnimationPackageCatalogEntry,
  AnimationPackageDiagnostic,
  AnimationPackageDocument,
  AnimationPackageReference,
} from './types';

const VIRTUAL_ID = 'virtual-animation-content';
const RESOLVED_VIRTUAL_ID = `\0${VIRTUAL_ID}`;
const PACKAGE_FILE = 'animation.json';

export interface AnimationContentRootOptions {
  readonly animationRoot?: string;
}

interface DiscoveredAnimationPackage {
  readonly absolutePath: string;
  readonly relativePath: string;
  readonly folderPath: string;
  readonly value: AnimationPackageDocument;
}

function jsonResponse(response: ServerResponse, statusCode: number, value: unknown): void {
  response.statusCode = statusCode;
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.end(JSON.stringify(value));
}

async function readRequestBody(request: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > 2 * 1024 * 1024) throw new Error('Animation package request is too large');
    chunks.push(buffer);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function pathIsInside(root: string, target: string): boolean {
  const relativeTarget = path.relative(path.resolve(root), path.resolve(target));
  return relativeTarget === '' || (relativeTarget !== '..' && !relativeTarget.startsWith(`..${path.sep}`) && !path.isAbsolute(relativeTarget));
}

function canonicalValue(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalValue).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonicalValue(record[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function packageRevision(value: AnimationPackageDocument): string {
  return createHash('sha256').update(canonicalValue(value)).digest('hex');
}

function packageError(packagePath: string, diagnostics: readonly AnimationPackageDiagnostic[]): Error {
  const details = diagnostics.map((diagnostic) => `${diagnostic.code}: ${diagnostic.message}`).join('; ');
  return new Error(`Animation package '${packagePath}' is invalid: ${details}`);
}

function validatePackagePath(root: string, absolutePath: string): string[] {
  const relativePath = path.relative(root, absolutePath).replaceAll('\\', '/');
  const segments = relativePath.split('/');
  const issues: string[] = [];
  if (segments.at(-1) !== PACKAGE_FILE) issues.push('package file must be named animation.json');
  for (const segment of segments.slice(0, -1)) {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(segment)) issues.push(`folder '${segment}' must use lowercase kebab-case`);
  }
  return issues;
}

async function findAnimationPackageFiles(root: string): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await fs.readdir(root, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  })) {
    if (entry.name.startsWith('.') || entry.name.startsWith('.animation-library-')) continue;
    const absolutePath = path.join(root, entry.name);
    if (entry.isFile() && entry.name === PACKAGE_FILE) files.push(absolutePath);
    else if (entry.isDirectory()) files.push(...await findAnimationPackageFiles(absolutePath));
  }
  return files.sort();
}

async function findAnimationFolders(root: string, current = root): Promise<string[]> {
  const folders: string[] = [];
  for (const entry of await fs.readdir(current, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  })) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue;
    const absolutePath = path.join(current, entry.name);
    const relativePath = path.relative(root, absolutePath).replaceAll('\\', '/');
    if (!/^[a-z0-9][a-z0-9-]*$/.test(entry.name)) continue;
    folders.push(relativePath, ...await findAnimationFolders(root, absolutePath));
  }
  return folders.sort();
}

async function discoverPackages(root: string): Promise<readonly DiscoveredAnimationPackage[]> {
  const packages: DiscoveredAnimationPackage[] = [];
  const byId = new Map<string, string>();
  for (const absolutePath of await findAnimationPackageFiles(root)) {
    const relativePath = path.relative(root, absolutePath).replaceAll('\\', '/');
    const pathIssues = validatePackagePath(root, absolutePath);
    if (pathIssues.length > 0) throw packageError(relativePath, pathIssues.map((message) => ({ code: 'animation-package-invalid', packagePath: relativePath, message })));
    let value: unknown;
    try {
      value = JSON.parse(await fs.readFile(absolutePath, 'utf8')) as unknown;
    } catch (error: unknown) {
      throw packageError(relativePath, [{ code: 'animation-package-invalid', packagePath: relativePath, message: error instanceof Error ? error.message : String(error) }]);
    }
    const diagnostics = validateAnimationPackage(value);
    if (diagnostics.length > 0) throw packageError(relativePath, diagnostics.map((diagnostic) => ({ ...diagnostic, packagePath: relativePath })));
    const typedValue = value as AnimationPackageDocument;
    const previous = byId.get(typedValue.animationId);
    if (previous) {
      throw packageError(relativePath, [{
        code: 'animation-id-duplicate',
        packagePath: relativePath,
        animationId: typedValue.animationId,
        message: `animationId '${typedValue.animationId}' duplicates '${previous}'`,
      }]);
    }
    byId.set(typedValue.animationId, relativePath);
    packages.push({
      absolutePath,
      relativePath,
      folderPath: path.posix.dirname(relativePath),
      value: typedValue,
    });
  }
  return packages.sort((left, right) => left.value.animationId.localeCompare(right.value.animationId));
}

async function readCatalog(root: string): Promise<AnimationPackageCatalog> {
  const packages = await discoverPackages(root);
  const entries: AnimationPackageCatalogEntry[] = packages.map((entry) => ({
    ...entry.value,
    packagePath: entry.relativePath,
    folderPath: entry.folderPath === '.' ? '' : entry.folderPath,
    revision: packageRevision(entry.value),
  }));
  const folders = await findAnimationFolders(root);
  const revision = createHash('sha256').update(canonicalValue({ folders, entries })).digest('hex');
  return { version: 1, revision, folders, packages: entries };
}

function invalidateAnimationCatalog(server: ViteDevServer): void {
  const module = server.moduleGraph.getModuleById(RESOLVED_VIRTUAL_ID);
  if (module) server.moduleGraph.invalidateModule(module);
}

type BeforeAnimationWrite = (paths: readonly string[]) => void;

function safePackagePath(root: string, packagePath: string): string {
  const normalized = packagePath.replaceAll('\\', '/');
  if (!normalized.endsWith('/animation.json') || normalized.startsWith('/') || normalized.split('/').some((segment) => segment === '..' || segment === '.' || !/^[a-z0-9][a-z0-9-]*$/.test(segment) && segment !== 'animation.json')) {
    throw new Error('Package path must contain lowercase kebab-case folders and end with animation.json');
  }
  const absolute = path.resolve(root, ...normalized.split('/'));
  if (!pathIsInside(root, absolute)) throw new Error('Package path escapes the animation root');
  return absolute;
}

function packageSchemaFor(root: string, packagePath: string): string {
  return path.relative(path.dirname(packagePath), path.join(root, 'animation-package.schema.json')).replaceAll(path.sep, '/');
}

interface AnimationPackageWrite {
  readonly packagePath: string;
  readonly expectedRevision?: string;
  readonly operation?: 'create' | 'update' | 'upsert';
  readonly package: AnimationPackageDocument;
}

interface AnimationPackageDelete {
  readonly packagePath: string;
  readonly expectedRevision?: string;
}

interface AnimationLibraryTransaction {
  readonly expectedCatalogRevision?: string;
  readonly createFolders?: readonly string[];
  readonly writes?: readonly AnimationPackageWrite[];
  readonly deletes?: readonly AnimationPackageDelete[];
}

interface AnimationLibraryTransactionResult {
  readonly catalog: AnimationPackageCatalog;
  readonly references: readonly AnimationPackageReference[];
}

function safeFolderPath(root: string, folderPath: string): string {
  const normalized = folderPath.replaceAll('\\', '/').replace(/^\/+|\/+$/g, '');
  if (!normalized || normalized.split('/').some((segment) => !/^[a-z0-9][a-z0-9-]*$/.test(segment))) {
    throw new Error('Folder path must contain lowercase kebab-case segments');
  }
  const absolute = path.resolve(root, ...normalized.split('/'));
  if (!pathIsInside(root, absolute)) throw new Error('Folder path escapes the animation root');
  return absolute;
}

async function findNamedFiles(root: string, fileName: string): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await fs.readdir(root, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  })) {
    if (entry.name.startsWith('.')) continue;
    const absolutePath = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...await findNamedFiles(absolutePath, fileName));
    else if (entry.isFile() && entry.name === fileName) files.push(absolutePath);
  }
  return files.sort();
}

async function readAnimationReferences(root: string): Promise<readonly AnimationPackageReference[]> {
  const contentRoot = path.dirname(root);
  const repoRoot = path.resolve(contentRoot, '../../..');
  const references: AnimationPackageReference[] = [];
  for (const file of await findNamedFiles(path.join(contentRoot, 'weapons'), 'weapon.json')) {
    const value = JSON.parse(await fs.readFile(file, 'utf8')) as Record<string, unknown>;
    const ownerId = typeof value.weaponId === 'string' ? value.weaponId : path.basename(path.dirname(file));
    const animations = value.animations as Record<string, unknown> | undefined;
    if (typeof animations?.idleAnimationId === 'string') references.push({
      sourcePath: path.relative(repoRoot, file).replaceAll('\\', '/'),
      field: 'animations.idleAnimationId',
      animationId: animations.idleAnimationId,
      ownerId,
      ownerKind: 'weapon',
      expectedLoop: true,
    });
    const attacks = value.directionalAttacks as Record<string, Record<string, unknown>> | undefined;
    for (const [direction, attack] of Object.entries(attacks ?? {})) {
      if (typeof attack?.animationId !== 'string') continue;
      references.push({
        sourcePath: path.relative(repoRoot, file).replaceAll('\\', '/'),
        field: `directionalAttacks.${direction}.animationId`,
        animationId: attack.animationId,
        ownerId,
        ownerKind: 'weapon',
        expectedLoop: false,
      });
    }
  }
  for (const file of await findObjectDefinitionFiles(path.join(contentRoot, 'objects'))) {
    const value = JSON.parse(await fs.readFile(file, 'utf8')) as Record<string, unknown>;
    const ownerId = typeof value.objectId === 'string' ? value.objectId : path.basename(file, '.json');
    const variants = Array.isArray(value.variants) ? value.variants : [];
    variants.forEach((variant, variantIndex) => {
      if (variant === null || typeof variant !== 'object' || Array.isArray(variant)) return;
      const frames = Array.isArray((variant as Record<string, unknown>).frames) ? (variant as { frames: unknown[] }).frames : [];
      frames.forEach((frame, frameIndex) => {
        if (frame === null || typeof frame !== 'object' || Array.isArray(frame)) return;
        for (const field of ['idleAnimationId', 'onHitAnimationId'] as const) {
          const animationId = (frame as Record<string, unknown>)[field];
          if (typeof animationId !== 'string') continue;
          references.push({
            sourcePath: path.relative(repoRoot, file).replaceAll('\\', '/'),
            field: `variants[${variantIndex}].frames[${frameIndex}].${field}`,
            animationId,
            ownerId,
            ownerKind: 'object',
            expectedLoop: field === 'idleAnimationId',
          });
        }
      });
    });
  }
  return references;
}

async function findObjectDefinitionFiles(root: string): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await fs.readdir(root, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  })) {
    if (entry.name.startsWith('.')) continue;
    const absolutePath = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...await findObjectDefinitionFiles(absolutePath));
    else if (entry.isFile() && entry.name.endsWith('.json') && entry.name !== 'objects.schema.json') files.push(absolutePath);
  }
  return files.sort();
}

export async function applyAnimationLibraryTransaction(
  root: string,
  transaction: AnimationLibraryTransaction,
  beforeWrite?: BeforeAnimationWrite,
): Promise<AnimationLibraryTransactionResult> {
  const catalog = await readCatalog(root);
  if (transaction.expectedCatalogRevision && transaction.expectedCatalogRevision !== catalog.revision) {
    throw new Error('Animation catalog changed since it was opened');
  }
  const writes = [...(transaction.writes ?? [])];
  const deletes = [...(transaction.deletes ?? [])];
  const writePaths = new Set<string>();
  const deletePaths = new Set<string>();
  const currentByPath = new Map(catalog.packages.map((entry) => [entry.packagePath, entry]));
  const nextByPath = new Map<string, AnimationPackageDocument>(catalog.packages.map((entry) => [entry.packagePath, {
    $schema: entry.$schema,
    version: entry.version,
    animationId: entry.animationId,
    displayName: entry.displayName,
    description: entry.description,
    animation: entry.animation,
  }]));
  const normalizedWrites: Array<{ relativePath: string; absolutePath: string; value: AnimationPackageDocument }> = [];

  for (const deletion of deletes) {
    const absolutePath = safePackagePath(root, deletion.packagePath);
    const relativePath = path.relative(root, absolutePath).replaceAll('\\', '/');
    if (deletePaths.has(relativePath)) throw new Error(`Package '${relativePath}' is deleted more than once`);
    deletePaths.add(relativePath);
    const existing = currentByPath.get(relativePath);
    if (!existing) throw new Error(`Package '${relativePath}' was not found`);
    if (deletion.expectedRevision && deletion.expectedRevision !== existing.revision) throw new Error(`Package '${relativePath}' changed since it was opened`);
    nextByPath.delete(relativePath);
  }

  for (const write of writes) {
    const absolutePath = safePackagePath(root, write.packagePath);
    const relativePath = path.relative(root, absolutePath).replaceAll('\\', '/');
    if (writePaths.has(relativePath)) throw new Error(`Package '${relativePath}' is written more than once`);
    writePaths.add(relativePath);
    const existing = currentByPath.get(relativePath);
    const operation = write.operation ?? (existing ? 'update' : 'create');
    if (operation === 'create' && existing && !deletePaths.has(relativePath)) throw new Error(`Package '${relativePath}' already exists`);
    if (operation === 'update' && !existing) throw new Error(`Package '${relativePath}' was not found`);
    if (write.expectedRevision && write.expectedRevision !== existing?.revision) throw new Error(`Package '${relativePath}' changed since it was opened`);
    const value = { ...write.package, $schema: packageSchemaFor(root, absolutePath) };
    const diagnostics = validateAnimationPackage(value);
    if (diagnostics.length > 0) throw packageError(relativePath, diagnostics.map((diagnostic) => ({ ...diagnostic, packagePath: relativePath })));
    nextByPath.set(relativePath, value);
    normalizedWrites.push({ relativePath, absolutePath, value });
  }

  const byId = new Map<string, string>();
  for (const [packagePath, value] of nextByPath) {
    const diagnostics = validateAnimationPackage(value);
    if (diagnostics.length > 0) throw packageError(packagePath, diagnostics.map((diagnostic) => ({ ...diagnostic, packagePath })));
    const previous = byId.get(value.animationId);
    if (previous) throw packageError(packagePath, [{ code: 'animation-id-duplicate', packagePath, animationId: value.animationId, message: `animationId '${value.animationId}' duplicates '${previous}'` }]);
    byId.set(value.animationId, packagePath);
  }

  const references = await readAnimationReferences(root);
  const missingReferences = references.filter((reference) => !byId.has(reference.animationId));
  if (missingReferences.length > 0) {
    const first = missingReferences[0];
    throw packageError(first.sourcePath, [{
      code: 'animation-reference-in-use',
      packagePath: first.sourcePath,
      animationId: first.animationId,
      field: first.field,
      message: `Cannot remove '${first.animationId}'; ${first.ownerKind} '${first.ownerId}' still references it at ${first.field}`,
    }]);
  }
  const loopMismatch = references.find((reference) => nextByPath.get(byId.get(reference.animationId)!)?.animation.loop !== reference.expectedLoop);
  if (loopMismatch) {
    throw packageError(loopMismatch.sourcePath, [{
      code: 'animation-slot-loop-mismatch',
      packagePath: loopMismatch.sourcePath,
      animationId: loopMismatch.animationId,
      field: loopMismatch.field,
      message: `${loopMismatch.field} requires a ${loopMismatch.expectedLoop ? 'looping' : 'one-shot'} package`,
    }]);
  }

  const createFolders = [...new Set(transaction.createFolders ?? [])].map((folder) => safeFolderPath(root, folder));
  beforeWrite?.([
    ...normalizedWrites.map((write) => write.absolutePath),
    ...[...deletePaths].map((relativePath) => safePackagePath(root, relativePath)),
  ]);
  const touchedPaths = [...new Set([...deletePaths, ...writePaths])];
  const stageRoot = await fs.mkdtemp(path.join(root, '.animation-library-transaction-'));
  const backups = new Map<string, string>();
  const installed = new Set<string>();
  try {
    for (const write of normalizedWrites) {
      const staged = path.join(stageRoot, 'writes', ...write.relativePath.split('/'));
      await fs.mkdir(path.dirname(staged), { recursive: true });
      await fs.writeFile(staged, `${JSON.stringify(write.value, null, 2)}\n`, 'utf8');
    }
    for (const relativePath of touchedPaths) {
      const absolutePath = safePackagePath(root, relativePath);
      const exists = await fs.access(absolutePath).then(() => true).catch(() => false);
      if (!exists) continue;
      const backup = path.join(stageRoot, 'backups', ...relativePath.split('/'));
      await fs.mkdir(path.dirname(backup), { recursive: true });
      await fs.rename(absolutePath, backup);
      backups.set(relativePath, backup);
    }
    for (const folder of createFolders) await fs.mkdir(folder, { recursive: true });
    for (const write of normalizedWrites) {
      const staged = path.join(stageRoot, 'writes', ...write.relativePath.split('/'));
      await fs.mkdir(path.dirname(write.absolutePath), { recursive: true });
      await fs.rename(staged, write.absolutePath);
      installed.add(write.relativePath);
    }
    const nextCatalog = await readCatalog(root);
    return { catalog: nextCatalog, references };
  } catch (error) {
    for (const relativePath of installed) {
      const absolutePath = safePackagePath(root, relativePath);
      await fs.rm(absolutePath, { force: true }).catch(() => undefined);
    }
    for (const [relativePath, backup] of backups) {
      const absolutePath = safePackagePath(root, relativePath);
      await fs.mkdir(path.dirname(absolutePath), { recursive: true });
      await fs.rename(backup, absolutePath).catch(() => undefined);
    }
    throw error;
  } finally {
    await fs.rm(stageRoot, { recursive: true, force: true });
  }
}

async function saveAnimationPackage(root: string, request: IncomingMessage, response: ServerResponse, beforeWrite?: BeforeAnimationWrite): Promise<void> {
  if (request.method !== 'POST') {
    jsonResponse(response, 405, { ok: false, error: { code: 'invalid-request', message: 'POST required' } });
    return;
  }
  const payload = JSON.parse(await readRequestBody(request)) as Record<string, unknown>;
  const packageValue = payload.package;
  if (packageValue === null || typeof packageValue !== 'object' || Array.isArray(packageValue)) throw new Error('package must be an object');
  const folderPath = typeof payload.folderPath === 'string' ? payload.folderPath.replaceAll('\\', '/') : undefined;
  const requestedPath = typeof payload.packagePath === 'string'
    ? payload.packagePath.replaceAll('\\', '/')
    : folderPath
      ? `${folderPath}/animation.json`
      : undefined;
  if (!requestedPath) throw new Error('packagePath or folderPath is required');
  const result = await applyAnimationLibraryTransaction(root, {
    ...(typeof payload.expectedCatalogRevision === 'string' ? { expectedCatalogRevision: payload.expectedCatalogRevision } : {}),
    writes: [{
      packagePath: requestedPath,
      ...(typeof payload.expectedRevision === 'string' ? { expectedRevision: payload.expectedRevision } : {}),
      package: packageValue as AnimationPackageDocument,
    }],
  }, beforeWrite);
  jsonResponse(response, 200, {
    ok: true,
    data: {
      packagePath: requestedPath,
      revision: result.catalog.packages.find((entry) => entry.packagePath === requestedPath)?.revision,
      catalogRevision: result.catalog.revision,
    },
  });
}

export function animationContentModulesPlugin(options: AnimationContentRootOptions = {}): Plugin {
  const root = path.resolve(options.animationRoot ?? path.join(process.cwd(), 'src/game/content/animations'));
  const suppressHotUpdates = new Set<string>();
  const suppressEditorWriteUpdates: BeforeAnimationWrite = (paths) => {
    for (const file of paths) suppressHotUpdates.add(path.resolve(file));
  };
  return {
    name: 'slime-animation-content-modules',
    resolveId(id) {
      return id === VIRTUAL_ID ? RESOLVED_VIRTUAL_ID : undefined;
    },
    async load(id) {
      if (id !== RESOLVED_VIRTUAL_ID) return undefined;
      const packages = await discoverPackages(root);
      const imports = packages.map((entry, index) => `import animationPackage${index} from ${JSON.stringify(entry.absolutePath)};`).join('\n');
      const values = packages.map((_, index) => `animationPackage${index}`).join(', ');
      return `${imports}\nexport const animationPackages = [${values}];`;
    },
    handleHotUpdate(context) {
      const changed = path.resolve(context.file);
      const relativeChanged = path.relative(root, changed);
      if (relativeChanged.split(path.sep)[0]?.startsWith('.animation-library-transaction-')) return [];
      if (suppressHotUpdates.delete(changed)) {
        invalidateAnimationCatalog(context.server);
        return [];
      }
      if (pathIsInside(root, changed)) {
        invalidateAnimationCatalog(context.server);
        context.server.ws.send({ type: 'full-reload' });
        return [];
      }
      return undefined;
    },
    configureServer(server) {
      server.middlewares.use('/__animation-library/save', (request, response) => {
        void saveAnimationPackage(root, request, response, suppressEditorWriteUpdates)
          .then(() => invalidateAnimationCatalog(server))
          .catch((error: unknown) => jsonResponse(response, 400, {
            ok: false,
            error: { code: 'animation-package-invalid', message: error instanceof Error ? error.message : String(error) },
          }));
      });
      server.middlewares.use('/__animation-library/transaction', (request, response) => {
        if (request.method !== 'POST') {
          jsonResponse(response, 405, { ok: false, error: { code: 'invalid-request', message: 'POST required' } });
          return;
        }
        void readRequestBody(request)
          .then((body) => JSON.parse(body) as AnimationLibraryTransaction)
          .then((transaction) => applyAnimationLibraryTransaction(root, transaction, suppressEditorWriteUpdates))
          .then((result) => {
            invalidateAnimationCatalog(server);
            jsonResponse(response, 200, { ok: true, data: { catalog: result.catalog } });
          })
          .catch((error: unknown) => jsonResponse(response, 400, {
            ok: false,
            error: { code: 'animation-package-invalid', message: error instanceof Error ? error.message : String(error) },
          }));
      });
      server.middlewares.use('/__animation-library/references', (request, response) => {
        if (request.method !== 'GET') {
          jsonResponse(response, 405, { ok: false, error: { code: 'invalid-request', message: 'GET required' } });
          return;
        }
        const animationId = new URL(request.url ?? '', 'http://animation-library.local').searchParams.get('animationId');
        void readAnimationReferences(root)
          .then((references) => jsonResponse(response, 200, {
            ok: true,
            data: references.filter((reference) => !animationId || reference.animationId === animationId),
          }))
          .catch((error: unknown) => jsonResponse(response, 500, {
            ok: false,
            error: { code: 'animation-package-invalid', message: error instanceof Error ? error.message : String(error) },
          }));
      });
      server.middlewares.use('/__animation-library/catalog', (request, response) => {
        if (request.method !== 'GET') {
          jsonResponse(response, 405, { ok: false, error: { code: 'invalid-request', message: 'GET required' } });
          return;
        }
        void readCatalog(root)
          .then((catalog) => jsonResponse(response, 200, { ok: true, data: catalog }))
          .catch((error: unknown) => jsonResponse(response, 500, {
            ok: false,
            error: {
              code: 'animation-package-invalid',
              message: error instanceof Error ? error.message : String(error),
            },
          }));
      });
    },
  };
}

export { findAnimationPackageFiles, discoverPackages, readCatalog };
