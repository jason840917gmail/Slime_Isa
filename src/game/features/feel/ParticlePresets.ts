import type Phaser from 'phaser';

import { resolveWorldDepth } from '../../presentation/WorldDepth';

/** Roadmap 9.3: the moments that throw particles. */
export type ParticleEvent = 'hit-spark' | 'slime-splash' | 'dodge-dust' | 'loot-sparkle' | 'boss-burst';

export interface ParticlePreset {
  /** A texture made by the boot scene (`ProceduralAssetScene`). */
  readonly texture: string;
  readonly count: number;
  /** Draw above the creatures (sparks, sparkles) or among them on the ground (dust, splash). */
  readonly layer: 'over' | 'ground';
  readonly config: Phaser.Types.GameObjects.Particles.ParticleEmitterConfig;
}

export const PARTICLE_PRESETS: Readonly<Record<ParticleEvent, ParticlePreset>> = Object.freeze({
  'hit-spark': {
    texture: 'fx-spark', count: 7, layer: 'over',
    config: { lifespan: 220, speed: { min: 90, max: 220 }, scale: { start: 0.9, end: 0 }, alpha: { start: 1, end: 0 }, blendMode: 'ADD' },
  },
  'slime-splash': {
    texture: 'fx-goo-drop', count: 9, layer: 'ground',
    config: { lifespan: 420, speed: { min: 50, max: 140 }, angle: { min: 200, max: 340 }, gravityY: 420, scale: { start: 0.8, end: 0.3 }, alpha: { start: 1, end: 0 } },
  },
  // A puff of sandy dust at the slime's feet (was tiny goo dots at 40 % alpha, too faint to see).
  'dodge-dust': {
    texture: 'dust-puff', count: 9, layer: 'ground',
    config: { lifespan: 460, speed: { min: 30, max: 95 }, gravityY: -30, scale: { start: 0.9, end: 0.25 }, alpha: { start: 0.8, end: 0 }, rotate: { min: 0, max: 360 } },
  },
  'loot-sparkle': {
    texture: 'fx-sparkle', count: 6, layer: 'over',
    config: { lifespan: 520, speed: { min: 20, max: 60 }, angle: { min: 220, max: 320 }, scale: { start: 0.9, end: 0 }, alpha: { start: 1, end: 0 }, rotate: { min: 0, max: 180 } },
  },
  'boss-burst': {
    texture: 'fx-sparkle', count: 36, layer: 'over',
    config: { lifespan: 900, speed: { min: 120, max: 320 }, scale: { start: 1.6, end: 0 }, alpha: { start: 1, end: 0 }, rotate: { min: 0, max: 360 }, tint: [0xffe89a, 0x86f0c3, 0xffffff] },
  },
});

/** Above every world object: bursts draw over the creature they come from. */
const OVER_DEPTH = 8_999_999_000;

/**
 * Pooled particle presets (roadmap 9.3): one emitter per preset, created when
 * the world scene binds and reused for every burst (Phaser recycles dead
 * particles), so a hit never allocates an emitter.
 */
export class ParticlePresets {
  private emitters = new Map<ParticleEvent, Phaser.GameObjects.Particles.ParticleEmitter>();

  bind(scene: Phaser.Scene): () => void {
    this.clear();
    const created = new Map<ParticleEvent, Phaser.GameObjects.Particles.ParticleEmitter>();
    for (const [event, preset] of Object.entries(PARTICLE_PRESETS) as [ParticleEvent, ParticlePreset][]) {
      if (!scene.textures.exists(preset.texture)) continue;
      const emitter = scene.add.particles(0, 0, preset.texture, { ...preset.config, emitting: false });
      if (preset.layer === 'over') emitter.setDepth(OVER_DEPTH);
      created.set(event, emitter);
    }
    this.emitters = created;
    return () => {
      if (this.emitters !== created) return;
      this.clear();
    };
  }

  play(event: ParticleEvent, x: number, y: number): void {
    const emitter = this.emitters.get(event);
    if (!emitter || !emitter.active) return;
    const preset = PARTICLE_PRESETS[event];
    // Ground bursts sort with the world by where they happen.
    if (preset.layer === 'ground') emitter.setDepth(resolveWorldDepth(y + 2, { stableId: `fx-${event}`, attachmentSlot: -4 }).depth);
    emitter.emitParticleAt(x, y, preset.count);
  }

  private clear(): void {
    for (const emitter of this.emitters.values()) if (emitter.active) emitter.destroy();
    this.emitters = new Map();
  }
}

export const particleFx = new ParticlePresets();
