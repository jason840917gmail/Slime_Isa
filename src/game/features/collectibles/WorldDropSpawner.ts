import type Phaser from 'phaser';

import {
  getObjectArchetype,
  hasObjectVisual,
  isObjectArchetypeId,
  type ObjectArchetypeId,
} from '../../content/objects/ObjectCatalog';
import type { DepthMode } from '../../presentation/WorldDepth';
import {
  resolveWorldDropTrajectory,
  WORLD_DROP_FLIGHT_MS,
  WORLD_DROP_REBOUND_HEIGHT,
  WORLD_DROP_REBOUND_MS,
  WORLD_DROP_SETTLE_MS,
  WORLD_DROP_STAGGER_MS,
  type WorldDropPoint,
} from './WorldDropMotion';

export interface WorldDropDefinition {
  readonly objectId: ObjectArchetypeId;
  readonly visualId: string;
  readonly instanceId: string;
  readonly initialState?: Readonly<Record<string, unknown>>;
}

export type WorldDropRequest =
  | {
      readonly mode: 'launch';
      readonly source: WorldDropPoint;
      readonly destination: WorldDropPoint;
      /** Zero-based launch order used for deterministic staggering. */
      readonly launchIndex: number;
      readonly drop: WorldDropDefinition;
    }
  | {
      readonly mode: 'settled';
      readonly destination: WorldDropPoint;
      readonly drop: WorldDropDefinition;
    };

export interface WorldDropCreateOptions {
  readonly x: number;
  readonly y: number;
  readonly visualId: string;
  readonly sortId: string;
  readonly initialState?: Readonly<Record<string, unknown>>;
}

export interface WorldDropRegistration {
  readonly image: Phaser.GameObjects.Image;
  readonly objectId: ObjectArchetypeId;
  readonly instanceId: string;
  readonly initialState?: Readonly<Record<string, unknown>>;
}

export interface WorldDropSpawnerContext {
  readonly scene: Phaser.Scene;
  readonly createObject: (
    objectId: ObjectArchetypeId,
    options: WorldDropCreateOptions,
  ) => Phaser.GameObjects.Image;
  readonly setObjectAnchor: (image: Phaser.GameObjects.Image, x: number, y: number) => void;
  readonly setObjectDepthMode: (
    image: Phaser.GameObjects.Image,
    mode: DepthMode,
    explicitDepth?: number,
  ) => void;
  readonly registerCollectible: (registration: WorldDropRegistration) => void;
}

interface ActiveWorldDrop {
  readonly image: Phaser.GameObjects.Image;
  readonly destination: WorldDropPoint;
  readonly registration: WorldDropRegistration;
  readonly baseScaleX: number;
  readonly baseScaleY: number;
  readonly tweens: Set<Phaser.Tweens.Tween>;
  completed: boolean;
}

type PickupBody = Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody;

/** Creates physical world drops and activates collection only after presentation settles. */
export class WorldDropSpawner {
  private readonly activeDrops = new Set<ActiveWorldDrop>();
  private disposed = false;

  constructor(private readonly ctx: WorldDropSpawnerContext) {}

  spawn(request: WorldDropRequest): Phaser.GameObjects.Image {
    if (this.disposed) throw new Error('WorldDropSpawner cannot spawn after destroy().');
    this.validateRequest(request);

    const image = this.ctx.createObject(request.drop.objectId, {
      x: request.destination.x,
      y: request.destination.y,
      visualId: request.drop.visualId,
      sortId: request.drop.instanceId,
      ...(request.drop.initialState ? { initialState: request.drop.initialState } : {}),
    });
    const body = this.pickupBody(image);
    if (!body) {
      image.destroy();
      throw new Error(`World drop '${request.drop.instanceId}' was created without a pickup body.`);
    }

    const registration: WorldDropRegistration = {
      image,
      objectId: request.drop.objectId,
      instanceId: request.drop.instanceId,
      ...(request.drop.initialState ? { initialState: request.drop.initialState } : {}),
    };

    if (request.mode === 'settled') {
      body.enable = true;
      this.ctx.registerCollectible(registration);
      return image;
    }

    body.enable = false;
    const active: ActiveWorldDrop = {
      image,
      destination: request.destination,
      registration,
      baseScaleX: image.scaleX,
      baseScaleY: image.scaleY,
      tweens: new Set(),
      completed: false,
    };
    this.activeDrops.add(active);

    try {
      const landingDepth = image.depth;
      this.ctx.setObjectDepthMode(image, 'explicit', landingDepth);
      this.ctx.setObjectAnchor(image, request.source.x, request.source.y);
      this.startFlight(active, request.source, request.launchIndex * WORLD_DROP_STAGGER_MS);
    } catch (error) {
      this.fallbackToSettled(active, error);
    }
    return image;
  }

  destroy(): void {
    if (this.disposed) return;
    this.disposed = true;
    for (const active of this.activeDrops) {
      active.completed = true;
      for (const tween of active.tweens) tween.remove();
      active.tweens.clear();
      if (active.image.active) active.image.destroy();
    }
    this.activeDrops.clear();
  }

