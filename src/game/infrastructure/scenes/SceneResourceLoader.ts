import type { ResourceId } from '../../content/scenes/identifiers';
import type { SceneResourceDocument } from '../../content/scenes/types';

export interface SceneResourceLease {
  readonly resource: SceneResourceDocument;
  release(): void;
}

interface CacheEntry {
  readonly promise: Promise<SceneResourceDocument>;
  resource?: SceneResourceDocument;
  leases: number;
}

function abortError(): Error { const error = new Error('Scene resource load was aborted'); error.name = 'AbortError'; return error; }

function awaitAbortable<T>(promise: Promise<T>, signal?: AbortSignal): Promise<T> {
  if (!signal) return promise;
  if (signal.aborted) return Promise.reject(abortError());
  return new Promise<T>((resolve, reject) => {
    const onAbort = (): void => reject(abortError());
    signal.addEventListener('abort', onAbort, { once: true });
    promise.then(
      (value) => { signal.removeEventListener('abort', onAbort); if (signal.aborted) reject(abortError()); else resolve(value); },
      (error: unknown) => { signal.removeEventListener('abort', onAbort); reject(error); },
    );
  });
}

function immutableResource(resource: SceneResourceDocument): SceneResourceDocument {
  const copy = structuredClone(resource);
  const freeze = (value: unknown): void => { if (!value || typeof value !== 'object' || Object.isFrozen(value)) return; Object.freeze(value); for (const nested of Object.values(value)) freeze(nested); };
  freeze(copy);
  return copy;
}

export class SceneResourceLoader {
  private readonly cache = new Map<ResourceId, CacheEntry>();

  constructor(private readonly loadResource: (resourceId: ResourceId) => Promise<SceneResourceDocument>) {}

  async acquire(resourceId: ResourceId, signal?: AbortSignal): Promise<SceneResourceLease> {
    let entry = this.cache.get(resourceId);
    if (!entry) {
      const created: CacheEntry = { leases: 0, promise: Promise.resolve().then(() => this.loadResource(resourceId)).then(immutableResource) };
      created.promise.then((resource) => { created.resource = resource; }, () => { if (this.cache.get(resourceId) === created) this.cache.delete(resourceId); });
      this.cache.set(resourceId, created);
      entry = created;
    }
    const resource = entry.resource ?? await awaitAbortable(entry.promise, signal);
    if (signal?.aborted) throw abortError();
    entry.leases += 1;
    let released = false;
    return { resource, release: () => { if (released) return; released = true; entry.leases -= 1; } };
  }

  activeLeaseCount(resourceId?: ResourceId): number {
    if (resourceId) return this.cache.get(resourceId)?.leases ?? 0;
    return [...this.cache.values()].reduce((total, entry) => total + entry.leases, 0);
  }

  hasCached(resourceId: ResourceId): boolean { return this.cache.get(resourceId)?.resource !== undefined; }
  clearUnused(): void { for (const [resourceId, entry] of this.cache) if (entry.leases === 0 && entry.resource) this.cache.delete(resourceId); }
}
