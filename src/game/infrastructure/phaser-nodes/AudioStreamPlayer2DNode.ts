import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D, type Node2DOptions } from '../../runtime/scene/Node2D';
import { AudioPlaybackController, compilePayloadFilter, type AudioStreamPlayerOptions } from './AudioStreamPlayerNode';

export interface AudioStreamPlayer2DOptions extends Node2DOptions, Omit<AudioStreamPlayerOptions, keyof Node2DOptions> {
  readonly maxDistance?: number;
  readonly panDistance?: number;
}

export class AudioStreamPlayer2DNode extends Node2D {
  readonly playbackFinished = this.createSignal<void>('playback_finished');
  private readonly playback: AudioPlaybackController;

  constructor(private readonly audio2DOptions: AudioStreamPlayer2DOptions) {
    super(audio2DOptions);
    if (!Number.isFinite(audio2DOptions.maxDistance ?? 800) || (audio2DOptions.maxDistance ?? 800) <= 0) throw new Error('Audio maxDistance must be positive and finite');
    if (!Number.isFinite(audio2DOptions.panDistance ?? 400) || (audio2DOptions.panDistance ?? 400) <= 0) throw new Error('Audio panDistance must be positive and finite');
    this.playback = new AudioPlaybackController(this, audio2DOptions, () => this.playbackFinished.emit());
    const accepts = compilePayloadFilter(audio2DOptions.payloadFilter);
    this.registerSignalHandler('play', (payload) => { if (accepts(payload)) this.play(); });
    this.registerSignalHandler('stop', (payload) => { if (accepts(payload)) this.stop(); });
    this.set_process(true);
    // Keep the mix live while menus pause the simulation (volume sliders, UI clicks).
    this.set_process_when_paused(true);
  }

  get playing(): boolean { return this.playback.playing; }
  play(): void { this.playback.play(); }
  stop(): void { this.playback.stop(); }
  override _enter_tree(): void { const { pan, attenuation } = this.spatial(); this.playback.enter(pan, attenuation); }
  override _process(): void { const { pan, attenuation } = this.spatial(); this.playback.synchronize(pan, attenuation); }

  /** Linear distance falloff and stereo pan relative to the main camera centre. */
  private spatial(): { readonly pan: number; readonly attenuation: number } {
    const position = this.get_global_transform().position;
    const camera = this.audio2DOptions.scene.cameras.main;
    const centerX = camera.worldView?.centerX ?? camera.midPoint.x;
    const centerY = camera.worldView?.centerY ?? camera.midPoint.y;
    const distance = Math.hypot(position.x - centerX, position.y - centerY);
    return {
      pan: (position.x - centerX) / (this.audio2DOptions.panDistance ?? 400),
      attenuation: Math.max(0, 1 - distance / (this.audio2DOptions.maxDistance ?? 800)),
    };
  }
  override _exit_tree(): void { this.playback.exit(); }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): AudioStreamPlayer2DNode {
    return new AudioStreamPlayer2DNode({ ...this.audio2DOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible });
  }
}
