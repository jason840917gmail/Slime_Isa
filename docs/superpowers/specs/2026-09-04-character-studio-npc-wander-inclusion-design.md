# Character Studio NPC and Authored Wander-Area Inclusion

## Goal

Make authored quest NPCs first-class character packages so their sprite sheets, animation clips, visual transforms, animation tracks, and physics bodies are editable in the existing Character Studio alongside players and enemies. Each placed NPC may also receive one optional circle or rectangle wander area authored in the Map Editor. NPCs with an area wander inside it; NPCs without one remain stationary.

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
- animation tracks;
- physics-body geometry; and
- basic wandering cadence.

Extend `CharacterKind` from `player | enemy` to `player | enemy | npc`. Add an optional `npc` gameplay document and require it when `kind` is `npc`. NPC documents must not contain `player`,` or `enemy` gameplay documents, `runtimeRole`, combat hitboxes, damage events, drops, or combat attributes.

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

Each `NpcDefinition` gains a required `characterId`. The catalog link is the only runtime route from quest identity to an NPC character package. Catalog validation must reject a missing character, a non-NPC character, or two catalog definitions that accidentally claim the same character package unless a future design explicitly permits shared presentation.

The initial links are:

- `village-elder-plop` -> character package `village-elder-plop`;
- `level-1-spider-giver` (Mossy Scout) -> character package `mossy-scout`.

### Authored maps

The placed map object remains the source of the NPC's stable `instanceId`, quest definition ID, initial position, and map membership. Wander geometry is map content rather than character content because it is specific to one placement.

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

Rename or generalize the existing circle/rectangle perimeter type and pure geometry helpers so both enemy camps and NPC areas reuse one implementation. Enemy-only concepts such as stay/pursue perimeters, roster weights, respawn interval, and population cap remain exclusive to `MapEnemySpawnArea`.

Each NPC instance may own at most one wander area. Multiple NPCs cannot share an area in this version. Omitting the collection or omitting an entry for a placed NPC is valid and means that NPC remains stationary.

## Character Studio behavior

### Roster and package creation

The package roster maps all three character kinds explicitly. NPC entries receive an `NPC` label and a role-specific glyph/accent; code must not use a binary `player ? player : enemy` branch that silently treats NPCs as enemies.

The existing package-creation form gains:

- `NPC` in the kind selector; and
- an NPC starter template containing the required NPC gameplay fields, empty combat hitboxes/tracks, a valid body, and starter `idle`, `walk-down`, `walk-up`, `walk-left`, and `walk-right` clips.

The creation endpoint and request parser accept `kind: "npc"` and an NPC template while retaining the existing path/ID safety rules. Creating an NPC produces the same `character.json` plus `visual-set.json` package shape used by the other roles.

### NPC inspector

Selecting an NPC preserves the existing source-asset shelf, sprite-sheet frame canvas, clip list, timeline, animation preview, visual defaults, frame transforms, animation-track controls, and body editor.

The role-specific gameplay section contains only wander speed and pause range. Player identity controls and enemy health, AI, projectile, combat, and drop controls do not render for NPCs. Unsupported combat authoring is rejected by validation rather than merely hidden.

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

Deleting an NPC deletes its referenced wander area in the same `MapEditorState` mutation, so a single undo restores both. Deleting only the area leaves the NPC in place and makes it stationary. Resizing the map scales NPC object positions and NPC perimeters by the same tile-size factor before applying map-bound validation.

Area selection is mutually exclusive with object, safe-zone, and enemy-area selection. Switching away from the NPC Area tool clears stale area selection and drag state. All pointer handlers, overlays, and DOM listeners follow the editor's existing cleanup lifecycle.

## Runtime design

### NPC actor

Introduce a focused runtime NPC actor/presentation unit rather than extending enemy combat AI. It owns:

- an invisible Arcade physics anchor at the authored object position;
- body geometry from the NPC character package;
- an `AnimatedVisual` using the package's visual set;
- current facing, wander target, pause deadline, and stuck-detection state; and
- start/stop/update/destroy lifecycle methods.

The actor is non-hostile: it is not registered with enemy groups, combat targets, damage receivers, enemy population counts, safe-zone avoidance, drops, or death events. It collides with world bounds and the same authored static collision geometry used by other moving actors.

Map construction registers NPC placement information with a scene-owned NPC controller. The controller resolves `object -> NpcDefinition -> characterId -> CharacterPackage`, creates the actor, and exposes its anchor to `QuestNpcController`. This removes the current assumption that quest interactions must track a static `Phaser.GameObjects.Image`.

`QuestNpcController` continues to own quest candidate priority, prompt text, offer/turn-in modals, talk events, and catalog text. Movement and animation remain outside it. The two controllers communicate through a narrow actor handle that exposes position plus an interaction lock; neither controller imports `WorldScene`.

### Wander policy

For an NPC with an assigned area and positive wander speed:

1. Inset the perimeter by half the larger body dimension plus a small safety margin.
2. Choose a random target inside the inset perimeter.
3. Move directly toward it at the package's `wanderSpeed`.
4. Select a directional walk clip from the dominant velocity axis.
5. On arrival, stop, play `idle`, and wait for a random duration in the inclusive configured pause range.
6. Choose another target and repeat.

The policy uses injectable randomness and a small pure state-transition helper so target selection and timing are deterministic in tests. Full navigation/pathfinding is out of scope. Arcade collision prevents entering obstacles; if progress toward the target stays below a small threshold for a bounded interval, the actor abandons the target, enters a pause, and later selects another point. Repeated stuck recovery never allows the actor to leave its perimeter.

The actor's depth is derived from the bottom of its physics body using the existing world-depth utilities. `AnimatedVisual` remains render-only and cannot resize or relocate the physics anchor.

### Interaction locking

When an NPC interaction executes, the interaction controller acquires a movement lock before opening or showing content. The actor clears velocity and plays `idle`. The lock remains active for the lifetime of the quest/talk modal and is released by the modal's close path. Plain floating-message talk interactions release after the message action completes rather than waiting indefinitely.

Locks are reference-counted or token-based so a duplicate close callback cannot resume movement early. Destroying the actor, controller, or scene cancels timers and locks idempotently. After the final lock releases, the NPC discards any stale target and starts with a fresh pause/target cycle.

## Migration of the two authored NPCs

Create normal character packages beneath `src/game/content/characters/` for Village Elder Plop and Mossy Scout. Their visual sets reference the existing authored NPC sprite-sheet assets and receive the five canonical clips. The Elder receives a slower speed and longer pauses; Mossy receives a faster speed and shorter pauses so her authored animation reads as playful without adding a one-off movement engine.

Update `NpcCatalog` with the two `characterId` links. Keep the existing quest-facing ID `level-1-spider-giver` unchanged so quests and save data do not break.

Migrate runtime presentation away from the two object-level idle animation packages. Remove those packages and their references only after the character-package runtime path is active and repository reference checks confirm nothing else consumes them. NPC object archetypes remain responsible for map placement and catalog identity; runtime scale, frame sequences, offsets, and body geometry come from Character Studio packages.

Add one authored wander area for each existing Level 1 NPC placement. Both starting positions must be inside their areas and the areas must remain inside map bounds. Their sizes and exact positions are authored in the Map Editor rather than hard-coded in NPC gameplay data.

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

Map parsing, `maps:check`, and save-time validation reject:

- duplicate NPC-area IDs;
- two areas referencing the same NPC instance;
- references to missing or non-NPC object instances;
- non-finite geometry or non-positive radius/width/height;
- a perimeter outside map bounds; and
- an assigned NPC position outside its perimeter.

An absent `npcWanderAreas` array normalizes to an empty collection in Map Editor state and to an empty readonly collection at runtime. Invalid authored content fails loudly at load/save/check time; runtime does not silently detach a malformed area. If a valid NPC catalog/package link cannot be resolved because of a development-time hot-reload race, the scene reports the content error and leaves the placement inactive rather than treating it as an enemy or crashing the interaction router.

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
- legacy maps with no NPC-area field.

Extract the wander transition/target policy from Phaser-specific presentation and test:

- deterministic point selection for circle and rectangle perimeters;
- body-aware inset containment;
- zero-speed behavior;
- pause-range boundaries;
- dominant-axis clip selection;
- target arrival and stuck recovery; and
- interaction lock/resume transitions.

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
