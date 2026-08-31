# Quest Authoring Guide

This guide explains how to create, connect, validate, and safely evolve quests in Slime Isa. It covers every objective currently supported by the quest engine and the steps required to add an entirely new objective type.

## The quest model

A quest is one journal entry with one lifecycle, one reward package, and one or more sequential stages.

- Stages run sequentially in their array order.
- All objectives inside the active stage progress in parallel.
- Every objective in the active stage must reach its target before the next stage starts.
- Objectives in later stages do not listen to gameplay events until their stage becomes active.
- Completing the last stage either completes the quest automatically or makes it ready for an NPC turn-in.

Use stages when several steps belong to the same quest:

```text
Quest: Prepare for the expedition
  Stage 1: collect berries AND wood
  Stage 2: defeat spiders
  Stage 3: report to the elder
  Reward: granted once after the entire quest
```

Use separate quests when each part should have its own journal entry, acceptance, completion, or rewards. Chain them with a `quest-status` prerequisite:

```ts
prerequisites: [
  { kind: 'quest-status', questId: 'previous-quest', status: 'completed' },
],
```

There is no separate quest-sequence entity. If the chained quest uses automatic acquisition, it starts immediately when the previous quest completes. If it uses NPC acquisition, it becomes available from its configured NPC.

## Where quest content lives

| Purpose | Location |
| --- | --- |
| Quest and objective types | `src/game/content/quests/types.ts` |
| Individual quest definitions | `src/game/content/quests/quests/` |
| Registered quest list | `src/game/content/quests/QuestCatalog.ts` |
| Catalog validation | `src/game/content/quests/validateQuestCatalog.ts` |
| Objective event matching | `src/game/quests/matchers/ObjectiveMatchers.ts` |
| Event subscriptions | `src/game/quests/QuestEventBridge.ts` |
| Runtime lifecycle | `src/game/quests/QuestService.ts` |
| Save reconciliation | `src/game/infrastructure/persistence/quests/QuestReconciliationRegistry.ts` |
| NPC identities | `src/game/content/npcs/NpcCatalog.ts` |
| NPC object archetypes | `src/game/content/objects/npcs/` |
| Authored maps | `src/game/content/maps/` |

The production catalog intentionally starts empty. Add each authored quest as a
new definition and use the synthetic quest-service tests for lifecycle examples.

## Quick-start workflow

For a quest made entirely from existing objective types:

1. Decide whether the actions are parallel objectives, sequential stages, or separate chained quests.
2. Confirm every referenced item, recipe, NPC, area, enemy, object, boss, or encounter ID.
3. Copy the template below into a new file under `src/game/content/quests/quests/`.
4. Configure acquisition, stages, completion, policies, and rewards.
5. Import the definition and add it to `QUEST_DEFINITIONS` in `QuestCatalog.ts`.
6. If it uses a new NPC, create and place that NPC as described below.
7. Confirm the owning gameplay feature emits the objective's authoritative event.
8. Run the validation checklist at the end of this guide.
9. Play through every route: acceptance, each stage transition, turn-in, reward, save/load, and any retry or abandonment path.

## Copy-ready quest template

Create `src/game/content/quests/quests/myQuest.ts`:

```ts
import type { QuestDefinition } from '../types';

export const myQuest: QuestDefinition = {
  // Stable, globally unique, kebab-case ID. Never reuse an old ID.
  id: 'my-quest',
  definitionVersion: 1,

  title: 'My Quest',
  description: 'Explain the overall goal to the player.',
  category: 'optional',

  // Every prerequisite must pass. An empty array means no prerequisite.
  prerequisites: [],

  // Use automatic, or use npc with one or more valid NPC IDs.
  acquisition: { kind: 'automatic' },

  stages: [
    {
      id: 'first-step',
      title: 'First step',
      description: 'Explain what the player should do now.',
      objectives: [
        {
          id: 'collect-berries',
          kind: 'collect',
          label: 'Collect purple berries',
          target: 3,
          itemIds: ['purple-berry-mat'],
        },
      ],
    },
  ],

  // Use automatic, or npc-turn-in with one or more valid NPC IDs.
  completion: { kind: 'automatic' },

  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: { kind: 'retryable', reset: 'quest' },

  rewards: {
    coins: 25,
    xp: 30,
    items: [{ itemId: 'hp-potion', count: 1 }],
  },
};
```

