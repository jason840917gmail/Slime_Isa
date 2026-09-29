# Quest Authoring Guide

How to create, connect, validate, and safely evolve quests in Slime Isa. It
covers every objective the quest engine supports today and the steps for
adding a new objective type.

The shipped catalog is **Chapter 1 — The Clearing**
(`src/game/content/quests/quests/chapterOne.ts`): `a-place-to-work` →
`stone-tools` → `worm-trouble` → `the-one-eyed-guardian` on the main line, plus
the optional `a-tonic-for-lili` → `snack-for-the-road`. Read it first; it is
the best working example of every field below.

## The quest model

A quest is one journal entry with one lifecycle, one reward package, and one or
more sequential stages.

- Stages run in array order; all objectives inside the active stage progress
  in parallel, and every one must reach its target before the next stage
  starts.
- Objectives in later stages ignore gameplay events until their stage becomes
  active.
- Finishing the last stage either completes the quest automatically or makes
  it ready for an NPC turn-in.

Use stages when several steps belong to one journal entry. Use separate quests
when each part needs its own acceptance, completion, or rewards, and chain them
with a `quest-status` prerequisite (see [Chaining quests](#chaining-quests)).

## Where quest content lives

| Purpose | Location |
| --- | --- |
| Quest, objective, and event types | `src/game/content/quests/types.ts` |
| Quest definitions | `src/game/content/quests/quests/` (currently `chapterOne.ts`) |
| Registered quest list and retired IDs | `src/game/content/quests/QuestCatalog.ts` |
| Catalog validation | `src/game/content/quests/validateQuestCatalog.ts` |
| Objective event matching | `src/game/quests/matchers/ObjectiveMatchers.ts` |
| Event subscriptions | `src/game/quests/QuestEventBridge.ts` |
| Runtime lifecycle | `src/game/quests/QuestService.ts` (facade: `QuestTracker.ts`) |
| NPC offer/turn-in/dialogue flow | `src/game/features/interaction/QuestNpcController.ts` |
| Learned recipes, story flags, talked NPCs | `src/game/features/progression/StoryProgress.ts` |
| Save reconciliation | `src/game/infrastructure/persistence/quests/QuestReconciliationRegistry.ts` |
| NPC identities | `src/game/content/npcs/NpcDefinitions.ts` (read through `NpcCatalog.ts`) |
| Items / recipes / bosses | `content/items/items.json`, `content/recipes/RecipeCatalog.ts`, `content/bosses/*.json` |
| World scenes (NPC placement) | `src/game/content/scenes/authored/worlds/<map-id>.scene.json` |

## Quick-start workflow

1. Decide whether the actions are parallel objectives, sequential stages, or
   separate chained quests.
2. Confirm every referenced item, recipe, NPC, area, enemy kind, and boss ID
   (see [Valid IDs](#valid-ids-today)).
3. Add the definition to `chapterOne.ts`, or to a new file under
   `src/game/content/quests/quests/` that you spread into `QUEST_DEFINITIONS`
   in `QuestCatalog.ts`.
4. Configure acquisition, stages, completion, policies, rewards, and dialogue.
5. If it uses a new NPC, create and place that NPC as described below.
6. Confirm the owning gameplay feature emits each objective's event (see the
   [objective table](#objective-reference)).
7. Run `pnpm quests:check`, then the rest of the
   [validation checklist](#validation-checklist).
8. Play every route: acceptance, each stage transition, turn-in, reward,
   save/load, and any retry or abandonment path.

## Copy-ready quest template

```ts
import type { QuestDefinition } from '../types';

export const myQuest: QuestDefinition = {
  // Stable, globally unique, kebab-case. Never reuse an old or retired ID.
  id: 'my-quest',
  definitionVersion: 1,
  chapter: 'Chapter 1 — The Clearing', // optional banner shown on accept
  title: 'My Quest',
  description: 'Explain the overall goal to the player.',
  category: 'optional', // 'mandatory' quests must use abandonment 'forbidden'

  prerequisites: [], // every entry must pass (AND)
  acquisition: { kind: 'npc', npcIds: ['lili'] }, // or { kind: 'automatic' }

  stages: [
    {
      id: 'first-step',
      title: 'First step',
      description: 'Explain what the player should do now.',
      objectives: [
        { id: 'collect-berries', kind: 'collect', label: 'Collect purple berries', target: 3, itemIds: ['purple-berry-mat'] },
      ],
    },
  ],

  completion: { kind: 'npc-turn-in', npcIds: ['lili'] }, // or { kind: 'automatic' }
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: { kind: 'retryable', reset: 'quest' },

  rewards: {
    coins: 25,
    xp: 30,
    items: [{ itemId: 'hp-potion', count: 1 }],
    // recipeIds: ['craft-stone-spear'], // recipe must have learnedByQuest: true
    // flags: ['my-story-flag'],         // persistent story flag
  },

  dialogue: {
    offer: ['Lines before the Accept / Decline choice.'],
    progress: ['Lines when talking to the giver mid-quest.'],
    complete: ['Lines before the reward is handed over.'],
  },
};
```

Catalog validation runs when `QuestCatalog.ts` loads, so an invalid definition
fails the game at startup; `pnpm quests:check` is the shortest feedback loop.

## Definition fields

### Identity and text

- `id`: stable, unique, kebab-case. When removing a quest, add its ID to
  `RETIRED_QUEST_IDS` in `QuestCatalog.ts` so old saves drop its state instead
  of failing to load; never reuse a retired ID.
- `definitionVersion`: positive integer used to reconcile old saves (see
  [Save compatibility](#save-compatibility-and-definition-versions)).
- `title`, `description`: journal and notification text.
- `category`: `mandatory` or `optional`.
- `chapter` (optional): chapter banner shown when the quest is accepted.
- `dialogue` (optional): `offer`, `progress`, and `complete` page arrays shown
  in the NPC conversation box. Without `progress`, the giver shows the
  remaining objectives; without dialogue at all the NPC falls back to its own
  `dialogue`/`description`.

Stage and objective IDs must also be kebab-case. Stage IDs must be unique
within the quest; objective IDs must be unique across the whole quest because
progress is stored by objective ID. Treat all persisted IDs as permanent.

### Acquisition

- `{ kind: 'automatic' }` starts the quest as soon as all prerequisites pass
  (with none, when the quest service starts).
- `{ kind: 'npc', npcIds: [...] }` makes it available from any listed NPC; the
  player must accept it. Every ID must exist in `NpcDefinitions.ts`.

### Stages and backfill

An event that happens before its stage is active is ignored. Only when a quest
first activates does the service backfill already-known facts, and only for
`discover-area`, `talk-to-npc`, and `defeat-boss` objectives in the first
active stage. Collect, kill, craft, place, escort, activation, and survival
progress is never backfilled, and known facts are not reapplied on later stage
transitions. Design later stages around actions the player has not done yet or
can repeat.

### Completion

- `{ kind: 'automatic' }` grants rewards as soon as the last stage finishes.
- `{ kind: 'npc-turn-in', npcIds: [...] }` keeps the quest active and marks it
  ready to turn in. The turn-in NPC need not be the giver, but it must exist
  and be placed somewhere reachable.

### Failure and abandonment

```ts
failurePolicy: { kind: 'permanent' }
failurePolicy: { kind: 'retryable', reset: 'quest' | 'current-stage' }
abandonmentPolicy: { kind: 'forbidden' }
abandonmentPolicy: { kind: 'retryable', reset: 'quest' | 'current-stage' }
```

A failure policy creates no timer or death rule: the owning feature must call
`questService.fail(questId, reason)`. No production feature calls it today.
Mandatory quests must use `forbidden` abandonment (validation rejects
anything else). Abandoned optional NPC quests are re-offered by their
acquisition NPC; automatic ones use the automatic retry path. Players abandon
from the quest journal.

### Rewards

All fields are optional and combinable. The service persists `rewardsGranted`,
so rewards are granted exactly once.

- `coins`, `xp`: non-negative integers.
- `items`: `{ itemId, count }` with a known item and positive count.
- `recipeIds`: recipes the player learns. Each must exist in `RecipeCatalog.ts`
  and be marked `learnedByQuest: true`; such recipes stay visible but locked
  until learned.
- `flags`: persistent story flags (pattern `a-z0-9` segments joined by `-`,
  `:`, or `.`) stored in `StoryProgress`; other content can require them with a
  `world-flag` prerequisite. Chapter 1 sets `chapter-1-complete`.

## Prerequisite recipes

Every entry in `prerequisites` must pass (AND). Within one entry's `areaIds` or
`npcIds`, any listed ID is enough (OR).

```ts
{ kind: 'quest-status', questId: 'previous-quest', status: 'completed' } // referenced quest must exist; cycles are rejected
{ kind: 'area-entered', areaIds: ['gloop-forest'] }                      // discovered map/area IDs
{ kind: 'player-level', minimumLevel: 3 }
{ kind: 'inventory-count', itemId: 'wood', minimumCount: 10 }           // checked, not consumed
{ kind: 'world-flag', flagId: 'chapter-1-complete' }                    // story flag, or boss:<bossId>
{ kind: 'npc-talked', npcIds: ['village-elder-plop'] }
```

All of these facts survive save/load: discovered areas and defeated bosses
live in world progress (a defeated boss is exposed as the flag
`boss:<bossId>`), and story flags and talked-to NPCs live in the save's
`story` block.

Prerequisites are evaluated when the service starts, after quest input events,
when a quest completes, and after save facts are restored. A new condition
that can change without one of those signals must trigger
`questTracker.evaluatePrerequisites()`.

## Objective reference

Objectives count events only while their quest is active and their stage is
current. Progress is capped at `target`.

| Kind | Event | Amount per match | Deduplicated by | Production producer |
| --- | --- | --- | --- | --- |
| `collect` | `collectible.collected` | payload `quantity` | none | `CollectibleController` (walk-over pickups, including resource drops) |
| `kill` | `enemy.died` | 1 | none | `CombatController` (no `tags` yet) |
| `talk-to-npc` | `npc.talked` | 1 | none | `QuestNpcController` |
| `craft-item` | `craft.completed` | payload `quantity` | none | `crafting/Crafting.ts` |
| `place-item` | `furniture.placed` | 1 | `placementId` | `WorldScene` furniture placement |
| `defeat-boss` | `boss.defeated` | 1 | `factId`, else `bossId` | boss camp progress service (`UniversalSceneWorldController`) |
| `discover-area` | `area.enter` | 1 | `areaId` | `WorldScene` on map entry |
| `escort-character` | `escort.completed` | 1 | `runId`, else `escortId` | **none yet** |
| `activate-object` | `object.activated` | 1 | `instanceId` | **none yet** |
| `survive-duration` | `survival.completed` | 1 | `factId`, else `encounterId` | **none yet** |

Do not ship a quest that uses a kind with no producer until the owning feature
emits its event.

```ts
// Collect: any listed item matches; counts pickups, not inventory; consumes nothing.
{ id: 'gather-silk', kind: 'collect', label: 'Collect spider silk', target: 5, itemIds: ['silk-clump'] }

// Kill: every configured filter must match; with no filters any death counts.
// enemyTags never match today because combat does not emit tags.
{ id: 'defeat-worms', kind: 'kill', label: 'Defeat worm brawlers', target: 5, enemyKinds: ['worm-brawler'], areaIds: ['level-1'] }

// Talk: repeated conversations count again, so keep target 1 unless repeats are intended.
{ id: 'speak-to-elder', kind: 'talk-to-npc', label: 'Talk to Village Elder Plop', target: 1, npcIds: ['village-elder-plop'] }

// Craft: output item must match; recipeIds optionally narrows the recipe.
{ id: 'brew-tonic', kind: 'craft-item', label: 'Brew a Slime Tonic', target: 1, itemIds: ['hp-potion'], recipeIds: ['brew-tonic'] }

// Place: counts a placed furniture item from the inventory (today: the workbench).
{ id: 'place-workbench', kind: 'place-item', label: 'Place the Workbench', target: 1, itemIds: ['workbench'] }

// Boss: each boss counts once unless the producer supplies distinct factIds.
{ id: 'defeat-fatty', kind: 'defeat-boss', label: 'Defeat Fatty One Eye', target: 1, bossIds: ['fatty-one-eye'] }

// Discover: each area counts once, so target must not exceed the number of listed areas.
{ id: 'enter-gloop-forest', kind: 'discover-area', label: 'Enter Gloop Forest', target: 1, areaIds: ['gloop-forest'] }

// Contract-only kinds (no producer yet):
{ id: 'escort-trader', kind: 'escort-character', label: 'Escort the trader', target: 1, escortIds: ['trader-escort'], destinationIds: ['camp'] } // needs escortIds or characterIds
{ id: 'light-shrines', kind: 'activate-object', label: 'Light the shrines', target: 3, objectIds: ['shrine'], areaIds: ['gloop-forest'] } // needs objectIds or instanceIds
{ id: 'survive-night', kind: 'survive-duration', label: 'Survive the assault', target: 1, encounterIds: ['night-assault'], requiredDurationMs: 60_000 }
```

`area.enter` fires with the **map ID** when the player enters a map
(`level-1`, `gloop-forest`, `crystal-caverns`, ...). Named `Area2D` world areas
inside a map (spawn, safe, NPC-wander, boss-arena areas) do not emit it.

## Authoritative gameplay events

A quest describes what counts; it never inspects gameplay systems. The feature
that owns a successful action emits the event on `gameEvents`
(`src/game/core/EventBus.ts`) with the payload declared in `QuestInputEvents`:

```ts
gameEvents.emit('collectible.collected', { mapId, instanceId, objectId, itemId, quantity });
gameEvents.emit('enemy.died', { enemyId, areaId, kind, tags }); // tags optional
gameEvents.emit('npc.talked', { npcId, conversationId });        // conversationId optional
gameEvents.emit('craft.completed', { recipeId, itemId, quantity });
gameEvents.emit('furniture.placed', { mapId, placementId, itemId, sceneId, x, y });
gameEvents.emit('boss.defeated', { bossId, factId });           // factId optional
gameEvents.emit('area.enter', { areaId });
gameEvents.emit('escort.completed', { escortId, characterId, destinationId, runId });
gameEvents.emit('object.activated', { objectId, instanceId, areaId });
gameEvents.emit('survival.completed', { encounterId, durationMs, factId });
```

Emit after the action succeeds and state is committed, exactly once, never from
buttons, quest UI, animations, or speculative attempts. `QuestEventBridge`
already forwards every event above to `QuestService.handleEvent`.

## Creating and placing a quest NPC

Skip this if the quest uses only existing NPCs. NPCs are universal scenes; the
most recent example to copy is `fisherman-slime` (commit `a3aa9a2`).

1. **Sprite asset.** Add the sheet under `asset/characters/authored/npcs/` and
   its `character.npc.<id>` entry to `asset/assets.json`; run
   `pnpm assets:check`.
2. **Character package.** Create `src/game/content/characters/<id>/character.json`
   (`"kind": "npc"`, `visualSetId: "character.npc.<id>"`) and
   `visual-set.json`, and register both in
   `src/game/content/characters/virtual-character-content.ts`.
3. **NPC identity.** Add an entry to `NPC_DEFINITIONS` in
   `src/game/content/npcs/NpcDefinitions.ts`:

   ```ts
   {
     id: 'old-miner',          // the ID quests reference
     characterId: 'old-miner', // one NPC per character package
     displayName: 'Old Miner',
     description: 'Fallback line when there is no dialogue.',
     dialogue: ['Pages shown when the NPC has no quest action.'],
   },
   ```

4. **Character scene.** Create
   `src/game/content/scenes/authored/characters/<id>.scene.json` (copy
   `fisherman-slime.scene.json`, or use Scene Studio at `?studio=scenes`). Its
   `game.npc` ScriptNode carries `characterId` and `npcDefinitionId` (the NPC
   ID) plus wander tuning.
5. **Place it.** In Scene Studio, open the world scene
   (`scenes/authored/worlds/<map-id>.scene.json`) and add an instance of
   `character.<id>` under the `world` node, overriding the `body` position.
   Optionally add an `npc-wander` world area (a `game.world-area` script with
   `data.npcInstanceId`) to keep it roaming nearby. In level 1, instances
   outside the generated `gen-*` groups survive
   `scripts/maps/build-level-1.mjs`; add the instance to that script's pinned
   position table only if the builder should own its position.

The `npc.*` object archetypes in `src/game/content/objects/npcs/` and
`LegacyMapPlacementMapping.ts` exist only for the older NPCs' map-JSON
placements; new NPCs do not need them.

Players interact within 96 world pixels. A ready turn-in has priority over an
available offer, which has priority over an abandoned re-offer and ordinary
dialogue; the controller shows the first applicable quest action and an
overhead marker for it.

## Chaining quests

```ts
prerequisites: [{ kind: 'quest-status', questId: 'first-quest', status: 'completed' }],
acquisition: { kind: 'automatic' },                 // starts the moment first-quest completes
// or
acquisition: { kind: 'npc', npcIds: ['lili'] },    // becomes available at Lili; the player accepts it
```

There is no separate quest-sequence entity. Prefer stages in one quest unless
the separation matters to the player or the lifecycle.

## Save compatibility and definition versions

Quest state persists the quest ID, definition version, status, active stage,
objective progress, consumed fact IDs, timestamps, resume stage, and reward
state. Keep `definitionVersion` unchanged for wording-only edits. Increment it
when a saved state needs transformation, for example when you rename or remove
a stage or objective ID, reorder stages, split or combine objectives, or lower
a target below possibly saved progress.

When going from version N to N+1, register a reconciler (no quest needs one
yet; register at module scope in `QuestReconciliationRegistry.ts`):

```ts
questReconciliationRegistry.register('my-quest', 1, 2, (state, definition) => ({
  ...state,
  definitionVersion: 2,
  // Rename, clamp, or remove progress, consumedFactIds, activeStageId, resumeStageId.
}));
```

Migrations must be contiguous (1→2 and 2→3 to load a v1 save into v3). Loading
fails loudly if a step is missing or the save is newer than the game. New
quests start at version 1; old saves that lack them get a new locked state.

## Adding a brand-new objective type

Only do this when no existing kind describes the gameplay fact. Example:
`repair-structure`, driven by `structure.repaired`.

1. **Types** (`content/quests/types.ts`): add a `RepairStructureObjective`
   interface to the `QuestObjectiveDefinition` union (`QuestObjectiveKind` is
   derived from it) and the payload to `QuestInputEvents`. `GameEvents`
   includes `QuestInputEvents`, so the bus becomes type-safe automatically.
2. **Validation** (`validateQuestCatalog.ts`): add a `validateObjective` case
   that checks required arrays, positive numbers, and catalog references.
3. **Matcher** (`ObjectiveMatchers.ts`): write the match function, add it to
   `OBJECTIVE_MATCHERS`, and add the kind to the completeness set in
   `QuestObjectiveRegistry`. Choose quantity-based, event-based, or fact-based
   progress; use a stable fact ID when one world fact must count once.
4. **Bridge** (`QuestEventBridge.ts`): subscribe, unsubscribe, and forward.
5. **Producer**: the owning feature emits after success. Keep quest logic out
   of it; it reports a domain fact.
6. **Remembered facts** (optional): if a quest accepted later should get
   credit, persist the fact in world or story progress, restore it through
   `restoreKnownFacts` (called from `core/SaveSystem.ts`), record it in
   `handleEvent`, apply it in `applyKnownFacts`, and update the save schema.
7. **Tests** (`scripts/tests/quests/`): matching and non-matching payloads,
   filters, amount and capping, duplicates, stage gating, save round trips, and
   prerequisite reevaluation.

## Validation checklist

```powershell
pnpm quests:check        # catalog + NPC-to-character references
pnpm test:quests
pnpm typecheck
```

For new NPCs or placements also run `pnpm characters:check`,
`pnpm scenes:check`, `pnpm assets:check`, and `pnpm test:npcs`. For save,
migration, or known-fact changes run `pnpm test:persistence`. Finish with
`pnpm check`.

Then play-test: start from a new run and from an older save; confirm the quest
is locked, available, or active at the right time; accept and decline; trigger
matching and near-miss events for every objective; confirm same-stage
objectives progress together and future stages do not; complete each stage;
turn in or auto-complete; confirm rewards arrive once; save and reload during
an active stage; exercise failure, retry, abandonment, and re-offer paths; and
confirm any chained quest appears as intended.

## Troubleshooting

**The quest stays locked.** Separate prerequisite entries are ANDed. Check the
exact IDs and requested status, and that the changing system triggers
reevaluation.

**An NPC does not offer the quest.** The status must be `available` (not
`locked`, `active`, or `abandoned`); acquisition must be `npc` with the same
NPC ID; the NPC's character scene must set that `npcDefinitionId`; an instance
must be placed in the current world scene; and the player must be within 96 px
with no higher-priority action on that NPC.

**An objective does not progress.** The quest must be `active` and the
objective in the active stage. Confirm a producer exists and emits after
success, that payload IDs match every filter exactly (case-sensitive), that a
fact ID was not already consumed, and that `target` is reachable after
deduplication. Items owned before acceptance never satisfy `collect`.

**A later stage starts at zero although the action happened earlier.** That is
the stage gate. Reorder stages, merge the objectives into one stage, make the
action repeatable, or extend known-fact backfill.

**The quest is ready but does not complete.** An `npc-turn-in` quest stays
active until the player talks to one of its completion NPCs.

**A definition-version change breaks loading.** Add every contiguous
reconciliation step, rename IDs in progress, consumed facts, active stage, and
resume stage, clamp progress to new targets, and run the persistence tests.

## Valid IDs today

Verify against the source before relying on this list.

- **NPCs** (`NpcDefinitions.ts`): `village-elder-plop`, `level-1-spider-giver`
  (Mossy; character `mossy-scout`), `lili`, `red-slime-boy`,
  `yellow-blond-slime-girl`, `fisherman-slime`.
- **Enemy kinds** (character packages with `kind: "enemy"`): `worm-brawler`,
  `worm-swordsman`, `worm-archer`, `slime-spider`.
- **Bosses**: `fatty-one-eye`.
- **Areas / maps** reachable in play: `level-1`, `gloop-forest`,
  `crystal-caverns`; interiors `slime-home`, `mushroom-home`.
- **Items** (`items.json`): `wood`, `stone`, `iron-ore`, `charcoal`,
  `hp-potion`, `energy-potion`, `purple-berry-mat`, `silk-clump`, `shard`,
  `green-key`, `workbench`, `berry-basket`, plus every weapon ID under
  `content/weapons/` (for example `wooden-spear`, `stone-spear`).
- **Recipes**: `craft-workbench`, `craft-wooden-spear`, `craft-stone-axe`,
  `craft-stone-pickaxe`, `craft-stone-spear`, `brew-tonic`,
  `cook-berry-basket`, `brew-fizzy`, `weave-tonics`.

## Final author review

- Are quest, stage, and objective IDs stable, unique, kebab-case, and not
  retired?
- Are same-stage objectives meant to be parallel, and stages in the order they
  should start counting?
- Does every prerequisite have a reevaluation and persistence path?
- Does every objective have a production event producer?
- Can every target be reached after filtering and deduplication?
- Are the giver and turn-in NPCs defined, placed, and reachable?
- Do failure and abandonment policies match the controls that exist?
- Are rewards valid, and are rewarded recipes marked `learnedByQuest`?
- Does an existing save need a reconciler?
- Do the checks pass, and has the full lifecycle been play-tested?
