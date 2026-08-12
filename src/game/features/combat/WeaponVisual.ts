import Phaser from 'phaser';

import type {
  NormalizedWeaponDefinition,
  WeaponAttackDirection,
  WeaponPlaybackAnimationId,
} from '../../content/weapons/types';
import { AnimationClock } from '../../shared/animation';
import { LayeredAnimationVisual } from '../visuals/LayeredAnimationVisual';
import type { LayeredAnimationHost } from '../visuals/LayeredAnimationHost';

type WeaponVisualAnchor = Phaser.GameObjects.GameObject & {
  readonly x: number;
  readonly y: number;
};

/** Weapon host adapter over the shared clock and layered visual renderer. */
export class WeaponVisual implements LayeredAnimationHost {
  private readonly clock: AnimationClock;
  private readonly visual: LayeredAnimationVisual;
  private activeAnimationId: WeaponPlaybackAnimationId = 'idle';
  private destroyed = false;

  constructor(
    private readonly scene: Phaser.Scene,
    private readonly anchor: WeaponVisualAnchor,
    private readonly definition: NormalizedWeaponDefinition,
    clock: AnimationClock,
    private readonly options: {
      readonly getDepth: () => number;
      readonly getFacing: () => Phaser.Math.Vector2;
    },
  ) {
    this.clock = clock;
    this.visual = new LayeredAnimationVisual(scene, this, this.clock, definition.animations.idle, {
      onDiagnostic: (message) => {
        if (import.meta.env.DEV) console.warn(`[weapon:${definition.weaponId}] ${message}`);
      },
    });
    this.anchor.once(Phaser.GameObjects.Events.DESTROY, this.handleAnchorDestroy);
    this.scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
  }

  play(animationId: WeaponPlaybackAnimationId, forceRestart = true): void {
    if (!forceRestart && !this.clock.state.paused) return;
    this.activeAnimationId = animationId;
    const animation = this.animation(animationId);
    this.visual.setAnimation(animation);
    void forceRestart;
  }

  update(deltaMs: number): void {
    void deltaMs;
    this.visual.updateAnchor();
  }

  setVisible(visible: boolean): void {
    this.visual.setVisible(visible);
  }

  getAnimationHostTransform() {
    const direction = this.activeDirection();
    const attack = direction ? this.definition.directionalAttacks[direction] : undefined;
    const facing = this.options.getFacing().lengthSq() > 0
      ? this.options.getFacing().clone().normalize()
      : new Phaser.Math.Vector2(1, 0);
    const legacyVector = attack?.presentation === 'legacy-vector';
    const mirrorX = attack?.presentation === 'mirror-right'
      || (!attack && this.definition.presentation.facingMode === 'horizontal-flip' && facing.x < 0);
    return {
      x: this.anchor.x,
      y: this.anchor.y,
      baseDepth: this.options.getDepth(),
      rotationRad: legacyVector && this.definition.presentation.facingMode === 'vector'
        ? Math.atan2(facing.y, facing.x)
        : 0,
      mirrorX,
    };
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.anchor.off(Phaser.GameObjects.Events.DESTROY, this.handleAnchorDestroy);
    this.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
    this.visual.destroy();
  }

  private animation(animationId: WeaponPlaybackAnimationId) {
    if (animationId === 'idle') return this.definition.animations.idle;
    return this.definition.directionalAttacks[animationId.slice('attack-'.length) as WeaponAttackDirection].animation;
  }

  private activeDirection(): WeaponAttackDirection | undefined {
    return this.activeAnimationId.startsWith('attack-')
      ? this.activeAnimationId.slice('attack-'.length) as WeaponAttackDirection
      : undefined;
  }

  private readonly handleAnchorDestroy = (): void => { this.destroy(); };
  private readonly handleSceneShutdown = (): void => { this.destroy(); };
}
