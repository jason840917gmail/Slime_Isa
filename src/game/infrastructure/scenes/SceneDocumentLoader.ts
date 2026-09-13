import type { SceneId } from '../../content/scenes/identifiers';
import type { SceneDocument } from '../../content/scenes/types';
import type { SceneCatalog } from '../../content/scenes/SceneCatalog';

export interface SceneDocumentLease {
  readonly document: SceneDocument;
  release(): void;
}

interface CacheEntry {
  readonly promise: Promise<SceneDocument>;
  document?: SceneDocument;
  leases: number;
}

function aborted(): Error {
  const error = new Error('Scene document load was aborted');
  error.name = 'AbortError';
  return error;
}

function waitFor<T>(promise: Promise<T>, signal?: AbortSignal): Promise<T> {
  if (!signal) return promise;
  if (signal.aborted) return Promise.reject(aborted());
  return new Promise<T>((resolve, reject) => {
    const onAbort = (): void => reject(aborted());
    signal.addEventListener('abort', onAbort, { once: true });
    promise.then(
      (value) => { signal.removeEventListener('abort', onAbort); if (signal.aborted) reject(aborted()); else resolve(value); },
      (error: unknown) => { signal.removeEventListener('abort', onAbort); reject(error); },
    );
  });
}

function immutableDocument(document: SceneDocument): SceneDocument {
  const copy = structuredClone(document);
  const freeze = (value: unknown): void => {
    if (!value || typeof value !== 'object' || Object.isFrozen(value)) return;
    Object.freeze(value);
    for (const nested of Object.values(value)) freeze(nested);
  };
  freeze(copy);
  return copy;
}

export class SceneDocumentLoader {
  private readonly cache = new Map<SceneId, CacheEntry>();

  constructor(private readonly loadDocument: (sceneId: SceneId) => Promise<SceneDocument>) {}

  static fromCatalog(catalog: SceneCatalog): SceneDocumentLoader {
    return new SceneDocumentLoader(async (sceneId) => {
      const document = catalog.get(sceneId);
      if (!document) throw new Error(`Unknown scene '${sceneId}'`);
      return document;
    });
  }

  async acquire(sceneId: SceneId, signal?: AbortSignal): Promise<SceneDocumentLease> {
    let entry = this.cache.get(sceneId);
    if (!entry) {
      const created: CacheEntry = { leases: 0, promise: Promise.resolve().then(() => this.loadDocument(sceneId)).then(immutableDocument) };
      created.promise.then((document) => { created.document = document; }, () => { if (this.cache.get(sceneId) === created) this.cache.delete(sceneId); });
      this.cache.set(sceneId, created);
      entry = created;
    }
    const document = entry.document ?? await waitFor(entry.promise, signal);
    if (signal?.aborted) throw aborted();
    entry.leases += 1;
    let released = false;
    return {
      document,
      release: () => { if (released) return; released = true; entry.leases -= 1; },
    };
  }

  activeLeaseCount(sceneId?: SceneId): number {
    if (sceneId) return this.cache.get(sceneId)?.leases ?? 0;
    return [...this.cache.values()].reduce((total, entry) => total + entry.leases, 0);
  }

  hasCached(sceneId: SceneId): boolean { return this.cache.get(sceneId)?.document !== undefined; }
  clearUnused(): void { for (const [sceneId, entry] of this.cache) if (entry.leases === 0 && entry.document) this.cache.delete(sceneId); }
}
