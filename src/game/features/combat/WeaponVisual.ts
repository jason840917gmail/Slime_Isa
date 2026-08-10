import Phaser from 'phaser';

import type { AssetId } from '../../infrastructure/assets/manifest';
import { getAsset } from '../../infrastructure/assets/manifest';
import type {
  NormalizedWeaponDefinition,
  NormalizedWeaponAnimationDocument,
  WeaponAttackDirection,
  WeaponPlaybackAnimationId,
} from '../../content/weapons/types';
import { AnimationPlayer, type AnimationPlaybackState } from '../../shared/animation';

type WeaponVisualAnchor = Phaser.GameObjects.GameObject & {
  readonly x: number;
  readonly y: number;
};

type WeaponFacingMode = NonNullable<NonNullable<NormalizedWeaponDefinition['visual']>['facingMode']>;

/** Render-only weapon layer attached to a stable player anchor. */
export class WeaponVisual {
  readonly sprite?: Phaser.GameObjects.Sprite;

  private readonly anchor: WeaponVisualAnchor;
  private readonly definition: NormalizedWeaponDefinition;
  private readonly depthResolver: () => number;
  private readonly facing: () => Phaser.Math.Vector2;
  private readonly asset?: ReturnType<typeof getAsset>;
  private activeAnimationId: WeaponPlaybackAnimationId = 'idle';
  private frameIndex = 0;
  private framePosition = 0;
  private destroyed = false;
  private readonly player = new AnimationPlayer({
    onFrame: (state) => this.applyPlaybackFrame(state),
  });

  constructor(
    private readonly scene: Phaser.Scene,
    anchor: WeaponVisualAnchor,
    definition: NormalizedWeaponDefinition,
    options: {
      readonly getDepth: () => number;
      readonly getFacing: () => Phaser.Math.Vector2;
    },
  ) {
    this.anchor = anchor;
    this.definition = definition;
    this.depthResolver = options.getDepth;
    this.facing = options.getFacing;
    if (definition.assetId) {
      try {
        this.asset = getAsset(definition.assetId as AssetId);
      } catch {
        this.asset = undefined;
      }
    }
    if (this.asset) {
      const textureKey = this.asset.runtime.textureKey;
      this.sprite = this.asset.source.kind === 'spritesheet'
        ? scene.add.sprite(anchor.x, anchor.y, textureKey, 0)
        : scene.add.sprite(anchor.x, anchor.y, textureKey);
      this.sprite.setDepth(this.depthResolver());
    }

    this.anchor.once(Phaser.GameObjects.Events.DESTROY, this.handleAnchorDestroy);
    this.scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
    this.applyTransform();
  }

  play(animationId: WeaponPlaybackAnimationId, forceRestart = true): void {
    if (!forceRestart && !this.player.state.paused) return;
    this.activeAnimationId = animationId;
    this.frameIndex = 0;
    this.framePosition = 0;
    this.player.start(this.animationClip(animationId), [], forceRestart);
    this.applyTransform();
  }

  update(deltaMs: number): void {
    this.player.update(deltaMs);
    this.applyTransform();
  }

  setVisible(visible: boolean): void {
    this.sprite?.setVisible(visible);
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.anchor.off(Phaser.GameObjects.Events.DESTROY, this.handleAnchorDestroy);
    this.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
    this.player.destroy();
    this.sprite?.destroy();
  }

  private animationClip(animationId = this.activeAnimationId): NormalizedWeaponAnimationDocument {
    if (animationId === 'idle' || animationId === 'impact') return this.definition.animations[animationId];
    return this.definition.directionalAttacks[animationId.slice('attack-'.length) as WeaponAttackDirection].animation;
  }

  private activeDirection(): WeaponAttackDirection | undefined {
    return this.activeAnimationId.startsWith('attack-')
      ? this.activeAnimationId.slice('attack-'.length) as WeaponAttackDirection
      : undefined;
  }

  private applyTransform(): void {
    const sprite = this.sprite;
    if (this.destroyed || !sprite) return;
    const visual = this.definition.visual;
    const origin = visual.origin ?? [0.5, 0.5];
    const baseScale = visual.scale ?? [1, 1];
    const mode: WeaponFacingMode = visual.facingMode ?? 'vector';
    const facing = this.facing().lengthSq() > 0
      ? this.facing().clone().normalize()
      : new Phaser.Math.Vector2(1, 0);
    const direction = this.activeDirection();
    const directionalAttack = direction ? this.definition.directionalAttacks[direction] : undefined;
    const presentation = directionalAttack?.presentation ?? 'legacy-vector';
    const usesAuthoredDirection = presentation !== 'legacy-vector';
    const facingAngle = Math.atan2(facing.y, facing.x);
    const angle = usesAuthoredDirection ? 0 : mode === 'vector' ? facingAngle : 0;
    const flipX = usesAuthoredDirection
      ? presentation === 'mirror-right'
      : mode === 'horizontal-flip' && facing.x < 0;
    const animationOffsetKey = presentation === 'mirror-right'
      ? 'attack-right'
      : direction ? `attack-${direction}` : this.activeAnimationId;
    const baseOffset = visual.frameOffsets?.[String(this.frameIndex)]
      ?? visual.animationOffsets?.[animationOffsetKey]
      ?? (direction ? visual.animationOffsets?.attack : undefined)
      ?? visual.sourceOffset;
    const frameTransform = this.animationClip().frameTransforms?.[String(this.framePosition)];
    const occurrenceOffset = frameTransform?.offset ?? [0, 0];
    const occurrenceScale = frameTransform?.scale ?? [1, 1];
    const scaleX = baseScale[0] * occurrenceScale[0];
    const scaleY = baseScale[1] * occurrenceScale[1];
    const scaledOffsetX = (baseOffset[0] + occurrenceOffset[0]) * baseScale[0];
    const scaledOffsetY = (baseOffset[1] + occurrenceOffset[1]) * baseScale[1];
    const rotatesWithFacing = !usesAuthoredDirection && mode === 'vector';
    const offsetX = rotatesWithFacing
      ? scaledOffsetX * Math.cos(angle) - scaledOffsetY * Math.sin(angle)
      : scaledOffsetX * (flipX ? -1 : 1);
    const offsetY = rotatesWithFacing
      ? scaledOffsetX * Math.sin(angle) + scaledOffsetY * Math.cos(angle)
      : scaledOffsetY;
    const localRotation = Phaser.Math.DegToRad(frameTransform?.rotationDeg ?? 0);

    sprite
      .setOrigin(origin[0], origin[1])
      .setScale(scaleX, scaleY)
      .setFlipX(flipX)
      .setRotation(angle + localRotation)
      .setPosition(this.anchor.x + offsetX, this.anchor.y + offsetY)
      .setDepth(this.depthResolver());
  }

  private applyPlaybackFrame(state: AnimationPlaybackState): void {
    this.frameIndex = state.sourceFrame;
    this.framePosition = state.occurrenceIndex;
    this.sprite?.setFrame(this.frameIndex);
    this.applyTransform();
  }

  private readonly handleAnchorDestroy = (): void => { this.destroy(); };
  private readonly handleSceneShutdown = (): void => { this.destroy(); };
}
