import Phaser from 'phaser';
import { getAsset, type AssetId } from '../../infrastructure/assets/manifest';
import type { CharacterPackage } from '../../content/characters/types';
import type { MapNpcWanderArea } from '../../content/maps/mapFormat';
import { AnimatedVisual } from '../visuals/AnimatedVisual';
import { applyArcadeBodyGeometry } from '../../shared/collisionShapes';
import { CharacterAnimationTrackRunner, type CharacterTrackEvent } from '../characters/CharacterAnimationTrackRunner';
import { createNpcWanderState, stepNpcWander, type NpcFacing, type NpcWanderState } from './NpcWanderPolicy';

export interface NpcActorOptions {
  readonly packageValue: CharacterPackage;
  readonly definitionId: string;
  readonly x: number;
  readonly y: number;
  readonly area?: MapNpcWanderArea;
  readonly getDepth?: () => number;
  readonly instanceId: string;
  readonly onPresentationEvent?: (event: CharacterTrackEvent, instanceId: string) => void;
}

/** Lightweight non-combat actor for an authored NPC placement. */
export class NpcActor {
  readonly anchor: Phaser.Physics.Arcade.Image;
  readonly visual: AnimatedVisual;
  readonly image: Phaser.Physics.Arcade.Image;
  readonly instanceId: string;
  readonly npcId: string;
  private readonly packageValue: CharacterPackage;
  private readonly area?: MapNpcWanderArea;
  private readonly pauseMinMs: number;
  private readonly pauseMaxMs: number;
  private readonly trackRunner: CharacterAnimationTrackRunner;
  private wanderState: NpcWanderState;
  private activeAnimation: string = 'idle';
  private simulationPaused = false;
  private paused = false;
  private interactionLocks = 0;
  private destroyed = false;

  constructor(scene: Phaser.Scene, options: NpcActorOptions) {
    this.packageValue = options.packageValue;
    this.area = options.area;
    this.instanceId = options.instanceId;
    this.npcId = options.definitionId;
    this.pauseMinMs = options.packageValue.character.npc?.pauseMinMs ?? 1000;
    this.pauseMaxMs = options.packageValue.character.npc?.pauseMaxMs ?? this.pauseMinMs;
    const visualAsset = getAsset(options.packageValue.visualSet.assetId as AssetId);
    const anchorTexture = scene.textures.exists(visualAsset.runtime.textureKey)
      ? visualAsset.runtime.textureKey
      : '__WHITE';
    this.anchor = scene.physics.add.image(options.x, options.y, anchorTexture, 0);
    this.anchor.setAlpha(0).setCollideWorldBounds(false);
    applyArcadeBodyGeometry(this.anchor.body as Phaser.Physics.Arcade.Body, this.anchor.displayOriginX, this.anchor.displayOriginY, options.packageValue.character.body);
    this.visual = new AnimatedVisual(scene, this.anchor, options.packageValue.visualSet.visualSetId, { getDepth: options.getDepth, initialFrame: 0 });
    this.trackRunner = new CharacterAnimationTrackRunner(options.packageValue.character, options.packageValue.visualSet, {
      onEvent: (event) => options.onPresentationEvent?.(event, options.instanceId),
    });
    this.image = this.anchor;
    this.image.setData('npcId', options.definitionId);
    this.visual.play('idle');
    this.trackRunner.start('idle');
    this.wanderState = createNpcWanderState(this.area ? this.randomPause() : Number.POSITIVE_INFINITY);
  }

  update(deltaMs: number): void {
    if (this.destroyed) return;
    this.trackRunner.update(Math.max(0, Number.isFinite(deltaMs) ? deltaMs : 0));
    if (this.paused || !this.area) return;
    const speed = this.packageValue.character.npc?.wanderSpeed ?? 0;
    const result = stepNpcWander(this.wanderState, {
      position: { x: this.anchor.x, y: this.anchor.y },
      deltaMs,
      speed,
      body: this.packageValue.character.body,
      perimeter: this.area.perimeter,
    });
    this.wanderState = result.state;
    this.anchor.setVelocity(result.velocity.x, result.velocity.y);
    this.playAnimation(result.animation);
    if (result.animation === 'idle' && result.state.phase === 'pause' && result.state.pauseRemainingMs === 0) {
      this.wanderState = createNpcWanderState(this.randomPause(), result.state.facing);
    }
  }

  setPaused(paused: boolean): void {
    if (this.destroyed) return;
    this.simulationPaused = paused;
    const nextPaused = this.simulationPaused || this.interactionLocks > 0;
    if (this.paused === nextPaused) {
      if (nextPaused) this.anchor.setVelocity(0, 0);
      return;
    }
    this.paused = nextPaused;
    if (this.paused) {
      this.anchor.setVelocity(0, 0);
      this.playAnimation('idle');
      this.trackRunner.pause();
    } else {
      this.wanderState = createNpcWanderState(this.area ? this.randomPause() : Number.POSITIVE_INFINITY, this.wanderState.facing);
      this.trackRunner.resume();
    }
  }

  acquireInteractionLock(): () => void {
    if (this.destroyed) return () => undefined;
    this.interactionLocks += 1;
    this.setPaused(this.simulationPaused);
    let released = false;
    return () => {
      if (released || this.destroyed) return;
      released = true;
      this.interactionLocks = Math.max(0, this.interactionLocks - 1);
      if (this.interactionLocks === 0) this.setPaused(this.simulationPaused);
    };
  }

  getPosition(): { readonly x: number; readonly y: number } {
    return { x: this.anchor.x, y: this.anchor.y };
  }

  isActive(): boolean {
    return this.anchor.active;
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.anchor.setVelocity(0, 0);
    this.trackRunner.destroy();
    this.visual.destroy();
    this.anchor.destroy();
  }

  private playAnimation(animation: 'idle' | `walk-${NpcFacing}`): void {
    if (this.activeAnimation !== animation) {
      this.activeAnimation = animation;
      this.visual.play(animation);
      // A direction change is a real clip change, so restart the track runner
      // instead of leaving it on the previous directional row after a pause.
      this.trackRunner.start(animation === 'idle' ? 'idle' : animation, true);
    }
    if (animation !== 'idle') this.visual.setFlipX(false);
  }

  private randomPause(): number {
    return this.pauseMinMs + Math.random() * Math.max(0, this.pauseMaxMs - this.pauseMinMs);
  }
}
