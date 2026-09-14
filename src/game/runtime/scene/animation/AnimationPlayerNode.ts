import type { RuntimeNodeId } from '../../../content/scenes/identifiers';
import type { JsonValue } from '../../../content/scenes/types';
import { AnimationClock, type AnimationClockDocument, type AnimationLoopMode } from '../../../shared/animation';
import { Node, type NodeOptions } from '../Node';
import { AnimationBinding, type AnimationDomain, type AnimationPropertyKey } from './AnimationBinding';
import type { AnimationEventEmission, UniversalAnimationEvent } from './AnimationEvent';

export interface UniversalAnimationPropertyTrack {
  readonly binding: string;
  readonly property: string;
  readonly keys: readonly AnimationPropertyKey[];
}

export interface UniversalAnimationDocument extends AnimationClockDocument {
  readonly loopMode?: AnimationLoopMode;
  readonly tracks: readonly UniversalAnimationPropertyTrack[];
  readonly events?: readonly UniversalAnimationEvent[];
}

export interface AnimationAdvanceSource {
  registerCallback(phase: 'physics-animation' | 'render-animation', callback: (deltaSeconds: number) => void): () => void;
}

export interface AnimationPlayerNodeOptions extends NodeOptions {
  readonly domain: AnimationDomain;
  readonly animations: Readonly<Record<string, UniversalAnimationDocument>>;
  readonly resolveBinding: (player: AnimationPlayerNode, binding: string, property: string) => AnimationBinding;
  readonly advanceSource?: AnimationAdvanceSource;
  readonly autoplay?: string;
}

function validateAnimation(name: string, animation: UniversalAnimationDocument): void {
  if (!Number.isFinite(animation.durationSeconds) || animation.durationSeconds <= 0) throw new Error(`Animation '${name}' duration must be positive`);
  if (!Number.isFinite(animation.framesPerSecond) || animation.framesPerSecond <= 0) throw new Error(`Animation '${name}' frame rate must be positive`);
  const targets = new Set<string>();
  for (const track of animation.tracks) {
    if (track.binding.length === 0 || track.property.length === 0 || track.keys.length === 0) throw new Error(`Animation '${name}' has an invalid property track`);
    const target = `${track.binding}\0${track.property}`;
    if (targets.has(target)) throw new Error(`Animation '${name}' writes '${track.binding}.${track.property}' more than once`);
    targets.add(target);
    for (const key of track.keys) if (!Number.isInteger(key.at) || key.at < 0) throw new Error(`Animation '${name}' key positions must be non-negative integers`);
  }
  for (const event of animation.events ?? []) if (!Number.isInteger(event.at) || event.at < 0) throw new Error(`Animation '${name}' event positions must be non-negative integers`);
}

export class AnimationPlayerNode extends Node {
  readonly animationEvent = this.createSignal<AnimationEventEmission>('animation_event');
  readonly animationFinished = this.createSignal<string>('animation_finished');
  private readonly clock: AnimationClock;
  private readonly writerToken = {};
  private activeBindings: readonly { readonly binding: AnimationBinding; readonly track: UniversalAnimationPropertyTrack }[] = [];
  private activeAnimation?: string;

  constructor(private readonly animationOptions: AnimationPlayerNodeOptions) {
    super(animationOptions);
    for (const [name, animation] of Object.entries(animationOptions.animations)) validateAnimation(name, animation);
    this.clock = new AnimationClock({
      onEvent: (event, context) => {
        if (!this.activeAnimation) return;
        this.animationEvent.emit({ animation: this.activeAnimation, event: event as UniversalAnimationEvent, context });
      },
      onComplete: () => {
        const completed = this.activeAnimation;
        if (!completed) return;
        this.releaseBindings(false);
        this.activeAnimation = undefined;
        this.animationFinished.emit(completed);
      },
    });
    this.clock.subscribeFrame('visual', (state) => {
      for (const { binding, track } of this.activeBindings) binding.apply(state.timelineFrame, track.keys);
    });
    if (!animationOptions.advanceSource) {
      if (animationOptions.domain === 'physics') this.set_physics_process(true);
      else this.set_process(true);
    }
  }

  get currentAnimation(): string | undefined { return this.activeAnimation; }
  get playbackState() { return this.clock.state; }

  override _enter_tree(): void {
    if (this.animationOptions.advanceSource) {
      const phase = this.animationOptions.domain === 'physics' ? 'physics-animation' : 'render-animation';
      this.entryDisposables.add(this.animationOptions.advanceSource.registerCallback(phase, (deltaSeconds) => this.advance(deltaSeconds)));
    }
  }

  override _ready(): void { if (this.animationOptions.autoplay) this.play(this.animationOptions.autoplay); }
  override _process(deltaSeconds: number): void { if (!this.animationOptions.advanceSource) this.advance(deltaSeconds); }
  override _physics_process(deltaSeconds: number): void { if (!this.animationOptions.advanceSource) this.advance(deltaSeconds); }
  override _exit_tree(): void { this.stop(); }

  play(name: string): void {
    const animation = this.animationOptions.animations[name];
    if (!animation) throw new Error(`Unknown animation '${name}'`);
    if (this.animationOptions.domain === 'render' && animation.events?.some((event) => event.gameplay)) throw new Error(`Animation '${name}' has gameplay events and must use the physics domain`);
    this.stop();
    const acquired: { readonly binding: AnimationBinding; readonly track: UniversalAnimationPropertyTrack }[] = [];
    try {
      for (const track of animation.tracks) {
        const binding = this.animationOptions.resolveBinding(this, track.binding, track.property);
        binding.acquire(this.writerToken, this.animationOptions.domain);
        acquired.push({ binding, track });
      }
    } catch (error) {
      for (const { binding } of acquired.reverse()) binding.release(this.writerToken, true);
      throw error;
    }
    this.activeBindings = acquired;
    this.activeAnimation = name;
    this.clock.start(animation, animation.events ?? []);
  }

  pause(): void { this.clock.pause(); }
  resume(): void { this.clock.resume(); }
  seek(frame: number): void { this.clock.scrub(frame); }

  stop(): void {
    this.clock.stop();
    this.releaseBindings(true);
    this.activeAnimation = undefined;
  }

  advance(deltaSeconds: number): void { this.clock.update(deltaSeconds * 1000); }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): AnimationPlayerNode {
    return new AnimationPlayerNode({ ...this.animationOptions, runtimeId, name: this.name });
  }

  private releaseBindings(restoreBaseline: boolean): void {
    for (const { binding } of [...this.activeBindings].reverse()) binding.release(this.writerToken, restoreBaseline);
    this.activeBindings = [];
  }
}

export function parseAnimationLibrary(value: Readonly<Record<string, JsonValue>>): Readonly<Record<string, UniversalAnimationDocument>> {
  return value as unknown as Readonly<Record<string, UniversalAnimationDocument>>;
}
