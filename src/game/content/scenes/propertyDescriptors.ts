import { collisionBits, DEFINED_COLLISION_BITS } from '../physics/CollisionLayers';
import type { JsonValue } from './resources/types';

export type PropertyValueDescriptor =
  | { readonly kind: 'boolean' }
  | { readonly kind: 'string'; readonly pattern?: RegExp; readonly minLength?: number; readonly maxLength?: number; /** Studio option list (e.g. 'effects') a 'select' inspector picks from; the value stays a plain string. */ readonly optionSource?: string }
  | { readonly kind: 'number'; readonly integer?: boolean; readonly min?: number; readonly max?: number; /** Value is a bit set over the named project collision layers; undefined bits are rejected. */ readonly collisionLayers?: boolean }
  | { readonly kind: 'enum'; readonly values: readonly string[] }
  | { readonly kind: 'vector2' }
  | { readonly kind: 'color' }
  | { readonly kind: 'json' }
  | { readonly kind: 'node-reference'; readonly capability?: string }
  | { readonly kind: 'resource-reference'; readonly resourceKinds?: readonly string[] }
  | { readonly kind: 'scene-reference'; readonly dynamic?: boolean };

export interface PropertyDescriptor {
  readonly key: string;
  readonly label: string;
  readonly help?: string;
  readonly group?: string;
  readonly units?: string;
  readonly value: PropertyValueDescriptor;
  readonly defaultValue?: JsonValue;
  readonly required?: boolean;
  readonly serialized: boolean;
  readonly inspector: 'checkbox' | 'text' | 'number' | 'select' | 'vector2' | 'color' | 'node' | 'resource' | 'scene' | 'json' | 'source-rect';
  readonly animation?: {
    readonly interpolation: 'step' | 'numeric';
    readonly domains: readonly ('physics' | 'render')[];
  };
  readonly overridable: boolean;
}

export interface SignalDescriptor {
  readonly id: string;
  readonly payload?: string;
}

export interface HandlerDescriptor {
  readonly id: string;
  readonly payload?: string;
}

export interface NodeTypeDescriptor {
  readonly type: string;
  readonly extends?: string;
  readonly capabilities?: readonly string[];
  readonly allowedParentTypes?: readonly string[];
  readonly allowedChildTypes?: readonly string[];
  readonly properties: readonly PropertyDescriptor[];
  readonly signals?: readonly SignalDescriptor[];
  readonly handlers?: readonly HandlerDescriptor[];
}

export interface ScriptDescriptor {
  readonly scriptId: string;
  readonly displayName: string;
  readonly description?: string;
  readonly sourcePath: string;
  readonly extends?: string;
  readonly capabilities?: readonly string[];
  readonly exclusiveCapabilities?: readonly string[];
  readonly references?: readonly ScriptReferenceDescriptor[];
  readonly properties: readonly PropertyDescriptor[];
  readonly signals?: readonly SignalDescriptor[];
  readonly handlers?: readonly HandlerDescriptor[];
}

export interface ScriptReferenceDescriptor {
  readonly key: string;
  readonly label: string;
  readonly required?: boolean;
  readonly expectedNodeType?: string;
  readonly expectedCapability?: string;
  readonly multiple?: boolean;
}

export interface DescriptorRegistry {
  readonly nodeTypes: ReadonlyMap<string, NodeTypeDescriptor>;
  readonly scripts: ReadonlyMap<string, ScriptDescriptor>;
}

export interface DescriptorIssue {
  readonly path: string;
  readonly message: string;
}

function nodeTypeChain(type: string, registry: DescriptorRegistry): readonly NodeTypeDescriptor[] {
  const chain: NodeTypeDescriptor[] = [];
  const visited = new Set<string>();
  let current = registry.nodeTypes.get(type);
  while (current && !visited.has(current.type)) {
    visited.add(current.type);
    chain.unshift(current);
    current = current.extends ? registry.nodeTypes.get(current.extends) : undefined;
  }
  return chain;
}

function scriptChain(scriptId: string, registry: DescriptorRegistry): readonly ScriptDescriptor[] {
  const chain: ScriptDescriptor[] = [];
  const visited = new Set<string>();
  let current = registry.scripts.get(scriptId);
  while (current && !visited.has(current.scriptId)) {
    visited.add(current.scriptId);
    chain.unshift(current);
    current = current.extends ? registry.scripts.get(current.extends) : undefined;
  }
  return chain;
}

