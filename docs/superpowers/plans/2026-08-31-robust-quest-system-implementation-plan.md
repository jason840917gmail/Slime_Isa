# Robust Quest System Implementation Plan

## Status

Implemented on 2026-08-31. This plan expands the current single automatically
active quest into a validated, event-driven quest platform with explicit
lifecycle states, sequential hidden stages, NPC offers, automatic assignment,
data-driven objective matching, reliable rewards, persistence migration, and
focused automated evidence.

The implementation is now landed in the working tree. The dependency tree was
restored from the lockfile and the focused quest tests, persistence tests,
content checks, typecheck, and production build all pass.

## Player outcome

The player can:

- discover quests through NPC interactions and prerequisite conditions;
- read an NPC quest description and accept or decline the offer;
- receive automatic quests immediately, with a visible notification;
- inspect available, active, completed, failed, and abandoned quests in the
  quest journal;
- progress only the current stage while future stages remain hidden;
- return to an NPC when a quest requires turn-in;
- abandon optional quests and later make them available again;
- never abandon mandatory quests;
- retry failed quests only when the quest definition permits it; and
- save and restore the exact quest lifecycle, stage, progress, and reward state.

The complete proof is:

`unlock -> offer/assign -> accept -> progress stages -> turn in/complete -> save -> reload`

## Current baseline

| Area | Current state | Required change |
|---|---|---|
| Definitions | One TypeScript `QUEST_DEFS` array in `src/game/quests/Quest.ts` | Move immutable definitions into a validated content-owned catalog |
| Lifecycle | `active` and `completed` only; every definition starts active | Add explicit transition rules for all six requested statuses |
| Stages | One flat objective array | Add sequential stages; process and reveal only the current stage |
| Matching | Collection uses one pure helper; kill and area matching live in tracker loops | Register pure matchers by objective kind and authoritative event type |
| Acquisition | No offers; starter quest is inserted automatically | Add NPC offers and prerequisite-driven automatic assignment |
| NPCs | `Friend` wanders but has no stable quest identity or interaction API | Add authored quest NPC identity and a scene-owned interaction controller |
| Completion | Final objective always completes and immediately rewards | Support automatic completion and NPC turn-in per definition |
| Journal | Active/completed lists only | Present lifecycle sections and hide future stages |
| Persistence | Saves current flat progress under schema version 7 | Bump schema and migrate/reconcile old quest states safely |
| Tests | Two matcher/tracker tests; current local command cannot load AJV runtime | Repair dependencies and add lifecycle, matcher, integration, and migration coverage |

## Decisions and invariants

- Keep the existing event-driven architecture. Gameplay systems verify actions
  and publish authoritative domain events; the quest system never infers
  gameplay by polling scenes, physics objects, inventory, or keyboard input.
- Keep quest definitions in TypeScript content for this slice. Discriminated
  unions, catalog validation, and repository checks provide a well-defined
  store without introducing a second JSON schema/editor workflow.
- The quest service is the only writer of quest state. UI, NPC controllers,
  event producers, and save code call commands or queries; none mutate state.
- Quest definitions are immutable. Saves contain progress and lifecycle only,
  never copied titles, descriptions, filters, stages, or reward definitions.
- Stable quest, stage, and objective IDs are persistence contracts. Objective
  IDs are unique within a quest. Renaming one requires an explicit migration.
- A quest has sequential stages. Objectives within the current stage may
  progress in parallel. Future stages are hidden and ignore all events.
- Stages sequence work inside one quest. Separate quests are never grouped in a
  persisted sequence object; they form a derived quest chain only when one
  quest declares another quest's status as a prerequisite.
- `kill-spider` is authored as `kind: 'kill'` with an `enemyKinds` filter. New
  objective kinds represent different authoritative facts, not each content
  variation.
- Automatic acquisition changes `locked -> active`, emits a new-quest
  notification, and begins tracking immediately. It does not require player
  confirmation.
- NPC acquisition changes `locked -> available` when prerequisites are met.
  Interaction displays description and rewards; Accept changes it to `active`,
  while Decline leaves it `available`.
