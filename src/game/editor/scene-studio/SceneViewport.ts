import type { SceneNodeDocument } from '../../content/scenes/types';
import { adjustPreviewZoom, clampPreviewZoom } from '../PreviewZoom';

export interface ViewportNode {
  readonly id: string;
  readonly name: string;
  readonly type: string;
  readonly position: readonly [number, number];
  readonly selected: boolean;
}

export class SceneViewportState {
  private zoomValue = 1;
  private selectedId?: string;

  get zoom(): number { return this.zoomValue; }
  get selection(): string | undefined { return this.selectedId; }
  setZoom(value: number): void { this.zoomValue = clampPreviewZoom(value); }
  wheel(deltaY: number): void { this.zoomValue = adjustPreviewZoom(this.zoomValue, deltaY); }
  select(nodeId?: string): void { this.selectedId = nodeId; }
  nodes(nodes: readonly SceneNodeDocument[]): readonly ViewportNode[] {
    return nodes.filter((node) => ['Node2D', 'Sprite2D', 'CharacterBody2D', 'StaticBody2D', 'Area2D', 'CollisionShape2D', 'Camera2D', 'AudioStreamPlayer2D'].includes(node.type)).map((node) => ({
      id: node.id, name: node.name, type: node.type,
      position: Array.isArray(node.properties.position) && node.properties.position.length === 2 ? [Number(node.properties.position[0]), Number(node.properties.position[1])] : [0, 0],
      selected: node.id === this.selectedId,
    }));
  }
}