export function nodeTypeIs(type: string, expectedType: string, registry: DescriptorRegistry): boolean {
  return nodeTypeChain(type, registry).some((descriptor) => descriptor.type === expectedType);
}

export function propertiesForNode(type: string, scriptId: string | undefined, registry: DescriptorRegistry): readonly PropertyDescriptor[] | undefined {
  const nodeChain = nodeTypeChain(type, registry);
  if (nodeChain.length === 0) return undefined;
  const merged = new Map<string, PropertyDescriptor>();
  for (const descriptor of nodeChain) for (const property of descriptor.properties) merged.set(property.key, property);
  if (scriptId) {
    for (const descriptor of scriptChain(scriptId, registry)) {
      for (const property of descriptor.properties) merged.set(property.key, property);
    }
  }
  return [...merged.values()];
}

export function signalsForNode(type: string, scriptId: string | undefined, registry: DescriptorRegistry): ReadonlyMap<string, SignalDescriptor> {
  const merged = new Map<string, SignalDescriptor>();
  for (const descriptor of nodeTypeChain(type, registry)) {
    for (const signal of descriptor.signals ?? []) merged.set(signal.id, signal);
  }
  if (scriptId) {
    for (const descriptor of scriptChain(scriptId, registry)) {
      for (const signal of descriptor.signals ?? []) merged.set(signal.id, signal);
    }
  }
  return merged;
}

export function handlersForScript(scriptId: string | undefined, registry: DescriptorRegistry): ReadonlyMap<string, HandlerDescriptor> {
  const merged = new Map<string, HandlerDescriptor>();
  if (!scriptId) return merged;
  for (const descriptor of scriptChain(scriptId, registry)) {
    for (const handler of descriptor.handlers ?? []) merged.set(handler.id, handler);
  }
  return merged;
}

/** Built-in node-type handlers (e.g. AudioStreamPlayer.play) merged with the attached script's handlers. */
export function handlersForNode(type: string, scriptId: string | undefined, registry: DescriptorRegistry): ReadonlyMap<string, HandlerDescriptor> {
  const merged = new Map<string, HandlerDescriptor>();
  for (const descriptor of nodeTypeChain(type, registry)) {
    for (const handler of descriptor.handlers ?? []) merged.set(handler.id, handler);
  }
  for (const [id, handler] of handlersForScript(scriptId, registry)) merged.set(id, handler);
  return merged;
}

/** Payload id a handler declares to accept (and ignore) any signal payload. */
export const ANY_SIGNAL_PAYLOAD = 'Any';

export function signalPayloadCompatible(signal: SignalDescriptor, handler: HandlerDescriptor): boolean {
  return handler.payload === ANY_SIGNAL_PAYLOAD || (signal.payload ?? 'void') === (handler.payload ?? 'void');
}

export function capabilitiesForNode(type: string, scriptId: string | undefined, registry: DescriptorRegistry): ReadonlySet<string> {
  const capabilities = new Set<string>();
  for (const descriptor of nodeTypeChain(type, registry)) {
    for (const capability of descriptor.capabilities ?? []) capabilities.add(capability);
  }
  if (scriptId) {
    for (const descriptor of scriptChain(scriptId, registry)) {
      for (const capability of descriptor.capabilities ?? []) capabilities.add(capability);
    }
  }
  return capabilities;
}

function duplicateIds(values: readonly string[]): string[] {
  const seen = new Set<string>();
  return values.filter((value) => seen.has(value) || !seen.add(value));
}