Register it in `src/game/content/quests/QuestCatalog.ts`:

```ts
import { myQuest } from './quests/myQuest';

export const QUEST_DEFINITIONS: readonly QuestDefinition[] = [
  myQuest,
];
```

Catalog validation runs as soon as the catalog loads. `pnpm quests:check` gives the shortest feedback loop.

## Definition fields

### Identity and text

- `id`: stable, globally unique, kebab-case quest ID.
- `definitionVersion`: positive integer used to reconcile old saves after structural changes.
- `title`: journal and notification title.
- `description`: overall quest description.
- `category`: `mandatory` or `optional`.

Stage and objective IDs must also be kebab-case. Stage IDs must be unique within the quest. Objective IDs must be unique across the entire quest, including different stages, because progress is stored by objective ID.

Treat all persisted IDs as permanent. Renaming a quest, stage, or objective ID can invalidate or lose saved progress unless a reconciliation migrates it.

### Acquisition

Automatic acquisition starts the quest as soon as all prerequisites pass:

```ts
acquisition: { kind: 'automatic' },
```

NPC acquisition makes the quest available from any listed NPC. The player must accept it:

```ts
acquisition: {
  kind: 'npc',
  npcIds: ['mossy-scout'],
},
```

With no prerequisites, an automatic quest starts when the quest service starts; an NPC quest becomes immediately available. With prerequisites, both remain locked until all conditions pass.

### Stages and objectives

Stages are always sequential. Objectives within one stage are parallel:

```ts
stages: [
  {
    id: 'prepare',
    title: 'Prepare',
    description: 'Gather both supplies.',
    objectives: [
      {
        id: 'collect-berries',
        kind: 'collect',
        label: 'Collect berries',
        target: 3,
        itemIds: ['purple-berry-mat'],
      },
      {
        id: 'collect-wood',
        kind: 'collect',
        label: 'Collect wood',
        target: 5,
        itemIds: ['wood'],
      },
    ],
  },
  {
    id: 'hunt',
    title: 'Clear the route',
    description: 'Defeat the spiders after preparing.',
    objectives: [
      {
        id: 'defeat-spiders',
        kind: 'kill',
        label: 'Defeat slime-spiders',
        target: 3,
        enemyKinds: ['slime-spider'],
      },
    ],
  },
],
```

An event that occurs before its stage becomes active is normally ignored. On initial quest activation only, the service can backfill already-known `discover-area`, `talk-to-npc`, and `defeat-boss` facts for the first active stage. It does not backfill collect, kill, craft, escort, activation, or survival progress, and it does not reapply known facts automatically when advancing to a later stage.

Design later stages around actions that have not happened yet or that the player can repeat. For example, do not put “discover the forest” after a stage that already requires the player to fight inside that forest.

### Completion

Automatic completion grants rewards immediately after the last stage finishes:

```ts
completion: { kind: 'automatic' },
```

An NPC turn-in keeps the quest active and marks it ready to turn in after the last stage finishes:

```ts
completion: {
  kind: 'npc-turn-in',
  npcIds: ['village-elder-plop'],
},
```

The completion NPC does not have to be the acquisition NPC. Every listed ID must exist in `NpcCatalog.ts` and have an NPC object placed in an accessible map if the player is expected to interact with it.

### Failure and abandonment

Failure behavior:

```ts
failurePolicy: { kind: 'permanent' },

// Or retry from the beginning:
failurePolicy: { kind: 'retryable', reset: 'quest' },

// Or retain completed stages and reset the failed stage:
failurePolicy: { kind: 'retryable', reset: 'current-stage' },
```

The owning gameplay feature must explicitly call `questService.fail(questId, reason)` when a failure condition occurs. Defining a failure policy does not create a timer, escort failure, or death rule by itself.

Abandonment behavior:

```ts
abandonmentPolicy: { kind: 'forbidden' },

// Or allow a later retry:
abandonmentPolicy: { kind: 'retryable', reset: 'quest' },
abandonmentPolicy: { kind: 'retryable', reset: 'current-stage' },
```

Mandatory quests must use `forbidden`; catalog validation rejects an abandonable mandatory quest. Optional NPC quests are re-offered by their acquisition NPC. Automatic abandoned quests use the automatic retry path.

