import type { AuthoredNodeId } from '../../content/scenes/identifiers';
import type { SceneCommand } from './SceneCommand';
import { sceneMutationCommand } from './SceneCommand';

export interface ViewportTransform {
  readonly position: readonly [number, number];
  readonly rotation: number;
  readonly scale: readonly [number, number];
}

export function validateViewportTransform(nodeType: string, transform: ViewportTransform, shape?: 'circle' | 'ellipse' | 'rectangle' | 'sector'): readonly string[] {
  const values = [...transform.position, transform.rotation, ...transform.scale];
  const issues: string[] = [];
  if (values.some((value) => !Number.isFinite(value))) issues.push('Transform values must be finite');
  if (transform.scale.some((value) => value === 0)) issues.push('Scale cannot be zero');
  if (['CharacterBody2D', 'StaticBody2D'].includes(nodeType) && transform.rotation !== 0) issues.push(`${nodeType} rotation is unsupported by the Phaser physics backend`);
  if (shape === 'circle' && transform.scale[0] !== transform.scale[1]) issues.push('Circle collision shapes require uniform scale');
  return issues;
}

export function transformNodeCommand(nodeId: AuthoredNodeId, nodeType: string, transform: ViewportTransform, shape?: 'circle' | 'ellipse' | 'rectangle' | 'sector'): SceneCommand {
  return sceneMutationCommand(`Transform ${nodeId}`, (draft) => {
    const issues = validateViewportTransform(nodeType, transform, shape);
    if (issues.length > 0) throw new Error(issues.join('\n'));
    const node = draft.nodes.find((candidate) => candidate.id === nodeId);
    if (!node) throw new Error(`Node '${nodeId}' does not exist`);
    draft.nodes = draft.nodes.map((candidate) => candidate.id === nodeId ? { ...candidate, properties: { ...candidate.properties, position: [...transform.position], rotation: transform.rotation, scale: [...transform.scale] } } : candidate);
    return { kind: 'node', nodeId };
  });
}