export function validateDescriptorRegistry(registry: DescriptorRegistry): readonly DescriptorIssue[] {
  const issues: DescriptorIssue[] = [];
  const validateProperties = (owner: string, properties: readonly PropertyDescriptor[]): void => {
    for (const duplicate of duplicateIds(properties.map((property) => property.key))) {
      issues.push({ path: owner, message: `duplicate property '${duplicate}'` });
    }
    for (const property of properties) {
      if (!property.serialized && property.defaultValue !== undefined) {
        issues.push({ path: `${owner}.${property.key}`, message: 'runtime-only property cannot declare a serialized default' });
      }
      if (property.animation?.interpolation === 'numeric' && !['number', 'vector2', 'color'].includes(property.value.kind)) {
        issues.push({ path: `${owner}.${property.key}`, message: `numeric interpolation is incompatible with ${property.value.kind}` });
      }
    }
  };
  for (const descriptor of registry.nodeTypes.values()) {
    validateProperties(`node:${descriptor.type}`, descriptor.properties);
    for (const duplicate of duplicateIds((descriptor.signals ?? []).map((signal) => signal.id))) {
      issues.push({ path: `node:${descriptor.type}`, message: `duplicate signal '${duplicate}'` });
    }
    if (descriptor.extends && !registry.nodeTypes.has(descriptor.extends)) {
      issues.push({ path: `node:${descriptor.type}`, message: `unknown base node type '${descriptor.extends}'` });
    }
    const visited = new Set<string>([descriptor.type]);
    let baseId = descriptor.extends;
    while (baseId) {
      if (visited.has(baseId)) { issues.push({ path: `node:${descriptor.type}`, message: 'node inheritance cycle' }); break; }
      visited.add(baseId);
      baseId = registry.nodeTypes.get(baseId)?.extends;
    }
  }
  for (const descriptor of registry.scripts.values()) {
    validateProperties(`script:${descriptor.scriptId}`, descriptor.properties);
    for (const duplicate of duplicateIds((descriptor.signals ?? []).map((signal) => signal.id))) {
      issues.push({ path: `script:${descriptor.scriptId}`, message: `duplicate signal '${duplicate}'` });
    }
    const base = descriptor.extends ? registry.scripts.get(descriptor.extends) : undefined;
    if (descriptor.extends && !base) {
      issues.push({ path: `script:${descriptor.scriptId}`, message: `unknown base script '${descriptor.extends}'` });
    }
    const visited = new Set<string>([descriptor.scriptId]);
    let baseId = descriptor.extends;
    while (baseId) {
      if (visited.has(baseId)) { issues.push({ path: `script:${descriptor.scriptId}`, message: 'script inheritance cycle' }); break; }
      visited.add(baseId);
      baseId = registry.scripts.get(baseId)?.extends;
    }
    if (base) {
      const inherited = new Map(scriptChain(base.scriptId, registry).flatMap((entry) => entry.properties).map((property) => [property.key, property]));
      for (const property of descriptor.properties) {
        const parent = inherited.get(property.key);
        if (parent && parent.value.kind !== property.value.kind) {
          issues.push({ path: `script:${descriptor.scriptId}.${property.key}`, message: `cannot change inherited type '${parent.value.kind}' to '${property.value.kind}'` });
        }
      }
      const inheritedSignals = new Set(scriptChain(base.scriptId, registry).flatMap((entry) => entry.signals ?? []).map((signal) => signal.id));
      for (const signal of descriptor.signals ?? []) {
        if (inheritedSignals.has(signal.id)) issues.push({ path: `script:${descriptor.scriptId}`, message: `duplicate inherited signal '${signal.id}'` });
      }
    }
  }
  return issues;
}

export function descriptorMap(properties: readonly PropertyDescriptor[]): ReadonlyMap<string, PropertyDescriptor> {
  return new Map(properties.map((property) => [property.key, property]));
}

const vector = (key: string, label: string, defaultValue: readonly [number, number]): PropertyDescriptor => ({
  key, label, value: { kind: 'vector2' }, defaultValue, serialized: true, inspector: 'vector2',
  animation: { interpolation: 'numeric', domains: ['physics', 'render'] }, overridable: true,
});

const resource = (key: string, label: string, kinds: readonly string[]): PropertyDescriptor => ({
  key, label, value: { kind: 'resource-reference', resourceKinds: kinds }, serialized: true, inspector: 'resource', overridable: true,
});

const boolean = (key: string, label: string, defaultValue: boolean): PropertyDescriptor => ({
  key, label, value: { kind: 'boolean' }, defaultValue, serialized: true, inspector: 'checkbox', overridable: true,
});

const number = (key: string, label: string, defaultValue: number, min?: number, max?: number): PropertyDescriptor => ({
  key, label, value: { kind: 'number', ...(min === undefined ? {} : { min }), ...(max === undefined ? {} : { max }) },
  defaultValue, serialized: true, inspector: 'number', animation: { interpolation: 'numeric', domains: ['physics', 'render'] }, overridable: true,
});

const collisionBitsProperty = (key: string, label: string, defaultValue: number, help: string): PropertyDescriptor => ({
  key, label, help, value: { kind: 'number', integer: true, min: 0, max: 0xffff_ffff, collisionLayers: true },
  defaultValue, serialized: true, inspector: 'number', overridable: true,
});