### Rewards

All reward fields are optional and may be combined:

```ts
rewards: {
  coins: 100,
  xp: 75,
  items: [
    { itemId: 'hp-potion', count: 2 },
    { itemId: 'wooden-spear', count: 1 },
  ],
},
```

Coins and XP must be non-negative integers. Item counts must be positive integers, and item IDs must exist in the item catalog. The service persists `rewardsGranted` and guards completion so rewards are granted only once.

## Prerequisite recipes

Every entry in `prerequisites` must pass; the array uses AND logic. Within `areaIds` or `npcIds`, matching any listed ID is enough.

### Require another quest state

This is the normal way to create a quest chain:

```ts
prerequisites: [
  { kind: 'quest-status', questId: 'previous-quest', status: 'completed' },
],
```

The referenced quest must exist. Dependency cycles are rejected. Although all lifecycle statuses are valid, `completed` is the safest status for normal story chains.

### Require entering any listed area

```ts
prerequisites: [
  { kind: 'area-entered', areaIds: ['gloop-forest', 'crystal-caverns'] },
],
```

### Require a player level

```ts
prerequisites: [
  { kind: 'player-level', minimumLevel: 5 },
],
```

### Require inventory

```ts
prerequisites: [
  { kind: 'inventory-count', itemId: 'wood', minimumCount: 10 },
],
```

This checks the current inventory count. The item is not consumed by accepting the quest.

### Require a world flag

```ts
prerequisites: [
  { kind: 'world-flag', flagId: 'bridge-repaired' },
],
```

The feature that owns the flag must make it available to the quest service through restored facts or condition queries. Boss events automatically expose `boss:<bossId>` as an in-run world flag.

### Require talking to any listed NPC

```ts
prerequisites: [
  { kind: 'npc-talked', npcIds: ['village-elder-plop'] },
],
```

`area-entered` facts and defeated bosses are restored by the current save installation path. Generic world flags and talked-NPC facts are supported by the service but are not currently included in the normal saved world snapshot. If a quest depends on either across save/load, add persistence for that fact before shipping the quest.

### Combine conditions

This requires all three conditions:

```ts
prerequisites: [
  { kind: 'quest-status', questId: 'previous-quest', status: 'completed' },
  { kind: 'player-level', minimumLevel: 3 },
  { kind: 'inventory-count', itemId: 'wood', minimumCount: 5 },
],
```

Prerequisites are evaluated when the service starts, after relevant quest input events, when a quest completes, after save facts are restored, and when another system explicitly requests reevaluation. If a new condition can change without one of those signals, its owning feature must trigger `questTracker.evaluatePrerequisites()` or an appropriate quest input event.

## Objective reference

Objectives only count events while their quest is active and their stage is current. Progress is capped at `target`.

| Objective kind | Event | Amount per matching event | Duplicate protection |
| --- | --- | --- | --- |
| `collect` | `collectible.collected` | payload `quantity` | None; producer must emit once per collection |
| `kill` | `enemy.died` | 1 | None; producer must emit once per death |
| `talk-to-npc` | `npc.talked` | 1 | None; repeated conversations can count again |
| `craft-item` | `craft.completed` | payload `quantity` | None; producer must emit once per craft |
| `escort-character` | `escort.completed` | 1 | `runId`, falling back to `escortId` |
| `defeat-boss` | `boss.defeated` | 1 | `factId`, falling back to `bossId` |
| `activate-object` | `object.activated` | 1 | `instanceId` |
| `survive-duration` | `survival.completed` | 1 | `factId`, falling back to `encounterId` |
| `discover-area` | `area.enter` | 1 | `areaId` |

### Collect items

```ts
{
  id: 'collect-materials',
  kind: 'collect',
  label: 'Collect berries or silk',
  target: 5,
  itemIds: ['purple-berry-mat', 'silk-clump'],
}
```

Any listed item matches. The collected quantity is added; this objective does not check the player's current inventory and does not consume items. Item IDs are validated against `ItemCatalog.ts`.

### Kill enemies

```ts
{
  id: 'defeat-forest-spiders',
  kind: 'kill',
  label: 'Defeat forest slime-spiders',
  target: 3,
  enemyKinds: ['slime-spider'],
  areaIds: ['gloop-forest'],
  enemyTags: ['spider', 'corrupted'],
}
```

