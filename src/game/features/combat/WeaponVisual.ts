import Phaser from 'phaser';

import type { AssetId } from '../../infrastructure/assets/manifest';
import { getAsset } from '../../infrastructure/assets/manifest';
import type {
  NormalizedWeaponDefinition,
  WeaponAnimationDocument,
  WeaponAttackDirection,
  WeaponPlaybackAnimationId,
} from '../../content/weapons/types';

type WeaponVisualAnchor = Phaser.GameObjects.GameObject & {
  readonly x: number;
  readonly y: number;
};

type WeaponFacingMode = NonNullable<NonNullable<NormalizedWeaponDefinition['visual']>['facingMode']>;

const registeredKeys = new WeakMap<Phaser.Animations.AnimationManager, Set<string>>();

function ownedKeys(manager: Phaser.Animations.AnimationManager): Set<string> {
  const current = registeredKeys.get(manager);
  if (current) return current;
  const next = new Set<string>();
  registeredKeys.set(manager, next);
  return next;
}

function runtimeKey(weaponId: string, animationId: string): string {
  return `weapon:${weaponId}:${animationId}`;
}

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
      this.sprite.on(Phaser.Animations.Events.ANIMATION_UPDATE, this.handleAnimationUpdate);
      this.registerAnimations();
    }

    this.anchor.once(Phaser.GameObjects.Events.DESTROY, this.handleAnchorDestroy);
    this.scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
    this.applyTransform();
  }

  play(animationId: WeaponPlaybackAnimationId, forceRestart = true): void {
    this.activeAnimationId = animationId;
    this.frameIndex = 0;
    this.framePosition = 0;
    const sprite = this.sprite;
    if (!sprite || !this.asset) return;
    const key = runtimeKey(this.definition.weaponId, animationId);
    if (this.asset.source.kind === 'spritesheet' && this.scene.anims.exists(key)) {
      sprite.play(key, !forceRestart);
      const currentFrame = sprite.anims.currentFrame?.textureFrame;
      this.frameIndex = typeof currentFrame === 'number' ? currentFrame : Number(currentFrame) || 0;
    } else {
      sprite.setFrame(0);
    }
    this.applyTransform();
  }

  update(): void {
    this.applyTransform();
  }

  setVisible(visible: boolean): void {
    this.sprite?.setVisible(visible);
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.sprite?.off(Phaser.Animations.Events.ANIMATION_UPDATE, this.handleAnimationUpdate);
    this.anchor.off(Phaser.GameObjects.Events.DESTROY, this.handleAnchorDestroy);
    this.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
    this.sprite?.destroy();
  }

  private registerAnimations(): void {
    if (!this.asset || this.asset.source.kind !== 'spritesheet') return;
    const keys = ownedKeys(this.scene.anims);
    const textureKey = this.asset.runtime.textureKey;
    for (const animationId of ['idle', 'attack-right', 'attack-left', 'attack-up', 'attack-down', 'impact'] as const) {
      const clip = this.animationClip(animationId);
      const key = runtimeKey(this.definition.weaponId, animationId);
      if (this.scene.anims.exists(key)) continue;
      const frames = this.clampedFrames(clip);
      this.scene.anims.create({
        key,
        frames: frames.map((frame) => ({ key: textureKey, frame })),
        frameRate: clip.framesPerSecond,
        repeat: clip.loop ? -1 : 0,
        yoyo: clip.loop && clip.loopMode === 'ping-pong',
      });
      keys.add(key);
    }
  }

  private animationClip(animationId = this.activeAnimationId): WeaponAnimationDocument {
    if (animationId === 'idle' || animationId === 'impact') return this.definition.animations[animationId];
    return this.definition.directionalAttacks[animationId.slice('attack-'.length) as WeaponAttackDirection].animation;
  }

  private activeDirection(): WeaponAttackDirection | undefined {
    return this.activeAnimationId.startsWith('attack-')
      ? this.activeAnimationId.slice('attack-'.length) as WeaponAttackDirection
      : undefined;
  }

  private clampedFrames(clip: WeaponAnimationDocument): number[] {
    const count = this.asset && 'frame' in this.asset.source
      ? this.asset.source.frame.cols * this.asset.source.frame.rows
      : 1;
    return clip.frames.map((frame) => Phaser.Math.Clamp(frame, 0, Math.max(0, count - 1)));
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

  private readonly handleAnimationUpdate = (
    _animation: Phaser.Animations.Animation,
    frame: Phaser.Animations.AnimationFrame,
  ): void => {
    this.frameIndex = typeof frame.textureFrame === 'number'
      ? frame.textureFrame
      : Number(frame.textureFrame) || 0;
    this.framePosition = Math.max(0, frame.index - 1);
    this.applyTransform();
  };

  private readonly handleAnchorDestroy = (): void => { this.destroy(); };
  private readonly handleSceneShutdown = (): void => { this.destroy(); };
}
