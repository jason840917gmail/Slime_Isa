import type Phaser from 'phaser';

import { DEPTH_BANDS } from '../../presentation/WorldDepth';

export interface InteractionCandidate {
  readonly id: string;
  readonly prompt: string;
  readonly priority: number;
  /** World point where the key badge's bottom centre sits, above the target. */
  readonly anchor?: () => { readonly x: number; readonly y: number };
  /** Optional second action on the same target (G), e.g. picking placed furniture back up. */
  readonly secondary?: {
    readonly prompt: string;
    execute(): boolean;
  };
  execute(): boolean;
}

const BADGE_SIZE = 22;
const BADGE_BOB_PX = 2.5;
const BADGE_BOB_PERIOD_MS = 1400;

export interface InteractionProvider {
  getCandidate(): InteractionCandidate | undefined;
}

/**
 * Chooses exactly one intentional F interaction and owns the shared prompt plus
 * the world-space key badge shown above the chosen target.
 */
export class InteractionRouter {
  private readonly providers = new Map<string, InteractionProvider>();
  private readonly prompt: Phaser.GameObjects.Text;
  private readonly badge: Phaser.GameObjects.Container;
  private badgeTween?: Phaser.Tweens.Tween;
  private suppressed = false;
  private candidate?: InteractionCandidate;
  private destroyed = false;

  constructor(private readonly scene: Phaser.Scene) {
    this.prompt = scene.add.text(scene.cameras.main.width / 2, scene.cameras.main.height - 42, '', {
      fontFamily: 'Trebuchet MS, Segoe UI Variable, sans-serif',
      fontSize: '14px',
      color: '#e7fff5',
      backgroundColor: '#101a31cc',
      padding: { left: 12, right: 12, top: 7, bottom: 7 },
    }).setOrigin(0.5).setScrollFactor(0).setDepth(250).setVisible(false);
    this.badge = this.createBadge();
    scene.scale.on('resize', this.handleResize, this);
    scene.events.once('shutdown', () => this.destroy());
  }

  register(id: string, provider: InteractionProvider): () => void {
    this.providers.set(id, provider);
    return () => {
      if (this.providers.get(id) === provider) this.providers.delete(id);
      if (this.candidate?.id.startsWith(`${id}:`)) this.clearCandidate();
    };
  }

  /** While suppressed (e.g. the player is asleep) nothing is offered or shown. */
  setSuppressed(suppressed: boolean): void {
    this.suppressed = suppressed;
    if (suppressed) this.clearCandidate();
  }

  update(): void {
    if (this.suppressed) return;
    let best: InteractionCandidate | undefined;
    for (const provider of this.providers.values()) {
      const candidate = provider.getCandidate();
      if (!candidate || (best && (candidate.priority < best.priority
        || (candidate.priority === best.priority && candidate.id > best.id)))) continue;
      best = candidate;
    }
    const previousId = this.candidate?.id;
    this.candidate = best;
    this.prompt.setText(best ? (best.secondary ? `${best.prompt}     ${best.secondary.prompt}` : best.prompt) : '').setVisible(!!best);
    this.updateBadge(best, best?.id !== previousId);
  }

  handleInteract(): boolean {
    const candidate = this.candidate;
    return candidate ? candidate.execute() : false;
  }

  handleSecondary(): boolean {
    const secondary = this.candidate?.secondary;
    return secondary ? secondary.execute() : false;
  }

  hasCandidate(): boolean {
    return this.candidate !== undefined;
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.scene.scale.off('resize', this.handleResize, this);
    this.providers.clear();
    this.candidate = undefined;
    this.badgeTween?.remove();
    this.prompt.destroy();
    this.badge.destroy();
  }

  private clearCandidate(): void {
    this.candidate = undefined;
    if (!this.destroyed && this.prompt.active) this.prompt.setVisible(false);
    if (!this.destroyed && this.badge.active) this.badge.setVisible(false);
  }

  private createBadge(): Phaser.GameObjects.Container {
    const half = BADGE_SIZE / 2;
    const frame = this.scene.add.graphics();
    frame.fillStyle(0x000000, 0.35).fillRoundedRect(-half + 1, -BADGE_SIZE + 2, BADGE_SIZE, BADGE_SIZE, 5);
    frame.fillStyle(0x101a31, 0.92).fillRoundedRect(-half, -BADGE_SIZE, BADGE_SIZE, BADGE_SIZE, 5);
    frame.lineStyle(2, 0x9dffc8, 1).strokeRoundedRect(-half, -BADGE_SIZE, BADGE_SIZE, BADGE_SIZE, 5);
    const label = this.scene.add.text(0, -half, 'F', {
      fontFamily: 'Trebuchet MS, Segoe UI Variable, sans-serif',
      fontSize: '14px',
      fontStyle: 'bold',
      color: '#e7fff5',
    }).setOrigin(0.5);
    return this.scene.add.container(0, 0, [frame, label])
      .setDepth(DEPTH_BANDS['overhead-artwork'])
      .setVisible(false);
  }

  private updateBadge(candidate: InteractionCandidate | undefined, changed: boolean): void {
    const anchor = candidate?.anchor?.();
    if (!anchor) {
      this.badge.setVisible(false);
      return;
    }
    const bob = Math.sin((this.scene.time.now / BADGE_BOB_PERIOD_MS) * Math.PI * 2) * BADGE_BOB_PX;
    this.badge.setPosition(Math.round(anchor.x), Math.round(anchor.y + bob)).setVisible(true);
    if (changed) {
      this.badgeTween?.remove();
      this.badge.setScale(0.5).setAlpha(0);
      this.badgeTween = this.scene.tweens.add({ targets: this.badge, scale: 1, alpha: 1, duration: 140, ease: 'Back.Out' });
    }
  }

  private readonly handleResize = (gameSize: Phaser.Structs.Size): void => {
    this.prompt.setPosition(gameSize.width / 2, gameSize.height - 42);
  };
}
