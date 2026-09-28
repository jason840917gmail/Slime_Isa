import { promises as fs } from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import path from 'node:path';

import type { Plugin } from 'vite';

import { ASSET_MANIFEST } from '../../assets/manifest';
import { SERIALIZED_ID_PATTERN } from '../../../content/scenes/identifiers';
import type { DescriptorRegistry } from '../../../content/scenes/propertyDescriptors';
import { createGameDescriptorRegistry } from '../../../features/scripts/registrations';
import { SceneCatalog } from '../../../content/scenes/SceneCatalog';
import type { SceneResourceDocument } from '../../../content/scenes/resources/types';
import type { SceneDocument } from '../../../content/scenes/types';
import {
  canonicalSceneJson,
  validateSceneDocument,
  validateSceneResourceDocument,
  type SceneValidationContext,
  type SceneValidationIssue,
} from '../../../content/scenes/validation';
import { ContentWriteJournal, contentHash, type ContentWrite } from './ContentWriteJournal';
import type {
  SceneStudioContentKind,
  SceneStudioContentRecord,
  SceneStudioContentSummary,
  SceneStudioWriteRequest,
  SceneStudioWriteResult,
} from './SceneStudioRepository';

const ENDPOINT = '/__scene-studio/content';
const DEFAULT_MAX_BODY_BYTES = 2 * 1024 * 1024;

export interface SceneStudioContentPluginOptions {
  readonly contentRoot?: string;
  readonly registry?: DescriptorRegistry;
  readonly maxBodyBytes?: number;
  readonly journal?: ContentWriteJournal;
  readonly hasAsset?: (assetId: string) => boolean;
}

interface IndexedContent extends SceneStudioContentSummary {
  readonly absolutePath: string;
  readonly document: unknown;
  readonly source: string;
}

interface WritePayload {
  readonly writes: readonly SceneStudioWriteRequest[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function kindForPath(relativePath: string): SceneStudioContentKind | undefined {
  if (relativePath.endsWith('.scene.json')) return 'scene';
  if (relativePath.endsWith('.resource.json')) return 'resource';
  return undefined;
}

function documentId(kind: SceneStudioContentKind, document: unknown): unknown {
  if (!isRecord(document)) return undefined;
  return kind === 'scene' ? document.sceneId : document.resourceId;
}

function normalizeContentPath(value: string, kind: SceneStudioContentKind): string {
  if (value.length === 0 || value.includes('\\') || path.isAbsolute(value)) throw new Error(`Unsafe content path '${value}'`);
  const normalized = path.posix.normalize(value);
  if (normalized === '.' || normalized.startsWith('../') || normalized.includes('/../')) throw new Error(`Unsafe content path '${value}'`);
  if (kindForPath(normalized) !== kind) throw new Error(`Content path '${value}' does not match kind '${kind}'`);
  return normalized;
}

async function discoverFiles(root: string): Promise<readonly string[]> {
  const files: string[] = [];
  const visit = async (current: string): Promise<void> => {
    let entries;
    try { entries = await fs.readdir(current, { withFileTypes: true }); } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return;
      throw error;
    }
    for (const entry of entries) {
      if (entry.name === JOURNAL_FOLDER) continue;
      const candidate = path.join(current, entry.name);
      if (entry.isDirectory()) await visit(candidate);
      else if (entry.isFile() && kindForPath(entry.name)) files.push(candidate);
    }
  };
  await visit(root);
  return files.sort();
}

const FOLDER_SEGMENT_PATTERN = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/;
const JOURNAL_FOLDER = '.scene-studio-transactions';

/** Every folder under the content root (relative, `/`-separated), including empty ones. */
async function discoverFolders(root: string): Promise<readonly string[]> {
  const folders: string[] = [];
  const visit = async (current: string, relative: string): Promise<void> => {
    let entries;
    try { entries = await fs.readdir(current, { withFileTypes: true }); } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return;
      throw error;
    }
    for (const entry of entries) {
      if (!entry.isDirectory() || entry.name === JOURNAL_FOLDER) continue;
      const child = relative ? `${relative}/${entry.name}` : entry.name;
      folders.push(child);
      await visit(path.join(current, entry.name), child);
    }
  };
  await visit(root, '');
  return folders.sort();
}

