# Fatty Guarded Chest and Boss Camp Implementation Plan

**Designs:**

- `docs/superpowers/specs/2026-09-11-fatty-one-eye-guarded-chest-design.md`
- `docs/superpowers/specs/2026-09-11-map-studio-boss-camp-authoring-design.md`

**Status:** Implemented, including the 2026-09-12 runtime/editor corrections below.

## 2026-09-12 implementation corrections

- Player movement across the arena edge no longer destroys or respawns a live
  boss. Fatty may finish an active cast or leap outside the combat circle and
  then enters a grounded return phase that walks to the authored arena center.
- The mini contact hop is a Character Studio boss animation. Its duration,
  source frames, active hit-layer window, shape, offsets, and size live in the
  `fatty-one-eye` character package; damage, cooldown, and knockback remain in
  the boss definition.
- Contact-hop collision uses the player's complete combat body rather than its
  center point, and the authored hit layer initially uses an 80 px circle.
- Development Tools has an independent Boss battle areas checkbox for the cyan
  activation and amber combat circles.
- The development map-save validator accepts and validates
  `chest.wooden.initialState.contents`, including known items, unique stacks,
  and positive quantities.

## Objective

Finish the Level 1 Fatty One Eye encounter and make the encounter fully
authorable in Map Studio. The completed slice must replace direct contact
damage with the approved collision-triggered contact hop, preserve the large
three-hop leap, make boss camps visible and editable as circular encounters,
keep guarded chests optional, and close the remaining persistence and
transaction-safety gaps in the guarded chest/key flow.

## Current baseline

The working tree already contains the main content package and much of the
runtime: boss/chest/key/potion/crack assets, boss and chest catalogs, save-schema
version 9 state, Fatty's large leap, eye-only spear damage, knockback immunity,
the chest inventory panel, green-key exit gating, an authored Level 1 camp, and
editable chest contents.

The remaining work is incremental:

- direct contact damage still uses a per-frame overlap poll;
- the player/boss collider has no contact-hop callback;
- Fatty has no 300 ms contact-hop phase;
- live fights do not yet preserve the boss and return it to center when the
  player draws it outside the arena;
- chest transfers and gate unlocks are sequential mutations rather than one
  rollback-safe aggregate transaction;
- boss camps are preserved by Map Studio but have no first-class selection,
  preview, creation, circle editing, or inspector controls;
- the map contract still requires a chest and still accepts rectangular boss
  perimeters; and
- roadmap/checklist language still refers to direct grounded contact damage.

Preserve the current dirty worktree and do not rewrite completed asset,
persistence, chest UI, or combat work unless a step below requires a focused
correction.

## Work sequence

### 1. Establish focused test seams and a baseline

Add a `test:bosses` package script and a focused test directory under
`scripts/tests/bosses/`. Keep deterministic state/timing decisions outside
Phaser where practical so Node tests can verify them without constructing a
scene.

Create `src/game/features/bosses/FattyOneEyeBehavior.ts` for small pure helpers
used by the Phaser adapter:

- whether a contact-hop request is eligible from the current phase and time;
- normalized 300 ms hop progress and visual height;
- whether the landing radius contains the player's current position; and
- preservation of the main special's existing `nextLeapAt` value when a
  contact hop finishes.

Add `scripts/tests/bosses/fatty-one-eye-contact-hop.test.mjs` before changing
the runtime. Cover the approved timing, exact radius boundary, cooldown start,
dodge rejection input, invalid phases, and overdue-special behavior. Add
source-boundary assertions only for wiring that cannot be exercised without a
browser; keep gameplay decisions in the pure helper tests.

Run the existing focused suites first and record any pre-existing failures:

```text
pnpm test:combat
pnpm test:persistence
pnpm test:map-editor
pnpm maps:check
pnpm typecheck
```

### 2. Align boss and map content contracts

Update the boss definition contract in:

- `src/game/content/bosses/types.ts`
- `src/game/content/bosses/boss.schema.json`
- `src/game/content/bosses/fatty-one-eye.json`
- `src/game/content/bosses/BossCatalog.ts`

