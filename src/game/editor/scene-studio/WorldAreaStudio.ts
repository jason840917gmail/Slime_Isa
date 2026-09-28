import type { MapEnemyAreaPerimeter } from '../../content/maps/mapFormat';
import { authoredNodeId, resourceId as toResourceId, type AuthoredNodeId } from '../../content/scenes/identifiers';
import type { CollisionShapeValue } from '../../content/scenes/resources/types';
import type { JsonValue, SceneDocument, SceneNodeDocument } from '../../content/scenes/types';
import { describePerimeter, enemySpawnPerimeterIssues, perimeterFromCollisionShape } from '../../content/scenes/worldAreaGeometry';
import { sceneMutationCommand, type SceneCommand } from './SceneCommand';
import type { ComposedSceneNode } from './SceneViewport';

/**
 * Scene Studio support for `game.world-area` nodes: which collision shapes
 * are an area's perimeter or stay shape (for viewport colouring), a live
 * summary with the same validation the world loader applies, and one-click
 * templates for new areas.
 */

export const WORLD_AREA_SCRIPT_ID = 'game.world-area';

export type WorldAreaShapeRole = 'perimeter' | 'stay' | 'safe' | 'wander';
export type WorldAreaTemplateKind = 'enemy-spawn' | 'enemy-safe-zone' | 'npc-wander';

