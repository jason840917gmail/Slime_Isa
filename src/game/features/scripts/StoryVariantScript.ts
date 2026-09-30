import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { Node } from '../../runtime/scene/Node';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import { STORY_FLAG_SERVICE, type StoryFlagPort } from './StoryFlagScript';

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('StoryVariantScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * Story-flag scene variants (roadmap 6.1): one subtree for "before" and one for
 * "after" a story flag, authored side by side in the same scene. Only the
 * matching subtree stays in the scene tree, so its visuals, collision, doors and
 * stations exist and the other's do not. The flag is saved with the story, so
 * the right variant comes back after save and load. The `set` handler sets the
 * flag (connect a plate's `pressed`, a quest reward sets it too).
 */
export class StoryVariantScript extends ScriptNode {
  readonly flagId: string;
  private port?: StoryFlagPort;
  private shown?: boolean;
  /** Variant subtrees taken out of the tree, with the parent to put them back under. */
  private readonly parked = new Map<Node, Node>();

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const flagId = context.properties.flagId;
    this.flagId = typeof flagId === 'string' ? flagId : '';
    this.registerSignalHandler('set', () => this.setFlag());
    this.set_process(true);
  }

  /** True while the "flag set" variant is the one in the tree. */
  get flagShown(): boolean {
    return this.shown === true;
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.port = this.service<StoryFlagPort>(STORY_FLAG_SERVICE);
  }

  override _ready(): void {
    super._ready();
    this.apply();
  }

  override _exit_tree(): void {
    this.port = undefined;
    // Parked variants are out of the tree, so the tree cannot free them: free them with us.
    for (const node of this.parked.keys()) if (!node.is_freed()) node.queue_free();
    this.parked.clear();
  }

  override _process(): void {
    // A set lookup per frame: cheap, and it also follows flags set by quests or loads.
    if (this.flagIsSet() !== this.shown) this.apply();
  }

  setFlag(): void {
    if (!this.flagId || !this.port || this.port.hasFlag(this.flagId)) return;
    this.port.setFlags([this.flagId]);
    this.apply();
  }

  private flagIsSet(): boolean {
    return !!this.flagId && (this.port?.hasFlag(this.flagId) ?? false);
  }

  private apply(): void {
    const set = this.flagIsSet();
    this.shown = set;
    const active = this.variant(set ? 'whenSet' : 'whenUnset');
    const inactive = this.variant(set ? 'whenUnset' : 'whenSet');
    if (inactive && inactive.is_inside_tree()) {
      const parent = inactive.get_parent();
      if (parent) {
        this.parked.set(inactive, parent);
        parent.remove_child(inactive);
      }
    }
    if (active) {
      const parent = this.parked.get(active);
      if (parent) {
        this.parked.delete(active);
        parent.add_child(active);
      }
    }
    this.getSignal<{ flagId: string; set: boolean }>('switched')?.emit({ flagId: this.flagId, set });
  }

  private variant(key: 'whenSet' | 'whenUnset'): Node | undefined {
    // The configured target stays bound while a variant is parked out of the tree.
    return this.getReference<Node>(key)?.configuredTarget as Node | undefined;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): StoryVariantScript {
    return new StoryVariantScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
