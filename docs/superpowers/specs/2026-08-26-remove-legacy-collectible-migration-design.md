# Remove Legacy Collectible Progress Migration

## Goal

Remove the runtime-only migration that converts legacy resource-pile progress into collectible progress. Authored maps already use the current collectible archetypes, and this project no longer needs to preserve saves created before that conversion.

## Current Context

Authored map objects persist content under `objects[]`. The converted pile objects are already authored as `collectible.*` entries. The remaining `resource.stone-node` entries in `level-1`, `meadow-crossing`, and `tiktok` are active resource nodes and must remain unchanged.

The legacy path operates on saved runtime state instead of authored maps:

`WorldScene` → `CollectibleController.register()` → `WorldProgress.migrateLegacyCollectibleState()` → `migrateLegacyCollectibleMapState()`

Removing this path intentionally stops restoring `resources[instanceId]` entries whose old stage was `pile` or `depleted` as collectible state.

## Design

### Collectible runtime state

- `CollectibleController.register()` reads only `progress.collectibleState()`.
- Remove `migrateLegacyCollectibleState()` from the `WorldProgress` class and its public context interface.
- Delete `CollectibleProgressMigration.ts`.
- Remove tests that directly exercise the deleted migration. Keep tests for current-format collectible registration, collection, depletion, and source-resource behavior.

### Resource-node legacy branches

The same pre-collectible transition left compatibility branches in `ResourceNodeController`. Remove the old `pile` stage registration path, `restoreLegacySingleDrop()`, and the `resource.wood-pile` / `resource.stone-pile` ID remapping in dynamic-drop restoration. Keep the current `node`, `destroyed`, and `depleted` paths because active resource nodes still use them.

Remove `pile` from the current `ResourceProgressStage` and save-schema resource-stage unions/guards. The v4 composite-key migration at the save boundary remains, but it accepts only the current resource-node stages; unsupported legacy `pile` entries are ignored rather than revived.

### Authored maps

- Do not convert or rewrite the existing map files because their collectible content is already in the current format.
- Keep active `resource.stone-node` objects.
- Run the map validator after the cleanup to verify that no authored map relies on the removed runtime migration.

### Compatibility audit

Classify migration-like code rather than deleting it indiscriminately:

- Retain `SaveRepository` migrations that still read older storage envelopes or flat resource progress, because they are the save-system boundary for supported older storage formats.
- Retain weapon migration and normalization because old weapon documents remain an explicitly supported editor/runtime input and have focused tests.
- Remove the resource-node helpers identified above because they are tied only to the unsupported pre-collectible format.
- Remove any additional helper found to be both unused and tied only to an unsupported format, provided the call sites and tests confirm it is orphaned.

## Data flow after cleanup

For a current collectible map object, registration uses saved state from `world.maps[mapId].collectibles[instanceId]` when present, otherwise the authored initial state or catalog default. Legacy resource entries are no longer translated by collectible registration.

Collection continues to persist through `setCollectibleState()`, which emits `world.progress.changed`; the existing save system remains responsible for writing the current-format state.

## Error handling

No new error behavior is needed. Invalid save data continues to be handled by the existing save-schema validation. An old resource entry that has no current collectible entry is ignored by collectible registration, matching the intentional decision to drop pre-collectible save compatibility.

## Verification

- `pnpm typecheck`
- `pnpm assets:check`
- `pnpm maps:check`
- Relevant collectible and persistence tests
- An explicit authored-content search confirming there are no `resource.*-pile` map objects, plus a runtime assertion that collectible registration uses only current-format collectible state.
- `pnpm check` when the focused checks pass
- Final repository search for references to `CollectibleProgressMigration`, `migrateLegacyCollectibleState`, the `pile` resource stage, and legacy resource-pile ID remapping

## Acceptance criteria

- No production code imports or calls the deleted collectible migration.
- No production resource-node code restores the unsupported `pile` stage or remaps legacy resource-pile IDs.
- Current resource progress contains only `node`, `destroyed`, or `depleted` stages; the supported v4 boundary migration still handles those stages.
- All authored maps validate and retain their intended active resource nodes and current collectible objects.
- Current-format collectible persistence still works.
- The audit identifies which migration/compatibility helpers remain intentionally supported and which unused helpers were removed.
