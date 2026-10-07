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
   - `player` present by itself;
   - `enemy` present by itself;
   - `runtimeRole` present by itself;
   - `attributes` present by itself;
   - non-empty `hitboxes` or `hitboxSpans`;
   - negative/non-finite speed or pause values;
   - `pauseMaxMs < pauseMinMs`;
   - animation event ID outside the `npc.*` namespace;
   - missing/empty `idle` or directional walking clips.
2. Extend `CharacterKind` to `player | enemy | npc` and add `NpcGameplayDocument` with `wanderSpeed`, `pauseMinMs`, and `pauseMaxMs`.
3. Add `npc?: NpcGameplayDocument` to `CharacterDocument` and the matching virtual-module declaration in `src/vite-env.d.ts`.
4. Add an explicit NPC branch to the JSON schema and TypeScript validator. Independently forbid `player`, `enemy`, `runtimeRole`, and `attributes` in that branch; do not use one `not` clause that rejects only a combination. Keep player and enemy validation unchanged and do not convert existing binary logic into a permissive fallback branch.
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
4. Audit every player-versus-enemy branch in `CharacterDocumentState` and `CharacterStudio`. Replace implicit `else enemy` logic with explicit three-way role handling. Inventory every public mutation method before changing UI controls.
5. Update the one existing roster and workbench:
   - add an `NPC` creation option and NPC starter option;
   - show a dedicated NPC glyph/label/accent in the shared roster;
   - label the workbench and inspector as an NPC package;
   - render wander speed and pause-range controls;
   - retain the common sheet, clip, timeline, transform, preview, and body controls;
   - keep Add Event with an `npc.footstep` default;
   - hide Add Hitbox and Add Span for NPCs;
   - do not add a tab, route, page, or new Studio mount.
6. Enforce role restrictions inside `CharacterDocumentState`, not only in rendered controls. NPC state may edit body/visual/clip/timeline data, `npc.wanderSpeed`, `npc.pauseMinMs`, `npc.pauseMaxMs`, and `npc.*` events. Mutation methods must reject NPC attributes, hitboxes, hitbox spans, player/enemy/runtime-role data, and events outside `npc.*`, even when called directly.
7. Add source-structure and direct state-mutation tests proving the UI has an explicit NPC branch, no binary fallback renders NPCs as enemies, and bypassing hidden controls cannot create forbidden NPC fields.
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
- `src/game/content/npcs/NpcDefinitions.ts`

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
6. Extract the immutable NPC definition records into `NpcDefinitions.ts`. This module imports no `CharacterCatalog`, virtual content module, Vite API, filesystem API, or Phaser type; `NpcCatalog` consumes/re-exports the snapshot so its existing public lookup API remains stable.
7. Add required `characterId` links to `NpcDefinition` and remove the unused optional `NpcDefinition.visualId` field so `characterId` is the only presentation link:
   - `village-elder-plop -> village-elder-plop`;
   - `level-1-spider-giver -> mossy-scout`.
8. Export `validateNpcCatalogReferences()` from `NpcCatalog`. It rejects missing/non-NPC package links and accidental duplicate package ownership. Load and invoke it explicitly from `scripts/check-quests.mjs` after Vite resolves the virtual character catalog.
9. Preserve the existing quest-facing `level-1-spider-giver` ID; do not rename quests or save references.

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

## Phase 4 — Add discriminated NPC placement choices and Map Editor previews

**Modify**

- `src/game/content/objects/ObjectCatalog.ts`
- `src/game/content/objects/ObjectInitialState.ts`
- `src/game/editor/MapEditorScene.ts`
- `src/game/editor/MapEditorPanel.ts`
- `src/game/editor/MapEditorInspector.ts`
- `src/game/editor/MapEditorObjectAuthoring.ts`
- `src/game/editor/ObjectTemplateEditorState.ts`
- `src/game/editor/GameplayAttributeEditorState.ts`
- `src/game/features/objects/ObjectFactory.ts`
- `src/game/features/resources/ResourceNodeController.ts`
- `scripts/tests/map-editor/gameplay-attributes.test.mjs`

**Read/audit for the Phase 8 cutover**

- `src/game/content/objects/objects.schema.json`
- `src/game/content/objects/npcs/npc-world.json`
- `src/game/content/objects/npcs/npc-world-scout.json`
- `vite.config.ts`
- `scripts/check-objects.mjs`
- `scripts/check-maps.mjs`

**Create**

