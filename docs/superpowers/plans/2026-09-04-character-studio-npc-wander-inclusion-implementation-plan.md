# Character Studio NPC and Wander-Area Implementation Plan

## Objective

Implement the approved [Character Studio NPC and Authored Wander-Area Inclusion design](../specs/2026-09-04-character-studio-npc-wander-inclusion-design.md): Village Elder Plop and Mossy Scout become first-class `npc` character packages in the existing Character Studio, while the Map Editor gains one optional personal wander area per placed NPC and runtime NPC actors move inside those authored bounds without joining enemy combat or spawning systems.

## Execution rules

- Preserve the existing split of ownership: Character Studio owns NPC presentation/body/movement cadence; `NpcCatalog` owns player-facing identity, dialogue, and quest relationships; maps own placement and wander geometry.
- Do not create a separate NPC studio, dialogue editor, enemy subtype, or pathfinding system.
- Work test-first at each boundary. Add the failing focused test, make the smallest implementation change, then run the focused command before moving on.
- Keep `WorldScene` as composition only. NPC behavior belongs in focused feature/controller classes that depend on narrow context interfaces.
- The worktree already contains unrelated UI work and uncommitted NPC assets/content. Re-read `git status --short` before every commit, stage only files named by the current task, and never overwrite or discard unrelated changes.
- Treat the two generated sprite sheets as the production sources:
  - `asset/characters/authored/npcs/village-elder-plop.png`
  - `asset/characters/authored/npcs/mossy-scout.png`
- Do not touch `.animation-library-transaction-*` directories. Remove only the two exact legacy NPC animation package files after their references have migrated.

## Phase 0 — Establish the baseline and protect concurrent work

**Read/verify**

- `git status --short`
- `asset/assets.json`
- `src/game/content/maps/level-1.map.json`
- `src/game/content/objects/npcs/npc-world.json`
- `src/game/content/objects/npcs/npc-world-scout.json`
- the two generated PNGs above

**Steps**

1. Record the current dirty files and confirm the two referenced PNGs are exactly 1374 x 1145 with a 229 x 229, 6 x 5, 30-frame manifest definition.
2. Confirm Level 1 still contains stable instances `level-1-npc-village-elder-plop` and `level-1-npc-mossy-scout` at `(512, 704)` and `(768, 704)`.
3. Run the current focused baseline without changing files:

```text
pnpm assets:check
pnpm characters:check
pnpm objects:check
pnpm maps:check
pnpm test:character-studio
pnpm test:map-editor
pnpm test:quests
pnpm typecheck
```

4. Record any pre-existing failures separately. Do not broaden this implementation to repair unrelated UI or content failures.

No commit is expected for this phase.

## Phase 1 — Add `npc` to the character content contract

**Modify**

- `src/game/content/characters/types.ts`
- `src/game/content/characters/character.schema.json`
- `src/game/content/characters/validation.ts`
- `src/game/content/characters/CharacterCatalog.ts`
- `src/game/content/characters/CharacterClipUsageRegistry.ts`
- `src/vite-env.d.ts`
- `scripts/check-characters.mjs`
- `scripts/tests/character-studio/character-studio.test.mjs`

**Steps**

1. Add failing validator tests for one valid NPC package and for these invalid cases:
   - missing `npc` gameplay document;
   - `player`, `enemy`, `runtimeRole`, or `attributes` present;
   - non-empty `hitboxes` or `hitboxSpans`;
   - negative/non-finite speed or pause values;
   - `pauseMaxMs < pauseMinMs`;
   - animation event ID outside the `npc.*` namespace;
   - missing/empty `idle` or directional walking clips.
2. Extend `CharacterKind` to `player | enemy | npc` and add `NpcGameplayDocument` with `wanderSpeed`, `pauseMinMs`, and `pauseMaxMs`.
3. Add `npc?: NpcGameplayDocument` to `CharacterDocument` and the matching virtual-module declaration in `src/vite-env.d.ts`.
4. Add an explicit NPC branch to the JSON schema and TypeScript validator. Keep player and enemy validation unchanged; do not convert existing binary logic into a permissive fallback branch.
5. Require NPC clips `idle`, `walk-down`, `walk-up`, `walk-left`, and `walk-right`, each with at least one in-range frame.
6. Add `getNpcPackages()` and `getNpcGameplay()` to `CharacterCatalog`. Retain existing `getPrimaryPlayerPackage()` and `getEnemyPackages()` behavior exactly.
7. Extend the optional kind discriminator in `CharacterClipUsageRegistry` to include `npc`; do not change existing registrations or consumers.
8. Mirror the same invariants in `scripts/check-characters.mjs` so the standalone content checker and runtime validator reject the same authored mistakes.
9. Add regression assertions that existing player/enemy packages still validate and their serialized forms do not acquire an `npc` field.

