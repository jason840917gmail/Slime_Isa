import Phaser from 'phaser';
import { resolveWorldDepth } from '../../presentation/WorldDepth';
import type { SensorShape } from '../../runtime/scene/physics/SensorGeometry';

export interface AttackTelegraphRequest {
  readonly sourceNodeId: string;
  readonly shapes: readonly SensorShape[];
  readonly shadow?: { readonly x: number; readonly y: number };
}

const FILL = 0xff7a3d;
const FILL_ALPHA = 0.15;
const STROKE = 0xffc85a;
const STROKE_ALPHA = 0.85;
const SHADOW = 0x07120e;
const SHADOW_ALPHA = 0.38;

/**
 * Ground warnings for incoming attacks (e.g. where a boss leap will land):
 * the attack's world-space shapes plus a shadow, drawn on the ground-decal
 * band so actors stay in front. One warning per attacking node.
 */
export class AttackTelegraphs {
  private readonly active = new Map<string, Phaser.GameObjects.Graphics>();

  constructor(private readonly scene: Phaser.Scene) {}

  show(request: AttackTelegraphRequest): void {
    this.clear(request.sourceNodeId);
    if (request.shapes.length === 0 && !request.shadow) return;
    const anchorY = request.shadow?.y ?? request.shapes.map(shapeCenterY).reduce((sum, y) => sum + y, 0) / request.shapes.length;
    const graphics = this.scene.add.graphics()
      .setDepth(resolveWorldDepth(anchorY, { band: 'ground-decals', stableId: `telegraph:${request.sourceNodeId}` }).depth);
    if (request.shadow) graphics.fillStyle(SHADOW, SHADOW_ALPHA).fillEllipse(request.shadow.x, request.shadow.y, 96, 34);
    for (const shape of request.shapes) drawShape(graphics, shape);
    this.active.set(request.sourceNodeId, graphics);
  }

  clear(sourceNodeId: string): void {
    this.active.get(sourceNodeId)?.destroy();
    this.active.delete(sourceNodeId);
  }

  destroy(): void {
    for (const graphics of this.active.values()) graphics.destroy();
    this.active.clear();
  }
}

function shapeCenterY(shape: SensorShape): number {
  if (shape.shape === 'rectangle') return shape.y + shape.height / 2;
  return shape.shape === 'sector' ? shape.originY : shape.centerY;
}

function drawShape(graphics: Phaser.GameObjects.Graphics, shape: SensorShape): void {
  graphics.fillStyle(FILL, FILL_ALPHA).lineStyle(3, STROKE, STROKE_ALPHA);
  traceSensorShape(graphics, shape);
}

/** Fills and strokes a world-space sensor shape with the graphics' current styles. */
export function traceSensorShape(graphics: Phaser.GameObjects.Graphics, shape: SensorShape): void {
  if (shape.shape === 'circle') {
    graphics.fillCircle(shape.centerX, shape.centerY, shape.radius).strokeCircle(shape.centerX, shape.centerY, shape.radius);
  } else if (shape.shape === 'ellipse') {
    graphics.fillEllipse(shape.centerX, shape.centerY, shape.radiusX * 2, shape.radiusY * 2).strokeEllipse(shape.centerX, shape.centerY, shape.radiusX * 2, shape.radiusY * 2);
  } else if (shape.shape === 'rectangle') {
    graphics.fillRect(shape.x, shape.y, shape.width, shape.height).strokeRect(shape.x, shape.y, shape.width, shape.height);
  } else {
    const start = shape.angleRad - shape.arcWidthRad / 2;
    const end = shape.angleRad + shape.arcWidthRad / 2;
    graphics.beginPath();
    graphics.arc(shape.originX, shape.originY, shape.outerRadius, start, end, false);
    if (shape.innerRadius > 0) graphics.arc(shape.originX, shape.originY, shape.innerRadius, end, start, true);
    else graphics.lineTo(shape.originX, shape.originY);
    graphics.closePath().fillPath().strokePath();
  }
}
