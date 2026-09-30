import type Phaser from 'phaser';

import type { ResourceId, RuntimeNodeId } from '../../content/scenes/identifiers';
import type { SceneResourceDocument } from '../../content/scenes/types';
import { contactPointAtTargetEdge } from '../../combat/ContactPoint';
import type { Node } from '../../runtime/scene/Node';
import { ContactRouter, type ContactParticipant } from '../../runtime/scene/physics/ContactRouter';
import { blockingPairAccepts, type BlockingContact, type BlockingMembership } from '../../runtime/scene/physics/PhysicsContact';
import type { SceneHostBackend } from './PhaserSceneTreeHost';
import { PresentationSync, type PresentationParticipant } from '../phaser-nodes/PresentationSync';
import { prepareArcadeBodiesForStep, type ArcadeStepBody } from './ArcadeStepBookkeeping';
import { segmentIntersectsRect } from '../../shared/segmentIntersectsRect';

interface StaticTreeBody {
  readonly enable: boolean;
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
  readonly gameObject?: Phaser.GameObjects.GameObject;
}

export type PhaserHostCallbackPhase =
  | 'physics-animation'
  | 'physics-sync'
  | 'physics-readback'
  | 'contacts'
  | 'attack-resolution'
  | 'post-physics'
  | 'render-animation'
  | 'clear-input';

const manualOwners = new WeakSet<object>();

export interface PhaserBlockingParticipant {
  readonly runtimeId: RuntimeNodeId;
  readonly node: Node;
  readonly physicsObject: Phaser.GameObjects.GameObject;
  readonly isStaticBody: boolean;
  readonly collisionLayer: number;
  readonly collisionMask: number;
  readonly blockingActive: boolean;
  beginBlockingStep(): void;
  recordBlockingContact(contact: BlockingContact): void;
}

interface DestroyableCollider { destroy(): void }

function membership(participant: PhaserBlockingParticipant): BlockingMembership {
  return { collisionLayer: participant.collisionLayer, collisionMask: participant.collisionMask, isStatic: participant.isStaticBody };
}

export class PhaserNodeContext implements SceneHostBackend {
  private readonly presentation = new PresentationSync();
  readonly contactRouter: ContactRouter;
  private readonly callbacks = new Map<PhaserHostCallbackPhase, Set<(deltaSeconds: number) => void>>();
  private readonly blockingParticipants = new Set<PhaserBlockingParticipant>();
  private readonly blockingColliders = new Map<string, DestroyableCollider>();
  private readonly staticBlockingParticipants = new WeakMap<Phaser.GameObjects.GameObject, PhaserBlockingParticipant>();
  private staticBlockingGroup?: Phaser.Physics.Arcade.StaticGroup;
  private staticBlockingCount = 0;
  private readonly baseResources: ReadonlyMap<ResourceId, SceneResourceDocument>;
  private readonly leasedResources = new Map<ResourceId, { readonly resource: SceneResourceDocument; leases: number }>();
  private ownsManualStepping = false;
  private stopped = false;
  private physicsSteps = 0;

  constructor(
    readonly scene: Phaser.Scene,
    resources: ReadonlyMap<ResourceId, SceneResourceDocument> = new Map(),
    private readonly resolveAssetKey: (assetId: string) => string = (assetId) => assetId,
  ) {
    this.baseResources = new Map(resources);
    this.contactRouter = new ContactRouter();
  }

  assetKey(assetId: string): string {
    const key = this.resolveAssetKey(assetId);
    if (!key) throw new Error(`Scene asset '${assetId}' resolved to an empty Phaser key`);
    return key;
  }

  get managedPresentationCount(): number { return this.presentation.size; }
  get physicsStepCount(): number { return this.physicsSteps; }
  get managedContactParticipantCount(): number { return this.contactRouter.participantCount; }
  get managedBlockingColliderCount(): number { return this.blockingColliders.size; }

