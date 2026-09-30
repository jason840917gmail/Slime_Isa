import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export const STORY_FLAG_SERVICE = 'world.story-flags';

export interface StoryFlagPort {
  setFlags(flagIds: readonly string[]): void;
  hasFlag(flagId: string): boolean;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('StoryFlagScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * Sets a persistent story flag when its `set` handler runs, so authored
 * world pieces (a pressure plate's `pressed`, for example) can move the story
 * on without code. Flags are saved with the run.
 */
export class StoryFlagScript extends ScriptNode {
  readonly flagId: string;
  private port?: StoryFlagPort;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const flagId = context.properties.flagId;
    this.flagId = typeof flagId === 'string' ? flagId : '';
    this.registerSignalHandler('set', () => {
      if (this.flagId) this.port?.setFlags([this.flagId]);
    });
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.port = this.service<StoryFlagPort>(STORY_FLAG_SERVICE);
  }

  override _exit_tree(): void {
    this.port = undefined;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): StoryFlagScript {
    return new StoryFlagScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