- Mandatory quests reject abandonment. Optional quests may change
  `active -> abandoned`; a retryable abandoned quest becomes `available` again
  through its giver when NPC-acquired. An abandoned automatic quest returns to
  `locked` through an explicit retry command and is activated again only when
  its prerequisites are evaluated as satisfied.
- Failure behavior is definition-owned. A failed quest may be permanent,
  retry the current stage, or reset the whole quest when retried.
- Completion behavior is definition-owned. Automatic quests may complete on
  their final objective. Turn-in quests remain `active` with derived
  `readyToTurnIn = true` until an allowed NPC interaction completes them.
- Rewards are granted only during the accepted transition to `completed`.
  Persist `rewardsGranted` as a defensive invariant and reject any attempt to
  grant them again. The flag protects migration, corrupted/repaired state, and
  future command replay even though normal transition guards already prevent a
  second `active -> completed` transition.
- The quest service does not implement escort movement, boss combat, timed
  encounters, crafting, or object activation. Each owning gameplay feature
  publishes its verified result; the corresponding matcher consumes it.
- `WorldScene` remains a composition root. It creates controllers and routes
  dependencies but contains no quest lifecycle, matching, or NPC offer logic.

## Stages versus quest chains

These are two different concepts:

- **Stage sequence inside one quest:** a quest contains ordered stages. Every
  objective in the current stage may progress in parallel. The next stage is
  hidden and cannot progress until every objective in the current stage is
  complete. An authored objective that must happen by itself is represented as
  a stage containing only that objective.
- **Quest chain across separate quests:** a later quest declares a
  `quest-status` prerequisite requiring an earlier quest to be `completed`.
  When all prerequisites become true, an automatic quest becomes `active` and
  an NPC-acquired quest becomes `available`.

There is no `QuestSequence` definition, sequence controller, sequence status,
or persisted chain state. Quest-chain behavior is derived entirely from quest
statuses and prerequisites. This keeps each quest independently queryable,
migratable, and retryable without duplicating lifecycle state.

## Lifecycle model

```ts
export type QuestStatus =
  | 'locked'
  | 'available'
  | 'active'
  | 'completed'
  | 'failed'
  | 'abandoned';
```

### Status meanings

| Status | Meaning | Processes objective events? |
|---|---|---|
| `locked` | One or more prerequisites are not satisfied | No |
| `available` | NPC quest can be inspected and accepted | No |
| `active` | Assigned quest is tracking its current stage | Yes, unless ready for turn-in |
| `completed` | Final completion accepted and rewards settled | No |
| `failed` | Authored failure fact occurred | No |
| `abandoned` | Player abandoned an optional quest | No |

### Allowed transitions

| Command/fact | From | To | Guard/effect |
|---|---|---|---|
| NPC prerequisites satisfied | `locked` | `available` | All prerequisites satisfied; acquisition kind must be `npc` |
| Automatic prerequisites satisfied | `locked` | `active` | All prerequisites satisfied; initialize first stage and notify |
| Accept NPC offer | `available` | `active` | Initialize first stage and timestamps |
| Decline NPC offer | `available` | `available` | No mutation |
| Complete non-final stage | `active` | `active` | Advance stage and initialize its progress |
| Complete final automatic stage | `active` | `completed` | Grant rewards once |
| Finish final turn-in stage | `active` | `active` | Derive `readyToTurnIn` |
| Turn in to allowed NPC | `active` | `completed` | Require ready state; grant rewards once |
| Failure event | `active` | `failed` | Record failure and retry policy |
| Retry failed quest | `failed` | `active` | Apply definition reset policy |
| Abandon optional quest | `active` | `abandoned` | `QuestService.abandon()` rejects mandatory quests without mutation |
| Re-offer abandoned NPC quest | `abandoned` | `available` | NPC-acquired quest must permit retry |
| Retry abandoned automatic quest | `abandoned` | `locked` | Re-evaluate prerequisites before activation |

All unlisted transitions return a typed rejection and leave state unchanged.
Repeated commands are idempotent where practical: accepting an already active
quest, completing an already completed quest, or turning in twice cannot repeat
events or rewards.

