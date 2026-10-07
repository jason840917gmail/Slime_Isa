# Character Studio NPC and Authored Wander-Area Inclusion

## Goal

Make authored quest NPCs first-class character packages so their sprite sheets, animation clips, timing, visual transforms, and physics bodies are editable in the existing Character Studio alongside players and enemies. Each placed NPC may also receive one optional circle or rectangle wander area authored in the Map Editor. NPCs with an area wander inside it; NPCs without one remain stationary.

The two initial migrations are Village Elder Plop and Mossy Scout. Their player-facing names, descriptions, dialogue, and quest relationships remain owned by `NpcCatalog`; Character Studio does not become a dialogue or quest editor.

## Approved product and interface direction

Character Studio remains the only actor-authoring studio. Its roster gains `NPC` as a third role next to `PLAYER` and `ENEMY`; there is no separate NPC studio, page, or duplicated animation workflow.

The interface vocabulary comes from the game-authoring domain: actor roster, sprite sheet, animation clip, facing direction, physics body, quest NPC, map anchor, and wander boundary. The existing dark-indigo Studio shell remains intact. NPC affordances use a restrained lavender/moss accent that is distinct from player slime green and enemy amber/red. The Map Editor uses the same accent for NPC boundaries.

The signature interaction is the connection between a selected placed NPC and its personal wander boundary: while the NPC Area tool is active, a subtle lavender tether identifies the owning NPC even when its perimeter overlaps other map content.

The design intentionally avoids three tempting defaults:

- NPCs are not represented as zero-damage enemies. They receive a first-class `npc` role and no combat or loot controls.
- NPC authoring is not split into another studio. The existing frame canvas, timeline, preview, transform controls, tracks, and body editor are reused.
- Quest content is not copied into character packages. A stable catalog link connects quest identity to presentation without creating competing sources of truth.

## Ownership boundaries

### Character packages

Character content owns how an NPC looks and moves:

- sprite-sheet asset and visual-set identity;
- visual defaults and per-frame transforms;
- animation clips and timing;
- physics-body geometry; and
- basic wandering cadence.

Extend `CharacterKind` from `player | enemy` to `player | enemy | npc`. Add an optional `npc` gameplay document and require it when `kind` is `npc`. The NPC schema contract is exact: `player`, `enemy`, `runtimeRole`, and `attributes` must be absent; `hitboxes` must be an empty object; and every `animationTracks.hitboxSpans` collection must be absent or empty. NPC animation tracks may contain non-combat events whose stable IDs begin with `npc.` and whose optional payload is JSON data; other event namespaces are rejected for NPC packages. Character Studio hides/disables Add Hitbox and Add Span actions for NPC packages, retains Add Event with `npc.footstep` as its role-specific default, and keeps timeline frame, hold, and clip-timing editing through the visual set.

The first version of the NPC gameplay document is deliberately small:

```ts
interface NpcGameplayDocument {
  readonly wanderSpeed: number;
  readonly pauseMinMs: number;
  readonly pauseMaxMs: number;
}
```

`wanderSpeed` is a finite non-negative world-units-per-second value. Pause values are finite non-negative integers, and `pauseMaxMs` must be greater than or equal to `pauseMinMs`. A speed of zero is valid and produces stationary behavior even if an area is assigned.

`CharacterDocument.displayName` remains a package/editor label required by the common character schema. Runtime dialogue, prompts, quest offers, and floating messages never read that field for NPCs.

### NPC catalog

`NpcCatalog` continues to own:

- stable quest-facing NPC ID;
- player-facing display name;
- description and ordinary talk text; and
- relationships referenced by quest definitions.

Each `NpcDefinition` gains a required `characterId`. The catalog link is the only runtime route from quest identity to an NPC character package. The obsolete optional `visualId` field is removed rather than retained as a second presentation route. Catalog validation must reject a missing character, a non-NPC character, or two catalog definitions that accidentally claim the same character package unless a future design explicitly permits shared presentation.

The initial links are:

- `village-elder-plop` -> character package `village-elder-plop`;
- `level-1-spider-giver` (Mossy Scout) -> character package `mossy-scout`.

### Authored maps

The placed map object remains the source of the NPC's stable `instanceId`, quest definition ID, initial position, and map membership. Wander geometry is map content rather than character content because it is specific to one placement.

