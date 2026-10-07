# Named Save, Load, and Reset Implementation Plan

## Status

P.1–P.4 are implemented and locally exercised. Post-review hardening now keeps
Reset Run non-mutating until the destination handoff commits, keeps save-index
entries metadata-only, validates saved positions against authored map bounds,
prompts before applying browser recovery, reports corrupt named records, and
uses the authored Level 1 spawn directly. Repository and schema automation now
covers eight focused scenarios. P.5 manual round-trip verification remains before
this plan is complete. This plan delivers Roadmap P.1–P.5 before additional
persistent maps, encounters, homes, rewards, and gates expand the current save
contract.

## Player outcome

The player can begin from one intentional initial state, review existing save
records, overwrite a selected record or create a new named snapshot, load a
selected snapshot later, and reset the active run to the authored Level 1 map
plus the initial player state.

One snapshot restores one coherent moment:

`player + inventory + equipment + quests + current location + every visited map`

The authored files under `src/game/content/maps/` are never changed by gameplay.
They are immutable map defaults. Runtime changes live only in the active session,
the recovery autosave, or a named save snapshot.

## Clarified behavior

| Action/data | Exact meaning |
|---|---|
| Authored map | Immutable baseline loaded from `src/game/content/maps/<mapId>.map.json` |
| Initial player state | Content-owned stats, inventory, equipment, quests, location, and spawn rules for a new run |
| Active session | Mutable in-memory player and multi-map runtime state currently being played |
| Recovery autosave | One replaceable crash/browser-close recovery record; never creates named save history |
| Save Game | Shows existing records and lets the player explicitly overwrite one or create a new named snapshot |
| Load Game | Validates and migrates one selected snapshot, then restores its player and all map states |
| Reset Run | Discards only active/recovery progress, restores the initial player, and loads authored `level-1`; named saves remain |
| Delete Save | Explicitly removes only the selected named snapshot after confirmation |

The current Development Tools **Restart Map** button is semantically incorrect:
it saves and reloads the current state. Replace it during this work with the
three explicit actions above. If a development-only reload action remains useful,
label it **Reload Current Session** so it cannot be confused with reset.

## Browser storage decision

The Phaser game runs in a browser, which cannot silently create arbitrary files
on the user's filesystem. Treat each manual snapshot as a separate save-file
record in the persistence repository. Give every record a stable generated ID
and a player-entered display name.

Use independent storage keys initially so one corrupt snapshot does not prevent
the index or other saves from loading:

```text
slime-isa:save-index:v1
slime-isa:save:<saveId>
slime-isa:recovery
```

Keep the repository interface backend-neutral. Runtime map deltas are small
because authored terrain and unchanged objects are not duplicated. If save size
later approaches browser limits, move the repository implementation to IndexedDB
without changing the SaveSystem or UI contracts. Add Export/Import JSON as a
follow-up if players need physical `.json` files for backup or transfer.

## Save model

Use an explicit schema rather than extending the current cast-based envelope.
The exact names may change during implementation, but ownership and nesting must
remain equivalent to this model:

```ts
interface NamedSaveMetadata {
  readonly saveId: string;
  readonly name: string;
  readonly createdAt: number;
  readonly updatedAt: number;
  readonly schemaVersion: number;
  readonly currentMapId: string;
  readonly playerLevel: number;
  readonly playTimeMs: number;
}

interface GameLocationData {
  readonly areaId: string;
  readonly mapId: string;
  readonly x: number;
  readonly y: number;
  readonly facing: 'up' | 'down' | 'left' | 'right';
}

interface MapRuntimeStateData {
  readonly resources: Record<string, ResourceProgressStateData>;
  readonly completedEncounterIds: readonly string[];
  readonly openedRewardIds: readonly string[];
  readonly unlockedGateIds: readonly string[];
  readonly objectStates: Record<string, unknown>;
}

interface GameSaveData {
  readonly player: GameStateData;
  readonly inventory: readonly InventorySlot[];
  readonly quests: readonly QuestState[];
  readonly location: GameLocationData;
  readonly world: {
    readonly discoveredAreas: readonly AreaId[];
    readonly defeatedBossIds: readonly string[];
    readonly completedDungeonIds: readonly string[];
    readonly maps: Record<string, MapRuntimeStateData>;
  };
  readonly playTimeMs: number;
}

interface NamedSaveSnapshot extends NamedSaveMetadata {
  readonly data: GameSaveData;
}
```