/** A new folder path of lowercase ID-style segments, e.g. `worlds/caves`. */
function normalizeFolderPath(value: unknown): string {
  if (typeof value !== 'string') throw new Error('Folder relativePath is required');
  const segments = value.split('/');
  if (segments.some((segment) => !FOLDER_SEGMENT_PATTERN.test(segment))) {
    throw new Error(`Folder '${value}' must use lowercase letters, digits, '.', '_' or '-' in each segment`);
  }
  return segments.join('/');
}

async function contentIndex(root: string): Promise<readonly IndexedContent[]> {
  const output: IndexedContent[] = [];
  const seen = new Set<string>();
  for (const absolutePath of await discoverFiles(root)) {
    const relativePath = path.relative(root, absolutePath).replaceAll('\\', '/');
    const kind = kindForPath(relativePath);
    if (!kind) continue;
    const source = await fs.readFile(absolutePath, 'utf8');
    let document: unknown;
    try { document = JSON.parse(source); } catch (error) {
      throw new Error(`Malformed JSON in '${relativePath}': ${error instanceof Error ? error.message : String(error)}`);
    }
    const id = documentId(kind, document);
    if (typeof id !== 'string' || !SERIALIZED_ID_PATTERN.test(id)) throw new Error(`Invalid ${kind} ID in '${relativePath}'`);
    const key = `${kind}:${id}`;
    if (seen.has(key)) throw new Error(`Duplicate ${kind} ID '${id}'`);
    seen.add(key);
    output.push({ kind, id, relativePath, absolutePath, document, source });
  }
  return output.sort((left, right) => left.relativePath.localeCompare(right.relativePath));
}

function validationContext(
  registry: DescriptorRegistry,
  resources: ReadonlyMap<string, SceneResourceDocument>,
  hasAsset: (assetId: string) => boolean,
): SceneValidationContext {
  return {
    registry,
    hasAsset,
    hasResource: (resourceId) => resources.has(resourceId),
    getResourceKind: (resourceId) => resources.get(resourceId)?.kind,
  };
}

function issuesFor(item: IndexedContent, context: SceneValidationContext): readonly SceneValidationIssue[] {
  return item.kind === 'scene'
    ? validateSceneDocument(item.document, context)
    : validateSceneResourceDocument(item.document, context);
}

function canonicalDocument(kind: SceneStudioContentKind, document: unknown): string {
  return kind === 'scene'
    ? canonicalSceneJson(document as SceneDocument)
    : `${JSON.stringify(document, null, 2)}\n`;
}

async function readBody(request: IncomingMessage, maximum: number): Promise<string> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const value = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += value.length;
    if (size > maximum) throw new Error(`Scene Studio payload exceeds ${maximum} bytes`);
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function send(response: ServerResponse, status: number, body: unknown): void {
  response.statusCode = status;
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.end(JSON.stringify(body));
}

function parsePayload(value: unknown): WritePayload {
  if (!isRecord(value) || !Array.isArray(value.writes) || value.writes.length === 0) throw new Error('A complete non-empty write set is required');
  const writes: SceneStudioWriteRequest[] = [];
  for (const raw of value.writes) {
    if (!isRecord(raw)) throw new Error('Invalid Scene Studio write');
    const allowed = new Set(['kind', 'id', 'relativePath', 'document', 'expectedHash']);
    for (const key of Object.keys(raw)) if (!allowed.has(key)) throw new Error(`Unknown write field '${key}'`);
    if (raw.kind !== 'scene' && raw.kind !== 'resource') throw new Error('Write kind must be scene or resource');
    if (typeof raw.id !== 'string' || !SERIALIZED_ID_PATTERN.test(raw.id)) throw new Error(`Invalid ${raw.kind} ID '${String(raw.id)}'`);
    if (typeof raw.relativePath !== 'string') throw new Error('Write relativePath is required');
    const relativePath = normalizeContentPath(raw.relativePath, raw.kind);
    if (raw.expectedHash !== null && (typeof raw.expectedHash !== 'string' || !/^[a-f0-9]{64}$/.test(raw.expectedHash))) {
      throw new Error(`Invalid expected hash for '${relativePath}'`);
    }
    if (documentId(raw.kind, raw.document) !== raw.id) throw new Error(`${raw.kind} ID does not match document at '${relativePath}'`);
    writes.push({ kind: raw.kind, id: raw.id, relativePath, document: raw.document as SceneDocument | SceneResourceDocument, expectedHash: raw.expectedHash });
  }
  return { writes };
}