NPC object archetypes become placement definitions rather than presentation definitions. Their `npc` payload contains `definitionId` and one stable `placementVisualId`; NPC archetypes omit ordinary object `variants` and keep `physics: null`. The object schema requires `variants` for non-NPC archetypes and forbids it for NPC archetypes. Existing map instances retain their current `visualId`, which must equal the archetype's `placementVisualId`, so stable authored map references do not change.

`ObjectCatalog` exposes a discriminated Map Editor placement-choice union. Ordinary entries carry `kind: "object-visual"` and the existing `ObjectVisualChoice`; NPC entries carry `kind: "npc-character"`, stable object/placement IDs, `npcDefinitionId`, `characterId`, `visualSetId`, display label, and tags. NPC choices do not imitate the ordinary choice's uniform scale, visual offset, collider, or object-animation fields.

A small `NpcPlacementPreview` adapter always resolves and renders `npc-character` choices from the character package. It applies the visual set's first `idle` frame, origin, non-uniform scale, and source offset; owns explicit destroy cleanup; and contains no editable presentation values. `ObjectFactory` and the object-template editor accept only `object-visual` choices. Selecting an NPC in object-template tooling directs the author to Character Studio instead of creating presentation overrides.

Add an optional map-level collection:

```ts
interface MapNpcWanderArea {
  readonly id: string;
  readonly npcInstanceId: string;
  readonly perimeter: MapAgentAreaPerimeter;
}

interface MapFile {
  // existing fields
  readonly npcWanderAreas?: readonly MapNpcWanderArea[];
}
```

Extracting the generic geometry names preserves both `MapEnemyAreaShape` and `MapEnemyAreaPerimeter` as compatibility aliases, so existing enemy-area imports remain source-compatible.

Rename or generalize the existing circle/rectangle perimeter type and pure geometry helpers so both enemy camps and NPC areas reuse one implementation. Enemy-only concepts such as stay/pursue perimeters, roster weights, respawn interval, and population cap remain exclusive to `MapEnemySpawnArea`.

Each NPC instance may own at most one wander area. Multiple NPCs cannot share an area in this version. Omitting the collection or omitting an entry for a placed NPC is valid and means that NPC remains stationary. Perimeter containment is inclusive. New area IDs use the lowest unused `npc-area-NN` value; IDs remain stable when an area moves or resizes.

## Character Studio behavior

### Roster and package creation

The package roster maps all three character kinds explicitly. NPC entries receive an `NPC` label and a role-specific glyph/accent; code must not use a binary `player ? player : enemy` branch that silently treats NPCs as enemies.

The existing package-creation form gains:

- `NPC` in the kind selector; and
- an NPC starter template containing the required NPC gameplay fields, an empty `hitboxes` object, empty span arrays and optional `npc.*` events in starter tracks, a valid body, and starter `idle`, `walk-down`, `walk-up`, `walk-left`, and `walk-right` clips.

The creation endpoint and request parser accept `kind: "npc"` and an NPC template while retaining the existing path/ID safety rules. Creating an NPC produces the same `character.json` plus `visual-set.json` package shape used by the other roles.

### NPC inspector

Selecting an NPC preserves the existing source-asset shelf, sprite-sheet frame canvas, clip list, timeline, animation preview, visual defaults, frame transforms, animation-event controls, and body editor. Timeline frame selection, ordering, holds, clip timing, and `npc.*` events remain editable. Hitbox and span controls are absent for the NPC role because NPC v1 requires an empty hitbox definition and empty span collections.

The role-specific gameplay section contains only wander speed and pause range. Player identity controls and enemy health, AI, projectile, combat, and drop controls do not render for NPCs. Unsupported combat authoring is both unavailable in the UI and rejected by validation. `CharacterDocumentState` enforces the same restrictions at every mutation boundary: NPCs cannot add or update attributes, hitboxes, hitbox spans, combat/runtime-role data, or non-`npc.*` events even if a caller bypasses the controls.

The asset shelf continues to display ready sprite sheets, including unused sources. Once Village Elder Plop and Mossy Scout reference their authored sheets from visual sets, those sheets no longer appear as unused sources.

### Required directional clips

NPC packages require these canonical clips:

- `idle`;
- `walk-down`;
- `walk-up`;
- `walk-left`; and
- `walk-right`.

All clips must contain at least one valid frame. Character Studio may temporarily display an incomplete unsaved draft, but package saving and repository checks reject a missing required clip. Runtime therefore does not need a silent enemy-animation fallback.