**Focused verification**

```text
pnpm test:character-studio
pnpm characters:check
pnpm typecheck
```

**Commit checkpoint:** `feat: add NPC character package contract`

## Phase 2 — Extend package creation and the existing Character Studio

**Modify**

- `src/game/content/characters/characterContentModulesPlugin.ts`
- `src/game/editor/CharacterDocumentState.ts`
- `src/game/editor/CharacterStudio.ts`
- `src/game/editor/character-studio.css`
- `scripts/tests/character-studio/authoring-runtime.test.mjs`
- `scripts/tests/character-studio/character-studio.test.mjs`

**Steps**

1. Extend the test fixture endpoint to create an NPC package from a spritesheet. Assert the created files use `kind: "npc"`, the required five clips, empty hitboxes/spans, and the three gameplay defaults.
2. Expand `PackageCreationRequest.kind` and its template union with `npc`. Add `NPC_STARTER_CLIP_IDS`; do not reuse the enemy starter list.
3. Update `starterPackage`, request parsing, imported-PNG metadata, duplication, and generated `visualSetId` logic so an NPC request produces a normal character package rather than an enemy package with modified values.
4. Audit every player-versus-enemy branch in `CharacterDocumentState` and `CharacterStudio`. Replace implicit `else enemy` logic with explicit three-way role handling.
5. Update the one existing roster and workbench:
   - add an `NPC` creation option and NPC starter option;
   - show a dedicated NPC glyph/label/accent in the shared roster;
   - label the workbench and inspector as an NPC package;
   - render wander speed and pause-range controls;
   - retain the common sheet, clip, timeline, transform, preview, and body controls;
   - keep Add Event with an `npc.footstep` default;
   - hide Add Hitbox and Add Span for NPCs;
   - do not add a tab, route, page, or new Studio mount.
6. Ensure state mutations can edit `npc.wanderSpeed`, `npc.pauseMinMs`, and `npc.pauseMaxMs`, and can save `npc.*` events while rejecting invalid namespace input before submission.
7. Add source-structure and state tests proving the UI has an explicit NPC branch and no binary fallback that renders NPCs as enemies.
8. Keep the existing dark Studio shell. Add only the lavender/moss NPC role tokens and states needed for roster, selection, hover, focus, and validation.

**Focused verification**

```text
pnpm test:character-studio
pnpm characters:check
pnpm typecheck
```

**Manual checkpoint:** Open Character Studio, create a temporary NPC from a fixture sheet, edit a clip plus movement values, save/reload, then remove the fixture through the test cleanup path.

**Commit checkpoint:** `feat: author NPC packages in Character Studio`

## Phase 3 — Create the two production NPC character packages

**Create**

- `src/game/content/characters/village-elder-plop/character.json`
- `src/game/content/characters/village-elder-plop/visual-set.json`
- `src/game/content/characters/mossy-scout/character.json`
- `src/game/content/characters/mossy-scout/visual-set.json`

**Modify**

- `asset/assets.json`
- `src/game/content/characters/virtual-character-content.ts`
- `src/game/content/npcs/NpcCatalog.ts`
- `scripts/check-quests.mjs`
- `scripts/tests/character-studio/character-studio.test.mjs`
- `scripts/tests/quests/quest-service.test.mjs` when catalog references are covered there

**Steps**

1. Add both character packages using the exact design values:
   - Elder: scale `[0.2, 0.2]`, ellipse body 34 x 24 with radii 17 x 12 and center offset `(0, 10)`, speed 18, pause 1800–3200 ms.
   - Mossy: scale `[0.32, 0.32]`, ellipse body 36 x 24 with radii 18 x 12 and center offset `(0, 10)`, speed 42, pause 250–900 ms.
2. Set origin `[0.5, 1]`, zero source offset, empty hitboxes, and empty track spans. Use package IDs `village-elder-plop` and `mossy-scout` and stable visual-set IDs under `character.npc.*`.
3. Map the 30-frame sheets exactly. Elder uses 5 FPS for `idle` and 7 FPS for every walk clip; Mossy uses 8 FPS for `idle` and 12 FPS for every walk clip:
   - `idle`: 0–5;
   - `walk-down`: 6–11;
   - `walk-up`: 12–17;
   - `walk-left`: 18–23;
   - `walk-right`: 24–29.
