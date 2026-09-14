import type { ChestViewModel, ChestViewPort } from '../../../features/scripts/ChestScript';

export interface LegacyChestPanelPort {
  open(instanceId: string): void;
  close(): void;
  destroy(): void;
}

export class LegacyChestUiBridge implements ChestViewPort {
  private model?: ChestViewModel;
  private disposed = false;

  constructor(private readonly panel: LegacyChestPanelPort) {}

  open(model: ChestViewModel): void {
    this.assertActive();
    this.model = model;
    this.panel.open(model.instanceId);
  }

  close(instanceId: string): void {
    if (this.disposed || this.model?.instanceId !== instanceId) return;
    this.panel.close();
    this.model = undefined;
  }

  getContents(instanceId: string): Readonly<Record<string, number>> {
    return this.model?.instanceId === instanceId ? this.model.contents : {};
  }

  transferStack(instanceId: string, itemId: string): number {
    return this.model?.instanceId === instanceId ? this.model.transferStack(itemId) : 0;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.model = undefined;
    this.panel.destroy();
  }

  private assertActive(): void {
    if (this.disposed) throw new Error('LegacyChestUiBridge has been disposed.');
  }
}

