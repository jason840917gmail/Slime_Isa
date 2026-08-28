import { createHash, randomUUID } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import type { Plugin, ViteDevServer } from 'vite';

import type { GameConstants } from '../Constant';
import { normalizeGameConstants, validateGameConstants } from './GameConstantsValidation';

const ENDPOINT = '/__game-constants';
const MAX_BODY_BYTES = 2 * 1024 * 1024;

export interface GameConstantsContentPluginOptions {
  readonly constantsPath?: string;
  readonly writeAtomic?: (target: string, content: string) => Promise<void>;
}

export interface GameConstantsContentSnapshot {
  readonly document: GameConstants;
  readonly revision: string;
}

export class GameConstantsRevisionConflictError extends Error {
  constructor(public readonly currentRevision: string) {
    super('Gameplay configuration changed on disk. Reload before saving again.');
    this.name = 'GameConstantsRevisionConflictError';
  }
}

function revision(content: string): string {
  return createHash('sha256').update(content).digest('hex');
}

async function defaultWriteAtomic(target: string, content: string): Promise<void> {
  const temporary = path.join(path.dirname(target), `.${path.basename(target)}.${randomUUID()}.tmp`);
  try {
    await fs.writeFile(temporary, content, 'utf8');
    await fs.rename(temporary, target);
  } catch (error) {
    await fs.rm(temporary, { force: true }).catch(() => undefined);
    throw error;
  }
}

export async function readGameConstantsContent(constantsPath: string): Promise<GameConstantsContentSnapshot> {
  const content = await fs.readFile(constantsPath, 'utf8');
  return { document: normalizeGameConstants(JSON.parse(content) as unknown), revision: revision(content) };
}

export async function saveGameConstantsContent(
  constantsPath: string,
  expectedRevision: string,
  value: unknown,
  writeAtomic: (target: string, content: string) => Promise<void> = defaultWriteAtomic,
): Promise<GameConstantsContentSnapshot> {
  const current = await readGameConstantsContent(constantsPath);
  if (current.revision !== expectedRevision) throw new GameConstantsRevisionConflictError(current.revision);
  const document = normalizeGameConstants(value);
  const content = `${JSON.stringify(document, null, 2)}\n`;
  await writeAtomic(constantsPath, content);
  return { document, revision: revision(content) };
}

async function requestBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > MAX_BODY_BYTES) throw new Error('Request body is too large');
    chunks.push(buffer);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
}

function respond(response: ServerResponse, status: number, body: unknown): void {
  response.statusCode = status;
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.end(JSON.stringify(body));
}

function invalidateConstants(server: ViteDevServer, constantsPath: string): void {
  const seen = new Set<unknown>();
  for (const module of server.moduleGraph.getModulesByFile(constantsPath) ?? []) {
    server.moduleGraph.invalidateModule(module, seen as Set<never>, Date.now(), true);
  }
}

export function gameConstantsContentPlugin(options: GameConstantsContentPluginOptions = {}): Plugin {
  const constantsPath = path.resolve(options.constantsPath ?? path.join(process.cwd(), 'src/game/content/game-constants.json'));
  return {
    name: 'slime-isa-game-constants-content',
    configureServer(server) {
      server.middlewares.use(ENDPOINT, async (request, response) => {
        try {
          if (request.method === 'GET') {
            respond(response, 200, { ok: true, data: await readGameConstantsContent(constantsPath) });
            return;
          }
          if (request.method !== 'POST') {
            respond(response, 405, { ok: false, error: { code: 'method_not_allowed', message: 'Use GET or POST.' } });
            return;
          }
          const payload = await requestBody(request);
          if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) throw new Error('Request body must be an object');
          const expectedRevision = (payload as Record<string, unknown>).expectedRevision;
          const document = (payload as Record<string, unknown>).document;
          if (typeof expectedRevision !== 'string') throw new Error('expectedRevision must be a string');
          const saved = await saveGameConstantsContent(constantsPath, expectedRevision, document, options.writeAtomic);
          invalidateConstants(server, constantsPath);
          respond(response, 200, { ok: true, data: saved });
        } catch (error) {
          if (error instanceof GameConstantsRevisionConflictError) {
            respond(response, 409, { ok: false, error: { code: 'revision_conflict', message: error.message, currentRevision: error.currentRevision } });
            return;
          }
          const issues = error !== null && typeof error === 'object' && 'issues' in error
            ? (error as { issues: unknown }).issues
            : validateGameConstants((error as { value?: unknown })?.value);
          respond(response, 400, { ok: false, error: { code: 'invalid_game_constants', message: error instanceof Error ? error.message : String(error), ...(Array.isArray(issues) && issues.length > 0 ? { issues } : {}) } });
        }
      });
    },
  };
}
