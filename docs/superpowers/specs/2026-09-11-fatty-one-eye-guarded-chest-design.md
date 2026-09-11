# Fatty One Eye Guarded Chest Design

## Status

Approved design for the Level 1 Milestone 2 guarded chest, reusable chest
inventory, respawning boss camp, green-key gate, and supporting sprite assets.

## Problem

Section E of the Level 1 Milestone 2 verification checklist still describes a
persistent `clear-once` ordinary enemy camp. That no longer matches the desired
gameplay. Ordinary camps, including the existing Level 1 worm camp, may refill
and must remain unchanged.

Level 1 instead needs a separate boss camp containing **Fatty One Eye**, a
large contact-damage slime that guards a reusable authored chest. The boss may
respawn, but the chest contents must never refill. The player defeats the boss
by standing beyond its contact reach and piercing its central eye with either
starter spear. The chest then provides the single green key required by the
east exit to Gloop Forest.

The repository already has normal enemy combat, map enemy areas, inventory,
the inventory backplate, a boss health bar, boss quest facts, and map-scoped
progress collections. It does not have a production boss controller, authored
boss camps, eye-only damage, chest objects or chest inventory state, key art or
items, gated exits, or the required Map Studio controls. Existing HP and energy
potions use procedural textures rather than an authored potion sheet.

## Goals

1. Add reusable authored boss camps without changing ordinary enemy-camp
   respawn behavior.
2. Implement Fatty One Eye with contact damage, spear-only eye vulnerability,
   a three-hop leap telegraph, airborne safety, and landing area damage.
3. Give enemies and bosses a shared, data-authored effect-immunity list.
4. Add reusable map-visible chests whose contents are editable in Map Studio
   and persist independently from boss respawns.
5. Add the Level 1 green key and permanent keyed east exit.
6. Create a cohesive sprite package for the boss, chest, twenty keys, ten
   potions, and landing effect, with no source frame larger than 96x96.
7. Replace the obsolete `clear-once` rows in checklist Section E with the
   approved respawning-boss flow and verify it across save/load.

## Non-goals

- Do not remove, convert, or rebalance the existing Level 1 worm camp.
- Do not build a universal encounter graph or convert normal enemies into boss
  controllers.
- Do not invent gameplay definitions or effects for the eight unused potion
  frames or nineteen unused key frames.
- Do not persist mid-fight boss HP, current attack phase, or animation frame.
- Do not add gore, realistic remains, terrain destruction, or permanent ground
  cracks.
- Do not give Fatty One Eye shockwaves beyond the defined landing area, ranged
  attacks, summoned enemies, or additional phases in this milestone.

## Architecture

### 1. Authored boss camps

Add an optional `bossCamps` collection to the authored map format. A boss camp
is separate from `enemySpawnAreas` and contains:

```ts
interface MapBossCamp {
  readonly id: string;
  readonly bossId: string;
  readonly activationPerimeter: MapEnemyAreaPerimeter;
  readonly arenaPerimeter: MapEnemyAreaPerimeter;
  readonly spawn: { readonly x: number; readonly y: number };
  readonly respawnMs: number;
  readonly guardedChestInstanceId: string;
}
```

IDs must be non-empty and unique within the map. `bossId` must resolve through
the boss catalog. The spawn point must be inside the arena. The guarded chest
must resolve to exactly one chest object instance on the same map. A chest may
be guarded by at most one boss camp. `respawnMs` must be a positive safe
integer.

Level 1 receives a new boss camp for `fatty-one-eye` with a three-minute
(`180000` ms) respawn duration. Its arena and chest are placed away from the
existing ordinary camp so that the worm encounter retains its current
behavior.

`BossCampController` owns activation, arena entry/exit tracking, boss creation,
health-bar lifetime, defeat handling, and respawn eligibility. It receives map
data and dependencies through a context interface and does not import
`WorldScene`.