4. Preview those rates in Character Studio to verify the intended deliberate/playful contrast. Do not alter source PNGs during this task.
5. Update the static virtual package fallback so direct Vite SSR tests see both packages. Confirm the development plugin discovers the same entries dynamically.
6. Add required `characterId` links to `NpcDefinition`:
   - `village-elder-plop -> village-elder-plop`;
   - `level-1-spider-giver -> mossy-scout`.
7. Export `validateNpcCatalogReferences()` from `NpcCatalog`. It rejects missing/non-NPC package links and accidental duplicate package ownership. Load and invoke it explicitly from `scripts/check-quests.mjs` after Vite resolves the virtual character catalog.
8. Preserve the existing quest-facing `level-1-spider-giver` ID; do not rename quests or save references.

**Focused verification**

```text
pnpm assets:check
pnpm characters:check
pnpm quests:check
pnpm test:character-studio
pnpm test:quests
```

**Manual checkpoint:** Both characters appear in the same Character Studio roster as NPCs and their five animations preview with correct frame boundaries.

**Commit checkpoint:** `content: add Elder and Mossy NPC packages`

## Phase 4 — Make NPC object archetypes placement-only

**Modify**

- `src/game/content/objects/objects.schema.json`
- `src/game/content/objects/ObjectCatalog.ts`
- `src/game/content/objects/npcs/npc-world.json`
- `src/game/content/objects/npcs/npc-world-scout.json`
- `src/game/editor/MapEditorScene.ts`
- `scripts/check-objects.mjs`
- `scripts/tests/map-editor/gameplay-attributes.test.mjs`

**Create**

- `src/game/editor/NpcPlacementPreview.ts`

**Steps**

1. Add failing object/catalog tests proving NPC archetypes may omit `variants`, must keep `physics: null`, require `npc.definitionId` plus `npc.placementVisualId`, and synthesize a valid palette choice from the linked NPC character package.
2. Make ordinary object archetypes continue requiring non-empty `variants`; do not relax the schema globally.
3. Update the TypeScript object definition union so the NPC branch is explicit and narrowed. Keep the existing `ObjectVisualChoice` API for palette/search consumers, but synthesize NPC choices from `NpcCatalog` plus `CharacterCatalog` using the first `idle` frame and visual defaults.
4. Convert `npc.world` and `npc.world-scout` to placement-only definitions. Preserve their object IDs, definition IDs, tags, `physics: null`, and current map-facing visual IDs `slime-npc` and `slime-scout`.
5. Remove presentation fields from those two object JSON files: asset ID, frame, scale, offsets, and object idle-animation IDs.
6. Add a render-only `NpcPlacementPreview` adapter for Map Editor canvas instances/cursor previews. It resolves the character visual set, applies origin/scale/source offset, renders the first idle frame, and owns explicit destroy cleanup. It is not an editor or source of authored values.
7. Branch Map Editor rendering for NPC choices through that adapter while keeping non-NPC objects on `ObjectFactory`. Adjust rendered-instance types only as far as needed for `Sprite`/`Image` compatibility.
8. Verify palette grouping/search and right-click picking still return the stable placement visual IDs stored in maps.

**Focused verification**

```text
pnpm objects:check
pnpm test:map-editor
pnpm typecheck
```

**Manual checkpoint:** The Object palette and placed Level 1 NPC previews reflect Character Studio scale/frame changes without editing the object archetype JSON.

**Commit checkpoint:** `refactor: resolve NPC object previews from character packages`

## Phase 5 — Add NPC wander-area map data and shared geometry

**Create**

- `src/game/content/maps/agentAreaGeometry.ts`
- `src/game/content/maps/validateMapReferences.ts`
- `src/game/content/npcs/npcWanderGeometry.ts`
- `scripts/tests/map-editor/npc-wander-area.test.mjs`

**Modify**

- `src/game/content/maps/mapFormat.ts`
- `src/game/content/maps/maps.schema.json`
- `src/game/content/maps/enemySpawnAreaGeometry.ts`
- `src/game/infrastructure/maps/MapRepository.ts`
- `vite.config.ts`
- `scripts/check-maps.mjs`
- `src/game/editor/MapEditorState.ts`
- `scripts/tests/map-editor/gameplay-attributes.test.mjs`

**Steps**

