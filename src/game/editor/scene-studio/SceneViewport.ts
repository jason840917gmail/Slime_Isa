import type { AuthoredNodeId, InstanceId, SceneId } from '../../content/scenes/identifiers';
import type { JsonValue, SceneDocument, SceneNodeDocument } from '../../content/scenes/types';
import { adjustPreviewZoom, clampPreviewZoom } from '../PreviewZoom';

export interface ViewportNode {
  readonly id: string;
  readonly name: string;
  readonly type: string;
  readonly kind: 'world' | 'ui';
  readonly position: readonly [number, number];
  readonly size?: readonly [number, number];
  readonly selected: boolean;
}

const WORLD_NODE_TYPES = new Set(['Node2D', 'Sprite2D', 'CharacterBody2D', 'StaticBody2D', 'Area2D', 'CollisionShape2D', 'Camera2D', 'AudioStreamPlayer2D']);
const UI_NODE_TYPES = new Set(['Control', 'Container', 'TextureRect', 'Label', 'ProgressBar', 'Slider', 'Button', 'ItemList', 'GridContainer', 'ScrollContainer', 'ModalRoot']);
export const UI_PREVIEW_SIZE = { width: 1280, height: 720 } as const;

export class SceneViewportState {
  private zoomValue = 1;
  private selectedId?: string;

  get zoom(): number { return this.zoomValue; }
  get selection(): string | undefined { return this.selectedId; }
  setZoom(value: number): void { this.zoomValue = clampPreviewZoom(value); }
  wheel(deltaY: number): void { this.zoomValue = adjustPreviewZoom(this.zoomValue, deltaY); }
  select(nodeId?: string): void { this.selectedId = nodeId; }
  nodes(nodes: readonly SceneNodeDocument[]): readonly ViewportNode[] {
    const byId = new Map(nodes.map((node) => [node.id, node]));
    const rectangles = new Map<string, Readonly<{ left: number; top: number; width: number; height: number }>>();
    const uiRectangle = (node: SceneNodeDocument, visiting = new Set<string>()): Readonly<{ left: number; top: number; width: number; height: number }> => {
      const cached = rectangles.get(node.id);
      if (cached) return cached;
      if (visiting.has(node.id)) return { left: 0, top: 0, width: UI_PREVIEW_SIZE.width, height: UI_PREVIEW_SIZE.height };
      visiting.add(node.id);
      const parent = node.parentId ? byId.get(node.parentId) : undefined;
      const parentRectangle = parent && UI_NODE_TYPES.has(parent.type)
        ? uiRectangle(parent, visiting)
        : { left: 0, top: 0, width: UI_PREVIEW_SIZE.width, height: UI_PREVIEW_SIZE.height };
      const anchorMin = vector(node.properties.anchorMin, [0, 0]);
      const anchorMax = vector(node.properties.anchorMax, [0, 0]);
      const offsetMin = vector(node.properties.offsetMin, [0, 0]);
      const offsetMax = vector(node.properties.offsetMax, [0, 0]);
      const left = parentRectangle.left + parentRectangle.width * anchorMin[0] + offsetMin[0];
      const top = parentRectangle.top + parentRectangle.height * anchorMin[1] + offsetMin[1];
      const right = parentRectangle.left + parentRectangle.width * anchorMax[0] + offsetMax[0];
      const bottom = parentRectangle.top + parentRectangle.height * anchorMax[1] + offsetMax[1];
      const rectangle = { left, top, width: Math.max(0, right - left), height: Math.max(0, bottom - top) };
      rectangles.set(node.id, rectangle);
      visiting.delete(node.id);
      return rectangle;
    };
    return nodes.flatMap((node): readonly ViewportNode[] => {
      if (WORLD_NODE_TYPES.has(node.type)) return [{
        id: node.id, name: node.name, type: node.type, kind: 'world',
        position: vector(node.properties.position, [0, 0]), selected: node.id === this.selectedId,
      }];
      if (!UI_NODE_TYPES.has(node.type)) return [];
      const rectangle = uiRectangle(node);
      return [{
        id: node.id, name: node.name, type: node.type, kind: 'ui', position: [rectangle.left, rectangle.top],
        size: [rectangle.width, rectangle.height], selected: node.id === this.selectedId,
      }];
    });
  }
}

function vector(value: unknown, fallback: readonly [number, number]): readonly [number, number] {
  return Array.isArray(value) && value.length === 2 && value.every((entry) => typeof entry === 'number' && Number.isFinite(entry))
    ? [value[0], value[1]]
    : fallback;
}

// ---------------------------------------------------------------------------
// Composed scene geometry (parent chains + packed-scene instances)
// ---------------------------------------------------------------------------

