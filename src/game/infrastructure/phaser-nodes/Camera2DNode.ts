import type Phaser from 'phaser';

import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D, type Node2DOptions } from '../../runtime/scene/Node2D';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';
import type { PresentationParticipant } from './PresentationSync';

export interface Camera2DNodeOptions extends Node2DOptions {
  readonly context: PhaserNodeContext;
  readonly zoom?: number;
  readonly roundPixels?: boolean;
}

export class Camera2DNode extends Node2D implements PresentationParticipant {
  private camera?: Phaser.Cameras.Scene2D.Camera;

  constructor(private readonly cameraOptions: Camera2DNodeOptions) {
    super(cameraOptions);
    if (!Number.isFinite(cameraOptions.zoom ?? 1) || (cameraOptions.zoom ?? 1) <= 0) throw new Error('Camera zoom must be positive and finite');
  }

  get phaserCameraActive(): boolean { return this.camera !== undefined; }

  override _enter_tree(): void {
    const scene = this.cameraOptions.context.scene;
    const camera = scene.cameras.add(0, 0, scene.scale.width, scene.scale.height);
    this.camera = camera;
    camera.setZoom(this.cameraOptions.zoom ?? 1);
    camera.setRoundPixels(this.cameraOptions.roundPixels ?? true);
    const unregister = this.cameraOptions.context.registerPresentation(this);
    this.entryDisposables.add(() => unregister());
    this.entryDisposables.add(() => { scene.cameras.remove(camera); if (this.camera === camera) this.camera = undefined; });
    this.syncPresentation(1);
  }

  syncPresentation(_alpha: number): void {
    const camera = this.camera;
    if (!camera) return;
    const transform = this.get_global_transform();
    camera.setViewport(0, 0, this.cameraOptions.context.scene.scale.width, this.cameraOptions.context.scene.scale.height);
    camera.centerOn(transform.position.x, transform.position.y);
    camera.setRotation(transform.rotation);
    camera.setVisible(this.visible);
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): Camera2DNode {
    return new Camera2DNode({ ...this.cameraOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible });
  }
}