1. Add table-driven failing tests for circle/rectangle structural parsing, absent legacy field, inclusive containment, duplicate area IDs, duplicate NPC assignments, bounds checks, and round-trip serialization.
2. Introduce `MapAgentAreaPerimeter` and `MapNpcWanderArea`; add optional `npcWanderAreas` to `MapFile` and `BuiltMap`. Preserve `MapEnemyAreaPerimeter` as an alias/re-export during the migration so existing enemy code remains source-compatible.
3. Move generic perimeter bounds, containment, translation, resizing support, inset, and random-point helpers into `agentAreaGeometry.ts`; keep enemy-specific player/pursuit behavior in `enemySpawnAreaGeometry.ts`.
4. Implement body-aware valid-anchor-domain calculation in `npcWanderGeometry.ts` using resolved collision dimensions, asymmetric center offsets, and the fixed eight-pixel margin. Reject zero/negative valid domains and starting anchors outside the valid domain.
5. Keep `parseMapFile` structural and dependency-free. It validates collection/field shapes, finite positive geometry, map bounds, stable IDs, and duplicate assignments.
6. Put the focused cross-reference validator in `validateMapReferences.ts` and use it from `MapRepository` and the Map Editor save endpoint. It resolves each assigned object through Object/NPC/Character catalogs and performs the body-aware check.
7. Add parity logic to `scripts/check-maps.mjs` so the standalone checker performs the same reference checks. Add fixtures for missing instance, non-NPC instance, too-small area, and offset body outside the area.
8. Normalize absent `npcWanderAreas` to `[]` in `MapEditorState`, include areas in map-resize scaling, and preserve maps that omit the field when round-tripped unless the editor adds an area.
9. Add regression coverage for existing enemy-area geometry and for player/enemy packages/maps remaining unchanged.

**Focused verification**

```text
pnpm test:map-editor
pnpm maps:check
pnpm typecheck
```

**Commit checkpoint:** `feat: add authored NPC wander-area map data`

## Phase 6 — Add the NPC Area workflow to Map Editor

**Create**

- `src/game/editor/AgentAreaEditorGeometry.ts`

**Modify**

- `src/game/editor/MapEditorState.ts`
- `src/game/editor/MapEditorScene.ts`
- `src/game/editor/MapEditorPanel.ts`
- `src/game/editor/EditorGeometryStyles.ts`
- `src/styles.css`
- `docs/MAP_EDITOR.md`
- `scripts/tests/map-editor/npc-wander-area.test.mjs`

**Steps**

1. Extract only the reusable circle/rectangle draft, move, corner-resize, snapping, and map-clamping calculations from enemy-area authoring. Keep enemy stay/pursue containment rules in the enemy workflow.
2. Add `npc-area` to `EditorTool`. Add explicit state for captured owner NPC instance and selected NPC area; do not overload enemy-area selection.
3. Implement the activation contract:
   - user selects a placed NPC with Select/Move;
   - clicking NPC Area captures that stable instance as the owner;
   - non-NPC selection leaves the previous tool active and reports why;
   - an existing personal area is selected instead of creating a duplicate.
4. Add state mutations for create/update/delete area. Generate the lowest unused `npc-area-NN` ID. Deleting an NPC cascades its area within the same undo snapshot; deleting only the area leaves the NPC stationary.
5. Add canvas pointer handling for create, select, move, and corner-resize. Area/object/safe-zone/enemy-area selections remain mutually exclusive and drag state clears on tool changes or scene shutdown.
6. Render NPC areas only while the tool is active using a lavender outline, quiet fill, resize handles, and a tether from area center/nearest point to its owner NPC. Reuse existing depth/selection conventions.
7. Add a compact panel section with selected NPC identity, shape choice, create/edit state, and delete action. Do not reuse or display the enemy roster/cooldown dialog and do not duplicate Character Studio movement values.
8. When an NPC is moved outside its raw perimeter, report the invalid relation immediately. Let the shared save validator remain authoritative for body-aware rejection and surface its precise response without writing.
9. Test activation, one-area ownership, ID allocation, circle/rectangle editing, cascade delete/undo, area-only delete, map scaling, invalid selection, selection cleanup, and legacy maps.

**Focused verification**

```text
pnpm test:map-editor
pnpm maps:check
pnpm typecheck
```

**Manual checkpoint:** Draw one circle and one rectangle for the two Level 1 NPCs, move/resize them, verify the tether, then test delete and undo.

**Commit checkpoint:** `feat: author personal NPC areas in Map Editor`

