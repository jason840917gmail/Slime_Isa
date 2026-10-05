/**
 * Per-node-type conversion. `convertNode(ctx)` returns
 * { type, props: [[key, value]], nodePaths: string[], children: generated[] }
 * where `generated` children are extra nodes the converter adds (tile
 * collision bodies, control captions) as { name, type, props, children }.
 *
 * Property conversion is a pure function of the node's (merged) properties,
 * so instance overrides are converted by diffing the result with and without
 * the override (see scene.mjs).
 */
import { gd } from './tscn.mjs';
import { convertSpriteProps } from './sprite.mjs';
import { convertShape } from './shapes.mjs';
import { convertAudioProps } from './audio.mjs';
import { convertAnimationPlayerProps } from './animation.mjs';
import { convertTileLayer } from './tiles.mjs';
import { convertScriptProps } from './script-props.mjs';
import { CONTROL_TYPES, controlGodotType, convertControl } from './controls.mjs';

const vec = (value, fallback) => (Array.isArray(value) && value.length === 2 ? value : fallback);

/** Phaser descriptor default for Area2D masks: every defined layer. */
const AREA_DEFAULT_MASK = 2047;

/** Godot type name for a JSON node. */
export function godotType(node) {
  switch (node.type) {
    case 'ScriptNode': return 'Node';
    case 'TileMapLayer2D': return 'TileMapLayer';
    default: return CONTROL_TYPES.has(node.type) ? controlGodotType(node) : node.type;
  }
}

/** Position of a non-root node: authored + the re-anchoring shift of root children. */
function shiftedPosition(ctx) {
  const [x, y] = vec(ctx.props.position, [0, 0]);
  const [dx, dy] = ctx.scene.childShift(ctx.node);
  return [x + dx, y + dy];
}

/**
 * Root position of a re-anchored scene: the feet are the origin, so the
 * node sits at (Phaser position + anchor·scale).
 */
function rootPosition(ctx) {
  const [x, y] = vec(ctx.props.position, [0, 0]);
  const anchor = ctx.scene.depthAnchor;
  if (!anchor || ctx.node.id !== ctx.scene.root.id) return [x, y];
  const [sx, sy] = vec(ctx.props.scale, [1, 1]);
  return [x + anchor[0] * sx, y + anchor[1] * sy];
}

function nodePosition(ctx) {
  return ctx.node.id === ctx.scene.root.id ? rootPosition(ctx) : shiftedPosition(ctx);
}

/** Container-like Node2D-derived nodes y-sort unless the scene draws as one unit. */
function ySortProps(ctx, props) {
  if (ctx.scene.ySorted) props.push(['y_sort_enabled', true]);
}

function rootMetadata(ctx, props) {
  if (ctx.node.id !== ctx.scene.root.id) {
    if (ctx.props.depthAnchor) ctx.warn('nested-depth-anchor', `${ctx.label}: depthAnchor on a non-root node is not re-anchored`);
    return;
  }
  if (ctx.scene.depthAnchor) {
    const [ax, ay] = ctx.scene.depthAnchor;
    props.push(['metadata/depth_anchor', gd.vec2(Math.round(ax * 1e6) / 1e6, Math.round(ay * 1e6) / 1e6)]);
  }
}

function convertNode2D(ctx) {
  const props = [];
  if (ctx.props.visible === false) props.push(['visible', false]);
  ySortProps(ctx, props);
  ctx.node2d(props, { position: nodePosition(ctx) });
  rootMetadata(ctx, props);
  return { props };
}

function collisionObjectProps(ctx, props, { layer, mask }) {
  if (layer !== 1) props.push(['collision_layer', layer]);
  if (mask !== 1) props.push(['collision_mask', mask]);
}

function convertArea(ctx) {
  const p = ctx.props;
  const props = [];
  ySortProps(ctx, props);
  ctx.node2d(props, { position: nodePosition(ctx) });
  collisionObjectProps(ctx, props, { layer: p.collisionLayer ?? 1, mask: p.collisionMask ?? AREA_DEFAULT_MASK });
  if (p.monitoring === false) props.push(['monitoring', false]);
  if (p.monitorable === false) props.push(['monitorable', false]);
  rootMetadata(ctx, props);
  return { props };
}

