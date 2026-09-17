import { SceneCatalog } from '../../content/scenes/SceneCatalog';
import type { DescriptorRegistry } from '../../content/scenes/propertyDescriptors';
import type { ResourceId, SceneId } from '../../content/scenes/identifiers';
import type { SceneDocument, SceneResourceDocument } from '../../content/scenes/types';
import type { PackedScene } from '../../runtime/scene/PackedScene';
import { SceneResolver } from '../../runtime/scene/resolution/SceneResolver';
import { SceneDocumentLoader } from './SceneDocumentLoader';
import { SceneResourceLoader } from './SceneResourceLoader';

export const PREPARED_SCENE_CONTENT_KEY = 'universal-scene-content';

export interface PreparedSceneContentOptions {
  readonly scenes: readonly SceneDocument[];
  readonly resources: readonly SceneResourceDocument[];
  readonly registry: DescriptorRegistry;
  readonly sceneIds: readonly SceneId[];
  readonly hasAsset?: (assetId: string) => boolean;
}

export class PreparedSceneContent {
  private readonly packed = new Map<SceneId, PackedScene>();
  private stopped = false;

  private constructor(
    readonly catalog: SceneCatalog,
    readonly resources: ReadonlyMap<ResourceId, SceneResourceDocument>,
    readonly documents: SceneDocumentLoader,
    readonly resourceLoader: SceneResourceLoader,
    private readonly registry: DescriptorRegistry,
  ) {}

  static async prepare(options: PreparedSceneContentOptions): Promise<PreparedSceneContent> {
    const resources = new Map<ResourceId, SceneResourceDocument>();
    for (const resource of options.resources) {
      if (resources.has(resource.resourceId)) throw new Error(`Duplicate scene resource '${resource.resourceId}'`);
      resources.set(resource.resourceId, resource);
    }
    const resourceContext = {
      hasAsset: options.hasAsset,
      hasResource: (resourceId: string) => resources.has(resourceId as ResourceId),
      getResourceKind: (resourceId: string) => resources.get(resourceId as ResourceId)?.kind,
    };
    const catalog = new SceneCatalog(options.scenes, { registry: options.registry, ...resourceContext });
    const documents = SceneDocumentLoader.fromCatalog(catalog);
    const resourceLoader = new SceneResourceLoader(async (resourceId) => {
      const resource = resources.get(resourceId);
      if (!resource) throw new Error(`Unknown scene resource '${resourceId}'`);
      return resource;
    });
    const prepared = new PreparedSceneContent(catalog, resources, documents, resourceLoader, options.registry);
    try {
      for (const sceneId of [...new Set(options.sceneIds)].sort()) {
        await prepared.ensure(sceneId);
      }
      return prepared;
    } catch (error) {
      prepared.dispose();
      throw error;
    }
  }

  get(sceneId: SceneId): PackedScene {
    if (this.stopped) throw new Error('Prepared scene content has been disposed');
    const packed = this.packed.get(sceneId);
    if (!packed) throw new Error(`Scene '${sceneId}' was not prepared for runtime use`);
    return packed;
  }

  async ensure(sceneId: SceneId, signal?: AbortSignal): Promise<PackedScene> {
    if (this.stopped) throw new Error('Prepared scene content has been disposed');
    if (signal?.aborted) throw abortError();
    const existing = this.packed.get(sceneId);
    if (existing) return existing;

    const resolver = new SceneResolver({
      documents: this.documents,
      resources: this.resourceLoader,
      registry: this.registry,
    });
    const candidate = await resolver.prepare_scene(sceneId, signal);
    if (this.stopped || signal?.aborted) {
      candidate.dispose();
      if (signal?.aborted) throw abortError();
      throw new Error('Prepared scene content was disposed while loading');
    }
    const winner = this.packed.get(sceneId);
    if (winner) {
      candidate.dispose();
      return winner;
    }
    this.packed.set(sceneId, candidate);
    return candidate;
  }

  dispose(): void {
    if (this.stopped) return;
    this.stopped = true;
    for (const packed of this.packed.values()) packed.dispose();
    this.packed.clear();
    this.documents.clearUnused();
    this.resourceLoader.clearUnused();
  }
}

function abortError(): Error {
  const error = new Error('Scene preparation was aborted');
  error.name = 'AbortError';
  return error;
}