## Phase 7 — Implement the pure wandering policy

**Create**

- `src/game/features/npcs/NpcWanderPolicy.ts`
- `scripts/tests/npcs/npc-wander-policy.test.mjs`

**Modify**

- `package.json` to include the focused NPC test directory in an appropriate test script and the repository `check` sequence

**Steps**

1. Define the four content-independent constants from the spec: margin 8 px, arrival distance 6 px, progress threshold 2 px, and stuck sample interval 750 ms.
2. Implement pure state transitions for idle/pause, target acquisition, moving, arrival, interaction lock, unlock, and stuck recovery. Accept clock/random inputs instead of reading Phaser globals.
3. Sample rectangle targets with independent linear X/Y interpolation and circle targets using angle plus `sqrt(random)` radial distance for uniform area distribution.
4. Map velocity to `walk-down`, `walk-up`, `walk-left`, or `walk-right` by dominant axis. Preserve the last facing while idle, but play the shared `idle` clip.
5. Explicitly handle zero speed, zero-duration pauses, already-arrived targets, very small positive valid domains, non-positive delta, and repeated lock/unlock calls without loops or unbounded retargeting.
6. Add deterministic tests for every transition, containment, distribution formula inputs, exact boundary inclusion, stuck recovery, and destruction/no-op behavior.

**Focused verification**

```text
pnpm test:npcs
pnpm typecheck
```

**Commit checkpoint:** `feat: add deterministic NPC wander policy`

## Phase 8 — Create runtime NPC actors and world composition

**Create**

- `src/game/features/npcs/NpcActor.ts`
- `src/game/features/npcs/NpcRuntimeController.ts`
- `scripts/tests/npcs/npc-runtime-contract.test.mjs`

**Modify**

- `src/game/features/world/MapBuilder.ts`
- `src/game/features/interaction/QuestNpcController.ts`
- `src/game/scenes/WorldScene.ts`

**Steps**

1. Add `BuiltNpcRegistration` plus `onNpcCreated` to MapBuilder. Branch on NPC metadata before `ObjectFactory.create`; emit placement information and never create a legacy object image. Keep `onObjectCreated` unchanged for ordinary objects.
2. Return `npcWanderAreas` in `BuiltMap` and prove maps with none return an empty readonly collection.
3. Implement `NpcActor` with an invisible Arcade anchor, body geometry from its package, `AnimatedVisual`, `CharacterAnimationTrackRunner`, policy state, world-depth synchronization, interaction-lock tokens, and idempotent destroy.
4. Synchronize every visual clip change to the track runner. Forward valid `npc.*` events through an optional presentation callback carrying the stable NPC instance ID; do not provide hitbox callbacks or emit to combat.
5. Implement `NpcRuntimeController` to resolve catalog/package links, match placements to personal areas, create actors, expose an NPC physics group/readonly handles, update actors, and destroy all resources.
6. Change `QuestNpcController.register` to accept a narrow actor handle containing stable IDs, current position, and `acquireInteractionLock()`. Keep all quest lookup, prompt priority, and text in that controller.
7. Compose both controllers in `WorldScene`: create them before map build, route `onNpcCreated`, finalize interaction registration after build, collide the NPC group with static world collision, call update from the normal scene update, and destroy before collision/world teardown.
8. Do not add NPCs to enemies, combat targets, damage receivers, safe-zone steering, enemy spawn counts, drops, or save-game entity state.
9. Add tests/source assertions for no ObjectFactory image, one actor per placement, correct body/clip selection, track-event forwarding with instance ID, absent callback no-op, static NPC without area, collision-group exposure, and idempotent disposal.

**Focused verification**

```text
pnpm test:npcs
pnpm test:quests
pnpm test:rendering
pnpm typecheck
```

**Commit checkpoint:** `feat: run authored NPC actors in world maps`

## Phase 9 — Make interaction locking complete and leak-free

**Modify**

- `src/game/ui/QuestOfferModal.ts`
- `src/game/features/interaction/QuestNpcController.ts`
- `scripts/tests/quests/interaction-router.test.mjs`
- `scripts/tests/modal-stack.test.mjs`
- `scripts/tests/npcs/npc-runtime-contract.test.mjs`

**Steps**

