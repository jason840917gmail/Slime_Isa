import { isCraftingStation } from '../../content/recipes/RecipeCatalog';
import type { CraftingSite, CraftingStation } from '../../content/recipes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

/**
 * A crafting station. The world controller discovers stations (authored or
 * placed by the player) and offers them to the InteractionRouter; using one
 * opens the crafting surface for the station and its tier (a restored Workshop
 * and an upgraded one are different variants carrying different tiers).
 */
function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('WorkbenchScript requires a registered script identity.');
  return context.scriptId;
}

export class WorkbenchScript extends ScriptNode {
  readonly prompt: string;
  /** The station this is (RecipeDef.station); authored as `recipeContext`. */
  readonly station: CraftingStation;
  /** How far the station is upgraded; recipes above it show as locked. */
  readonly tier: number;
  /** Distance from the station origin within which it can be used. */
  readonly interactRadius: number;
  /** How far above the station origin the interaction key badge floats. */
  readonly badgeRise: number;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const { prompt, recipeContext, tier, interactRadius, badgeRise } = context.properties;
    this.prompt = typeof prompt === 'string' && prompt ? prompt : 'Use workbench';
    this.station = isCraftingStation(recipeContext) && recipeContext !== 'portable' ? recipeContext : 'workbench';
    this.tier = typeof tier === 'number' && Number.isInteger(tier) && tier >= 1 ? tier : 1;
    this.interactRadius = typeof interactRadius === 'number' && Number.isFinite(interactRadius) && interactRadius > 0 ? interactRadius : 90;
    this.badgeRise = typeof badgeRise === 'number' && Number.isFinite(badgeRise) ? badgeRise : 80;
  }

  get site(): CraftingSite {
    return { station: this.station, tier: this.tier };
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