Only store runtime deltas keyed by stable authored IDs. Do not copy terrain rows,
object visual metadata, texture keys, colliders, or complete map JSON into a
save. On load, build the authored map first and apply the selected map's deltas
by `mapId` and stable `instanceId`.

`objectStates` is the extension point for future doors, crops, furniture, home
upgrades, and placed objects. Do not route untyped values directly into runtime
systems; each owning feature must validate and normalize its own state before
use.

## Initial-state ownership

Create a content-owned initial-run definition, preferably under
`src/game/content/initial-state/`. It must identify:

- initial area and map: `level-1`;
- initial location rule: use `level-1.map.json` player spawn;
- base player progression data;
- initial inventory and equipment ownership;
- initial hotbar/equipped weapon;
- initial quests and global progression;
- empty runtime state for all maps.

Refactor `GameState` defaults and starter inventory/loadout initialization to
consume this definition. `WorldScene` must not seed potions, materials, or tools
ad hoc. Development grants remain separate and explicit.

The initial state is versioned content, not a save. Changing it affects only new
runs and Reset Run; existing named saves continue through schema migration.

## Work sequence

### 1. Extract one deterministic initial-run factory

Add typed initial-state content and a pure factory that returns fresh cloned
state. It must never return shared mutable arrays or objects. Point `GameState`,
inventory initialization, weapon loadout initialization, quests, and initial
location at that factory.

Set `level-1` as the single initial area/map authority. Remove fallback behavior
that silently starts at another area when no query override or save is present.
Development `?map=` overrides may still open another map, but they must be marked
as development-only and must not change the production initial-state definition.

Add tests proving two calls to the initial-state factory are deeply independent
and exactly match the intended Level 1 player setup.

### 2. Separate authored defaults from runtime map deltas

Introduce a `MapProgressStore` or extend `WorldProgress` with explicit map-scoped
APIs:

```ts
stateForMap(mapId: MapId): Readonly<MapRuntimeStateData>;
resourceState(mapId: MapId, instanceId: string): ResourceProgressState | undefined;
setResourceState(mapId: MapId, instanceId: string, state: ResourceProgressState): void;
clearMap(mapId: MapId): void;
resetAllMaps(): void;
serializeMaps(): Record<MapId, MapRuntimeStateData>;
```

Migrate existing flat keys such as `level-1:level-1-tree-01` into
`world.maps['level-1'].resources['level-1-tree-01']`. Preserve unknown map IDs so
a snapshot does not lose progress merely because the currently running build
does not load that map.

Ensure every map transition keeps the full map-state collection in memory. Only
the destination map is instantiated, but every visited map remains represented
in the snapshot. `ResourceNodeController` continues to query by map and instance;
future encounter/chest/gate controllers use the same map-scoped pattern.

### 3. Build a validating, indexed snapshot repository

Replace the single-slot assumptions in `SaveRepository` with operations that do
not expose `localStorage` to scenes or UI:

```ts
list(): readonly NamedSaveMetadata[];
create(name: string, data: GameSaveData): NamedSaveMetadata;
overwrite(saveId: string, data: GameSaveData): NamedSaveMetadata;
read(saveId: string): NamedSaveSnapshot | null;
delete(saveId: string): boolean;
readRecovery(): GameSaveData | null;
writeRecovery(data: GameSaveData): boolean;
clearRecovery(): void;
```

Generate IDs independently from display names. Normalize names by trimming and
reject empty/overlong names. If a new name matches an existing record, show that
record and require the player to choose explicit overwrite or enter another
name; never infer overwrite from text alone. Sort the list by `updatedAt`, newest
first. Creating writes the new snapshot before updating the index; if index
writing fails, roll back the new snapshot so no hidden orphan remains.
Overwriting preserves `saveId`, `name`, and `createdAt`, updates `updatedAt`, and
uses a rollback-safe replacement so a failed write leaves the old snapshot
readable. Deleting one record updates the index and leaves every other record
untouched.