  /**
   * Whether the straight line between two world points crosses a static
   * blocking body on one of `layerMask`'s collision layers (for enemy sight:
   * walls, houses, trees and rocks on the world layer; water stays
   * see-through). Bodies smaller than `minSize` on both sides (posts,
   * lanterns) never block.
   */
  sightBlocked(from: Readonly<{ x: number; y: number }>, to: Readonly<{ x: number; y: number }>, layerMask: number, minSize = 20): boolean {
    const tree = (this.scene.physics?.world as unknown as { staticTree?: { search(bounds: { minX: number; minY: number; maxX: number; maxY: number }): readonly StaticTreeBody[] } } | undefined)?.staticTree;
    if (!tree) return false;
    const bounds = { minX: Math.min(from.x, to.x), minY: Math.min(from.y, to.y), maxX: Math.max(from.x, to.x), maxY: Math.max(from.y, to.y) };
    for (const body of tree.search(bounds)) {
      if (!body.enable || (body.width < minSize && body.height < minSize)) continue;
      const participant = body.gameObject ? this.staticBlockingParticipants.get(body.gameObject) : undefined;
      if (!participant || (participant.collisionLayer & layerMask) === 0) continue;
      if (segmentIntersectsRect(from, to, body.x, body.y, body.width, body.height)) return true;
    }
    return false;
  }

  resource(resourceId: ResourceId): SceneResourceDocument {
    const resource = this.leasedResources.get(resourceId)?.resource ?? this.baseResources.get(resourceId);
    if (!resource) throw new Error(`Scene resource '${resourceId}' is not available in this Phaser context`);
    return resource;
  }

  acquireResources(resources: readonly SceneResourceDocument[]): () => void {
    this.assertRunning();
    const acquired: ResourceId[] = [];
    try {
      for (const resource of resources) {
        const base = this.baseResources.get(resource.resourceId);
        if (base) {
          this.assertSameResource(resource.resourceId, base, resource);
          continue;
        }
        const leased = this.leasedResources.get(resource.resourceId);
        if (leased) {
          this.assertSameResource(resource.resourceId, leased.resource, resource);
          leased.leases += 1;
        } else {
          this.leasedResources.set(resource.resourceId, { resource, leases: 1 });
        }
        acquired.push(resource.resourceId);
      }
    } catch (error) {
      this.releaseResources(acquired);
      throw error;
    }
    let active = true;
    return () => {
      if (!active) return;
      active = false;
      this.releaseResources(acquired);
    };
  }

  registerPresentation(participant: PresentationParticipant): () => void {
    return this.presentation.register(participant);
  }

  registerCallback(phase: PhaserHostCallbackPhase, callback: (deltaSeconds: number) => void): () => void {
    const callbacks = this.callbacks.get(phase) ?? new Set();
    callbacks.add(callback);
    this.callbacks.set(phase, callbacks);
    let active = true;
    return () => { if (!active) return; active = false; callbacks.delete(callback); if (callbacks.size === 0) this.callbacks.delete(phase); };
  }

  registerContactParticipant(participant: ContactParticipant): () => void {
    this.assertRunning();
    return this.contactRouter.register(participant);
  }

  registerBlockingParticipant(participant: PhaserBlockingParticipant): () => void {
    this.assertRunning();
    if (this.blockingParticipants.has(participant)) throw new Error(`Blocking participant '${participant.runtimeId}' is already registered`);
    const staticGroup = this.ensureStaticBlockingGroup();
    if (staticGroup && participant.isStaticBody) {
      this.staticBlockingParticipants.set(participant.physicsObject, participant);
      staticGroup.add(participant.physicsObject);
      this.staticBlockingCount += 1;
      if (this.staticBlockingCount === 1) {
        for (const other of this.blockingParticipants) if (!other.isStaticBody) this.createStaticGroupCollider(other, staticGroup);
      }
    } else {
      for (const other of this.blockingParticipants) {
        if (staticGroup && other.isStaticBody) continue;
        this.synchronizePairCollider(participant, other);
      }
      if (staticGroup && this.staticBlockingCount > 0) this.createStaticGroupCollider(participant, staticGroup);
    }
    this.blockingParticipants.add(participant);
    let active = true;
    return () => {
      if (!active) return;
      active = false;
      this.blockingParticipants.delete(participant);
      if (staticGroup && participant.isStaticBody) {
        staticGroup.remove(participant.physicsObject, false, false);
        this.staticBlockingParticipants.delete(participant.physicsObject);
        this.staticBlockingCount -= 1;
        if (this.staticBlockingCount === 0) {
          for (const [key, collider] of this.blockingColliders) {
            if (!key.endsWith('|static-group')) continue;
            collider.destroy();
            this.blockingColliders.delete(key);
          }
        }
      }
      for (const [key, collider] of [...this.blockingColliders]) {
        if (!key.split('|').includes(participant.runtimeId)) continue;
        collider.destroy();
        this.blockingColliders.delete(key);
      }
    };
  }