The initial 6-by-5 sheets use six frames per row:

| Clip | Frames |
|---|---|
| `idle` | 0-5 |
| `walk-down` | 6-11 |
| `walk-up` | 12-17 |
| `walk-left` | 18-23 |
| `walk-right` | 24-29 |

Exact frame sequences, playback rates, offsets, and scale remain editable after migration; the table defines only the starter mapping.

## Map Editor behavior

### Tool activation and drawing

Add `NPC Area` to the existing Map Editor tool set. It reuses the enemy-area circle/rectangle drawing, tile snapping, bounds clamping, move, resize, undo, and redo mechanics, but owns separate state and rendering so no enemy roster or pursuit controls leak into NPC authoring.

The tool is enabled only when the selected map object resolves to a valid NPC definition. Activating it with a non-NPC selection keeps the current tool active and reports a concise status message. When the selected NPC already has an area, entering the tool selects that area instead of creating another.

Dragging empty map space creates the selected NPC's single perimeter. A selected perimeter exposes the same corner handles used by enemy areas. The overlay uses a lavender boundary, a quiet translucent fill, and a tether to the assigned NPC. NPC-area overlays are visible only while the tool is active, preventing authoring geometry from cluttering normal terrain and object work.

The panel presents only:

- selected NPC identity;
- circle/rectangle choice;
- `Create area` or `Edit area` state; and
- `Delete area`.

It does not open the enemy-camp dialog and does not duplicate movement-speed controls, which belong to Character Studio.

### Selection, movement, deletion, and resizing

An NPC placement and its area are separate authored coordinates. Moving an NPC does not silently translate its area. If the new position falls outside the assigned perimeter, the editor reports the invalid relationship immediately and saving remains disabled/rejected until the NPC or area is corrected.

`MapEditorState.deleteObjectInstances(instanceIds)` is the only object-deletion mutation. Single erase and box erase call it; any selected-object keyboard deletion added in this work must call it too. It removes each object and its referenced wander area in one mutation, so a single undo restores both. There is no separate object-replacement contract in this design. If replacement is introduced later, it must use the same ownership operation. Deleting only the area leaves the NPC in place and makes it stationary. Resizing the map scales NPC object positions and NPC perimeters by the same tile-size factor before applying map-bound validation.

Area selection is mutually exclusive with object, safe-zone, and enemy-area selection. Switching away from the NPC Area tool clears stale area selection and drag state. All pointer handlers, overlays, and DOM listeners follow the editor's existing cleanup lifecycle.

## Runtime design

### NPC actor

Introduce a focused runtime NPC actor/presentation unit rather than extending enemy combat AI. It owns:

- an invisible Arcade physics anchor at the authored object position;
- body geometry from the NPC character package;
- an `AnimatedVisual` using the package's visual set;
- a `CharacterAnimationTrackRunner` synchronized to the active visual clip;
- current facing, wander target, pause deadline, and stuck-detection state; and
- start/stop/update/destroy lifecycle methods.

The actor is non-hostile: it is not registered with enemy groups, combat targets, damage receivers, enemy population counts, safe-zone avoidance, drops, or death events. It collides with world bounds and the same authored static collision geometry used by other moving actors.

Map construction branches before `ObjectFactory.create`: an archetype with NPC metadata is never created as an ordinary object image. `MapBuilder` emits a dedicated `BuiltNpcRegistration` containing `objectId`, `instanceId`, `npcDefinitionId`, authored position, and initial state through an `onNpcCreated` callback, then continues to the next map object. Non-NPC objects retain the existing `ObjectFactory` path unchanged. Because the legacy NPC image is never created, there is no duplicate image to hide or destroy and no object-level idle animation lifecycle to leak.

A scene-owned NPC runtime controller receives the placement registration, resolves `NpcDefinition -> characterId -> CharacterPackage`, and creates exactly one NPC actor. The controller exposes the actor anchor to `QuestNpcController`. This replaces the current assumption that quest interactions must track a static `Phaser.GameObjects.Image`. Map Editor rendering follows the separate catalog-backed preview adapter described above; it never invokes the runtime NPC controller.