Rename the old `contact` block to `contactHop`. It owns `cooldownMs: 1000`,
`damage: 18`, `knockbackStrength: 180`, plus references to the Character Studio
clip and hitbox. The character package owns the 300 ms duration and 80 px
initial hit circle. Extend catalog validation so every value is finite and
positive. Add a catalog-driven `BossEditorPreview` descriptor containing
the manifest asset ID, texture key, idle frame, origin, and definition-owned
scale. Both runtime and Map Studio must resolve Fatty's presentation through
this descriptor instead of hard-coding its asset ID.

Update the authored map contract in:

- `src/game/content/maps/mapFormat.ts`
- `src/game/content/maps/maps.schema.json`
- `src/game/content/maps/validateMapReferences.ts`
- `src/game/infrastructure/maps/BrowserMapReferenceResolver.ts`
- `scripts/check-maps.mjs`

Make `guardedChestInstanceId` optional. Constrain both boss perimeters to
positive-radius circles whose centers exactly equal `spawn`; require arena
radius to be no larger than activation radius; require the complete circles to
fit inside the map; and retain unique camp IDs, valid boss IDs, positive integer
respawn times, and unique valid chest ownership when a chest is present.

Update `src/game/content/maps/level-1.map.json` to use co-centered circles at
Fatty's current `(2528, 1472)` spawn, with activation radius `416`, arena radius
`320`, respawn time `180000`, and the existing guarded chest reference.

Add contract tests for valid chestless camps, invalid shapes/centers/radii,
duplicate chest ownership, unknown references, and the converted Level 1
record. Run:

```text
pnpm maps:check
pnpm test:bosses
pnpm typecheck
```

### 3. Implement the collision-triggered contact hop

Update `src/game/features/bosses/FattyOneEyeBoss.ts`:

1. Add `contact-hop` to the phase union and remove `applyContactDamage` plus
   the per-frame `physics.overlap` poll.
2. Expose `requestContactHop(time): boolean`. Accept only an alive,
   non-destroyed boss in `chase` at or after `nextContactHopAt`.
3. On acceptance, set the cooldown deadline immediately, store the current
   boss position as the stationary anchor, stop velocity, show the authored marker
   and shadow synchronously, and disable the Arcade body.
4. Advance the visual and active hit layer from the Character Studio
   `contact-hop` clip while leaving the combat anchor fixed.
5. At the authored hit-layer activation, play the crack effect and evaluate the
   player's complete combat body exactly once. Apply 18 damage and 180 knockback
   only when the player is active, intersects the authored shape, and is not
   currently dodging; the
   health system remains authoritative for any other active i-frame.
6. Return directly to `chase` without calling the large-leap recovery helper or
   changing `nextLeapAt`. An overdue large special becomes eligible on the next
   update.
7. Keep contact-hop airborne invulnerability consistent with the large leap.
   Defeat, reset, destruction, or scene cleanup must clear its presentation and
   prevent any delayed impact.

Refactor the common marker, shadow, crack, body-enable, and circular-impact
operations only enough to keep the contact hop and large leap consistent. The
large leap still captures the player's destination once, flies for one second,
deals 32 damage in its configured radius, shakes the camera, and enters
recovery. The contact hop does not shake the camera and never interrupts the
special, landing, recovery, or death phases.

Update `src/game/features/bosses/BossCampController.ts` so the existing blocking
player/boss collider invokes `requestContactHop(scene.time.now)` for the actual
Fatty target. A rejected request leaves the collider harmless. Do not use a
second overlap sensor or restore direct collision damage.

Extend the focused boss tests to cover one collider request, no damage at
request time, one landing hit, outside-radius and dodge safety, disabled-body
airborne safety, repeated callback rejection, the one-second cooldown measured
from hop start, special-phase non-interruption, and `nextLeapAt` preservation.

Run:

```text
pnpm test:bosses
pnpm test:combat
pnpm typecheck
```

### 4. Complete boss-camp lifecycle and optional guard behavior

