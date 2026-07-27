import Phaser from 'phaser';

import {
  buildSourceAlphaMask,
  expandRectangle,
  rectanglesIntersect,
  resolveWorldAlphaMaskRuns,
  resolveWorldOcclusionRectangle,
  type SourceAlphaMask,
  type SourceFrameDimensions,
  type SourceOcclusionBounds,
  type WorldRectangle,
} from '../../presentation/WorldOcclusion';
import { resolveWorldDepth } from '../../presentation/WorldDepth';
import type { AnimatedVisual, AnimatedVisualRenderState } from '../visuals/AnimatedVisual';
import type { ObjectOccluderRegistration } from '../objects/ObjectFactory';

const CELL_SIZE = 256;
const ACTOR_CAMERA_MARGIN = 128;
const QUERY_MARGIN = 32;
const ALPHA_THRESHOLD = 8;

export interface OcclusionActorRegistration {
  readonly id: string;
  readonly owner: Phaser.GameObjects.GameObject;
  readonly visual: AnimatedVisual;
  readonly getGroundAnchorY: () => number;
  readonly getDepth: () => number;
  readonly isEligible: () => boolean;
  readonly silhouetteColor: number;
}

interface StaticOccluder {
  readonly id: string;
  readonly owner: Phaser.GameObjects.Image;
  readonly sourceFrame: SourceFrameDimensions;
  readonly bounds: SourceOcclusionBounds;
  readonly rectangle: WorldRectangle;
  readonly maskRuns: readonly WorldRectangle[];
  readonly depth: () => number;
  readonly cells: readonly string[];
  readonly dispose: () => void;
}

interface RevealActor {
  readonly registration: OcclusionActorRegistration;
  readonly silhouette: Phaser.GameObjects.Sprite;
  readonly maskGraphics: Phaser.GameObjects.Graphics;
  readonly mask: Phaser.Display.Masks.GeometryMask;
  hidden: boolean;
  hiddenRatio: number;
  disposed: boolean;
  readonly dispose: () => void;
}

export interface OcclusionDiagnostics {
  readonly registeredOccluders: number;
  readonly registeredActors: number;
  readonly queriedCells: number;
  readonly candidates: number;
  readonly intersections: number;
  readonly lastUpdateMs: number;
  readonly averageUpdateMs: number;
}

export interface OcclusionActorDiagnostics {
  readonly id: string;
  readonly groundAnchorY: number;
  readonly depth: number;
  readonly silhouetteVisible: boolean;
  readonly hiddenRatio: number;
}

function cellCoordinate(value: number): number {
  return Math.floor(value / CELL_SIZE);
}

function cellKey(x: number, y: number): string {
  return `${x},${y}`;
}

function cellsForRectangle(rectangle: WorldRectangle): string[] {
  const minX = cellCoordinate(rectangle.x);
  const maxX = cellCoordinate(rectangle.x + Math.max(0, rectangle.width - 0.001));
  const minY = cellCoordinate(rectangle.y);
  const maxY = cellCoordinate(rectangle.y + Math.max(0, rectangle.height - 0.001));
  const cells: string[] = [];
  for (let y = minY; y <= maxY; y += 1) {
    for (let x = minX; x <= maxX; x += 1) cells.push(cellKey(x, y));
  }
  return cells;
}

function ownerIsActive(owner: Phaser.GameObjects.GameObject): boolean {
  return 'active' in owner ? Boolean(owner.active) : true;
}

function intersectionArea(a: WorldRectangle, b: WorldRectangle): number {
  const width = Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x));
  const height = Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
  return width * height;
}

/**
 * Scene-owned static-occluder grid and reveal-silhouette controller.
 * Static rectangles are indexed once; actor queries are camera- and cell-
 * bounded so a large map never requires a full occluder/actor scan.
 */
export class OcclusionController {
  private readonly grid = new Map<string, Set<StaticOccluder>>();
  private readonly occluders = new Map<string, StaticOccluder>();
  private readonly actors = new Map<string, RevealActor>();
  private readonly alphaMaskCache = new Map<string, SourceAlphaMask>();
  private lastUpdateMs = 0;
  private averageUpdateMs = 0;
  private updateCount = 0;
  private queriedCells = 0;
  private candidates = 0;
  private intersections = 0;
  private destroyed = false;