After a defeat, the controller persists an absolute `respawnReadyAtEpochMs`
using wall-clock time. The timer therefore continues while the game is closed.
When the timestamp has passed, the boss does not appear on top of a player who
is still inside the arena. It waits until the player has been observed outside
the activation perimeter and then crosses back inside. Loading at an interior
saved position also requires a later exit and re-entry before spawning.

That suppression applies only when a persisted defeat timestamp exists. On a
never-defeated camp, or after leaving, dying, or loading during an active fight,
the controller creates a full-health boss immediately when the scene starts or
the player is already inside the activation perimeter. A transient fight reset
can therefore never produce an unguarded chest. These resets do not start the
defeat cooldown. Only an actual boss death writes the respawn timestamp.

Chest access distinguishes three guard states rather than inferring safety from
the temporary absence of a sprite:

- `never-defeated-or-fight-reset`: chest locked; the full-health boss is
  present or is created immediately;
- `defeated-window`: chest accessible from the recorded death until the next
  actual boss spawn, including time spent awaiting the required re-entry;
- `live`: chest locked unless already permanently empty.

### 2. Boss definitions and shared effect immunities

Add a validated boss catalog whose definitions own presentation and balancing:

- stable ID and display name;
- visual-set ID and authored display scale;
- max HP and physical body geometry;
- central eye vulnerability geometry;
- grounded movement and contact-damage settings;
- three-hop, leap, landing, and recovery timings;
- landing radius, damage, and knockback;
- allowed eye-damaging weapon categories or IDs;
- effect immunities and reward/quest identity.

The normal enemy definition schema and boss schema share this optional field:

```ts
effectImmunities?: readonly EnemyEffectImmunity[];
type EnemyEffectImmunity = 'knockback';
```

The field is optional and defaults to an empty list. Unknown and duplicate
values fail content validation. Fatty One Eye declares `['knockback']`.
Existing enemies remain unchanged.

Combat resolves the target's declared response instead of checking a hard-coded
`isBoss` flag. Knockback immunity removes physical displacement only. It does
not suppress damage, impact visuals, damage flash, floating numbers, hit-stun,
or later status effects. If more effects gain immunity support later, they are
added as explicit union members. Damage-type immunity, if ever needed, uses a
separate contract so it cannot be confused with control-effect immunity.

### 3. Fatty One Eye combat controller

`FattyOneEyeController` owns a non-directional state machine:

```text
dormant -> active/chasing -> hop 1 -> hop 2 -> hop 3
        -> airborne -> landing impact -> recovery -> active/chasing
        -> defeated
```

The boss always faces the camera so the vulnerable eye stays visible. Initial
authored tuning is:

| Field | Initial value |
| --- | ---: |
| Max HP | 140 |
| Visual scale | 1.5 |
| Physical body | 88x58 ellipse |
| Eye vulnerability | 30x30 centered rectangle, 8 pixels above body center |
| Ground chase speed | 42 pixels/second |
| Contact damage / cooldown | 18 / 1000 ms |
| Contact knockback | 180 |
| Leap cadence | 5000 ms after recovery ends |
| Small hops | 3 x 260 ms, with 100 ms between hops |
| Air time | 1000 ms |
| Landing radius | 64 pixels |
| Landing damage / knockback | 32 / 280 |
| Landing recovery | 700 ms |
| Rejected-hit message throttle | 700 ms per boss and reason |
| Crack-effect fade | 650 ms |
| Camera shake | 100 ms at intensity 0.003 |

All values remain definition-owned and may be tuned after playtesting without
changing controller code. The 88x58 body/contact footprint is shorter than the
80-88 pixel starter spear thrust once the player's own body radius is included,
so careful maximum-range attacks can reach the eye without touching the boss.

Grounded body contact damages and knocks the player back, subject to a contact
cooldown so overlapping physics callbacks cannot apply damage every frame.
Existing player dodge invulnerability remains authoritative.

The special attack becomes eligible while the boss is in `active/chasing`, the
player is inside the arena, and 5000 ms have elapsed since the previous landing
recovery ended (or since the boss first became active). Eligibility starts one
sequence and resets no earlier than recovery completion. The attack performs
three small stationary hops. After the third hop, the boss captures the
player's current world position once and uses it as the landing destination.
It does not home toward later movement. Air time is 1000 ms.

