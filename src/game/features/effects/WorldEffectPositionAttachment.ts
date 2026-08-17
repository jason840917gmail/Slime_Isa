import type Phaser from 'phaser';

export type WorldEffectPositionTarget = Pick<Phaser.GameObjects.GameObject, 'once' | 'off'> & {
  readonly x: number;
  readonly y: number;
};

interface PositionSink {
  setPosition(x: number, y: number): void;
}

/** Follows only a target's world position and freezes after target destruction. */
export class WorldEffectPositionAttachment {
  private target?: WorldEffectPositionTarget;
  private x: number;
  private y: number;

  constructor(
    private readonly sink: PositionSink,
    target: WorldEffectPositionTarget,
    private readonly destroyEvent: string,
    initialX: number,
    initialY: number,
  ) {
    this.target = target;
    this.x = initialX;
    this.y = initialY;
    target.once(this.destroyEvent, this.handleTargetDestroy);
    this.sync();
  }

  update(): void {
    if (!this.target) return;
    this.sync();
  }

  dispose(): void {
    const target = this.target;
    if (!target) return;
    this.target = undefined;
    target.off(this.destroyEvent, this.handleTargetDestroy);
  }

  private sync(): void {
    const target = this.target;
    if (!target) return;
    if (Number.isFinite(target.x)) this.x = target.x;
    if (Number.isFinite(target.y)) this.y = target.y;
    this.sink.setPosition(this.x, this.y);
  }

  private readonly handleTargetDestroy = (): void => {
    this.sync();
    this.dispose();
  };
}
