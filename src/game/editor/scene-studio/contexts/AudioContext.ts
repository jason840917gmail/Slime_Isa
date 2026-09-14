export class AudioPreviewContext {
  private stopCurrent?: () => void;
  preview(play: () => () => void): void { this.stop(); this.stopCurrent = play(); }
  stop(): void { const stop = this.stopCurrent; this.stopCurrent = undefined; stop?.(); }
  get playing(): boolean { return this.stopCurrent !== undefined; }
}