export const TRANSFORM_NODE_TYPES: ReadonlySet<string> = new Set([
  'Node2D', 'Sprite2D', 'PhysicsBody2D', 'CharacterBody2D', 'StaticBody2D', 'Area2D', 'CollisionShape2D',
  'TileMapLayer2D', 'Camera2D', 'AudioStreamPlayer2D',
]);

export interface ComposedTransform {
  readonly position: readonly [number, number];
  readonly rotation: number;
  readonly scale: readonly [number, number];
}

export interface ComposedSceneNode {
  /** Matches `SceneTreeRow.key` so tree, viewport and preview share one identity. */
  readonly key: string;
  readonly nodeId: AuthoredNodeId;
  readonly instancePath: readonly InstanceId[];
  readonly sourceSceneId: SceneId;
  readonly name: string;
  readonly type: string;
  readonly scriptId?: string;
  readonly readOnly: boolean;
  readonly parentKey?: string;
  /** Effective properties after every enclosing instance override. */
  readonly properties: Readonly<Record<string, JsonValue>>;
  /** Global transform (undefined for nodes outside the 2D transform chain). */
  readonly global?: ComposedTransform;
  /** Transform of the nearest 2D ancestor, used to convert global edits back to local values. */
  readonly parentGlobal?: ComposedTransform;
}

export type ComposedSceneResolver = (sceneId: SceneId) => SceneDocument | undefined;


export function composeTransform(parent: ComposedTransform | undefined, properties: Readonly<Record<string, JsonValue>>): ComposedTransform {
  const local = {
    position: vector(properties.position, [0, 0]),
    rotation: typeof properties.rotation === 'number' && Number.isFinite(properties.rotation) ? properties.rotation : 0,
    scale: vector(properties.scale, [1, 1]),
  };
  if (!parent) return local;
  // Mirrors Node2D.readWorldTransform so overlays land exactly on runtime output.
  const scaledX = local.position[0] * parent.scale[0];
  const scaledY = local.position[1] * parent.scale[1];
  const cosine = Math.cos(parent.rotation);
  const sine = Math.sin(parent.rotation);
  return {
    position: [parent.position[0] + scaledX * cosine - scaledY * sine, parent.position[1] + scaledX * sine + scaledY * cosine],
    rotation: parent.rotation + local.rotation,
    scale: [parent.scale[0] * local.scale[0], parent.scale[1] * local.scale[1]],
  };
}

/** Converts a desired global position back into the node's authored local position. */
export function localPositionFor(parent: ComposedTransform | undefined, global: readonly [number, number]): readonly [number, number] {
  if (!parent) return [global[0], global[1]];
  const dx = global[0] - parent.position[0];
  const dy = global[1] - parent.position[1];
  const cosine = Math.cos(-parent.rotation);
  const sine = Math.sin(-parent.rotation);
  return [(dx * cosine - dy * sine) / parent.scale[0], (dx * sine + dy * cosine) / parent.scale[1]];
}

/**
 * Walks the authored tree the same way the packed-scene resolver does:
 * children are composed through their 2D ancestors and instances expand into
 * their source scenes with enclosing overrides applied (outermost wins).
 */
export function composeSceneNodes(
  document: SceneDocument,
  resolve: ComposedSceneResolver = () => undefined,
  isTransformType: (type: string) => boolean = (type) => TRANSFORM_NODE_TYPES.has(type),
): readonly ComposedSceneNode[] {
  const output: ComposedSceneNode[] = [];
  const visit = (
    owner: SceneDocument,
    nodeId: AuthoredNodeId,
    instancePath: readonly InstanceId[],
    readOnly: boolean,
    parentKey: string | undefined,
    parentGlobal: ComposedTransform | undefined,
    overrides: ReadonlyMap<string, Readonly<Record<string, JsonValue>>>,
    sceneStack: readonly SceneId[],
  ): void => {
    const node = owner.nodes.find((candidate) => candidate.id === nodeId);
    if (!node) return;
    const key = `${instancePath.join('/')}:${node.id}`;
    const properties = { ...node.properties, ...(overrides.get(key) ?? {}) };
    const is2D = isTransformType(node.type);
    const global = is2D ? composeTransform(parentGlobal, properties) : undefined;
    output.push({
      key, nodeId: node.id, instancePath, sourceSceneId: owner.sceneId, name: node.name, type: node.type,
      ...(node.scriptId ? { scriptId: node.scriptId } : {}),
      readOnly, ...(parentKey ? { parentKey } : {}), properties,
      ...(global ? { global } : {}), ...(parentGlobal ? { parentGlobal } : {}),
    });
    const childParentGlobal = global ?? parentGlobal;
    const children = [
      ...owner.nodes.filter((candidate) => candidate.parentId === node.id).map((child) => ({ order: child.order, node: child })),
      ...owner.instances.filter((instance) => instance.parentNodeId === node.id).map((instance) => ({ order: instance.order, instance })),
    ].sort((left, right) => left.order - right.order);
    for (const child of children) {
      if ('node' in child) {
        visit(owner, child.node.id, instancePath, readOnly, key, childParentGlobal, overrides, sceneStack);
        continue;
      }
      const instance = child.instance;
      const source = resolve(instance.sceneId);
      if (!source || sceneStack.includes(source.sceneId)) continue;
      const nestedPath = [...instancePath, instance.instanceId];
      const nested = new Map(overrides);
      for (const override of instance.overrides) {
        const targetKey = `${[...nestedPath, ...override.sourceInstancePath].join('/')}:${override.sourceNodeId}`;
        const current = nested.get(targetKey) ?? {};
        // Outer overrides were inserted first and must keep precedence.
        if (Object.hasOwn(current, override.property)) continue;
        nested.set(targetKey, { ...current, [override.property]: override.value });
      }
      visit(source, source.rootNodeId, nestedPath, true, key, childParentGlobal, nested, [...sceneStack, source.sceneId]);
    }
  };
  visit(document, document.rootNodeId, [], false, undefined, undefined, new Map(), [document.sceneId]);
  return output;
}

