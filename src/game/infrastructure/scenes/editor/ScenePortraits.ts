import type { SceneStudioContentKind, SceneStudioPortrait } from './SceneStudioRepository';

/**
 * Picks a representative sprite frame for each explorer entry so the Scene
 * Studio list can show a thumbnail. A scene uses its first visible textured
 * node (Sprite2D / TextureRect); scenes without one borrow the portrait of
 * their first instanced child scene. Texture and sprite-sheet resources use
 * their own asset. Everything here is best effort: anything unresolvable
 * simply has no portrait.
 */
export interface PortraitSource {
  readonly kind: SceneStudioContentKind;
  readonly id: string;
  readonly document: unknown;
}

const TEXTURED_NODE_TYPES = new Set(['Sprite2D', 'TextureRect']);
const MAX_INSTANCE_DEPTH = 4;

type JsonRecord = Readonly<Record<string, unknown>>;

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function records(value: unknown): readonly JsonRecord[] {
  return Array.isArray(value) ? value.filter(isRecord) : [];
}

function fromResource(resource: JsonRecord, frame: unknown): SceneStudioPortrait | undefined {
  if (typeof resource.assetId !== 'string') return undefined;
  const index = typeof frame === 'number' && Number.isInteger(frame) && frame >= 0
    ? frame
    : typeof resource.frame === 'number' ? resource.frame : 0;
  if (resource.kind === 'texture') return { assetId: resource.assetId, frame: index };
  if (resource.kind === 'sprite-sheet' && typeof resource.frameWidth === 'number' && typeof resource.frameHeight === 'number') {
    return { assetId: resource.assetId, frame: index, frameWidth: resource.frameWidth, frameHeight: resource.frameHeight };
  }
  return undefined;
}

export function resolvePortraits(sources: readonly PortraitSource[]): ReadonlyMap<string, SceneStudioPortrait> {
  const resources = new Map<string, JsonRecord>();
  const scenes = new Map<string, JsonRecord>();
  for (const source of sources) {
    if (!isRecord(source.document)) continue;
    (source.kind === 'resource' ? resources : scenes).set(source.id, source.document);
  }

  const sceneCache = new Map<string, SceneStudioPortrait | undefined>();
  const scenePortrait = (sceneId: string, depth: number): SceneStudioPortrait | undefined => {
    if (sceneCache.has(sceneId)) return sceneCache.get(sceneId);
    const scene = scenes.get(sceneId);
    if (!scene || depth > MAX_INSTANCE_DEPTH) return undefined;
    sceneCache.set(sceneId, undefined); // guards instance cycles
    const local = new Map(records(scene.subresources).map((resource) => [resource.resourceId, resource]));
    let portrait: SceneStudioPortrait | undefined;
    for (const node of [...records(scene.nodes)].sort((left, right) => Number(left.order ?? 0) - Number(right.order ?? 0))) {
      if (typeof node.type !== 'string' || !TEXTURED_NODE_TYPES.has(node.type)) continue;
      const properties = isRecord(node.properties) ? node.properties : {};
      if (properties.visible === false) continue;
      const reference = isRecord(properties.texture) ? properties.texture.resourceId : undefined;
      if (typeof reference !== 'string') continue;
      const resource = local.get(reference) ?? resources.get(reference);
      portrait = resource ? fromResource(resource, properties.frame) : undefined;
      if (portrait) break;
    }
    if (!portrait) {
      for (const instance of records(scene.instances)) {
        if (typeof instance.sceneId !== 'string') continue;
        portrait = scenePortrait(instance.sceneId, depth + 1);
        if (portrait) break;
      }
    }
    sceneCache.set(sceneId, portrait);
    return portrait;
  };

  const output = new Map<string, SceneStudioPortrait>();
  for (const source of sources) {
    const portrait = source.kind === 'scene'
      ? scenePortrait(source.id, 0)
      : isRecord(source.document) ? fromResource(source.document, undefined) : undefined;
    if (portrait) output.set(`${source.kind}:${source.id}`, portrait);
  }
  return output;
}
