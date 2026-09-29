import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

/**
 * A door the player uses on purpose (press interact nearby) to travel to its
 * linked door in another area, e.g. from a house exterior into its interior
 * and back. The player arrives at the target door's `arrival` child node, or
 * at the door itself when it has none.
 * The world controller discovers doors and offers them to the InteractionRouter;
 * navigation itself goes through the same exit flow as walk-in area exits.
 */
function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('DoorScript requires a registered script identity.');
  return context.scriptId;
}

export class DoorScript extends ScriptNode {
  readonly mapId: string;
  readonly doorId: string;
  readonly targetAreaId: string;
  readonly targetDoorId: string;
  readonly prompt: string;
  /** World-space distance from the door origin within which it can be used. */
  readonly interactRadius: number;
  /** How far above the door origin the interaction key badge floats. */
  readonly badgeRise: number;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    this.mapId = this.stringProperty('mapId', '');
    this.doorId = this.stringProperty('doorId', '');
    this.targetAreaId = this.stringProperty('targetAreaId', '');
    this.targetDoorId = this.stringProperty('targetDoorId', '');
    this.prompt = this.stringProperty('prompt', 'Use door');
    const radius = context.properties.interactRadius;
    this.interactRadius = typeof radius === 'number' && Number.isFinite(radius) && radius > 0 ? radius : 96;
    const rise = context.properties.badgeRise;
    this.badgeRise = typeof rise === 'number' && Number.isFinite(rise) ? rise : 56;
  }

  private stringProperty(key: string, fallback: string): string {
    const value = this.exportedProperties[key];
    return typeof value === 'string' ? value : fallback;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): DoorScript {
    return new DoorScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
