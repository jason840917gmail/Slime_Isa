import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { Node } from '../../runtime/scene/Node';
import type { Node2D } from '../../runtime/scene/Node2D';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

interface VelocityBody extends Node2D {
  velocity: { readonly x: number; readonly y: number };
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

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: scriptId(context), exportedProperties: context.properties });
    const values: Readonly<Record<string, JsonValue>> = context.properties;
    this.projectileId = typeof values.projectileId === 'string' ? values.projectileId : 'unknown-projectile';
    this.defaultSpeed = typeof values.defaultSpeed === 'number' ? Math.max(0, values.defaultSpeed) : 0;
    this.lifetimeMs = typeof values.lifetimeMs === 'number' ? Math.max(0, values.lifetimeMs) : 0;
    this.rotateToVelocity = values.rotateToVelocity === true;
  }

  get age(): number { return this.ageMs; }
  get launched(): boolean { return this.launchedValue; }

  override _enter_tree(): void { this.set_physics_process(true); }

  override _physics_process(deltaSeconds: number): void {
    if (!this.launchedValue) return;
    this.ageMs += deltaSeconds * 1000;
    if (this.ageMs >= this.lifetimeMs) this.expire();
  }

  override _exit_tree(): void {
    this.set_physics_process(false);
    this.launchedValue = false;
  }

  launch(direction: { readonly x: number; readonly y: number }, speed = this.defaultSpeed): void {
    const length = Math.hypot(direction.x, direction.y);
    if (!Number.isFinite(speed) || speed < 0 || length === 0) throw new Error('Projectile launch requires a direction and finite non-negative speed.');
    const body = this.body();
    const velocity = { x: direction.x / length * speed, y: direction.y / length * speed };
    body.velocity = velocity;
    if (this.rotateToVelocity) body.rotation = Math.atan2(velocity.y, velocity.x);
    this.ageMs = 0;
    this.launchedValue = true;
    this.getSignal<{ projectileId: string }>('launched')?.emit({ projectileId: this.projectileId });
  }

  expire(): void {
    if (!this.launchedValue) return;
    this.launchedValue = false;
    this.getSignal<{ projectileId: string }>('expired')?.emit({ projectileId: this.projectileId });
    (this.get_parent() ?? this).queue_free();
  }

  private body(): VelocityBody {
    const body = this.getReference<Node>('body')?.configuredTarget;
    if (!body || !body.has_runtime_capability('character-body') || !('velocity' in body) || !('rotation' in body)) {
      throw new Error(`ProjectileScript '${this.runtimeId}' requires a CharacterBody2D body reference.`);
    }
    return body as VelocityBody;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ProjectileScript {
    return new ProjectileScript({ runtimeId, name: this.name, type: 'ScriptNode', scriptId: this.scriptId, properties: this.exportedProperties, resources: new Map() });
  }
}
