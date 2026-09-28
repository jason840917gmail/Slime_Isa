import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { Node } from '../../runtime/scene/Node';
import { Node2D } from '../../runtime/scene/Node2D';
import type { PhysicsContact } from '../../runtime/scene/physics/PhysicsContact';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import type { AttackActivation } from '../combat/AttackActivation';
import type { DamageEffectRequest } from '../combat/DamageReceiver';
import type { DamageRouter } from '../combat/DamageRouter';
import { ATTACK_ACTIVATION_SERVICE, DAMAGE_ROUTER_SERVICE } from './EnemyScript';

interface VelocityBody extends Node2D {
  velocity: { readonly x: number; readonly y: number };
  readonly blockingContacts?: readonly unknown[];
}

export interface ProjectileDamagePayload {
  readonly sourceNodeId: string;
  readonly damage: number;
  readonly knockbackStrength: number;
  readonly weaponId?: string;
  readonly weaponTags?: readonly string[];
  readonly damageTypes?: readonly string[];
  readonly targetAreaNodeIds?: readonly string[];
  /** Extra on-hit effects besides knockback, e.g. `web` (potency = stuck milliseconds). */
  readonly effects?: readonly DamageEffectRequest[];
}

function scriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('ProjectileScript requires a registered script identity.');
  return context.scriptId;
}

export class ProjectileScript extends ScriptNode {
  readonly projectileId: string;
  readonly defaultSpeed: number;
  readonly lifetimeMs: number;
  readonly rotateToVelocity: boolean;

  private ageMs = 0;
  private launchedValue = false;
  private damage?: ProjectileDamagePayload;
  private activations?: AttackActivation;
  private damageRouter?: DamageRouter;
  private activationId?: string;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: scriptId(context), exportedProperties: context.properties });
    const values: Readonly<Record<string, JsonValue>> = context.properties;
    this.projectileId = typeof values.projectileId === 'string' ? values.projectileId : 'unknown-projectile';
    this.defaultSpeed = typeof values.defaultSpeed === 'number' ? Math.max(0, values.defaultSpeed) : 0;
    this.lifetimeMs = typeof values.lifetimeMs === 'number' ? Math.max(0, values.lifetimeMs) : 0;
    this.rotateToVelocity = values.rotateToVelocity === true;
    this.registerSignalHandler<PhysicsContact>('on_area_entered', (contact) => this.onAreaEntered(contact));
  }

  get age(): number { return this.ageMs; }
  get launched(): boolean { return this.launchedValue; }

  override _enter_tree(): void { this.set_physics_process(true); }

  override _physics_process(deltaSeconds: number): void {
    if (!this.launchedValue) return;
    this.ageMs += deltaSeconds * 1000;
    if ((this.body().blockingContacts?.length ?? 0) > 0) {
      this.expire();
      return;
    }
    if (this.ageMs >= this.lifetimeMs) this.expire();
  }

  override _exit_tree(): void {
    this.set_physics_process(false);
    this.launchedValue = false;
    this.endActivation();
    this.damage = undefined;
  }

  launch(direction: { readonly x: number; readonly y: number }, speed = this.defaultSpeed, damage?: ProjectileDamagePayload): void {
    const length = Math.hypot(direction.x, direction.y);
    if (!Number.isFinite(speed) || speed < 0 || length === 0) throw new Error('Projectile launch requires a direction and finite non-negative speed.');
    const body = this.body();
    const velocity = { x: direction.x / length * speed, y: direction.y / length * speed };
    body.velocity = velocity;
    if (this.rotateToVelocity) this.visual().rotation = Math.atan2(velocity.y, velocity.x);
    this.ageMs = 0;
    this.launchedValue = true;
    this.damage = damage;
    if (damage) {
      this.activations = this.service<AttackActivation>(ATTACK_ACTIVATION_SERVICE);
      this.damageRouter = this.service<DamageRouter>(DAMAGE_ROUTER_SERVICE);
      const area = this.getReference<Node>('attackArea')?.configuredTarget;
      if (!area) throw new Error(`ProjectileScript '${this.runtimeId}' requires an attackArea reference.`);
      this.activationId = this.activations.begin(damage.sourceNodeId, [area.runtimeId]);
    }
    this.getSignal<{ projectileId: string }>('launched')?.emit({ projectileId: this.projectileId });
  }

  expire(): void {
    if (!this.launchedValue) return;
    this.launchedValue = false;
    this.endActivation();
    this.getSignal<{ projectileId: string }>('expired')?.emit({ projectileId: this.projectileId });
    (this.get_parent() ?? this).queue_free();
  }

  private onAreaEntered(contact: PhysicsContact): void {
    const damage = this.damage;
    const activationId = this.activationId;
    const router = this.damageRouter;
    const attackArea = this.getReference<Node>('attackArea')?.configuredTarget;
    if (!this.launchedValue || !damage || !activationId || !router || !attackArea || contact.otherKind !== 'area') return;
    if (damage.targetAreaNodeIds && !damage.targetAreaNodeIds.includes(contact.otherId)) return;
    const velocity = this.body().velocity;
    const length = Math.hypot(velocity.x, velocity.y) || 1;
    router.routeStep([{
      activationId,
      sourceNodeId: damage.sourceNodeId,
      attackAreaNodeId: attackArea.runtimeId,
      targetAreaNodeId: contact.otherId,
      weaponId: damage.weaponId ?? this.projectileId,
      weaponTags: damage.weaponTags ?? ['projectile'],
      damageTypes: damage.damageTypes ?? ['physical'],
      baseDamage: damage.damage,
      effects: [
        ...(damage.knockbackStrength > 0 ? [{ effectId: 'knockback', potency: damage.knockbackStrength }] : []),
        ...(damage.effects ?? []),
      ],
      impact: { x: 0, y: 0, knockX: velocity.x / length, knockY: velocity.y / length },
    }], this.ageMs);
    this.expire();
  }

  private endActivation(): void {
    if (this.activationId) this.activations?.end(this.activationId);
    this.activationId = undefined;
    this.activations = undefined;
    this.damageRouter = undefined;
  }

  private body(): VelocityBody {
    const body = this.getReference<Node>('body')?.configuredTarget;
    if (!body || !body.has_runtime_capability('character-body') || !('velocity' in body) || !('rotation' in body)) {
      throw new Error(`ProjectileScript '${this.runtimeId}' requires a CharacterBody2D body reference.`);
    }
    return body as VelocityBody;
  }

  private visual(): Node2D {
    const visual = this.getReference<Node>('visual')?.configuredTarget;
    if (!(visual instanceof Node2D)) throw new Error(`ProjectileScript '${this.runtimeId}' requires a Node2D visual reference.`);
    return visual;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ProjectileScript {
    return new ProjectileScript({ runtimeId, name: this.name, type: 'ScriptNode', scriptId: this.scriptId, properties: this.exportedProperties, resources: new Map() });
  }
}