## Content model

Create `src/game/content/quests/` as the definition owner:

```text
src/game/content/quests/
  types.ts
  QuestCatalog.ts
  quests/
    firstSteps.ts
    spiderTrouble.ts
  validateQuestCatalog.ts
```

Use definitions equivalent to:

```ts
export interface QuestDefinition {
  readonly id: QuestId;
  readonly definitionVersion: number;
  readonly title: string;
  readonly description: string;
  readonly category: 'mandatory' | 'optional';
  readonly prerequisites: readonly QuestConditionDefinition[];
  readonly acquisition: QuestAcquisitionDefinition;
  readonly stages: readonly QuestStageDefinition[];
  readonly completion: QuestCompletionDefinition;
  readonly failurePolicy: QuestFailurePolicy;
  readonly rewards: QuestRewards;
}

export interface QuestStageDefinition {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly objectives: readonly QuestObjectiveDefinition[];
}

export type QuestAcquisitionDefinition =
  | { readonly kind: 'npc'; readonly npcIds: readonly string[] }
  | { readonly kind: 'automatic' };

export type QuestCompletionDefinition =
  | { readonly kind: 'automatic' }
  | { readonly kind: 'npc-turn-in'; readonly npcIds: readonly string[] };

export type QuestFailurePolicy =
  | { readonly kind: 'permanent' }
  | { readonly kind: 'retryable'; readonly reset: 'quest' | 'current-stage' };
```

`definitionVersion` is per quest, not global. Editing one quest does not force
unrelated quest migrations. A quest increments its version only when its saved
state can no longer be interpreted identically, such as a stage/objective
rename, removal, insertion into an already reachable stage, or reset-policy
change.

Catalog validation must reject:

- duplicate or malformed quest IDs;
- empty titles, stages, objectives, or NPC acquisition sources;
- duplicate stage IDs or objective IDs;
- non-positive or non-integer targets;
- objective filters with no values;
- NPC acquisition/turn-in IDs absent from the NPC catalog;
- item, recipe, enemy, boss, area, object, encounter, or character IDs absent
  from the appropriate catalog when that catalog exists;
- mandatory quests configured to allow abandonment;
- retry settings incompatible with permanent failure; and
- prerequisite dependency cycles or references to unknown quests.

Add `scripts/check-quests.mjs` and `pnpm quests:check`, then include it in
`pnpm check`. Runtime catalog construction must also fail loudly during startup
if invalid content bypasses the repository check.

## Runtime state and queries

Replace flat `QuestState` with:

```ts
export interface QuestState {
  readonly questId: QuestId;
  readonly definitionVersion: number;
  readonly status: QuestStatus;
  readonly activeStageId: string | null;
  readonly progress: Readonly<Record<string, number>>;
  readonly acceptedAt?: number;
  readonly completedAt?: number;
  readonly failedAt?: number;
  readonly abandonedAt?: number;
  readonly rewardsGranted: boolean;
}
```

Keep mutable records private inside `QuestService`. Return cloned readonly
snapshots from queries:

```ts
interface QuestQueries {
  get(questId: QuestId): QuestView | undefined;
  list(status?: QuestStatus): readonly QuestView[];
  offersForNpc(npcId: string): readonly QuestOfferView[];
  turnInsForNpc(npcId: string): readonly QuestView[];
  isReadyToTurnIn(questId: QuestId): boolean;
}
```

`QuestView` combines definition presentation with a state snapshot and exposes
only completed stages plus the current stage. It must never expose future stage
titles, descriptions, objectives, or progress to the journal.
`readyToTurnIn` is a computed `QuestView` property and is true only when the
completion kind is `npc-turn-in`, the current stage is final, and every final
objective has reached its target. It is never persisted.

## Data-driven objective matching

### Objective union

Support this initial definition union:

```ts
export type QuestObjectiveDefinition =
  | CollectObjective
  | KillObjective
  | TalkToNpcObjective
  | CraftItemObjective
  | EscortCharacterObjective
  | DefeatBossObjective
  | ActivateObjectObjective
  | SurviveDurationObjective
  | DiscoverAreaObjective;
```