- `src/game/editor/NpcPlacementPreview.ts`

**Steps**

1. Add failing catalog/editor tests proving an archetype with NPC metadata produces a valid `npc-character` placement choice linked to its character package, while ordinary archetypes produce `object-visual` choices.
2. Add `ObjectPlacementChoice = (ObjectVisualChoice & { readonly kind: "object-visual" }) | NpcCharacterPlacementChoice`, where the NPC branch requires `kind: "npc-character"`. Keep `ObjectVisualChoice` ordinary-object-only. The NPC choice carries stable object/placement IDs, `npcDefinitionId`, `characterId`, `visualSetId`, display name, and tags; it deliberately does not expose ordinary object asset/frame, uniform scale, visual-offset, collider, or animation-override fields.
3. Add new editor-facing placement-choice lookup APIs that synthesize NPC choices from `NpcCatalog` plus `CharacterCatalog`. Keep the existing runtime object-visual resolver temporarily intact so `MapBuilder -> ObjectFactory` remains functional until the Phase 8 actor cutover. Mark that compatibility path for removal in the audit checklist.
4. Add a render-only `NpcPlacementPreview` adapter for Map Editor canvas instances/cursor previews. It accepts only `NpcCharacterPlacementChoice`, resolves the package, applies origin, non-uniform scale, source offset, and the first `idle` frame, and owns explicit destroy cleanup. It is not an editor or source of authored values.
5. Migrate palette, search, selection, placement, and right-click picking consumers to narrow on the discriminator. Route only `object-visual` editor choices through `ObjectFactory`; route only `npc-character` editor choices through `NpcPlacementPreview`. Use a common rendered-instance interface for bounds/position/depth/destroy without widening either source type.
6. Prevent object-template and gameplay-attribute editors from treating NPC choices as editable object visuals. Show a concise “Edit in Character Studio” route/status for NPC presentation. Keep the legacy NPC object variants read-only during the transition.
7. Narrow collectible/drop logic in `ObjectInitialState`, `GameplayAttributeEditorState`, `MapEditorInspector`, and `ResourceNodeController` to ordinary collectible choices. An NPC placement can never become a resource drop merely because it has a palette entry.
8. Complete and record a repository scan for `.variants`, `ObjectVisualChoice`, `getObjectVisualChoice`, and `getObjectVisualChoices`. Classify every result and produce the exact Phase 8 deletion/cutover checklist; document why unrelated effect/legacy-migration variant code is unchanged.
9. Do not yet remove NPC JSON variants, change the schema to forbid them, or delete the legacy runtime resolver. Add a regression assertion that Level 1 still builds through its existing runtime path after this phase.
10. Verify palette grouping/search and right-click picking return the stable placement visual IDs stored in maps while using Character Studio presentation in the editor.

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
- `src/game/infrastructure/maps/BrowserMapReferenceResolver.ts`
- `src/game/content/npcs/npcWanderGeometry.ts`
- `scripts/tests/map-editor/npc-wander-area.test.mjs`

**Modify**

- `src/game/content/maps/mapFormat.ts`
- `src/game/content/maps/maps.schema.json`
- `src/game/content/maps/enemySpawnAreaGeometry.ts`
- `src/game/shared/collisionShapes.ts`
- `src/game/infrastructure/maps/MapRepository.ts`
- `vite.config.ts`
- `scripts/check-maps.mjs`
- `src/game/editor/MapEditorState.ts`
- `scripts/tests/map-editor/gameplay-attributes.test.mjs`

**Steps**

