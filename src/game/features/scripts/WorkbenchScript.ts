import type { CraftingContext } from '../../content/recipes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

/**
 * A crafting station. The world controller discovers stations (authored or
 * placed by the player) and offers them to the InteractionRouter; using one
 * opens the crafting surface filtered to the station's recipe context.
 */
function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('WorkbenchScript requires a registered script identity.');
  return context.scriptId;
}

export class WorkbenchScript extends ScriptNode {
  readonly prompt: string;
  /** Recipe context this station crafts (RecipeDef.context). */
  readonly recipeContext: CraftingContext;
  /** Distance from the station origin within which it can be used. */
  readonly interactRadius: number;
  /** How far above the station origin the interaction key badge floats. */
  readonly badgeRise: number;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const { prompt, recipeContext, interactRadius, badgeRise } = context.properties;
    this.prompt = typeof prompt === 'string' && prompt ? prompt : 'Use workbench';
    this.recipeContext = typeof recipeContext === 'string' && recipeContext ? recipeContext as CraftingContext : 'workbench';
    this.interactRadius = typeof interactRadius === 'number' && Number.isFinite(interactRadius) && interactRadius > 0 ? interactRadius : 90;
    this.badgeRise = typeof badgeRise === 'number' && Number.isFinite(badgeRise) ? badgeRise : 80;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): WorkbenchScript {
    return new WorkbenchScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
