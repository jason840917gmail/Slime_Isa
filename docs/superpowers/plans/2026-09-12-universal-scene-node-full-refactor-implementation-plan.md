# Universal Scene, Node, and Scene Studio Full Refactor Implementation Plan

**Design:**

- `docs/superpowers/specs/2026-09-12-godot-inspired-universal-scene-node-architecture-design.md`

**Status:** Revised after execution-readiness review; incorporates the five
review corrections. Implementation has not started.

## Objective

Replace the Phaser application's separate character, boss, animation, weapon,
projectile, effect, object, map, and UI composition paths with one versioned
scene document, one Godot-inspired runtime node tree, and one Scene Studio.

The completed refactor must make Fatty One Eye an enemy with `rank: "boss"` and
`FattyScript extends EnemyScript`, while retaining its custom behavior. Ordinary
enemies must be able to use the same damage-area, vulnerability, resistance,
effect-response, animation, collision, visual, audio, and signal capabilities.
Geometry stays generic; ScriptNodes and shared domain services decide what a
contact means.

This is one coordinated refactor. The work is divided into bounded work packages
so failures can be localized and reviewed, but implementation proceeds through
the whole plan without separate product approvals at each package. Temporary
development breakage is acceptable. The final handoff must clearly separate
automated technical verification from gameplay verification reserved for the
user.

## Execution rules

1. Preserve the user's existing dirty worktree. Before editing, inventory and
   save the current diff/status. Never reset, discard, or overwrite unrelated
   work. Many files in this plan already contain uncommitted Fatty, chest,
   animation, persistence, and editor work; integrate those changes rather than
   replacing them from `HEAD`.
2. Use one implementation branch/working tree and bounded commits. Stage only
   files owned by the active package. Suggested commit boundaries appear below;
   they are not approval gates.
3. Keep the application architecture direction: scenes compose features;
   features depend on content/shared contracts; infrastructure owns browser
   storage, file writes, asset loading, and Phaser adapters. ScriptNodes must not
   import `WorldScene` or Phaser.
4. Keep `asset/assets.json` limited to media-loading metadata. Scene behavior,
   collision, scripts, animation bindings, ranks, and damage rules belong in
   typed scene/resource content.
5. Keep production maps authored. Do not import the procedural map generator
   into gameplay.
6. Retain the current versioned `GameSaveData` aggregate and persistence layer.
   Introduce a save migration only if a preserved state cannot be represented;
   do not add a hybrid save envelope or node-tree serialization to saves.
7. Use one declarative descriptor as the source for each node/script property:
   serialization, validation, inspector controls, defaults, animation, and
   override eligibility must agree.
8. Do not add a code editor. Scene Studio creates/selects registered ScriptNodes,
   displays exports and source paths, and may open source externally.
9. Avoid compatibility layers with two writers. A temporary adapter reads the
   current owner and has a named removal package. Once a family switches, its
   legacy authoring route becomes unavailable or redirects to Scene Studio.
10. Automated tests may verify deterministic calculations, lifecycle, routing,
    and simulations. They are never reported as gameplay testing.

## Target module boundaries

Create focused modules under these destinations. Keep files small enough that a
single class or contract can be understood without opening the whole engine.

```text
src/game/
|- content/scenes/
|  |- scene.schema.json, types.ts, identifiers.ts, propertyDescriptors.ts
|  |- validation.ts, SceneCatalog.ts, resources/types.ts
|  `- authored scene/resource packages
|- runtime/scene/
|  |- NodePath.ts, NodeReference.ts
|  |- Node.ts, Node2D.ts, SceneTree.ts, SceneMutationQueue.ts
|  |- Signal.ts, DisposableScope.ts, PackedScene.ts
|  |- registries/NodeTypeRegistry.ts, ScriptRegistry.ts
|  `- resolution/SceneResolver.ts, SceneInstantiator.ts
|- infrastructure/scenes/
|  |- SceneDocumentLoader.ts, SceneResourceLoader.ts
|  |- PhaserSceneTreeHost.ts
|  |- editor/SceneStudioRepository.ts, SceneStudioContentPlugin.ts
|  `- compatibility/ temporary legacy bridges
|- infrastructure/phaser-nodes/
|  |- Sprite2DNode.ts, CharacterBody2DNode.ts, StaticBody2DNode.ts
|  |- Area2DNode.ts, CollisionShape2DNode.ts, Camera2DNode.ts
|  |- AudioStreamPlayerNode.ts, AudioStreamPlayer2DNode.ts
|  `- TileMapLayer2DNode.ts and Control adapters
|- features/scripts/
|  |- CharacterScript.ts, EnemyScript.ts, PlayerScript.ts, NpcScript.ts
|  |- FattyScript.ts and non-character behavior scripts
|  `- registrations.ts
`- editor/scene-studio/
   |- SceneStudio.ts, SceneStudioRoute.ts, SceneDocumentState.ts
   |- SceneTreePanel.ts, SceneInspector.ts, SceneViewport.ts
   |- contexts/animation, tile, audio, signals, debug
   |- history, validation, preview, resources
   `- scene-studio.css