// ---------------------------------------------------------------------------
// Camera: world <-> screen mapping shared by the canvas preview and overlays
// ---------------------------------------------------------------------------

export const VIEW_ZOOM_MIN = 0.05;
export const VIEW_ZOOM_MAX = 8;

export interface ViewportCamera {
  readonly centerX: number;
  readonly centerY: number;
  readonly zoom: number;
}

export interface ViewportSize { readonly width: number; readonly height: number }
export interface WorldRect { readonly x: number; readonly y: number; readonly width: number; readonly height: number }

export function clampViewZoom(value: number): number {
  return Number.isFinite(value) ? Math.max(VIEW_ZOOM_MIN, Math.min(VIEW_ZOOM_MAX, value)) : 1;
}

export function worldToScreen(camera: ViewportCamera, size: ViewportSize, point: readonly [number, number]): readonly [number, number] {
  return [(point[0] - camera.centerX) * camera.zoom + size.width / 2, (point[1] - camera.centerY) * camera.zoom + size.height / 2];
}

export function screenToWorld(camera: ViewportCamera, size: ViewportSize, point: readonly [number, number]): readonly [number, number] {
  return [(point[0] - size.width / 2) / camera.zoom + camera.centerX, (point[1] - size.height / 2) / camera.zoom + camera.centerY];
}

/** Zooms by `factor` while keeping the world point under `screenPoint` fixed. */
export function zoomCameraAt(camera: ViewportCamera, size: ViewportSize, screenPoint: readonly [number, number], factor: number): ViewportCamera {
  const anchor = screenToWorld(camera, size, screenPoint);
  const zoom = clampViewZoom(camera.zoom * factor);
  return {
    zoom,
    centerX: anchor[0] - (screenPoint[0] - size.width / 2) / zoom,
    centerY: anchor[1] - (screenPoint[1] - size.height / 2) / zoom,
  };
}

export function panCamera(camera: ViewportCamera, deltaScreenX: number, deltaScreenY: number): ViewportCamera {
  return { ...camera, centerX: camera.centerX - deltaScreenX / camera.zoom, centerY: camera.centerY - deltaScreenY / camera.zoom };
}

export function frameCamera(rect: WorldRect, size: ViewportSize, padding = 48): ViewportCamera {
  const width = Math.max(rect.width, 16);
  const height = Math.max(rect.height, 16);
  const zoom = clampViewZoom(Math.min((size.width - padding * 2) / width, (size.height - padding * 2) / height, 4));
  return { zoom, centerX: rect.x + rect.width / 2, centerY: rect.y + rect.height / 2 };
}

export function unionRects(rects: readonly WorldRect[]): WorldRect | undefined {
  const finite = rects.filter((rect) => [rect.x, rect.y, rect.width, rect.height].every(Number.isFinite));
  if (finite.length === 0) return undefined;
  const minX = Math.min(...finite.map((rect) => rect.x));
  const minY = Math.min(...finite.map((rect) => rect.y));
  const maxX = Math.max(...finite.map((rect) => rect.x + rect.width));
  const maxY = Math.max(...finite.map((rect) => rect.y + rect.height));
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

/** Bounds of every composed 2D node position, used when the canvas preview is unavailable. */
export function composedBounds(nodes: readonly ComposedSceneNode[]): WorldRect | undefined {
  return unionRects(nodes.flatMap((node) => node.global ? [{ x: node.global.position[0], y: node.global.position[1], width: 0, height: 0 }] : []));
}