1. Add one `onClosed` callback to the current modal session. Invoke it exactly once after cleanup for accept, decline, Escape, replacement, explicit close, and destroy. Keep `onFinished` limited to successful quest bookkeeping.
2. In `QuestNpcController`, acquire a lock only for the NPC whose candidate executes. Transfer every acquired token to exactly one release owner:
   - modal `onClosed`; or
   - a scene timer lasting 700 ms for plain talk or pre-modal floating errors.
3. Cover reoffer failure and missing refreshed quest explicitly. If an exception occurs before any modal/message owner is installed, release immediately in `finally`.
4. Repeated interactions may create multiple tokens, but one timer/close callback releases only its own token. Actor movement resumes only after the last token releases and starts from a fresh pause/target cycle.
5. Preserve any concurrent visual-skin edits already present in `QuestOfferModal`; this task changes session lifecycle only.
6. Test success, command error that leaves a modal open, Escape, decline, modal replacement, destroy, reoffer failure before modal creation, plain-talk timeout, duplicate callback protection, and scene shutdown with pending timers.

**Focused verification**

```text
pnpm test:quests
pnpm test:ui
pnpm test:npcs
pnpm typecheck
```

**Commit checkpoint:** `fix: coordinate NPC movement with quest interactions`

## Phase 10 — Migrate Level 1 and remove legacy presentation

**Modify**

- `src/game/content/maps/level-1.map.json`

**Delete only after a reference scan**

- `src/game/content/animations/objects/npc/village-elder-plop/idle/animation.json`
- `src/game/content/animations/objects/npc/mossy-scout/idle/animation.json`

**Steps**

1. Re-read the current dirty Level 1 map and merge rather than replace other authored edits.
2. Add the exact approved areas:
   - `npc-area-01`: circle centered `(512, 704)`, radius 96, assigned to `level-1-npc-village-elder-plop`;
   - `npc-area-02`: rectangle `(672, 640, 192, 128)`, assigned to `level-1-npc-mossy-scout`.
3. Run a reference search for `object.npc.village-elder-plop.idle` and `object.npc.mossy-scout.idle`. After all object/runtime references are gone, delete only the two exact `animation.json` files above and remove now-empty owned directories if safe. Do not delete animation transaction directories.
4. Confirm the character packages are now the sole owner of NPC scale, frame sequence, offsets, body, and runtime animation.
5. Run all content checkers before committing the migration.

**Focused verification**

```text
pnpm assets:check
pnpm animations:check
pnpm visuals:check
pnpm characters:check
pnpm objects:check
pnpm maps:check
pnpm quests:check
```

**Manual checkpoint in Level 1**

1. Elder stays inside the circle, moves slowly, and pauses deliberately.
2. Mossy stays inside the rectangle, moves faster, and uses the funny authored motion.
3. All four movement directions select the matching animation row.
4. Both NPCs stop for ordinary talk, offers, and turn-in, then resume without jumping.
5. Removing an area in Map Editor makes only that NPC stationary and does not break interaction.
6. Neither NPC becomes targetable, damageable, counted as an enemy, or affected by enemy camps.

**Commit checkpoint:** `content: migrate Level 1 NPCs to authored wandering`

## Final verification and acceptance

Run the focused suites first, then the repository-wide sequence:

```text
pnpm test:character-studio
pnpm test:map-editor
pnpm test:npcs
pnpm test:quests
pnpm test:ui
pnpm test:rendering
pnpm assets:check
pnpm animations:check
pnpm visuals:check
pnpm characters:check
pnpm objects:check
pnpm maps:check
pnpm quests:check
pnpm typecheck
pnpm build
pnpm check
```

If the pnpm wrapper is blocked by the known sandbox/store permission issue, run the equivalent declared Node/Vite/TypeScript command using the repository's configured bundled runtime and report that substitution explicitly. Do not treat a command that never executed as passing.

The implementation is complete only when:

- Village Elder Plop and Mossy Scout appear as `NPC` entries in the existing Character Studio.
- Their sprite frames, five clips, timing, transforms, names used as editor labels, body geometry, namespaced events, speed, and pause ranges save and reload.
- NPC player-facing text still comes from `NpcCatalog`.
- Each placed NPC owns at most one optional Map Editor wander area with create/move/resize/delete/undo behavior.
- Body-aware validation prevents an actor from being assigned an unusable area.
- Runtime creates one animated non-hostile actor per NPC placement and no duplicate object image.
- Wandering remains inside the authored valid anchor domain and recovers from obstacle stalls.
- Every interaction path releases its movement lock.
- Existing player, enemy, enemy-area, quest, and legacy no-NPC-area behavior remains green.
- Full typecheck and production build pass.
