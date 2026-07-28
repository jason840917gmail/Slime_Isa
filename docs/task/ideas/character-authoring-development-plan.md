# Character and Enemy Authoring Development Plan

## Status

Closed — 2026-07-28. The first Character Studio authoring plan is implemented
and verified. Future runtime capability extensions are intentionally separate
follow-up work, not blockers for this idea.

Initial authoring slice implemented: the development server now exposes the
asset catalog, PNG registration, and starter-package creation endpoints, and
Character Studio has a source-selection and creation form.

The unified PNG import path is now implemented as well: `POST
/__character-studio/create` journals the staged PNG, manifest, and character
package together, with startup/request recovery for interrupted commits.

The first-paint authoring slice is implemented: Character Studio now shows
stable body and live hitbox guides, edits complete hitbox geometry, and exposes
the supported ranged, projectile, leap, and enemy timing fields. An isolated
Vite fixture test now creates player/enemy packages, reloads the real enemy
adapter and roster source, and verifies authored maps remain byte-for-byte
unchanged. The first runtime smoke slice now covers mirrored hitbox geometry,
edge-touch semantics, hit-once activation bookkeeping, deactivation cleanup,
and authored enemy body/AI data flowing through `ENEMY_CONFIGS`. Remaining
follow-up work is broader scene-level visual/combat coverage and new capability
implementations beyond the current runtime. The fixture now also exercises
recovery of an interrupted character-creation transaction and an interrupted
asset-registration transaction. A live browser pass covers roster navigation,
capability controls, source-library creation choices, and the map-editor enemy
roster without saving production content. The deterministic runtime slice now
also covers enemy idle/chase/attack transitions, attack cooldown and cleanup,
damage-to-zero, and the production `Enemy` integration seam.

## Closure

This idea is closed because the planned development-only authoring workflow is
available end to end: authors can create player or enemy packages from existing
or imported PNG sources, edit and preview animations, author transforms,
hitboxes, events, and gameplay fields, save existing packages, duplicate
packages, and reload new content through the existing catalog and runtime
adapters. Transaction recovery, map immutability, browser smoke coverage,
runtime fixture coverage, and repository checks are passing.

The remaining capability-extension list in Slice 6 is deliberately deferred to
new, focused ideas so it does not reopen this completed authoring milestone.

## Why this is the next step

The current Character Studio can open, edit, preview, validate, save, and
duplicate existing player and enemy packages. Its deliberate boundary is that
the spritesheet must already be registered in `asset/assets.json`, and package
identity fields cannot be changed during an update.

The next capability is therefore a development-only creation workflow that can
turn an authored spritesheet into a complete character package. It should
support both players and enemies while keeping the existing data ownership and
runtime catalog rules intact.

This plan follows:

- [`2026-07-27-character-studio-design.md`](../../superpowers/specs/2026-07-27-character-studio-design.md)
- [`ADDING_ASSETS.md`](../../ADDING_ASSETS.md)
- [`2026-07-23-animated-worm-enemy-roster-design.md`](2026-07-23-animated-worm-enemy-roster-design.md)
- [`future-enemy-types.md`](future-enemy-types.md)
- [`2026-07-24-combat-hit-feedback-and-parry-design.md`](2026-07-24-combat-hit-feedback-and-parry-design.md)

## Goal

Add a `Create Character` workflow to Character Studio that lets an author:

1. choose an existing manifest spritesheet or import a new PNG spritesheet;
2. define and preview its uniform frame grid;
3. choose `player` or `enemy` and provide stable identity fields;
4. generate a complete version-1 character package with safe starter values;
5. continue immediately in the existing timeline, preview, inspector, and save
   workflow; and
6. reload the development catalog so the new package is available to runtime
   adapters and editor rosters.

The first milestone creates content that uses capabilities already supported by
the runtime. It does not attempt to invent arbitrary AI or combat behavior from
the editor.

## Product decisions for the first milestone

### Creation modes

The library gets a `NEW CHARACTER` entry with three choices:

- **From existing asset** — select a known ready image or spritesheet and create
  a new package around it.
- **Import spritesheet** — upload a PNG through the development server, define a
  uniform grid, and register the asset and package in one authoring operation.
- **From package** — keep the existing `DUPLICATE PACKAGE` flow for preserving
  animation, gameplay, and alignment work from an existing character.

Creation from an existing package remains duplication rather than a second
implementation of the same behavior.

### Source-art scope