1. Add table-driven failing tests for circle/rectangle structural parsing, absent legacy field, inclusive containment, duplicate area IDs, duplicate NPC assignments, bounds checks, and round-trip serialization.
2. Introduce `MapAgentAreaShape`, `MapAgentAreaPerimeter`, and `MapNpcWanderArea`; add optional `npcWanderAreas` to `MapFile` and `BuiltMap`. Preserve both `MapEnemyAreaShape` and `MapEnemyAreaPerimeter` as aliases/re-exports during the migration so existing enemy code remains source-compatible.
3. Move generic perimeter bounds, containment, translation, resizing support, inset, and random-point helpers into `agentAreaGeometry.ts`; keep enemy-specific player/pursuit behavior in `enemySpawnAreaGeometry.ts`.
4. Add `resolveEffectiveArcadeBodyBoundsRelativeToAnchor()` to `collisionShapes.ts`. It is the single authority for resolved dimensions, asymmetric center offsets, and Arcade's conservative rectangular ellipse representation. Refactor `applyArcadeBodyGeometry()` to consume it, then use the same result in NPC map validation and runtime target clamping.
5. Implement body-aware valid-anchor-domain calculation in `npcWanderGeometry.ts` using those shared bounds and the fixed eight-pixel margin. Reject zero/negative valid domains and starting anchors outside the valid domain.
6. Keep `parseMapFile` structural and dependency-free. It validates collection/field shapes, finite positive geometry, map bounds, stable IDs, and duplicate assignments.
7. Define a narrow `MapReferenceResolver` port in `validateMapReferences.ts` for resolving object placement metadata, NPC definitions, NPC character packages, and effective bodies. The validator imports no runtime catalog, virtual module, filesystem API, Vite API, or Phaser type.
8. Add a browser adapter in `BrowserMapReferenceResolver.ts` backed by Object/NPC/Character catalogs and inject it from `MapRepository`. In `vite.config.ts`, build a Node adapter from the pure `NpcDefinitions.ts` snapshot plus authored object, character, and visual-set JSON. Do not import `NpcCatalog`, runtime `CharacterCatalog`, or `virtual-character-content` from the config.
9. Make the Map Editor save/create endpoints and `scripts/check-maps.mjs` call the same pure validator with the filesystem resolver. The standalone checker may load the pure TypeScript module through Vite SSR, but it must not duplicate body-domain policy or resolve `virtual-character-content` from the config process.
10. Add fixtures for missing instance, non-NPC instance, bad placement visual ID, missing NPC definition/package, too-small area, asymmetric offset body outside the area, ellipse bounds, and exact-boundary inclusion.
11. Treat absent `npcWanderAreas` as an empty editor view without assigning `[]` into the document. Scale the collection only when present; create it on the first NPC-area mutation. Preserve absent-versus-present state in undo/redo snapshots so merely opening, editing unrelated content, resizing, or saving a legacy map does not serialize `npcWanderAreas: []`.
12. Add regression coverage for existing enemy-area geometry, both compatibility aliases, large frame deltas, and player/enemy packages/maps remaining unchanged.

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
4. Add state mutations for create/update/delete area. Generate the lowest unused `npc-area-NN` ID. Add one `MapEditorState.deleteObjectInstances(instanceIds)` mutation that removes all targeted objects plus their personal NPC areas atomically. Route single erase and box erase through it; route any selected-object Delete/Backspace action added in this phase through it as well. Do not invent an object-replacement workflow, but any existing replacement discovered during the consumer audit must use the same ownership mutation. Deleting only the area leaves the NPC stationary.
5. Add canvas pointer handling for create, select, move, and corner-resize. Area/object/safe-zone/enemy-area selections remain mutually exclusive and drag state clears on tool changes or scene shutdown.
6. Render NPC areas only while the tool is active using a lavender outline, quiet fill, resize handles, and a tether from area center/nearest point to its owner NPC. Reuse existing depth/selection conventions.
7. Add a compact panel section with selected NPC identity, shape choice, create/edit state, and delete action. Do not reuse or display the enemy roster/cooldown dialog and do not duplicate Character Studio movement values.
8. When an NPC is moved outside its raw perimeter, report the invalid relation immediately. Let the shared save validator remain authoritative for body-aware rejection and surface its precise response without writing.
9. Test activation, one-area ownership, ID allocation, circle/rectangle editing, single-erase cascade, box-delete cascade for mixed NPC/non-NPC selections, undo/redo of the atomic mutation, area-only delete, map scaling, invalid selection, selection cleanup, and absent-field legacy round trips.

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

1. Create `test:npcs` in `package.json` as soon as the first NPC test file exists, and add it to `pnpm check` before running this phase's focused verification. No pre-existing NPC test directory or script is assumed.
2. Define the four content-independent constants from the spec: margin 8 px, arrival distance 6 px, progress threshold 2 px, and stuck sample interval 750 ms.
3. Implement pure state transitions for idle/pause, target acquisition, moving, arrival, interaction lock, unlock, and stuck recovery. Accept clock/random inputs instead of reading Phaser globals.
4. Sample rectangle targets with independent linear X/Y interpolation and circle targets using angle plus `sqrt(random)` radial distance for uniform area distribution.
5. Map velocity to `walk-down`, `walk-up`, `walk-left`, or `walk-right` by dominant axis. Preserve the last facing while idle, but play the shared `idle` clip.
6. Explicitly handle zero speed, zero-duration pauses, already-arrived targets, very small positive valid domains, non-positive and unusually large delta, and repeated lock/unlock calls without loops or unbounded retargeting.
7. Add deterministic tests for every transition, containment, distribution formula inputs, exact boundary inclusion, large frame deltas, stuck recovery, and destruction/no-op behavior.

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
- `src/game/content/objects/objects.schema.json`
- `src/game/content/objects/ObjectCatalog.ts`
- `src/game/content/objects/npcs/npc-world.json`
- `src/game/content/objects/npcs/npc-world-scout.json`
- `vite.config.ts`
- `scripts/check-objects.mjs`
- `scripts/check-maps.mjs`

