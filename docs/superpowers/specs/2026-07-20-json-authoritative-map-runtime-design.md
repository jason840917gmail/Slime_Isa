# JSON-authoritative map runtime

## Goal

Make authored map JSON the source of truth for map houses and for whether an area enables enemy spawning. Runtime systems must not add fallback houses, beds, enemies, or a training dummy when the map does not request them.

## Runtime behavior

- `MapBuilder` remains the only path that paints authored house objects from `map.objects`.
- `WorldScene` no longer invokes procedural house placement. Existing authored houses remain visible and collidable through `ObjectFactory`.
- Home, door, and bed interaction remains unavailable until the map format explicitly represents ownership and interaction metadata. The runtime must not infer these details from visual IDs or object order.
- `CombatController` creates an enemy spawner only when the loaded map contains `spawns`.
- Maps with `spawns` keep the existing weighted random spawning behavior configured by that JSON.
- Maps without `spawns` create no enemies.
- The automatic training dummy is removed. The existing debug hotkey may still create one explicitly during a development session.

## Documentation

- Mark the reported bug completed and summarize the solution in `docs/task/bugs.md`.
- Track authored enemy spawn coordinates and authored house interaction metadata
  in [`docs/task/ideas/completed/authored-map-entity-spawns.md`](../../task/ideas/completed/authored-map-entity-spawns.md).
- Add a dedicated task document describing that future map-format extension without implementing it now.

## Implementation constraint

Only files required for this fix may be modified. Existing unrelated edits and untracked files in the working tree must be preserved and must not be overwritten, reverted, or deleted.

## Validation

- Run the project map validation, strict TypeScript checks, and production build through the complete local check command.
- Smoke-test the authored starter map in the browser: it starts successfully
  and no unauthored monsters or training dummy appear.
- Smoke-test or inspect a map that contains `spawns` to ensure JSON-configured spawning remains enabled.