All configured filter groups must match:

- `enemyKinds`: the event's `kind` must be one of these IDs.
- `areaIds`: the event's `areaId` must be one of these IDs.
- `enemyTags`: the event must contain every configured tag.

Every filter is optional. With no filters, every enemy death counts. The current combat producer emits `enemyId`, `areaId`, and `kind`, but not tags, so a tag-filtered quest will not progress until combat emits `tags`.

### Talk to an NPC

```ts
{
  id: 'speak-to-elder',
  kind: 'talk-to-npc',
  label: 'Talk to Village Elder Plop',
  target: 1,
  npcIds: ['village-elder-plop'],
}
```

Any listed NPC matches. NPC IDs are validated against `NpcCatalog.ts`. Because repeated `npc.talked` events are not deduplicated, use a target above 1 only when repeated conversations should count.

### Craft items

```ts
{
  id: 'brew-tonics',
  kind: 'craft-item',
  label: 'Brew two slime tonics',
  target: 2,
  itemIds: ['hp-potion'],
  recipeIds: ['brew-tonic', 'weave-tonics'],
}
```

The output item must match `itemIds`. When `recipeIds` is present, the recipe must also match. The output quantity is added. Item and recipe IDs are validated against their catalogs.

### Escort a character

```ts
{
  id: 'escort-trader',
  kind: 'escort-character',
  label: 'Escort the trader to camp',
  target: 1,
  escortIds: ['forest-trader-escort'],
  characterIds: ['forest-trader'],
  destinationIds: ['meadow-camp'],
}
```

At least `escortIds` or `characterIds` is required. Every configured filter must match. A producer should supply a stable, unique `runId` for each escort attempt. Without one, the matcher uses `escortId`, so repeated completions of the same escort cannot increment the same objective more than once.

The event contract and matcher exist, but no production escort feature currently emits `escort.completed`. Connect the escort feature before authoring a playable quest with this objective.

### Defeat a boss

```ts
{
  id: 'defeat-guardians',
  kind: 'defeat-boss',
  label: 'Defeat both guardians',
  target: 2,
  bossIds: ['amber-guardian', 'crystal-guardian'],
}
```

Any listed boss matches. Each boss normally counts once because `bossId` is the default fact ID. Supply a different stable `factId` only if repeatable defeats of the same boss are intentionally distinct.

The event contract and matcher exist, but no production boss feature currently emits `boss.defeated`. Connect the boss feature and persist the defeated boss through world progress before using it in a shipped quest.

### Activate an object

```ts
{
  id: 'activate-shrines',
  kind: 'activate-object',
  label: 'Activate the forest shrines',
  target: 3,
  objectIds: ['shrine.world'],
  areaIds: ['gloop-forest'],
}
```

At least `objectIds` or `instanceIds` is required. Use `objectIds` to accept any instance of an archetype; use `instanceIds` to require specific authored map instances. Every configured filter must match. Each `instanceId` can count only once for an objective.

The event contract and matcher exist, but no production interaction feature currently emits `object.activated`. Emit it only after activation succeeds, not when the player merely presses the interaction key.

### Survive for a duration

```ts
{
  id: 'survive-night',
  kind: 'survive-duration',
  label: 'Survive the night assault',
  target: 1,
  encounterIds: ['forest-night-assault'],
  requiredDurationMs: 60_000,
}
```

The encounter ID must match and the event duration must be at least `requiredDurationMs`. Progress increases by one completed survival run, not by milliseconds. For targets above 1, emit a different stable `factId` for each completed run; otherwise the encounter ID deduplicates later completions.

The event contract and matcher exist, but no production survival feature currently emits `survival.completed`. The encounter feature must own the timer and emit only after authoritative success.

### Discover an area

```ts
{
  id: 'discover-regions',
  kind: 'discover-area',
  label: 'Discover both regions',
  target: 2,
  areaIds: ['gloop-forest', 'crystal-caverns'],
}
```

Any listed area matches, and each area counts once. The world scene already emits `area.enter`. Discovered area facts are persisted and may be applied when the quest activates.

Make the target achievable: because area IDs are deduplicated, `target` must not exceed the number of distinct matching areas the player can enter.

