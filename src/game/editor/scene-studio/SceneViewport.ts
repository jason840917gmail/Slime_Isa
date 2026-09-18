import type { SceneNodeDocument } from '../../content/scenes/types';
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
const UI_NODE_TYPES = new Set(['Control', 'Container', 'TextureRect', 'Label', 'ProgressBar', 'Button', 'ItemList', 'GridContainer', 'ScrollContainer', 'ModalRoot']);
const UI_PREVIEW_SIZE = { width: 1280, height: 720 } as const;

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
