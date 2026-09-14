import type { RuntimeNodeId } from '../../../content/scenes/identifiers';
import type { Node } from '../Node';
import { collisionMembershipAccepts, type PhysicsContact, type PhysicsOwnerKind, type ShapeContact } from './PhysicsContact';
import { sensorBoundsIntersect, sensorShapesIntersect, unionSensorBounds, type SensorBounds, type SensorShape } from './SensorGeometry';

export interface ContactParticipant {
  readonly runtimeId: RuntimeNodeId;
  readonly node: Node;
  readonly kind: PhysicsOwnerKind;
  readonly collisionLayer: number;
  readonly collisionMask: number;
  readonly monitoring: boolean;
  readonly monitorable: boolean;
  readonly contactActive: boolean;
  contactShapes(): readonly SensorShape[];
  contactBounds(): SensorBounds | undefined;
  contactEntered(contact: PhysicsContact): void;
  contactExited(contact: PhysicsContact): void;
}

export type ContactCandidateProvider = (observer: ContactParticipant, bounds: SensorBounds) => readonly ContactParticipant[];

interface ActiveContact {
  readonly observerId: RuntimeNodeId;
  readonly otherId: RuntimeNodeId;
  readonly observerKind: PhysicsOwnerKind;
  readonly otherKind: PhysicsOwnerKind;
  readonly shapes: readonly ShapeContact[];
}

function directedKey(observerId: RuntimeNodeId, otherId: RuntimeNodeId): string { return `${observerId}>${otherId}`; }

export class ContactRouter {
  private readonly participants = new Map<RuntimeNodeId, ContactParticipant>();
  private active = new Map<string, ActiveContact>();

  constructor(private readonly candidates?: ContactCandidateProvider) {}

  get participantCount(): number { return this.participants.size; }
  get activeContactCount(): number { return this.active.size; }

  register(participant: ContactParticipant): () => void {
    if (this.participants.has(participant.runtimeId)) throw new Error(`Physics contact participant '${participant.runtimeId}' is already registered`);
    this.participants.set(participant.runtimeId, participant);
    let registered = true;
    return () => { if (!registered) return; registered = false; this.participants.delete(participant.runtimeId); };
  }

  currentContacts(observerId: RuntimeNodeId): readonly PhysicsContact[] {
    const observer = this.participants.get(observerId);
    if (!observer?.contactActive || !observer.monitoring) return [];
    return [...this.active.values()]
      .filter((contact) => contact.observerId === observerId && this.contactStillValid(contact))
      .map((contact) => this.materialize(contact));
  }

  isOverlapping(observerId: RuntimeNodeId, otherId: RuntimeNodeId): boolean {
    return this.currentContacts(observerId).some((contact) => contact.otherId === otherId);
  }

  reconcile(): void {
    const desired = new Map<string, ActiveContact>();
    const observers = [...this.participants.values()].filter((entry) => entry.kind === 'area' && entry.contactActive && entry.monitoring);
    for (const observer of observers) {
      const observerShapes = observer.contactShapes();
      const bounds = observer.contactBounds() ?? unionSensorBounds(observerShapes);
      if (!bounds || observerShapes.length === 0) continue;
      const candidates = this.candidates?.(observer, bounds) ?? [...this.participants.values()];
      for (const other of candidates) {
        if (other === observer || !other.contactActive || !other.monitorable || !collisionMembershipAccepts(observer.collisionMask, other.collisionLayer)) continue;
        const otherShapes = other.contactShapes();
        const otherBounds = other.contactBounds() ?? unionSensorBounds(otherShapes);
        if (!otherBounds || !sensorBoundsIntersect(bounds, otherBounds)) continue;
        const shapes: ShapeContact[] = [];
        for (const observerShape of observerShapes) for (const otherShape of otherShapes) {
          if (sensorShapesIntersect(observerShape, otherShape)) shapes.push({ observerShapeId: observerShape.shapeId, otherShapeId: otherShape.shapeId });
        }
        if (shapes.length === 0) continue;
        shapes.sort((left, right) => `${left.observerShapeId}/${left.otherShapeId}`.localeCompare(`${right.observerShapeId}/${right.otherShapeId}`));
        const key = directedKey(observer.runtimeId, other.runtimeId);
        desired.set(key, { observerId: observer.runtimeId, otherId: other.runtimeId, observerKind: observer.kind, otherKind: other.kind, shapes });
      }
    }

    for (const [key, contact] of this.active) {
      if (desired.has(key)) continue;
      const observer = this.participants.get(contact.observerId);
      if (observer?.contactActive && observer.monitoring) observer.contactExited(this.materialize(contact));
    }
    for (const [key, contact] of desired) {
      if (!this.active.has(key)) this.participants.get(contact.observerId)?.contactEntered(this.materialize(contact));
    }
    this.active = desired;
  }

  clear(): void { this.active.clear(); this.participants.clear(); }

  private materialize(contact: ActiveContact): PhysicsContact {
    const observer = this.participants.get(contact.observerId);
    const other = this.participants.get(contact.otherId);
    return {
      ...contact,
      ...(observer ? { observer: observer.node } : {}),
      ...(other ? { other: other.node } : {}),
    };
  }

  private contactStillValid(contact: ActiveContact): boolean {
    const observer = this.participants.get(contact.observerId);
    const other = this.participants.get(contact.otherId);
    if (!observer?.contactActive || !observer.monitoring || !other?.contactActive || !other.monitorable
      || !collisionMembershipAccepts(observer.collisionMask, other.collisionLayer)) return false;
    const observerShapeIds = new Set(observer.contactShapes().map((shape) => shape.shapeId));
    const otherShapeIds = new Set(other.contactShapes().map((shape) => shape.shapeId));
    return contact.shapes.some((shape) => observerShapeIds.has(shape.observerShapeId) && otherShapeIds.has(shape.otherShapeId));
  }
}