const AUDIO_PLAYER_HANDLERS: readonly HandlerDescriptor[] = [{ id: 'play', payload: ANY_SIGNAL_PAYLOAD }, { id: 'stop', payload: ANY_SIGNAL_PAYLOAD }];

const audioPlayerProperties = (): PropertyDescriptor[] => [
  { ...resource('stream', 'Audio Stream', ['audio']), required: true },
  { key: 'bus', label: 'Audio Bus', value: { kind: 'enum', values: ['effects', 'music', 'ambience'] }, defaultValue: 'effects', serialized: true, inspector: 'select', overridable: true },
  number('volume', 'Volume', 1, 0), number('pitch', 'Pitch', 1, 0.01), boolean('loop', 'Loop', false), boolean('autoplay', 'Autoplay', false),
  { ...number('pitchRandomness', 'Pitch Randomness', 0, 0, 0.9), help: 'Each one-shot play offsets pitch by a random amount within +/- this value.' },
  { key: 'polyphony', label: 'Max Overlapping Plays', value: { kind: 'number', integer: true, min: 1, max: 16 }, defaultValue: 4, serialized: true, inspector: 'number', overridable: true },
  { ...number('minIntervalMs', 'Min Retrigger Interval (ms)', 0, 0), help: 'Plays requested sooner than this after the previous one are dropped.' },
  { key: 'payloadFilter', label: 'Signal Payload Filter', help: 'Optional "field=value|value" test on the triggering signal payload (dotted field path). Only matching signals play or stop the stream.', value: { kind: 'string', pattern: /^$|^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*=[^=]+$/ }, defaultValue: '', serialized: true, inspector: 'text', overridable: true },
];

