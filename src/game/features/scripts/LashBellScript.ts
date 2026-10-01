import type { Node } from '../../runtime/scene/Node';
import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import type { DamageCommit, DamageReceiver } from '../combat/DamageReceiver';
import type { DamageRouter } from '../combat/DamageRouter';
import { DAMAGE_ROUTER_SERVICE } from './EnemyScript';
import { GateScript } from './GateScript';

export const LASH_BELL_SERVICE = 'world.lash-bell';

/** The world's side of a bell: its sound and hint. */
export interface LashBellPort {
  rung(at: Readonly<{ x: number; y: number }>): void;
}

export interface LashBellEvent {
  readonly bellId: string;
}

interface BellVisual extends Node {
  frame: number;
}

/** Frames of the ring (`256x256-tile_3x1-lash-bell-post`: 0 rest, 1 and 2 swung) and how long each shows. */
const RING_FRAMES = [1, 2, 1, 2, 1, 0];
const RING_FRAME_SECONDS = 0.09;

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('LashBellScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * A bell post rung from a distance: the Stretch Lash hooking it rings it (the
 * world calls `ring`), and with `lashOnly` off a weapon hit on its
 * `damageArea` rings it too. Ringing emits `rung` and opens every `game.gate`
 * whose id is `gateId`. The bell has no health to lose and never breaks.
 */
export class LashBellScript extends ScriptNode implements DamageReceiver {
  readonly bellId: string;
  readonly gateId: string;
  readonly lashOnly: boolean;
  private port?: LashBellPort;
  private ringStep = -1;
  private ringElapsed = 0;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const bellId = context.properties.bellId;
    this.bellId = typeof bellId === 'string' ? bellId : '';
    const gateId = context.properties.gateId;
    this.gateId = typeof gateId === 'string' ? gateId : '';
    this.lashOnly = context.properties.lashOnly !== false;
    this.set_process(true);
  }

  get runtimeNodeId(): string { return this.runtimeId; }

  get ringing(): boolean { return this.ringStep >= 0; }

  getDamageState() {
    return { hp: 1, maxHp: 1, dead: false };
  }

  commitDamage(_commit: DamageCommit): void {
    this.ring();
  }

  override _enter_tree(): void {
    super._enter_tree();
    const area = this.getReference('damageArea')?.configuredTarget;
    if (!area) throw new Error(`LashBellScript '${this.runtimeId}' requires its damageArea reference.`);
    this.port = this.service<LashBellPort>(LASH_BELL_SERVICE);
    if (this.lashOnly) return;
    const router = this.service<DamageRouter>(DAMAGE_ROUTER_SERVICE);
    router.registerArea(this, { areaNodeId: area.runtimeId, priority: 0, damageMultiplier: 1 });
    this.entryDisposables.add(() => router.unregisterArea(this, area.runtimeId));
  }

  override _exit_tree(): void {
    this.port = undefined;
  }

  override _process(deltaSeconds: number): void {
    if (this.ringStep < 0) return;
    this.ringElapsed += deltaSeconds;
    if (this.ringElapsed < RING_FRAME_SECONDS) return;
    this.ringElapsed = 0;
    this.ringStep += 1;
    if (this.ringStep >= RING_FRAMES.length) {
      this.ringStep = -1;
      this.showFrame(0);
      return;
    }
    this.showFrame(RING_FRAMES[this.ringStep]);
  }

  /** Rings the bell and opens its gates. */
  ring(): void {
    this.ringStep = 0;
    this.ringElapsed = 0;
    this.showFrame(RING_FRAMES[0]);
    this.openLinkedGates();
    const parent = this.get_parent();
    const at = parent instanceof Node2D ? parent.get_global_transform().position : { x: 0, y: 0 };
    this.port?.rung(at);
    this.getSignal<LashBellEvent>('rung')?.emit({ bellId: this.bellId });
  }

  private showFrame(frame: number): void {
    const visual = this.getReference<BellVisual>('visual')?.configuredTarget;
    if (visual && 'frame' in visual) visual.frame = frame;
  }

  private openLinkedGates(): void {
    const root = this.get_tree()?.root;
    if (!this.gateId || !root) return;
    const visit = (node: Node): void => {
      for (const child of node.get_children()) {
        if (child instanceof GateScript && child.gateId === this.gateId) child.open();
        visit(child);
      }
    };
    visit(root);
  }
}
