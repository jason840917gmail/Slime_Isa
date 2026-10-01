import type { Node } from '../../runtime/scene/Node';
import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import type { DamageCommit, DamageReceiver } from '../combat/DamageReceiver';
import type { DamageRouter } from '../combat/DamageRouter';
import { DAMAGE_ROUTER_SERVICE } from './EnemyScript';

export const TRAINING_DUMMY_SERVICE = 'world.training-dummy';

/** The world's side of a dummy: the damage number over it. */
export interface TrainingDummyPort {
  showHit(at: Readonly<{ x: number; y: number }>, damage: number): void;
}

interface WobblingVisual extends Node {
  rotation: number;
}

/** How far the dummy leans on a hit (radians) and how fast the wobble dies away. */
const WOBBLE_LEAN = 0.22;
const WOBBLE_FREQUENCY = 9;
const WOBBLE_DECAY = 4.5;
const HEALTH = 9999;

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('TrainingDummyScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * A straw dummy for trying attacks: any hit on its `damageArea` shows the
 * damage and makes the `visual` wobble, and the attacker gets the usual hit
 * feedback (hit-stop, sparks). It never breaks and never fights back.
 */
export class TrainingDummyScript extends ScriptNode implements DamageReceiver {
  private port?: TrainingDummyPort;
  private wobbleAge = -1;
  private wobbleSide = 1;
  private hitCount = 0;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    this.set_process(true);
  }

  get runtimeNodeId(): string { return this.runtimeId; }

  get hits(): number { return this.hitCount; }

  getDamageState() {
    return { hp: HEALTH, maxHp: HEALTH, dead: false };
  }

  commitDamage(commit: DamageCommit): void {
    this.hitCount += 1;
    this.wobbleAge = 0;
    this.wobbleSide = commit.request.impact.knockX < 0 ? -1 : 1;
    const parent = this.get_parent();
    const at = parent instanceof Node2D ? parent.get_global_transform().position : { x: 0, y: 0 };
    this.port?.showHit(at, commit.result.actualDamage);
    this.getSignal<{ damage: number }>('hit')?.emit({ damage: commit.result.actualDamage });
  }

  override _enter_tree(): void {
    super._enter_tree();
    const router = this.service<DamageRouter>(DAMAGE_ROUTER_SERVICE);
    const area = this.getReference('damageArea')?.configuredTarget;
    if (!area) throw new Error(`TrainingDummyScript '${this.runtimeId}' requires its damageArea reference.`);
    router.registerArea(this, { areaNodeId: area.runtimeId, priority: 0, damageMultiplier: 1 });
    this.entryDisposables.add(() => router.unregisterArea(this, area.runtimeId));
    this.port = this.service<TrainingDummyPort>(TRAINING_DUMMY_SERVICE);
  }

  override _exit_tree(): void {
    this.port = undefined;
  }

  override _process(deltaSeconds: number): void {
    if (this.wobbleAge < 0) return;
    this.wobbleAge += deltaSeconds;
    const visual = this.getReference<WobblingVisual>('visual')?.configuredTarget;
    const amplitude = WOBBLE_LEAN * Math.exp(-WOBBLE_DECAY * this.wobbleAge);
    const lean = amplitude < 0.004 ? 0 : this.wobbleSide * amplitude * Math.cos(this.wobbleAge * WOBBLE_FREQUENCY * Math.PI * 2 / 3);
    if (visual && 'rotation' in visual) visual.rotation = lean;
    if (lean === 0) this.wobbleAge = -1;
  }
}
