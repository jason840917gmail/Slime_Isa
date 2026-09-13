import type Phaser from 'phaser';

import type { ResourceId, RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D, type Node2DOptions, type Vector2 } from '../../runtime/scene/Node2D';
import { defaultWorldDepthResolver, type WorldDepthBand, type WorldDepthResolver } from '../../presentation/WorldDepth';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';
import type { PresentationParticipant } from './PresentationSync';

export interface Sprite2DNodeOptions extends Node2DOptions {
  readonly context: PhaserNodeContext;
  readonly texture: ResourceId;
  readonly frame?: number;
  readonly origin?: Vector2;
  readonly visualOffset?: Vector2;
  readonly alpha?: number;
  readonly tint?: string;
  readonly flipX?: boolean;
  readonly flipY?: boolean;
  readonly depthMode?: 'world-sorted' | 'explicit';
  readonly depthBand?: WorldDepthBand;
  readonly depth?: number;
  readonly depthResolver?: WorldDepthResolver;
}

function colorNumber(value: string | undefined): number | undefined {
  if (!value) return undefined;
  if (!/^#[0-9a-f]{6}$/i.test(value)) throw new Error(`Sprite tint '${value}' must be #RRGGBB`);
  return Number.parseInt(value.slice(1), 16);
}

export class Sprite2DNode extends Node2D implements PresentationParticipant {
  private sprite?: Phaser.GameObjects.Sprite;
  private readonly origin: Vector2;
  private readonly visualOffset: Vector2;
  private readonly tint?: number;
  private readonly depthResolver: WorldDepthResolver;

  constructor(private readonly spriteOptions: Sprite2DNodeOptions) {
    super(spriteOptions);
    this.origin = spriteOptions.origin ?? { x: 0.5, y: 0.5 };
    this.visualOffset = spriteOptions.visualOffset ?? { x: 0, y: 0 };
    this.tint = colorNumber(spriteOptions.tint);
    this.depthResolver = spriteOptions.depthResolver ?? defaultWorldDepthResolver;
    const alpha = spriteOptions.alpha ?? 1;
    if (![this.origin.x, this.origin.y, this.visualOffset.x, this.visualOffset.y, alpha, spriteOptions.depth ?? 0].every(Number.isFinite)) {
      throw new Error('Sprite presentation values must be finite');
    }
    if (alpha < 0 || alpha > 1) throw new Error('Sprite alpha must be between 0 and 1');
    if (spriteOptions.frame !== undefined && (!Number.isInteger(spriteOptions.frame) || spriteOptions.frame < 0)) throw new Error('Sprite frame must be a non-negative integer');
  }

  get phaserObjectActive(): boolean { return this.sprite !== undefined; }

  override _enter_tree(): void {
    const resource = this.spriteOptions.context.resource(this.spriteOptions.texture);
    if (resource.kind !== 'texture' && resource.kind !== 'sprite-sheet') throw new Error(`Resource '${resource.resourceId}' cannot back Sprite2D`);
    const frame = this.spriteOptions.frame ?? (resource.kind === 'texture' ? resource.frame : undefined);
    const sprite = this.spriteOptions.context.scene.add.sprite(0, 0, resource.assetId, frame);
    this.sprite = sprite;
    sprite.setName(this.runtimeId);
    sprite.setOrigin(this.origin.x, this.origin.y);
    sprite.setAlpha(this.spriteOptions.alpha ?? 1);
    sprite.setFlip(Boolean(this.spriteOptions.flipX), Boolean(this.spriteOptions.flipY));
    if (this.tint !== undefined) sprite.setTint(this.tint);
    const unregister = this.spriteOptions.context.registerPresentation(this);
    this.entryDisposables.add(() => unregister());
    this.entryDisposables.add(() => { sprite.destroy(); if (this.sprite === sprite) this.sprite = undefined; });
    this.syncPresentation(1);
  }

  syncPresentation(_alpha: number): void {
    const sprite = this.sprite;
    if (!sprite) return;
    const transform = this.get_global_transform();
    const offsetX = this.visualOffset.x * transform.scale.x;
    const offsetY = this.visualOffset.y * transform.scale.y;
    const cosine = Math.cos(transform.rotation);
    const sine = Math.sin(transform.rotation);
    sprite.setPosition(
      transform.position.x + offsetX * cosine - offsetY * sine,
      transform.position.y + offsetX * sine + offsetY * cosine,
    );
    sprite.setRotation(transform.rotation);
    sprite.setScale(transform.scale.x, transform.scale.y);
    sprite.setVisible(this.visible);
    const depth = this.spriteOptions.depthMode === 'explicit'
      ? this.spriteOptions.depth ?? 0
      : this.depthResolver.resolve(transform.position.y, { band: this.spriteOptions.depthBand, stableId: this.runtimeId }).depth;
    sprite.setDepth(depth);
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): Sprite2DNode {
    return new Sprite2DNode({ ...this.spriteOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible });
  }
}