## Authoritative gameplay events

A quest definition describes what counts; it does not inspect gameplay systems directly. The feature that owns a successful action must emit the corresponding event through `gameEvents`:

```ts
gameEvents.emit('collectible.collected', {
  mapId,
  instanceId,
  objectId,
  itemId,
  quantity,
});

gameEvents.emit('enemy.died', {
  enemyId,
  areaId,
  kind: enemyKind,
  tags: ['spider'], // Optional; needed by tag-filtered objectives.
});

gameEvents.emit('npc.talked', { npcId, conversationId });
gameEvents.emit('craft.completed', { recipeId, itemId, quantity });
gameEvents.emit('escort.completed', { escortId, characterId, destinationId, runId });
gameEvents.emit('boss.defeated', { bossId, factId });
gameEvents.emit('object.activated', { objectId, instanceId, areaId });
gameEvents.emit('survival.completed', { encounterId, durationMs, factId });
gameEvents.emit('area.enter', { areaId });
```

Emit after the action succeeds and state has been committed. Do not emit from buttons, quest UI, animations, or speculative attempts. Emit exactly once unless repeated events are part of the objective's intended meaning.

The `QuestEventBridge` must subscribe to every quest input event and forward it to `QuestService.handleEvent`. All current objective events are already connected there, including the contract-ready objective types that do not yet have gameplay producers.

## Creating and placing a quest NPC

Skip this section if all acquisition and completion are automatic and no objective refers to a new NPC.

### 1. Add the NPC identity

Add a stable definition to `src/game/content/npcs/NpcCatalog.ts`:

```ts
{
  id: 'mossy-scout',
  displayName: 'Mossy Scout',
  description: 'A scout keeping watch over the forest path.',
},
```

The `description` is the fallback message when the NPC has no offer or turn-in. `visualId` is optional metadata; the placed object archetype owns the current visual.

### 2. Create an NPC object archetype

Create a JSON file under `src/game/content/objects/npcs/`, following an existing NPC file:

```json
{
  "$schema": "../objects.schema.json",
  "objectId": "npc.mossy-scout",
  "selection": "authored",
  "variants": [
    {
      "assetId": "character.player.slime",
      "frames": [
        {
          "visualId": "mossy-scout",
          "frame": 9,
          "scale": 0.28125,
          "displayName": "Mossy Scout"
        }
      ]
    }
  ],
  "physics": null,
  "npc": { "definitionId": "mossy-scout" },
  "tags": ["npc", "interactable"]
}
```

NPC identity is currently owned by the object archetype, so create a separate archetype for each NPC identity.

### 3. Register the object archetype

Import the JSON and add its `objectId` to `OBJECT_FILES` in `src/game/content/objects/ObjectCatalog.ts`.

### 4. Place the NPC in an authored map

Add it through the map editor or add an object entry to the relevant map JSON:

```json
{
  "instanceId": "level-1-npc-mossy-scout",
  "objectId": "npc.mossy-scout",
  "visualId": "mossy-scout",
  "x": 768,
  "y": 704
}
```

The `instanceId` must be stable and unique within the map. The object and visual IDs must exactly match the object catalog. Place the NPC somewhere reachable; the interaction distance is 96 world pixels.

### 5. Reference the NPC from the quest

The same NPC ID may appear in acquisition, completion, talk objectives, or prerequisites:

```ts
acquisition: { kind: 'npc', npcIds: ['mossy-scout'] },
completion: { kind: 'npc-turn-in', npcIds: ['mossy-scout'] },
```

When interacting, ready turn-ins have priority over available offers, abandoned quest re-offers, and ordinary dialogue. The controller currently presents the first applicable quest action for that NPC.

## Chaining quests

### Start the next quest automatically

```ts
export const secondQuest: QuestDefinition = {
  id: 'second-quest',
  // ...
  prerequisites: [
    { kind: 'quest-status', questId: 'first-quest', status: 'completed' },
  ],
  acquisition: { kind: 'automatic' },
  // ...
};
```

When `first-quest` completes, `second-quest` becomes active immediately.

### Reveal the next quest at an NPC

```ts
prerequisites: [
  { kind: 'quest-status', questId: 'first-quest', status: 'completed' },
],
acquisition: { kind: 'npc', npcIds: ['mossy-scout'] },
```