  /**
   * Re-evaluates which dynamic pairs can block each other after a
   * participant's collision layer or mask changed. Pair colliders exist only
   * for pairs the blocking rule can accept, so bodies whose layers never
   * interact (NPC vs NPC, enemy vs enemy, projectiles vs characters) cost
   * nothing per step.
   */
  refreshBlockingParticipant(participant: PhaserBlockingParticipant): void {
    if (!this.blockingParticipants.has(participant)) return;
    const grouped = this.staticBlockingGroup !== undefined;
    if (grouped && participant.isStaticBody) return;
    for (const other of this.blockingParticipants) {
      if (other === participant || (grouped && other.isStaticBody)) continue;
      this.synchronizePairCollider(participant, other);
    }
  }

  startManualStepping(): void {
    this.assertRunning();
    const physics = this.scene.physics as unknown as object;
    if (manualOwners.has(physics)) throw new Error('Arcade Physics already has a managed manual-step owner');
    manualOwners.add(physics);
    this.scene.physics.disableUpdate();
    this.ownsManualStepping = true;
  }

  advancePhysicsAnimations(deltaSeconds: number): void { this.run('physics-animation', deltaSeconds); }
  synchronizePhysicsToBackend(): void {
    for (const participant of this.blockingParticipants) participant.beginBlockingStep();
    this.run('physics-sync', 0);
  }
  /**
   * Owns the whole Arcade step contract. `World.step` does not run
   * `Body.preUpdate` (only `World.update` does, and that path is disabled for
   * manual stepping), so the per-step flag reset and prev/prevFrame refresh
   * happen here before the step. `updateFromGameObject` is deliberately
   * skipped: the backend object sits at the node anchor, not the body centre.
   */
  stepPhysics(deltaSeconds: number): void {
    const world = this.scene.physics.world as unknown as { readonly bodies?: { readonly entries?: readonly ArcadeStepBody[] } };
    prepareArcadeBodiesForStep(world.bodies?.entries ?? []);
    this.scene.physics.world.step(deltaSeconds);
    this.physicsSteps += 1;
  }
  readAuthoritativePhysicsState(): void { this.run('physics-readback', 0); }
  collectManagedContacts(): void { this.run('contacts', 0); this.contactRouter.reconcile(); }
  resolveManagedAttacks(deltaSeconds: number): void { this.run('attack-resolution', deltaSeconds); }
  runPostPhysics(deltaSeconds: number): void { this.run('post-physics', deltaSeconds); }
  advanceRenderAnimations(deltaSeconds: number): void { this.run('render-animation', deltaSeconds); }
  synchronizePresentation(alpha: number): void { this.presentation.synchronize(alpha); }
  clearHeldInputTransitions(): void { this.run('clear-input', 0); }

  shutdown(): void {
    if (this.stopped) return;
    this.stopped = true;
    this.presentation.clear();
    this.callbacks.clear();
    for (const collider of this.blockingColliders.values()) collider.destroy();
    this.blockingColliders.clear();
    this.staticBlockingGroup?.destroy(false);
    this.staticBlockingGroup = undefined;
    this.staticBlockingCount = 0;
    this.blockingParticipants.clear();
    this.contactRouter.clear();
    this.leasedResources.clear();
    if (this.ownsManualStepping) {
      const physics = this.scene.physics as typeof this.scene.physics & { readonly systems?: unknown };
      if (physics.systems) physics.enableUpdate();
      manualOwners.delete(physics as unknown as object);
      this.ownsManualStepping = false;
    }
  }

  private run(phase: PhaserHostCallbackPhase, deltaSeconds: number): void {
    for (const callback of [...(this.callbacks.get(phase) ?? [])]) callback(deltaSeconds);
  }