export function createCoreDescriptorRegistry(scripts: readonly ScriptDescriptor[] = []): DescriptorRegistry {
  const nodeTypes: NodeTypeDescriptor[] = [
    { type: 'Node', properties: [] },
    { type: 'Node2D', extends: 'Node', properties: [vector('position', 'Position', [0, 0]), vector('scale', 'Scale', [1, 1]), { key: 'rotation', label: 'Rotation', units: 'radians', help: 'Stored in radians like the runtime; the animation timeline and Keyframes section edit it in degrees.', value: { kind: 'number' }, defaultValue: 0, serialized: true, inspector: 'number', animation: { interpolation: 'numeric', domains: ['physics', 'render'] }, overridable: true }, { ...boolean('visible', 'Visible', true), animation: { interpolation: 'step', domains: ['physics', 'render'] } },
      { key: 'depthAnchor', label: 'Depth Anchor', value: { kind: 'vector2' }, serialized: true, inspector: 'vector2', overridable: true },
    ] },
    { type: 'Sprite2D', extends: 'Node2D', properties: [
      { ...resource('texture', 'Texture', ['texture', 'sprite-sheet']), required: true },
      { key: 'frame', label: 'Frame', value: { kind: 'number', integer: true, min: 0 }, defaultValue: 0, serialized: true, inspector: 'number', animation: { interpolation: 'step', domains: ['physics', 'render'] }, overridable: true },
      vector('origin', 'Origin', [0.5, 0.5]), vector('visualOffset', 'Visual Offset', [0, 0]),
      number('alpha', 'Alpha', 1, 0, 1),
      { key: 'tint', label: 'Tint', value: { kind: 'string', pattern: /^#[0-9a-f]{6}$/i }, defaultValue: '#ffffff', serialized: true, inspector: 'color', overridable: true },
      { ...boolean('flipX', 'Flip X', false), animation: { interpolation: 'step', domains: ['physics', 'render'] } },
      { ...boolean('flipY', 'Flip Y', false), animation: { interpolation: 'step', domains: ['physics', 'render'] } },
      { key: 'depthMode', label: 'Depth Mode', value: { kind: 'enum', values: ['world-sorted', 'explicit', 'relative'] }, defaultValue: 'world-sorted', serialized: true, inspector: 'select', overridable: true },
      { ...number('depthOffset', 'Relative Depth Offset', 0), animation: { interpolation: 'step', domains: ['physics', 'render'] } },
      { key: 'depthBand', label: 'Depth Band', value: { kind: 'enum', values: ['ground-terrain', 'ground-decals', 'world-entities', 'overhead-artwork', 'reveal-effects', 'screen-ui', 'editor-cursor', 'editor-drag-lift', 'editor-selection-marker', 'editor-template-overlay'] }, defaultValue: 'world-entities', serialized: true, inspector: 'select', overridable: true },
      number('depth', 'Explicit Depth', 0),
      { key: 'occlusionBounds', label: 'Occlusion Bounds', help: 'Source-frame pixels of the artwork that hides actors walking behind it (they show as a silhouette).', value: { kind: 'json' }, defaultValue: {}, serialized: true, inspector: 'source-rect', overridable: true },
      { key: 'depthBounds', label: 'Depth Bounds', help: 'Source-frame pixels of the footprint; its bottom edge (Y + H) is the line this sprite sorts front/behind by.', value: { kind: 'json' }, defaultValue: {}, serialized: true, inspector: 'source-rect', overridable: true },
    ] },
    { type: 'PhysicsBody2D', extends: 'Node2D', capabilities: ['physics-body'], properties: [
      collisionBitsProperty('collisionLayer', 'Collision Layer', collisionBits('world'), 'Named layers this body occupies.'),
      collisionBitsProperty('collisionMask', 'Collision Mask', collisionBits('world'), 'Named layers that block this body while it moves. A static body\'s mask is ignored.'),
      boolean('collisionEnabled', 'Collision Enabled', true),
    ] },
    { type: 'CharacterBody2D', extends: 'PhysicsBody2D', capabilities: ['character-body'], properties: [
      vector('velocity', 'Velocity', [0, 0]),
      { ...boolean('collideWorldBounds', 'Collide With World Bounds', true), help: 'Keep the body inside the loaded world\'s bounds.' },
      { ...boolean('allowWorldPassThrough', 'Allow World Pass-Through', false), help: 'Explicit opt-out of the scenes:check rule that an enabled CharacterBody2D mask must include the world layer.' },
    ] },
    { type: 'StaticBody2D', extends: 'PhysicsBody2D', properties: [] },
    { type: 'Area2D', extends: 'Node2D', capabilities: ['area'], properties: [
      collisionBitsProperty('collisionLayer', 'Collision Layer', collisionBits('world'), 'Named layers this area occupies.'),
      collisionBitsProperty('collisionMask', 'Collision Mask', DEFINED_COLLISION_BITS, 'Named layers this area detects.'),
      { ...boolean('monitoring', 'Monitoring', true), animation: { interpolation: 'step', domains: ['physics'] } }, boolean('monitorable', 'Monitorable', true),
    ], signals: [
      { id: 'body_entered', payload: 'PhysicsContact' }, { id: 'body_exited', payload: 'PhysicsContact' },
      { id: 'area_entered', payload: 'PhysicsContact' }, { id: 'area_exited', payload: 'PhysicsContact' },
    ] },
    { type: 'CollisionShape2D', extends: 'Node2D', capabilities: ['collision-shape'], allowedParentTypes: ['CharacterBody2D', 'StaticBody2D', 'Area2D'], properties: [
      { ...resource('shape', 'Shape', ['collision-shape']), required: true }, { ...boolean('disabled', 'Disabled', false), animation: { interpolation: 'step', domains: ['physics'] } },
      { key: 'angleRad', label: 'Geometry Angle', units: 'radians', value: { kind: 'number' }, serialized: true, inspector: 'number', animation: { interpolation: 'numeric', domains: ['physics'] }, overridable: true },
    ] },
    { type: 'TileMapLayer2D', extends: 'Node2D', properties: [
      { ...resource('tileData', 'Tile Data', ['tile-data']), required: true },
      number('tileSize', 'Tile Size', 64, 1),
      { key: 'seed', label: 'Visual Seed', value: { kind: 'number', integer: true }, defaultValue: 0, serialized: true, inspector: 'number', overridable: true },
      number('depth', 'Render Depth', 0),
      collisionBitsProperty('collisionLayer', 'Collision Layer', collisionBits('world'), 'Named layers the collidable tiles occupy.'),
      collisionBitsProperty('collisionMask', 'Collision Mask', 0, 'Unused: tile bodies are static, and a static body\'s mask is ignored.'),
      boolean('collisionEnabled', 'Collision Enabled', true),
      boolean('editorLocked', 'Editor Locked', false),
    ] },
    { type: 'Camera2D', extends: 'Node2D', properties: [number('zoom', 'Zoom', 1, 0.01), boolean('roundPixels', 'Round Pixels', true)] },
    { type: 'AnimationPlayer', extends: 'Node', properties: [
      { ...resource('library', 'Animation Library', ['animation-library']), required: true },
      { key: 'domain', label: 'Clock Domain', value: { kind: 'enum', values: ['physics', 'render'] }, defaultValue: 'render', serialized: true, inspector: 'select', overridable: true },
      { key: 'autoplay', label: 'Autoplay', value: { kind: 'string' }, serialized: true, inspector: 'text', overridable: true },
      { ...boolean('randomizeStart', 'Randomize Start Frame', false), help: 'Looping autoplay clips begin at a random frame so placed copies do not move in sync.' },
    ], signals: [{ id: 'animation_event', payload: 'AnimationEventEmission' }, { id: 'animation_finished', payload: 'string' }] },
    { type: 'AudioStreamPlayer', extends: 'Node', properties: audioPlayerProperties(), signals: [{ id: 'playback_finished' }], handlers: AUDIO_PLAYER_HANDLERS },
    { type: 'AudioStreamPlayer2D', extends: 'Node2D', properties: [
      ...audioPlayerProperties(),
      number('maxDistance', 'Maximum Distance', 800, 0.01), number('panDistance', 'Pan Distance', 400, 0.01),
      boolean('detached', 'Outlive Owner', false),
    ], signals: [{ id: 'playback_finished' }], handlers: AUDIO_PLAYER_HANDLERS },
    { type: 'ScriptNode', extends: 'Node', properties: [] },
    { type: 'Control', extends: 'Node', capabilities: ['control'], properties: [
      vector('anchorMin', 'Minimum Anchor', [0, 0]), vector('anchorMax', 'Maximum Anchor', [0, 0]),
      vector('offsetMin', 'Minimum Offset', [0, 0]), vector('offsetMax', 'Maximum Offset', [0, 0]),
      boolean('visible', 'Visible', true), boolean('focused', 'Focused', false), boolean('modal', 'Modal', false),
      boolean('consumeInput', 'Consume Input', false), boolean('processWhenPaused', 'Process When Paused', true),
      { key: 'inputPriority', label: 'Input Priority', value: { kind: 'number', integer: true }, defaultValue: 1000, serialized: true, inspector: 'number', overridable: true },
      { key: 'styleClass', label: 'Style Class', value: { kind: 'string' }, defaultValue: '', serialized: true, inspector: 'text', overridable: true },
      { key: 'ariaLabel', label: 'Accessible Label', value: { kind: 'string' }, defaultValue: '', serialized: true, inspector: 'text', overridable: true },
      { key: 'tooltip', label: 'Tooltip', value: { kind: 'string' }, defaultValue: '', serialized: true, inspector: 'text', overridable: true },
      { key: 'zIndex', label: 'Stack Order', value: { kind: 'number', integer: true }, defaultValue: 0, serialized: true, inspector: 'number', overridable: true },
      resource('theme', 'Theme', ['theme']),
    ] },
    { type: 'Container', extends: 'Control', capabilities: ['container'], properties: [
      { key: 'direction', label: 'Direction', value: { kind: 'enum', values: ['none', 'horizontal', 'vertical'] }, defaultValue: 'none', serialized: true, inspector: 'select', overridable: true },
      number('gap', 'Gap', 0, 0),
      { key: 'padding', label: 'Padding', value: { kind: 'json' }, defaultValue: [0, 0, 0, 0], serialized: true, inspector: 'json', overridable: true },
      { key: 'align', label: 'Cross Axis Alignment', value: { kind: 'enum', values: ['start', 'center', 'end', 'stretch'] }, defaultValue: 'stretch', serialized: true, inspector: 'select', overridable: true },
      { key: 'justify', label: 'Main Axis Alignment', value: { kind: 'enum', values: ['start', 'center', 'end', 'stretch', 'space-between'] }, defaultValue: 'start', serialized: true, inspector: 'select', overridable: true },
    ] },
    { type: 'TextureRect', extends: 'Control', capabilities: ['image-control'], properties: [
      resource('texture', 'Texture', ['texture', 'sprite-sheet']),
      { key: 'frame', label: 'Frame', value: { kind: 'number', integer: true, min: 0 }, defaultValue: 0, serialized: true, inspector: 'number', overridable: true },
      { key: 'fit', label: 'Fit', value: { kind: 'enum', values: ['contain', 'cover', 'fill', 'none'] }, defaultValue: 'contain', serialized: true, inspector: 'select', overridable: true },
      { key: 'alt', label: 'Alternative Text', value: { kind: 'string' }, defaultValue: '', serialized: true, inspector: 'text', overridable: true },
    ] },
    { type: 'Label', extends: 'Control', capabilities: ['text-control'], properties: [
      { key: 'text', label: 'Text', value: { kind: 'string' }, defaultValue: '', serialized: true, inspector: 'text', overridable: true },
      { key: 'tone', label: 'Tone', value: { kind: 'enum', values: ['default', 'muted', 'accent', 'info', 'warning', 'danger', 'special'] }, defaultValue: 'default', serialized: true, inspector: 'select', overridable: true },
      number('fontSize', 'Font Size', 14, 1), number('fontWeight', 'Font Weight', 400, 1),
      { key: 'textAlign', label: 'Text Alignment', value: { kind: 'enum', values: ['left', 'center', 'right'] }, defaultValue: 'left', serialized: true, inspector: 'select', overridable: true },
      boolean('wrap', 'Wrap Text', false),
    ] },
    { type: 'ProgressBar', extends: 'Control', capabilities: ['status-control'], properties: [
      number('value', 'Value', 0, 0), number('max', 'Maximum', 1, 0.000001),
      { key: 'label', label: 'Label', value: { kind: 'string' }, defaultValue: '', serialized: true, inspector: 'text', overridable: true },
      { key: 'tone', label: 'Tone', value: { kind: 'enum', values: ['default', 'muted', 'accent', 'info', 'warning', 'danger', 'special'] }, defaultValue: 'accent', serialized: true, inspector: 'select', overridable: true },
      boolean('showValue', 'Show Value', false),
    ] },
    { type: 'Slider', extends: 'Control', capabilities: ['value-control', 'focusable'], properties: [
      number('value', 'Value', 0), number('min', 'Minimum', 0), number('max', 'Maximum', 1), number('step', 'Step', 0.05, 0.000001),
      { key: 'label', label: 'Label', value: { kind: 'string' }, defaultValue: '', serialized: true, inspector: 'text', overridable: true },
      { key: 'tone', label: 'Tone', value: { kind: 'enum', values: ['default', 'muted', 'accent', 'info', 'warning', 'danger', 'special'] }, defaultValue: 'accent', serialized: true, inspector: 'select', overridable: true },
      boolean('disabled', 'Disabled', false),
    ], signals: [{ id: 'value_changed', payload: 'UiSliderChange' }] },
    { type: 'Button', extends: 'Label', capabilities: ['button-control', 'focusable'], properties: [boolean('disabled', 'Disabled', false)], signals: [{ id: 'pressed' }] },
    { type: 'ItemList', extends: 'Control', capabilities: ['list-control', 'focusable'], properties: [
      { key: 'items', label: 'Items', value: { kind: 'json' }, defaultValue: [], serialized: true, inspector: 'json', overridable: true },
      { key: 'selectedIndex', label: 'Selected Index', value: { kind: 'number', integer: true, min: -1 }, defaultValue: -1, serialized: true, inspector: 'number', overridable: true },
      { key: 'columns', label: 'Columns', value: { kind: 'number', integer: true, min: 1 }, defaultValue: 1, serialized: true, inspector: 'number', overridable: true },
      number('gap', 'Gap', 8, 0),
    ], signals: [{ id: 'item_selected', payload: 'UiListSelection' }, { id: 'item_secondary', payload: 'UiListSelection' }] },
    { type: 'GridContainer', extends: 'Container', capabilities: ['grid-control'], properties: [
      { key: 'columns', label: 'Columns', value: { kind: 'number', integer: true, min: 1 }, defaultValue: 1, serialized: true, inspector: 'number', overridable: true },
    ] },
    { type: 'ScrollContainer', extends: 'Container', capabilities: ['scroll-control'], properties: [
      { key: 'scrollAxis', label: 'Scroll Axis', value: { kind: 'enum', values: ['horizontal', 'vertical'] }, defaultValue: 'vertical', serialized: true, inspector: 'select', overridable: true },
    ] },
    { type: 'ModalRoot', extends: 'Container', capabilities: ['modal-control'], properties: [boolean('open', 'Open', false)], signals: [{ id: 'close_requested' }] },
  ];
  return {
    nodeTypes: new Map(nodeTypes.map((descriptor) => [descriptor.type, descriptor])),
    scripts: new Map(scripts.map((descriptor) => [descriptor.scriptId, descriptor])),
  };
}
