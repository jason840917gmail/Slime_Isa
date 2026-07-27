import Phaser from 'phaser';

import { resolveBodyBottom } from '../../presentation/WorldDepth';
import type {
  OcclusionActorDiagnostics,
  OcclusionController,
} from './OcclusionController';

export interface DepthDiagnosticsContext {
  readonly scene: Phaser.Scene;
  readonly getPlayer: () => Phaser.Physics.Arcade.Sprite;
  readonly getOcclusionController: () => OcclusionController | undefined;
}

/** Development-only DOM diagnostics for deterministic depth/occlusion smoke checks. */
export class DepthDiagnostics {
  private readonly element?: HTMLPreElement;

  constructor(private readonly ctx: DepthDiagnosticsContext) {
    if (!import.meta.env.DEV || typeof document === 'undefined') return;
    const element = document.createElement('pre');
    element.dataset.depthDiagnostics = 'true';
    element.style.position = 'fixed';
    element.style.left = '8px';
    element.style.bottom = '8px';
    element.style.zIndex = '10000';
    element.style.margin = '0';
    element.style.padding = '8px';
    element.style.maxWidth = 'min(720px, calc(100vw - 16px))';
    element.style.maxHeight = '35vh';
    element.style.overflow = 'auto';
    element.style.pointerEvents = 'none';
    element.style.background = 'rgba(8, 18, 18, 0.84)';
    element.style.color = '#d9ffe8';
    element.style.font = '11px/1.35 ui-monospace, SFMono-Regular, Consolas, monospace';
    document.body.appendChild(element);
    this.element = element;
    ctx.scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.destroy);
  }

  update(): void {
    if (!this.element) return;
    const player = this.ctx.getPlayer();
    const body = player.body as Phaser.Physics.Arcade.Body | null;
    const anchorY = body ? resolveBodyBottom(body) : player.y;
    const controller = this.ctx.getOcclusionController();
    const diagnostics = controller?.diagnostics;
    const actors = controller?.actorDiagnostics ?? [];
    const actorText = actors
      .map((actor) => this.formatActor(actor))
      .join('\n');
    this.element.textContent = [
      'depth/occlusion diagnostics',
      `player anchorY=${anchorY.toFixed(2)} depth=${Math.round(player.depth)}`,
      `occluders=${diagnostics?.registeredOccluders ?? 0} ids=${controller?.occluderIds.join(',') ?? ''}`,
      `actors=${diagnostics?.registeredActors ?? 0} cells=${diagnostics?.queriedCells ?? 0} candidates=${diagnostics?.candidates ?? 0} intersections=${diagnostics?.intersections ?? 0}`,
      `updateMs=${(diagnostics?.lastUpdateMs ?? 0).toFixed(3)} avgMs=${(diagnostics?.averageUpdateMs ?? 0).toFixed(3)}`,
      actorText,
    ].filter(Boolean).join('\n');
  }

  destroy = (): void => {
    if (this.element?.parentElement) this.element.parentElement.removeChild(this.element);
    this.ctx.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.destroy);
  };

  private formatActor(actor: OcclusionActorDiagnostics): string {
    return `${actor.id} anchorY=${actor.groundAnchorY.toFixed(2)} depth=${Math.round(actor.depth)} silhouette=${actor.silhouetteVisible} hidden=${Math.round(actor.hiddenRatio * 100)}%`;
  }
}
