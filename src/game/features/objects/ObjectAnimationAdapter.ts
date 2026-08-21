import Phaser from 'phaser';

import type {
  AnimationDefinitionResolver,
} from '../../content/animations/AnimationCatalog';
import { AnimationClock } from '../../shared/animation';
import type { LayeredAnimationHostTransform, NormalizedLayeredAnimationDocument } from '../../shared/animation';
import type { LayeredAnimationHost } from '../visuals/LayeredAnimationHost';
import { LayeredAnimationVisual } from '../visuals/LayeredAnimationVisual';

export interface ObjectAnimationAdapterOptions {
  readonly scene: Phaser.Scene;
  readonly anchor: Phaser.GameObjects.Image;
  readonly resolver: AnimationDefinitionResolver;
  readonly objectId: string;
  readonly idleAnimationId?: string;
  readonly onHitAnimationId?: string;
  readonly onDiagnostic?: (message: string) => void;
}

/** Resolves optional object animation packages while keeping the static image as the fallback anchor. */
export class ObjectAnimationAdapter implements LayeredAnimationHost {
  private readonly clock: AnimationClock;
  private visual?: LayeredAnimationVisual;
  private activeSlot: 'idle' | 'hit' | undefined;
  private hitComplete?: () => void;
  private disposed = false;

  constructor(private readonly options: ObjectAnimationAdapterOptions) {
    this.clock = new AnimationClock({ onComplete: this.handlePlaybackComplete });
    if (options.idleAnimationId) this.animateIdle(options.idleAnimationId);
  }

  animateIdle(animationId: string | undefined): void {
    if (this.disposed) return;
    if (!animationId) {
      this.stopToStatic();
      return;
    }
    const animation = this.resolve(animationId, true);
    if (!animation) {
      this.stopToStatic();
      return;
    }
    this.hitComplete = undefined;
    this.activeSlot = 'idle';
    this.start(animation);
  }

  animateOnHit(animationId: string | undefined = this.options.onHitAnimationId, onComplete?: () => void): boolean {
    if (this.disposed || !animationId) return false;
    const animation = this.resolve(animationId, false);
    if (!animation) return false;
    this.hitComplete = onComplete;
    this.activeSlot = 'hit';
    this.start(animation);
    return true;
  }

  update(deltaMs: number): void {
    if (this.disposed) return;
    this.clock.update(deltaMs);
    this.visual?.updateAnchor();
  }

  updateAnchor(): void {
    if (this.disposed) return;
    this.visual?.updateAnchor();
  }

  dispose(): void {
    if (this.disposed) return;
    const completePendingHit = this.activeSlot === 'hit' ? this.hitComplete : undefined;
    this.disposed = true;
    this.hitComplete = undefined;
    this.activeSlot = undefined;
    this.clock.destroy();
    this.visual?.destroy();
    this.visual = undefined;
    this.options.anchor.setVisible(true);
    completePendingHit?.();
  }

  getAnimationHostTransform(): LayeredAnimationHostTransform {
    return {
      x: this.options.anchor.x,
      y: this.options.anchor.y,
      baseDepth: this.options.anchor.depth,
      rotationRad: 0,
      mirrorX: false,
      mirrorY: false,
    };
  }

  private resolve(animationId: string, expectedLoop: boolean): NormalizedLayeredAnimationDocument | undefined {
    const result = this.options.resolver.get(animationId);
    if (!result.ok) {
      this.report(`${result.diagnostic.message}`);
      return undefined;
    }
    if (result.animation.loop !== expectedLoop) {
      this.report(`Object '${this.options.objectId}' animation '${animationId}' has the wrong loop contract`);
      return undefined;
    }
    if (result.animation.layers.length === 0) {
      this.report(`Object '${this.options.objectId}' animation '${animationId}' has no visual layers`);
      return undefined;
    }
    return result.animation;
  }

  private start(animation: NormalizedLayeredAnimationDocument): void {
    if (!this.visual) {
      this.visual = new LayeredAnimationVisual(
        this.options.scene,
        this,
        this.clock,
        animation,
        { onDiagnostic: (message) => this.report(message) },
      );
    } else {
      this.visual.setAnimation(animation);
    }
    this.visual.setVisible(true);
    this.options.anchor.setVisible(false);
    this.clock.start(animation, [], true);
  }

  private stopToStatic(): void {
    this.clock.stop();
    this.activeSlot = undefined;
    this.hitComplete = undefined;
    this.visual?.setVisible(false);
    this.options.anchor.setVisible(true);
  }

  private readonly handlePlaybackComplete = (): void => {
    if (this.disposed || this.activeSlot !== 'hit') return;
    const complete = this.hitComplete;
    this.hitComplete = undefined;
    const idleId = this.options.idleAnimationId;
    if (idleId) this.animateIdle(idleId);
    else this.stopToStatic();
    complete?.();
  };

  private report(message: string): void {
    this.options.onDiagnostic?.(message);
    if (import.meta.env.DEV && !this.options.onDiagnostic) console.warn(message);
  }
}