Common fields are `id`, `kind`, `label`, and `target`. Kind-specific filters:

| Kind | Authoritative event | Filters/value |
|---|---|---|
| `collect` | `collectible.collected` | `itemIds`; progress by transferred quantity |
| `kill` | `enemy.died` | optional `enemyKinds`, `areaIds`, `enemyTags`; progress by one |
| `talk-to-npc` | `npc.talked` | `npcIds`; progress by one conversation completion |
| `craft-item` | `craft.completed` | optional `recipeIds`, required `itemIds`; progress by output quantity |
| `escort-character` | `escort.completed` | `escortIds` or `characterIds`, optional destination IDs |
| `defeat-boss` | `boss.defeated` | `bossIds`; progress by one unique boss defeat |
| `activate-object` | `object.activated` | `objectIds` or stable instance IDs, optional area IDs |
| `survive-duration` | `survival.completed` | encounter IDs and required verified duration |
| `discover-area` | `area.enter` | `areaIds`; progress by one unique matching area |

Do not let `survive-duration` start timers in the quest service. A survival or
encounter controller measures simulation time, handles pause/death rules, and
publishes `survival.completed` only after verification.

### Matcher contract

Create pure matchers under `src/game/quests/matchers/`:

```ts
interface ObjectiveMatcher<TKind extends QuestObjectiveKind, TEvent extends QuestInputEventName> {
  readonly kind: TKind;
  readonly event: TEvent;
  match(
    objective: ObjectiveByKind<TKind>,
    payload: QuestInputEvents[TEvent],
    context: ObjectiveMatchContext,
  ): ObjectiveMatchResult;
}

type ObjectiveMatchResult =
  | { readonly matched: false }
  | { readonly matched: true; readonly amount: number; readonly factId?: string };
```

`QuestObjectiveRegistry` validates one matcher per objective kind and indexes
matchers by event name. Adding a new kind therefore requires its definition,
event contract, matcher, catalog validation, and tests, but no edit to the
quest service's event-processing loop.

One application/run-owned `QuestEventBridge` subscribes the registry to the
global event bus. There are no listeners per quest or objective. `start()` is
idempotent, `dispose()` removes every subscription, and a later `start()` may
subscribe once again. Map-scene transitions do not create duplicate listeners;
the bootstrap/run owner installs the bridge, while `WorldScene` only receives
quest commands and readonly queries. Completing or abandoning a quest requires
no subscription changes because the service filters by status and current
stage.

Use `factId` for objectives that count unique world facts, such as a boss ID,
area ID, object instance, or escort run. Persist consumed fact IDs only where
repeat delivery or revisiting would otherwise inflate progress. Quantity events
such as collection and crafting use the owning system's accepted quantity.

Implementation readiness is explicit:

- playable producers in this plan: collect, filtered kill, talk-to-NPC,
  craft-item, and discover-area;
- contract-ready matchers in this plan: escort-character, defeat-boss,
  activate-object, and survive-duration.

Contract-ready kinds receive complete types, pure matchers, validation, and
synthetic event tests, but no production quest may use one until its owning
gameplay controller publishes the authoritative event. Catalog validation must
reject a production definition that enables a kind whose producer capability
is not registered.

## Automatic acquisition and prerequisites

Prerequisite conditions are separate from objective matchers. Objective
matchers advance active quests; condition evaluators determine whether a locked
quest is eligible for acquisition. All prerequisites use AND semantics in this
version. A quest with no prerequisites is immediately eligible.

Acquisition describes what happens after eligibility; it does not contain a
second set of trigger conditions. An eligible automatic quest changes directly
from `locked` to `active`. An eligible NPC-acquired quest changes from `locked`
to `available` and still requires explicit acceptance through an allowed NPC.

Initial prerequisite condition kinds:

- `quest-status`: another quest reached a specified status;
- `area-entered`: player entered or previously discovered an area;
- `player-level`: verified level is at least a threshold;
- `inventory-count`: authoritative inventory count meets a threshold;
- `world-flag`: boss, dungeon, encounter, gate, or stable object fact exists;
- `npc-talked`: a conversation with a stable NPC completed.

