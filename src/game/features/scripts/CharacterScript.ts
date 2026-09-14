import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';

export interface CharacterPoint {
  readonly x: number;
  readonly y: number;
}

export interface CharacterMovementIntent {
  readonly x: number;
  readonly y: number;
  readonly speed: number;
}

function scriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('CharacterScript requires a registered script identity.');
  return context.scriptId;
}

export class CharacterScript extends ScriptNode {
  protected readonly values: Readonly<Record<string, JsonValue>>;

  constructor(context: NodeConstructionContext) {
    super({
      runtimeId: context.runtimeId,
      name: context.name,
      scriptId: scriptId(context),
      exportedProperties: context.properties,
    });
    this.values = context.properties;
  }

  protected numberProperty(key: string, fallback: number): number {
    const value = this.values[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  protected stringProperty(key: string, fallback: string): string {
    const value = this.values[key];
    return typeof value === 'string' ? value : fallback;
  }

  protected jsonProperty(key: string): JsonValue | undefined {
    return this.values[key];
  }

  distanceSquared(from: CharacterPoint, to: CharacterPoint): number {
    const x = to.x - from.x;
    const y = to.y - from.y;
    return x * x + y * y;
  }

  movementToward(from: CharacterPoint, to: CharacterPoint, speed: number): CharacterMovementIntent {
    const x = to.x - from.x;
    const y = to.y - from.y;
    const length = Math.hypot(x, y);
    if (length === 0 || speed <= 0) return { x: 0, y: 0, speed: 0 };
    return { x: x / length, y: y / length, speed };
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): CharacterScript {
    return new CharacterScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}

