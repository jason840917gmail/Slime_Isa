import type Phaser from 'phaser';

import { DEPTH_BANDS } from '../../presentation/WorldDepth';
import { controlCodes } from '../player/PlayerInputActions';
import { controlLabel, controlVerb } from '../player/ControlLabels';

export interface InteractionCandidate {
  readonly id: string;
  /** What interacting does, without a key ("Open chest"); the router adds the control. */
  readonly prompt: string;
  readonly priority: number;
  /** World point where the key badge's bottom centre sits, above the target. */
  readonly anchor?: () => { readonly x: number; readonly y: number };
  /** Where the target stands in the world, for pointing at it (falls back to `anchor`). */
  readonly origin?: () => { readonly x: number; readonly y: number };
  /**
   * Optional second action on the same target, done by holding interact
   * (e.g. picking placed furniture back up). A short press still does `execute`.
   */
  readonly secondary?: {
    readonly prompt: string;
    execute(): boolean;
  };
  execute(): boolean;
}

/** The shared prompt line: "Right-click: Sleep     Hold: Pick up". */
export function interactionPromptText(candidate: Pick<InteractionCandidate, 'prompt' | 'secondary'>): string {
  const main = `${controlVerb('interact')}: ${candidate.prompt}`;
  return candidate.secondary ? `${main}     Hold: ${candidate.secondary.prompt}` : main;
}

const BADGE_SIZE = 22;
const BADGE_BOB_PX = 2.5;
const BADGE_BOB_PERIOD_MS = 1400;

export interface InteractionProvider {
  getCandidate(): InteractionCandidate | undefined;
  /** Every target in reach, so the pointer can choose one that is not the nearest. */
  getCandidates?(): readonly InteractionCandidate[];
}

/** The pointer picks a target in reach whose position is within this many world pixels. */
export const POINTER_PICK_PX = 64;

/**
 * Chooses exactly one intentional interaction and owns the shared prompt plus
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

  /**
   * Chooses the target for the next interact press: the one in reach that the
   * pointer (`pointer`, world coordinates) is on, else the highest-priority one.
   */
  update(pointer?: Readonly<{ x: number; y: number }>): void {
    if (this.suppressed) return;
    const candidates = [...this.providers.values()].flatMap((provider) => (
      provider.getCandidates ? [...provider.getCandidates()] : [provider.getCandidate()].filter((candidate): candidate is InteractionCandidate => !!candidate)
    ));
    let best = pointer ? pointedCandidate(candidates, pointer) : undefined;
    if (!best) {
      for (const candidate of candidates) {
        if (best && (candidate.priority < best.priority
          || (candidate.priority === best.priority && candidate.id > best.id))) continue;
        best = candidate;
      }
    }
    const previousId = this.candidate?.id;
    this.candidate = best;
    this.prompt.setText(best ? interactionPromptText(best) : '').setVisible(!!best);
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

  /** The chosen target also has a second action (picking placed furniture back up). */
  hasSecondary(): boolean {
    return this.candidate?.secondary !== undefined;
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
    const code = controlCodes('interact')[0];
    const mouseButton = code.startsWith('Mouse') ? Number(code.slice(5)) : undefined;
    const glyph = mouseButton === undefined
      ? this.scene.add.text(0, -half, controlLabel('interact'), {
        fontFamily: 'Trebuchet MS, Segoe UI Variable, sans-serif',
        fontSize: '14px',
        fontStyle: 'bold',
        color: '#e7fff5',
      }).setOrigin(0.5)
      : this.drawMouseGlyph(-half, mouseButton);
    return this.scene.add.container(0, 0, [frame, glyph])
      .setDepth(DEPTH_BANDS['overhead-artwork'])
      .setVisible(false);
  }

  /** A small mouse with the bound button lit (stand-in until the control glyph art exists). */
  private drawMouseGlyph(centerY: number, button: number): Phaser.GameObjects.Graphics {
    const width = 11;
    const height = 15;
    const left = -width / 2;
    const top = centerY - height / 2;
    const mouse = this.scene.add.graphics();
    if (button === 0 || button === 2) {
      mouse.fillStyle(0x9dffc8, 1);
      const buttonLeft = button === 0 ? left : 0;
      mouse.fillRoundedRect(buttonLeft, top, width / 2, height * 0.45, { tl: button === 0 ? 4 : 0, tr: button === 2 ? 4 : 0, bl: 0, br: 0 });
    }
    mouse.lineStyle(1.5, 0xe7fff5, 1).strokeRoundedRect(left, top, width, height, 4);
    mouse.lineBetween(0, top, 0, top + height * 0.45);
    mouse.lineBetween(left, top + height * 0.45, left + width, top + height * 0.45);
    return mouse;
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

/** The candidate whose position is nearest the pointer, if one is within `POINTER_PICK_PX`. */
function pointedCandidate(
  candidates: readonly InteractionCandidate[],
  pointer: Readonly<{ x: number; y: number }>,
): InteractionCandidate | undefined {
  let pointed: InteractionCandidate | undefined;
  let pointedDistance: number = POINTER_PICK_PX;
  for (const candidate of candidates) {
    const at = candidate.origin?.() ?? candidate.anchor?.();
    if (!at) continue;
    const distance = Math.hypot(at.x - pointer.x, at.y - pointer.y);
    if (distance <= pointedDistance) {
      pointed = candidate;
      pointedDistance = distance;
    }
  }
  return pointed;
}