async function validateWriteSet(
  root: string,
  indexed: readonly IndexedContent[],
  writes: readonly SceneStudioWriteRequest[],
  registry: DescriptorRegistry,
  hasAsset: (assetId: string) => boolean,
): Promise<readonly ContentWrite[]> {
  const byPath = new Map(indexed.map((item) => [item.relativePath, item]));
  const keys = new Set<string>();
  for (const write of writes) {
    const key = `${write.kind}:${write.id}`;
    if (keys.has(key)) throw new Error(`Duplicate write for ${write.kind} '${write.id}'`);
    keys.add(key);
    const pathOwner = byPath.get(write.relativePath);
    if (pathOwner && (pathOwner.kind !== write.kind || pathOwner.id !== write.id)) {
      throw new Error(`Content path '${write.relativePath}' belongs to ${pathOwner.kind} '${pathOwner.id}'`);
    }
    const idOwner = indexed.find((item) => item.kind === write.kind && item.id === write.id);
    if (idOwner && idOwner.relativePath !== write.relativePath) {
      throw new Error(`${write.kind} '${write.id}' belongs to '${idOwner.relativePath}'`);
    }
    byPath.set(write.relativePath, {
      kind: write.kind,
      id: write.id,
      relativePath: write.relativePath,
      absolutePath: path.resolve(root, ...write.relativePath.split('/')),
      document: write.document,
      source: canonicalDocument(write.kind, write.document),
    });
  }

  const all = [...byPath.values()];
  const resources = new Map<string, SceneResourceDocument>();
  for (const item of all) {
    if (item.kind !== 'resource') continue;
    if (resources.has(item.id)) throw new Error(`Duplicate resource ID '${item.id}'`);
    resources.set(item.id, item.document as SceneResourceDocument);
  }
  const context = validationContext(registry, resources, hasAsset);
  for (const write of writes) {
    const item = byPath.get(write.relativePath);
    if (!item) throw new Error(`Missing staged content '${write.relativePath}'`);
    const issues = issuesFor(item, context);
    if (issues.length > 0) throw new Error(issues.map((issue) => `${write.relativePath}${issue.path}: ${issue.message}`).join('\n'));
  }

  const allScenes = new Map(all.filter((item) => item.kind === 'scene').map((item) => [item.id, item.document as SceneDocument]));
  const changedResourceIds = new Set(writes.filter((write) => write.kind === 'resource').map((write) => write.id));
  const nestedIds = (value: unknown, key: 'sceneId' | 'resourceId', output = new Set<string>()): ReadonlySet<string> => {
    if (Array.isArray(value)) for (const entry of value) nestedIds(entry, key, output);
    else if (isRecord(value)) {
      if (typeof value[key] === 'string') output.add(value[key]);
      for (const nested of Object.values(value)) nestedIds(nested, key, output);
    }
    return output;
  };
  const catalogIds = new Set(writes.filter((write) => write.kind === 'scene').map((write) => write.id));
  if (changedResourceIds.size > 0) {
    for (const [id, document] of allScenes) {
      if ([...nestedIds(document, 'resourceId')].some((resourceId) => changedResourceIds.has(resourceId))) catalogIds.add(id);
    }
  }
  const queue = [...catalogIds];
  for (let index = 0; index < queue.length; index += 1) {
    const document = allScenes.get(queue[index]);
    if (!document) continue;
    for (const referencedId of nestedIds(document, 'sceneId')) {
      if (referencedId === document.sceneId || catalogIds.has(referencedId)) continue;
      catalogIds.add(referencedId);
      queue.push(referencedId);
    }
  }
  if (catalogIds.size > 0) {
    const catalogDocuments = [...catalogIds].flatMap((id) => {
      const document = allScenes.get(id);
      return document ? [document] : [];
    });
    new SceneCatalog(catalogDocuments, context);
  }
  return writes.map((write) => ({ relativePath: write.relativePath, content: canonicalDocument(write.kind, write.document), expectedHash: write.expectedHash }));
}

