import Ajv2020, { type ErrorObject } from 'ajv/dist/2020';

import { CHARACTER_BODY_REQUIRED_MASK, collisionLayerNames, undefinedCollisionBits } from '../physics/CollisionLayers';
import sceneSchema from './scene.schema.json';
import { SERIALIZED_ID_PATTERN } from './identifiers';
import type { DescriptorRegistry, PropertyDescriptor } from './propertyDescriptors';
import { descriptorMap, nodeTypeIs, propertiesForNode, validateDescriptorRegistry } from './propertyDescriptors';
import type { NodeReferenceDocument, SceneDocument, SceneNodeDocument } from './types';
import type { JsonValue } from './resources/types';
import type { SceneResourceDocument } from './resources/types';
import { parseTileMapDataResource } from './resources/TileMapDataResource';
import { parseTileSetResource } from './resources/TileSetResource';

export interface SceneValidationIssue {
  readonly path: string;
  readonly message: string;
}

export interface SceneValidationContext {
  readonly registry: DescriptorRegistry;
  readonly hasAsset?: (assetId: string) => boolean;
  readonly hasResource?: (resourceId: string) => boolean;
  readonly getResourceKind?: (resourceId: string) => string | undefined;
}

const ajv = new Ajv2020({ allErrors: true, strict: true });
const validateStructure = ajv.compile(sceneSchema);

