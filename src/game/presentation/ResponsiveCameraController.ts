import Phaser from 'phaser';

import {
  cameraCenterFromScroll,
  exponentialDampingFactor,
  resolveDeadzoneCenter,
  responsiveDeadzoneSize,
} from './CameraMotion';
import {
  cameraRenderingMode,
  DEFAULT_CAMERA_ZOOM,
  isIntegerCameraZoom,
  nextCameraZoom,
  type CameraRenderingMode,
} from './CameraZoom';
import {
  resolvePhysicsPresentationPosition,
  type PhysicsPresentationTarget,
} from './PhysicsPresentation';

export { DEFAULT_CAMERA_ZOOM } from './CameraZoom';

const ZOOM_EPSILON = 0.000_001;

export interface CameraPresentationState {
  readonly mode: CameraRenderingMode;
  readonly deadzoneWidth: number;
  readonly deadzoneHeight: number;
  readonly targetX?: number;
  readonly targetY?: number;
}

/** Owns integer gameplay zoom, fractional overview zoom, and deadzone following. */
export class ResponsiveCameraController {
  private followTarget?: PhysicsPresentationTarget;
  private following = false;
  private targetZoom = DEFAULT_CAMERA_ZOOM;
  private readonly presentationTarget = new Phaser.Math.Vector2();
  private state: CameraPresentationState = {
    mode: 'gameplay',
    deadzoneWidth: 128,
    deadzoneHeight: 96,
  };

  constructor(
    private readonly scene: Phaser.Scene,
    private readonly camera: Phaser.Cameras.Scene2D.Camera,
  ) {}

  get zoom(): number {
    return this.targetZoom;
  }

  get presentationState(): CameraPresentationState {
    return this.state;
  }

  setZoom(zoom: number): void {
    if (!Number.isFinite(zoom) || zoom <= 0) return;

    this.camera.zoomEffect.reset();
    this.targetZoom = zoom;
    this.camera.setZoom(zoom);
    this.camera.setRoundPixels(isIntegerCameraZoom(zoom));
    this.refreshState();
  }

  resetZoom(): void {
    this.setZoom(DEFAULT_CAMERA_ZOOM);
  }

  stepZoom(deltaY: number): boolean {
    if (deltaY === 0) return false;
    const nextZoom = nextCameraZoom(this.targetZoom, deltaY);
    if (Math.abs(nextZoom - this.targetZoom) < ZOOM_EPSILON) return false;
    this.setZoom(nextZoom);
    // A deadzone intentionally lets the player sit away from the camera center.
    // Re-anchor wheel zoom on the followed actor so changing scale never zooms
    // toward that stale camera center.
    if (this.following) this.centerOnTarget();
    return true;
  }

  startFollow(target: PhysicsPresentationTarget, centerImmediately = false): void {
    this.camera.stopFollow();
    this.followTarget = target;
    this.following = true;
    if (centerImmediately) this.centerOnTarget();
  }

  stopFollow(): void {
    this.following = false;
  }

  update(deltaMs: number): void {
    if (!this.following || !this.followTarget || this.camera.panEffect.isRunning) return;

    const target = resolvePhysicsPresentationPosition(
      this.scene,
      this.followTarget,
      this.presentationTarget,
    );
    const zoom = this.camera.zoom;
    const deadzone = responsiveDeadzoneSize(this.camera.width, this.camera.height);
    const currentCenter = cameraCenterFromScroll(
      this.camera.scrollX,
      this.camera.scrollY,
      this.camera.width,
      this.camera.height,
    );
    const desiredCenter = resolveDeadzoneCenter(
      currentCenter,
      target,
      deadzone.width / (2 * zoom),
      deadzone.height / (2 * zoom),
    );
    const damping = exponentialDampingFactor(deltaMs);
    const centerX = Phaser.Math.Linear(currentCenter.x, desiredCenter.x, damping);
    const centerY = Phaser.Math.Linear(currentCenter.y, desiredCenter.y, damping);

    this.camera.centerOn(centerX, centerY);
    this.state = {
      mode: cameraRenderingMode(zoom),
      deadzoneWidth: deadzone.width,
      deadzoneHeight: deadzone.height,
      targetX: target.x,
      targetY: target.y,
    };
  }

  private centerOnTarget(): void {
    if (!this.followTarget) return;
    const target = resolvePhysicsPresentationPosition(
      this.scene,
      this.followTarget,
      this.presentationTarget,
    );
    this.camera.centerOn(target.x, target.y);
    this.refreshState(target);
  }

  private refreshState(target?: Phaser.Math.Vector2): void {
    const deadzone = responsiveDeadzoneSize(this.camera.width, this.camera.height);
    this.state = {
      mode: cameraRenderingMode(this.targetZoom),
      deadzoneWidth: deadzone.width,
      deadzoneHeight: deadzone.height,
      targetX: target?.x ?? this.state.targetX,
      targetY: target?.y ?? this.state.targetY,
    };
  }
}