Small hops are visual grounded telegraphs, not the `airborne` combat state.
Ground contact damage remains active during `active/chasing`, all three small
hops, and recovery. The instantaneous landing-impact state applies only its one
area hit so it cannot double-hit through body contact on the same frame.

Accepted spear hits never cancel, restart, or skip a hop/leap sequence. Hit-stun
stops chase velocity in `active/chasing`; during stationary hops and recovery,
its timer may continue to elapse but the authored sequence timers remain
authoritative. Flash, damage numbers, and impact effects still play. This lets
Fatty One Eye suffer hit-stun without allowing repeated spear hits to suppress
the special attack indefinitely.

While airborne:

- the boss cannot take player damage;
- its overlap and collision cannot damage or trap the player;
- its visible sprite rises/scales to communicate height;
- an elliptical shadow remains beneath its apparent position and changes size
  and opacity with height;
- a clear ground marker shows the locked landing center and damage radius.

Landing applies one circular area hit, with configured damage and knockback,
then enters a short punishable recovery. It also plays a temporary radial
cracked-ground and slime-splash effect plus restrained camera shake. The cracks
fade and never change terrain data or collision.

### 4. Eye-only damage

Fatty One Eye has one physical body and a separately authored central-eye
vulnerability. Extend weapon-hit requests with the active hitbox's normalized
world-space combat shape: rectangle, circle, or ellipse with its resolved
center, dimensions/radii, and rotation where applicable. `HitboxPool` already
owns the active geometry and produces this immutable snapshot at hit time.
Ordinary damage targets ignore it; the boss target intersects it with the
definition-owned eye rectangle. This avoids a second physics target that could
double-register one attack and gives eye geometry one authoritative owner.

Damage acceptance rules, in order, are:

1. Reject if the boss is dead or absent.
2. Reject if the boss is airborne.
3. Reject if the active weapon is not the Wooden Spear or Stone Spear.
4. Reject if the active attack geometry does not intersect the eye.
5. Otherwise apply normal weapon/combo damage and all non-immune feedback.

Rejected body or wrong-weapon hits do not reduce HP, start hit-stun, change the
boss state, or play a successful impact effect. They show throttled feedback
such as `Aim for the eye!`. Both starter spears may damage the eye; the Stone
Spear is faster to finish the encounter because of its higher damage.

### 5. Reusable authored chests

Add a reusable chest object archetype with closed/open visuals and the normal
stable object `instanceId`. Chest gameplay metadata belongs concretely in the
placed `MapObjectInstance.initialState`, following the existing object-state
contract, not in `asset/assets.json` or a second top-level map collection:

```ts
interface MapChestContentsEntry {
  readonly itemId: string;
  readonly quantity: number;
}

interface MapChestInitialState {
  readonly contents: readonly MapChestContentsEntry[];
}
```

Every item must resolve through the combined base-item and weapon catalog.
Quantities must be positive safe integers. Duplicate item rows are rejected so
each item has one authoritative quantity. Guard ownership has one direction:
`MapBossCamp.guardedChestInstanceId` points to the object. The chest inspector
may display the derived guard, but does not serialize a reciprocal field.

The chest object archetype declares `contents` as an allowed gameplay initial
state key through `ObjectInitialState.ts`. `MapBuilder` passes the state in its
normal object-created registration, and `ChestController` accepts only
registrations whose object archetype has the chest capability. Structural
validation reports paths such as `objects[4].initialState.contents[0].itemId`;
reference validation confirms the item and boss/chest links.

Level 1's boss chest contains only `green-key x1`. The generic format may hold
materials, potions, keys, collectibles, tools, or weapons.

During map construction, `ChestController.register` calls
`WorldProgress.ensureChestInitialized` before the chest becomes interactive.
If no runtime record exists, it copies and normalizes the authored contents and
persists that record immediately. If a record exists, authored quantities are
ignored. Later content changes therefore do not refill an initialized chest in
an existing save. A reset run removes runtime state and seeds the then-current
authored contents again.

