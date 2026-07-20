# Authored map entity spawn points

## Status

- [ ] Planned

## Goal

Extend the authored map format so level designers can control exact enemy spawn locations while keeping the existing enemy population and respawn rules configurable per map.

## Requirements

- Add stable spawn-point IDs and exact `x`/`y` coordinates to map JSON.
- Let each point restrict the enemy types that may spawn there.
- Keep weights, population caps, spawn intervals, and respawn behavior authored in JSON.
- Update the map schema, runtime parser, validation script, editor, and enemy spawner together.
- Reject duplicate IDs, out-of-bounds points, unknown enemy types, and points inside safe zones.
- Do not fall back to hidden runtime spawn points when authored points are absent.

## Related house metadata

Add authored ownership and interaction metadata for houses, doors, and beds. Runtime house systems must consume that data instead of creating extra house or bed sprites.

## Acceptance criteria

- A designer can place and edit enemy spawn points in the map editor.
- Runtime enemies originate only from valid points in the loaded map JSON.
- Existing maps are migrated or explicitly remain on the current JSON-configured random-position behavior until migration.
- House interaction can be restored using authored metadata without procedurally painting objects.