Authoritative events are reevaluation signals, not separate acquisition
triggers. Evaluate only the relevant locked quests when an event changes a fact
used by their prerequisites, and evaluate all locked quests once after the
complete run has loaded. Conditions inspect injected readonly query ports for
facts that may already be true. Automatic quests activate immediately and
notify; NPC quests become available and notify only when first unlocked.

## NPC and interaction design

### Authored NPC identity

Do not use array positions or random `Friend` ordering as quest identities.
Add content-owned NPC definitions with stable IDs, display names, visual
references, offer text, and optional quest associations. Map instances retain
their stable `instanceId` and refer to an NPC definition ID.

Store NPC definitions under `src/game/content/npcs/`; quest definitions refer
to their stable IDs but do not own NPC visuals or general dialogue text. Add an
`npc` capability to object archetype content that points to an NPC definition.
The object catalog validator checks that reference, and map validation continues
to validate the object/visual pair and stable map instance ID.

Add an NPC capability to the object catalog/map validation path rather than
encoding behavior in object-ID prefixes. `MapBuilder` reports validated NPC
registrations to a `QuestNpcController`, analogous to collectible registration.
The first version may use a stationary authored visual; wandering behavior is
not required for a functional offer flow.

Construction order is fixed: `WorldScene` creates the interaction router and
quest NPC controller before calling `MapBuilder.build()`; the builder's
`onObjectCreated` callback forwards each validated NPC registration to the
controller; after build, the controller finalizes proximity bodies and registers
one provider with the router. It never rescans scene children or infers identity
from placement order.

### Interaction routing

Introduce a small `InteractionRouter` so `WorldScene` does not grow an ordered
chain of feature-specific `F` checks. Providers expose their nearest valid
candidate, prompt, priority, and execute callback. Houses and quest NPCs
register providers; the router renders one prompt and lets exactly one provider
consume each interaction press.

The router owns intentional `F` interactions only. Loose collectibles remain
walk-over pickups, never register with the router, and continue to show no `F`
prompt. Adapting houses and adding NPCs must not change collectible behavior.

`QuestNpcController` owns proximity and interaction behavior:

1. prefer a ready turn-in;
2. otherwise prefer an available quest offer;
3. otherwise show short non-quest text;
4. emit `npc.talked` only when the interaction/conversation finishes, not when
   the player merely enters proximity.

### Quest offer modal

Create a ModalStack-owned `QuestOfferModal` showing NPC name, quest title,
description, visible first-stage objective summary, and rewards. It provides
Accept and Decline commands and restores simulation/focus on close.

Accept calls `QuestService.accept(questId, npcId)`. Decline performs no state
transition. Turn-in uses a confirmation/summary view, calls
`QuestService.turnIn(questId, npcId)`, and displays granted rewards.

## Quest events and notifications

Replace the broad `quest.changed` payload as the primary domain contract with
typed lifecycle events while retaining a presentation invalidation event if it
keeps the journal simple:

```ts
'quest.available': { questId: string; source: 'npc' | 'condition' };
'quest.accepted': { questId: string; source: 'npc' | 'automatic' };
'quest.progressed': { questId: string; stageId: string; objectiveId: string; before: number; after: number };
'quest.stage-completed': { questId: string; stageId: string };
'quest.completed': { questId: string; title: string; rewards: QuestRewards };
'quest.failed': { questId: string; reason: string };
'quest.abandoned': { questId: string };
'quest.changed': { questId: string };
```

Create a quest notification presenter that subscribes to accepted, stage,
completed, failed, and available events. It must not grant rewards or alter
quest state. Reuse a general toast implementation if one exists by implementation
time; otherwise keep the first presenter quest-specific and scene-owned with
explicit cleanup.

## Persistence and migration

Increase `SAVE_SCHEMA_VERSION` from 7 to 8 and extend both repository guards and
focused persistence tests.

### Version 7 migration

For each old state:

- rename `id` to `questId`;
- map `active` and `completed` directly;
- set `activeStageId` to the first incomplete stage, or final stage for a
  completed quest;
- retain recognized objective progress and clamp it to authored targets;
- initialize newly introduced objectives in reached/current stages to zero;
- discard objective IDs no longer present in the definition;
- set `rewardsGranted: true` for old completed quests so migration never pays
  rewards again;
- set `definitionVersion` to the reconciled catalog version; and
- fail the load with a useful validation issue when reconciliation cannot
  preserve meaning safely.

For catalog quests absent from an old save, derive initial `locked`, `available`,
or automatic `active` state through acquisition rules. Unknown saved quest IDs
must be preserved in a quarantined migration diagnostic or rejected; they must
not silently become another quest.

### Definition evolution

Add a `QuestStateReconciler` keyed by `(questId, savedDefinitionVersion)`. Simple
add/remove/clamp changes may use a shared reconciler; renamed stages/objectives
require an explicit mapping. Never infer renames from labels or array positions.

Register migrations explicitly in
`src/game/infrastructure/persistence/quests/QuestReconciliationRegistry.ts` as
ordered `(questId, fromVersion, toVersion)` entries. Each entry names its
reconciler and explains the authored ID change it preserves. Loading walks a
contiguous chain to the catalog's per-quest version; a missing or ambiguous step
rejects the load with a diagnostic instead of guessing.

`QuestService.load()` validates and installs all reconciled state atomically.
If any state is invalid, leave the currently installed run unchanged.

## Journal changes

Update the journal to query `QuestView` values rather than definition and state
singletons separately. Provide sections or tabs for:

- Available;
- Active;
- Completed; and
- Failed/Abandoned history.

For an active quest show completed stages in compact form and the current stage
in full. Never render future-stage metadata. Mark turn-in quests with an
actionable `Return to <NPC>` message. Optional active quests may expose an
Abandon command with confirmation; mandatory quests do not render that action.

Available NPC quests may identify their giver and location but are accepted
only through NPC interaction in this first version. Abandoned retryable quests
direct the player back to the giver.

## First playable quest content

Migrate `first-steps` without losing existing intent, but stop automatically
activating every catalog entry. Split it into sequential stages, for example:

1. collect three meadow snacks;
2. defeat three nearby enemies;
3. discover Gloop Forest;
4. return to Village Elder Plop for completion.

Add one optional NPC quest proving filtered objectives and retry behavior:

1. accept `Spider Trouble` from an authored Level 1 NPC;
2. enter Gloop Forest;
3. defeat a configured number of `slime-spider` enemies;
4. return to the giver for rewards.

At least one additional small automatic quest should prove condition-based
assignment and notification without acceptance. Its objectives must use
existing executable gameplay events so the first release is playable end to
end.

Do not claim playable escort, boss, activation, or survival content until their
owning gameplay controllers publish the required authoritative events. Their
quest definitions, matchers, catalog validation, and synthetic contract tests
may land now so future producers integrate without changing quest lifecycle.

## Implementation sequence

### Q0. Restore the verification baseline

1. Run `pnpm install --frozen-lockfile` to restore the dependency tree declared
   by `pnpm-lock.yaml`; do not work around AJV with an undeclared deep import.
2. Run `pnpm test:quests`, `pnpm test:collectibles`, and `pnpm typecheck`.
3. Record pre-existing failures separately. Do not change checklist evidence
   until the named commands execute successfully.

### Q1. Introduce content types and validation

1. Add the content-owned quest types, catalog, and validator.
2. Move `first-steps` from `src/game/quests/Quest.ts` into the catalog while
   preserving its stable quest and objective IDs where possible.
3. Add sequential stages, acquisition/completion/failure policies, and catalog
   cross-reference checks.
4. Add `quests:check` and focused validator tests for valid content, duplicate
   IDs, unknown references, invalid targets, and dependency cycles.

Focused validation: `pnpm quests:check` and the quest catalog tests.

### Q2. Replace the tracker with a lifecycle service

1. Add `QuestService` with injected catalog, clock, reward port, event port, and
   readonly world/player query ports.