Version 1 supports PNG files and uniform grids only. The author supplies frame
width and height; columns and rows are derived from the verified image size.
The author may set a populated contiguous frame count, defaulting to the full
grid capacity. Alpha-based frame discovery, irregular cut-lines, atlases, GIFs,
skeletal art, and image editing are later work.

The server derives the destination path from the validated asset ID. The browser
never sends or receives an arbitrary filesystem path.

### Starter content

The wizard offers code-owned starter templates, but templates are convenience
presets and do not become schema-required actions:

- **Player starter**: one looping `idle` clip using frame `0`, a reviewed body,
  and player values copied from the current primary player as an editable
  baseline. The new package never receives `runtimeRole` automatically.
- **Melee enemy starter**: one looping `idle` clip and the current enemy melee
  baseline.
- **Ranged enemy starter**: one looping `idle` clip and the current ranged
  baseline, with the projectile fields left unset until a valid projectile is
  selected.

The author must review the stable body, visual scale, origin, gameplay values,
and initial clip before the package can be created. `idle` is a starter clip,
not a schema requirement; freely named clips remain the runtime contract.

### Runtime availability

A successfully created, valid package is catalog-visible after the required
page reload:

- a new player is available as a non-primary player package and does not replace
  the active player;
- a new enemy is available to `ENEMY_CONFIGS` and the map editor after reload,
  but no authored map or spawn table is changed automatically.

This keeps creation useful for iteration without silently altering production
encounters or granting a second primary player.

## Data ownership and invariants

| Concern | Authoritative owner | Creation rule |
| --- | --- | --- |
| Source path, PNG dimensions, grid, texture key, bundle | `asset/assets.json` | Register atomically with the uploaded file; add character art to `boot` in v1. |
| Character ID, kind, body, hitboxes, gameplay values, tracks | package `character.json` | Generate a complete schema-valid document; never write TypeScript imports. |
| Visual set ID, frame lists, transforms, clips | package `visual-set.json` | Generate a complete schema-valid document using the selected asset. |
| Map placement and spawn weights | authored maps and map editor | Never changed by character creation. |
| AI and combat capabilities | owning runtime feature and typed content fields | Only expose currently implemented modes in v1. |

The stable body remains independent of source-frame size, origin, scale, offsets,
and mirroring. Character creation must not introduce a special body rule that
the existing editor does not use.

## Proposed authoring flow

```text
Character library
  -> New Character
  -> choose existing asset or import PNG
  -> inspect image dimensions and choose uniform grid
  -> choose player/enemy and starter template
  -> enter ID and display name
  -> review generated body, clip, and gameplay defaults
  -> server validates and commits asset + manifest + package
  -> page reloads the virtual catalog
  -> existing Character Studio opens the new package
```

The wizard should not expose raw JSON or texture keys as normal authoring
fields. Advanced identity values may be shown as read-only derived values so
authors can understand what will be written.

## Technical design

### Asset registration

Extend the development authoring server with an asset-registration service,
preferably shared by the Character Studio plugin rather than embedded in the
UI component.

Proposed development-only endpoints:

```text
GET  /__character-studio/assets
POST /__character-studio/asset/register
POST /__character-studio/package/create
```

`GET /assets` returns ready image/spritesheet candidates from the manifest,
including dimensions, grid, populated count, tags, and whether an asset is
already referenced by a character package.

`POST /asset/register` accepts multipart data for the PNG and a small metadata
object containing the requested asset ID, frame width, frame height, populated
count, and authoring tags. The server must:

- verify the PNG signature and actual dimensions;
- verify that frame dimensions divide the image evenly;
- derive columns and rows from the image dimensions;
- reject duplicate asset IDs, duplicate texture keys, path traversal, hidden
  transaction paths, and attempts to overwrite existing files;
- write the source under an authoring-owned `asset/` subdirectory;
- add the asset to the `boot` bundle for character art in v1; and
- run the same manifest validation used by `assets:check` before commit.

The initial upload limit should be explicit and separate from the current 2 MiB
JSON package limit, with a documented development default of 32 MiB. The limit
must be enforced while streaming the request, not after buffering an unlimited
body.

### Package creation

`POST /package/create` accepts stable IDs and generated document values, not
filesystem paths. It should support either a previously registered `assetId`
or an upload transaction that has produced a staged asset.

The server owns all package identity derivation:

- character IDs are lowercase kebab-case;
- player visual sets use `character.<dot-separated-id>`;
- enemy visual sets use `enemy.<dot-separated-id>`;
- the runtime texture key is derived from the asset ID unless the server must
  disambiguate it; and
- a new player cannot claim `primary-player` during creation.

