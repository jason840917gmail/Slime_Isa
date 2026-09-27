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

interface ActiveContact {
  readonly observerId: RuntimeNodeId;
  readonly otherId: RuntimeNodeId;
  readonly observerKind: PhysicsOwnerKind;
  readonly otherKind: PhysicsOwnerKind;
  readonly shapes: readonly ShapeContact[];
}

interface ContactTarget {
  readonly participant: ContactParticipant;
  readonly order: number;
  readonly shapes: readonly SensorShape[];
  readonly bounds: SensorBounds;
}

interface CellRange { readonly minX: number; readonly minY: number; readonly maxX: number; readonly maxY: number }

function directedKey(observerId: RuntimeNodeId, otherId: RuntimeNodeId): string { return `${observerId}>${otherId}`; }

/**
 * Uniform-grid broadphase cell size in world pixels. The grid is only a
 * conservative filter: every candidate still passes the exact bounds and shape
 * tests, so the size affects speed, never which contacts are reported.
 */
const BROADPHASE_CELL_SIZE = 128;
/** Grows indexed bounds so edge-touching pairs (see sensorBoundsIntersect) share a cell. */
const BROADPHASE_PADDING = 1e-6;
/** Packs a cell coordinate pair into one numeric key; maps span far fewer than 2^20 cells per axis. */
const BROADPHASE_ROW_STRIDE = 2 ** 21;
/** Bounds covering more cells than this skip the grid and are tested against everything. */
const BROADPHASE_MAX_CELLS = 256;

/** Grid cells covered by the bounds, or undefined when they are too large or not finite to index. */
function cellRange(bounds: SensorBounds): CellRange | undefined {
  const range = {
    minX: Math.floor((bounds.x - BROADPHASE_PADDING) / BROADPHASE_CELL_SIZE),
    minY: Math.floor((bounds.y - BROADPHASE_PADDING) / BROADPHASE_CELL_SIZE),
    maxX: Math.floor((bounds.x + bounds.width + BROADPHASE_PADDING) / BROADPHASE_CELL_SIZE),
    maxY: Math.floor((bounds.y + bounds.height + BROADPHASE_PADDING) / BROADPHASE_CELL_SIZE),
  };
  const cells = (range.maxX - range.minX + 1) * (range.maxY - range.minY + 1);
  return Number.isFinite(cells) && cells <= BROADPHASE_MAX_CELLS ? range : undefined;
}

export class ContactRouter {
  private readonly participants = new Map<RuntimeNodeId, ContactParticipant>();
  private readonly registrationOrder = new Map<ContactParticipant, number>();
  private nextRegistrationOrder = 0;
  private active = new Map<string, ActiveContact>();

  get participantCount(): number { return this.participants.size; }
  get activeContactCount(): number { return this.active.size; }

  register(participant: ContactParticipant): () => void {
    if (this.participants.has(participant.runtimeId)) throw new Error(`Physics contact participant '${participant.runtimeId}' is already registered`);
    this.participants.set(participant.runtimeId, participant);
    this.registrationOrder.set(participant, this.nextRegistrationOrder++);
    let registered = true;
    return () => {
      if (!registered) return;
      registered = false;
      this.participants.delete(participant.runtimeId);
      this.registrationOrder.delete(participant);
    };
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

  /**
   * Rebuilds the desired contact set. Monitorable participants are indexed in
   * a uniform grid once per call, so each observer only tests nearby targets
   * instead of every participant. Candidates are visited in registration order,
   * which keeps enter/exit emission order identical to an exhaustive scan.
   */
  reconcile(): void {
    const desired = new Map<string, ActiveContact>();
    const observers: ContactTarget[] = [];
    const grid = new Map<number, ContactTarget[]>();
    const targets: ContactTarget[] = [];
    const oversized: ContactTarget[] = [];
    for (const participant of this.participants.values()) {
      if (!participant.contactActive) continue;
      const observing = participant.kind === 'area' && participant.monitoring;
      if (!observing && !participant.monitorable) continue;
      // Shapes and bounds are read once per reconcile and shared by both roles.
      const shapes = participant.contactShapes();
      const bounds = participant.contactBounds() ?? unionSensorBounds(shapes);
      if (!bounds) continue;
      const target: ContactTarget = { participant, order: this.registrationOrder.get(participant) ?? 0, shapes, bounds };
      if (observing && shapes.length > 0) observers.push(target);
      if (!participant.monitorable) continue;
      targets.push(target);
      const range = cellRange(bounds);
      if (!range) { oversized.push(target); continue; }
      for (let cellY = range.minY; cellY <= range.maxY; cellY += 1) {
        for (let cellX = range.minX; cellX <= range.maxX; cellX += 1) {
          const key = cellY * BROADPHASE_ROW_STRIDE + cellX;
          const cell = grid.get(key);
          if (cell) cell.push(target); else grid.set(key, [target]);
        }
      }
    }
    for (const { participant: observer, shapes: observerShapes, bounds } of observers) {
      const range = cellRange(bounds);
      let candidates = targets;
      if (range) {
        const found = new Set<ContactTarget>(oversized);
        for (let cellY = range.minY; cellY <= range.maxY; cellY += 1) {
          for (let cellX = range.minX; cellX <= range.maxX; cellX += 1) {
            const cell = grid.get(cellY * BROADPHASE_ROW_STRIDE + cellX);
            if (cell) for (const target of cell) found.add(target);
          }
        }
        candidates = [...found].sort((left, right) => left.order - right.order);
      }
      for (const { participant: other, shapes: otherShapes, bounds: otherBounds } of candidates) {
        if (other === observer || !collisionMembershipAccepts(observer.collisionMask, other.collisionLayer)) continue;
        if (!sensorBoundsIntersect(bounds, otherBounds)) continue;
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

  clear(): void { this.active.clear(); this.participants.clear(); this.registrationOrder.clear(); }

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