Whenever the actor changes its active visual clip, it starts the same clip on `CharacterAnimationTrackRunner`; its update loop advances the runner with scene delta time. The runner has no hitbox callbacks for NPCs. It forwards namespaced track events through an optional `NpcControllerContext.onPresentationEvent` callback containing NPC instance ID plus the existing character track event. This is the complete NPC v1 track interface: consumers may attach sound or cosmetic reactions, but combat systems are never recipients and an absent callback is a valid no-op. The actor destroys the runner with its visual and anchor.

`WorldScene` forwards the effective simulation-paused state to the NPC runtime controller. Pausing clears every NPC velocity and freezes policy/track advancement. Resuming discards stale targets and begins a fresh pause/target cycle rather than continuing pre-modal movement. Scene teardown destroys quest interaction timers and handles first, then the NPC collider, then NPC actors and their physics group, and finally the remaining collision/world resources.

`QuestNpcController` continues to own quest candidate priority, prompt text, offer/turn-in modals, talk events, and catalog text. Movement and animation remain outside it. The two controllers communicate through a narrow actor handle that exposes position plus an interaction lock; neither controller imports `WorldScene`.

### Wander policy

Define the policy constants in the focused `NpcWanderPolicy` module rather than in Character Studio data:

```ts
const NPC_AREA_MARGIN = 8; // world pixels
const NPC_TARGET_ARRIVAL_DISTANCE = 6; // world pixels
const NPC_STUCK_PROGRESS_DISTANCE = 2; // minimum progress per sample
const NPC_STUCK_SAMPLE_MS = 750;
```

Containment is based on the full anchor-relative Arcade body bounds, not only width/height. One shared `resolveEffectiveArcadeBodyBoundsRelativeToAnchor()` helper owns this calculation and is used by Arcade body setup, map reference validation, and runtime target clamping. It includes asymmetric center offsets and represents ellipses with the same conservative rectangle used by Arcade collision. Its extents are `centerOffsetX +/- width / 2` and `centerOffsetY +/- height / 2`. For a rectangle perimeter, derive the valid anchor rectangle by subtracting those asymmetric extents plus `NPC_AREA_MARGIN` from each edge. For a circle perimeter, conservatively subtract the maximum distance from the anchor to any resolved body-bounds corner plus the margin from the circle radius. The resulting valid anchor domain must have positive dimensions/radius and must contain the authored starting anchor; otherwise map reference validation rejects the area. A valid assigned area never silently falls back to stationary behavior because its body cannot fit.

For an NPC with an assigned area and positive wander speed:

1. Resolve the body-aware valid anchor domain described above.
2. Choose a random target inside the inset perimeter.
3. Move directly toward it at the package's `wanderSpeed`.
4. Select a directional walk clip from the dominant velocity axis.
5. When distance to the target is at most `NPC_TARGET_ARRIVAL_DISTANCE`, stop, play `idle`, and wait for a random duration in the inclusive configured pause range.
6. Choose another target and repeat.

The policy uses injectable randomness and a small pure state-transition helper so target selection and timing are deterministic in tests. Rectangle targets use independent linear interpolation on X and Y. Circle targets use a uniformly distributed angle and `sqrt(random)` radial distance so points are uniform by area. Full navigation/pathfinding is out of scope. Arcade collision prevents entering obstacles. Every `NPC_STUCK_SAMPLE_MS`, compare the remaining target distance with the previous sample. If it improved by less than `NPC_STUCK_PROGRESS_DISTANCE`, the actor abandons the target, stops, performs one configured random pause, and then selects another point. A successful sample resets the comparison baseline. Repeated stuck recovery never allows the actor to leave its valid anchor domain.

The actor's depth is derived from the bottom of its physics body using the existing world-depth utilities. `AnimatedVisual` remains render-only and cannot resize or relocate the physics anchor.

### Interaction locking

When an NPC interaction executes, the interaction controller acquires a movement lock before opening or showing content. The actor clears velocity and plays `idle`. The lock remains active for the lifetime of a quest modal. Extend `QuestOfferModal.openOffer` and `openTurnIn` with one `onClosed` callback stored for the current open session. `close()` invokes it exactly once after cleanup for accept, decline, Escape, replacement by another open, explicit close, and destroy. The existing `onFinished` callback remains responsible only for successful quest/talk bookkeeping and must not release movement.

Plain talk uses no modal and the current floating-message API exposes no completion handle. Define `NPC_PLAIN_TALK_LOCK_MS = 700` in `QuestNpcController`, matching the normal floating-text tween duration. Plain talk acquires a lock, spawns the message, and schedules release after exactly 700 ms with a scene timer. Destroying the controller or scene removes pending talk timers and releases/destroys their lock tokens idempotently; no `FloatingText` API change is required.