Add complete runtime guards and migrations for every supported schema. Never
upgrade by merely casting parsed JSON. Invalid entries should return a typed
error containing the save ID and reason, while valid saves remain listable and
loadable.

### 4. Refactor SaveSystem into capture, restore, recovery, and reset operations

SaveSystem owns orchestration and exposes intent-level operations:

```ts
captureCurrentState(location: GameLocationData): GameSaveData;
createNamedSave(name: string, location: GameLocationData): SaveResult;
overwriteNamedSave(saveId: string, location: GameLocationData): SaveResult;
loadNamedSave(saveId: string): LoadResult;
writeRecovery(location: GameLocationData): boolean;
resetRun(): ResetResult;
```

Manual Save has two explicit commit paths: create a new snapshot or overwrite a
selected existing snapshot after confirmation. It must never choose a target by
display name or overwrite the last-used save implicitly. Autosave events
continue to debounce, but they overwrite only `slime-isa:recovery`; they must
never create or modify a named save.

Loading must be transactional:

1. read, validate, and migrate the selected snapshot without changing runtime;
2. verify its current map exists and location is finite/in bounds;
3. stop gameplay and dispose the current scene-owned controllers;
4. install player/global/all-map state in memory;
5. start the normal `MapLoadScene` path for the saved map;
6. spawn at the saved position, falling back to the authored spawn only when the
   saved point is invalid;
7. write the loaded snapshot into recovery only after successful world creation.

If any preflight step fails, leave the current session untouched and show one
readable error. Do not partially load inventory before discovering that map data
is invalid.

Reset Run is also transactional. It creates a fresh initial-state object, clears
the recovery record and all active map deltas, then enters authored `level-1` at
its authored spawn. It must not delete the save index or any named snapshot.

### 5. Make map loading accept an explicit run destination

Replace URL/session-storage-only handoff with a typed navigation request that can
represent normal area travel, loading a snapshot, resetting a run, and a
development map override. Keep one owner for precedence:

1. explicit load/reset request;
2. normal area transition handoff;
3. development query override;
4. recovery prompt/choice;
5. initial Level 1 state.

`MapLoadScene` resolves and validates the requested map before `WorldScene`
creates entities. `WorldScene` receives already-installed session state and does
not decide whether to reset, load, or seed inventory. Extract this orchestration
into a run/session controller rather than expanding the scene composition root.

Record current player position and facing immediately before manual save and on
safe transition/page-hide recovery writes. Map state must already be in the
central progress store, not scraped from rendered sprites at save time.

### 6. Add Save, Load, and Reset UI controls

Replace Development Tools **Restart Map** with:

- **Save Game** — opens the existing snapshot list. Each record has an explicit
  **Overwrite** action, and a separate **Create New Save** action opens the
  required name field. Overwrite shows the target name and last-saved time in a
  confirmation before committing;
- **Load Game** — opens a newest-first snapshot list with name, timestamp,
  current map, player level, Load, Delete, and Cancel;
- **Reset Run** — opens a destructive confirmation explaining that active
  progress resets to Level 1 while named saves remain.

Pause gameplay while any persistence modal is open. Route all actions through
callbacks supplied by the session/save controller; DOM UI must not read storage
or mutate scene systems directly. Disable controls during an operation, show
success/failure status, restore focus when closing, and clean up every DOM and
keyboard listener.

Use buttons as the primary controls. Do not add letter-key shortcuts, avoiding
the input conflicts already encountered in editor text fields. `Escape` may
close a modal without applying an action.

The development panel is the first integration surface. Once behavior is
verified, expose the same reusable save/load panel from the production pause or
title menu without duplicating persistence logic.

### 7. Add optional export/import after core named saves are stable

If physical save files are required, add explicit **Export** and **Import**
actions using JSON download/file-picker flows. Export includes schema version,
metadata, and a checksum or content hash. Import validates completely, assigns a
new local save ID, and never overwrites an existing snapshot automatically.

