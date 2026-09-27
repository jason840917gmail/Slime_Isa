import { propertiesForNode, type DescriptorRegistry, type PropertyDescriptor } from '../../../content/scenes/propertyDescriptors';
import type { JsonValue } from '../../../content/scenes/types';
import type { AnimationDomain } from '../../../runtime/scene/animation/AnimationBinding';
import type { ComposedSceneNode } from '../SceneViewport';

/** A node an AnimationPlayer can bind, addressed by a Godot-style relative NodePath. */
export interface AnimationTarget {
  readonly key: string;
  readonly name: string;
  readonly type: string;
  readonly binding: string;
  readonly depth: number;
  readonly node: ComposedSceneNode;
  readonly properties: readonly PropertyDescriptor[];
}

function chain(byKey: ReadonlyMap<string, ComposedSceneNode>, key: string): ComposedSceneNode[] {
  const output: ComposedSceneNode[] = [];
  let current = byKey.get(key);
  while (current) {
    output.unshift(current);
    current = current.parentKey ? byKey.get(current.parentKey) : undefined;
  }
  return output;
}

/** Relative path from the player to a node: `..` climbs, names descend (`../AttackArea/right--primary`). */
export function relativeBinding(byKey: ReadonlyMap<string, ComposedSceneNode>, fromKey: string, toKey: string): string {
  const from = chain(byKey, fromKey);
  const to = chain(byKey, toKey);
  let shared = 0;
  while (shared < from.length && shared < to.length && from[shared].key === to[shared].key) shared += 1;
  const segments = [...Array.from({ length: from.length - shared }, () => '..'), ...to.slice(shared).map((node) => node.name)];
  return segments.length === 0 ? '.' : segments.join('/');
}

/** Resolves a binding relative to the player, the way `Node.get_node` does at runtime. */
export function resolveBinding(nodes: readonly ComposedSceneNode[], playerKey: string, binding: string): ComposedSceneNode | undefined {
  const byKey = new Map(nodes.map((node) => [node.key, node]));
  let current = byKey.get(playerKey);
  const absolute = binding.startsWith('/');
  if (absolute) {
    while (current?.parentKey) current = byKey.get(current.parentKey);
  }
  const segments = binding.split('/').filter((segment) => segment.length > 0);
  if (absolute && current && segments[0] === current.name) segments.shift();
  for (const segment of segments) {
    if (!current) return undefined;
    if (segment === '.') continue;
    if (segment === '..') { current = current.parentKey ? byKey.get(current.parentKey) : undefined; continue; }
    const parentKey: string = current.key;
    current = nodes.find((node) => node.parentKey === parentKey && node.name === segment);
  }
  return current;
}

export function animatableProperties(node: Pick<ComposedSceneNode, 'type' | 'scriptId'>, registry: DescriptorRegistry, domain: AnimationDomain): readonly PropertyDescriptor[] {
  return (propertiesForNode(node.type, node.scriptId, registry) ?? []).filter((descriptor) => descriptor.animation?.domains.includes(domain));
}

/** Every node the player can animate in its clock domain, in tree order. */
export function animationTargets(nodes: readonly ComposedSceneNode[], playerKey: string, registry: DescriptorRegistry, domain: AnimationDomain): readonly AnimationTarget[] {
  const byKey = new Map(nodes.map((node) => [node.key, node]));
  return nodes.flatMap((node) => {
    if (node.key === playerKey || node.type === 'ScriptNode') return [];
    const properties = animatableProperties(node, registry, domain);
    if (properties.length === 0) return [];
    return [{ key: node.key, name: node.name, type: node.type, binding: relativeBinding(byKey, playerKey, node.key), depth: chain(byKey, node.key).length - 1, node, properties }];
  });
}

/** Linear blending is available for numeric properties unless the track forces nearest. */
export function descriptorIsNumeric(descriptor: PropertyDescriptor | undefined): boolean {
  return descriptor?.animation?.interpolation === 'numeric';
}

/** The value a new key starts with: the node's authored value, then the descriptor default. */
export function initialKeyValue(node: ComposedSceneNode | undefined, descriptor: PropertyDescriptor): JsonValue {
  const authored = node?.properties[descriptor.key];
  if (authored !== undefined) return structuredClone(authored);
  if (descriptor.defaultValue !== undefined) return structuredClone(descriptor.defaultValue);
  switch (descriptor.value.kind) {
    case 'boolean': return false;
    case 'vector2': return [0, 0];
    case 'number': return 0;
    default: return null;
  }
}