Update `BossCampController` and Fatty's state machine to distinguish a live
fight, a player-death reset, and a recorded defeat:

- player exit/re-entry never destroys or restores a live boss;
- after Fatty finishes an uninterruptible action outside the arena, walk the
  existing instance back to the authored center without restoring health;
- on player death or scene reload, perform the same transient reset without
  starting the three-minute timer;
- only `onDefeated` writes `Date.now() + respawnMs`;
- after a true defeat, require the timer to expire plus an observed exit and
  re-entry before spawning; and
- clear the persisted deadline in the same synchronous spawn step that creates
  the next live boss.

Make chest lookup tolerate an absent `guardedChestInstanceId`. A chestless camp
still spawns, fights, dies, and respawns normally. A guarded non-empty chest is
locked only while its referenced camp has a live boss; a permanently empty
chest remains open.

Add focused lifecycle tests around pure perimeter/timer decisions for
never-defeated interior load, transient reset, true defeat, clock-forward and
clock-backward cases, exit/re-entry, single-instance enforcement, and optional
chests.

Run:

```text
pnpm test:bosses
pnpm test:persistence
pnpm typecheck
```

### 5. Make chest transfer and gate unlock aggregate transactions

Introduce `src/game/features/progression/InventoryWorldTransaction.ts` as the
single coordinator for operations that update both `Inventory` and
`WorldProgress`. Give `Inventory` and `WorldProgress` narrow prepare/install
snapshot methods rather than duplicating slot or save-state logic in
controllers.

For a chest transfer, the coordinator must:

1. capture both current snapshots;
2. compute the maximum accepted quantity without mutating either owner;
3. prepare the next inventory and chest snapshots;
4. install both without intermediate notifications;
5. roll both owners back if either install unexpectedly fails; and
6. emit inventory/world-progress changes only after both installs succeed.

Route `ChestController.transferStack` through that service. Preserve the
existing binary search or replace it with an equally deterministic maximum-fit
calculation. Zero capacity changes nothing; partial capacity moves only the
accepted amount; the last transfer persists `{ remaining: {} }` and keeps the
chest permanently open.

Route the gated exit branch in `WorldScene` through the same coordinator.
Unlock and optional item consumption must commit together, and an already
unlocked gate must never consume another key. Keep transition orchestration in
`WorldScene`, but move the cross-owner mutation out of the scene.

Add `scripts/tests/progression/inventory-world-transaction.test.mjs` for full,
partial, zero-capacity, invalid-item, injected-install-failure rollback,
single-notification, consuming gate, non-consuming gate, and idempotent unlocked
gate cases.

Run:

```text
pnpm test:progression
pnpm test:persistence
pnpm typecheck
```

### 6. Add first-class boss-camp state to Map Studio

Update `src/game/editor/MapEditorState.ts`:

- add `boss-camp` to `EditorTool`;
- normalize missing `bossCamps` to an empty editable array;
- add `selectedBossCampId` to `EditorViewState`;
- make boss-camp selection mutually exclusive with object, exit, safe-zone,
  enemy-area, and NPC-area selection;
- add create, select, update, move, radius-edit, and delete operations;
- generate stable IDs such as `boss-camp-01` without collisions;
- use the first catalog boss, 416/320 px radii, 180 seconds, and no chest for
  one-click creation;
- validate candidate geometry and chest ownership before every mutation;
- keep deletion limited to the camp record; and
- keep all changes in the existing serialized undo/redo history.

Spawn edits must move both circle centers. Activation and arena radius edits
must be independent, with arena never exceeding activation. Respawn is edited
in whole seconds but stored as positive integer milliseconds.

Complete resize behavior in `updateMapDimensions`: scale boss spawn and radii
only by the tile-size ratio; row/column-only changes retain their values; reject
any candidate that would leave the spawn or a complete circle outside the new
map. Do not clamp or silently move boss data.

