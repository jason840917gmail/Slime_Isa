import Phaser from 'phaser';

import type { AssetId } from '../../infrastructure/assets/manifest';
import { getAsset } from '../../infrastructure/assets/manifest';
import {
  AnimationClock,
  composeAnimationVisualTransform,
  LayeredAnimationPlayer,
  type LayeredAnimationPlaybackState,
  type NormalizedLayeredAnimationDocument,
  type ResolvedAnimationVisualLayer,
} from '../../shared/animation';
import type { LayeredAnimationHost } from './LayeredAnimationHost';

interface LayerSpriteSlot {
  readonly sprite: Phaser.GameObjects.Sprite;
  assetId: string;
}

export interface LayeredAnimationVisualOptions {
  readonly onDiagnostic?: (message: string) => void;
}

/** Reusable sprite set driven by a shared external animation clock. */
export class LayeredAnimationVisual {
  private animation: NormalizedLayeredAnimationDocument;
  private readonly player: LayeredAnimationPlayer;
  private readonly slots: LayerSpriteSlot[] = [];
  private readonly invalidLayerIds = new Set<string>();
  private currentLayers: readonly ResolvedAnimationVisualLayer[] = [];
  private visible = true;
  private destroyed = false;

  constructor(
    private readonly scene: Phaser.Scene,
    private readonly host: LayeredAnimationHost,
    clock: AnimationClock,
    animation: NormalizedLayeredAnimationDocument,
    private readonly options: LayeredAnimationVisualOptions = {},
  ) {
    this.animation = animation;
    this.player = new LayeredAnimationPlayer(clock, animation, (state) => this.applyFrame(state));
    this.scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
  }

  setAnimation(animation: NormalizedLayeredAnimationDocument): void {
    this.animation = animation;
    this.invalidLayerIds.clear();
    this.currentLayers = [];
    this.player.setAnimation(animation);
    this.hideUnusedSlots(0);
  }

  setVisible(visible: boolean): void {
    this.visible = visible;
    this.applyCurrentFrame();
  }

  updateAnchor(): void {
    this.applyCurrentFrame();
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
    this.player.destroy();
    for (const slot of this.slots) slot.sprite.destroy();
    this.slots.length = 0;
    this.currentLayers = [];
  }

  private applyFrame(state: LayeredAnimationPlaybackState): void {
    this.currentLayers = state.layers;
    this.applyCurrentFrame();
  }

  private applyCurrentFrame(): void {
    if (this.destroyed) return;
    const hostTransform = this.host.getAnimationHostTransform();
    let slotIndex = 0;
    for (const layer of this.currentLayers) {
      const slot = this.resolveSlot(slotIndex, layer);
      if (!slot) continue;
      const transform = composeAnimationVisualTransform(layer, hostTransform);
      slot.sprite
        .setFrame(layer.sourceFrame)
        .setOrigin(transform.originX, transform.originY)
        .setPosition(transform.x, transform.y)
        .setScale(transform.scaleX, transform.scaleY)
        .setFlip(transform.flipX, transform.flipY)
        .setRotation(transform.rotationRad)
        .setDepth(transform.depth)
        .setVisible(this.visible);
      slotIndex += 1;
    }
    this.hideUnusedSlots(slotIndex);
  }

  private resolveSlot(slotIndex: number, layer: ResolvedAnimationVisualLayer): LayerSpriteSlot | undefined {
    let asset: ReturnType<typeof getAsset>;
    try {
      asset = getAsset(layer.assetId as AssetId);
      if (!asset || asset.source.kind !== 'spritesheet') throw new Error('not a spritesheet');
    } catch {
      this.reportInvalidLayer(layer, `Layer '${layer.layerId}' references unavailable spritesheet '${layer.assetId}'`);
      return undefined;
    }

    const textureKey = asset.runtime.textureKey;
    let slot = this.slots[slotIndex];
    if (!slot) {
      slot = {
        sprite: this.scene.add.sprite(0, 0, textureKey, layer.sourceFrame).setVisible(false),
        assetId: layer.assetId,
      };
      this.slots.push(slot);
    } else if (slot.assetId !== layer.assetId) {
      slot.assetId = layer.assetId;
      slot.sprite.setTexture(textureKey, layer.sourceFrame);
    }
    return slot;
  }

  private hideUnusedSlots(start: number): void {
    for (let index = start; index < this.slots.length; index += 1) this.slots[index].sprite.setVisible(false);
  }

  private reportInvalidLayer(layer: ResolvedAnimationVisualLayer, message: string): void {
    const key = `${this.animation.version}:${layer.layerId}:${layer.assetId}`;
    if (this.invalidLayerIds.has(key)) return;
    this.invalidLayerIds.add(key);
    this.options.onDiagnostic?.(message);
  }

  private readonly handleSceneShutdown = (): void => {
    this.destroy();
  };
}
