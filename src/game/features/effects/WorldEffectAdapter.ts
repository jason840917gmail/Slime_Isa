import type { LayeredAnimationHost } from '../visuals/LayeredAnimationHost';

export class WorldEffectAdapter implements LayeredAnimationHost {
  constructor(
    private x: number,
    private y: number,
    private baseDepth: number,
    private mirrorX: boolean,
    private mirrorY: boolean,
  ) {}

  reset(x: number, y: number, baseDepth: number, mirrorX: boolean, mirrorY: boolean): void {
    this.x = x;
    this.y = y;
    this.baseDepth = baseDepth;
    this.mirrorX = mirrorX;
    this.mirrorY = mirrorY;
  }

  setPosition(x: number, y: number): void {
    this.x = x;
    this.y = y;
  }

  getAnimationHostTransform() {
    return {
      x: this.x,
      y: this.y,
      baseDepth: this.baseDepth,
      rotationRad: 0,
      mirrorX: this.mirrorX,
      mirrorY: this.mirrorY,
    };
  }
}
