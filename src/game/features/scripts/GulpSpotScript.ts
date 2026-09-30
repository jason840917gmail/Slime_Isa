import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('GulpSpotScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * A Gulp spot: a world object (a mossy boulder, a silk cocoon) the slime can
 * eat from with W any number of times to take its material's form. It never
 * runs out. The world controller discovers spots; eating belongs to the gulp
 * feature. `radius` is measured from the spot's root, at the bottom centre of
 * its art.
 */
export class GulpSpotScript extends ScriptNode {
  /** Item ID of the material this spot offers (for example `stone`). */
  readonly materialItemId: string;
  readonly radius: number;
  /** How far above the spot origin the "[W] Gulp" hint floats. */
  readonly badgeRise: number;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const material = context.properties.materialItemId;
    this.materialItemId = typeof material === 'string' ? material : '';
    const radius = context.properties.radius;
    this.radius = typeof radius === 'number' && Number.isFinite(radius) && radius > 0 ? radius : 96;
    const badgeRise = context.properties.badgeRise;
    this.badgeRise = typeof badgeRise === 'number' && Number.isFinite(badgeRise) ? badgeRise : 80;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): GulpSpotScript {
    return new GulpSpotScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