Add `scripts/tests/map-editor/boss-camps.test.mjs` for defaults, selection
exclusivity, all mutations, independent radii, invalid edits, optional and
exclusive chest assignment, camp-only deletion, undo/redo, tile-size scaling,
row/column-only resizing, rejected shrink, and save/reload round trips.

Run:

```text
pnpm test:map-editor
pnpm maps:check
pnpm typecheck
```

### 7. Render and manipulate boss camps on the editor canvas

Update `src/game/editor/MapEditorScene.ts` to own editor-only boss presentation:

- maintain a `renderedBosses` map separate from `renderedInstances`;
- resolve preview sprites through `BossCatalog` and keep every authored boss
  visible in every tool;
- hit-test boss sprites before ordinary map objects where their bounds overlap;
- after the existing unsaved visual-template discard guard succeeds, clear the
  object-template context, preserve `GameplayAttributeEditorState` working
  drafts, switch to `boss-camp`, and select the camp;
- create a camp with one valid map click while the Boss Camp tool is active;
- drag the selected boss as one undoable spawn-and-centers move; and
- let Delete/Backspace remove only the selected camp.

While `boss-camp` is active, render low-opacity cyan activation and amber arena
circles with labels and exact radii. Render selected-state anchor treatment,
separate radius handles, and a gold connector to a valid guarded chest. Dragging
one handle changes only that radius and rejects invalid geometry with status
feedback. Hide camp circles, labels, connector, and handles in other tools while
leaving boss sprites visible.

Destroy every boss preview, label, connector, drag draft, and handle during
rerender and scene teardown. Use the existing explicit editor depth tokens and
do not place preview sprites into `map.objects` or a physics group.

Add focused tests for preview lookup, selection routing, template-discard
cancel/confirm behavior, gameplay-draft preservation, drag commit/cancel, radius
handle routing, and cleanup. Use manual browser verification for pixel-level hit
testing and overlay readability.

Run:

```text
pnpm test:map-editor
pnpm typecheck
```

### 8. Add Boss Camp panel and inspector controls

Update `src/game/editor/MapEditorPanel.ts` with the Boss Camp tool, compact count,
and concise usage/status copy. Keep exact properties out of the left panel.

Update `src/game/editor/MapEditorInspector.ts` so a selected boss camp renders a
dedicated inspector branch before the existing object-template branch. Include:

- read-only stable camp ID;
- boss catalog select;
- spawn X and Y;
- activation radius;
- arena radius;
- respawn seconds;
- guarded chest select with a clear `None` option; and
- delete camp.

Build the chest options from current-map object instances whose archetype has
the chest capability. Disable or omit chests claimed by another camp while
retaining the selected camp's current chest. Send every edit through
`MapEditorState`; show field/status errors instead of silently coercing invalid
data. Boss-definition combat values may be summarized for recognition but
remain read-only.

Keep object-template visual drafts subject to the existing confirmation guard.
Do not clear or prompt for cached gameplay-attribute drafts when switching to a
boss and back.

Update `src/styles.css` for the tool, inspector form, circle labels/handles, and
optional chest control using existing Map Studio tokens. Add DOM-level tests for
all controls, seconds-to-milliseconds conversion, `None`, duplicate-chest
filtering, deletion, and inspector mutual exclusion.

Run:

```text
pnpm test:map-editor
pnpm typecheck
pnpm build
```

### 9. Reconcile Level 1, roadmap, and checklist language

Update:

- `docs/GAME_ROADMAP.md`
- `docs/task/ideas/open/level-1-milestone-2-verification-checklist.md`
- `docs/task/ideas/open/starter-stone-age-progression.md`

Replace every claim that Fatty deals direct grounded contact damage with the
collision-triggered 300 ms contact hop and one 64 px landing hit. Add Map Studio
proof for visible boss selection, both editable circles, optional chest
assignment, and save/reload. Keep the ordinary worm camp refill behavior and
three-minute boss respawn requirements unchanged.

Do not regenerate the approved sprite sheets. Re-run manifest checks to prove
that the existing chest, twenty-key, ten-potion, Fatty, and crack assets still
match disk truth and remain at or below 96x96 per frame.

