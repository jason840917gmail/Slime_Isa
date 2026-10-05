# Authored enemy spawn areas

## Status

- [x] Core implementation complete
- [x] Browser smoke coverage complete
- [x] Production maps migrated to authored enemy camps

## Goal

Let level designers author enemy camps directly on the map. Each camp owns its
enemy roster and population rules, shows its boundaries in the map editor, and
keeps enemies leashed to the authored space instead of letting them chase the
player across the whole map.

## Runtime contract

Maps may define `enemySpawnAreas`. Each area has:

- a stable `id`;
- a `stayPerimeter`, either a circle (`x`, `y`, `radius`) or rectangle
  (`x`, `y`, `w`, `h`), where enemies spawn and settle;
- a same-shaped, containing `pursuePerimeter`, which activates the camp and
  limits how far an enemy may pursue;
- weighted enemy types with optional per-type `maxAlive`;
- `intervalMs` respawn cooldown and `maxPopulation`.

When the player is inside a camp's pursue perimeter, that camp may refill up to
its own population cap using its own roster. When the player leaves, enemies
stop chasing and return to the stay perimeter. Enemies that are pushed outside
the stay perimeter are also directed home. Areas take precedence over the
legacy player-relative `spawns` block; maps without authored areas retain the
legacy behavior during migration.

## Editor workflow

1. Press `M` or click **Enemy Area**.
2. Choose rectangle or circle for the next camp.
3. Drag on the map. The editor creates an amber stay perimeter and an expanded
   cyan pursue perimeter.
4. Click-drag an existing camp to move both perimeters together.
5. Use **Edit selected** to change either perimeter's dimensions, enemy types,
   weights, per-type caps, respawn cooldown, or population cap.
6. Click **Delete selected**, confirm the prompt, then save normally.

The camp overlays are visible only while the Enemy Area tool is selected. Amber
means stay; cyan means pursue.

## Validation and persistence

- Area IDs must be unique within a map.
- Both perimeters must fit inside map bounds, use the same shape, and have
  positive dimensions.
- The stay perimeter must be fully contained by the pursue perimeter.
- Each area must have at least one valid weighted enemy entry, a positive
  cooldown, and a positive population cap.
- Runtime loading, the editor save endpoint, and `maps:check` all validate the
  same structural rules. Runtime/editor reference validation rejects unknown
  enemy IDs.

## Related house metadata

Add authored ownership and interaction metadata for houses, doors, and beds.
Runtime house systems must consume that data instead of creating extra house or
bed sprites.

## Completion notes

The editor workflow, runtime boundary behavior, focused browser coverage, and
production-map migration are complete for the authored enemy-camp slice.
