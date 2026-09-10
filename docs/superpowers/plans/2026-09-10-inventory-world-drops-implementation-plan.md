# Inventory World Drops Implementation Plan

**Design:** `docs/superpowers/specs/2026-09-10-inventory-world-drops-design.md`

## Sequence

1. Add explicit item ground-presentation metadata and catalog validation.
2. Add collectible object/manifest entries for current non-equipment items
   that do not yet have physical pickup definitions.
3. Extend map runtime save data and `WorldProgress` with player-created drop
   records, monotonic IDs, migration defaults, and mutation helpers.
4. Add a focused deterministic placement helper and `InventoryDropController`
   for drop/restore/collection lifecycle and rollback.
5. Extend collectible state-change ownership so resource and inventory drops
   update their respective persistent owner without coupling the collectible
   controller to either feature.
6. Compose the controller in `WorldScene` and route inventory drop actions to
   it using player position, facing, blocked-cell checks, and the shared
   `WorldDropSpawner`.
7. Add Drop N and Drop All controls to non-equipment inventory details while
   preserving Remove and Use behavior.
8. Add the deferred authored weapon-drop feature to the game roadmap.
9. Add focused persistence, controller, collectible, and UI contract tests;
   run content validation, typecheck, focused suites, and production build.