function schemaIssue(error: ErrorObject): SceneValidationIssue {
  return { path: error.instancePath || '/', message: error.message ?? error.keyword };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function validatePropertyDocumentValue(value: JsonValue, descriptor: PropertyDescriptor, path: string, context: SceneValidationContext): readonly SceneValidationIssue[] {
  const issues: SceneValidationIssue[] = [];
  const invalid = (message: string): void => { issues.push({ path, message }); };
  switch (descriptor.value.kind) {
    case 'boolean': if (typeof value !== 'boolean') invalid('expected boolean'); break;
    case 'string': {
      if (typeof value !== 'string') invalid('expected string');
      else if (descriptor.value.minLength !== undefined && value.length < descriptor.value.minLength) invalid(`must contain at least ${descriptor.value.minLength} characters`);
      else if (descriptor.value.maxLength !== undefined && value.length > descriptor.value.maxLength) invalid(`must contain at most ${descriptor.value.maxLength} characters`);
      else if (descriptor.value.pattern && !descriptor.value.pattern.test(value)) invalid('does not match the required pattern');
      break;
    }
    case 'number': {
      if (typeof value !== 'number' || !Number.isFinite(value)) invalid('expected finite number');
      else if (descriptor.value.integer && !Number.isInteger(value)) invalid('expected integer');
      else if (descriptor.value.min !== undefined && value < descriptor.value.min) invalid(`must be >= ${descriptor.value.min}`);
      else if (descriptor.value.max !== undefined && value > descriptor.value.max) invalid(`must be <= ${descriptor.value.max}`);
      else if (descriptor.value.collisionLayers && undefinedCollisionBits(value) !== 0) {
        invalid(`uses collision bits 0x${undefinedCollisionBits(value).toString(16)} that no named layer in collision-layers.json defines`);
      }
      break;
    }
    case 'enum': if (typeof value !== 'string' || !descriptor.value.values.includes(value)) invalid(`expected one of ${descriptor.value.values.join(', ')}`); break;
    case 'vector2': if (!Array.isArray(value) || value.length !== 2 || value.some((entry) => typeof entry !== 'number' || !Number.isFinite(entry))) invalid('expected [x, y] finite-number tuple'); break;
    case 'color': if (typeof value !== 'string' || !/^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/i.test(value)) invalid('expected #RRGGBB or #RRGGBBAA color'); break;
    case 'node-reference': if (!isRecord(value) || typeof value.nodeId !== 'string' || (value.instancePath !== undefined && !Array.isArray(value.instancePath))) invalid('expected stable node reference'); break;
    case 'resource-reference': {
      if (!isRecord(value) || typeof value.resourceId !== 'string') invalid('expected resource reference');
      else if (context.hasResource && !context.hasResource(value.resourceId)) invalid(`unknown resource '${value.resourceId}'`);
      else if (descriptor.value.resourceKinds && context.getResourceKind) {
        const kind = context.getResourceKind(value.resourceId);
        if (kind && !descriptor.value.resourceKinds.includes(kind)) invalid(`resource kind '${kind}' is incompatible`);
      }
      break;
    }
    case 'scene-reference': if (!isRecord(value) || typeof value.sceneId !== 'string') invalid('expected scene reference'); break;
    case 'json': break;
  }
  return issues;
}

function localReferenceExists(reference: NodeReferenceDocument, nodes: ReadonlyMap<string, SceneNodeDocument>): boolean {
  return (reference.instancePath?.length ?? 0) > 0 || nodes.has(reference.nodeId);
}

const SCALE_MESSAGE = 'scale must be positive; mirror sprites with flipX/flipY instead of a negative scale';

/** Node2D (vector) and Control (number) scales must be positive, as the runtime enforces. */
function positiveScale(value: unknown): boolean {
  if (value === undefined) return true;
  if (typeof value === 'number') return value > 0;
  return !Array.isArray(value) || value.every((component) => typeof component !== 'number' || component > 0);
}

export function validateSceneDocument(value: unknown, context: SceneValidationContext): readonly SceneValidationIssue[] {
  if (!validateStructure(value)) return (validateStructure.errors ?? []).map(schemaIssue);
  const scene = value as unknown as SceneDocument;
  const issues: SceneValidationIssue[] = validateDescriptorRegistry(context.registry).map((issue) => ({ ...issue }));
  const localResources = new Map<string, SceneResourceDocument>();
  for (const [index, resource] of (scene.subresources ?? []).entries()) {
    if (localResources.has(resource.resourceId)) issues.push({ path: `/subresources/${index}/resourceId`, message: `duplicate subresource ID '${resource.resourceId}'` });
    localResources.set(resource.resourceId, resource);
  }
  const resourceContext: SceneValidationContext = {
    ...context,
    // Inline resources supplement an external catalog. Their presence must not
    // make every non-inline reference invalid when no catalog is available yet.
    hasResource: context.hasResource
      ? (resourceId) => localResources.has(resourceId) || Boolean(context.hasResource?.(resourceId))
      : undefined,
    getResourceKind: context.getResourceKind || localResources.size > 0
      ? (resourceId) => localResources.get(resourceId)?.kind ?? context.getResourceKind?.(resourceId)
      : undefined,
  };
  for (const [index, resource] of (scene.subresources ?? []).entries()) {
    for (const issue of validateSceneResourceDocument(resource, resourceContext)) {
      issues.push({ path: `/subresources/${index}${issue.path === '/' ? '' : issue.path}`, message: issue.message });
    }
  }
  const nodes = new Map<string, SceneNodeDocument>();
  for (const [index, node] of scene.nodes.entries()) {
    if (nodes.has(node.id)) issues.push({ path: `/nodes/${index}/id`, message: `duplicate node ID '${node.id}'` });
    nodes.set(node.id, node);
    if (!positiveScale(node.properties.scale)) issues.push({ path: `/nodes/${index}/properties/scale`, message: SCALE_MESSAGE });
  }
  const roots = scene.nodes.filter((node) => node.parentId === null);
  if (roots.length !== 1) issues.push({ path: '/nodes', message: `expected exactly one root, found ${roots.length}` });
  if (!nodes.has(scene.rootNodeId)) issues.push({ path: '/rootNodeId', message: `unknown root node '${scene.rootNodeId}'` });
  else if (nodes.get(scene.rootNodeId)?.parentId !== null) issues.push({ path: '/rootNodeId', message: 'root node must have parentId null' });

  const instances = new Set<string>();
  const persistenceKeys = new Set<string>();
  for (const [index, instance] of scene.instances.entries()) {
    if (instances.has(instance.instanceId)) issues.push({ path: `/instances/${index}/instanceId`, message: `duplicate instance ID '${instance.instanceId}'` });
    instances.add(instance.instanceId);
    if (instance.persistenceKey !== undefined) {
      if (persistenceKeys.has(instance.persistenceKey)) issues.push({ path: `/instances/${index}/persistenceKey`, message: `duplicate persistence key '${instance.persistenceKey}'` });
      persistenceKeys.add(instance.persistenceKey);
    }
    if (!nodes.has(instance.parentNodeId)) issues.push({ path: `/instances/${index}/parentNodeId`, message: `unknown parent node '${instance.parentNodeId}'` });
    const overrideKeys = new Set<string>();
    for (const [overrideIndex, override] of instance.overrides.entries()) {
      const key = `${override.sourceInstancePath.join('/')}|${override.sourceNodeId}|${override.property}`;
      if (overrideKeys.has(key)) issues.push({ path: `/instances/${index}/overrides/${overrideIndex}`, message: 'duplicate override target/property' });
      overrideKeys.add(key);
      if (override.property === 'scale' && !positiveScale(override.value)) {
        issues.push({ path: `/instances/${index}/overrides/${overrideIndex}/value`, message: SCALE_MESSAGE });
      }
    }
  }

  for (const [index, node] of scene.nodes.entries()) {
    const nodePath = `/nodes/${index}`;
    if (node.parentId !== null && !nodes.has(node.parentId)) issues.push({ path: `${nodePath}/parentId`, message: `unknown parent node '${node.parentId}'` });
    const seen = new Set<string>([node.id]);
    let parentId = node.parentId;
    while (parentId !== null) {
      if (seen.has(parentId)) { issues.push({ path: `${nodePath}/parentId`, message: 'node hierarchy cycle' }); break; }
      seen.add(parentId);
      parentId = nodes.get(parentId)?.parentId ?? null;
    }
    const type = context.registry.nodeTypes.get(node.type);
    if (!type) { issues.push({ path: `${nodePath}/type`, message: `unknown node type '${node.type}'` }); continue; }
    if (node.type === 'ScriptNode' && !node.scriptId) issues.push({ path: `${nodePath}/scriptId`, message: 'ScriptNode requires scriptId' });
    if (node.type !== 'ScriptNode' && node.scriptId !== undefined) issues.push({ path: `${nodePath}/scriptId`, message: 'scriptId is valid only on ScriptNode' });
    if (node.scriptId && !context.registry.scripts.has(node.scriptId)) issues.push({ path: `${nodePath}/scriptId`, message: `unknown script '${node.scriptId}'` });
    const parentType = node.parentId ? nodes.get(node.parentId)?.type : undefined;
    if (parentType && type.allowedParentTypes && !type.allowedParentTypes.some((allowed) => nodeTypeIs(parentType, allowed, context.registry))) issues.push({ path: `${nodePath}/parentId`, message: `${node.type} cannot be parented to ${parentType}` });
    const parentDescriptor = parentType ? context.registry.nodeTypes.get(parentType) : undefined;
    if (parentDescriptor?.allowedChildTypes && !parentDescriptor.allowedChildTypes.some((allowed) => nodeTypeIs(node.type, allowed, context.registry))) issues.push({ path: `${nodePath}/parentId`, message: `${parentType} cannot contain ${node.type}` });
    const descriptors = propertiesForNode(node.type, node.scriptId, context.registry);
    if (!descriptors) continue;
    const byKey = descriptorMap(descriptors);
    for (const [key, propertyValue] of Object.entries(node.properties)) {
      const descriptor = byKey.get(key);
      if (!descriptor || !descriptor.serialized) issues.push({ path: `${nodePath}/properties/${key}`, message: 'unknown or runtime-only property' });
      else {
        issues.push(...validatePropertyDocumentValue(propertyValue, descriptor, `${nodePath}/properties/${key}`, resourceContext));
        if (descriptor.value.kind === 'node-reference' && isRecord(propertyValue) && typeof propertyValue.nodeId === 'string') {
          const instancePath = Array.isArray(propertyValue.instancePath) ? propertyValue.instancePath : [];
          if (instancePath.length === 0 && !nodes.has(propertyValue.nodeId)) issues.push({ path: `${nodePath}/properties/${key}`, message: `node '${propertyValue.nodeId}' does not resolve` });
          if (instancePath.length > 0 && typeof instancePath[0] === 'string' && !instances.has(instancePath[0])) issues.push({ path: `${nodePath}/properties/${key}`, message: `instance '${instancePath[0]}' does not resolve` });
        }
      }
    }
    for (const descriptor of descriptors) if (descriptor.required && node.properties[descriptor.key] === undefined) issues.push({ path: `${nodePath}/properties/${descriptor.key}`, message: 'required property is missing' });
    if (nodeTypeIs(node.type, 'CharacterBody2D', context.registry)) {
      const resolved = (key: string): JsonValue | undefined => node.properties[key] ?? byKey.get(key)?.defaultValue;
      const mask = resolved('collisionMask');
      if (resolved('collisionEnabled') !== false && resolved('allowWorldPassThrough') !== true
        && typeof mask === 'number' && ((mask >>> 0) & CHARACTER_BODY_REQUIRED_MASK) !== CHARACTER_BODY_REQUIRED_MASK) {
        issues.push({
          path: `${nodePath}/properties/collisionMask`,
          message: `enabled CharacterBody2D mask must include the '${collisionLayerNames(CHARACTER_BODY_REQUIRED_MASK).join("', '")}' layer (or set allowWorldPassThrough: true)`,
        });
      }
    }
  }

  const childrenByParent = new Map<string, Array<{ name: string; order: number; path: string; type?: string }>>();
  const addChild = (parent: string, child: { name: string; order: number; path: string; type?: string }): void => {
    const siblings = childrenByParent.get(parent) ?? [];
    siblings.push(child);
    childrenByParent.set(parent, siblings);
  };
  scene.nodes.forEach((node, index) => { if (node.parentId) addChild(node.parentId, { name: node.name, order: node.order, path: `/nodes/${index}`, type: node.type }); });
  scene.instances.forEach((instance, index) => addChild(instance.parentNodeId, { name: instance.name, order: instance.order, path: `/instances/${index}` }));
  for (const [parentId, children] of childrenByParent) {
    const names = new Set<string>();
    const orders = children.map((child) => child.order).sort((left, right) => left - right);
    children.forEach((child) => { if (names.has(child.name)) issues.push({ path: `${child.path}/name`, message: `duplicate sibling name '${child.name}' under '${parentId}'` }); names.add(child.name); });
    if (orders.some((order, index) => order !== index)) issues.push({ path: parentId, message: `child order must be the dense sequence 0..${children.length - 1}` });
  }

  for (const [index, connection] of (scene.connections ?? []).entries()) {
    if (!localReferenceExists(connection.source, nodes)) issues.push({ path: `/connections/${index}/source`, message: `source node '${connection.source.nodeId}' does not resolve` });
    if (!localReferenceExists(connection.target, nodes)) issues.push({ path: `/connections/${index}/target`, message: `target node '${connection.target.nodeId}' does not resolve` });
  }
  return issues;
}

export function canonicalSceneJson(scene: SceneDocument): string {
  return `${JSON.stringify(scene, null, 2)}\n`;
}

export function validateSceneResourceDocument(value: unknown, context: Pick<SceneValidationContext, 'hasAsset' | 'hasResource' | 'getResourceKind'> = {}): readonly SceneValidationIssue[] {
  if (!isRecord(value)) return [{ path: '/', message: 'expected resource object' }];
  const issues: SceneValidationIssue[] = [];
  const baseFields = ['version', 'resourceId', 'kind'];
  const kindFields: Readonly<Record<string, readonly string[]>> = {
    texture: ['assetId', 'frame'],
    'sprite-sheet': ['assetId', 'frameWidth', 'frameHeight', 'frameCount'],
    'collision-shape': ['value'],
    'animation-library': ['animations'],
    audio: ['assetId', 'variants'],
    'tile-set': ['tiles'],
    'tile-data': ['tileSet', 'columns', 'rows', 'cells'],
    font: ['assetId'],
    theme: ['values'],
  };
  const allowed = new Set([...baseFields, ...(typeof value.kind === 'string' ? kindFields[value.kind] ?? [] : [])]);
  for (const key of Object.keys(value)) if (!allowed.has(key)) issues.push({ path: `/${key}`, message: `field is not valid for resource kind '${String(value.kind)}'` });
  if (value.version !== 1) issues.push({ path: '/version', message: 'expected resource version 1' });
  if (typeof value.resourceId !== 'string' || !SERIALIZED_ID_PATTERN.test(value.resourceId)) issues.push({ path: '/resourceId', message: 'expected stable resource ID' });
  const media = ['texture', 'sprite-sheet', 'audio', 'font'];
  if (typeof value.kind !== 'string' || !Object.hasOwn(kindFields, value.kind)) issues.push({ path: '/kind', message: 'expected known resource kind' });
  if (media.includes(String(value.kind))) {
    if (typeof value.assetId !== 'string') issues.push({ path: '/assetId', message: 'media resource requires assetId' });
    else if (context.hasAsset && !context.hasAsset(value.assetId)) issues.push({ path: '/assetId', message: `unknown raw-media asset '${value.assetId}'` });
  }
  if (value.kind === 'audio' && value.variants !== undefined) {
    if (!Array.isArray(value.variants)) issues.push({ path: '/variants', message: 'expected an array of asset IDs' });
    else for (const [index, variant] of value.variants.entries()) {
      if (typeof variant !== 'string') issues.push({ path: `/variants/${index}`, message: 'expected asset ID' });
      else if (context.hasAsset && !context.hasAsset(variant)) issues.push({ path: `/variants/${index}`, message: `unknown raw-media asset '${variant}'` });
    }
  }
  if (value.kind === 'sprite-sheet') {
    if (!Number.isInteger(value.frameWidth) || Number(value.frameWidth) < 1) issues.push({ path: '/frameWidth', message: 'expected positive integer' });
    if (!Number.isInteger(value.frameHeight) || Number(value.frameHeight) < 1) issues.push({ path: '/frameHeight', message: 'expected positive integer' });
    if (value.frameCount !== undefined && (!Number.isInteger(value.frameCount) || Number(value.frameCount) < 1)) issues.push({ path: '/frameCount', message: 'expected positive integer' });
  }
  if (value.kind === 'collision-shape') {
    const geometry = isRecord(value.value) ? value.value : {};
    const shape = geometry.shape;
    const positive = (entry: unknown): boolean => typeof entry === 'number' && Number.isFinite(entry) && entry > 0;
    if (shape === 'rectangle' && (!positive(geometry.width) || !positive(geometry.height))) issues.push({ path: '/value', message: 'rectangle requires positive width and height' });
    else if (shape === 'circle' && !positive(geometry.radius)) issues.push({ path: '/value', message: 'circle requires positive radius' });
    else if (shape === 'ellipse' && (!positive(geometry.radiusX) || !positive(geometry.radiusY))) issues.push({ path: '/value', message: 'ellipse requires positive radii' });
    else if (shape === 'sector') {
      const finite = (entry: unknown): entry is number => typeof entry === 'number' && Number.isFinite(entry);
      const angleRad = geometry.angleRad;
      const arcWidthRad = geometry.arcWidthRad;
      const innerRadius = geometry.innerRadius;
      const outerRadius = geometry.outerRadius;
      if (!finite(angleRad) || !finite(arcWidthRad) || arcWidthRad <= 0 || arcWidthRad > Math.PI * 2
        || !finite(innerRadius) || innerRadius < 0 || !positive(outerRadius) || innerRadius >= Number(outerRadius)) {
        issues.push({ path: '/value', message: 'sector requires finite angleRad, 0 < arcWidthRad <= 2π, and 0 <= innerRadius < outerRadius' });
      }
    }
    else if (!['rectangle', 'circle', 'ellipse', 'sector'].includes(String(shape))) issues.push({ path: '/value', message: 'collision shape resource requires known shape geometry' });
  }
  if (value.kind === 'animation-library' && !isRecord(value.animations)) issues.push({ path: '/animations', message: 'animation library requires animations' });
  if (value.kind === 'tile-set') {
    if (!isRecord(value.tiles)) issues.push({ path: '/tiles', message: 'tile set requires tiles' });
    else {
      try {
        const parsed = parseTileSetResource(value as unknown as Extract<SceneResourceDocument, { kind: 'tile-set' }>);
        if (context.hasAsset) {
          for (const [tileId, tile] of Object.entries(parsed.tiles)) {
            for (const assetId of tile.assetIds) {
              if (!context.hasAsset(assetId)) issues.push({ path: `/tiles/${tileId}/assetIds`, message: `unknown raw-media asset '${assetId}'` });
            }
          }
        }
      } catch (error) {
        issues.push({ path: '/tiles', message: error instanceof Error ? error.message : String(error) });
      }
    }
  }
  if (value.kind === 'tile-data') {
    if (typeof value.tileSet !== 'string') issues.push({ path: '/tileSet', message: 'tile data requires tileSet resource ID' });
    else if (context.hasResource && !context.hasResource(value.tileSet)) issues.push({ path: '/tileSet', message: `unknown resource '${value.tileSet}'` });
    else {
      // Like resource-reference properties, only a known, different kind is an error:
      // tile data embedded in a scene may be validated before the shared TileSet catalog is known.
      const tileSetKind = context.getResourceKind?.(value.tileSet);
      if (tileSetKind !== undefined && tileSetKind !== 'tile-set') issues.push({ path: '/tileSet', message: 'tileSet must reference a tile-set resource' });
    }
    if (!Number.isSafeInteger(value.columns) || Number(value.columns) < 1) issues.push({ path: '/columns', message: 'tile data requires positive integer columns' });
    if (!Number.isSafeInteger(value.rows) || Number(value.rows) < 1) issues.push({ path: '/rows', message: 'tile data requires positive integer rows' });
    if (!Array.isArray(value.cells)) issues.push({ path: '/cells', message: 'tile data requires cells' });
    else {
      try {
        parseTileMapDataResource(value as unknown as Extract<SceneResourceDocument, { kind: 'tile-data' }>);
      } catch (error) {
        issues.push({ path: '/cells', message: error instanceof Error ? error.message : String(error) });
      }
    }
  }
  if (value.kind === 'theme' && !isRecord(value.values)) issues.push({ path: '/values', message: 'theme requires values' });
  return issues;
}

export function assertValidSceneDocument(value: unknown, context: SceneValidationContext): asserts value is SceneDocument {
  const issues = validateSceneDocument(value, context);
  if (issues.length > 0) throw new Error(issues.map((issue) => `${issue.path}: ${issue.message}`).join('\n'));
}

export function assertValidSceneResourceDocument(value: unknown, context: Pick<SceneValidationContext, 'hasAsset' | 'hasResource' | 'getResourceKind'> = {}): asserts value is SceneResourceDocument {
  const issues = validateSceneResourceDocument(value, context);
  if (issues.length > 0) throw new Error(issues.map((issue) => `${issue.path}: ${issue.message}`).join('\n'));
}