`ChestController` derives access from the guard and chest state:

- while the boss is alive, a non-empty chest is closed and interaction reports
  that its guardian must be defeated;
- after the boss dies, the chest may be opened and looted;
- if the boss later respawns before the chest is empty, the chest closes and
  locks while retaining its exact remaining contents;
- when the final item is removed, the chest is permanently marked empty and
  remains visibly open even after later boss respawns;
- an empty chest can still open an empty inspection panel.

The chest is locked by a live boss, not merely by an elapsed cooldown. If the
player remains in the arena past the cooldown without triggering the required
exit/re-entry spawn, the defeated boss is still absent and the chest remains
accessible.

When the controller creates the next boss instance, it clears the camp's
`respawnReadyAtEpochMs` in the same synchronous lifecycle step before exposing
the boss to physics. From that point the guard state is `live`, the non-empty
chest is locked, and a save/load restarts that live fight at full health.

### 6. Chest inventory UI and transfer rules

`ChestInventoryUI` reuses `ui.backplate.inventory` and the existing modal/input
patterns. The left region displays chest slots; the right region displays the
selected item's icon, name, category, remaining quantity, and description.

- Left-click selects a chest slot and shows its properties.
- Right-click attempts to transfer that slot's stack.
- The transfer moves the maximum quantity the player inventory can accept.
- If only part fits, the accepted amount enters inventory and the exact
  remainder stays in the chest.
- If nothing fits, neither state changes and clear feedback is shown.
- The chest quantity is decremented only by the amount the inventory reports
  as accepted.
- Closing the modal preserves all remaining quantities.

`ProgressionInventoryTransactionService` is the aggregate mutation boundary
for chest transfers and keyed gates. For a chest transfer it:

1. clones the current inventory slots and chest record;
2. computes the maximum accepted quantity in a pure draft without emitting;
3. produces both next snapshots or rejects the request;
4. installs both validated snapshots in one notification batch;
5. rolls both owners back to their captured snapshots if either installation
   unexpectedly throws; and
6. emits inventory/world-progress notifications only after both installs
   succeed.

Recovery or named-save capture therefore cannot observe only half of a
transfer. `ChestController` delegates to this service and refreshes the UI from
the committed result. Modal pointer and keyboard input is isolated so
right-click does not also attack or interact with the world, and the browser
context menu is suppressed only for the active game interaction surface.

### 7. Green key and gated east exit

Register `green-key` as a non-stackable (`maxStack: 1`) category `key` item.
It has no world-drop definition in this milestone, so normal inventory dropping
cannot discard it into the world.

Extend authored exits with an optional gate:

```ts
gate?: {
  readonly id: string;
  readonly requiredItemId: string;
  readonly consumeOnUnlock: boolean;
  readonly lockedMessage: string;
};
```

Gate IDs are stable and unique within the map. Required items must be known.
The Level 1 east exit to Gloop Forest requires one `green-key` and consumes it
on first unlock. Without the key, overlap refuses transition and shows locked
feedback at most once per gate every 700 ms. With the key, the aggregate
transaction service
commits inventory removal and persistent gate unlock exactly once before
transition. An already-unlocked gate never requires or consumes another key
and remains open after reload.

Generic `consumeOnUnlock: false` gates still require at least one copy of the
configured item at first use, but persist the gate unlock without changing
inventory. That world-only commit must succeed before transition. For
`consumeOnUnlock: true`, item removal and unlock use the shared two-owner
transaction. In both cases a subsequent overlap consults only the persisted
unlock and does not re-check the item.

`GateController` owns this decision and exposes transition permission to the
existing navigation feature. It does not own map loading.

### 8. Map Studio authoring

The chest appears in the normal object palette, can be placed/moved like other
objects, and previews its closed frame by default. Selecting a chest exposes a
`Chest Contents` section with add/remove rows, a searchable known-item picker,
positive quantity input, and optional guarding boss-camp selection.

