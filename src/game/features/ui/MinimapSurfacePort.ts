import type Phaser from 'phaser';
import type { JsonValue } from '../../content/scenes/types';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

export interface MinimapSurfaceOptions {
  readonly uiRoot: HTMLElement;
  readonly dimensions: WorldDimensions;
}

/** Canvas renderer mounted inside the authored minimap Control host. */
export class MinimapSurfacePort implements UiSurfacePort {
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly resizeObserver: ResizeObserver;
  private canvas?: HTMLCanvasElement;
  private host?: HTMLElement;
  private stopped = false;

  constructor(private readonly options: MinimapSurfaceOptions) {
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(options.uiRoot);
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'minimap' || this.stopped) return {};
    const shortSide = Math.min(this.options.uiRoot.clientWidth, this.options.uiRoot.clientHeight);
    const size = Math.min(180, Math.max(128, shortSide * 0.24));
    const margin = Math.min(16, Math.max(12, shortSide * 0.025));
    return {
      offsetMin: [Math.round(margin), -Math.round(margin + size)],
      offsetMax: [Math.round(margin + size), -Math.round(margin)],
      summary: 'Local map',
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== 'minimap' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(_surfaceId: string, _actionId: string, _payload?: JsonValue): void {}

  update(camera: Phaser.Cameras.Scene2D.Camera, player: Phaser.Physics.Arcade.Sprite | undefined): void {
    if (this.stopped) return;
    const canvas = this.ensureCanvas();
    if (!canvas) return;
    const size = Math.min(canvas.parentElement?.clientWidth ?? 0, canvas.parentElement?.clientHeight ?? 0);
    if (size <= 0) return;
    const ratio = Math.max(1, window.devicePixelRatio || 1);
    const pixels = Math.round(size * ratio);
    if (canvas.width !== pixels || canvas.height !== pixels) {
      canvas.width = pixels;
      canvas.height = pixels;
    }
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.clearRect(0, 0, size, size);
    ctx.fillStyle = 'rgba(24, 43, 70, 0.16)';
    ctx.fillRect(0, 0, size, size);
    ctx.strokeStyle = 'rgba(185, 239, 202, 0.42)';
    ctx.lineWidth = 1;
    ctx.strokeRect(0.5, 0.5, size - 1, size - 1);
    const mapX = (x: number): number => x / this.options.dimensions.width * size;
    const mapY = (y: number): number => y / this.options.dimensions.height * size;
    if (player) {
      const x = mapX(player.x);
      const y = mapY(player.y);
      ctx.beginPath();
      ctx.arc(x, y, 5.25, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(8, 16, 34, 0.88)';
      ctx.fill();
      ctx.beginPath();
      ctx.arc(x, y, 4, 0, Math.PI * 2);
      ctx.fillStyle = '#72d8ff';
      ctx.fill();
      canvas.setAttribute('aria-label', `Local map. Player at ${Math.round(player.x)}, ${Math.round(player.y)}.`);
    }
    const viewW = camera.width / camera.zoom;
    const viewH = camera.height / camera.zoom;
    const left = mapX(camera.scrollX);
    const top = mapY(camera.scrollY);
    ctx.strokeStyle = 'rgba(136, 200, 153, 0.95)';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(left, top,
      Math.max(2, mapX(camera.scrollX + viewW) - left),
      Math.max(2, mapY(camera.scrollY + viewH) - top));
  }

  destroy(): void {
    if (this.stopped) return;
    this.stopped = true;
    this.resizeObserver.disconnect();
    this.canvas?.remove();
    this.canvas = undefined;
    this.host = undefined;
    this.listeners.clear();
  }

  private ensureCanvas(): HTMLCanvasElement | undefined {
    const host = this.options.uiRoot.querySelector<HTMLElement>('[data-scene-control-id="ui-minimap/map-canvas"]');
    if (!host) return undefined;
    if (host === this.host && this.canvas?.isConnected) return this.canvas;
    this.canvas?.remove();
    const canvas = document.createElement('canvas');
    canvas.className = 'scene-minimap-canvas';
    canvas.setAttribute('role', 'img');
    canvas.setAttribute('aria-label', 'Local map');
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    canvas.style.display = 'block';
    host.append(canvas);
    this.canvas = canvas;
    this.host = host;
    return canvas;
  }

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot('minimap');
    for (const listener of this.listeners) listener(model);
  };
}
