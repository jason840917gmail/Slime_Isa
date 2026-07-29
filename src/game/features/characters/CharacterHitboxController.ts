import type { CharacterDocument } from '../../content/characters/types';
import {
  characterHitboxesIntersect,
  geometryToRectangle,
  resolveCharacterHitboxGeometry,
  type CharacterHitboxRectangle,
  type CharacterHitboxGeometry,
} from './characterHitboxGeometry';

export interface CharacterHitboxTarget {
  getBounds(): CharacterHitboxRectangle;
  getCollisionGeometry?: () => CharacterHitboxGeometry;
}

export interface CharacterHitboxTargetCollection {
  getChildren(): readonly CharacterHitboxTarget[];
}

export interface CharacterHitboxControllerOptions {
  readonly anchor: { readonly x: number; readonly y: number };
  readonly facingX: () => 1 | -1;
  readonly targets: CharacterHitboxTargetCollection | readonly CharacterHitboxTarget[];
  readonly onHit: (hitboxId: string, target: CharacterHitboxTarget, activationId: string) => void;
}

export interface ResolvedCharacterHitbox {
  readonly hitboxId: string;
  readonly activationId: string;
  readonly geometry: CharacterHitboxGeometry;
  /** Kept for debug consumers that still draw rectangular bounds. */
  readonly rectangle: CharacterHitboxRectangle;
}

/**
 * Opt-in hitbox primitive for authored character tracks. Production combat
 * owners remain responsible for damage and target selection; this controller
 * only resolves geometry and hit-once bookkeeping for one activation.
 */
export class CharacterHitboxController {
  private readonly active = new Map<string, ResolvedCharacterHitbox>();
  private readonly hitTargets = new Map<string, Set<CharacterHitboxTarget>>();

  constructor(
    private readonly character: CharacterDocument,
    private readonly options: CharacterHitboxControllerOptions,
  ) {}

  activate(hitboxId: string, activationId: string): void {
    const hitbox = this.character.hitboxes[hitboxId];
    if (!hitbox) throw new Error(`Unknown hitbox '${hitboxId}'`);
    const geometry = this.resolveGeometry(hitbox);
    this.active.set(hitboxId, {
      hitboxId,
      activationId,
      geometry,
      rectangle: geometryToRectangle(geometry),
    });
    this.hitTargets.set(activationId, new Set());
  }

  deactivate(hitboxId: string): void {
    const active = this.active.get(hitboxId);
    if (!active) return;
    this.active.delete(hitboxId);
    this.hitTargets.delete(active.activationId);
  }

  deactivateAll(): void {
    this.active.clear();
    this.hitTargets.clear();
  }

  update(): void {
    const targets = 'getChildren' in this.options.targets
      ? this.options.targets.getChildren()
      : this.options.targets;
    for (const active of this.active.values()) {
      const alreadyHit = this.hitTargets.get(active.activationId);
      if (!alreadyHit) continue;
      for (const candidate of targets) {
        const target = candidate;
        if (alreadyHit.has(target)) continue;
        if (!characterHitboxesIntersect(active.geometry, target.getCollisionGeometry?.() ?? target.getBounds())) continue;
        alreadyHit.add(target);
        this.options.onHit(active.hitboxId, target, active.activationId);
      }
    }
  }

  getResolvedHitboxes(): readonly ResolvedCharacterHitbox[] {
    return [...this.active.values()].map((entry) => ({
      ...entry,
      geometry: { ...entry.geometry },
      rectangle: { ...entry.rectangle },
    }));
  }

  destroy(): void { this.deactivateAll(); }

  private resolveGeometry(hitbox: CharacterDocument['hitboxes'][string]): CharacterHitboxGeometry {
    return resolveCharacterHitboxGeometry(hitbox, this.options.anchor, this.options.facingX());
  }
}