  private synchronizePairCollider(first: PhaserBlockingParticipant, second: PhaserBlockingParticipant): void {
    const ids = [first.runtimeId, second.runtimeId].sort();
    const key = `${ids[0]}|${ids[1]}`;
    const wanted = blockingPairAccepts(membership(first), membership(second));
    const existing = this.blockingColliders.get(key);
    if (wanted && !existing) this.createBlockingCollider(key, first, second);
    else if (!wanted && existing) { existing.destroy(); this.blockingColliders.delete(key); }
  }

  private createBlockingCollider(key: string, first: PhaserBlockingParticipant, second: PhaserBlockingParticipant): void {
    const process = (): boolean => first.blockingActive && second.blockingActive
      && blockingPairAccepts(membership(first), membership(second));
    const onCollide = (): void => {
      first.recordBlockingContact(this.blockingContact(first, second));
      second.recordBlockingContact(this.blockingContact(second, first));
    };
    const collider = this.scene.physics.add.collider(first.physicsObject, second.physicsObject, onCollide, process) as unknown as DestroyableCollider;
    this.blockingColliders.set(key, collider);
  }

  private ensureStaticBlockingGroup(): Phaser.Physics.Arcade.StaticGroup | undefined {
    if (!this.scene.physics.add.staticGroup) return undefined;
    return this.staticBlockingGroup ??= this.scene.physics.add.staticGroup();
  }

  private createStaticGroupCollider(participant: PhaserBlockingParticipant, group: Phaser.Physics.Arcade.StaticGroup): void {
    const staticFor = (first: unknown, second: unknown): PhaserBlockingParticipant | undefined =>
      this.staticBlockingParticipants.get(first as Phaser.GameObjects.GameObject)
      ?? this.staticBlockingParticipants.get(second as Phaser.GameObjects.GameObject);
    const process = (first: unknown, second: unknown): boolean => {
      const fixed = staticFor(first, second);
      return fixed !== undefined && participant.blockingActive && fixed.blockingActive
        && blockingPairAccepts(membership(participant), membership(fixed));
    };
    const onCollide = (first: unknown, second: unknown): void => {
      const fixed = staticFor(first, second);
      if (!fixed) return;
      participant.recordBlockingContact(this.blockingContact(participant, fixed));
      fixed.recordBlockingContact(this.blockingContact(fixed, participant));
    };
    const collider = this.scene.physics.add.collider(participant.physicsObject, group, onCollide, process) as unknown as DestroyableCollider;
    this.blockingColliders.set(`${participant.runtimeId}|static-group`, collider);
  }

  private blockingContact(owner: PhaserBlockingParticipant, other: PhaserBlockingParticipant): BlockingContact {
    const ownerBody = owner.physicsObject.body as Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody | null;
    const otherBody = other.physicsObject.body as Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody | null;
    const touching = ownerBody?.touching;
    const normal = touching?.left ? { x: 1, y: 0 } : touching?.right ? { x: -1, y: 0 }
      : touching?.up ? { x: 0, y: 1 } : touching?.down ? { x: 0, y: -1 } : { x: 0, y: 0 };
    return {
      colliderId: other.runtimeId,
      collider: other.node,
      normal,
      ...(otherBody && (normal.x !== 0 || normal.y !== 0) ? {
        position: contactPointAtTargetEdge(
          { x: otherBody.x, y: otherBody.y, width: otherBody.width, height: otherBody.height },
          { x: -normal.x, y: -normal.y },
        ),
      } : {}),
    };
  }

  private assertRunning(): void { if (this.stopped) throw new Error('Phaser node context has shut down'); }

  private assertSameResource(resourceId: ResourceId, current: SceneResourceDocument, candidate: SceneResourceDocument): void {
    if (JSON.stringify(current) !== JSON.stringify(candidate)) {
      throw new Error(`Scene resource '${resourceId}' conflicts with an active Phaser resource`);
    }
  }

  private releaseResources(resourceIds: readonly ResourceId[]): void {
    for (const resourceId of [...resourceIds].reverse()) {
      const leased = this.leasedResources.get(resourceId);
      if (!leased) continue;
      leased.leases -= 1;
      if (leased.leases === 0) this.leasedResources.delete(resourceId);
    }
  }
}
