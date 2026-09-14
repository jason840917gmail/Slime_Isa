import type { DescriptorRegistry } from '../../content/scenes/propertyDescriptors';

export interface SceneCreationEntry {
  readonly kind: 'node' | 'script';
  readonly id: string;
  readonly label: string;
  readonly description: string;
  readonly sourcePath?: string;
}

export interface SceneAssemblyTemplate {
  readonly id: string;
  readonly label: string;
  readonly description: string;
  readonly nodeTypes: readonly string[];
}

export function sceneCreationEntries(registry: DescriptorRegistry, search = ''): readonly SceneCreationEntry[] {
  const query = search.trim().toLowerCase();
  const entries: SceneCreationEntry[] = [
    ...[...registry.nodeTypes.values()].map((descriptor) => ({ kind: 'node' as const, id: descriptor.type, label: descriptor.type, description: descriptor.extends ? `Extends ${descriptor.extends}` : 'Base scene node' })),
    ...[...registry.scripts.values()].map((descriptor) => ({ kind: 'script' as const, id: descriptor.scriptId, label: descriptor.displayName, description: descriptor.description ?? 'Registered behavior script', sourcePath: descriptor.sourcePath })),
  ];
  return entries.filter((entry) => !query || `${entry.id} ${entry.label} ${entry.description}`.toLowerCase().includes(query))
    .sort((left, right) => left.kind.localeCompare(right.kind) || left.label.localeCompare(right.label));
}

export const COMMON_SCENE_TEMPLATES: readonly SceneAssemblyTemplate[] = [
  { id: 'visual-body', label: 'Visual body', description: 'A generic movable body, sprite, and collision shape.', nodeTypes: ['CharacterBody2D', 'Sprite2D', 'CollisionShape2D'] },
  { id: 'sensor', label: 'Sensor', description: 'A generic area with a collision shape.', nodeTypes: ['Area2D', 'CollisionShape2D'] },
  { id: 'presentation', label: 'Presentation', description: 'Animation and audio presentation nodes.', nodeTypes: ['AnimationPlayer', 'AudioStreamPlayer2D'] },
];