2. Implement initial state derivation, command guards, the transition table,
   sequential stage advancement, turn-in readiness, and exactly-once rewards.
  Enforce mandatory abandonment in `QuestService.abandon()` even though the
  journal also hides the command.
3. Keep a compatibility export only while call sites move; remove the mutable
   singleton API after all consumers use commands and readonly queries.
4. Add state-machine table tests covering every accepted and rejected
   transition, repeated commands, mandatory abandonment, and failure retry
   reset behavior.

Focused validation: quest lifecycle tests and `pnpm typecheck`.

### Q3. Add the matcher and prerequisite-condition registries

1. Define typed quest input events and add the missing authoritative event
   contracts to `EventBus.ts`.
2. Implement one pure matcher per objective kind and registry completeness
   validation.
3. Route events to only matching active current-stage objectives.
4. Implement prerequisite-condition evaluators separately from objective
   matching. Index conditions by the authoritative events that can change their
   result so those events reevaluate only relevant locked quests.
5. Add matcher tests for positive matches, every filter, invalid quantities,
   unique facts, unrelated events, hidden future stages, and capped progress.

Focused validation: matcher/prerequisite-condition tests and `pnpm typecheck`.

### Q4. Connect current authoritative producers

1. Keep collection advancement on the existing exact transferred-quantity
   event.
2. Extend enemy-death payloads only as required for stable kind/tag/area
   filters; do not inspect enemy sprites from quests.
3. Publish `craft.completed` from the crafting domain after inventory
   consumption and output insertion both succeed, not from `CraftingUI`.
4. Continue using verified `area.enter` navigation events.
5. Add producer contract tests proving rejected gameplay actions emit nothing
   and successful actions emit once with accepted values.

Focused validation: quest, collectible, crafting, combat/enemy, and navigation
tests for the touched producers.

### Q5. Add authored quest NPCs and interaction routing

1. Add stable NPC content and object/map capability validation.
2. Author Village Elder Plop and the optional quest giver into the appropriate
   production maps with stable instance IDs.
3. Create the router/controller before map build, forward validated NPC
  registrations through `onObjectCreated`, then finalize interaction providers.
4. Add `InteractionRouter` and adapt house interaction without changing house
   behavior.
5. Add `QuestNpcController` and `QuestOfferModal` with Accept/Decline/Turn-in.
6. Emit `npc.talked` only after completed interaction and clean up all input,
   event, modal, and proximity resources on scene shutdown.
7. Add controller tests for proximity, candidate priority, offer ordering,
   decline, acceptance, turn-in, repeated input, and disposal.

Focused validation: NPC/interaction/UI tests, `pnpm maps:check`, and
`pnpm typecheck`.

### Q6. Persist and migrate lifecycle state

1. Update save schema guards and bump schema version to 8.
2. Implement version-7 quest migration and definition reconciliation.
3. Make `SaveSystem` capture/install use immutable service snapshots.
4. Add round-trip tests for every status, mid-stage progress, ready-to-turn-in,
   failed retry policy, abandonment, automatic quests, and rewarded completion.
5. Prove migrated completed quests never receive rewards again.

Focused validation: `pnpm test:persistence` and quest migration tests.

### Q7. Upgrade journal and notifications

1. Render all lifecycle sections from `QuestView` queries.
2. Hide every future-stage field and ignore future-stage progress.
3. Add new-quest, stage-complete, ready-to-turn-in, completion, failure, and
   abandonment notifications.
4. Add optional abandonment confirmation and mandatory-quest protection.
5. Verify ModalStack ordering, Escape behavior, pause restoration, keyboard
   focus, and listener cleanup.

Focused validation: quest UI tests, `pnpm test:ui`, and `pnpm typecheck`.

### Q8. Prove checklist line 77 and complete acceptance

1. Replace or extend the current isolated quest test with a combined test using
   the real `CollectibleEventChannel`, collectible publisher/controller, and
   quest service.
2. Start the quest service twice and prove only one subscription exists.
3. Collect one matching pile and assert one exact progress delta equal to the
   quantity actually transferred.