Every branch that acquires a lock must transfer it to one of those two explicit owners before returning: an opened modal's `onClosed`, or a 700 ms floating-message timer. In particular, reoffer failure and missing-refreshed-quest branches show their existing floating error, transfer the token to the timed-release helper, and return. A thrown error before any feedback or modal is created releases the token immediately in `finally`. Tests assert that no failed interaction path leaves a permanent lock.

Locks are reference-counted or token-based so a duplicate close callback cannot resume movement early. `QuestOfferModal` owns the current session callback and releases it from `destroy()` before unregistering its modal handle; this does not change `ModalStack.destroy()` into a global callback dispatcher. Destroying the actor, controller, or scene cancels timers and locks idempotently. After the final lock releases, the NPC discards any stale target and starts with a fresh pause/target cycle.

## Migration of the two authored NPCs

Create normal character packages beneath `src/game/content/characters/` for Village Elder Plop and Mossy Scout. Their visual sets reference the existing authored NPC sprite-sheet assets and receive the five canonical clips. Use these initial gameplay values:

| Character package | `wanderSpeed` | `pauseMinMs` | `pauseMaxMs` |
|---|---:|---:|---:|
| `village-elder-plop` | 18 | 1800 | 3200 |
| `mossy-scout` | 42 | 250 | 900 |

The Elder therefore reads as slow and deliberate, while Mossy reads as faster and playful without requiring a one-off movement engine. These values remain editable in Character Studio after migration.

Use these initial presentation/body defaults, preserving the scale of the current map-object art:

| Package | Origin | Scale | Body |
|---|---|---|---|
| `village-elder-plop` | `[0.5, 1]` | `[0.2, 0.2]` | ellipse, 34 x 24, radii 17 x 12, center offset `(0, 10)` |
| `mossy-scout` | `[0.5, 1]` | `[0.32, 0.32]` | ellipse, 36 x 24, radii 18 x 12, center offset `(0, 10)` |

Update `NpcCatalog` with the two `characterId` links. Keep the existing quest-facing ID `level-1-spider-giver` unchanged so quests and save data do not break.

Migrate runtime presentation away from the two object-level idle animation packages. Convert `npc.world` and `npc.world-scout` to placement-only NPC archetypes with their existing definition IDs and existing map-facing visual IDs (`slime-npc` and `slime-scout`). Remove their `assetId`, frame, scale, visual offset, and `idleAnimationId` presentation fields. Remove the two object-level animation packages and their references only after the character-package runtime and Map Editor preview paths are active and repository reference checks confirm nothing else consumes them. Runtime and editor preview scale, frame sequences, offsets, and body geometry then come exclusively from Character Studio packages.

Add these initial areas to `level-1.map.json`:

```json
[
  {
    "id": "npc-area-01",
    "npcInstanceId": "level-1-npc-village-elder-plop",
    "perimeter": { "shape": "circle", "x": 512, "y": 704, "radius": 96 }
  },
  {
    "id": "npc-area-02",
    "npcInstanceId": "level-1-npc-mossy-scout",
    "perimeter": { "shape": "rectangle", "x": 672, "y": 640, "w": 192, "h": 128 }
  }
]
```

Both starting anchors are inside their areas, the areas remain inside map bounds, and the exact initial bodies above fit their body-aware valid anchor domains. Future size and position changes are authored through Character Studio and the Map Editor rather than hard-coded in NPC gameplay data; repository checks catch a later body edit that makes an assigned area unusable.

## Validation and error handling

Character validation rejects:

- an unknown character kind;
- a missing or malformed NPC gameplay document;
- player/enemy-only data in an NPC package;
- invalid wander speed or pause bounds;
- missing/empty canonical NPC clips;
- invalid body geometry; and
- asset/frame references outside the visual set's source sheet.

Catalog/reference validation rejects:

- an NPC definition whose `characterId` is absent;
- a link to a player or enemy package; and
- unintended duplicate character-package ownership.

`parseMapFile` remains a dependency-free structural validator. It checks the `npcWanderAreas` container and field shapes, stable ID syntax, finite geometry, positive dimensions, map bounds, duplicate area IDs, and duplicate `npcInstanceId` assignments. It does not import Object, NPC, or Character catalogs and does not attempt body-aware validation.