  constructor(private readonly scene: Phaser.Scene) {
    scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.destroy);
  }

  registerOccluder(registration: ObjectOccluderRegistration): { dispose(): void } {
    if (this.destroyed) return { dispose: () => undefined };
    const previous = this.occluders.get(registration.id);
    if (previous) this.removeOccluder(previous);
    const rectangle = resolveWorldOcclusionRectangle(
      registration.owner,
      registration.sourceFrame,
      registration.bounds,
    );
    const textureKey = registration.owner.texture.key;
    const frameName = registration.owner.frame.name;
    const cacheKey = [
      textureKey,
      String(frameName),
      registration.bounds.offsetX,
      registration.bounds.offsetY,
      registration.bounds.width,
      registration.bounds.height,
    ].join(':');
    const sourceMask = this.alphaMaskCache.get(cacheKey) ?? buildSourceAlphaMask(
      registration.sourceFrame,
      (x, y) => this.scene.textures.getPixelAlpha(x, y, textureKey, frameName),
      registration.bounds,
      ALPHA_THRESHOLD,
    );
    this.alphaMaskCache.set(cacheKey, sourceMask);
    const maskRuns = sourceMask.runs.length > 0
      ? resolveWorldAlphaMaskRuns(registration.owner, registration.sourceFrame, sourceMask)
      : [rectangle];
    const cells = cellsForRectangle(rectangle);
    let disposed = false;
    let occluder: StaticOccluder;
    const dispose = (): void => {
      if (disposed) return;
      disposed = true;
      this.removeOccluder(occluder);
    };
    occluder = {
      id: registration.id,
      owner: registration.owner,
      sourceFrame: registration.sourceFrame,
      bounds: registration.bounds,
      rectangle,
      maskRuns,
      depth: registration.getDepth,
      cells,
      dispose,
    };
    this.occluders.set(occluder.id, occluder);
    for (const cell of cells) {
      const entries = this.grid.get(cell) ?? new Set<StaticOccluder>();
      entries.add(occluder);
      this.grid.set(cell, entries);
    }
    registration.owner.once(Phaser.GameObjects.Events.DESTROY, dispose);
    return { dispose };
  }

  registerActor(registration: OcclusionActorRegistration): { dispose(): void } {
    if (this.destroyed) return { dispose: () => undefined };
    const previous = this.actors.get(registration.id);
    previous?.dispose();
    const state: AnimatedVisualRenderState = registration.visual.getRenderState();
    const silhouette = this.scene.add.sprite(state.x, state.y, state.textureKey, state.frame);
    const maskGraphics = this.scene.add.graphics().setVisible(false);
    const mask = maskGraphics.createGeometryMask();
    silhouette.setMask(mask);
    silhouette
      .setVisible(false)
      .setDepth(resolveWorldDepth(registration.getGroundAnchorY(), {
        band: 'reveal-effects',
        stableId: registration.id,
      }).depth);
    let actor: RevealActor;
    const dispose = (): void => {
      if (actor.disposed) return;
      actor.disposed = true;
      if (this.actors.get(registration.id) === actor) this.actors.delete(registration.id);
      registration.owner.off(Phaser.GameObjects.Events.DESTROY, dispose);
      silhouette.clearMask(true);
      maskGraphics.destroy();
      silhouette.destroy();
    };
    actor = {
      registration,
      silhouette,
      maskGraphics,
      mask,
      hidden: false,
      hiddenRatio: 0,
      disposed: false,
      dispose,
    };
    this.actors.set(registration.id, actor);
    registration.owner.once(Phaser.GameObjects.Events.DESTROY, dispose);
    return { dispose };
  }

  update(): void {
    if (this.destroyed) return;
    const started = typeof performance !== 'undefined' ? performance.now() : Date.now();
    this.queriedCells = 0;
    this.candidates = 0;
    this.intersections = 0;
    const cameraView = this.scene.cameras.main.worldView as WorldRectangle;
    const cameraBounds = expandRectangle(cameraView, ACTOR_CAMERA_MARGIN);

    for (const actor of this.actors.values()) {
      const registration = actor.registration;
      if (actor.disposed || !ownerIsActive(registration.owner) || !registration.isEligible()) {
        actor.silhouette.setVisible(false);
        actor.hidden = false;
        actor.hiddenRatio = 0;
        actor.maskGraphics.clear();
        continue;
      }

      const actorBounds = registration.visual.getBounds() as WorldRectangle;
      if (!rectanglesIntersect(actorBounds, cameraBounds)) {
        actor.silhouette.setVisible(false);
        actor.hidden = false;
        actor.hiddenRatio = 0;
        actor.maskGraphics.clear();
        continue;
      }

      const queryBounds = expandRectangle(actorBounds, QUERY_MARGIN);
      const candidates = new Set<StaticOccluder>();
      for (const cell of cellsForRectangle(queryBounds)) {
        this.queriedCells += 1;
        for (const candidate of this.grid.get(cell) ?? []) candidates.add(candidate);
      }
      this.candidates += candidates.size;

      const actorDepth = registration.getDepth();
      let hidden = false;
      let hiddenArea = 0;
      actor.maskGraphics.clear();
      actor.maskGraphics.fillStyle(0xffffff, 1);
      for (const candidate of candidates) {
        if (!ownerIsActive(candidate.owner) || candidate.depth() <= actorDepth) continue;
        if (!rectanglesIntersect(actorBounds, candidate.rectangle)) continue;
        let candidateIntersects = false;
        for (const maskRun of candidate.maskRuns) {
          if (!rectanglesIntersect(actorBounds, maskRun)) continue;
          candidateIntersects = true;
          hiddenArea += intersectionArea(actorBounds, maskRun);
          actor.maskGraphics.fillRect(maskRun.x, maskRun.y, maskRun.width, maskRun.height);
        }
        if (candidateIntersects) {
          this.intersections += 1;
          hidden = true;
        }
      }

      actor.hidden = hidden;
      const actorArea = Math.max(1, actorBounds.width * actorBounds.height);
      actor.hiddenRatio = Math.min(1, hiddenArea / actorArea);
      if (!hidden) {
        actor.silhouette.setVisible(false);
        continue;
      }

      registration.visual.mirrorTo(actor.silhouette, 0.46 + actor.hiddenRatio * 0.42);
      actor.silhouette
        .setTintFill(registration.silhouetteColor)
        .setDepth(resolveWorldDepth(registration.getGroundAnchorY(), {
          band: 'reveal-effects',
          stableId: registration.id,
        }).depth)
        .setVisible(true);
    }

    const elapsed = (typeof performance !== 'undefined' ? performance.now() : Date.now()) - started;
    this.lastUpdateMs = elapsed;
    this.updateCount += 1;
    this.averageUpdateMs += (elapsed - this.averageUpdateMs) / this.updateCount;
  }

  get diagnostics(): OcclusionDiagnostics {
    return {
      registeredOccluders: this.occluders.size,
      registeredActors: this.actors.size,
      queriedCells: this.queriedCells,
      candidates: this.candidates,
      intersections: this.intersections,
      lastUpdateMs: this.lastUpdateMs,
      averageUpdateMs: this.averageUpdateMs,
    };
  }

  get actorDiagnostics(): readonly OcclusionActorDiagnostics[] {
    return [...this.actors.values()].map((actor) => ({
      id: actor.registration.id,
      groundAnchorY: actor.registration.getGroundAnchorY(),
      depth: actor.registration.getDepth(),
      silhouetteVisible: actor.silhouette.visible,
      hiddenRatio: actor.hiddenRatio,
    }));
  }

  get occluderIds(): readonly string[] {
    return [...this.occluders.keys()];
  }

  destroy = (): void => {
    if (this.destroyed) return;
    this.destroyed = true;
    this.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.destroy);
    for (const actor of this.actors.values()) actor.dispose();
    this.actors.clear();
    for (const occluder of [...this.occluders.values()]) occluder.dispose();
    this.grid.clear();
    this.alphaMaskCache.clear();
  };

  private removeOccluder(occluder: StaticOccluder): void {
    if (this.occluders.get(occluder.id) !== occluder) return;
    this.occluders.delete(occluder.id);
    occluder.owner.off(Phaser.GameObjects.Events.DESTROY, occluder.dispose);
    for (const cell of occluder.cells) {
      const entries = this.grid.get(cell);
      entries?.delete(occluder);
      if (entries?.size === 0) this.grid.delete(cell);
    }
  }
}
