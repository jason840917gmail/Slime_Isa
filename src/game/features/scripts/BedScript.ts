import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

/**
 * A bed the player can sleep in. The world controller discovers beds and
 * offers them to the InteractionRouter; sleeping itself (animation, healing,
 * waking, respawn point) belongs to the rest feature. All points are local to
 * the bed's root, which sits at the bottom centre of the bed art.
 */
function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('BedScript requires a registered script identity.');
  return context.scriptId;
}

export interface BedPoint {
  readonly x: number;
  readonly y: number;
}

export class BedScript extends ScriptNode {
  readonly prompt: string;
  /** Distance from the bed origin within which the player can lie down. */
  readonly interactRadius: number;
  /** How far above the bed origin the interaction key badge floats. */
  readonly badgeRise: number;
  /** Where the sleeping slime is drawn, relative to the bed origin. */
  readonly sleepPoint: BedPoint;
  /** Walkable spot in front of the bed where the slime stands up (and respawns). */
  readonly wakePoint: BedPoint;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const prompt = context.properties.prompt;
    this.prompt = typeof prompt === 'string' && prompt ? prompt : 'Sleep';
    this.interactRadius = this.positiveNumber('interactRadius', 90);
    this.badgeRise = this.finiteNumber('badgeRise', 70);
    this.sleepPoint = this.point('sleepPoint', { x: 0, y: -30 });
    this.wakePoint = this.point('wakePoint', { x: 0, y: 28 });
  }

  private positiveNumber(key: string, fallback: number): number {
    const value = this.exportedProperties[key];
    return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : fallback;
  }

  private finiteNumber(key: string, fallback: number): number {
    const value = this.exportedProperties[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  private point(key: string, fallback: BedPoint): BedPoint {
    const value = this.exportedProperties[key];
    return Array.isArray(value) && value.length === 2 && value.every((part) => typeof part === 'number' && Number.isFinite(part))
      ? { x: value[0] as number, y: value[1] as number }
      : fallback;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): BedScript {
    return new BedScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