The created package contains both files before the destination becomes visible
to catalog discovery. A successful response returns the normalized package,
revision, and `reloadRequired: true`, matching the existing duplicate contract.

### Cross-store transaction and recovery

Creation changes two independently loaded stores: the asset file/manifest and
the character package. A partial write must never leave a package pointing at a
missing or half-written asset.

Add a shared development authoring transaction coordinator that stages:

1. the uploaded source file;
2. the candidate `asset/assets.json`;
3. `character.json`; and
4. `visual-set.json`.

The commit journal should identify the transaction, asset ID, character ID,
source and destination paths, and completed phases. Startup recovery must either
finish one unambiguous transaction or stop with a recovery error. It must never
delete another package's artifacts or guess between conflicting valid copies.

Existing package update and duplicate transactions should reuse the same path
validation, locking, and recovery primitives where practical.

### Catalog invalidation and reload

The current manifest is imported as a Vite module and the character catalog is
discovered by `characterContentModulesPlugin`. Asset registration therefore
invalidates the relevant Vite modules but still requires a full page reload for
the new static manifest import and eager package discovery to be available in
browser code.

The client should navigate only after the server confirms the commit. On an
ambiguous response, it reloads the candidate package and asset list before
offering retry. It must not create a second package or asset blindly.

## Development slices

### Slice 0: decisions and fixtures

- Confirm PNG-only, uniform-grid scope and the 32 MiB upload ceiling.
- Choose the authoring destination directory for imported character art.
- Define starter presets for player, melee enemy, and ranged enemy.
- Add temporary asset and package roots to Character Studio browser tests.
- Document that a new enemy is catalog-visible but does not edit maps.

Exit check: the decisions are recorded, fixture roots can contain an isolated
manifest plus character packages, and no test writes production `asset/` or
`src/game/content/characters/`.

### Slice 1: shared authoring transaction foundation

- Extract safe-root, ID, case, and collision checks into reusable server code.
- Add manifest loading and normalized writing with a per-manifest mutex.
- Add staged source-file and manifest transaction artifacts with recovery.
- Extend the test harness to simulate interruption before and after each commit
  rename.
- Preserve the existing package update/duplicate behavior and error codes.

Exit check: interrupted asset/package creation either recovers to one complete
state or returns a recovery error without data loss or cross-package cleanup.

### Slice 2: register and inspect a spritesheet

- Implement `GET /__character-studio/assets`.
- Implement streamed PNG registration and manifest mutation.
- Add frame-grid preview with image dimensions, frame dimensions, columns,
  rows, capacity, and populated count.
- Add `asset:check` coverage for newly registered files, bundle membership,
  duplicate texture keys, and populated-frame bounds.
- Keep all loading metadata in the manifest; do not put gameplay fields there.

Exit check: a fixture PNG can be registered, survives a server restart, passes
`pnpm assets:check`, and is returned by the asset catalog without an orphan or
partial manifest entry.

### Slice 3: create a blank package

- Add the library entry and creation route.
- Build complete player and enemy starter documents from typed templates.
- Add live validation for IDs, names, selected asset, visual-set identity,
  body, initial clip, and kind-specific fields.
- Add a review step showing the generated visual set and gameplay baseline.
- Commit package and asset changes through the transaction coordinator.
- Reload and open the new package in the existing Character Studio.

Exit check: creating one player and one enemy from fixture assets produces two
independent packages; the player remains non-primary, the enemy appears in the
enemy editor roster, and maps are byte-for-byte unchanged.

### Slice 4: first-paint authoring quality

- Add frame selection to the first clip without imposing action or direction
  slots.
- Add a body guide and initial numeric body review before commit.
- Reuse the existing timeline, transforms, hitboxes, tracks, undo/redo, and save
  conflict behavior without copying those implementations.
- Add a clear “asset registration committed; reload required” state.

Exit check: an author can import a new sheet, create a useful idle/walk/attack
starting point, save edits, reload, and see identical frames and transforms.

### Slice 5: enemy activation and gameplay verification

- Confirm new enemy packages flow through `CharacterCatalog` and
  `ENEMY_CONFIGS` using the existing adapter.
- Expose only supported current AI fields and capabilities in the inspector.
- Add a map-editor roster test proving a created enemy is selectable after
  reload, while authored map files and spawn tables remain unchanged.
- Add runtime smoke coverage for spawn, movement, attack, damage, death, and
  cleanup using a fixture enemy package. The first isolated runtime slice is
  complete: it exercises the real hitbox controller through a Vite fixture and
  verifies mirrored geometry, hit-once behavior, and deactivation cleanup.
  The same fixture now verifies restart-style recovery for staged character and
  asset transactions.
