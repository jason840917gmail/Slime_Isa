import type { HitboxActivationHandle, HitboxConfig } from '../../../combat/Hitbox';
import type {
  SupplementalWeaponAttack,
  SupplementalWeaponHitboxPort,
  SupplementalWeaponHitboxRequest,
} from '../../../combat/Weapon';
import { authoredNodeId, runtimeNodeId } from '../../../content/scenes/identifiers';
import type { DamageRouter, RoutedDamageOutcome } from '../../../features/combat/DamageRouter';
import {
  sensorShapeBounds,
  sensorShapesIntersect,
  type SensorShape,
} from '../../../runtime/scene/physics/SensorGeometry';
import type { PhaserNodeContext } from '../PhaserNodeContext';
import type { LegacyCombatBridge } from './LegacyCombatBridge';

export interface LegacyWeaponManagedTarget {
  readonly areaNodeId: string;
  readonly receiverNodeId: string;
  readonly x: number;
  readonly y: number;
  readonly attackDirection: SupplementalWeaponHitboxRequest['attackDirection'];
}

export interface LegacyWeaponTargetBridgeOptions {
  readonly context: PhaserNodeContext;
  readonly combat: LegacyCombatBridge;
  readonly router: DamageRouter;
  readonly sourceNodeId?: string;
  readonly weaponTags?: (weaponId: string) => readonly string[];
  readonly damageTypes?: (weaponId: string) => readonly string[];
  readonly transformDamage?: (damage: number, target: LegacyWeaponManagedTarget) => number;
  readonly onOutcome?: (outcome: RoutedDamageOutcome, target: LegacyWeaponManagedTarget | undefined) => void;
}

interface ActiveHitbox {
  readonly token: number;
  readonly request: SupplementalWeaponHitboxRequest;
  readonly areaNodeId: string;
  readonly shape: SensorShape;
}

/**
 * Temporary mixed-runtime adapter. Phaser weapon tracks own activation timing;
 * this bridge only gathers managed Area2D candidates and submits normalized
 * contacts to the shared combat authority during the fixed-step route phase.
 */
export class LegacyWeaponTargetBridge implements SupplementalWeaponHitboxPort {
  private readonly sourceNodeId: string;
  private readonly active = new Map<string, ActiveHitbox>();
  private readonly seenAreas = new Set<string>();
  private readonly targetByArea = new Map<string, LegacyWeaponManagedTarget>();
  private readonly unregisterResolution: () => void;
  private attack?: SupplementalWeaponAttack;
  private nextToken = 1;
  private simulationTimeMs = 0;
  private disposed = false;

  constructor(private readonly options: LegacyWeaponTargetBridgeOptions) {
    this.sourceNodeId = options.sourceNodeId ?? 'legacy.player.weapon';
    this.unregisterResolution = options.context.registerCallback('attack-resolution', (deltaSeconds) => {
      this.simulationTimeMs += deltaSeconds * 1000;
      this.resolveActiveHitboxes();
    });
  }

  beginAttack(request: SupplementalWeaponAttack): void {
    this.assertActive();
    this.endAttack();
    this.attack = request;
    this.seenAreas.clear();
    this.targetByArea.clear();
    this.options.combat.beginAttack(
      this.sourceNodeId,
      request.hitboxIds.map((hitboxId) => this.attackAreaNodeId(hitboxId)),
    );
  }

  activateHitbox(request: SupplementalWeaponHitboxRequest): HitboxActivationHandle {
    this.assertActive();
    const attack = this.attack;
    if (!attack || attack.playbackId !== request.playbackId || attack.weaponId !== request.weaponId) {
      return inactiveHandle();
    }
    const token = this.nextToken++;
    const active: ActiveHitbox = {
      token,
      request,
      areaNodeId: this.attackAreaNodeId(request.hitboxId),
      shape: hitboxSensorShape(request.hitboxId, request.hitbox),
    };
    this.active.set(request.hitboxId, active);
    let registered = true;
    return {
      get isActive(): boolean { return registered; },
      deactivate: () => {
        if (!registered) return;
        registered = false;
        if (this.active.get(request.hitboxId)?.token === token) this.active.delete(request.hitboxId);
      },
    };
  }

  endAttack(): void {
    if (!this.attack) return;
    this.active.clear();
    this.seenAreas.clear();
    this.targetByArea.clear();
    this.options.combat.cancelAttack(this.sourceNodeId);
    this.attack = undefined;
  }

  dispose(): void {
    if (this.disposed) return;
    this.endAttack();
    this.unregisterResolution();
    this.disposed = true;
  }

