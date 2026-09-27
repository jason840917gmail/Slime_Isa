import collisionLayerTable from './collision-layers.json';

/**
 * Project-wide named physics layers, loaded from `collision-layers.json`.
 *
 * Godot semantics: layer N (1-based) occupies bit value `2^(N-1)`. A body's
 * `collisionLayer` says what it *is*; its `collisionMask` says what it
 * *detects* (for Area2D) or is *blocked by* (for moving bodies). Content,
 * converters and the editor refer to layers by name; raw numbers only exist
 * in serialized scene data.
 */
export interface CollisionLayerDefinition {
  readonly layer: number;
  readonly name: string;
  readonly value: number;
  readonly description: string;
}

interface CollisionLayerTableDocument {
  readonly version: number;
  readonly characterBodyRequiredMaskLayer: string;
  readonly layers: readonly { readonly layer: number; readonly name: string; readonly description?: string }[];
}

function parseTable(document: CollisionLayerTableDocument): {
  readonly layers: readonly CollisionLayerDefinition[];
  readonly byName: ReadonlyMap<string, CollisionLayerDefinition>;
  readonly definedBits: number;
  readonly characterBodyRequiredMask: number;
} {
  if (document.version !== 1) throw new Error(`Unsupported collision layer table version '${document.version}'`);
  const byName = new Map<string, CollisionLayerDefinition>();
  const usedLayers = new Set<number>();
  let definedBits = 0;
  const layers = document.layers.map((entry) => {
    if (!Number.isInteger(entry.layer) || entry.layer < 1 || entry.layer > 32) throw new Error(`Collision layer '${entry.name}' must use a layer number from 1 to 32`);
    if (!/^[a-z][a-z0-9-]*$/.test(entry.name)) throw new Error(`Collision layer name '${entry.name}' must be kebab-case`);
    if (byName.has(entry.name)) throw new Error(`Duplicate collision layer name '${entry.name}'`);
    if (usedLayers.has(entry.layer)) throw new Error(`Duplicate collision layer number ${entry.layer}`);
    const definition: CollisionLayerDefinition = { layer: entry.layer, name: entry.name, value: (2 ** (entry.layer - 1)) >>> 0, description: entry.description ?? '' };
    byName.set(entry.name, definition);
    usedLayers.add(entry.layer);
    definedBits = (definedBits | definition.value) >>> 0;
    return definition;
  });
  const required = byName.get(document.characterBodyRequiredMaskLayer);
  if (!required) throw new Error(`characterBodyRequiredMaskLayer '${document.characterBodyRequiredMaskLayer}' is not a defined collision layer`);
  return { layers, byName, definedBits, characterBodyRequiredMask: required.value };
}

const TABLE = parseTable(collisionLayerTable as CollisionLayerTableDocument);

export const COLLISION_LAYERS: readonly CollisionLayerDefinition[] = TABLE.layers;

/** Union of every bit a layer in the table defines. */
export const DEFINED_COLLISION_BITS: number = TABLE.definedBits;

/**
 * Bits every enabled CharacterBody2D mask must include unless the body opts
 * out explicitly (the solid-world layer: moving bodies must not walk through
 * walls by accident).
 */
export const CHARACTER_BODY_REQUIRED_MASK: number = TABLE.characterBodyRequiredMask;

export function collisionLayerValue(name: string): number {
  const definition = TABLE.byName.get(name);
  if (!definition) throw new Error(`Unknown collision layer '${name}'`);
  return definition.value;
}

/** Bit union of the named layers, e.g. `collisionBits('world', 'enemy')`. */
export function collisionBits(...names: readonly string[]): number {
  return names.reduce((bits, name) => (bits | collisionLayerValue(name)) >>> 0, 0);
}

/** Bits set in `value` that no layer in the table defines. */
export function undefinedCollisionBits(value: number): number {
  return ((value >>> 0) & ~DEFINED_COLLISION_BITS) >>> 0;
}

/** Names of the layers set in `value` (for editor display and diagnostics). */
export function collisionLayerNames(value: number): readonly string[] {
  return COLLISION_LAYERS.filter((layer) => ((value >>> 0) & layer.value) !== 0).map((layer) => layer.name);
}