function isRecord(value: JsonValue | undefined): value is { readonly [key: string]: JsonValue } {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/** Composed key of the node a world-area reference points at (same scoping as the packed resolver). */
export function referencedNodeKey(owner: ComposedSceneNode, property: string): string | undefined {
  const reference = owner.properties[property];
  if (!isRecord(reference) || typeof reference.nodeId !== 'string') return undefined;
  const nested = Array.isArray(reference.instancePath) ? reference.instancePath.filter((part): part is string => typeof part === 'string') : [];
  return `${[...owner.instancePath, ...nested].join('/')}:${reference.nodeId}`;
}

export function isWorldAreaScript(node: ComposedSceneNode): boolean {
  return node.scriptId === WORLD_AREA_SCRIPT_ID;
}

/** Shape node key → the role it plays for its world area. */
export function worldAreaShapeRoles(nodes: readonly ComposedSceneNode[]): ReadonlyMap<string, WorldAreaShapeRole> {
  const roles = new Map<string, WorldAreaShapeRole>();
  for (const script of nodes.filter(isWorldAreaScript)) {
    const kind = script.properties.areaKind;
    const outer = referencedNodeKey(script, 'shape');
    if (outer) roles.set(outer, kind === 'enemy-spawn' ? 'perimeter' : kind === 'npc-wander' ? 'wander' : 'safe');
    const stay = referencedNodeKey(script, 'stayShape');
    if (stay && kind === 'enemy-spawn') roles.set(stay, 'stay');
  }
  return roles;
}

/** Keys of the shapes a world-area script references, so selecting the script shows them. */
export function worldAreaShapeKeys(script: ComposedSceneNode): readonly string[] {
  return ['shape', 'stayShape'].flatMap((property) => referencedNodeKey(script, property) ?? []);
}

/** The world-area script that owns a node: the script itself, or the one using it as its area or a shape. */
export function owningWorldArea(node: ComposedSceneNode, nodes: readonly ComposedSceneNode[]): ComposedSceneNode | undefined {
  if (isWorldAreaScript(node)) return node;
  return nodes.find((candidate) => isWorldAreaScript(candidate)
    && (referencedNodeKey(candidate, 'area') === node.key || worldAreaShapeKeys(candidate).includes(node.key)));
}

export interface WorldAreaSummary {
  readonly kind: string;
  readonly lines: readonly string[];
  readonly issues: readonly string[];
}

/** What the game will load for this area, plus every problem that would stop the world loading. */
export function worldAreaSummary(
  script: ComposedSceneNode,
  nodes: readonly ComposedSceneNode[],
  shapeValue: (node: ComposedSceneNode) => CollisionShapeValue | undefined,
  /** Enemy types a spawn area may use; unknown names are reported. */
  enemyTypes?: ReadonlySet<string>,
): WorldAreaSummary {
  const kind = String(script.properties.areaKind ?? '');
  const byKey = new Map(nodes.map((node) => [node.key, node]));
  const lines: string[] = [];
  const issues: string[] = [];
  const resolve = (property: string, label: string): MapEnemyAreaPerimeter | undefined => {
    const key = referencedNodeKey(script, property);
    const node = key ? byKey.get(key) : undefined;
    if (!node) { issues.push(`${label} shape is not assigned`); return undefined; }
    if (node.type !== 'CollisionShape2D' || !node.global) { issues.push(`${label} must reference a CollisionShape2D`); return undefined; }
    const value = shapeValue(node);
    if (!value) { issues.push(`${label} shape has no collision-shape resource`); return undefined; }
    const result = perimeterFromCollisionShape(value, node.global);
    if (!result.perimeter) { issues.push(`${label}: ${result.issue}`); return undefined; }
    lines.push(`${label}: ${describePerimeter(result.perimeter)}`);
    return result.perimeter;
  };
  const outer = resolve('shape', kind === 'enemy-spawn' ? 'Pursue' : kind === 'npc-wander' ? 'Wander' : 'Safe zone');
  if (kind === 'enemy-safe-zone' && outer && outer.shape !== 'rectangle') issues.push('Safe zones must be rectangles');
  if (kind === 'enemy-spawn') {
    const stay = resolve('stayShape', 'Stay');
    if (outer && stay) issues.push(...enemySpawnPerimeterIssues(stay, outer).map((issue) => issue.charAt(0).toUpperCase() + issue.slice(1)));
    const data = isRecord(script.properties.data) ? script.properties.data : {};
    if (!Array.isArray(data.enemies) || data.enemies.length === 0) issues.push('Add at least one enemy');
    else if (enemyTypes) {
      for (const entry of data.enemies) {
        const type = isRecord(entry) ? entry.type : undefined;
        if (typeof type !== 'string' || !enemyTypes.has(type)) issues.push(`Unknown enemy type '${String(type ?? '')}'`);
      }
    }
  }
  if (kind === 'npc-wander') {
    const data = isRecord(script.properties.data) ? script.properties.data : {};
    if (typeof data.npcInstanceId !== 'string' || data.npcInstanceId.length === 0) issues.push('Choose the NPC that wanders here');
  }
  return { kind, lines, issues };
}

export interface WorldAreaTemplate {
  readonly kind: WorldAreaTemplateKind;
  readonly label: string;
  readonly description: string;
}

export const WORLD_AREA_TEMPLATES: readonly WorldAreaTemplate[] = [
  { kind: 'enemy-spawn', label: 'Enemy Spawn Area', description: 'Area2D with pursue + stay shapes and spawn settings; drag both shapes in the viewport.' },
  { kind: 'enemy-safe-zone', label: 'Enemy Safe Zone', description: 'Rectangle enemies will not enter.' },
  { kind: 'npc-wander', label: 'NPC Wander Area', description: 'Perimeter one placed NPC wanders inside; set its npcInstanceId.' },
];

const TEMPLATE_DEFAULTS: Readonly<Record<WorldAreaTemplateKind, {
  readonly idPrefix: string;
  readonly outer: CollisionShapeValue;
  readonly stay?: CollisionShapeValue;
  readonly data: JsonValue;
}>> = {
  'enemy-spawn': {
    idPrefix: 'enemy-area',
    outer: { shape: 'rectangle', width: 512, height: 384 },
    stay: { shape: 'rectangle', width: 256, height: 192 },
    data: { enemies: [{ type: 'worm-brawler', weight: 1, maxAlive: 3 }], intervalMs: 2500, maxPopulation: 3 },
  },
  'enemy-safe-zone': { idPrefix: 'enemy-safe', outer: { shape: 'rectangle', width: 384, height: 384 }, data: {} },
  'npc-wander': { idPrefix: 'npc-area', outer: { shape: 'circle', radius: 96 }, data: { npcInstanceId: '' } },
};

/** Area2D in the world's trigger layer that monitors nothing; matches converted world areas. */
const WORLD_AREA_LAYER = 512;

export function worldAreaTemplateCommand(
  document: SceneDocument,
  kind: WorldAreaTemplateKind,
  parentId: AuthoredNodeId,
  position: readonly [number, number],
): { readonly command: SceneCommand; readonly areaNodeId: AuthoredNodeId; readonly areaId: string } {
  const defaults = TEMPLATE_DEFAULTS[kind];
  const nodeIds = new Set(document.nodes.map((node) => node.id as string));
  const resourceIds = new Set((document.subresources ?? []).map((resource) => resource.resourceId as string));
  const areaIds = new Set(document.nodes.filter((node) => node.scriptId === WORLD_AREA_SCRIPT_ID).map((node) => String(node.properties.areaId)));
  let index = 1;
  let areaId = `${defaults.idPrefix}-${String(index).padStart(2, '0')}`;
  while (areaIds.has(areaId) || nodeIds.has(`area-${areaId}`)) areaId = `${defaults.idPrefix}-${String(++index).padStart(2, '0')}`;
  const areaNodeId = authoredNodeId(`area-${areaId}`);
  const scope = document.sceneId.replace(/^[^.]+\./, '');
  const resource = (suffix: string): string => {
    let candidate = `${scope}.${areaNodeId}.${suffix}`;
    for (let n = 2; resourceIds.has(candidate); n += 1) candidate = `${scope}.${areaNodeId}.${suffix}-${n}`;
    return candidate;
  };
  const outerResource = resource('shape');
  const stayResource = defaults.stay ? resource('stay-shape') : undefined;
  const shapeNodeId = authoredNodeId(`${areaNodeId}-shape`);
  const stayNodeId = authoredNodeId(`${areaNodeId}-stay-shape`);
  const scriptNodeId = authoredNodeId(`${areaNodeId}-script`);
  const order = document.nodes.filter((node) => node.parentId === parentId).length + document.instances.filter((instance) => instance.parentNodeId === parentId).length;
  const round = (value: number): number => Math.round(value);
  const nodes: SceneNodeDocument[] = [
    { id: areaNodeId, name: areaId, type: 'Area2D', parentId, order, properties: { position: [round(position[0]), round(position[1])], collisionLayer: WORLD_AREA_LAYER, collisionMask: 0, monitoring: false, monitorable: false } },
    { id: shapeNodeId, name: defaults.stay ? 'pursue-shape' : 'collision-shape', type: 'CollisionShape2D', parentId: areaNodeId, order: 0, properties: { shape: { resourceId: outerResource } } },
    ...(defaults.stay ? [{ id: stayNodeId, name: 'stay-shape', type: 'CollisionShape2D', parentId: areaNodeId, order: 1, properties: { shape: { resourceId: stayResource! } } } as SceneNodeDocument] : []),
    { id: scriptNodeId, name: 'world-area-script', type: 'ScriptNode', scriptId: WORLD_AREA_SCRIPT_ID, parentId: areaNodeId, order: defaults.stay ? 2 : 1, properties: {
      areaKind: kind, areaId, area: { nodeId: areaNodeId }, shape: { nodeId: shapeNodeId },
      ...(defaults.stay ? { stayShape: { nodeId: stayNodeId } } : {}), data: structuredClone(defaults.data),
    } } as SceneNodeDocument,
  ];
  const command = sceneMutationCommand(`Add ${areaId}`, (draft) => {
    if (!draft.nodes.some((node) => node.id === parentId)) throw new Error(`Parent '${parentId}' does not exist`);
    draft.nodes.push(...structuredClone(nodes));
    draft.subresources = [
      ...(draft.subresources ?? []),
      { version: 1, resourceId: toResourceId(outerResource), kind: 'collision-shape', value: structuredClone(defaults.outer) },
      ...(defaults.stay && stayResource ? [{ version: 1 as const, resourceId: toResourceId(stayResource), kind: 'collision-shape' as const, value: structuredClone(defaults.stay) }] : []),
    ];
    return { kind: 'node', nodeId: areaNodeId };
  });
  return { command, areaNodeId, areaId };
}

/** Converts a shape to another kind, keeping roughly the same footprint. */
export function convertShapeKind(value: CollisionShapeValue, kind: 'rectangle' | 'circle' | 'ellipse'): CollisionShapeValue {
  const width = value.shape === 'rectangle' ? value.width : value.shape === 'circle' ? value.radius * 2 : value.shape === 'ellipse' ? value.radiusX * 2 : value.outerRadius * 2;
  const height = value.shape === 'rectangle' ? value.height : value.shape === 'circle' ? value.radius * 2 : value.shape === 'ellipse' ? value.radiusY * 2 : value.outerRadius * 2;
  if (kind === 'rectangle') return { shape: 'rectangle', width, height };
  if (kind === 'circle') return { shape: 'circle', radius: Math.max(width, height) / 2 };
  return { shape: 'ellipse', radiusX: width / 2, radiusY: height / 2 };
}

export interface SpawnEnemyEntry {
  readonly type: string;
  readonly weight: number;
  readonly maxAlive?: number;
}

/** The spawn settings of an enemy-spawn area, normalised for the inspector editor. */
export function spawnSettings(script: ComposedSceneNode): { readonly enemies: readonly SpawnEnemyEntry[]; readonly intervalMs: number; readonly maxPopulation: number } {
  const data = isRecord(script.properties.data) ? script.properties.data : {};
  const enemies = Array.isArray(data.enemies) ? data.enemies.flatMap((entry) => isRecord(entry) ? [{
    type: typeof entry.type === 'string' ? entry.type : '',
    weight: typeof entry.weight === 'number' ? entry.weight : 1,
    ...(typeof entry.maxAlive === 'number' ? { maxAlive: entry.maxAlive } : {}),
  }] : []) : [];
  return {
    enemies,
    intervalMs: typeof data.intervalMs === 'number' ? data.intervalMs : 2500,
    maxPopulation: typeof data.maxPopulation === 'number' ? data.maxPopulation : 3,
  };
}

/** Returns the area's `data` with one settings edit applied, keeping any other keys. */
export function editAreaSettings(
  data: JsonValue | undefined,
  edit:
    | { readonly kind: 'enemy-field'; readonly index: number; readonly field: 'type' | 'weight' | 'maxAlive'; readonly value: string }
    | { readonly kind: 'enemy-add'; readonly type: string }
    | { readonly kind: 'enemy-remove'; readonly index: number }
    | { readonly kind: 'setting'; readonly key: 'intervalMs' | 'maxPopulation' | 'npcInstanceId'; readonly value: string },
): JsonValue {
  const current: Record<string, JsonValue> = isRecord(data) ? { ...data } : {};
  const enemies = Array.isArray(current.enemies) ? current.enemies.map((entry) => isRecord(entry) ? { ...entry } : {}) : [];
  const positiveInteger = (raw: string, label: string): number => {
    const value = Number(raw);
    if (!Number.isInteger(value) || value <= 0) throw new Error(`${label} must be a whole number above 0`);
    return value;
  };
  if (edit.kind === 'enemy-add') enemies.push({ type: edit.type, weight: 1, maxAlive: 1 });
  else if (edit.kind === 'enemy-remove') enemies.splice(edit.index, 1);
  else if (edit.kind === 'enemy-field') {
    const entry = enemies[edit.index];
    if (!entry) throw new Error('That enemy row no longer exists');
    if (edit.field === 'type') entry.type = edit.value;
    else if (edit.field === 'maxAlive' && edit.value.trim() === '') delete entry.maxAlive;
    else entry[edit.field] = positiveInteger(edit.value, edit.field === 'weight' ? 'Weight' : 'Max alive');
  } else if (edit.key === 'npcInstanceId') current.npcInstanceId = edit.value;
  else current[edit.key] = positiveInteger(edit.value, edit.key === 'intervalMs' ? 'Spawn interval' : 'Max population');
  if (edit.kind !== 'setting') current.enemies = enemies;
  return current;
}
