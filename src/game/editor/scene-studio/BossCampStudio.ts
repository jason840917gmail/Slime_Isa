import type { CollisionShapeValue } from '../../content/scenes/resources/types';
import type { JsonValue, SceneDocument } from '../../content/scenes/types';
import { describePerimeter, perimeterFromCollisionShape } from '../../content/scenes/worldAreaGeometry';
import type { MapEnemyAreaPerimeter } from '../../content/maps/mapFormat';
import type { ComposedSceneNode } from './SceneViewport';
import { referencedNodeKey } from './WorldAreaStudio';

/**
 * Scene Studio support for boss camps (`game.boss-camp`): the link from an
 * encounter to the boss scene it spawns, where that boss appears, and the
 * activation/arena circles, validated the way the game uses them.
 */

export const BOSS_CAMP_SCRIPT_ID = 'game.boss-camp';

export type BossCampShapeRole = 'activation' | 'arena';

function isRecord(value: JsonValue | undefined): value is { readonly [key: string]: JsonValue } {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function isBossCampScript(node: ComposedSceneNode): boolean {
  return node.scriptId === BOSS_CAMP_SCRIPT_ID;
}

/** The boss scene a camp spawns (after instance overrides). */
export function bossSceneIdOf(script: ComposedSceneNode): string | undefined {
  const value = script.properties.bossScene;
  return isRecord(value) && typeof value.sceneId === 'string' && value.sceneId.length > 0 ? value.sceneId : undefined;
}

/** Shape node key → activation/arena, for every camp in the composed scene. */
export function bossCampShapeRoles(nodes: readonly ComposedSceneNode[]): ReadonlyMap<string, BossCampShapeRole> {
  const roles = new Map<string, BossCampShapeRole>();
  for (const script of nodes.filter(isBossCampScript)) {
    for (const [property, role] of [['activationArea', 'activation'], ['arenaArea', 'arena']] as const) {
      const areaKey = referencedNodeKey(script, property);
      for (const node of nodes) if (areaKey && node.parentKey === areaKey && node.type === 'CollisionShape2D') roles.set(node.key, role);
    }
  }
  return roles;
}

/** The camp a node belongs to: the camp script itself, or the camp in the same (instanced) scene. */
export function owningBossCamp(node: ComposedSceneNode, nodes: readonly ComposedSceneNode[]): ComposedSceneNode | undefined {
  if (isBossCampScript(node)) return node;
  const scope = node.instancePath.join('/');
  return nodes.find((candidate) => isBossCampScript(candidate) && candidate.instancePath.join('/') === scope);
}

/** World position the boss spawns at: the camp root plus the script's `spawn` offset (as BossCampScript does). */
export function bossSpawnPoint(script: ComposedSceneNode, byKey: ReadonlyMap<string, ComposedSceneNode>): readonly [number, number] | undefined {
  const owner = script.parentKey ? byKey.get(script.parentKey) : undefined;
  const origin = owner?.global?.position ?? script.parentGlobal?.position;
  if (!origin) return undefined;
  const spawn = script.properties.spawn;
  const offset = Array.isArray(spawn) && spawn.length === 2 && typeof spawn[0] === 'number' && typeof spawn[1] === 'number' ? spawn : [0, 0];
  return [origin[0] + (offset[0] as number), origin[1] + (offset[1] as number)];
}

export interface BossSceneInfo {
  readonly sceneId: string;
  readonly name: string;
  /** False when the scene has no enemy script, so the game could not spawn it as a boss. */
  readonly spawnable: boolean;
}

/** Display name and spawnability of a boss scene, read from its enemy script. */
export function bossSceneInfo(
  sceneId: string,
  document: SceneDocument | undefined,
  isEnemyScript: (scriptId: string) => boolean,
  fallbackName: string,
): BossSceneInfo {
  const script = document?.nodes.find((node) => node.scriptId !== undefined && isEnemyScript(node.scriptId));
  const displayName = script?.properties.displayName;
  return {
    sceneId,
    name: typeof displayName === 'string' && displayName.length > 0 ? displayName : fallbackName,
    spawnable: script !== undefined,
  };
}

export interface BossCampSummary {
  readonly boss?: BossSceneInfo;
  readonly lines: readonly string[];
  readonly issues: readonly string[];
  /** Whether the camp's shapes can be resized from the scene being edited. */
  readonly shapesEditableHere: boolean;
}

export function bossCampSummary(
  script: ComposedSceneNode,
  nodes: readonly ComposedSceneNode[],
  shapeValue: (node: ComposedSceneNode) => { readonly value: CollisionShapeValue; readonly editable: boolean } | undefined,
  boss: BossSceneInfo | undefined,
): BossCampSummary {
  const byKey = new Map(nodes.map((node) => [node.key, node]));
  const lines: string[] = [];
  const issues: string[] = [];
  let shapesEditableHere = true;
  if (!boss) issues.push('Boss Scene is not set');
  else if (!boss.spawnable) issues.push(`'${boss.sceneId}' has no enemy script, so it cannot be spawned as a boss`);
  const spawn = bossSpawnPoint(script, byKey);
  if (spawn) lines.push(`Boss spawns at ${Math.round(spawn[0])}, ${Math.round(spawn[1])}`);
  const perimeter = (property: string, label: string): MapEnemyAreaPerimeter | undefined => {
    const areaKey = referencedNodeKey(script, property);
    const shapeNode = nodes.find((node) => areaKey && node.parentKey === areaKey && node.type === 'CollisionShape2D');
    if (!shapeNode?.global) { issues.push(`${label} has no collision shape`); return undefined; }
    const shape = shapeValue(shapeNode);
    if (!shape) { issues.push(`${label} shape has no collision-shape resource`); return undefined; }
    if (!shape.editable) shapesEditableHere = false;
    const result = perimeterFromCollisionShape(shape.value, shapeNode.global);
    if (!result.perimeter) { issues.push(`${label}: ${result.issue}`); return undefined; }
    lines.push(`${label}: ${describePerimeter(result.perimeter)}`);
    return result.perimeter;
  };
  const activation = perimeter('activationArea', 'Activation');
  const arena = perimeter('arenaArea', 'Arena');
  if (activation?.shape === 'circle' && arena?.shape === 'circle'
    && Math.hypot(arena.x - activation.x, arena.y - activation.y) + arena.radius > activation.radius + 1e-6) {
    issues.push('The arena should fit inside the activation circle, or the boss can be left behind without despawning');
  }
  if (arena && spawn) {
    const inside = arena.shape === 'circle'
      ? Math.hypot(spawn[0] - arena.x, spawn[1] - arena.y) <= arena.radius
      : spawn[0] >= arena.x && spawn[0] <= arena.x + arena.w && spawn[1] >= arena.y && spawn[1] <= arena.y + arena.h;
    if (!inside) issues.push('The boss spawns outside its arena and would immediately walk back in');
  }
  return { ...(boss ? { boss } : {}), lines, issues, shapesEditableHere };
}
