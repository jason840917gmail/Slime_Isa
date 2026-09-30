import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { Node } from '../../runtime/scene/Node';
import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import { GateScript } from './GateScript';

export const PLATE_WEIGHT_SERVICE = 'world.plate-weight';

/** Where something heavy enough to hold a plate down is standing. */
export interface PlateWeightPort {
  weights(): Iterable<Readonly<{ x: number; y: number }>>;
}

export interface PlateEvent {
  readonly plateId: string;
}

interface PlateVisual extends Node {
  visualOffset: { readonly x: number; readonly y: number };
  frame: number;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('PressurePlateScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * A pressure plate that only something heavy (the Heavy Gulp form) can hold
 * down. It emits `pressed` when a weight arrives and `released` when the last
 * one leaves. Name a gate in `gateId` to open every gate with that id in the
 * scene when pressed (placement and properties only, no connection needed), or
 * connect `pressed` to a gate's `open` handler. A latching plate
 * stays down once pressed. The `visual` sprite sinks by `sinkPx` while the
 * plate is down, and shows `pressedFrame` then when one is set (-1: none).
 */
export class PressurePlateScript extends ScriptNode {
  readonly plateId: string;
  readonly radius: number;
  readonly latch: boolean;
  /** Gates (`game.gate` gateId) this plate opens when pressed; empty for none. */
  readonly gateId: string;
  private readonly sinkPx: number;
  private readonly pressedFrame: number;
  private restFrame?: number;
  private weightPort?: PlateWeightPort;
  private down = false;
  private restOffset?: { readonly x: number; readonly y: number };

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const plateId = context.properties.plateId;
    this.plateId = typeof plateId === 'string' ? plateId : '';
    this.radius = this.numberProperty('radius', 40);
    this.sinkPx = this.numberProperty('sinkPx', 4);
    const pressedFrame = context.properties.pressedFrame;
    this.pressedFrame = typeof pressedFrame === 'number' && Number.isInteger(pressedFrame) ? pressedFrame : -1;
    this.latch = context.properties.latch === true;
    const gateId = context.properties.gateId;
    this.gateId = typeof gateId === 'string' ? gateId : '';
    this.set_process(true);
  }

  get pressed(): boolean {
    return this.down;
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.weightPort = this.service<PlateWeightPort>(PLATE_WEIGHT_SERVICE);
  }

  override _exit_tree(): void {
    this.weightPort = undefined;
  }

  override _process(): void {
    if (this.down && this.latch) return;
    const loaded = this.isLoaded();
    if (loaded === this.down) return;
    this.down = loaded;
    this.showSunk(loaded);
    if (loaded) this.openLinkedGates();
    this.getSignal<PlateEvent>(loaded ? 'pressed' : 'released')?.emit({ plateId: this.plateId });
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

  private isLoaded(): boolean {
    const parent = this.get_parent();
    const origin = parent instanceof Node2D ? parent.get_global_transform().position : undefined;
    if (!origin || !this.weightPort) return false;
    for (const weight of this.weightPort.weights()) {
      if (Math.hypot(weight.x - origin.x, weight.y - origin.y) <= this.radius) return true;
    }
    return false;
  }

  private showSunk(sunk: boolean): void {
    const visual = this.getReference<Node>('visual')?.configuredTarget as Partial<PlateVisual> | undefined;
    if (!visual) return;
    if (typeof visual.visualOffset === 'object') {
      this.restOffset ??= visual.visualOffset;
      const { x, y } = this.restOffset;
      visual.visualOffset = { x, y: sunk ? y + this.sinkPx : y };
    }
    if (this.pressedFrame >= 0 && typeof visual.frame === 'number') {
      this.restFrame ??= visual.frame;
      visual.frame = sunk ? this.pressedFrame : this.restFrame;
    }
  }

  private numberProperty(key: string, fallback: number): number {
    const value = this.exportedProperties[key];
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : fallback;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): PressurePlateScript {
    return new PressurePlateScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
