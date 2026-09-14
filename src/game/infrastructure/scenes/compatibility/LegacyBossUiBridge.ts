import type { BossStatusViewPort } from '../../../features/scripts/BossCampScript';

export interface LegacyBossBarHandle {
  destroy(): void;
  defeat?(): void;
}

export type LegacyBossBarFactory = (campId: string, bossId: string) => LegacyBossBarHandle;

export class LegacyBossUiBridge implements BossStatusViewPort {
  private readonly bars = new Map<string, LegacyBossBarHandle>();

  constructor(private readonly createBar: LegacyBossBarFactory) {}

  showBoss(campId: string, bossId: string): void {
    this.hideBoss(campId, false);
    this.bars.set(campId, this.createBar(campId, bossId));
  }

  hideBoss(campId: string, defeated: boolean): void {
    const bar = this.bars.get(campId);
    if (!bar) return;
    if (defeated) bar.defeat?.();
    else bar.destroy();
    this.bars.delete(campId);
  }

  dispose(): void {
    for (const bar of this.bars.values()) bar.destroy();
    this.bars.clear();
  }
}