Add a Boss Camps editor using the existing area-authoring conventions. It can
draw/edit the activation and arena perimeters, place the boss spawn anchor,
select a boss definition, link the guarded chest, and edit the respawn duration
in readable seconds while serializing milliseconds.

The Map Connections inspector exposes gate ID, required item, consume-on-unlock,
and locked message for each exit. All three authoring surfaces use the same pure
validators as the runtime map loader and repository checks. Tab/selection
changes retain independent drafts and must not silently save or discard edits.

These additions are optional and backward compatible, so authored maps retain
format version 1. `mapFormat.ts` remains the structural parser used at runtime;
`validateMapReferences.ts` owns cross-catalog and cross-instance references;
`ObjectInitialState.ts` owns chest initial-state validation. Map Studio and
`maps:check` call the same pure helpers instead of duplicating their rules.

## Persistence and data flow

Map runtime state gains normalized boss-camp and chest records in addition to
the existing completed-encounter/reward/gate collections:

```ts
interface BossCampProgressData {
  readonly respawnReadyAtEpochMs?: number;
}

interface ChestProgressData {
  readonly remaining: Readonly<Record<string, number>>;
}
```

Absence of a chest record means uninitialized. Presence means initialized.
Every `remaining` key is a known item ID and every stored quantity is a positive
safe integer. An empty `remaining` record is the sole permanent-empty marker;
there is no second `emptied` boolean that could disagree. Transient open-modal
and active-fight state is excluded.

```text
authored map/boss/item content
        |
        +--> BossCampController --> boss state machine --> defeat timestamp
        |            |                      |
        |            +--> chest access <----+
        |
        +--> ChestController --> ChestInventoryUI --> player inventory
        |            |
        |            +--> remaining chest contents / permanent empty state
        |
        +--> GateController --> one key removal --> permanent exit unlock
                                      |
                                      v
                           existing area navigation
```

`WorldProgress` exposes intent-level methods for boss defeat timestamps, chest
initialization/remaining quantities, and gate unlocks. Each method clones and
normalizes data, performs no-op detection, and emits `world.progress.changed`
only when state actually changes.

Inventory and `WorldProgress` also expose validated draft/install hooks used
only by `ProgressionInventoryTransactionService`. They do not reference one
another. Notification batching is owned by the transaction service, keeping
the two storage owners independently understandable while providing one atomic
progression mutation boundary.

The existing permanent `defeatedBossIds` collection remains an "ever defeated"
quest fact. It must not suppress a respawning boss. The first defeat records the
fact; every successful death may emit the normal runtime boss-defeated event,
but persistence remains idempotent. Boss-camp cooldown state is the sole source
of respawn timing.

Older save data receives empty/default boss-camp, chest, and gate state through
a schema migration. A corrupt record is rejected by the repository validation
boundary rather than partially installed into the active run.

## Visual asset package

All new raster assets use transparent backgrounds and match the existing
glossy, outlined, kid-friendly storybook presentation.

### Fatty One Eye

- Source frames are 96x96 and may render larger through authored scale.
- The boss is front-facing and non-directional with one oversized, high-contrast
  central eye.
- Its body is dirty translucent green with bubbles, warts, drool, grime, and
  uneven cartoon teeth.
- Colorful jelly chunks, small leaves/sprouts, and playful cartoon eyes or faces
  from swallowed slimes are visibly suspended inside it, without blood, gore,
  or realistic remains.
- Clips cover idle, grounded movement, small-hop telegraph, leap ascent,
  airborne hold, landing, recovery, hit, and death.
- A separate 96x96 animated radial ground-crack/slime-impact sheet fades after
  the landing effect.
- The dynamic shadow and landing marker are generated at runtime so they can
  follow authored height and radius values.

The boss sheet is a 6x6 grid (576x576 total), with this stable frame map:

| Row / frames | Clip |
| --- | --- |
| Row 0, 0-3 | `idle` |
| Row 0, 4-5 | `hit` |
| Row 1, 6-11 | `walk` |
| Row 2, 12-15 | `small-hop`; replayed exactly three times |
| Row 2, 16-17 | reserved transparent cells |
| Row 3, 18-21 | `leap-ascent` |
| Row 3, 22-23 | `airborne` hold |
| Row 4, 24-27 | `land` |
| Row 4, 28-29 | `recovery` |
| Row 5, 30-35 | `die` |

The visual-set document owns frame rates, looping, and clip-to-frame mappings.
Reserved cells are intentionally transparent and are not runtime frames. The
ground-crack effect is a separate horizontal 4x1 sheet (384x96) played once.

### Chest

- One 64x64-frame sheet with distinct closed and open frames.
- Chunky wood, metal corners, a readable lock plate, and restrained slime-world
  ornamentation match the inventory backplate.
- The open frame shows an empty interior cavity rather than fixed loot because
  contents vary per map instance.

### Keys

- One 5x4 sheet with exactly twenty 64x64 frames.
- Every frame differs by silhouette and color, rather than color alone.
- Themes include leaf/vine, thorn, spiral, crystal, crescent, gear, flame,
  wave, mushroom, cartoon bone, star, crown, fang, flower, rune, and other
  similarly readable shapes.
- The green leaf/vine frame is assigned to Level 1's `green-key`. The other
  nineteen frames are available assets only until future item definitions need
  them.

### Potions

- One 5x2 sheet with ten 64x64 frames.
- Bottle silhouettes, liquid colors, stoppers, and symbols remain readable at
  inventory scale.
- Two frames replace the procedural HP and energy potion visuals.
- The other eight frames are registered as visual frames only and do not gain
  speculative item IDs or effects.

All sheets are entered in `asset/assets.json` with stable IDs, exact frame
dimensions, origins, and appropriate runtime/editor/inventory tags. Asset
validation must reject wrong frame dimensions, missing files, or orphaned
production art.

## Error handling and edge cases

- Invalid boss, chest, item, or gate references fail map validation with their
  exact map field path.
- Invalid immunity values fail the enemy/boss content checker.
- Body hits, wrong-weapon eye hits, and airborne hits cause no HP, hit-stun,
  state, or successful-effect changes.
- Contact and landing damage are each protected against repeated physics
  callbacks within one attack/cooldown.
- A zero-capacity chest transfer changes neither inventory nor chest state.
- Partial transfers decrement only the accepted amount and never mark the chest
  empty early.
- Chest runtime records are created during object registration. Absence means
  uninitialized; `{ remaining: {} }` means permanently empty; no other empty
  state representation is valid.
- Repeated interaction, save/load, boss respawn, and subsequent boss defeats
  never recreate removed chest contents.
- An empty chest is permanently open and ignores guard relocking.
- Wall-clock time moving forward may make a boss immediately eligible. Clock
  movement backward delays eligibility until the stored timestamp; it never
  creates duplicate bosses or loot.
- Only one live boss instance may belong to a boss camp. Scene shutdown removes
  its timers, physics callbacks, UI, effects, and global listeners.
- Player death or scene exit during a leap removes the shadow, marker, crack
  effect, and pending damage callback.
- A consuming gate is persisted in the same aggregate commit as item removal.
  A non-consuming gate requires the item but persists without removing it. Any
  rejected aggregate commit prevents both unlock and transition.

## Implementation phases and compatibility gates

The implementation plan must split this design into the following sequential,
independently verifiable phases. Each phase ends with its focused tests plus
`pnpm typecheck`; no authored Level 1 boss camp is activated until all runtime
dependencies exist.

1. **Content and persistence foundations:** shared effect-immunity contract,
   boss catalog/schema, optional map `bossCamps` and exit gate fields, chest
   `initialState.contents`, green-key item, save migration, pure validators, and
   focused contract tests. All new map fields remain optional, so production
   behavior is unchanged at this gate.