- Add an explicit “not ready for production encounters” note or readiness flag
  in the editor UI if the team wants a stronger review gate later.

Exit check: a created enemy can be manually added to a test map and behaves
through the existing runtime path without bespoke imports or hardcoded IDs.

### Slice 6: capability extensions after creation works

New visual packages should first use existing runtime behavior. Additional
capabilities should be delivered as focused, typed extensions rather than an
arbitrary behavior graph. Candidate order:

1. reusable attack capability and animation-timed hitbox execution;
2. projectile capability with authored projectile asset references;
3. leap/windup/impact capability;
4. status-effect or drop capability; and
5. boss phases and encounter-specific orchestration.

Each capability needs a schema field, runtime adapter, validator, inspector
metadata, preview behavior, and focused tests before it is offered in the
creation wizard. The existing hitbox/parry design remains the source for attack
hitbox ownership and collision semantics.

## Validation and test plan

### Repository checks

Every created fixture must pass the same checks as production content:

- `pnpm assets:check`
- `pnpm visuals:check`
- `pnpm characters:check`
- `pnpm enemies:check`
- `pnpm maps:check`
- `pnpm typecheck`
- `pnpm build`

### Authoring server tests

Cover:

- malformed PNG and incorrect dimensions;
- non-divisible frame sizes and invalid populated counts;
- duplicate asset IDs, texture keys, character IDs, and visual-set IDs;
- path traversal, hidden artifact, oversize upload, and unsupported file type;
- package validation against a newly registered asset;
- player primary-role protection;
- map immutability;
- concurrent asset/package creation;
- interruption at every transaction phase;
- restart recovery and ambiguous-artifact refusal; and
- unknown-commit retry without duplicate files.

### Browser tests

Cover:

- existing-asset and imported-asset flows;
- grid preview and frame-count editing;
- player/enemy starter selection;
- invalid form preservation;
- create, reload, and open behavior;
- new player not becoming active automatically;
- new enemy appearing in the editor roster;
- no map-file mutation;
- asset/package conflict and recovery UI; and
- cleanup of object URLs, upload listeners, and pending requests.

### Runtime smoke tests

At minimum, verify one newly created player package and one newly created enemy
package through the existing runtime adapters. Check animation playback, stable
body geometry, enemy attack/death cleanup, asset loading, and scene transition
cleanup. The new workflow must not require editing `WorldScene`, a handwritten
catalog import, or a map file.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Manifest and package are committed separately | Use one journaled authoring transaction with startup recovery. |
| Vite retains the old statically imported manifest | Return `reloadRequired` and navigate only after commit. |
| New enemy becomes accidentally playable in production maps | Do not modify maps or spawn tables; require explicit map authoring. |
| Starter templates become hidden schema requirements | Keep templates code-owned and validate only the existing free-form schema. |
| Large or malicious uploads consume the dev server | Stream with a hard limit, verify PNG bytes, and write only beneath a server-owned root. |
| New behavior needs code the package cannot express | Add a focused typed capability slice; do not expose arbitrary AI graphs. |
| A failed write leaves an asset orphan | Recovery validates references and removes only artifacts owned by the transaction. |

## Open decisions before implementation

1. Confirm the exact import destination directory and whether authored source art
   should be visually separated from hand-curated production art.
2. Decide whether `boot` is permanently the bundle for all character sheets or
   whether bundle selection should be included in a later asset workflow.
3. Decide whether the editor needs an explicit draft/readiness flag for new
   enemies, or whether catalog visibility plus manual map opt-in is sufficient.
4. Decide whether populated frame count is manually authored in v1 or whether
   alpha occupancy detection is worth adding after the basic upload path.

## Definition of done for the first release

- Character Studio can create a player or enemy from a registered or uploaded
  PNG spritesheet.
- The uploaded file, manifest entry, and package are committed as one recoverable
  authoring transaction.
- The new package uses the existing catalog, preview, validation, and runtime
  adapters without handwritten registration.
- The primary player remains unique and unchanged.
- New enemies are available for explicit map-editor use but no maps change as a
  side effect.
- Production builds contain no creation endpoint or creation UI.
- Repository, server, browser, runtime, interruption, and recovery checks pass.

## Closure note

The original recommended first task has been completed through the full
authoring workflow. New work should start in a separate idea file for the next
capability, runtime, or scene-level milestone.