**Steps**

1. Add `BuiltNpcRegistration` plus `onNpcCreated` to MapBuilder. Branch on NPC metadata before `ObjectFactory.create`; emit placement information and never create a legacy object image. Keep `onObjectCreated` unchanged for ordinary objects.
2. Return `npcWanderAreas` in `BuiltMap` and prove maps with none return an empty readonly collection.
3. Implement `NpcActor` with an invisible Arcade anchor, body geometry from its package, `AnimatedVisual`, `CharacterAnimationTrackRunner`, policy state, world-depth synchronization, interaction-lock tokens, and idempotent destroy.
4. Synchronize every visual clip change to the track runner. Forward valid `npc.*` events through an optional presentation callback carrying the stable NPC instance ID; do not provide hitbox callbacks or emit to combat.
5. Implement `NpcRuntimeController` to resolve catalog/package links, match placements to personal areas, create actors, expose an NPC physics group/readonly handles, update actors, apply `setSimulationPaused(paused)`, and destroy all resources. Pausing clears velocity and freezes policy/track advancement; resuming discards stale targets and begins a fresh pause/target cycle.
6. Change `QuestNpcController.register` to accept a narrow actor handle containing stable IDs, current position, and `acquireInteractionLock()`. Keep all quest lookup, prompt priority, and text in that controller.
7. Compose both controllers in `WorldScene` in this order: create NPC and quest controllers before map build; route each `onNpcCreated` registration into the NPC controller; after build, attach personal areas and register actor handles with quest interaction; then create the NPC-group/static-world collider. Call NPC update only from the normal unpaused scene update.
8. Integrate the controller with `WorldScene.setSimulationPaused()`. Forward only effective paused-state transitions, include the NPC group in defensive `stopMovingBodies()` handling, and prove nested pause sources cannot resume NPCs early.
9. Use the shutdown order: destroy `QuestNpcController` and its pending timers/session handles; destroy the NPC collider; destroy `NpcRuntimeController`, actors, track runners, visuals, and NPC group; then continue collision/map/world teardown. Every stage is idempotent.
10. Once the actor path, Map Editor preview, collision, interaction registration, pause, and teardown tests are green, perform the placement-only cutover from the Phase 4 audit checklist. Make NPC archetypes omit and forbid `variants`, preserve `physics: null`, `definitionId`, stable `placementVisualId`, object IDs, and map-facing visual IDs, and remove asset/frame/scale/offset/object-animation fields. Remove the temporary legacy NPC runtime visual resolver only after `MapBuilder` can no longer call it for NPC metadata.
11. Update Vite object-authoring endpoints, `scripts/check-objects.mjs`, and `scripts/check-maps.mjs` to branch on the discriminated definition. They reject attempts to add ordinary variants or gameplay attributes to NPC placements while ordinary objects still require non-empty variants.
12. Do not add NPCs to enemies, combat targets, damage receivers, safe-zone steering, enemy spawn counts, drops, or save-game entity state.
13. Add tests/source assertions for no ObjectFactory image, NPC definitions valid without variants, ordinary definitions still requiring variants, one actor per placement, correct body/clip selection, track-event forwarding with instance ID, absent callback no-op, static NPC without area, collision-group exposure, pause/resume with nested sources, zero velocity while paused, fresh policy state after resume, ordered teardown, and idempotent disposal.

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

1. Add one `onClosed` callback to the current `QuestOfferModal` session and guard it with an idempotent session token. Invoke it exactly once after session cleanup for accept, decline, Escape, replacement, explicit close, and destroy. `QuestOfferModal.destroy()` must release the current session before `handle.unregister()`. Keep `onFinished` limited to successful quest bookkeeping; do not change `ModalStack.destroy()` into a global callback dispatcher.
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
