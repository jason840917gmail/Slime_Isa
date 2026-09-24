import type { JsonValue } from '../../content/scenes/types';
import type { BossStatusViewPort } from '../scripts/BossCampScript';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

export interface BossHealthSource {
  readonly name: string;
  readonly hp: () => number;
  readonly maxHp: () => number;
}

/** Presents the currently active authored boss without owning combat state. */
export class BossHealthSurfacePort implements UiSurfacePort, BossStatusViewPort {
  private readonly active = new Map<string, BossHealthSource>();
  private lastSignature = '';
  private lastModel: UiPresentationModel = {};
  private stopped = false;

  constructor(private readonly resolveBoss: (campId: string, bossId: string) => BossHealthSource | undefined) {}

  showBoss(campId: string, bossId: string): void {
    if (this.stopped) return;
    const source = this.resolveBoss(campId, bossId);
    if (source) this.active.set(campId, source);
    this.lastSignature = '';
  }

  hideBoss(campId: string, _defeated: boolean): void {
    this.active.delete(campId);
    this.lastSignature = '';
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'boss-health-bar' || this.stopped) return {};
    const source = [...this.active.values()].at(-1);
    const model = {
      name: source?.name ?? '',
      hp: Math.max(0, source?.hp() ?? 0),
      maxHp: Math.max(1, source?.maxHp() ?? 1),
      visible: source !== undefined,
    } satisfies Readonly<Record<string, JsonValue>>;
    const signature = JSON.stringify(model);
    if (signature === this.lastSignature) return this.lastModel;
    this.lastSignature = signature;
    this.lastModel = model;
    return model;
  }

  invoke(): void {}

  destroy(): void {
    this.stopped = true;
    this.active.clear();
    this.lastModel = {};
  }
}