```

The exact split may be refined while implementing, but do not collapse the tree,
Phaser backend, content documents, editor state, and gameplay scripts into one
module. Public barrel files may re-export stable APIs after their individual
modules are proven.

Canonical ownership is fixed for planning: identifier brands live only in
`content/scenes/identifiers.ts`; runtime code imports those types. JSON resource
types live in `content/scenes/resources/types.ts`; resource loaders and lease
management live in `infrastructure/scenes/`. The browser HTTP repository lives
in `infrastructure/scenes/editor/SceneStudioRepository.ts`, and the Node-side
Vite writer lives beside it in `SceneStudioContentPlugin.ts`. Never import that
Node-only writer from runtime or editor browser code. The editor consumes its
repository through an interface. There is no second runtime identifier module
or editor-owned file writer.

## Required verification commands

Add focused scripts as their suites become available:

```text
pnpm scenes:check
pnpm test:scene-runtime
pnpm test:scene-content
pnpm test:scene-studio
pnpm test:scene-integration
pnpm test:scene-browser
pnpm test:scene-conversion
```

Use these package commands. Node suites load TypeScript through the shared
esbuild helper described below; browser fixtures load through Vite:

```json
{
  "scenes:check": "node scripts/check-scenes.mjs",
  "test:scene-runtime": "node --test scripts/tests/scene-runtime/*.test.mjs",
  "test:scene-content": "node --test scripts/tests/scene-content/*.test.mjs",
  "test:scene-studio": "node --test scripts/tests/scene-studio/*.test.mjs",
  "test:scene-integration": "node --test scripts/tests/scene-integration/*.test.mjs",
  "test:scene-browser": "playwright test --config scripts/tests/scene-browser/playwright.config.ts",
  "test:scene-conversion": "node --test scripts/tests/scene-conversion/*.test.mjs",
  "scenes:convert": "node scripts/convert-scenes.mjs"
}
```

Each work package runs its focused suites plus `pnpm typecheck`. Packages that
change Vite/editor integration or runtime construction also run `pnpm build`.
The final package runs `pnpm check`. Existing suites stay active until their
owned legacy path is deliberately removed; their preserved behavior must move
into replacement suites before deleting them.

### Shared test harness and real-engine evidence

Package 0 establishes the harness; later packages add assertions when their
implementations exist. Empty or skipped future suites are not evidence.

- `scripts/tests/helpers/load-typescript.mjs` exposes a shared esbuild loader,
  following existing combat/boss tests: bundle to ESM for Node with `write:false`,
  then import the in-memory output. A suite bundles one entry exporting its
  collaborating modules to avoid duplicate singleton/class copies across builds.
  Inject virtual content through explicit fixtures; reject unexpected Phaser,
  browser-only, or production virtual-module dependencies in pure tests.
- Node suites exercise contracts, pure calculations, filesystem journals in
  temporary directories, and fake-backend fault injection. They do not pretend
  to supply a DOM or actual Phaser world.
- Add `@playwright/test` as a pinned development dependency through pnpm and
  install its matching Chromium during implementation. Use real Chromium DOM,
  canvas, and the project's real Phaser package for engine/editor integration.
  No additional DOM emulator is needed. Browser installation/setup failures are
  reported as blocked technical verification, never replaced by a passing mock.
- `scripts/tests/scene-browser/playwright.config.ts` owns one test worker, zero
  retries for deterministic acceptance, fresh contexts per test, failure traces,
  and a managed Vite server on `127.0.0.1:3101` with `--strictPort` and
  `reuseExistingServer:false`. Use a separate fixture Vite config that never
  registers production content-write endpoints. Editor write tests inject a
  temporary content root and the real repository/plugin under test.
- `scripts/tests/scene-browser/fixtures/index.html` and `main.ts` load synthetic
  node scenes, the real host/backend adapters, and real editor controls. They
  never boot WorldScene or read the user's saves. Expose a narrow fixture API to
  enqueue inputs, advance fixed ticks, inspect state/counters, and destroy.
  Stop automatic frame advancement in deterministic fixtures, feed explicit
  deltas through the actual host, and spy on actual Arcade steps/readback.
- The browser suite verifies one real backend step, collision/body sync, sensor
  reconciliation, root replacement, DOM/Control event consumption, rendering
  object lifetime, and teardown. It also mounts the real Scene Studio controls
  to verify focus, preview isolation, and save-conflict UI. Assert no unexpected
  console/page errors and no surviving test-owned objects, leases, or listeners.
  Diagnostic wrappers must count actual registered resources, not mirror what
  the implementation intends to register.

Add `scripts/tests/scene-browser/tsconfig.json` covering browser fixtures and
Playwright configuration; extend `typecheck` to check it explicitly because the
root tsconfig currently includes only `src/`. Add the `virtual-scene-content`
path alias to the root tsconfig and its declaration to `src/vite-env.d.ts` in
package 1. Keep browser fixtures and Node-only configs outside production bundles.

The browser tests are deterministic technical integration checks, not AI-driven
gameplay sessions. They do not judge combat feel or complete the user's gameplay
checklist. Performance uses a separate baseline/final workload with normal
rendering, fixed setup/warm-up/sample lengths, recorded browser/hardware, and
separate measured runs; controlled-step fixture timings are not frame-rate data.

Implementation references: [esbuild build API](https://esbuild.github.io/api/#build),
[Playwright web-server management](https://playwright.dev/docs/test-webserver),
and [Playwright configuration](https://playwright.dev/docs/test-configuration).

## Work package 0 — Freeze the real baseline and create the conversion ledger

### Files

Create:

- `docs/superpowers/plans/evidence/universal-scene-baseline.md`
- `docs/superpowers/plans/evidence/universal-scene-conversion-ledger.md`
- `scripts/migrations/universal-scene-conversion-ledger.json`
- `scripts/inventory-scene-conversion.mjs`
- `scripts/tests/scene-conversion/conversion-inventory.test.mjs`
- `scripts/tests/helpers/load-typescript.mjs`
- `scripts/tests/scene-browser/playwright.config.ts`
- `scripts/tests/scene-browser/vite.config.ts`
- `scripts/tests/scene-browser/tsconfig.json`
- `scripts/tests/scene-browser/fixtures/index.html`
- `scripts/tests/scene-browser/fixtures/main.ts`
- `scripts/tests/scene-browser/harness.spec.ts`
- `scripts/tests/scene-browser/baseline-performance.spec.ts`

Update:

- `package.json`
- `pnpm-lock.yaml`
- `.gitignore` (test reports, traces, and temporary conversion/journal outputs)

### Steps

1. Record `git status --short`, the current commit, Node/pnpm versions, and the
   exact existing test/check results. Label existing failures without fixing
   unrelated issues in this package.
2. Inventory every production content document and its runtime/editor owner:
   characters, visual sets, animations, enemies, boss definitions, weapons,
   projectiles, effects, object archetypes, NPC definitions, maps, terrain,
   encounters, UI entry points, and global settings/resources.
3. Store the machine-readable rows in the JSON ledger and render/summarize them
   in the Markdown evidence file. For every inventory row record:
   old source path, stable ID, old catalog/validator, old factory/controller,
   old editor write endpoint, destination scene/resource ID, persistence keys,
   migration work package, focused verification, and legacy removal package.
4. Include every authored map in `src/game/content/maps/`, not only the three
   production maps commonly baked. Mark test/development maps explicitly so the
   migration does not silently orphan them.
5. Inventory every Vite write handler and every `?studio=`/`?editor=` route. This
   establishes the list that must reach zero category-specific writers.
6. Capture performance baselines for representative small and large authored
   maps: load time, median frame time, p95 frame time, Phaser object/body count,
   and cleanup count. Use a deterministic workload and document the procedure.
7. Add `test:scene-conversion` to `package.json`. The first test validates that
   every discovered old content ID appears exactly once in the ledger.
8. Establish the shared esbuild and Playwright harness from the verification
   section, pin dependencies, and add fixture typechecking. The initial browser
   test proves real Phaser can initialize/step/destroy and a DOM control can
   consume an event; it does not claim the unimplemented host is verified.
9. Record clocks/randomness, baseline assets/map hashes, viewport, renderer,
   warm-up/sample counts, and browser/hardware in the evidence file. Retain a
   baseline measurement entry until the final comparison is complete.

### Gate

- The ledger is machine-checkable and contains no unclassified production ID.
- Baseline failures and dirty files are documented.
- No runtime or content owner changes in this package.
- The Node loader and real Chromium/Phaser harness execute; new host behavior is
  tested later in the package that implements it.

### Suggested commit

```text
test: inventory universal scene conversion baseline
```

## Work package 1 — Define scene documents, IDs, descriptors, and pure validation

### Files

Create:

- `src/game/content/scenes/scene.schema.json`
- `src/game/content/scenes/types.ts`
- `src/game/content/scenes/identifiers.ts`
- `src/game/content/scenes/propertyDescriptors.ts`
- `src/game/content/scenes/resources/types.ts`
- `src/game/content/scenes/validation.ts`
- `src/game/content/scenes/SceneCatalog.ts`
- `src/game/content/scenes/virtual-scene-content.ts`
- `src/game/content/scenes/sceneContentModulesPlugin.ts`
- `scripts/check-scenes.mjs`
- `scripts/tests/scene-content/document-contract.test.mjs`
- `scripts/tests/scene-content/property-descriptors.test.mjs`
- `scripts/tests/scene-content/catalog-validation.test.mjs`
- `scripts/tests/scene-content/fixtures/`
- `scripts/convert-scenes.mjs`
- `scripts/lib/scene-conversion/ConversionRunner.mjs`
- `scripts/lib/scene-conversion/StableIdMap.mjs`
- `scripts/lib/scene-conversion/ConversionReport.mjs`
- `scripts/lib/scene-conversion/load-scene-tooling.mjs`
- `scripts/tests/scene-conversion/runner.test.mjs`

Update:

- `vite.config.ts`
- `src/vite-env.d.ts`
- `tsconfig.json` (virtual scene alias)
- `package.json`

### Steps

1. Add branded `SceneId`, `ResourceId`, `AuthoredNodeId`, `InstanceId`,
   `RuntimeNodeId`, and `PersistenceKey` string types. Define one delimiter-safe
   serialized alphabet and canonical segment encoding. Runtime IDs must remain
   stable through rename and reparent.
2. Implement the version-1 `SceneDocument`, `SceneNodeDocument`,
   `SceneInstanceDocument`, `SceneOverrideDocument`, `NodeReferenceDocument`,
   `SceneReferenceDocument`, signal connection document, and resource reference
   contracts exactly as described in the design.
3. Enforce one root, flat local node list, separate instance list, dense shared
   sibling order, unique sibling names, unique IDs, valid parent/type/reference
   relationships, safe names, known versions, and acyclic authored instance
   graphs.
4. Define JSON-safe property types and one descriptor contract owning type,
   default, constraints, labels/help/units, serialization, inspector editor,
   animation interpolation/domain, and override eligibility.
5. Define resource documents for texture/sprite-sheet references, collision
   shapes, animation libraries, audio, tile sets/data, fonts, and themes. Keep
   the existing asset manifest as the raw-media source; validate references into
   it without copying asset paths into scenes.
6. Implement pure registration validation for node and script descriptors.
   Reject unknown fields, incompatible inherited script properties, duplicate
   signals, duplicate overrides, illegal parent/child constraints, and mismatched
   reference capabilities.
7. Add the virtual content module and Vite plugin for read-only scene discovery.
   File writes arrive later through the dedicated Scene Studio repository.
8. Add `scenes:check` and `test:scene-content` package scripts and include them in
   `pnpm check` after the initial fixtures pass.
9. Implement the common conversion runner using the contract below. Start with
   synthetic source fixtures; family adapters arrive with their conversion
   packages. Production output cannot be generated by hand instead of exercising
   those adapters.

### Repeatable conversion contract

`pnpm scenes:convert -- --family <family> --dry-run` is the default planning
operation. It loads the ledger and canonical source inputs, computes a complete
write set in memory, validates it, and emits a report without changing content.
`--apply` installs that exact write set only when source/target hashes still
match; use the journaled writer from package 7. Before package 7, conversions may
write only to test-owned temporary output roots. `--check` recomputes expected
generated output and fails on unexplained differences. `--family all` runs in
resource-dependency order and rejects missing adapters.

| Adapter path under `scripts/lib/scene-conversion/` | Inputs | First required package |
| --- | --- | --- |
| `animations.mjs` | Visual sets, character clips, shared layered animations and directional bindings | 9 |
| `characters.mjs` | Character/NPC definitions, enemy balance and AI configuration | 9, completed in 10 |
| `boss-camps.mjs` | Fatty boss definition and authored camp records | 9 |
| `weapons.mjs` | Weapon definitions, attack tracks, targeting, animation references | 11 |
| `projectiles.mjs` | Projectile definitions and visual/animation references | 11 |
| `effects.mjs` | Effect definitions and shared visual/animation references | 11 |
| `objects.mjs` | Object archetypes/variants, resource/drop/chest/interaction definitions | 9 for chest fixture, completed in 12 |
| `maps.mjs` | Every map, tile legend/grid, placement, area and connection | 13 |
| `ui.mjs` | Explicit extraction descriptors from current UI code, themes and layout | 14 |

Each adapter is a pure input-to-document transformation using shared validators
and a persisted stable ID map. It cannot write files, read saves, or allocate
random IDs. The runner owns I/O. Shared animation resources are deduplicated by
stable source identity; family adapters emit bindings/references rather than
copies. UI extraction descriptors are authored explicitly and audited against
the existing modules; the plan does not assume automatic conversion of arbitrary
TypeScript UI code.

The Node CLI's `load-scene-tooling.mjs` bundles a single tooling entry with esbuild
for the canonical TypeScript validators and (after package 7) write journal.
It must not import a browser catalog or require Vite's virtual modules to run.
Use the same validation implementation as Scene Studio; do not duplicate it in
JavaScript to make the converter executable.

The JSON ledger records source path/hash, converter version, old-to-new ID map,
persistence keys, outputs/hashes, consumed field paths, intentionally retained
fields with owning paths, and writer state (`legacy` or `scene`). Unknown or
unaccounted gameplay fields fail conversion. Tests compare preserved values and
behavioral boundary fixtures, not only document counts. Run each adapter twice
and compare canonical output bytes/IDs; run all-family conversion in different
discovery orders and require the same output. Changing one source must update
only its expected outputs/dependents.

Once a family switches writer to scenes, conversion refuses to overwrite its
edited scene output. Verify that family against frozen source fixtures and its
cutover output hashes; current scene edits are validated as authored data.
Retain minimal migration fixtures and mapping reports after legacy removal so
repeatability and ID-preservation tests do not depend on deleted source files.

### Focused checks

Cover round trips, malformed JSON, future versions, hierarchy cycles, instance
cycles, invalid references, nested override source scopes, duplicate ordering,
property descriptor parity, unknown raw-media IDs, and source values that retain
unknown development fields for repair.

### Gate

- Validators operate without Phaser or DOM imports.
- One descriptor supplies runtime validation and editor metadata.
- Valid fixture round trips are byte-stable after canonical formatting.

### Suggested commit

```text
feat: define universal scene document contracts
```

## Work package 2 — Implement Node, SceneTree, signals, and deterministic mutation

### Files

Create:

- `src/game/runtime/scene/Node.ts`
- `src/game/runtime/scene/Node2D.ts`
- `src/game/runtime/scene/NodePath.ts`
- `src/game/runtime/scene/NodeReference.ts`
- `src/game/runtime/scene/SceneTree.ts`
- `src/game/runtime/scene/SceneMutationQueue.ts`
- `src/game/runtime/scene/Signal.ts`
- `src/game/runtime/scene/DisposableScope.ts`
- `src/game/runtime/scene/SceneDiagnostic.ts`
- `scripts/tests/scene-runtime/node-lifecycle.test.mjs`
- `scripts/tests/scene-runtime/node-path-reference.test.mjs`
- `scripts/tests/scene-runtime/mutation-queue.test.mjs`
- `scripts/tests/scene-runtime/signals-disposal.test.mjs`
- `scripts/tests/scene-runtime/error-containment.test.mjs`

Reuse/update:

- `src/game/shared/lifecycle/Disposable.ts`
- `package.json`

### Steps

1. Implement the detached, entering, inside/not-ready, ready, exiting,
   queued-for-free, and freed state machine. Keep logical node lifetime separate
   from tree-entry leases.
2. Implement parent/child operations, lookup paths, stable runtime indexes,
   process enablement, group membership, and deterministic tree order.
3. Implement queued mutation flushes and precedence `free > remove > reparent >
   add`. Revalidate parent existence, ancestry, naming, type, and transform
   constraints at flush time. Reject ambiguous same-flush remove/add.
4. Implement parent-first `_enter_tree`, child-first ready after complete private
   indexing, ready-once semantics, child-first `_exit_tree`, and same-tree atomic
   reparent preserving global `Node2D` transform.
5. Implement node-lifetime authored signals separately from entry-lifetime
   listeners/timers/Phaser leases. Detachment suspends delivery and releases entry
   leases; re-entry restores them without multiplying ready-time connections;
   free permanently disconnects.
6. Implement `duplicate()` as configuration duplication: regenerate IDs, reset
   logical runtime state, remap all internal references/animation targets/signals,
   share immutable resources, deep-copy inline subresources, and leave required
   external references unresolved.
7. Implement synchronous signal delivery in connection order over a snapshot.
   Skip endpoints disconnected/freed before invocation and defer structural
   changes to normal mutation boundaries.
8. Add development diagnostics with scene, human path, runtime ID, lifecycle
   phase, and original error. Exhaust all exit/disposer cleanup even when one
   cleanup operation fails.
9. Add `test:scene-runtime` and run it without constructing Phaser.

### Focused checks

Cover entry/ready/exit order, detach/re-entry, ready once, paused processing,
queued free in every lifecycle callback, mutation coalescing, ancestor free,
invalid reparent, lookup/rename behavior, internal/external duplication, signal
mutation during dispatch, lease cleanup, disposer failures, and zero residual
indexes after free.

### Gate

- All lifecycle traces match the design.
- Detach/re-entry neither loses authored connections nor duplicates leases.
- No runtime tree code imports `WorldScene` or browser persistence.

### Suggested commit

```text
feat: add deterministic scene tree runtime
```

## Work package 3 — Resolve, prepare, instantiate, and replace scenes safely

### Files

Create:

- `src/game/runtime/scene/PackedScene.ts`
- `src/game/runtime/scene/registries/NodeTypeRegistry.ts`
- `src/game/runtime/scene/registries/ScriptRegistry.ts`
- `src/game/runtime/scene/resolution/SceneResolver.ts`
- `src/game/runtime/scene/resolution/SceneInstantiator.ts`
- `src/game/infrastructure/scenes/SceneDocumentLoader.ts`
- `src/game/infrastructure/scenes/SceneResourceLoader.ts`
- `scripts/tests/scene-runtime/scene-resolution.test.mjs`
- `scripts/tests/scene-runtime/scene-instantiation.test.mjs`
- `scripts/tests/scene-runtime/root-replacement.test.mjs`
- `scripts/tests/scene-runtime/loading-cancellation.test.mjs`

Update:

- `src/game/content/scenes/SceneCatalog.ts`
- `src/game/runtime/scene/SceneTree.ts`

### Steps

1. Implement asynchronous `prepare_scene(sceneId, abortSignal)`. Load and cache
   immutable documents/resources, expand authored instances, apply overrides in
   source-to-outer order, validate the resolved tree, and return a `PackedScene`.
2. Keep authored instance edges separate from dynamic `SceneReferenceDocument`
   fields. Only the authored instance graph participates in construction-cycle
   rejection.
3. Preserve authoring scope for reference-valued overrides. Resolve source values
   relative to their source scene and values injected by a parent override
   relative to the document containing the instance record.
4. Namespace canonical runtime IDs through the complete authored instance path.
   Preserve immutable instance provenance on authored resolved roots. Allocate a
   transient namespace for dynamically instantiated roots and require explicit
   unique persistence keys for any saved dynamic placement.
5. Implement synchronous, side-effect-free `instantiate_scene(packedScene)` that
   returns a detached configured tree. Constructors validate/copy properties only;
   entry creates backend leases later.
6. Implement transactional subtree insertion. Use private staged lookup, resolve
   all required references before callbacks, queue external domain commands, and
   expose the subtree publicly only after ready succeeds. On failure, discard
   commands, remove indexes, exit entered nodes, and release resources.
7. Implement the single-root replacement transaction. Pause the host contract,
   detach the old root, insert/ready the replacement, then free the old root on
   success. On failure restore the old logical animation, timer, velocity, body,
   and signal state and acquire entry leases once.
8. Tie load requests and resource leases to the initiating node/host. Abort map
   loads and dynamic spawns on exit. Ignore late success and release only that
   request's leases.

### Focused checks

Cover deep nested instances, two instances of one source, order merging, local
and outer overrides, injected sibling references, stale override diagnostics,
direct/indirect cycles, allowed dynamic scene references, cancelled loads, failed
resources, constructor/enter/ready failure injection, external-command isolation,
root restoration, and failed restoration fatal state.

### Gate

- A packed scene can be prepared once and instantiated repeatedly without shared
  mutable state.
- Failed preparation/insertion/replacement never exposes a partial tree or domain
  side effect.

### Suggested commit

```text
feat: add packed scene resolution and transactional loading
```

## Work package 4 — Add the Phaser host and presentation nodes

### Files

Create:

- `src/game/infrastructure/scenes/PhaserSceneTreeHost.ts`
- `src/game/infrastructure/scenes/PhaserNodeContext.ts`
- `src/game/infrastructure/scenes/compatibility/LegacyWorldAdapter.ts`
- `src/game/infrastructure/phaser-nodes/PhaserNodeRegistry.ts`
- `src/game/infrastructure/phaser-nodes/Sprite2DNode.ts`
- `src/game/infrastructure/phaser-nodes/Camera2DNode.ts`
- `src/game/infrastructure/phaser-nodes/PresentationSync.ts`
- `scripts/tests/scene-integration/host-order.test.mjs`
- `scripts/tests/scene-integration/presentation-lifecycle.test.mjs`
- `scripts/tests/scene-integration/root-swap.test.mjs`
- `scripts/tests/scene-browser/host-step.spec.ts`
- `scripts/tests/scene-browser/presentation-lifecycle.spec.ts`

Update:

- `src/game/config.ts`
- `src/game/presentation/PhysicsPresentation.ts`
- `src/game/presentation/WorldDepth.ts`
- `src/game/presentation/ResponsiveCameraController.ts`
- `package.json`

### Steps

1. Implement the design's exact host order: prior mutations; timestamped input;
   zero-to-five fixed steps; physics animation; physics process; backend sync;
   one Arcade step; authoritative body-state readback; managed contacts; attack
   resolution; post-physics work; render animation/process; presentation sync;
   final mutation flush.
2. Choose and document one verified integration with Phaser's lifecycle. Disable
   automatic stepping if the host manually advances Arcade Physics. Assert one
   backend step per fixed tick while temporary legacy callbacks coexist.
3. Use the project-owned fixed delta and cap catch-up at five steps. Drop excess
   accumulated time with a development diagnostic. Clear stale accumulated time
   and held-action transitions on resume.
4. Implement `Sprite2D` and `Camera2D` through entry leases. `Node2D` owns logical
   transforms; wrappers create/destroy Phaser objects without exposing them to
   ScriptNodes.
5. Preserve existing texture/frame/origin/scale/tint/alpha/flip/depth and camera
   behavior. Keep world-depth calculation in its presentation owner and reference
   it through a narrow adapter.
6. Add a temporary `LegacyWorldAdapter` with explicit pre-physics, post-physics,
   input, and render hooks. It exists only through work package 15 and never owns
   new scene content.
7. Add `test:scene-integration` to `package.json` and add actual host/backend
   tests to the browser suite created in package 0.

### Focused checks

Use the fake Phaser boundary for exhaustive order/failure cases and the real
browser fixture for backend compatibility. Advance the real host by known
deltas, count actual Arcade world steps, and assert body/sprite state before
and after synchronization. Exercise entry/re-entry, camera teardown, five-step
cap, pause/resume, mutation flushes, and complete destruction in both applicable
suites. A fake-only pass cannot satisfy this package's gate.

### Gate

- A fixture scene displays and removes sprites exclusively through the host.
- Legacy and managed paths cannot both advance Arcade Physics.
- Presentation nodes can detach/re-enter without replaying `_ready()`.
- `pnpm test:scene-browser` passes the real host/presentation fixtures; evidence
  records actual engine steps and resource counters.

### Suggested commit

```text
feat: host universal scene trees in Phaser
```

## Work package 5 — Implement bodies, areas, shapes, and contact routing

### Files

Create:

- `src/game/runtime/scene/physics/PhysicsContact.ts`
- `src/game/runtime/scene/physics/SensorGeometry.ts`
- `src/game/runtime/scene/physics/ContactRouter.ts`
- `src/game/infrastructure/phaser-nodes/PhysicsBody2DNode.ts`
- `src/game/infrastructure/phaser-nodes/CharacterBody2DNode.ts`
- `src/game/infrastructure/phaser-nodes/StaticBody2DNode.ts`
- `src/game/infrastructure/phaser-nodes/Area2DNode.ts`
- `src/game/infrastructure/phaser-nodes/CollisionShape2DNode.ts`
- `scripts/tests/scene-runtime/sensor-geometry.test.mjs`
- `scripts/tests/scene-integration/physics-nodes.test.mjs`
- `scripts/tests/scene-integration/contact-routing.test.mjs`
- `scripts/tests/scene-conversion/legacy-collision-parity.test.mjs`
- `scripts/tests/scene-browser/physics-contacts.spec.ts`

Reuse/update:

- `src/game/shared/collisionShapes.ts`
- `src/game/features/characters/characterHitboxGeometry.ts`
- `src/game/combat/CombatBodyGeometry.ts`
- `src/game/combat/ContactPoint.ts`
- `src/game/config.ts`

### Steps

1. Implement blocking `CharacterBody2D`/`StaticBody2D` with exactly one enabled
   axis-aligned rectangle or circle shape. Validate positive scale, uniform circle
   world scale, no rotation/shear, and invalid ancestor transforms.
2. Implement sensor-only `Area2D` with one or more shapes combined as a union:
   rectangle, circle, ellipse, and directional sector. Preserve explicit sector
   angle, arc width, inner/outer radius, directional offsets, and existing
   boundary conventions.
3. Use Arcade for blocking resolution and spatial candidate filtering. Use the
   shared pure geometry routines for ellipse and sector contacts; do not create
   fake Arcade ellipses or silently use bounds for sensors.
4. Preserve legacy ellipse movement collision by converting it to the exact
   effective bounding rectangle calculated by `shared/collisionShapes.ts`.
   Create ellipse sensors only where the legacy runtime actually used sensing.
5. Implement membership layers and observer masks. Require mutual acceptance for
   blocking bodies; make area monitoring directional. Canonicalize owner pairs
   and shape IDs so multiple shape overlaps emit one owner enter/exit while
   detailed contact data retains contributing shapes.
6. Reconcile current overlap sets every fixed step. Enabling an overlapping area
   produces an enter next step. Disable/detach/free invalidates the pair for
   damage immediately and provides one stable-ID exit to surviving observers.
7. After Arcade advances, copy authoritative body position/velocity into logical
   Node2D state, recompute descendant sensors, then route contacts. Expose previous
   step blocking records to `_physics_process` and current step signals afterward.
8. Expose world-unit velocity and queued teleport. Do not implement a misleading
   synchronous `move_and_slide`/`move_and_collide` API.

### Focused checks

Cover all shape-pair combinations, exact boundaries, sector facing and inner
radius, compound sensor union, duplicate pair suppression, masks/layers, enable/
disable, detach/free exits, rectangle/circle blocking, ellipse legacy bounds,
post-step readback, teleport, and rejection of rotated/scaled invalid bodies.
The browser fixture must reproduce one real blocking collision, a sensor pair
following post-step body motion, disable/free exit reconciliation, and zero
remaining bodies/colliders after teardown. Pure geometry tests alone do not
establish synchronization with Arcade.

### Gate

- Existing sword and goo-gauntlet sector fixtures match their pre-refactor
  contact decisions.
- Existing character movement bodies match effective legacy bounds.
- No gameplay label appears in a physics node type.

### Suggested commit

```text
feat: add universal physics and sensor nodes
```

## Work package 6 — Unify animation, audio, input, ScriptNodes, and minimal Control

### Files

Create:

- `src/game/runtime/scene/animation/AnimationPlayerNode.ts`
- `src/game/runtime/scene/animation/AnimationBinding.ts`
- `src/game/runtime/scene/animation/AnimationEvent.ts`
- `src/game/runtime/scene/input/InputEvent.ts`
- `src/game/runtime/scene/input/InputRouter.ts`
- `src/game/runtime/scene/scripts/ScriptNode.ts`
- `src/game/runtime/scene/ui/ControlNode.ts`
- `src/game/infrastructure/phaser-nodes/AudioStreamPlayerNode.ts`
- `src/game/infrastructure/phaser-nodes/AudioStreamPlayer2DNode.ts`
- `src/game/infrastructure/phaser-nodes/ControlPresentationAdapter.ts`
- `scripts/tests/scene-runtime/animation-player.test.mjs`
- `scripts/tests/scene-runtime/script-node.test.mjs`
- `scripts/tests/scene-runtime/input-routing.test.mjs`
- `scripts/tests/scene-integration/audio-lifecycle.test.mjs`
- `scripts/tests/scene-integration/control-input.test.mjs`
- `scripts/tests/scene-browser/control-audio-lifecycle.spec.ts`

Reuse/update:

- `src/game/shared/animation/`
- `src/game/core/Input.ts`
- `src/game/ui/ModalStack.ts`
- `src/game/features/visuals/LayeredAnimationHost.ts`
- `src/game/features/visuals/LayeredAnimationVisual.ts`

### Steps

1. Build `AnimationPlayer` around the existing shared animation clock, timeline,
   layered documents, transform composition, and validation. Migrate behavior
   into common modules where necessary instead of creating a parallel timeline.
2. Add named typed bindings from reusable animation resources to stable scene
   references. Inline animations may reference local nodes directly.
3. Enforce one master clock per player and physics mode for collision, attack,
   or gameplay event tracks. Ensure associated visual tracks use the same clock.
4. Implement step/numeric interpolation from property descriptors, deterministic
   event ordering across loop boundaries, seek-without-gameplay-events for
   preview, cancellation baseline restoration, and conflicting-writer rejection.
5. Implement positional and non-positional audio nodes through the existing
   effects/music preference and browser-unlock services. Stop one-shots on exit;
   restore explicitly playing loops from logical state where supported.
6. Implement `ScriptNode` registry construction, immutable `scriptId`, metadata
   inheritance, exported references, expected capabilities, configuration
   warnings, typed signals/handlers, source navigation, and exclusive-capability
   conflicts.
7. Give scripts typed access to runtime nodes and narrowly scoped domain services.
   Keep reusable damage math, inventory, quests, saves, and animation engines out
   of entity scripts.
8. Implement input routing across DOM, focused/modal Control, `_input`, and
   `_unhandled_input`, with one handled flag. Gameplay actions use unhandled input.
   Controls marked `processWhenPaused` remain available during pause.
9. Implement only enough `Control` layout/focus/visibility/input/theme behavior
   to prove the registry and later UI conversion. Do not move all UI yet.

### Focused checks

Cover master-clock parity, exact event positions, loop boundaries, seek/preview,
cancel/replace cleanup, binding validation, script inheritance conflicts, multiple
ScriptNodes with distinct capabilities, exclusive conflicts, input consumption,
pause, audio unlock, audio preview cleanup, and detach/re-entry.
Real-browser assertions verify DOM event consumption reaches the shared handled
flag and prevents the synthetic gameplay-action callback, plus actual audio
object/unlock/cleanup lifecycle. Audible quality remains a user check.

### Gate

- One fixture scene combines sprite, body, area, animation, audio, Control, and
  ScriptNode without category-specific runtime code.
- The old shared animation behavior remains represented once.

### Suggested commit

```text
feat: add animation audio input and script nodes
```

## Work package 7 — Build Scene Studio document state and safe file ownership

### Files

Create:

- `src/game/editor/scene-studio/SceneStudio.ts`
- `src/game/editor/scene-studio/SceneStudioRoute.ts`
- `src/game/editor/scene-studio/SceneDocumentState.ts`
- `src/game/editor/scene-studio/SceneSelectionState.ts`
- `src/game/editor/scene-studio/SceneCommand.ts`
- `src/game/editor/scene-studio/SceneHistory.ts`
- `src/game/editor/scene-studio/SceneClipboard.ts`
- `src/game/editor/scene-studio/SceneValidationState.ts`
- `src/game/infrastructure/scenes/editor/SceneStudioRepository.ts`
- `src/game/infrastructure/scenes/editor/SceneStudioContentPlugin.ts`
- `src/game/infrastructure/scenes/editor/ContentWriteJournal.ts`
- `src/game/editor/scene-studio/scene-studio.css`
- `scripts/tests/scene-studio/document-state.test.mjs`
- `scripts/tests/scene-studio/history.test.mjs`
- `scripts/tests/scene-studio/repository.test.mjs`
- `scripts/tests/scene-studio/route.test.mjs`

Update:

- `src/game/config.ts`
- `vite.config.ts`
- `src/vite-env.d.ts`
- `src/styles.css`
- `package.json`

### Steps

1. Add one development route, `?studio=scenes&scene=<SceneId>`, and one mount
   function. Keep old routes during construction but do not add another editor
   shell for any new content.
2. Create a document state that edits scenes/resources through immutable commands.
   Support add, delete, rename, reorder, duplicate, reparent, property edit,
   instance add/remove, override/revert, resource reference, and signal wiring.
3. Use the exact runtime validation and property descriptors. Do not copy node
   schemas into editor-specific conditionals.
4. Implement command-level undo/redo, dirty tracking, selection restoration, and
   multi-document tabs. A command changing multiple references is atomic.
5. On referenced-node deletion, calculate affected references and require an
   explicit command result: cancel, remove optional references, or choose repairs.
   Do not silently clear unrelated fields.
6. Create a single Vite endpoint/repository for scene/resource read and write.
   Validate ID/path containment, payload size, version/hash preconditions, full
   document schema, resource references, and canonical formatting.
7. Implement a recoverable multi-file write journal in the Node-side Vite plugin.
   Before changing targets, place exact originals and a manifest in a transaction
   directory. Write validated temporary files beside each target, then replace in
   stable path order. Mark the journal committed only after every replacement.
   On failure restore every original; on server startup recover any uncommitted
   journal before accepting writes. The browser repository sends the complete
   write set and keeps editor state dirty until the committed response.
   Export the Node-only journal module for the conversion runner as well; both
   writers use the same validation, hash-precondition, and recovery contract.
8. Load invalid development documents in repair mode and preserve unknown fields
   as opaque data. Production validators and gameplay still reject invalid data.
9. Add `test:scene-studio` and include its non-Phaser state/repository tests in
   the standard check.

### Focused checks

Cover every command and inverse, sibling ordering, root replacement command,
reference repair, invalid drafts, unknown field preservation, stale hash conflict,
path traversal, unknown IDs, partial write failure restoration, dirty-state
retention, and route round trips.

### Gate

- Scene Studio is the sole writer for version-1 scene documents/resources.
- Saving cannot bypass runtime validation or overwrite a newer disk version.
- Editor state and repository contain no character/enemy/boss-specific branches.

### Suggested commit

```text
feat: add universal Scene Studio document workflow
```

## Work package 8 — Build the common tree, inspector, viewport, resources, and preview

### Files

Create:

- `src/game/editor/scene-studio/SceneTreePanel.ts`
- `src/game/editor/scene-studio/SceneCreationDialog.ts`
- `src/game/editor/scene-studio/SceneInspector.ts`
- `src/game/editor/scene-studio/PropertyEditorRegistry.ts`
- `src/game/editor/scene-studio/SceneViewport.ts`
- `src/game/editor/scene-studio/ViewportSelection.ts`
- `src/game/editor/scene-studio/ShapeEditor.ts`
- `src/game/editor/scene-studio/ResourceBrowser.ts`
- `src/game/editor/scene-studio/ResourceInspector.ts`
- `src/game/editor/scene-studio/ScenePreview.ts`
- `src/game/editor/scene-studio/contexts/AnimationContext.ts`
- `src/game/editor/scene-studio/contexts/AudioContext.ts`
- `src/game/editor/scene-studio/contexts/SignalContext.ts`
- `src/game/editor/scene-studio/contexts/DebugContext.ts`
- `scripts/tests/scene-studio/tree-panel.test.mjs`
- `scripts/tests/scene-studio/inspector.test.mjs`
- `scripts/tests/scene-studio/viewport-shapes.test.mjs`
- `scripts/tests/scene-studio/resource-editing.test.mjs`
- `scripts/tests/scene-studio/preview-isolation.test.mjs`
- `scripts/tests/scene-studio/authoring-walkthrough.test.mjs`
- `scripts/tests/scene-browser/studio-controls.spec.ts`
- `scripts/tests/scene-browser/preview-isolation.spec.ts`

Reuse/update:

- `src/game/editor/StudioHistoryShortcut.ts`
- `src/game/editor/StudioLibraryTree.ts`
- `src/game/editor/PreviewZoom.ts`
- `src/game/editor/EditorGeometryStyles.ts`
- `src/game/editor/LayeredAnimationDocumentState.ts`
- `src/game/editor/LayeredAnimationPreviewPanel.ts`
- `src/game/editor/LayeredAnimationTimelinePanel.ts`
- `src/game/editor/LayeredAnimationTimelineView.ts`
- `src/game/editor/WeaponHitboxGuides.ts`
- `src/game/editor/WeaponHitboxPreview.ts`

### Steps

1. Build one stable shell: project/scene/resource browser, open document tabs,
   scene tree, 2D viewport, generated inspector, and selected-node context panel.
2. Drive the searchable creation dialog from node registrations. Add optional
   templates for common assemblies, but save ordinary nodes and ScriptNodes; a
   template must not create a hidden runtime/editor category.
3. Render local nodes and instance records in one ordered tree. Make resolved
   instance descendants structurally read-only. Permit source navigation,
   overridable properties, override origin, revert, and instance-level rename/
   reorder/move/duplicate/delete.
4. Generate inspector groups, controls, help, units, constraints, defaults,
   reset, animation affordance, resource picker, stable node picker, and override
   status from descriptors. ScriptNode shows registered ID, source path, exports,
   expected references, signals, capabilities, and warnings.
5. Build viewport selection and handles for Node2D transforms and valid shape
   geometry. Display authored and effective collision regions where they differ.
   Prevent unsupported body rotation/nonuniform circle scale at edit time.
6. Add shared resource consumers list plus edit-shared/make-unique. Local override
   edits must never mutate a shared resource implicitly.
7. Adapt the existing common animation workbench into the AnimationPlayer context.
   Add arbitrary property tracks, typed bindings, events, physics/render domain,
   playback, and seek-only preview. Reuse its clock and layered preview logic.
8. Add audio inspection/explicit preview, signal wiring, and a diagnostics panel
   for validation, lifecycle errors, reference resolution, and resource leaks.
9. Implement preview with a disposable presentation tree and a capability set
   that excludes gameplay/domain/persistence services. Disable ScriptNodes,
   display gameplay events as markers, and stop all preview resources on close.
10. Add keyboard navigation, visible focus, labels, readable errors, stable
    selection through validation/save, and responsive panels.

### Focused checks

Use Node suites for document/model interactions and the real-browser suite for
mounted controls. Cover common inspector reuse across entity templates,
local/instance editing, make-unique, viewport constraints, timeline domain,
preview isolation, focus, undo/redo, save conflict, and source navigation.
Playwright exercises accessible labels/keyboard operations in actual Chromium;
repository tests use temporary content roots, never authored production files.

### Gate

- The design's ordinary-enemy authoring walkthrough works against fixtures.
- Preview cannot call gameplay services or write saves even with a malicious or
  misregistered ScriptNode fixture.
- The common controls contain no Fatty/boss-specific UI implementation.

### Suggested commit

```text
feat: complete common Scene Studio authoring tools
```

## Work package 9 — Prove the complete vertical slice with Worm Brawler and Fatty

### Files

Create:

- `src/game/features/scripts/CharacterScript.ts`
- `src/game/features/scripts/EnemyScript.ts`
- `src/game/features/scripts/FattyScript.ts`
- `src/game/features/scripts/BossCampScript.ts`
- `src/game/features/scripts/ChestScript.ts` (guard/contents/transfer foundation;
  completed for all chest content in package 12)
- `src/game/features/scripts/registrations.ts`
- `src/game/features/combat/DamageReceiver.ts`
- `src/game/features/combat/DamageResolver.ts`
- `src/game/features/combat/DamageRouter.ts`
- `src/game/features/combat/AttackActivation.ts`
- `src/game/features/player/PlayerHealthService.ts`
- `src/game/features/player/PlayerServicePorts.ts`
- `src/game/infrastructure/scenes/compatibility/LegacyPlayerBridge.ts`
- `src/game/infrastructure/scenes/compatibility/LegacyCombatBridge.ts`
- `src/game/infrastructure/scenes/compatibility/LegacyChestUiBridge.ts`
- `src/game/infrastructure/scenes/compatibility/LegacyBossUiBridge.ts`
- `src/game/infrastructure/scenes/compatibility/LegacyMapPlacementBridge.ts`
- `src/game/content/scenes/characters/worm-brawler.scene.json`
- `src/game/content/scenes/characters/fatty-one-eye.scene.json`
- `src/game/content/scenes/encounters/level-1-fatty-camp.scene.json`
- `src/game/content/scenes/objects/chest-wooden.scene.json` (minimum camp dependency)
- `scripts/tests/scene-content/damage-rules.test.mjs`
- `scripts/tests/scene-integration/worm-brawler-scene.test.mjs`
- `scripts/tests/scene-integration/fatty-scene.test.mjs`
- `scripts/tests/scene-integration/boss-camp-scene.test.mjs`
- `scripts/tests/scene-studio/enemy-fatty-parity.test.mjs`
- `scripts/tests/scene-integration/legacy-scene-bridges.test.mjs`
- `scripts/tests/progression/player-health-service.test.mjs`
- `scripts/lib/scene-conversion/animations.mjs`
- `scripts/lib/scene-conversion/characters.mjs`
- `scripts/lib/scene-conversion/boss-camps.mjs`
- `scripts/lib/scene-conversion/objects.mjs` (chest fixture first)

Update/adapt:

- `src/game/enemies/Enemy.ts`
- `src/game/enemies/EnemyAI.ts`
- `src/game/enemies/enemyCombatLifecycle.ts`
- `src/game/enemies/library/EnemyTypes.ts`
- `src/game/features/bosses/FattyOneEyeBoss.ts`
- `src/game/features/bosses/FattyOneEyeBehavior.ts`
- `src/game/features/bosses/BossCampController.ts`
- `src/game/features/bosses/BossCampBehavior.ts`
- `src/game/features/combat/CombatController.ts`
- `src/game/systems/HealthSystem.ts`
- `src/game/systems/StatusEffects.ts`
- current Worm/Fatty character, visual-set, animation, and boss content
- `src/game/content/maps/level-1.map.json`

### Steps

Before wiring the slice, implement the service and compatibility boundaries
listed below. Its legacy player, weapon, and UI dependencies are deliberate
adapters with contract tests, not future package assumptions.

1. Implement a shared `DamageReceiver` capability and pure normalized request/
   result resolver usable by player, enemy, and destructible scripts. Register
   receiver areas on entry; enforce one receiver per area and unregister on exit.
2. Validate matcher OR/AND semantics, blocked tags, damage/effect multipliers,
   priorities, and state-dependent script rejection. Preserve existing balance
   values; the refactor does not rebalance damage, knockback, effects, rewards,
   cooldowns, or invulnerability.
3. Implement attack activation IDs, per-step contact grouping, selected-area
   priority, accepted-hit deduplication, retryable state blocking, and area-set
   sensitive rejected-hit caching. Confirm that armor contact does not suppress a
   later weak-point hit in the same activation.
4. Implement `CharacterScript` common state/helpers and `EnemyScript` faction,
   rank, attributes, targeting, movement settings, health, damage/effects,
   rewards, and death signals. Rank is metadata; faction owns hostility.
5. Convert Worm Brawler as the ordinary-enemy fixture using nodes for body,
   visuals, animation, areas, audio, and `EnemyScript`. Preserve its targeting,
   attack, damage, feedback, reward, and death behavior.
6. Convert Fatty to the same scene shape with `rank: "boss"` and `FattyScript
   extends EnemyScript`. Model body collision, eye damage area, contact-hop attack
   area, animation events, and audio through common nodes. Preserve grounded eye
   weapon filtering, airborne immunity, hop/leap phases, return, death, and
   respawn behavior.
7. Convert the boss camp to `BossCampScript`: authored activation/arena areas,
   boss spawn, active-boss container, eager chest instance, dynamic Fatty scene
   reference, respawn, boss UI signal, and guarded-chest state. Preserve existing
   persistence keys and map placement ID.
   Implement ChestScript's guard input, existing contents/remaining-state access,
   open/transfer intents, and InventoryWorldTransaction calls here. Use
   LegacyChestUiBridge to present the existing panel; package 12 generalizes
   object conversion, and package 14 replaces the panel adapter.
8. Route combat feedback only from confirmed results. Animation markers cannot
   independently synthesize an accepted hit or reward.
9. Use LegacyMapPlacementBridge to resolve the existing authored Level 1 camp
   and its chest into scene placements inside the current world. Suppress the
   corresponding legacy constructors/spawns so each authored ID has one live
   owner. Synthetic standalone fixtures are allowed in the test harness, but
   production world composition may not inject an extra camp or chest.
10. Exercise the same Scene Studio controls for Worm and Fatty. The only differing
    inspector content must come from their ScriptNode exports/resources.

### Required bridges and service foundation

| Boundary | Contract and call direction | Retire/replace |
| --- | --- | --- |
| LegacyPlayerBridge | Implements typed player position/body/dodge/health/knockback ports using the existing sprite; exposes a synthetic receiver registration to managed damage routing and forwards accepted health changes through PlayerHealthService | Package 10 installs PlayerScript and node-backed ports |
| LegacyCombatBridge | Converts active legacy weapon contacts into normalized attack requests for managed receivers; supplies legacy weapon input/facing/player handles until weapon conversion; maps source runtime ID + monotonic activation sequence and suppresses the original damage path for bridged pairs | Package 11 switches the final legacy weapon/projectile path to ScriptNodes |
| LegacyChestUiBridge | ChestScript passes a typed view model and transfer/close actions to the existing ChestInventoryPanel; the panel cannot mutate world state directly | Package 14 UI scenes |
| LegacyBossUiBridge | Consumes camp/enemy health/defeat signals to update the existing BossHealthBar | Package 14 UI scenes |
| LegacyMapPlacementBridge | Reads authored map records, preserves IDs/keys and translates scene-enabled placements; ensures old factories skip those same placements | Package 13 world scene cutover |

All bridges are entry-owned infrastructure objects. Script contexts accept their
typed ports, never Phaser types or an import of a legacy controller. During
coexistence, LegacyCombatBridge delegates managed requests to the same
AttackActivation/DamageRouter, and backend callbacks only collect candidates;
only one designated route commits a given source/receiver pair. Managed Fatty
attacks reach the registered legacy player receiver through LegacyPlayerBridge.
Explicitly test both directions, repeated callbacks, source cancellation, and
bridge disposal. At package 10 the player bridge disappears while the combat
bridge uses the new player's ports until package 11; ownership never overlaps.
LegacyPlayerBridge's sensor proxy follows post-step legacy body geometry; it
does not create a second blocking body. Existing body callbacks and sensor
candidates share the same source/receiver identity so they cannot double-hit.

Extract PlayerHealthService from HealthSystem here because the slice can damage
the legacy player. Preserve defense, true-damage semantics, status modifiers,
rounding, i-frames, actual HP loss, death-once, and existing domain events.
The service accepts plain damage data plus simulation time and state/stats ports;
it returns outcomes/intents. The legacy wrapper applies knockback/flash to Phaser
through ports until PlayerScript replaces it. The shared damage route must call
health mitigation exactly once: area/source eligibility is resolved first, then
the player service owns its existing mitigation pipeline. Add equivalence tests
against captured HealthSystem cases before redirecting callers.

Build the four initial converters through the common runner and generate Worm,
Fatty, their animations, the camp, and minimum chest from current content. Test
two dry runs and replay in isolated output directories before writer cutover.

### Focused checks

Move or reproduce all relevant existing combat/boss assertions before retiring
their owners. Cover Worm movement/attacks/death/rewards; Fatty eye filtering,
ground/air state, contact hop, leap, return, defeat/respawn; area priority; zero
damage plus effect; immune/dead/invalid results; no duplicate rewards; camp/chest
signals; cleanup; editor parity; and save-key preservation.
The slice gate additionally requires managed-to-legacy and legacy-to-managed
damage, one player health commit, one authored chest/camp instance, adapter lease
cleanup, and existing panel behavior through the typed ports. No dependency on
packages 11, 12, or 14 may remain unexplained at this gate.

### Gate

- Worm and Fatty run through the same runtime and authoring model.
- Fatty has no separate `boss` character document kind or boss-only editor path.
- All relevant existing boss/combat suites and new scene suites pass.
- Record the first replacement performance comparison.

### Suggested commit

```text
feat: prove universal enemy and boss scene slice
```

## Work package 10 — Convert the player, remaining enemies, and NPCs

### Files

Create:

- `src/game/features/scripts/PlayerScript.ts`
- `src/game/features/scripts/NpcScript.ts`
- `src/game/features/player/PlayerAbilityService.ts`
- `src/game/features/player/PlayerNodePorts.ts`
- `src/game/features/player/PlayerAbilityPresentation.ts`
- `scripts/tests/progression/player-ability-service.test.mjs`
- `scripts/tests/scene-integration/player-service-ports.test.mjs`
- `scripts/tests/scene-integration/player-ability-nodes.test.mjs`
- `src/game/features/scripts/SlimeSpiderScript.ts` only if its AI cannot be a
  policy/resource consumed by `EnemyScript`
- one scene document per remaining character under
  `src/game/content/scenes/characters/`
- reusable AI/movement resources where multiple scenes share configuration
- `scripts/tests/scene-conversion/character-conversion.test.mjs`
- `scripts/tests/scene-integration/player-scene.test.mjs`
- `scripts/tests/scene-integration/enemy-scenes.test.mjs`
- `scripts/tests/scene-integration/npc-scenes.test.mjs`

Update/adapt:

- `src/game/features/player/PlayerController.ts`
- `src/game/features/player/PlayerFactory.ts`
- `src/game/systems/AbilitySystem.ts`
- `src/game/systems/HealthSystem.ts`
- `src/game/systems/StatusEffects.ts`
- `src/game/features/player/PlayerHealthService.ts`
- `src/game/features/player/PlayerServicePorts.ts`
- `src/game/infrastructure/scenes/compatibility/LegacyCombatBridge.ts`
- `scripts/lib/scene-conversion/characters.mjs`
- `scripts/lib/scene-conversion/animations.mjs`
- `src/game/enemies/EnemySpawner.ts`
- `src/game/enemies/ai/SlimeSpiderAI.ts`
- `src/game/features/npcs/NpcActor.ts`
- `src/game/features/npcs/NpcRuntimeController.ts`
- `src/game/features/npcs/NpcWanderPolicy.ts`
- `src/game/features/interaction/QuestNpcController.ts`
- `src/game/content/characters/`
- `src/game/content/npcs/`
- `src/game/content/player.ts`
- `src/game/core/Input.ts`
- `src/game/scenes/WorldScene.ts`

### Steps

1. Convert every remaining `character.json`/visual set and any standalone NPC
   definition to a scene plus reusable resources. Preserve character IDs,
   spritesheet frames, origins, scaling, body bounds, animation timing, hit areas,
   wander geometry, enemy attributes, rewards, and map references.
2. Keep player balance/progression values in `game-constants.json`; `PlayerScript`
   references those domain settings and must not copy them into scene exports.
3. Convert player visual/body/input/health/energy/equipment/dodge/ability signals
   to nodes and PlayerScript. Retain progression, inventory, and loadout domain
   ownership. Extract the engine-dependent AbilitySystem operations into the
   service/port boundary below and finish replacing the legacy HealthSystem
   wrapper; retaining domain ownership does not mean retaining Phaser-dependent
   interfaces or direct presentation construction.
4. Route input through the SceneTree handled/unhandled contract. Preserve keyboard,
   mouse, controller, debug-cheat separation, modal locking, and current action
   timings.
5. Replace `EnemySpawner` construction with packed-scene selection and dynamic
   instantiation. Preserve authored spawn areas, weighted entries, per-type caps,
   safe zones, respawn cadence, population cap, despawn policy, and fresh runtime
   namespaces.
6. Convert common enemy AI into `EnemyScript` configuration/policies. Add a
   specialized script only for behavior that cannot be expressed through shared
   policy without serialized expressions.
7. Convert NPC presentation, movement, interaction, and quest locking. Keep quest
   rules in `QuestService`/interaction features; `NpcScript` emits typed intent and
   consumes injected capabilities.
8. Change world composition to query node groups/capabilities for player, target,
   NPC, and interaction membership instead of using `instanceof` entity classes.
9. Mark old character/NPC catalogs read-only adapters once all references resolve
   to scenes. Redirect Character Studio to the equivalent Scene Studio scene.

### Player service extraction and node ports

1. PlayerAbilityService owns unlock/cooldown/energy/busy-state decisions for jump,
   teleport, squash-slam, and stretch-lash. Preserve current numerical values,
   targets, collision stopping, cancellation, and domain events. Store them with
   their existing balancing owner or a named owning-feature definition, without
   a second editable copy. Inject plain vectors, terrain-query and state ports,
   and a simulation clock; no Phaser, sprite, group, tween, or scene timer enters
   its public interface.
2. PlayerNodePorts applies movement/teleport through CharacterBody2D, damage and
   targeting through DamageRouter/registered capabilities, and animation/audio
   through node references. PlayerAbilityPresentation orchestrates existing
   visual intents using scene nodes and their entry leases. Move shadow, ring,
   afterimage, particle, and feedback creation out of AbilitySystem; the actor
   script owns the intents and backend adapters own rendering. Preserve existing
   procedural assets, but never create live Phaser objects inside a domain service.
3. Bring minimum ability-owned Area2D/AnimationPlayer/effect-node assemblies into
   this package so ability damage does not wait for weapon/effect conversion.
   Shared reusable effect resources may be promoted by package 11; no second
   attack or animation engine is introduced here.
4. Bind PlayerHealthService's outcomes to player-node knockback/flash/death
   handling. Adapt StatusEffects to injected simulation time and existing domain
   state/events, retaining its calculation rules. Convert simulation seconds to
   existing millisecond policy inputs in one clock adapter. Epoch time remains
   exclusive to persisted real-time deadlines such as camp respawn.
5. Remove LegacyPlayerBridge and the old health/ability wrappers once equivalence
   tests pass. Update LegacyCombatBridge to use the new player ports until
   package 11. Add an import-boundary test rejecting Phaser, Hitbox/TargetDummy,
   scene timers, and direct sprite/tween construction in player domain services
   and ScriptNodes.

Service tests cover exact cooldown/energy/mitigation boundaries, true damage,
i-frames, status ticks, death-once, cancel/death/exit, and paused simulation time.
Node integration tests cover jump/teleport stopping, both ability attacks routed
once, knockback versus movement ownership, and cleanup of every ability visual.
These deterministic cases do not replace the user's gameplay checklist.

### Focused checks

Require the conversion ledger to cover every character/NPC. Preserve existing
character-studio, NPC, progression, input, enemy spawn, combat, animation, and
cleanup expectations in replacement tests. Test two concurrent instances of each
enemy scene for independent state and stable authored references.

### Gate

- No runtime character is directly constructed by PlayerFactory, Enemy, NpcActor,
  or their spawners.
- All character and NPC authoring opens Scene Studio.
- Save/load preserves player and world state through existing domain adapters.

### Suggested commit

```text
feat: convert all characters to universal scenes
```

## Work package 11 — Convert weapons, projectiles, and effects

### Files

Create:

- `src/game/features/scripts/WeaponScript.ts`
- `src/game/features/scripts/ProjectileScript.ts`
- `src/game/features/scripts/EffectScript.ts` only for effects requiring behavior
- scene documents under `src/game/content/scenes/weapons/`
- scene documents under `src/game/content/scenes/projectiles/`
- scene documents under `src/game/content/scenes/effects/`
- shared animation/effect resources referenced by those scenes
- `scripts/tests/scene-conversion/weapon-conversion.test.mjs`
- `scripts/tests/scene-conversion/projectile-effect-conversion.test.mjs`
- `scripts/tests/scene-integration/weapon-scenes.test.mjs`
- `scripts/tests/scene-integration/projectile-scenes.test.mjs`
- `scripts/tests/scene-integration/effect-scenes.test.mjs`
- `scripts/lib/scene-conversion/weapons.mjs`
- `scripts/lib/scene-conversion/projectiles.mjs`
- `scripts/lib/scene-conversion/effects.mjs`

Update/adapt:

- `src/game/combat/Weapon.ts`
- `src/game/combat/Hitbox.ts`
- `src/game/combat/WeaponAttackTrackRunner.ts`
- `src/game/features/combat/CombatController.ts`
- `src/game/features/combat/WeaponVisual.ts`
- `src/game/enemies/Projectile.ts`
- `src/game/features/effects/WorldEffectAdapter.ts`
- `src/game/features/effects/WorldEffectPool.ts`
- `src/game/features/effects/WorldEffectPositionAttachment.ts`
- `src/game/content/weapons/`
- `src/game/content/projectiles/`
- `src/game/content/effects/`
- `src/game/content/animations/weapons/`
- `src/game/systems/WeaponLoadout.ts`
- `scripts/lib/scene-conversion/animations.mjs`
- `src/game/infrastructure/scenes/compatibility/LegacyCombatBridge.ts`

### Steps

1. Convert every weapon to a reusable scene with visual nodes, AnimationPlayer,
   attack `Area2D` shapes, audio, and `WeaponScript`. Preserve item/weapon IDs,
   equipment ownership, directional idle/attack presentation, combo/cooldown,
   damage, knockback, targeting, hit effect, and inventory stack behavior.
2. Convert sector, rectangle, circle, and ellipse attack areas without changing
   coverage. Animation physics tracks own activation/deactivation; cancellation,
   scene exit, and weapon switching clear areas and activation IDs.
3. Keep `WeaponLoadout` and inventory authoritative. `CombatController` becomes a
   feature adapter that requests scene instances and reacts to script signals,
   then shrinks or is removed when no orchestration remains.
4. Convert projectiles to pooled scene instances with presentation, body/sensor,
   movement, ownership, impact, range/lifetime, and cleanup. Pooling uses detach/
   re-entry contracts; reset transient script state explicitly before reuse and
   never copy persistence keys.
5. Convert effects to scenes using visuals, animations, audio, and optional
   minimal behavior. Preserve confirmed-hit anchoring, depth following, freeze at
   last position after target destruction, deterministic completion, and pooling.
6. Route all damage through `DamageRouter`; remove direct target-class branching
   and old hitbox-specific damage application after parity checks pass.
7. Redirect Weapon, Projectile, Effect, and Animation Studio deep links to the
   corresponding scene/AnimationPlayer/resource context.
8. Run the common runner's weapons/projectiles/effects adapters, with animation
   dependencies resolved through animations.mjs. Require dry-run/apply/check,
   idempotency, and source-hash conflict tests for each family. Remove
   LegacyCombatBridge after both directions use only node-based combat, and
   assert old callbacks cannot still apply damage.

### Focused checks

Cover every ledger ID, directional weapon bindings, sector parity, exact active
frames, one accepted hit per activation, intentional multi-hit pulses, weapon
switch cancellation, projectile pool reset, effect cleanup/attachment, resource
hit feedback only after positive damage, and loadout/inventory integration.

### Gate

- Every weapon/projectile/effect is instantiated from a scene.
- One AnimationPlayer implementation owns their timelines.
- No legacy studio remains writable for these families.

### Suggested commit

```text
feat: convert combat entities and effects to scenes
```

## Work package 12 — Convert props, resources, collectibles, chests, and interactions

### Files

Create:

- `src/game/features/scripts/DestructibleScript.ts`
- `src/game/features/scripts/ResourceNodeScript.ts`
- `src/game/features/scripts/CollectibleScript.ts`
- `src/game/features/scripts/InteractionScript.ts`
- scene documents under `src/game/content/scenes/objects/`
- shared object visual/animation resources
- `scripts/tests/scene-conversion/object-conversion.test.mjs`
- `scripts/tests/scene-integration/object-scenes.test.mjs`
- `scripts/tests/scene-integration/collectible-resource-scenes.test.mjs`
- `scripts/tests/scene-integration/chest-interaction-scenes.test.mjs`

Update/adapt:

- `src/game/features/objects/ObjectFactory.ts`
- `src/game/features/scripts/ChestScript.ts` (extend the package 9 foundation;
  preserve its registry ID)
- `src/game/features/objects/ObjectAnimationAdapter.ts`
- `src/game/features/resources/ResourceNodeController.ts`
- `src/game/features/resources/ResourceDropPlacement.ts`
- `src/game/features/collectibles/CollectibleController.ts`
- `src/game/features/collectibles/InventoryDropController.ts`
- `src/game/features/collectibles/WorldDropSpawner.ts`
- `src/game/features/chests/ChestController.ts`
- `src/game/features/interaction/InteractionRouter.ts`
- `src/game/features/occlusion/OcclusionController.ts`
- `src/game/content/objects/`
- `src/game/content/visuals/`
- `src/game/features/progression/InventoryWorldTransaction.ts`
- `src/game/features/progression/WorldProgress.ts`
- `scripts/lib/scene-conversion/objects.mjs`
- `src/game/infrastructure/scenes/compatibility/LegacyChestUiBridge.ts`

### Steps

1. Convert every object archetype/visual variant to reusable scenes/resources:
   decorations, walls, houses, rocks, trees, resource nodes, collectibles, NPC
   placements, chests, and current/future interaction objects.
2. Express sprites, solid body shapes, overlap areas, depth/occlusion bounds,
   animation, and audio as common nodes. Use scripts only for actual behavior.
   Static presentation-only props need no ScriptNode.
3. Preserve object IDs, visual IDs, map instance IDs, variants, frame selection,
   scaling, offsets, depth, occlusion, collision, hit animations/effects, resource
   tags, durability/yield, and persistence keys.
4. Implement damageable props through the shared DamageReceiver capability, not
   EnemyScript. Preserve tool/tag requirements, positive-damage feedback, drops,
   and depletion/destroyed state.
5. Convert collectibles and dynamic inventory drops. Preserve source-resource/
   inventory-drop IDs, placement, motion, stacking, pickup capacity, and cleanup.
6. Convert chest contents, guarded-state input, panel opening, transfer signals,
   and persistent empty state. Keep inventory/world changes inside
   `InventoryWorldTransaction`; ScriptNodes request the transaction and publish
   results after commit.
7. Convert interaction areas/prompts/gates to node signals and domain services.
   Preserve modal/input locking, key consumption, unlocked state, and navigation
   handoff.
8. Replace ObjectFactory creation with scene instantiation and reduce existing
   controllers to temporary adapters. Redirect object-template authoring to Scene
   Studio and make old endpoints read-only before removal.
9. Complete objects.mjs for every archetype/variant and run the common conversion
   contract. The already converted camp chest is verified from its frozen
   cutover fixture rather than overwritten; extend its scene through normal
   authored edits. Keep the same ChestScript registry ID and UI port until
   package 14 removes LegacyChestUiBridge.

### Focused checks

Cover every object ledger row, persistent placement keys, object/visual variants,
static collision, depth/occlusion, resource damage/drop state, collectible source
IDs, inventory capacity, chest partial/full/empty transfer, guarded chest signals,
gate idempotence, transaction fault rollback, interaction locking, and cleanup.

### Gate

- Map object creation uses scenes, including static props without scripts.
- No object gameplay rule is encoded in a CollisionShape2D/Area2D subtype.
- Cross-domain actions preserve complete save consistency.

### Suggested commit

```text
feat: convert world objects and interactions to scenes
```

## Work package 13 — Convert authored maps, tile layers, areas, and navigation

### Files

Create:

- `src/game/infrastructure/phaser-nodes/TileMapLayer2DNode.ts`
- `src/game/content/scenes/resources/TileSetResource.ts`
- `src/game/content/scenes/resources/TileMapDataResource.ts`
- one world scene per current map under `src/game/content/scenes/worlds/`
- tile-set/data resources under `src/game/content/scenes/resources/tiles/`
- `src/game/editor/scene-studio/contexts/TileMapContext.ts`
- `src/game/editor/scene-studio/TilePaintCommand.ts`
- `scripts/lib/scene-conversion/maps.mjs`
- `scripts/tests/scene-conversion/map-conversion.test.mjs`
- `scripts/tests/scene-content/tile-resources.test.mjs`
- `scripts/tests/scene-studio/tile-context.test.mjs`
- `scripts/tests/scene-integration/world-scenes.test.mjs`
- `scripts/tests/scene-integration/navigation-scenes.test.mjs`

Update/adapt:

- `src/game/content/maps/mapFormat.ts`
- `src/game/content/maps/maps.schema.json`
- `src/game/content/maps/validateMapReferences.ts`
- `src/game/infrastructure/maps/MapRepository.ts`
- `src/game/infrastructure/maps/BrowserMapReferenceResolver.ts`
- `src/game/features/world/MapBuilder.ts`
- `src/game/features/world/TileFactory.ts`
- terrain transition modules under `src/game/features/world/`
- `src/game/features/world-navigation/AreaNavigation.ts`
- `src/game/scenes/MapLoadScene.ts`
- `src/game/scenes/WorldScene.ts`
- `src/game/world/WorldDimensions.ts`
- current map JSON files and `scripts/check-maps.mjs`
- `src/game/infrastructure/scenes/compatibility/LegacyMapPlacementBridge.ts`

### Steps

1. Implement `TileMapLayer2D` with an external stable-ID tile set and tile-data
   resource. Preserve transform, order/depth, visibility, collision participation,
   editor lock, terrain tile IDs, transitions, and authored dimensions.
2. Convert each map into a world scene containing ordered tile layers, nested
   object/NPC/encounter/character scene instances, and ordinary Area2D/script
   assemblies for safe zones, spawn/wander areas, exits, gates, and navigation.
3. Preserve every `MapId`, entry/exit relationship, authored instance ID,
   persistence key, boss camp ID, object state key, map dimensions, spawn rule,
   and placement transform. Produce a mapping report and reject duplicates/loss.
4. Keep production generation out of runtime. `maps:bake` may continue producing
   the legacy authoring source only until conversion; after cutover it either
   generates valid scene/tile resources deterministically or is retired with a
   documented replacement. It must never overwrite manually edited maps without
   explicit invocation.
5. Replace `MapRepository`/MapBuilder construction with `prepare_scene` plus root
   replacement. Retain repository responsibilities for asynchronous loading,
   errors, and cancellation through the new loader rather than duplicating them.
6. Convert navigation to typed signals/domain commands. A failed destination load
   keeps the active world root and save/location state intact. Commit new location
   only after the replacement is ready.
7. Build the Tile Map context inside Scene Studio: layer creation/order, tile-set
   selection, brush/erase/fill as bounded commands, collision/effective-region
   display, snapping, viewport navigation, and map validation. Use external tile
   data so large maps do not become giant node property arrays.
8. Redirect the existing `?editor=<map>` route into `?studio=scenes&scene=<world
   scene id>` preserving deep-link usefulness. Stop old Map Studio writes.
9. Remove the temporary authored-placement translation. World scenes now own
   all authored populations and encounter placements.
   Concretely, delete LegacyMapPlacementBridge after maps.mjs has converted each
   authored placement and root loading no longer needs legacy map records.
   Invoke `pnpm scenes:convert -- --family maps --dry-run`, then validate the
   report and apply through the common journal. There is no separate map-only
   CLI or second conversion implementation.

### Focused checks

Validate all maps, tiles, placements, world dimensions, entry/exit reciprocity,
areas, navigation, load cancellation/failure, root swap, save keys, tile painting
undo/redo, save/reload, and authored-population rules. Compare rendered tile/body
counts and representative collision points with the baseline.

### Gate

- Every map in the conversion ledger resolves to one valid world scene.
- Production world construction no longer invokes MapBuilder/ObjectFactory/
  EnemySpawner population paths.
- No persistent population is injected directly by `WorldScene`.

### Suggested commit

```text
feat: convert authored worlds to universal scenes
```

## Work package 14 — Convert HUD, panels, menus, and global audio to UI scenes

### Files

Create:

- concrete Control adapters under `src/game/infrastructure/phaser-nodes/ui/`
- behavior scripts under `src/game/features/scripts/ui/`
- UI scene documents under `src/game/content/scenes/ui/`
- theme/font resources under `src/game/content/scenes/resources/ui/`
- `scripts/tests/scene-conversion/ui-conversion.test.mjs`
- `scripts/tests/scene-integration/ui-scenes.test.mjs`
- `scripts/tests/scene-integration/ui-input-pause.test.mjs`
- `scripts/tests/scene-studio/ui-authoring.test.mjs`
- `scripts/lib/scene-conversion/ui.mjs`
- `scripts/migrations/ui-extraction-descriptors.json`
- `scripts/tests/scene-browser/ui-scenes.spec.ts`

Update/adapt:

- `src/game/HUD.ts`
- `src/game/Minimap.ts`
- all modules under `src/game/ui/`
- `src/game/ui/ModalStack.ts`
- `src/game/features/quests/QuestNotificationPresenter.ts`
- `src/game/presentation/theme.ts`
- `src/game/presentation/UiSkin.ts`
- `src/game/config.ts`
- `src/styles.css`
- `src/game/infrastructure/scenes/compatibility/LegacyChestUiBridge.ts`
- `src/game/infrastructure/scenes/compatibility/LegacyBossUiBridge.ts`

### Steps

1. Complete the minimum Control family needed by current UI: containers/layout,
   image/icon, text, progress/status display, button, list/grid, scroll region,
   modal root, and focus/navigation behavior. Add a new type only for genuinely
   different engine/presentation behavior.
2. Convert HUD status, health/energy, weapon hotbar, boss health, floating text,
   area title, minimap/world map, inventory, chest, crafting, quest journal/
   offer/notifications, level-up modal, ability bar, and remaining menus.
3. Keep domain state/actions outside controls. UI ScriptNodes subscribe to typed
   presentation models and invoke injected actions. They do not reach into scene
   internals, browser storage, or unrelated services.
4. Preserve current responsive layout, modal stacking, reopen rules, focus,
   keyboard/mouse behavior, input consumption, pause behavior, and cleanup.
5. Convert global music/UI sounds to `AudioStreamPlayer`; use
   `AudioStreamPlayer2D` for world sounds. Preserve volume/mute settings and
   browser gesture unlock.
6. Make UI scene/resource editing use the same tree, inspector, resource browser,
   signal context, and viewport. Add UI-specific layout handles as a context,
   never as a separate studio.
7. Keep any necessary DOM implementation behind Control adapters. Ensure DOM and
   Phaser input share handled state and destroyed scenes leave no nodes/listeners.
8. Audit each UI module into ui-extraction-descriptors.json with source hashes,
   layout/theme values, typed binding/action mappings, and destination scene IDs.
   Generate those scenes through ui.mjs, then verify descriptor/source coverage
   and converter repeatability. Delete LegacyChestUiBridge and LegacyBossUiBridge
   when their consumers are real Control scenes, and run real-browser focus,
   event-consumption, panel teardown, and preview-isolation cases.

### Focused checks

Cover each UI ledger entry, layout model calculations, focus and keyboard paths,
modal priority, handled input, pause/resume, domain-action boundaries, boss/chest/
quest signals, volume/mute/unlock, DOM cleanup, and Scene Studio save/reopen.

### Gate

- Every live UI composition is instantiated from the common scene tree.
- No UI module owns browser persistence or gameplay state mutation.
- The same Scene Studio can edit world, entity, and UI scenes.

### Suggested commit

```text
feat: convert UI and audio composition to scenes
```

## Work package 15 — Remove legacy owners and make Scene Studio universal

### Files

Remove after references reach zero:

- category-specific studio mount/routes and write endpoints replaced by Scene
  Studio, including `CharacterStudio.ts`, `AnimationStudio.ts`, `WeaponStudio.ts`,
  `ProjectileStudio.ts`, map-editor scenes/panels/state, and their CSS-only shell
  code
- legacy factories/controllers whose complete responsibilities moved to
  ScriptNodes/scenes, including direct entity construction in `PlayerFactory`,
  `Enemy`, `NpcActor`, `ObjectFactory`, legacy projectile/effect construction,
  and `LegacyWorldAdapter`
- old family schemas/catalogs/documents only after all consumers use the new
  scenes/resources and the ledger maps every stable ID
- temporary runtime adapters after their consumers switch; retain conversion
  tooling and frozen fixtures needed for repeatability/identity evidence

Retain when still the correct owner:

- immutable item, recipe, quest, global-balance, and area/project data
- asset manifest and asset loading metadata
- shared domain services for inventory, progression, quests, transactions,
  combat calculations, and saves
- compatibility save readers required by existing saves
- reusable editor controls now consumed by Scene Studio
- common conversion runner, family adapters, frozen inputs and ID maps used by
  retained conversion tests

Create/update:

- `src/game/editor/scene-studio/LegacyRouteRedirects.ts`
- `scripts/check-scene-ownership.mjs`
- `scripts/tests/scene-conversion/single-owner.test.mjs`
- `scripts/tests/scene-conversion/no-legacy-construction.test.mjs`
- `docs/ARCHITECTURE.md`
- `README.md`
- `docs/superpowers/plans/evidence/universal-scene-final-report.md`
- `package.json`
- `vite.config.ts`
- `src/game/config.ts`

### Steps

1. Complete the conversion ledger. Every row must be converted, intentionally
   retained as project data/resource, or explicitly removed with reason. Zero
   production IDs may be unresolved.
2. Add static ownership checks rejecting new imports/construction of retired
   factories, category-specific editor branches, duplicate property schemas,
   gameplay imports of procedural generation, and persistence access outside
   infrastructure.
3. Replace old editor routes with redirects that identify the destination scene
   and selected node/resource context. Remove old writers and Vite endpoints.
4. Remove old runtime construction and shrink `WorldScene` to a Phaser
   composition/host boundary. It should load the world packed scene, inject
   feature/domain services, forward host lifecycle, and coordinate fatal errors.
5. Remove obsolete catalogs/schemas only after `rg` confirms no consumers and
   the conversion check proves every ID. Do not remove project data that the
   design deliberately keeps outside nodes.
6. Update architecture docs with final dependency direction, target directories,
   Scene Studio workflow, ScriptNode convention, physics limitations, content
   ownership, persistence rules, and user-only gameplay testing language.
7. Run the required authoring walkthrough contracts for document behavior. The
   AI may exercise deterministic editor operations but must leave subjective and
   interactive gameplay checks to the user.
   Include the actual Chromium/Phaser and mounted-control suites; a missing
   browser executable or failed fixture cannot be marked passed by substituting
   fake-backend evidence.
8. Re-run the deterministic performance workload. Record median/p95 frame and
   load time plus Phaser object/body and cleanup counts. A regression over 10%
   requires optimization or a recorded user-approved exception.

### Gate

- `rg` and ownership checks find no category-specific writable editor or retired
  construction path.
- Every success criterion in the design maps to concrete evidence.
- `pnpm check` and production build pass.
- Real browser engine/editor fixtures pass and all temporary bridge imports
  have reached zero at their assigned removal package.
- The final manual checklist is delivered with gameplay acceptance pending.

### Suggested commit

```text
refactor: retire legacy editors and entity construction
```

## Milestone mapping and critical path

| Design milestone | Work packages | Exit condition |
| --- | --- | --- |
| M1: Contracts and thin runtime | 0-6 | Complete generic fixture; lifecycle, resolution, host, physics, animation/audio/input/script contracts pass |
| M2: First complete authoring slice | 7-9 | Scene Studio authors Worm and Fatty with the same common controls; the vertical slice runs through scenes |
| M3: All entity families | 10-12 | Characters, combat entities, effects, and objects are scene-instantiated; persistence/domain owners remain coherent |
| M4: World and UI integration | 13-14 | Every world and UI composition is scene-instantiated; one Scene Studio owns authoring |
| M5: Consolidation and handoff | 15 | Legacy writers/construction removed, ownership checks and full verification pass, user checklist delivered |

The critical dependency chain is:

```text
documents/descriptors
  -> Node/SceneTree lifecycle
  -> packed resolution and transactional insertion
  -> Phaser host
  -> physics + animation/audio/input/script nodes
  -> Scene Studio common authoring
  -> Worm/Fatty vertical slice
  -> remaining entity families
  -> worlds and UI
  -> legacy removal