function convertStaticBody(ctx) {
  const p = ctx.props;
  const props = [];
  ySortProps(ctx, props);
  ctx.node2d(props, { position: nodePosition(ctx) });
  collisionObjectProps(ctx, props, { layer: p.collisionLayer ?? 1, mask: p.collisionMask ?? 1 });
  rootMetadata(ctx, props);
  return { props };
}

function convertCharacterBody(ctx) {
  const p = ctx.props;
  const props = [];
  ySortProps(ctx, props);
  ctx.node2d(props, { position: nodePosition(ctx) });
  collisionObjectProps(ctx, props, { layer: p.collisionLayer ?? 1, mask: p.collisionMask ?? 1 });
  props.push(['motion_mode', 1]);
  // Arcade keeps the tangential velocity at any angle into a wall; Godot's default 15° would stop it dead.
  props.push(['wall_min_slide_angle', gd.float(0)]);
  const [vx, vy] = vec(p.velocity, [0, 0]);
  if (vx || vy) props.push(['velocity', gd.vec2(vx, vy)]);
  if (p.collideWorldBounds !== undefined) props.push(['metadata/collide_world_bounds', Boolean(p.collideWorldBounds)]);
  rootMetadata(ctx, props);
  return { props };
}

function convertCollisionShape(ctx) {
  const p = ctx.props;
  const props = [];
  const parent = ctx.scene.parentOf(ctx.node);
  const resource = p.shape?.resourceId ? ctx.resource(p.shape.resourceId, 'collision-shape') : null;
  let rotation = 0;
  if (resource) {
    const converted = convertShape(resource, parent?.type, p.angleRad);
    props.push(['shape', converted.shape]);
    if (converted.rotation !== undefined) rotation = converted.rotation;
    if (converted.concave) ctx.warn('concave-sector', `${ctx.label}: concave sector converted to segments`);
  } else {
    ctx.warn('shape-missing', `${ctx.label}: no collision-shape resource`);
  }
  if (p.rotation) ctx.warn('rotated-shape', `${ctx.label}: shape rotation ${p.rotation} ignored (Phaser forbids rotated shapes)`);
  ctx.node2d(props, { position: shiftedPosition(ctx), rotation, ignoreRotation: true });
  if (p.disabled) props.push(['disabled', true]);
  return { props };
}

function convertAudio(ctx, is2d) {
  const props = convertAudioProps(ctx, is2d);
  if (is2d) ctx.node2d(props, { position: shiftedPosition(ctx) });
  return { props };
}

function convertTileMap(ctx) {
  const { props, children } = convertTileLayer(ctx);
  return { props, children };
}

function convertScript(ctx) {
  return convertScriptProps(ctx);
}

const CONVERTERS = {
  Node2D: convertNode2D,
  Sprite2D: (ctx) => ({ props: convertSpriteProps(ctx) }),
  Area2D: convertArea,
  StaticBody2D: convertStaticBody,
  CharacterBody2D: convertCharacterBody,
  CollisionShape2D: convertCollisionShape,
  AnimationPlayer: (ctx) => ({ props: convertAnimationPlayerProps(ctx) }),
  AudioStreamPlayer: (ctx) => convertAudio(ctx, false),
  AudioStreamPlayer2D: (ctx) => convertAudio(ctx, true),
  TileMapLayer2D: convertTileMap,
  ScriptNode: convertScript,
  Camera2D: (ctx) => {
    const props = [];
    ctx.node2d(props, { position: nodePosition(ctx) });
    if (typeof ctx.props.zoom === 'number') props.push(['zoom', gd.vec2(ctx.props.zoom, ctx.props.zoom)]);
    return { props };
  },
};

export function convertNode(ctx) {
  const node = ctx.node;
  const converter = CONVERTERS[node.type] ?? (CONTROL_TYPES.has(node.type) ? convertControl : null);
  if (!converter) {
    ctx.warn('unknown-node-type', `${ctx.label}: node type '${node.type}' is not converted (emitted as Node)`);
    return { type: 'Node', props: [], nodePaths: [], children: [] };
  }
  const result = converter(ctx);
  return { type: godotType(node), props: result.props, nodePaths: result.nodePaths ?? [], children: result.children ?? [] };
}
