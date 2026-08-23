import type Phaser from 'phaser';

export type WorldEffectPositionTarget = Pick<Phaser.GameObjects.GameObject, 'once' | 'off'> & {
  readonly x: number;
  readonly y: number;
  readonly depth: number;
  readonly body?: unknown;
};

type PositionResolver = (target: WorldEffectPositionTarget) => { readonly x: number; readonly y: number };

interface PositionSink {
  setPosition(x: number, y: number): void;
  setDepth(baseDepth: number): void;
}

/** Follows a target's world position/depth and freezes after target destruction. */
export class WorldEffectPositionAttachment {
  private target?: WorldEffectPositionTarget;
  private x: number;
  private y: number;
  private depth: number;

  constructor(
    private readonly sink: PositionSink,
    target: WorldEffectPositionTarget,
    private readonly destroyEvent: string,
    initialX: number,
    initialY: number,
    initialDepth: number,
    private readonly depthOffset: number,
    private readonly resolvePosition?: PositionResolver,
  ) {
    this.target = target;
    this.x = initialX;
    this.y = initialY;
    this.depth = initialDepth;
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
    const position = this.resolvePosition?.(target) ?? target;
    if (Number.isFinite(position.x)) this.x = position.x;
    if (Number.isFinite(position.y)) this.y = position.y;
    if (Number.isFinite(target.depth) && Number.isFinite(this.depthOffset)) {
      const nextDepth = target.depth + this.depthOffset;
      if (Number.isFinite(nextDepth)) this.depth = nextDepth;
    }
    this.sink.setPosition(this.x, this.y);
    this.sink.setDepth(this.depth);
  }

  private readonly handleTargetDestroy = (): void => {
    this.sync();
    this.dispose();
  };
}
