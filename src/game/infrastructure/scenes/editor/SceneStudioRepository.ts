import type { SceneValidationIssue } from '../../../content/scenes/validation';
import type { SceneResourceDocument } from '../../../content/scenes/resources/types';
import type { SceneDocument } from '../../../content/scenes/types';

export type SceneStudioContentKind = 'scene' | 'resource';
export type SceneStudioDocument = SceneDocument | SceneResourceDocument;

export interface SceneStudioContentSummary {
  readonly kind: SceneStudioContentKind;
  readonly id: string;
  readonly relativePath: string;
  /** Representative sprite frame for the explorer thumbnail, when one resolves. */
  readonly portrait?: SceneStudioPortrait;
}

export interface SceneStudioPortrait {
  readonly assetId: string;
  readonly frame: number;
  /** Frame size from a sprite-sheet resource; otherwise the asset manifest's frame geometry applies. */
  readonly frameWidth?: number;
  readonly frameHeight?: number;
}

export interface SceneStudioContentRecord extends SceneStudioContentSummary {
  readonly document: SceneStudioDocument;
  readonly hash: string;
  readonly repairMode: boolean;
  readonly issues: readonly SceneValidationIssue[];
}

export interface SceneStudioContentIndex {
  readonly items: readonly SceneStudioContentSummary[];
  readonly folders: readonly string[];
}

export interface SceneStudioWriteRequest extends SceneStudioContentSummary {
  readonly document: SceneStudioDocument;
  readonly expectedHash: string | null;
}

export interface SceneStudioWriteResult extends SceneStudioContentSummary {
  readonly hash: string;
}

export class SceneStudioRepositoryError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = 'SceneStudioRepositoryError';
  }
}

export class SceneStudioConflictError extends SceneStudioRepositoryError {
  constructor(message: string) {
    super(message, 409);
    this.name = 'SceneStudioConflictError';
  }
}

type Fetch = typeof fetch;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export class SceneStudioRepository {
  constructor(
    private readonly endpoint = '/__scene-studio/content',
    private readonly request: Fetch = (input, init) => globalThis.fetch(input, init),
  ) {}

  async list(): Promise<readonly SceneStudioContentSummary[]> {
    return (await this.index()).items;
  }

  /** Documents plus every folder under the content root, so empty folders still show. */
  async index(): Promise<SceneStudioContentIndex> {
    const payload = await this.#readJson(`${this.endpoint}?action=list`);
    if (!isRecord(payload) || !Array.isArray(payload.items)) throw new Error('Scene Studio returned an invalid content list');
    const folders = Array.isArray(payload.folders) ? payload.folders.filter((folder): folder is string => typeof folder === 'string') : [];
    return { items: payload.items as unknown as readonly SceneStudioContentSummary[], folders };
  }

  /** Creates an (empty) folder under the content root; `relativePath` like `worlds/caves`. */
  async createFolder(relativePath: string): Promise<string> {
    const response = await this.request(`${this.endpoint}?action=create-folder`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ relativePath }),
    });
    const payload = await response.json().catch(() => undefined) as unknown;
    if (!response.ok) {
      const message = isRecord(payload) && typeof payload.error === 'string' ? payload.error : `Scene Studio folder creation failed (${response.status})`;
      throw new SceneStudioRepositoryError(message, response.status);
    }
    if (!isRecord(payload) || typeof payload.relativePath !== 'string') throw new Error('Scene Studio returned an invalid folder result');
    return payload.relativePath;
  }

  /**
   * Moves a document into `folder` (`''` is the content root), keeping its file
   * name unless `fileName` renames it (e.g. into a variant family).
   */
  async move(kind: SceneStudioContentKind, id: string, folder: string, fileName?: string): Promise<SceneStudioContentSummary> {
    const response = await this.request(`${this.endpoint}?action=move`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(fileName === undefined ? { kind, id, folder } : { kind, id, folder, fileName }),
    });
    const payload = await response.json().catch(() => undefined) as unknown;
    if (!response.ok) {
      const message = isRecord(payload) && typeof payload.error === 'string' ? payload.error : `Scene Studio move failed (${response.status})`;
      throw new SceneStudioRepositoryError(message, response.status);
    }
    if (!isRecord(payload) || !isRecord(payload.item) || typeof payload.item.relativePath !== 'string') throw new Error('Scene Studio returned an invalid move result');
    return payload.item as unknown as SceneStudioContentSummary;
  }

  async load(kind: SceneStudioContentKind, id: string): Promise<SceneStudioContentRecord> {
    const query = new URLSearchParams({ action: 'load', kind, id });
    const payload = await this.#readJson(`${this.endpoint}?${query.toString()}`);
    if (!isRecord(payload) || !isRecord(payload.item)) throw new Error('Scene Studio returned an invalid content document');
    return payload.item as unknown as SceneStudioContentRecord;
  }

  async save(writes: readonly SceneStudioWriteRequest[]): Promise<readonly SceneStudioWriteResult[]> {
    const response = await this.request(this.endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ writes }),
    });
    const payload = await response.json().catch(() => undefined) as unknown;
    if (!response.ok) {
      const message = isRecord(payload) && typeof payload.error === 'string' ? payload.error : `Scene Studio save failed (${response.status})`;
      if (response.status === 409) throw new SceneStudioConflictError(message);
      throw new SceneStudioRepositoryError(message, response.status);
    }
    if (!isRecord(payload) || !Array.isArray(payload.writes)) throw new Error('Scene Studio returned an invalid save result');
    return payload.writes as unknown as readonly SceneStudioWriteResult[];
  }

  async #readJson(url: string): Promise<unknown> {
    const response = await this.request(url, { headers: { Accept: 'application/json' } });
    const payload = await response.json().catch(() => undefined) as unknown;
    if (!response.ok) {
      const message = isRecord(payload) && typeof payload.error === 'string' ? payload.error : `Scene Studio request failed (${response.status})`;
      throw new SceneStudioRepositoryError(message, response.status);
    }
    return payload;
  }
}