This is not required for the first named-save milestone. Do not block ordinary
browser saves on filesystem permissions or browser-specific file APIs.

### 8. Migrate existing single-envelope data safely

On first launch after the new system ships:

- read the current `slime-isa:save` envelope;
- validate and migrate it into the new multi-map recovery format;
- do not automatically create a named save unless the player chooses Save Game;
- retain the legacy key until one recovery write and one successful load have
  completed, then mark migration complete;
- never delete legacy data merely because one parsing attempt failed.

Existing `resourceStates` composite keys migrate into per-map resources. Existing
inventory, quests, equipment slots, active weapon, discovered areas, bosses, and
dungeons remain unchanged. Missing location falls back to authored Level 1
spawn, or to the legacy current area when it can be determined safely.

## File ownership map

| Concern | Primary ownership |
|---|---|
| Initial run content | `src/game/content/initial-state/`, `src/game/content/player.ts`, `level-1.map.json` |
| Save contracts/migrations | `src/game/infrastructure/persistence/SaveSchema.ts` and migration modules |
| Named snapshot index/storage | `src/game/infrastructure/persistence/SaveRepository.ts`, `storageKeys.ts` |
| Capture/load/reset orchestration | `src/game/core/SaveSystem.ts` plus a run/session controller |
| Per-map runtime deltas | `src/game/features/progression/WorldProgress.ts` or extracted `MapProgressStore.ts` |
| Map reconstruction | `MapLoadScene.ts`, `MapRepository.ts`, `MapBuilder.ts` |
| Player location capture/restore | player/session feature boundary, not DOM UI |
| Controls and dialogs | reusable persistence UI plus `devTools.ts` integration |
| Verification | focused suites under `scripts/tests/persistence/` and runtime playtest checklist |

`asset/assets.json` remains unrelated. Authored map JSON remains content and is
never treated as writable save storage. Scenes compose the flow but do not parse
storage or own migrations.

## Verification gates

Run narrow tests after each persistence slice and the full project check before
handoff:

1. initial-state factory and independent-clone tests;
2. save schema guard and every supported migration test;
3. repository create/list/read/overwrite/delete, overwrite-cancel,
   failed-write rollback, corrupt-entry isolation, and recovery tests;
4. multi-map state serialization and legacy composite-resource-key migration;
5. transactional load/reset tests proving failures do not mutate the active run;
6. UI tests for name validation, list ordering, disabled operation state,
   confirmation, focus return, and listener cleanup;
7. `pnpm maps:check`, `pnpm typecheck`, `pnpm build`, and `pnpm check`;
8. manual Level 1 → second map → Level 1 round-trip using two named saves.

## Acceptance matrix

| Scenario | Required result |
|---|---|
| New run | Authored Level 1 and the content-owned initial player state load exactly |
| Open Save Game | Existing records appear before the player chooses an action |
| Create new save | A name is required and a new stable save ID is created |
| Matching new name | The UI offers explicit overwrite or requests a different name; nothing changes silently |
| Confirm overwrite | Only the selected record changes; its stable ID and creation time remain |
| Cancel overwrite | No save record changes |
| Save A then Save B | Overwriting A does not change B, and both remain loadable |
| Cut and collect | Depleted tree and collected material agree after named load |
| Partial node | Saved health/drop state restores according to the resource's persistence rule |
| Two visited maps | Each map restores its own independent object/resource/encounter deltas |
| Player restore | Inventory, equipment, hotbar, stats, quests, map, position, and facing match |
| Reset Run | Active progress returns to initial player plus untouched authored Level 1 |
| Reset with named saves | Every named save remains present and loadable |
| Delete one save | Only the selected snapshot disappears |
| Corrupt save | It reports an error without changing the active session or other saves |
| Legacy migration | Existing player/inventory/world progress survives into recovery format |
| Browser close | Recovery reflects the latest debounced/page-hide state without adding named saves |

Roadmap P is complete only when every row passes and the ambiguous restart action
has been removed or relabeled.
