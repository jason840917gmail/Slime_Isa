import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export const WORLD_INTERACTION_SERVICE = 'world.interaction';

export interface InteractionRequest {
  readonly interactionId: string;
  readonly instanceId: string;
  readonly actorNodeId: string;
  readonly action: JsonValue;
}

export type InteractionResult =
  | { readonly status: 'completed'; readonly navigationTarget?: string }
  | { readonly status: 'blocked'; readonly message: string };

export interface WorldInteractionPort {
  execute(request: InteractionRequest): InteractionResult;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('InteractionScript requires a registered script identity.');
  return context.scriptId;
}

export class InteractionScript extends ScriptNode {
  readonly interactionId: string;
  readonly instanceId: string;
  readonly prompt: string;
  readonly priority: number;
  readonly action: JsonValue;
  private world?: WorldInteractionPort;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    this.interactionId = this.stringProperty('interactionId', '');
    this.instanceId = this.stringProperty('instanceId', '');
    this.prompt = this.stringProperty('prompt', 'Interact');
    this.priority = Math.trunc(this.numberProperty('priority', 0));
    this.action = context.properties.action ?? {};
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.world = this.service<WorldInteractionPort>(WORLD_INTERACTION_SERVICE);
  }

  override _exit_tree(): void {
    this.world = undefined;
  }

  requestInteraction(actorNodeId: string): InteractionResult {
    const request: InteractionRequest = {
      interactionId: this.interactionId,
      instanceId: this.instanceId,
      actorNodeId,
      action: this.action,
    };
    const result = this.world?.execute(request) ?? { status: 'blocked' as const, message: 'Interaction unavailable' };
    this.getSignal<InteractionResult>('interaction_resolved')?.emit(result);
    return result;
  }

  private stringProperty(key: string, fallback: string): string {
    const value = this.exportedProperties[key];
    return typeof value === 'string' ? value : fallback;
  }

  private numberProperty(key: string, fallback: number): number {
    const value = this.exportedProperties[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): InteractionScript {
    return new InteractionScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
