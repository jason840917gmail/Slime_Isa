import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { Node } from '../../runtime/scene/Node';
import { AnimationPlayerNode } from '../../runtime/scene/animation/AnimationPlayerNode';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

function scriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('EffectScript requires a registered script identity.');
  return context.scriptId;
}

export class EffectScript extends ScriptNode {
  readonly effectId: string;
  readonly lifetimeMs: number;
  private ageMs = 0;
  private playingValue = false;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: scriptId(context), exportedProperties: context.properties });
    const values: Readonly<Record<string, JsonValue>> = context.properties;
    this.effectId = typeof values.effectId === 'string' ? values.effectId : 'unknown-effect';
    this.lifetimeMs = typeof values.lifetimeMs === 'number' ? Math.max(0, values.lifetimeMs) : 0;
  }

  get playing(): boolean { return this.playingValue; }

  override _enter_tree(): void {
    this.set_physics_process(true);
    this.play('right');
  }

  override _physics_process(deltaSeconds: number): void {
    if (!this.playingValue) return;
    this.ageMs += deltaSeconds * 1000;
    if (this.ageMs >= this.lifetimeMs) this.finish();
  }

  override _exit_tree(): void {
    this.set_physics_process(false);
    this.playingValue = false;
  }

  play(variant: 'right' | 'left' | 'up' | 'down' | 'default'): void {
    const animation = this.getReference<Node>('animation')?.configuredTarget;
    if (animation instanceof AnimationPlayerNode && animation.hasAnimation(variant)) animation.play(variant);
    this.ageMs = 0;
    this.playingValue = true;
  }

  finish(): void {
    if (!this.playingValue) return;
    this.playingValue = false;
    this.getSignal<{ effectId: string }>('finished')?.emit({ effectId: this.effectId });
    (this.get_parent() ?? this).queue_free();
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): EffectScript {
    return new EffectScript({ runtimeId, name: this.name, type: 'ScriptNode', scriptId: this.scriptId, properties: this.exportedProperties, resources: new Map() });
  }
}
