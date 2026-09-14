import type Phaser from 'phaser';

import type { ResourceId, RuntimeNodeId } from '../../content/scenes/identifiers';
import type { SceneResourceDocument } from '../../content/scenes/types';
import { contactPointAtTargetEdge } from '../../combat/ContactPoint';
import type { Node } from '../../runtime/scene/Node';
import { ContactRouter, type ContactParticipant } from '../../runtime/scene/physics/ContactRouter';
import { collisionMembershipAccepts, type BlockingContact } from '../../runtime/scene/physics/PhysicsContact';
import type { SensorBounds } from '../../runtime/scene/physics/SensorGeometry';
import type { SceneHostBackend } from './PhaserSceneTreeHost';
import { PresentationSync, type PresentationParticipant } from '../phaser-nodes/PresentationSync';

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

export class PhaserNodeContext implements SceneHostBackend {
  private readonly presentation = new PresentationSync();
  readonly contactRouter: ContactRouter;
  private readonly callbacks = new Map<PhaserHostCallbackPhase, Set<(deltaSeconds: number) => void>>();
  private readonly contactParticipants = new Set<ContactParticipant>();
  private readonly contactBodies = new WeakMap<object, ContactParticipant>();
  private readonly blockingParticipants = new Set<PhaserBlockingParticipant>();
  private readonly blockingColliders = new Map<string, DestroyableCollider>();
  private ownsManualStepping = false;
  private stopped = false;
  private physicsSteps = 0;

  constructor(
    readonly scene: Phaser.Scene,
    private readonly resources: ReadonlyMap<ResourceId, SceneResourceDocument> = new Map(),
  ) {
    this.contactRouter = new ContactRouter((observer, bounds) => this.contactCandidates(observer, bounds));
  }

  get managedPresentationCount(): number { return this.presentation.size; }
  get physicsStepCount(): number { return this.physicsSteps; }
  get managedContactParticipantCount(): number { return this.contactRouter.participantCount; }
  get managedBlockingColliderCount(): number { return this.blockingColliders.size; }

  resource(resourceId: ResourceId): SceneResourceDocument {
    const resource = this.resources.get(resourceId);
    if (!resource) throw new Error(`Scene resource '${resourceId}' is not available in this Phaser context`);
    return resource;
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

  registerContactParticipant(participant: ContactParticipant, backendBody?: object): () => void {
    this.assertRunning();
    this.contactParticipants.add(participant);
    if (backendBody) this.contactBodies.set(backendBody, participant);
    const unregisterRouter = this.contactRouter.register(participant);
    let active = true;
    return () => {
      if (!active) return;
      active = false;
      unregisterRouter();
      this.contactParticipants.delete(participant);
      if (backendBody) this.contactBodies.delete(backendBody);
    };
  }

  registerBlockingParticipant(participant: PhaserBlockingParticipant): () => void {
    this.assertRunning();
    if (this.blockingParticipants.has(participant)) throw new Error(`Blocking participant '${participant.runtimeId}' is already registered`);
    for (const other of this.blockingParticipants) this.createBlockingCollider(participant, other);
    this.blockingParticipants.add(participant);
    let active = true;
    return () => {
      if (!active) return;
      active = false;
      this.blockingParticipants.delete(participant);
      for (const [key, collider] of [...this.blockingColliders]) {
        if (!key.split('|').includes(participant.runtimeId)) continue;
        collider.destroy();
        this.blockingColliders.delete(key);
      }
    };
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
  stepPhysics(deltaSeconds: number): void { this.scene.physics.world.step(deltaSeconds); this.physicsSteps += 1; }
  readAuthoritativePhysicsState(): void { this.run('physics-readback', 0); }
  collectManagedContacts(): void { this.run('contacts', 0); this.contactRouter.reconcile(); }
  resolveManagedAttacks(): void { this.run('attack-resolution', 0); }
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
    this.blockingParticipants.clear();
    this.contactParticipants.clear();
    this.contactRouter.clear();
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

  private contactCandidates(_observer: ContactParticipant, bounds: SensorBounds): readonly ContactParticipant[] {
    const overlapRect = (this.scene.physics.world as unknown as {
      overlapRect?: (x: number, y: number, width: number, height: number, includeDynamic?: boolean, includeStatic?: boolean) => readonly object[];
    }).overlapRect;
    if (!overlapRect) return [...this.contactParticipants];
    const padding = 1e-6;
    const bodies = overlapRect.call(this.scene.physics.world, bounds.x - padding, bounds.y - padding, bounds.width + padding * 2, bounds.height + padding * 2, true, true);
    const candidates = new Set<ContactParticipant>();
    for (const body of bodies) {
      const participant = this.contactBodies.get(body);
      if (participant) candidates.add(participant);
    }
    return [...candidates];
  }

  private createBlockingCollider(first: PhaserBlockingParticipant, second: PhaserBlockingParticipant): void {
    if (first.isStaticBody && second.isStaticBody) return;
    const ids = [first.runtimeId, second.runtimeId].sort();
    const key = `${ids[0]}|${ids[1]}`;
    const process = (): boolean => first.blockingActive && second.blockingActive
      && collisionMembershipAccepts(first.collisionMask, second.collisionLayer)
      && collisionMembershipAccepts(second.collisionMask, first.collisionLayer);
    const onCollide = (): void => {
      first.recordBlockingContact(this.blockingContact(first, second));
      second.recordBlockingContact(this.blockingContact(second, first));
    };
    const collider = this.scene.physics.add.collider(first.physicsObject, second.physicsObject, onCollide, process) as unknown as DestroyableCollider;
    this.blockingColliders.set(key, collider);
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
}
