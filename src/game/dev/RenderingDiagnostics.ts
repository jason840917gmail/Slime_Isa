import Phaser from 'phaser';
import type { CameraPresentationState } from '../presentation/ResponsiveCameraController';
import { physicsPresentationAlpha } from '../presentation/PhysicsPresentation';

const UPDATE_INTERVAL_MS = 200;

export class RenderingDiagnostics {
  private readonly element?: HTMLPreElement;
  private nextUpdateAt = 0;

  constructor(
    private readonly scene: Phaser.Scene,
    private readonly getWorldCamera: () => Phaser.Cameras.Scene2D.Camera,
    private readonly getPlayerVisualSize: () => { width: number; height: number } | undefined,
    private readonly getCameraPresentationState: () => CameraPresentationState | undefined,
  ) {
    if (!import.meta.env.DEV) return;
    if (new URLSearchParams(window.location.search).get('renderDebug') !== '1') return;

    const element = document.createElement('pre');
    element.dataset.renderingDiagnostics = 'true';
    element.style.cssText = [
      'position:fixed',
      'left:10px',
      'top:10px',
      'z-index:1000',
      'margin:0',
      'padding:9px 11px',
      'border:1px solid #72d8ff',
      'background:rgba(8,16,34,.9)',
      'color:#d7e7f8',
      'font:11px/1.45 Consolas,monospace',
      'pointer-events:none',
      'white-space:pre',
    ].join(';');
    document.body.append(element);
    this.element = element;
  }

  update(time: number): void {
    if (!this.element || time < this.nextUpdateAt) return;
    this.nextUpdateAt = time + UPDATE_INTERVAL_MS;

    const canvas = this.scene.game.canvas;
    const bounds = canvas.getBoundingClientRect();
    const camera = this.getWorldCamera();
    const visualSize = this.getPlayerVisualSize();
    const presentation = this.getCameraPresentationState();
    const renderRoundPixels = (camera as Phaser.Cameras.Scene2D.Camera & {
      renderRoundPixels?: boolean;
    }).renderRoundPixels;
    const cssScaleX = bounds.width > 0 ? bounds.width / canvas.width : 0;
    const cssScaleY = bounds.height > 0 ? bounds.height / canvas.height : 0;

    this.element.textContent = [
      'RENDER GRID',
      `camera zoom     ${camera.zoom.toFixed(3)}`,
      `camera mode     ${presentation?.mode ?? 'n/a'}`,
      `camera deadzone ${presentation ? `${presentation.deadzoneWidth.toFixed(0)} x ${presentation.deadzoneHeight.toFixed(0)}` : 'n/a'}`,
      `camera scroll   ${camera.scrollX.toFixed(3)}, ${camera.scrollY.toFixed(3)}`,
      `physics alpha   ${physicsPresentationAlpha(this.scene).toFixed(3)}`,
      `actual fps      ${this.scene.game.loop.actualFps.toFixed(1)}`,
      `round pixels    ${camera.roundPixels} / render ${String(renderRoundPixels)}`,
      `canvas backing  ${canvas.width} x ${canvas.height}`,
      `canvas css      ${bounds.width.toFixed(0)} x ${bounds.height.toFixed(0)}`,
      `css ratio       ${cssScaleX.toFixed(4)}, ${cssScaleY.toFixed(4)}`,
      `device ratio    ${window.devicePixelRatio.toFixed(2)}`,
      `player visual   ${visualSize ? `${visualSize.width.toFixed(2)} x ${visualSize.height.toFixed(2)}` : 'n/a'}`,
      `renderer        ${this.scene.game.renderer.type === Phaser.WEBGL ? 'webgl' : 'canvas'}`,
    ].join('\n');
  }

  destroy(): void {
    this.element?.remove();
  }
}