2. **Asset package:** generate, normalize, register, and validate the boss,
   chest, keys, potions, and landing-effect sheets. Existing procedural potion
   texture keys remain available until item definitions switch atomically to
   the ready sheet frames.
3. **Boss runtime:** aggregate immunity handling, hit geometry, boss-camp
   lifecycle, Fatty One Eye state machine, health UI, shadow/marker/landing VFX,
   cleanup, and focused combat/timer tests. It is exercised on a fixture map;
   Level 1 is still unchanged.
4. **Chest runtime:** chest object capability, initialization, aggregate
   transaction service, guarded access, chest inventory UI, persistence, and
   focused partial-transfer/refill tests on fixtures.
5. **Gate runtime:** generic consuming/non-consuming gate transaction rules,
   navigation integration, persistence, and focused gate tests on fixtures.
6. **Map Studio:** boss-camp authoring, chest contents, connection gates,
   shared validation, undo/redo, and editor round-trip tests. Existing maps
   still load unchanged because every new field is optional.
7. **Level 1 integration and close-out:** author Fatty One Eye's camp, chest,
   green-key east gate, update checklist terminology, run the full command
   sequence, and complete the manual fresh-run matrix.

## Verification

Add focused automated coverage for:

1. Normal enemy definitions defaulting to no effect immunities.
2. Knockback immunity removing displacement while retaining damage, flash,
   impact, floating-number, and hit-stun behavior.
3. Wooden and Stone Spear intersection with the eye.
4. Body, non-spear, airborne, dead, and invalid-damage rejection paths.
5. Three stationary hops, one-time target capture, one-second airborne timing,
   landing-radius damage, shadow/marker cleanup, and recovery.
6. Contact-damage cooldown and existing dodge invulnerability.
7. Boss death timestamp, three-minute real-time cooldown, no spawn while the
   player remains inside, and spawn after exit/re-entry.
8. Full-health restart after save/load, arena exit, and player death without a
   false defeat cooldown.
9. Chest initialization, partial transfers, zero capacity, remaining-content
   save/load, relocking on boss spawn, and permanent empty/open state.
10. No chest refill after repeated boss deaths, reloads, or map round trips.
11. One green-key consumption, idempotent gate unlock, and unlocked reload.
12. Boss-camp, chest-content, and connection-gate Map Studio save/reload,
    undo/redo, validation, and draft-preservation behavior.
13. Save migration from the previous schema with normalized empty new state.
14. Asset manifest paths, 64x64 and 96x96 frame metadata, and orphan checks.

Run the narrow content/editor/runtime tests after each slice, then:

```text
pnpm maps:check
pnpm assets:check
pnpm typecheck
pnpm build
pnpm check
```

Manual Level 1 acceptance must verify:

1. The current worm camp still refills normally.
2. Fatty One Eye spawns only in its separate authored camp.
3. Only a Wooden or Stone Spear piercing the eye causes damage.
4. The three hops, shadow, marker, one-second flight, landing crack, landing
   area, and recovery are readable at default and overview zoom.
5. Saving/loading or dying mid-fight restarts a full-health fight.
6. Defeat unlocks the chest and starts the three-minute real-world timer.
7. Partial chest looting persists; a later boss spawn relocks the non-empty
   chest; another defeat exposes the exact remainder.
8. The final green-key transfer leaves the chest permanently open and empty.
9. The east exit consumes the key once, transitions to Gloop Forest, and stays
   unlocked after reload and the return trip.
10. No debug grant or automatic production gear is required.

## Checklist reconciliation

Rewrite Section E of
`docs/task/ideas/open/level-1-milestone-2-verification-checklist.md` so it no
longer claims that the ordinary Level 1 camp is `clear-once`. Its acceptance
rows must instead cover the separate respawning boss camp, transient fight
reset, timed exit/re-entry respawn, guarded reusable chest, partial persistent
contents, one-time green key, permanent gate unlock, transition, and return
state. Section H's focused encounter tests and Section I's fresh-run loop remain
required, with terminology updated from ordinary camp completion to boss
defeat/chest availability.
