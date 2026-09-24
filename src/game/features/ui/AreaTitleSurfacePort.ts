import type Phaser from 'phaser';

import type { JsonValue } from '../../content/scenes/types';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

const ENTER_MS = 320;
const HOLD_MS = 1200;
const EXIT_MS = 320;

/** Transient area announcement projected through the authored Control scene. */
export class AreaTitleSurfacePort implements UiSurfacePort {
  private title = '';
  private color = '#ffd277';
  private startedAt = Number.NEGATIVE_INFINITY;
  private lastSignature = '';
  private lastModel: UiPresentationModel = {};
  private stopped = false;

  constructor(private readonly scene: Phaser.Scene) {}

  show(title: string, color: string): void {
    if (this.stopped) return;
    this.title = title;
    this.color = /^#[0-9a-f]{6}$/i.test(color) ? color : '#ffd277';
    this.startedAt = this.scene.time.now;
    this.lastSignature = '';
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'area-title-card' || this.stopped) return {};
    const elapsed = this.scene.time.now - this.startedAt;
    const duration = ENTER_MS + HOLD_MS + EXIT_MS;
    const visible = elapsed >= 0 && elapsed < duration;
    const progress = elapsed < ENTER_MS ? Math.max(0, elapsed / ENTER_MS)
      : elapsed < ENTER_MS + HOLD_MS ? 1
        : Math.max(0, 1 - (elapsed - ENTER_MS - HOLD_MS) / EXIT_MS);
    const eased = 1 - (1 - progress) ** 3;
    const top = Math.round(54 + eased * 18);
    const model = {
      title: this.title,
      color: this.color,
      visible,
      opacity: visible ? eased : 0,
      offsetMin: [-220, top],
      offsetMax: [220, top + 64],
    } satisfies Readonly<Record<string, JsonValue>>;
    const signature = JSON.stringify(model);
    if (signature === this.lastSignature) return this.lastModel;
    this.lastSignature = signature;
    this.lastModel = model;
    return model;
  }

  invoke(): void {}
  destroy(): void { this.stopped = true; this.lastModel = {}; }
}
