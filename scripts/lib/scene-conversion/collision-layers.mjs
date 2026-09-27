import { readFileSync } from 'node:fs';

/**
 * Converter view of the project collision layer table
 * (`src/game/content/physics/collision-layers.json`). Converters write layer
 * and mask bits only through `collisionBits(...)` so no scene data carries a
 * hand-picked number.
 */
const table = JSON.parse(readFileSync(new URL('../../../src/game/content/physics/collision-layers.json', import.meta.url), 'utf8'));
const values = new Map(table.layers.map((entry) => [entry.name, (2 ** (entry.layer - 1)) >>> 0]));

export function collisionBits(...names) {
  return names.reduce((bits, name) => {
    const value = values.get(name);
    if (value === undefined) throw new Error(`Unknown collision layer '${name}'`);
    return (bits | value) >>> 0;
  }, 0);
}

/** `{ collisionLayer, collisionMask }` properties for a node, by layer name. */
export function collision(layers, mask) {
  return { collisionLayer: collisionBits(...layers), collisionMask: collisionBits(...mask) };
}