4. Attempt to collect the depleted pile again and assert no event and no quest
   progress.
5. Collect a nonmatching item and assert no objective progress.
6. Fill inventory, attempt collection, and assert no transfer, event, or quest
   progress; free capacity and assert only the accepted remainder advances.
7. Dispose/recreate the scene-owned integration and prove old listeners no
   longer react.
8. Save/reload after partial collection and quest progress, then prove the
   remaining world quantity and quest progress continue exactly once.
9. Run the complete command matrix below before retaining line 77 as checked.

## Test matrix

| Test area | Required evidence |
|---|---|
| Catalog | IDs, references, cycles, targets, policy combinations, matcher completeness |
| Lifecycle | Every allowed/rejected transition and idempotent repeated command |
| Stages | Parallel current objectives, sequential advancement, hidden future stages |
| Matchers | Every kind, every filter, unrelated event rejection, exact quantities |
| Acquisition | NPC availability, decline, accept, automatic assignment and notification |
| Completion | Automatic and NPC turn-in, invalid giver rejection, rewards exactly once |
| Failure | Permanent and retryable policies, stage/quest reset behavior |
| Abandonment | Optional abandon/re-offer; mandatory rejection |
| Persistence | Version-7 migration, schema-8 round trip, definition reconciliation |
| Interaction | One `F` consumer, prompt priority, modal cleanup, `npc.talked` timing |
| Collection check | Exact-once publication through real channel into quest progress |

## Verification commands

Run focused commands after each phase, then finish with:

```text
pnpm quests:check
pnpm maps:check
pnpm test:quests
pnpm test:collectibles
pnpm test:persistence
pnpm test:ui
pnpm typecheck
pnpm build
pnpm check
```

Manual acceptance remains necessary for Phaser presentation and interaction:

1. Approach an authored quest NPC and confirm only one `F` prompt appears.
2. Decline an offer and confirm it remains available without progress.
3. Accept it and confirm only the first stage is visible.
4. Perform a future-stage action early and confirm it does not count.
5. Complete each stage and confirm the next stage appears only afterward.
6. Trigger an automatic quest and confirm immediate activation plus notification.
7. Attempt to abandon a mandatory quest and confirm rejection.
8. Abandon and re-offer an optional quest and confirm its authored reset policy.
9. Complete automatic and NPC-turn-in quests and confirm rewards once each.
10. Save/reload at available, active, mid-stage, ready-to-turn-in, failed,
    abandoned, and completed states and confirm exact restoration.

## Acceptance criteria

- All six requested statuses have documented meanings, guarded transitions,
  query support, journal presentation, persistence, and tests.
- Quest definitions come from one validated catalog with stable IDs and no
  runtime copies of authored presentation or rules.
- NPC quests require interaction and explicit Accept; Decline is nonmutating.
- Automatic quests activate immediately, notify the player, and require no
  confirmation.
- Only current-stage objectives progress or display; future stages remain hidden.
- Objective dispatch is registry-driven and supports collect, filtered kill,
  talk-to-NPC, craft-item, escort-character, defeat-boss, activate-object,
  survive-duration, and discover-area contracts. Production content uses only
  kinds whose authoritative producer capability is registered.
- Existing gameplay producers publish one authoritative accepted fact; quests
  do not poll or duplicate domain validation.
- Mandatory quests cannot be abandoned; optional quests can be abandoned and
  made available again; failed retries follow per-definition policy.
- Automatic and NPC-turn-in completion grant rewards exactly once across
  repeated events, repeated commands, and save/load.
- Version-7 saves migrate deterministically without replaying rewards or
  silently assigning progress to renamed content.
- `pnpm test:quests` and the combined collectible-to-quest integration test pass
  before checklist line 77 is retained as verified automated evidence.

## Explicit non-goals

- A general branching dialogue-tree engine.
- A visual quest-authoring editor.
- Procedural quest generation.
- Network synchronization or multiplayer quest ownership.
- Implementing escort AI, bosses, survival encounters, or generic object
  activation inside the quest feature.
- Revealing future stage content in the journal.