export function sceneStudioContentPlugin(options: SceneStudioContentPluginOptions = {}): Plugin {
  const root = path.resolve(options.contentRoot ?? path.join(process.cwd(), 'src/game/content/scenes/authored'));
  const registry = options.registry ?? createGameDescriptorRegistry();
  const maximum = options.maxBodyBytes ?? DEFAULT_MAX_BODY_BYTES;
  const hasAsset = options.hasAsset ?? ((assetId: string) => Object.hasOwn(ASSET_MANIFEST.assets, assetId));
  const journal = options.journal ?? new ContentWriteJournal(root);
  let writeQueue = Promise.resolve();

  return {
    name: 'slime-scene-studio-content',
    async configureServer(server) {
      await fs.mkdir(root, { recursive: true });
      await journal.recover();
      server.middlewares.use(ENDPOINT, async (request, response) => {
        try {
          const url = new URL(request.url ?? '/', 'http://scene-studio.local');
          if (request.method === 'GET') {
            const indexed = await contentIndex(root);
            if (url.searchParams.get('action') === 'list') {
              send(response, 200, { items: indexed.map(({ kind, id, relativePath }) => ({ kind, id, relativePath })), folders: await discoverFolders(root) });
              return;
            }
            if (url.searchParams.get('action') !== 'load') throw new Error('Unknown Scene Studio read action');
            const kind = url.searchParams.get('kind');
            const id = url.searchParams.get('id');
            if ((kind !== 'scene' && kind !== 'resource') || !id || !SERIALIZED_ID_PATTERN.test(id)) throw new Error('Valid content kind and ID are required');
            const item = indexed.find((candidate) => candidate.kind === kind && candidate.id === id);
            if (!item) { send(response, 404, { error: `Unknown ${kind} '${id}'` }); return; }
            const resources = new Map(indexed.filter((candidate) => candidate.kind === 'resource').map((candidate) => [candidate.id, candidate.document as SceneResourceDocument]));
            const issues = issuesFor(item, validationContext(registry, resources, hasAsset));
            const record: SceneStudioContentRecord = {
              kind: item.kind,
              id: item.id,
              relativePath: item.relativePath,
              document: item.document as SceneDocument | SceneResourceDocument,
              hash: contentHash(item.source),
              repairMode: issues.length > 0,
              issues,
            };
            send(response, 200, { item: record });
            return;
          }
          if (request.method !== 'POST') { send(response, 405, { error: 'GET or POST required' }); return; }
          if (url.searchParams.get('action') === 'create-folder') {
            const body = JSON.parse(await readBody(request, maximum)) as unknown;
            const relativePath = normalizeFolderPath(isRecord(body) ? body.relativePath : undefined);
            const target = path.resolve(root, ...relativePath.split('/'));
            if (await fs.stat(target).then(() => true, () => false)) throw new Error(`Folder '${relativePath}' already exists`);
            await fs.mkdir(target, { recursive: true });
            send(response, 200, { relativePath });
            return;
          }
          const payload = parsePayload(JSON.parse(await readBody(request, maximum)));
          const execute = async (): Promise<readonly SceneStudioWriteResult[]> => {
            const indexed = await contentIndex(root);
            const journalWrites = await validateWriteSet(root, indexed, payload.writes, registry, hasAsset);
            const results = await journal.commit(journalWrites);
            return results.map((result) => {
              const write = payload.writes.find((candidate) => candidate.relativePath === result.relativePath);
              if (!write) throw new Error(`Committed unknown content path '${result.relativePath}'`);
              return { kind: write.kind, id: write.id, relativePath: result.relativePath, hash: result.hash };
            });
          };
          const pending = writeQueue.then(execute, execute);
          writeQueue = pending.then(() => undefined, () => undefined);
          send(response, 200, { writes: await pending });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          const status = message.startsWith('Content conflict') ? 409 : message.includes('payload exceeds') ? 413 : 400;
          send(response, status, { error: message });
        }
      });
    },
  };
}

export { ENDPOINT as SCENE_STUDIO_CONTENT_ENDPOINT };