```

Editor document-state work may begin once package 1 is stable, but preview and
runtime inspection depend on packages 3-6. Content migrators may be developed
against the pure schema after package 1, but their output cannot become
authoritative before the relevant runtime and editor package pass. World
conversion waits for all placed entity families, and final removal waits for
the complete conversion ledger.

The early slice explicitly includes minimum ChestScript and PlayerHealthService
plus its five compatibility bridges; later family packages extend or remove
these named dependencies rather than creating substitutes. The shared test
harness starts in package 0, converters start in package 1, and real-engine
verification starts in package 4. These are prerequisites, not final cleanup
tasks. The sixteen work packages remain within the five approved milestones.

## Cross-cutting implementation decisions

### One source of truth

At the end of each family conversion, audit each editable value:

| Value | Final owner |
| --- | --- |
| Raw media path/frame-grid/load metadata | `asset/assets.json` |
| Scene hierarchy, node properties, instance overrides, signal wiring | scene documents |
| Shared texture/shape/animation/audio/tile/theme data | resources referenced by scenes |
| Entity-specific configuration and node references | ScriptNode exported properties |
| Global player/balance/default values | existing `game-constants.json` owner |
| Item/recipe/quest/localization definitions | existing project-data catalogs |
| Runtime behavior orchestration | registered TypeScript ScriptNode implementations |
| Shared inventory/quest/progression/save/combat operations | existing or extracted domain services |
| Browser saves and editor file writes | infrastructure only |

Scene Studio may navigate to or present the actual owner in one shell; it must
not copy the value into a convenience document.

### Error handling

- Content errors identify scene ID plus full node/property/instance path and
  preserve invalid drafts for repair.
- Async load/cancel/resource failures leave the active world and save location
  unchanged.
- Constructor/enter/ready failures roll back the staged subtree and queued
  external commands.
- Script processing failures disable that script in development with diagnostics;
  generic engine invariant failures pause the tree. Production follows the fatal
  presentation contract.
- Cleanup attempts every child, connection, listener, timer, Phaser object, and
  disposer even after one failure.
- Editor file conflicts never overwrite newer disk content. Partial multi-file
  saves restore recoverable originals and keep editor state dirty.
- Cross-domain gameplay transactions commit complete snapshots or roll all
  participating owners back before notifications/autosave.

### Performance and memory

- Index runtime IDs and resolved paths; process only enabled nodes.
- Cache immutable packed source documents/resources, never mutable instances.
- Use Phaser groups/spatial filtering for candidate contacts; never scan every
  area against every node.
- Pool only where profiling justifies it. A pooled scene must reset transient
  script/animation/contact state and prove detach/re-entry cleanup.
- Measure the same map/workload at baseline, vertical slice, world cutover, and
  final consolidation. Keep median/p95 frame/load regression within 10% unless
  the user explicitly accepts a documented exception.
- Add leak assertions for node indexes, resource leases, Phaser objects/bodies,
  timers, DOM listeners, signal delivery indexes, and preview trees.

## Final automated verification

Run focused suites during their packages. At M5 run from the repository root:

```text
pnpm constants:check
pnpm assets:check
pnpm scenes:check
pnpm maps:check
pnpm quests:check
pnpm test:scene-content
pnpm test:scene-runtime
pnpm test:scene-studio
pnpm test:scene-integration
pnpm test:scene-browser
pnpm test:scene-conversion
pnpm check
```

`pnpm check` must contain all still-relevant legacy behavioral suites until their
assertions have moved to replacement suites. When a retired suite is removed,
name its replacement in the final evidence report. Run `git diff --check` and
review `git status --short` so the refactor commit does not consume unrelated
user files.

Automated evidence must include:

- complete conversion-ledger coverage and one-writer ownership;
- document/registry/descriptor validation and round trips;
- lifecycle, mutation, signal, duplicate, detach/re-entry, failure, and cleanup;
- nested instance/reference/override/provenance behavior;
- exact host order and one Arcade step;
- blocking/sensor geometry parity, including sectors and legacy ellipse bounds;
- animation clocks/events/cancellation/bindings and audio/input/pause behavior;
- generic damage routing, candidate priority, rejection retry, and hit dedup;
- player/enemy/NPC/weapon/projectile/effect/object/world/UI integration;
- player health/ability service equivalence with no legacy Phaser dependencies;
- real Phaser host/body/contact/cleanup and real DOM/Control input evidence;
- early-slice bridge routing in both directions and removal checks;
- complete save snapshot and inventory/world transaction consistency;
- editor history, invalid repair, conflict recovery, preview isolation, resource
  uniqueness, and required authoring walkthrough models; and
- baseline/final performance and leak comparison.

## User-only gameplay and product checklist

The AI prepares and delivers this checklist with the final build. The user runs
it interactively. Each group records pass/fail, observed symptoms, map/save used,
and any follow-up. The implementation handoff must use this exact status until
the user completes it:

```text
Gameplay testing: Not performed - reserved for user verification.
```

### A. Scene Studio consistency

Setup: start `pnpm dev`; open Scene Studio with an ordinary enemy and Fatty.

1. Select and edit their visual, collision shape, animation, audio, and ScriptNode
   children. Expected: the shell and common controls are identical; only registered
   script exports differ. Failure: boss-only panels, missing common properties, or
   any need to open a second editor.
2. Add a damage area and weapon vulnerability to an ordinary enemy. Expected:
   ordinary enemies expose the same matcher/modifier tools as Fatty. Failure:
   hard-coded boss restrictions or raw JSON editing.
3. Create a scene instance twice, override one visual/health value, edit the
   source, and revert the override. Expected: non-overridden fields update both;
   the local override remains until reverted. Failure: source mutation, lost
   override, or unclear value origin.
4. Undo/redo node operations, repair a missing reference, cause a save conflict,
   close/reopen, and run preview. Expected: no unrelated data loss; preview does
   not change inventory/world saves or execute gameplay events.
5. Repeat visual/shape/animation/audio editing for a weapon, projectile, prop,
   world, and UI scene. Expected: the same resource browser/inspectors apply.

### B. Character and combat behavior

Setup: use a new save and a progressed save with all weapon types available.

1. Move, attack, switch weapons, dodge, use unlocked abilities, pause, and operate
   modals. Expected: timing/input/collision match the pre-refactor game; UI consumes
   gameplay input while open.
2. Fight Worm Brawler and representative remaining enemies. Expected: targeting,
   spawn areas, movement, attacks, damage/effects, hit feedback, rewards, and
   death/despawn/respawn remain correct.
3. Fight Fatty with allowed and disallowed weapons; strike body and eye on the
   ground and during airborne phases. Expected: boss rank/UI works, eye/source
   vulnerability and immunity rules match current behavior, and no duplicate hits
   occur from overlapping areas.
4. Trigger Fatty contact hop, large leap, arena return, defeat, chest unlock, and
   timed respawn. Expected: authored visual/contact frames align, each activation
   hits at most as designed, camp persists correctly, and the chest reflects the
   live boss state.
5. Exercise sword and goo-gauntlet directional sector boundaries from all
   directions. Expected: coverage feels identical to the previous build.

### C. Objects, progression, and persistence

Setup: use a copy of an old supported save plus a fresh save.

1. Damage trees/rocks/resources with correct and incorrect tools. Expected:
   requirements, hit feedback, yields, depletion, drops, and reload state match.
2. Collect normal drops and inventory world drops with full, partial, and zero
   capacity. Expected: item totals remain exact and saved placement/source IDs
   remain stable.
3. Transfer partial and final chest stacks; unlock consuming and non-consuming
   gates; reload after each. Expected: inventory and world state always agree,
   empty chests stay empty/open, and unlocked gates consume at most once.
4. Progress representative quests through NPC interaction and collection.
   Expected: locks, prompts, rewards, journal state, and saves remain correct.
5. Load the copied old save, travel between maps, save, close, and reload.
   Expected: player, inventory, equipment, quests, location, boss/chest/gate/
   resource/object state, and play time are preserved without duplication.

### D. Worlds, UI, audio, and cleanup

Setup: visit every authored production map and at least one development/test map
through its supported development route.

1. Walk boundaries, walls, doors, narrow passages, safe zones, spawn/wander
   areas, exits, and transitions. Expected: visuals, collision, dimensions,
   placements, and navigation match authored content.
2. Inspect depth/occlusion around houses, trees, rocks, characters, projectiles,
   effects, pickups, and floating feedback. Expected: ordering and attachment are
   stable without flicker or leaked effects.
3. Open every HUD/panel/menu workflow with keyboard and mouse. Expected: readable
   layout, visible focus, correct modal order, responsive sizing, and restored
   input after close.
4. Verify music, world sounds, UI sounds, mute, and volume settings, including the
   first browser gesture. Expected: positional/global distinction and cleanup are
   correct; re-entering scenes does not duplicate loops.
5. Repeatedly transition maps, spawn/despawn enemies/projectiles/effects, open/
   close panels and previews, and return to the title/start flow if available.
   Expected: no growing duplication, stale collision, stuck pause/input, repeated
   audio, missing sprites, or progressively worse frame rate.

## Completion criteria

The refactor is technically complete only when all of the following are true:

1. Every live world, character, weapon, projectile, effect, object, encounter,
   and UI composition is instantiated through the common SceneTree.
2. Scene Studio is the only writable authoring shell for their shared nodes and
   resources; it contains no top-level player/NPC/enemy/boss/weapon/projectile/
   effect/map inspector branches.
3. Fatty is an enemy with boss rank and `FattyScript extends EnemyScript`; its
   special behavior remains programmatic and its shared properties use the same
   editor controls as ordinary enemies.
4. Damage reception is a shared ScriptNode capability using ordinary Area2D
   geometry, and any suitable entity can configure vulnerabilities/effect rules.
5. Visual, animation, physics, sensor, audio, input, UI, resource, instance,
   override, and script contracts each have one implementation and clear owner.
6. The conversion ledger contains every original production ID and stable
   persistence key with no lossy or unresolved conversion.
7. The existing save/domain architecture remains coherent; no node tree or
   independently dated hybrid section is persisted.
8. Retired editors, factories, construction branches, duplicate schemas, and
   temporary adapters have no remaining imports and are removed.
9. Node/scene/preview cleanup leaves no runtime indexes, resources, listeners,
   timers, signals, DOM elements, Phaser objects, or physics bodies.
10. `pnpm check`, the new scene suites, ownership check, conversion check, build,
    diff check, and performance/leak gates pass, with evidence recorded.
    `pnpm check` includes `test:scene-browser`; conversion checks use frozen
    fixtures for migrated families and never rewrite authored scene edits.
11. The final user-only gameplay checklist is delivered. Gameplay acceptance is
    complete only after the user runs it and explicitly approves the result.
