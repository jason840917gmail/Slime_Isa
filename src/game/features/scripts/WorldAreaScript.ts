import type { JsonValue } from '../../content/scenes/resources/types';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export type WorldAreaKind = 'enemy-safe-zone' | 'enemy-spawn' | 'npc-wander';

/** Typed ownership marker for scene-authored world areas. */
export class WorldAreaScript extends ScriptNode {
  readonly areaKind: WorldAreaKind;
  readonly areaId: string;
  readonly data: JsonValue;

  constructor(context: NodeConstructionContext) {
    if (!context.scriptId) throw new Error('WorldAreaScript requires a registered script identity.');
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: context.scriptId, exportedProperties: context.properties });
    const kind = context.properties.areaKind;
    if (kind !== 'enemy-safe-zone' && kind !== 'enemy-spawn' && kind !== 'npc-wander') {
      throw new Error(`World area '${context.runtimeId}' has invalid kind.`);
    }
    this.areaKind = kind;
    this.areaId = typeof context.properties.areaId === 'string' ? context.properties.areaId : '';
    this.data = structuredClone(context.properties.data ?? {});
  }
}