When `first-quest` completes, this quest becomes available. It remains unaccepted until the player talks to the NPC and accepts it.

Create separate quests only when that separation matters to the player or the lifecycle. Otherwise, prefer stages in one quest.

## Save compatibility and definition versions

Quest state persists the quest ID, definition version, status, active stage, objective progress, consumed fact IDs, timestamps, retry stage, and reward state.

Keep `definitionVersion` unchanged for wording-only edits that do not alter saved-state meaning. Increment it when an existing saved quest needs transformation, for example when you:

- Rename or remove a stage or objective ID.
- Change stage ordering in a way that changes the active stage.
- Split or combine objectives.
- Lower targets below potentially saved progress.
- Change facts or lifecycle semantics that existing states cannot safely interpret.

When incrementing from version N to N+1, register a reconciler in `QuestReconciliationRegistry.ts`:

```ts
questReconciliationRegistry.register('my-quest', 1, 2, (state, definition) => {
  return {
    ...state,
    definitionVersion: 2,
    // Rename, clamp, remove, or initialize persisted fields as needed.
  };
});
```

Migrations must be contiguous. A saved version 1 loading definition version 3 needs both `1 -> 2` and `2 -> 3`. Loading fails loudly if any step is missing or if the save contains a newer version than the game.

For a brand-new quest, use version 1. Old saves that do not contain it receive a new locked state, after which prerequisites are evaluated.

## Adding a brand-new objective type

Use this path only when none of the existing objective kinds describes the gameplay fact. A new label or different IDs do not require a new kind.

Assume a new objective named `repair-structure` driven by `structure.repaired`.

### 1. Define the objective and event contract

In `src/game/content/quests/types.ts`:

```ts
export interface RepairStructureObjective extends QuestObjectiveBase {
  readonly kind: 'repair-structure';
  readonly structureIds: readonly string[];
}
```

Add it to `QuestObjectiveDefinition`. `QuestObjectiveKind` is derived from that union.

Add the authoritative event payload to `QuestInputEvents`:

```ts
'structure.repaired': {
  readonly structureId: string;
  readonly instanceId: string;
};
```

Because `GameEvents` includes `QuestInputEvents`, the central event bus becomes type-safe for the event automatically.

### 2. Add catalog validation

Add a case to `validateObjective` in `validateQuestCatalog.ts`. Validate required arrays, positive values, mutually required fields, and referenced catalog IDs where a catalog exists. Prefer rejecting impossible definitions during `quests:check` instead of silently accepting them.

### 3. Implement and register the matcher

In `ObjectiveMatchers.ts`:

```ts
function repairStructureMatch(
  objective: RepairStructureObjective,
  payload: QuestInputEvents['structure.repaired'],
): ObjectiveMatchResult {
  return objective.structureIds.includes(payload.structureId)
    ? matched(1, payload.instanceId)
    : { matched: false };
}
```

Add the matcher to `OBJECTIVE_MATCHERS` and add its kind to the registry's completeness set. Decide deliberately whether progress is:

- Quantity-based, such as collected or crafted item counts.
- Event-based, such as kills or conversations.
- Fact-based, where a stable `factId` prevents one world fact from counting more than once.

Use fact deduplication for persistent or replayed facts. The fact ID must be stable for the same fact and different for distinct facts that should each count.

### 4. Connect the event bridge

Subscribe, unsubscribe, and forward the new event in `QuestEventBridge.ts`, following the existing handlers.

### 5. Emit from the owning feature

The structure feature should emit only after the repair succeeds:

```ts
gameEvents.emit('structure.repaired', { structureId, instanceId });
```

Do not put quest-specific logic into the producer. It reports a domain fact; the matcher decides which quests care.

### 6. Decide whether the fact must be remembered

If a quest accepted later should receive credit for an already-completed repair:

1. Persist repaired structure IDs in the owning world-progress data.
2. Restore them into the quest service or expose them through condition queries.
3. Record the event in `handleEvent`.
4. Apply matching known facts in `applyKnownFacts`.
5. Update the save schema and migration if the saved shape changes.

If the objective should count only actions performed while active, do not add known-fact backfill.

### 7. Test the new kind

Add quest tests covering:

- Matching and non-matching payloads.
- Filter combinations.
- Progress amount and target capping.
- Duplicate behavior.
- Stage gating.
- Save serialization and loading if fact IDs or migrations are involved.
- Prerequisite reevaluation if the event can unlock quests.

Run the complete validation checklist before authoring production quests with the new kind.

## Validation checklist

During authoring, run the narrow checks first:

```powershell
pnpm quests:check
pnpm test:quests
pnpm typecheck
```

If you add or change NPC object archetypes or map placement, also run:

```powershell
pnpm objects:check
pnpm maps:check
```

If you change save state, migrations, or known facts, also run:

```powershell
pnpm test:persistence
```

Before considering the quest finished:

```powershell
pnpm check
```

Then play-test this exact lifecycle:

1. Start from a new run and from an older save.
2. Verify the quest is locked, available, or active at the intended time.
3. Accept or decline it if NPC-acquired.
4. Trigger matching and near-miss events for every objective.
5. Confirm same-stage objectives progress in parallel.
6. Confirm future-stage objectives do not progress early.
7. Complete each stage and check journal visibility.
8. Turn in or auto-complete the quest.
9. Confirm rewards are granted once.
10. Save and reload during at least one active stage.
11. Test failure, retry, abandonment, and re-offer paths when configured.
12. Confirm any chained quest becomes active or available as intended.

## Troubleshooting

### The quest remains locked

- Remember that separate prerequisite entries use AND logic.
- Check the exact prerequisite IDs and requested quest status.
- Confirm the changing system causes prerequisite reevaluation.
- For save-dependent area or boss facts, confirm they exist in world progress and are restored.
- For world flags or talked-NPC facts, confirm the owning feature persists and restores them if needed across loads.

### An NPC does not offer the quest

- Confirm the quest status is `available`, not `locked`, `active`, or `abandoned`.
- Confirm acquisition is `npc` and contains the same NPC definition ID.
- Confirm the NPC exists in `NpcCatalog.ts`.
- Confirm its object archetype points to that definition ID and is registered in `ObjectCatalog.ts`.
- Confirm a valid object instance is placed in the current authored map.
- Move within 96 world pixels and ensure another higher-priority interaction is not taking precedence.

### An objective does not progress

- Confirm the quest is `active` and the objective belongs to the active stage.
- Confirm the owning feature emits the expected event after success.
- Compare the payload IDs with every configured filter; matching is exact and case-sensitive.
- For kill tags, confirm the producer actually supplies `tags`.
- For fact-backed objectives, check whether that fact ID was already consumed.
- Confirm `target` is achievable with the number of distinct deduplicated facts.
- Remember that inventory already owned before acceptance does not satisfy a `collect` objective.

### A later stage starts at zero even though the action happened earlier

That is the intended stage gate. Future stages do not listen to events. Known-fact backfill happens on quest activation, not every stage transition. Reorder the stages, combine the objectives in one stage, make the action repeatable, or extend known-fact application if the game design requires retrospective credit.

### The quest is ready but does not complete

Check `completion`. An `npc-turn-in` quest intentionally remains active after its objectives finish. The player must interact with one of its completion NPCs.

### A definition-version change breaks loading

- Confirm the definition version is a positive integer.
- Add every contiguous reconciliation step.
- Update renamed stage and objective IDs in saved progress, consumed fact IDs, active stage, and retry stage.
- Clamp progress to new targets.
- Run persistence tests with representative old states.

## Final author review

Before shipping a quest, answer yes to each item:

- Are quest, stage, and objective IDs stable, unique, and kebab-case?
- Are actions in the same stage intentionally parallel?
- Are stages in the order actions should begin counting?
- Should this be one multi-stage quest rather than several chained quests, or vice versa?
- Does every prerequisite have a reliable reevaluation and persistence path?
- Does every objective have an authoritative production event?
- Are all IDs exact and backed by the appropriate catalogs or authored content?
- Can every target be reached after deduplication and filtering?
- Are acquisition and turn-in NPCs defined, registered, placed, and reachable?
- Do failure and abandonment policies match the available gameplay controls?
- Are rewards valid and appropriate for a one-time grant?
- Does an existing save need a definition reconciliation?
- Do all relevant checks pass?
- Has the complete lifecycle been play-tested?