### 10. Final automated and manual acceptance

Run the narrow suites, then the complete verification sequence:

```text
pnpm test:bosses
pnpm test:combat
pnpm test:progression
pnpm test:persistence
pnpm test:map-editor
pnpm assets:check
pnpm objects:check
pnpm maps:check
pnpm typecheck
pnpm build
pnpm check
```

If `pnpm check` still stops on the known Windows Character Studio temporary-file
`EPERM`, verify that every preceding project command passes, capture the exact
failure, and keep that unrelated fixture issue separate from this slice.

Manual runtime acceptance must start from a fresh run and verify:

1. Fatty appears only in the separate Level 1 boss camp and the worm camp still
   refills normally.
2. Body collision starts the fast stationary hop, deals no immediate damage,
   shows the marker/shadow, and cannot trap or hurt the player while airborne.
3. Intersecting the authored landing hit layer causes one hit; dodging or
   leaving the shape avoids it; repeated collider callbacks respect the one-second
   cooldown.
4. The contact hop never cancels or postpones an eligible three-hop special.
5. Only Wooden and Stone Spear intersections with the exact central eye damage
   Fatty; knockback immunity suppresses displacement but not other feedback.
6. Leaving/re-entering the arena preserves the live boss and its health/action;
   player death, saving/loading, or destroying the scene restores a full-health
   fight without a defeat timer.
7. A true defeat unlocks the optional guarded chest and starts the three-minute
   wall-clock timer; exit/re-entry is required for the next spawn.
8. Chest selection and partial right-click transfer work, remaining contents
   survive reload and relock on respawn, and the final green key leaves the
   chest permanently open and empty.
9. The key is consumed exactly once, the east gate stays unlocked, and the
   Level 1 to Gloop Forest round trip preserves independent map state.
10. Map Studio opens Level 1 with Fatty visible, edits both circle radii and the
    optional chest independently, preserves gameplay drafts, and round-trips the
    complete camp record through save/reload and undo/redo.

## Expected file ownership

| Concern | Primary files |
|---|---|
| Boss tuning and editor preview | `src/game/content/bosses/types.ts`, `boss.schema.json`, `fatty-one-eye.json`, `BossCatalog.ts` |
| Boss-map contract and validation | `src/game/content/maps/mapFormat.ts`, `maps.schema.json`, `validateMapReferences.ts`, `scripts/check-maps.mjs` |
| Contact hop and encounter lifecycle | `src/game/features/bosses/FattyOneEyeBehavior.ts`, `FattyOneEyeBoss.ts`, `BossCampController.ts` |
| Aggregate loot/gate transactions | `src/game/features/progression/InventoryWorldTransaction.ts`, `WorldProgress.ts`, `src/game/systems/Inventory.ts` |
| Runtime composition | `src/game/scenes/WorldScene.ts` |
| Map Studio state | `src/game/editor/MapEditorState.ts` |
| Map Studio canvas | `src/game/editor/MapEditorScene.ts` |
| Map Studio controls | `src/game/editor/MapEditorPanel.ts`, `MapEditorInspector.ts`, `src/styles.css` |
| Authored encounter | `src/game/content/maps/level-1.map.json` |
| Focused verification | `scripts/tests/bosses/`, `scripts/tests/progression/`, `scripts/tests/map-editor/boss-camps.test.mjs` |

## Completion criteria

- Both approved specs are represented by runtime/editor behavior and automated
  contracts.
- Fatty has no direct-contact damage path or per-frame overlap polling.
- Every contact hop is collision-triggered, stationary, Character Studio
  authored, harmless before its hit-layer window, and capable of exactly one
  body-aware landing hit.
- Boss camps are circular, independently editable, visible in Map Studio, and
  valid without a chest.
- Chest loot and key-gate state cannot partially commit.
- Existing assets and ordinary enemy camps remain unchanged.
- Focused tests, content checks, strict TypeScript, and the production build
  pass; remaining manual checklist rows accurately describe what still needs
  human verification.