  private validateRequest(request: WorldDropRequest): void {
    if (request.mode !== 'launch' && request.mode !== 'settled') {
      throw new Error('World drop mode must be launch or settled.');
    }
    this.validatePoint(request.destination, 'destination');
    if (request.mode === 'launch') {
      this.validatePoint(request.source, 'source');
      if (!Number.isInteger(request.launchIndex) || request.launchIndex < 0) {
        throw new Error('World drop launchIndex must be a zero-based non-negative integer.');
      }
    }
    if (!request.drop.instanceId.trim()) throw new Error('World drop instanceId must not be empty.');
    const objectId = request.drop.objectId as string;
    if (!isObjectArchetypeId(objectId)) throw new Error(`Unknown world drop object '${objectId}'.`);
    const archetype = getObjectArchetype(objectId);
    if (!archetype.collectible || archetype.behavior !== 'collectible.walk-over') {
      throw new Error(`World drop object '${objectId}' must be a walk-over collectible.`);
    }
    if (!hasObjectVisual(objectId, request.drop.visualId)) {
      throw new Error(`World drop object '${objectId}' has no visual '${request.drop.visualId}'.`);
    }
  }

  private validatePoint(point: WorldDropPoint, label: string): void {
    if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) {
      throw new Error(`World drop ${label} must contain finite coordinates.`);
    }
  }

  private startFlight(active: ActiveWorldDrop, source: WorldDropPoint, delay: number): void {
    const state = { progress: 0 };
    this.addTween(active, {
      targets: state,
      progress: 1,
      duration: WORLD_DROP_FLIGHT_MS,
      delay,
      ease: 'Linear',
      onUpdate: () => {
        if (!this.canContinue(active)) return;
        const point = resolveWorldDropTrajectory(source, active.destination, state.progress);
        this.ctx.setObjectAnchor(active.image, point.x, point.y);
      },
    }, () => {
      this.ctx.setObjectAnchor(active.image, active.destination.x, active.destination.y);
      active.image.setScale(active.baseScaleX * 1.12, active.baseScaleY * 0.82);
      this.startRebound(active);
    });
  }

  private startRebound(active: ActiveWorldDrop): void {
    const state = { progress: 0 };
    this.addTween(active, {
      targets: state,
      progress: 1,
      duration: WORLD_DROP_REBOUND_MS,
      ease: 'Sine.Out',
      onUpdate: () => {
        if (!this.canContinue(active)) return;
        const progress = state.progress;
        this.ctx.setObjectAnchor(
          active.image,
          active.destination.x,
          active.destination.y - WORLD_DROP_REBOUND_HEIGHT * progress,
        );
        active.image.setScale(
          this.lerp(active.baseScaleX * 1.12, active.baseScaleX * 0.96, progress),
          this.lerp(active.baseScaleY * 0.82, active.baseScaleY * 1.04, progress),
        );
      },
    }, () => this.startSettle(active));
  }

  private startSettle(active: ActiveWorldDrop): void {
    const state = { progress: 0 };
    this.addTween(active, {
      targets: state,
      progress: 1,
      duration: WORLD_DROP_SETTLE_MS,
      ease: 'Sine.In',
      onUpdate: () => {
        if (!this.canContinue(active)) return;
        const progress = state.progress;
        this.ctx.setObjectAnchor(
          active.image,
          active.destination.x,
          active.destination.y - WORLD_DROP_REBOUND_HEIGHT * (1 - progress),
        );
        active.image.setScale(
          this.lerp(active.baseScaleX * 0.96, active.baseScaleX, progress),
          this.lerp(active.baseScaleY * 1.04, active.baseScaleY, progress),
        );
      },
    }, () => this.complete(active));
  }

  private addTween(
    active: ActiveWorldDrop,
    config: Phaser.Types.Tweens.TweenBuilderConfig,
    onComplete: () => void,
  ): void {
    let tween: Phaser.Tweens.Tween | undefined;
    try {
      tween = this.ctx.scene.tweens.add({
        ...config,
        onComplete: () => {
          if (tween) active.tweens.delete(tween);
          if (!this.canContinue(active)) return;
          onComplete();
        },
      });
      if (this.canContinue(active)) active.tweens.add(tween);
      else tween.remove();
    } catch (error) {
      this.fallbackToSettled(active, error);
    }
  }

  private fallbackToSettled(active: ActiveWorldDrop, error: unknown): void {
    if (!this.canContinue(active)) return;
    for (const tween of active.tweens) tween.remove();
    active.tweens.clear();
    if (import.meta.env.DEV) console.warn('World drop motion fell back to settled presentation.', error);
    this.complete(active);
  }

  private complete(active: ActiveWorldDrop): void {
    if (!this.canContinue(active)) return;
    active.completed = true;
    for (const tween of active.tweens) tween.remove();
    active.tweens.clear();
    this.ctx.setObjectAnchor(active.image, active.destination.x, active.destination.y);
    active.image.setScale(active.baseScaleX, active.baseScaleY);
    this.ctx.setObjectDepthMode(active.image, 'world-sorted');
    const body = this.pickupBody(active.image);
    if (!body) {
      this.activeDrops.delete(active);
      active.image.destroy();
      throw new Error(`World drop '${active.registration.instanceId}' lost its pickup body before landing.`);
    }
    body.enable = true;
    this.activeDrops.delete(active);
    this.ctx.registerCollectible(active.registration);
  }

  private canContinue(active: ActiveWorldDrop): boolean {
    return !this.disposed && !active.completed && active.image.active;
  }

  private pickupBody(image: Phaser.GameObjects.Image): PickupBody | null {
    const body = (image as Phaser.Physics.Arcade.Image).body;
    return body && 'enable' in body ? body : null;
  }

  private lerp(from: number, to: number, progress: number): number {
    return from + (to - from) * progress;
  }
}