  private resolveActiveHitboxes(): void {
    if (!this.attack || this.active.size === 0) return;
    const pendingByReceiver = new Map<string, Array<{ readonly hitbox: ActiveHitbox; readonly target: LegacyWeaponManagedTarget }>>();
    for (const hitbox of [...this.active.values()].sort((left, right) => left.areaNodeId.localeCompare(right.areaNodeId))) {
      const bounds = sensorShapeBounds(hitbox.shape);
      const participants = this.options.context.queryContactParticipants(bounds)
        .filter((participant) => participant.kind === 'area' && participant.monitorable && this.options.router.hasArea(participant.runtimeId))
        .sort((left, right) => left.runtimeId.localeCompare(right.runtimeId));
      for (const participant of participants) {
        if (this.seenAreas.has(participant.runtimeId)) continue;
        const targetBounds = participant.contactBounds();
        if (!targetBounds || !participant.contactShapes().some((shape) => sensorShapesIntersect(hitbox.shape, shape))) continue;
        const receiverNodeId = this.options.router.receiverNodeIdForArea(participant.runtimeId);
        if (!receiverNodeId) continue;
        const target = {
          areaNodeId: participant.runtimeId,
          receiverNodeId,
          x: targetBounds.x + targetBounds.width / 2,
          y: targetBounds.y + targetBounds.height / 2,
          attackDirection: hitbox.request.attackDirection,
        };
        const pending = pendingByReceiver.get(receiverNodeId) ?? [];
        pending.push({ hitbox, target });
        pendingByReceiver.set(receiverNodeId, pending);
      }
    }

    for (const receiverNodeId of [...pendingByReceiver.keys()].sort()) {
      const contacts = pendingByReceiver.get(receiverNodeId) ?? [];
      const representative = contacts[0];
      if (!representative) continue;
      const damage = Math.max(0, this.options.transformDamage?.(representative.hitbox.request.damage, representative.target)
        ?? representative.hitbox.request.damage);
      for (const { hitbox, target } of contacts) {
        this.seenAreas.add(target.areaNodeId);
        this.targetByArea.set(target.areaNodeId, target);
        this.options.combat.collectContact({
          sourceNodeId: this.sourceNodeId,
          attackAreaNodeId: hitbox.areaNodeId,
          targetAreaNodeId: target.areaNodeId,
          weaponId: hitbox.request.weaponId,
          weaponTags: this.options.weaponTags?.(hitbox.request.weaponId) ?? [],
          damageTypes: this.options.damageTypes?.(hitbox.request.weaponId) ?? ['physical'],
          damage,
          effects: hitbox.request.knockStrength > 0 ? [{ effectId: 'knockback', potency: hitbox.request.knockStrength }] : [],
          impact: {
            x: hitbox.request.hitbox.x,
            y: hitbox.request.hitbox.y,
            knockX: hitbox.request.knockX,
            knockY: hitbox.request.knockY,
          },
        });
      }
    }

    const outcomes = this.options.combat.resolveStep(this.simulationTimeMs);
    for (const outcome of outcomes) {
      const target = outcome.selectedAreaNodeId ? this.targetByArea.get(outcome.selectedAreaNodeId) : undefined;
      this.options.onOutcome?.(outcome, target);
    }
  }

  private attackAreaNodeId(hitboxId: string): string {
    return `${this.sourceNodeId}.${hitboxId}`;
  }

  private assertActive(): void {
    if (this.disposed) throw new Error('LegacyWeaponTargetBridge has been disposed.');
  }
}

function inactiveHandle(): HitboxActivationHandle {
  return { isActive: false, deactivate() {} };
}

function hitboxSensorShape(hitboxId: string, hitbox: Readonly<HitboxConfig>): SensorShape {
  const shapeId = runtimeNodeId('legacy-player-weapon', [], authoredNodeId(hitboxId));
  if (hitbox.shape === 'circle') {
    const radius = hitbox.radiusX ?? hitbox.width / 2;
    return { shapeId, shape: 'circle', centerX: hitbox.x, centerY: hitbox.y, radius };
  }
  if (hitbox.shape === 'ellipse') {
    return {
      shapeId,
      shape: 'ellipse',
      centerX: hitbox.x,
      centerY: hitbox.y,
      radiusX: hitbox.radiusX ?? hitbox.width / 2,
      radiusY: hitbox.radiusY ?? hitbox.height / 2,
    };
  }
  if (hitbox.shape === 'sector') {
    return {
      shapeId,
      shape: 'sector',
      originX: hitbox.originX ?? hitbox.x,
      originY: hitbox.originY ?? hitbox.y,
      angleRad: hitbox.angle ?? 0,
      arcWidthRad: hitbox.arcWidth ?? Math.PI / 2,
      innerRadius: hitbox.innerRadius ?? 0,
      outerRadius: hitbox.outerRadius ?? Math.max(hitbox.width, hitbox.height) / 2,
    };
  }
  return {
    shapeId,
    shape: 'rectangle',
    x: hitbox.x - hitbox.width / 2,
    y: hitbox.y - hitbox.height / 2,
    width: hitbox.width,
    height: hitbox.height,
  };
}