Cross-catalog validation is a pure, dependency-injected function. It accepts a narrow resolver port for object placements, NPC definitions, character packages, and effective body bounds; it never imports `CharacterCatalog` or the `virtual-character-content` module. Immutable NPC definition data lives in a catalog-neutral TypeScript module that imports no character catalog; `NpcCatalog` consumes and exposes it. `MapRepository` supplies a browser adapter backed by Object/NPC/Character catalogs. The development save endpoint and `maps:check` supply Node adapters backed by that pure NPC definition snapshot plus authored object, character, and visual-set JSON. All three call the same validator and reject:

- references to missing or non-NPC object instances;
- a body-aware valid anchor domain with non-positive dimensions/radius; or
- an assigned NPC anchor outside that valid anchor domain.

Map Editor state applies the dependency-free structural checks before accepting local mutations. Save remains the authoritative cross-catalog gate and returns the first precise reference issue to the editor without writing the map.

An absent `npcWanderAreas` array is read as an empty collection without materializing the field in the editable document; merely opening, editing unrelated content, or saving a legacy map preserves omission. The first NPC-area authoring mutation creates the field, and undo/redo preserves whether it was absent or present. Runtime exposes an empty readonly collection either way. Invalid authored content fails loudly at load/save/check time; runtime does not silently detach a malformed area. If a valid NPC catalog/package link cannot be resolved because of a development-time hot-reload race, the scene reports the content error and leaves the placement inactive rather than treating it as an enemy or crashing the interaction router.

## Verification strategy

### Automated coverage

Extend the existing character-authoring tests to cover:

- parsing and validating `kind: "npc"`;
- rejecting cross-role fields and invalid pause ranges;
- NPC package creation through the Vite authoring endpoint;
- virtual package discovery and catalog retrieval;
- explicit three-way roster/inspector rendering; and
- saving edits to NPC clips, transforms, tracks, body, and movement settings.

Add map/editor tests for:

- parsing and serializing circle and rectangle NPC areas;
- one-area-per-instance and stable-reference validation;
- create, move, resize, delete, and undo behavior;
- cascading area deletion when its NPC is deleted;
- map resize scaling;
- rejected non-NPC selections and out-of-area placements; and
- legacy maps with no NPC-area field; and
- unchanged parsing/serialization of existing player/enemy packages and maps without NPC areas.

Extract the wander transition/target policy from Phaser-specific presentation and test:

- deterministic point selection for circle and rectangle perimeters;
- body-aware inset containment;
- zero-speed behavior;
- pause-range boundaries;
- dominant-axis clip selection;
- target arrival and stuck recovery; and
- interaction lock/resume transitions, including reoffer failure before a modal opens.

### Manual acceptance checks

1. Character Studio lists Village Elder Plop and Mossy Scout as `NPC`, alongside existing player and enemy entries.
2. Each NPC opens in the standard frame canvas and timeline, and edits persist through save/reload.
3. NPC inspectors show body/visual/animation and wander controls, with no enemy combat or loot controls.
4. Map Editor can draw, select, move, resize, delete, undo, and restore one circle or rectangle area for a selected NPC.
5. The area overlay and tether identify the correct NPC and disappear outside the NPC Area tool.
6. Both Level 1 NPCs wander inside their authored boundaries with the correct directional clips and do not cross world obstacles or map bounds.
7. The Elder reads as slow and deliberate; Mossy reads as faster and playful.
8. Starting a talk, offer, or turn-in stops the NPC; closing it resumes wandering without a jump or stale target.
9. NPCs remain non-hostile and do not affect combat targeting or enemy population.
10. An NPC with its area removed remains stationary and fully interactable.

Run the character, asset, animation, object, map, and quest content checks, the relevant script tests, strict TypeScript validation, and the production Vite build after implementation. The repository-wide `pnpm check` command is the final verification target.

## Out of scope

- A separate NPC studio or NPC-specific animation editor.
- Dialogue, quest, schedule, shop, or relationship editing in Character Studio.
- Shared wander areas, patrol paths, schedules, doors, or cross-map travel.
- Navmesh or grid pathfinding.
- NPC combat, damage, health, loot, pursuit, or respawning.
- Moving or translating an NPC area automatically when the NPC placement moves.
- Save-game persistence of an NPC's moment-to-moment wander position. NPCs begin from their authored map position when an area loads.
