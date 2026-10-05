# Spec: Quests, NPC quest talk, the dialogue box and the quest HUD

Area owner: quests (the quest service, objectives and rewards, NPC offer / turn-in / talk, the
dialogue box, the offer window, the quest tracker, NPC quest markers, the waypoint, quest
notifications). Binding inputs: [GODOT_MIGRATION.md](../../GODOT_MIGRATION.md),
[CONVENTIONS.md](../CONVENTIONS.md), [ARCHITECTURE.md](../ARCHITECTURE.md),
[UI_THEME.md](../UI_THEME.md). Related specs: [interaction.md](./interaction.md) (router, NPC talk
candidate, the stand-ins this spec replaces), [abilities.md](./abilities.md) (ability rewards,
restoration sites), [world-objects.md](./world-objects.md) (collectibles), [boss.md](./boss.md) /
[matron.md](./matron.md) (`boss_defeated`), [enemy.md](./enemy.md) (enemy defeat award),
[shell.md](./shell.md) (banners, end cards, pause menu), [audio.md](./audio.md) (cues).

Sources read (read-only): `src/game/content/quests/{types,QuestCatalog,validateQuestCatalog}.ts`,
`content/quests/quests/{chapterOne,chapterTwo}.ts`, `src/game/quests/{QuestService,QuestTracker,
QuestEventBridge,Quest,QuestCollectionProgress}.ts`, `quests/matchers/ObjectiveMatchers.ts`,
`src/game/features/quests/{QuestNotificationPresenter,QuestRewardText,QuestWaypoint,
QuestWaypointPresenter}.ts`, `features/interaction/{QuestNpcController,InteractionRouter}.ts`,
`features/ui/{NpcDialogueSurfacePort,QuestOfferSurfacePort,QuestTrackerSurfacePort,
QuestJournalSurfacePort}.ts`, `features/npcs/NpcNameTags.ts`, `features/progression/StoryProgress.ts`,
`features/collectibles/CollectibleController.ts`, `features/combat/CombatController.ts`,
`features/world/UniversalSceneWorldController.ts`, `scenes/WorldScene.ts`, `core/SaveSystem.ts`,
`infrastructure/persistence/quests/*`, `features/player/{ControlLabels,PlayerInputActions,
PlayerAbilityDefinitions}.ts`, `content/recipes/RecipeCatalog.ts`, `content/npcs/NpcDefinitions.ts`,
`features/audio/AudioEventBridge.ts`, the authored `ui/{npc-dialogue,quest-offer-modal,
quest-tracker}.scene.json`, `worlds/{level-1,gloop-forest}.scene.json`, `src/styles.css:3640-3720`;
on the Godot side `godot/game/autoload/run_state.gd`, `game/interaction/interaction_controller.gd`,
`game/scripts/{npc,collectible,resource_node,restoration_site,boss_camp}.gd`, `game/main.gd`,
`game/shell/{shell,control_labels}.gd`, `game/audio/music_director.gd`, `game/ui/*`,
`game/ui/theme/*`, `godot/tests/**`, `scripts/godot/lib/inputs.mjs`.

Line numbers are `file:line` in the current `feat/godot-migration` tree (2026-10-05). Paths without
a folder are under `src/game/`.

Legend: **[IN]** port in the quest phase. **[OUT]** exists in Phaser, deferred (listed so later
phases know). **[QUIRK]** Phaser behaviour that looks unintended or surprising; port as is unless
the owner decides otherwise (§12). **[BLOCKED]** works in the port only once another system lands
(crafting, furniture placement, enemy loot, menus). **[CENTRE]** a Phaser position that is the old
sprite centre (player: `get_centre()`); NPC positions are the old sprite bottom
(`npc.get_phaser_position()`).

Godot state this spec was written against: the committed tree up to `f29f770` plus the uncommitted
working tree (boss/matron, ranged enemies, shell, audio, UI theme). `RunState` already has
`quests: Array` (empty, saved by `serialize()`), `story.talked_npc_ids` + `record_talk`,
`story.learned_recipe_ids` (no API), `learn_ability` / `ability_learned`, `set_flag` /
`story_flag_changed`, `add_coins`, `add_item` / `item_capacity`, `world.discovered_areas` +
`mark_area_discovered`, `world.defeated_boss_ids`, and the stub `is_quest_active` +
`debug_active_quests`. The interaction controller offers NPCs only as "talk" (priority 50) and its
`_talk` shows the first page as floating text (interaction spec §8.6 stand-in).

---

## 0. Phaser file map

| Concern | File |
|---|---|
| Quest data types, input and domain events | `content/quests/types.ts` (300 lines) |
| Catalogue (order, retired ids, lookup, validation) | `content/quests/QuestCatalog.ts:5-48`, `validateQuestCatalog.ts` |
| Chapter 1 / 2 content | `content/quests/quests/chapterOne.ts` (8 quests), `chapterTwo.ts` (6 quests) |
| State machine, rewards, conditions, known facts | `quests/QuestService.ts` (597 lines) |
| Event bus → service | `quests/QuestEventBridge.ts:13-27` (11 input events) |
| Objective matchers | `quests/matchers/ObjectiveMatchers.ts:49-129` |
| Facade, legacy migration, save hooks | `quests/QuestTracker.ts`, `core/SaveSystem.ts:78-114`, `infrastructure/persistence/quests/*` |
| Toasts and chapter banner | `features/quests/QuestNotificationPresenter.ts:29-44` |
| "QUEST COMPLETE" texts | `scenes/WorldScene.ts:497-502` |
| Reward lines | `features/quests/QuestRewardText.ts:51-73` |
| NPC candidates, conversations, markers | `features/interaction/QuestNpcController.ts` (324 lines) |
| Marker drawing | `features/npcs/NpcNameTags.ts:6-21, 56-105` |
| Dialogue box | `features/ui/NpcDialogueSurfacePort.ts` + `content/scenes/authored/ui/npc-dialogue.scene.json` |
| Offer / turn-in window | `features/ui/QuestOfferSurfacePort.ts` + `ui/quest-offer-modal.scene.json` |
| Quest tracker (HUD) | `features/ui/QuestTrackerSurfacePort.ts` + `ui/quest-tracker.scene.json` |
| Waypoint | `features/quests/QuestWaypoint.ts`, `QuestWaypointPresenter.ts`, `WorldScene.ts:1148-1189`, `UniversalSceneWorldController.ts:1145-1215` |
| Journal [OUT] | `features/ui/QuestJournalSurfacePort.ts` |
| Wiring | `WorldScene.ts:327-337` (controller), `:397-410` (presenter, story binding, `questTracker.start()`), `:515` (`area.enter`), `:750-772` (pause sources), `:2279-2285` (`quest-npc`, `npc-dialogue` sources) |
| Legacy, not ported | `quests/Quest.ts`, `QuestCollectionProgress.ts`, `ui/QuestJournal.ts`, `ui/QuestOfferModal.ts` (deprecated views) |

---

## 1. Data model (`content/quests/types.ts`)

### 1.1 Definition

```
QuestDefinition {
  id, definitionVersion (int > 0), title, description,
  category: 'mandatory' | 'optional',
  prerequisites: QuestCondition[],                 # all must hold (every)
  acquisition: {kind:'npc', npcIds[]} | {kind:'automatic'},
  stages: [{id, title, description, objectives[]}], # >= 1 stage, >= 1 objective each
  completion: {kind:'automatic'} | {kind:'npc-turn-in', npcIds[]},
  failurePolicy: {kind:'permanent'} | {kind:'retryable', reset:'quest'|'current-stage'},
  abandonmentPolicy: {kind:'forbidden'} | {kind:'retryable', reset:'quest'|'current-stage'},
  rewards: {coins?, items?:[{itemId,count}], recipeIds?, abilityIds?, flags?},
  chapter?: string,                                 # banner on accept
  dialogue?: {offer?[], progress?[], complete?[]}   # pages of the NPC conversation box
}
```

Conditions (`:117-139`): `quest-status {questId, status}` (exact status match), `area-entered
{areaIds}` (any), `inventory-count {itemId, minimumCount}`, `world-flag {flagId}`, `npc-talked
{npcIds}` (any). Content uses only `quest-status`, `area-entered`, `world-flag`.

Objective kinds (`:34-113`), each `{id, kind, label, target (int > 0)}` plus:

| Kind | Fields | Input event | Used in content |
|---|---|---|---|
| `collect` | `itemIds` | `collectible.collected` | yes |
| `kill` | `enemyKinds?`, `areaIds?`, `enemyTags?` | `enemy.died` | yes |
| `talk-to-npc` | `npcIds` | `npc.talked` | no |
| `craft-item` | `itemIds`, `recipeIds?` | `craft.completed` | yes |
| `escort-character` | `escortIds?`, `characterIds?`, `destinationIds?` | `escort.completed` | no |
| `defeat-boss` | `bossIds` | `boss.defeated` | yes |
| `activate-object` | `objectIds?`, `instanceIds?`, `areaIds?` | `object.activated` | yes |
| `survive-duration` | `encounterIds`, `requiredDurationMs` | `survival.completed` | no |
| `place-item` | `itemIds` | `furniture.placed` | yes |
| `discover-area` | `areaIds` | `area.enter` | yes |
| `use-control` | `controlIds` ⊂ `menu:inventory, menu:crafting, menu:journal, menu:map, sprint, weapon-switch, pause` (`:93`) | `control.used` | yes |

Validation (`validateQuestCatalog.ts:149-246, 275-282`, throws at import): ids match an id pattern
and are unique; stage ids unique per quest; objective ids unique **per stage** (progress is keyed
by objective id across the whole quest, so a duplicate across stages would collide; none exists);
items / NPCs / recipes / abilities must exist; reward recipes must be `learnedByQuest`; mandatory
quests must have `abandonmentPolicy: forbidden`; prerequisite references exist and are acyclic.

### 1.2 State (`:192-207`) and statuses

`QuestState {questId, definitionVersion, status, activeStageId (null unless active), progress
{objectiveId: int}, consumedFactIds? {objectiveId: string[]}, acceptedAt?, completedAt?,
failedAt?, failureReason?, abandonedAt?, resumeStageId?, rewardsGranted}`. Times are
`Date.now()` epoch ms (`QuestService.ts:69`).

Statuses: `locked` → `available` (NPC quests) → `active` → `completed`; `failed`, `abandoned`
side states. Load-time invariants (`validateQuestState`, `validateQuestCatalog.ts:284-317`):
`active` ⇔ `activeStageId` set and known; `resumeStageId` only for failed/abandoned;
`rewardsGranted === (status === 'completed')`; progress values integers in `[0, target]` for known
objectives; consumed facts are string arrays of known objectives.

`QuestView` = state + `definition`, `visibleStages`, `readyToTurnIn` (§2.9).

### 1.3 Domain events (`:284-300`)

`quest.available {questId, source: 'npc'|'condition'}`, `quest.accepted {questId, source:
'npc'|'automatic'}`, `quest.progressed {questId, stageId, objectiveId, before, after}`,
`quest.stage-completed {questId, stageId}`, `quest.completed {questId, title, rewards}`,
`quest.failed {questId, reason}`, `quest.abandoned {questId}`, `quest.changed {questId}` (after
every mutation), `story.changed {}`.

---

## 2. Quest service behaviour (`quests/QuestService.ts`) [IN]

### 2.1 Lifecycle

- One module singleton `questService` (`:597`); Phaser reloads the page on every area travel, so it
  is rebuilt per world: `SaveSystem.install` → `questTracker.load(states)` (`:97`) →
  `restoreKnownFacts({discoveredAreas, defeatedBossIds, talkedNpcIds, worldFlags})` (`:104-109`)
  → `WorldScene.create` → `questTracker.start()` (`WorldScene.ts:410` = `questService.start()` +
  `QuestEventBridge.start()`) → later in `create` `gameEvents.emit('area.enter', {areaId})`
  (`:515`, not in title mode).
- `start()` (`:190-197`): if no states exist, a `locked` state per definition (catalog order,
  `createLockedState :443-453`: progress `{}`, consumed `{}`, rewardsGranted false); then
  `evaluatePrerequisites()`.
- Order of `QuestService` construction vs listeners: the notification presenter (`:397-401`) and
  the story binding (`:402-409`) exist before `start()`, so a new run shows its first toasts at
  boot (§4.1).

### 2.2 `evaluatePrerequisites()` (`:430-441`)

```
for definition in catalog order:               # one pass; later quests see earlier changes
    state = states[definition.id]
    if state.status != 'locked' or not every(prerequisites, condition_satisfied): continue
    if acquisition.kind == 'automatic': activate(state, definition, 'automatic')
    else: state.status = 'available'; emit quest.available {questId, source:'condition'}; changed
```

`condition_satisfied` (`:459-472`):

| Kind | True when |
|---|---|
| `quest-status` | `states[questId].status == status` (exact; e.g. `'available'` stops matching once accepted) |
| `area-entered` | any area in the service's discovered set (area.enter events + restored `discoveredAreas`) **or** `worldProgress.discovered()` |
| `inventory-count` | `playerInventory.count(itemId) >= minimumCount` |
| `world-flag` | the service's world-flag set (`boss:<bossId>` from `boss.defeated` / restored `defeatedBossIds`, plus restored story flags) **or** `storyProgress.hasFlag(flagId)` |
| `npc-talked` | any npc in the talked set or `storyProgress.hasTalkedTo` |

### 2.3 `activate(state, definition, source)` (`:474-482`) and known facts (`:484-503`)

```
state.status = 'active'; state.activeStageId = stages[0].id; state.acceptedAt = now
progress[o.id] ??= 0 for every objective of stages[0]
emit quest.accepted {questId, source}; changed
# apply known facts, FIRST STAGE ONLY:
for objective in stages[0].objectives:
    facts = discover-area: areaIds in the discovered set
          | talk-to-npc:  npcIds in the talked set
          | defeat-boss:  bossIds with 'boss:<id>' in the world-flag set
          | other kinds:  []
    for fact in facts not yet consumed for this objective: consume; increment(objective, 1)
try_complete_stage(stages[0])     # may advance, become ready, or complete (automatic)
```

**[QUIRK] Known facts apply only to the first stage on activation.** Advancing to a later stage
never looks at facts, so `the-one-eyed-guardian` stage 2 needs a Fatty defeat **after** stage 2
starts (Fatty respawns 180 s after a defeat once the player has left his circle, boss spec 4.1),
and stage 3 needs an `area.enter gloop-forest` after stage 3 starts (every arrival emits it).
**[QUIRK]** `the-matrons-nest` has `defeat-boss` in its first and only stage: a run that killed the
Matron before accepting the quest completes it **on accept** (rewards, `chapter-2-complete`, end
card).

### 2.4 `handleEvent(event, payload)` (`:396-428`)

```
if event == 'npc.talked':    talked set += payload.npcId
if event == 'area.enter':    discovered set += payload.areaId
if event == 'boss.defeated': world-flag set += 'boss:' + payload.bossId
evaluatePrerequisites()
active = [states with status 'active']              # snapshot AFTER the first evaluation
for state in active (catalog order):
    stage = stage(state.activeStageId); progressed = false
    for objective in stage.objectives:
        r = matchObjective(objective, event, payload, consumed)   # §2.5
        if not r.matched or r.amount <= 0: continue
        if r.factId:
            if r.factId in consumed[objective.id]: continue
            consumed[objective.id].append(r.factId)    # consumed even if progress is capped
        progressed = increment(state, stage.id, objective.id, r.amount) or progressed
    if progressed: try_complete_stage(state, stage.id)
evaluatePrerequisites()
```

- Only objectives of the **current stage** of **active** quests count. Items picked up, enemies
  killed or bosses defeated before (or during an earlier stage) are lost for that objective.
- Every active quest is matched independently: one wood pickup advances every active quest with a
  matching objective.
- A quest completed inside the loop runs `complete()` → `evaluatePrerequisites()`; newly available
  or auto-activated quests are not in the snapshot and do not see this event.

### 2.5 Matchers (`ObjectiveMatchers.ts:49-115, 151-162`)

`valuesInclude(values, v)` = `values is undefined or v in values`; `tagsIncludeAll(values, tags)` =
`values undefined or (tags defined and every value in tags)`.

| Kind | Matches when | Amount | Fact id |
|---|---|---|---|
| `collect` | `not payload.recovered` and `itemId in itemIds` and `quantity` integer > 0 | `quantity` | — |
| `kill` | `valuesInclude(enemyKinds, kind)` and `valuesInclude(areaIds, areaId)` and `tagsIncludeAll(enemyTags, tags)` | 1 | — |
| `talk-to-npc` | `npcId in npcIds` | 1 | — |
| `craft-item` | `itemId in itemIds` and `valuesInclude(recipeIds, recipeId)` and `quantity` integer > 0 | `quantity` | — |
| `escort-character` | escort/character match (undefined = any) and `valuesInclude(destinationIds, destinationId ?? '')` | 1 | `runId ?? escortId` |
| `defeat-boss` | `bossId in bossIds` | 1 | `factId ?? bossId` |
| `activate-object` | `objectIds`/`instanceIds` undefined or include, `valuesInclude(areaIds, areaId)` | 1 | `instanceId` |
| `survive-duration` | `encounterId in encounterIds` and `durationMs >= requiredDurationMs` | 1 | `factId ?? encounterId` |
| `place-item` | `itemId in itemIds` | 1 | `placementId` |
| `discover-area` | `areaId in areaIds` | 1 | `areaId` |
| `use-control` | `controlId in controlIds` | 1 | `controlId` |

`matchObjective` also returns not-matched when the matcher's event differs from `event`, or when
the fact id is already consumed for that objective.

### 2.6 `increment` (`:505-515`) and `tryCompleteStage` (`:517-532`)

```
increment(state, stageId, objectiveId, amount) -> bool:
    before = progress[objectiveId] ?? 0
    after = min(objective.target, before + floor(amount))
    if after <= before: return false                   # capped: no event
    progress[objectiveId] = after
    emit quest.progressed {questId, stageId, objectiveId, before, after}; changed; return true

try_complete_stage(state, stageId):
    if status != 'active' or activeStageId != stageId: return
    if any objective of the stage has progress < target: return
    emit quest.stage-completed {questId, stageId}
    if it is the last stage:
        if completion.kind == 'automatic': complete(state)
        else: changed                                   # now readyToTurnIn
        return
    activeStageId = next stage; progress[o.id] ??= 0 for its objectives; changed
```

`quest.stage-completed` fires for the **last** stage too, right before `quest.completed`.

### 2.7 `complete` (`:534-548`) and rewards (`defaultRewards :95-109`)

```
complete(state):
    if status == 'completed': return
    if not rewardsGranted:
        grant(rewards)            # may throw: nothing below runs, the quest stays as it was
        rewardsGranted = true
    status = 'completed'; activeStageId = null; completedAt = now
    emit quest.completed {questId, title, rewards}; changed
    evaluatePrerequisites()        # follow-up quests unlock in the same call

grant(rewards), in this order:
    items:     playerInventory.transact([], additions) all-or-nothing;
               false -> throw Error("Could not grant all reward items for quest '<id>'.")
    recipeIds: storyProgress.learnRecipes(ids)        # story.changed if new
    abilityIds:storyProgress.learnAbilities(ids)      # per NEW id: ability.learned {abilityId}
    flags:     storyProgress.setFlags(ids)            # story.changed if new
    coins:     gameState.addCoins(coins)              # if coins != 0
```

So the "ability learned" banner and a flag's consequences (story variants, end cards) happen before
`quest.completed` (the "QUEST COMPLETE" texts), and follow-up `quest.available` toasts after it.
Quests never take items from the bag (no objective consumes; turning in keeps crafted items).

### 2.8 Commands (results `{ok:true, state}` or `{ok:false, code, reason}`)

| Command | Lines | Rules (failure code: reason) |
|---|---|---|
| `accept(questId, npcId)` | `:288-298` | unknown → `unknown-quest`: `Unknown quest '<id>'.`; already `active` → ok (no-op); not `available`, not NPC-acquired, or `npcId` not a giver → `invalid-status`: `Quest '<id>' is not available from NPC '<npc>'.`; else `activate(..., 'npc')` |
| `decline(questId, npcId)` | `:300-308` | same checks as accept; ok **without** any state change |
| `turnIn(questId, npcId)` | `:310-320` | not active / not `npc-turn-in` / npc not listed → `wrong-npc`: `Quest '<id>' cannot be turned in to NPC '<npc>'.`; not ready → `not-ready`: `Quest '<id>' is not ready to turn in.`; else `complete` |
| `abandon(questId)` | `:322-337` | not active → `invalid-status`: `Quest '<id>' is not active.`; mandatory or forbidden → `mandatory-quest`: `Quest '<id>' cannot be abandoned.`; else status `abandoned`, `resumeStageId = activeStageId`, stage null, `abandonedAt`, emit `quest.abandoned`, changed |
| `reoffer(questId, npcId)` | `:339-353` | not abandoned / not NPC-acquired / npc not a giver → `invalid-status`: `Quest '<id>' cannot be re-offered by NPC '<npc>'.`; policy forbidden → `retry-not-allowed`: `Quest '<id>' cannot be retried after abandonment.`; else reset (abandonment policy), status `available`, emit `quest.available {source:'npc'}`, changed |
| `retryFailed(questId)` | `:355-363` | not failed or permanent → `retry-not-allowed`: `Quest '<id>' cannot be retried.`; else reset (failure policy), `activate` |
| `retryAbandonedAutomatic(questId)` | `:365-377` | not an abandoned automatic quest → `invalid-status`; policy → `retry-not-allowed`; reset, status `locked`, changed, `evaluatePrerequisites()` |
| `fail(questId, reason)` | `:379-394` | not active → ok no-op; blank reason → `invalid-state`; status `failed`, resume stage, `failedAt`, `failureReason`, emit `quest.failed`, changed. **No caller in the game** (no content fails) |

Reset (`resetForRetry :550-569`): `'quest'` clears progress and facts and returns to stage 1;
`'current-stage'` drops the progress and facts of `resumeStageId` (else the first unfinished
stage, else stage 1) and resumes there. Both clear `failedAt, failureReason, abandonedAt,
completedAt, resumeStageId` and set `rewardsGranted = false`.

**[QUIRK]** `slime-basics` (automatic) abandoned and retried returns to `locked`, but its
prerequisite `a-place-to-work == 'available'` no longer holds once that quest was accepted, so it
never restarts.

### 2.9 Views and queries (`:249-286, 571-582`)

```
activeIndex = index of activeStageId
            | completed: last stage | resumeStageId: its index | else -1
visibleStages = stages[0 .. activeIndex]        # [] for locked/available
readyToTurnIn = completion is npc-turn-in and status active and activeIndex == last
                and every objective of the LAST stage has progress >= target
list(status?)            states in insertion order (= catalog order), filtered
offersForNpc(npcId)      available + acquisition npc + npcId in npcIds
reoffersForNpc(npcId)    abandoned + acquisition npc + npcId in npcIds + abandonment retryable
turnInsForNpc(npcId)     active + readyToTurnIn + completion npc-turn-in + npcId in npcIds
```

### 2.10 Load and save

- `serialize()` (`:245-247`): every state, cloned. Saved as `GameSaveData.quests` (`SaveSystem.ts:82`)
  and in every area handoff (`AreaNavigation.ts:112`).
- `load(states)` (`:210-243`): retired ids (`RETIRED_QUEST_IDS = {'gather-building-materials'}`,
  `QuestCatalog.ts:17-20`) dropped; unknown ids, failed reconciliations or invalid states collect
  issues and throw `QuestLoadError` (the whole save is rejected); missing quests get a `locked`
  state; the fact sets are cleared (then `restoreKnownFacts` refills them).
- Version reconciliation (`QuestReconciliationRegistry.ts`, `QuestStateRepair.ts`): `worm-trouble`
  v1→v2, `beyond-the-verdant-gate` v1→v2, `a-harder-pick` v1→v2 clamp/move progress; legacy
  `{id, status, progress}` saves are migrated (`QuestTracker.ts:9-33`). **[OUT]** for Godot: no
  Godot save predates this phase; store `definition_version` so a reconciler can be added later.

---

## 3. Input events: who emits them [IN unless marked]

| Event | Phaser emitter | Payload | When | Godot source (§10.4) |
|---|---|---|---|---|
| `collectible.collected` | `CollectibleController.ts:92-99` | `{mapId, instanceId, objectId, itemId, quantity: moved, recovered?: true}` | after a pickup moved ≥ 1 item (also partial pickups and Stretch Lash pulls); `recovered` = the pile is a bag drop whose origin is not `'loot'` (`:65-66`) | `collectible.gd _on_collected` |
| `enemy.died` | `CombatController.ts:282-289` via `finishDefeatedOrdinaryEnemies` (`UniversalSceneWorldController.ts:2047-2058`) | `{enemyId, areaId (current area), kind (enemy type id)}`; no `tags` | once per **ordinary** enemy defeat; bosses never | enemy defeat award port (other engineer) |
| `npc.talked` | `QuestNpcController.ts:285-288` (with `storyProgress.recordTalk`) | `{npcId}` (definition id) | plain talk: when the box **opens**; offer/turn-in: after a successful decision (§5.3) | quest NPC flow |
| `craft.completed` | `CraftingService.ts:223-227` | `{recipeId, itemId, quantity = output.count × crafts}` | each successful craft | crafting port [BLOCKED] |
| `boss.defeated` | `UniversalSceneWorldController.ts:596-600` (`markBossDefeated`) | `{bossId}` | boss defeat, after `defeatBoss(bossId)` | camp signal `boss_defeated {campId, bossId}` |
| `object.activated` | `WorldScene.ts:2114` (`restoreSite`) | `{objectId, instanceId (persistence key of the enclosing instance, e.g. `level-1.level-1-forge`), areaId}` | after the cost is paid and the flag set | `restoration_site.gd restore()` |
| `area.enter` | `WorldScene.ts:515` | `{areaId}` (= map id for every current world) | every world arrival (boot, travel, door, load), not in title mode | `main.gd _build_world` end |
| `control.used` | `WorldScene.ts:596-602` (modal opened: `inventory`→`menu:inventory`, `crafting`→`menu:crafting`, `quest-journal`→`menu:journal`, `world-map`→`menu:map`, `pause-menu`→`pause`, `MENU_CONTROL_IDS :141-147`), `:620-624` (sprint rising edge: moving and sprint held, while playing), `:2157-2161` (belt switch) | `{controlId}` | as listed | Shell `menu_opened(&"pause-menu")`, `player.gd` sprint edge; menus/belt [BLOCKED] |
| `furniture.placed` | `WorldScene.ts:1248-1250` | `{mapId, placementId, itemId, sceneId, x, y}` | after a successful placement | `furniture_placement.gd` `place` |
| `escort.completed`, `survival.completed` | none | — | never emitted [OUT] | — |

- `workbench.opened {mapId, context}` (`WorldScene.ts:1283`) is **not** a quest input and has **no
  listener at all** (`core/EventBus.ts:48` declares it) **[QUIRK]**. Opening a bench never advances a
  quest; crafting at it does.
- Resource nodes emit nothing for quests: "Chop wood" / "Mine stone" / "Mine iron ore" count the
  **pickups** of the piles a node drops (and of loose authored piles), via `collectible.collected`.
- Chest transfers, quest rewards and crafting outputs do **not** emit `collectible.collected`, so
  they never count for `collect` objectives.

---

## 4. What the player sees

### 4.1 Toasts (`QuestNotificationPresenter.ts:29-44`, `WorldScene.ts:397-401, 497-502`)

Floating text at the player position **[CENTRE]** `p` (`this.player.x/y`), colours of the floating
text palette (Godot `GameFeel.TEXT_COLORS`):

| Event | Text | Colour | Big | At | Duration |
|---|---|---|---|---|---|
| `quest.available` | `New quest available: <title>` | yellow | yes | `p - (0, 112)` ("lifted above the completion card") | default |
| `quest.accepted` | `Quest accepted: <title>`; if the quest has `chapter`: banner `showAreaTitle(chapter, '#ffd277')` first | green | yes | `p - (0, 70)` | default |
| `quest.stage-completed` | `Stage complete: <title>` | green | no | `p - (0, 70)` | default |
| `quest.failed` | `Quest failed: <title> (<reason>)` | red | yes | `p - (0, 70)` | default |
| `quest.abandoned` | `Quest abandoned: <title>` | red | no | `p - (0, 70)` | default |
| `quest.completed` | `QUEST COMPLETE: <title>` | yellow | yes | `p - (0, 70)` | 2400 ms |
| `quest.completed` | one line per reward: `+ <line>` (§4.2) | green | yes | `p + (0, -46 + 20·i)` | 2400 ms |

`<title>` = definition title, else the id. Chapter banners: `a-place-to-work` → "Chapter 1 — The
Clearing", `beyond-the-verdant-gate` → "Chapter 2 — Gloop Forest". **[QUIRK]** Two quests unlocked
by one completion (e.g. `stone-tools` and `a-tonic-for-lili`) draw two "New quest available"
texts on the same spot; the last stage's "Stage complete" shares `p - (0, 70)` with "QUEST
COMPLETE".

### 4.2 Reward lines (`QuestRewardText.ts:51-73`)

`lines = [coins? "<n> coins"] + [items: (count > 1 ? "<count>× " : "") + item name] + ["New
recipe: <recipe name>"] + ["New ability: <ability title>"]` (flags are not listed). Summary (offer
window) = `"Reward: " + lines.join(" · ")`, or `"Reward: the elder's gratitude"` when empty.
Exact values per quest in §7.

### 4.3 Ability banner and audio

- `ability.learned` (from rewards) → banner `"<title> learned: press <key>"` in `#9ff0c8`
  (`WorldScene.ts:483-491`), e.g. "Dodge learned: press 1", "Jump learned: press Space", "Stretch
  Lash learned: press 2", "Squash Slam learned: press 3"; cue `AbilityLearned` (abilities spec §1.1).
- Cues (`AudioEventBridge.ts:95-109`, all `audio.global` players, pitch ±0.06, `minIntervalMs 60`):
  `npc.talked` → `NpcBlip`; `quest.accepted` → `QuestAccept`; `quest.progressed` and
  `quest.stage-completed` → `QuestProgress` (the second within 60 ms is dropped); `quest.completed`
  → `QuestComplete`; `quest.failed` → `QuestFailed`; any modal opening → `MenuOpen` (`JournalOpen`
  for `quest-journal`), closing → `MenuClose` (dialogue box and offer window included).
- Reward coins play `Coin` (coins spec), learned flags may open the end card (`chapter-2-complete`,
  shell spec §6), and every pause source ducks the music to 0.35 (audio spec §3.2).

### 4.4 Quest tracker (HUD) (`QuestTrackerSurfacePort.ts`, `ui/quest-tracker.scene.json`)

Always-visible card under the HUD; hidden when it has no entry and on the title screen.

Entries (`trackedQuestViews :68-73`): every `active` quest plus every `available` NPC quest,
sorted by `rank` = `(mandatory ? 0 : 2) + (active ? 0 : 1)`, then `acceptedAt` descending
(available ones count as 0), then input order (active list then offers, each in catalog order;
JS sort is stable). The first 4 (`TRACKED_QUEST_SLOTS`) are shown.

Per entry (`describe :80-98`):
- available: lines `["! Talk to <first giver name>"]`;
- active and ready to turn in: `["? Return to <first turn-in npc name>"]`;
- else one line per objective of the current stage:
  `(progress >= target ? "✓" : "•") + " " + objectiveLabel + (target > 1 ? "  <p>/<t>" : "")`
  with `p = min(target, progress)` and two spaces before the count;
- `objectiveLabel` (`:53-57`): a `use-control` objective appends its key:
  `menu:inventory` → `(E)`, `menu:crafting` / `menu:journal` → `(E, then its tab)`, `menu:map` →
  `(M)`, `sprint` → `(hold Shift)`, `weapon-switch` → `(Mouse wheel)`, `pause` → `(Esc)` (labels from
  the binding table, `controlLabel(menu|map|sprint|weapon-next|pause)`).
- Title = quest title (prefixed `"➜ "` while the waypoint points at it); colour `#ffd277` for
  mandatory, `#d9ecff` for optional.

Layout (`build :174-207`; constants `:11-25`), in CSS px:

```
WIDTH 284, TOP 96, LEFT 16, HEADER 26, TITLE 20, LINE 18, GAP 8, FOOTER 22, CHARS_PER_ROW 40
rows(line) = max(1, ceil(codepoints(line) / 40))
y = 26
for slot in 1..4: entry height = 20 + 18 · sum(rows(lines)); quest<slot> rect = [10, y] .. [-10, y + h]
                  (left/right relative to the card); y += h + 8 for each shown entry
card = [16, 96] .. [300, 96 + (y - 8 + 22)]
heading  "QUESTS · <all entries, not only the 4 shown>"
hint     waypoint off: "Click a quest to show the way"
         on and found:  "➜ Follow the gold arrow · click it again to hide"
         on, not found: "Nothing to point at on this map"
         + "  (+<n> in the book)" when more than 4 entries
bookHint "E · Journal tab"                       # controlLabel('menu') + " · Journal tab"
```

Scene styling: heading 10 px bold muted (letter-spacing 0.12 em), book hint 10 px muted right
aligned on the same row, titles 14 px bold, objectives 12 px wrap (line height 1.45), hint 11 px
muted; panel `TrackerPanel` (1 px warning border 38 %, 3 px warning left edge, radius 10, dark
gradient, text shadow). Only the four quest blocks take the pointer (`GhostButton`, hover tint
warning 10 %). Clicking quest *n* (`invoke track-n`, `:128-141`): if the waypoint is on and this
quest is the tracked one → waypoint off; else select it and turn the waypoint on. The tracked quest
is the selected one if still listed, else the first entry. Rebuilt on every `quest.changed`.

Fresh run (keys E/M/Shift/Esc): entries `a-place-to-work` (rank 1) then `slime-basics` (rank 2):

| Slot | Title (colour) | Lines (rows) | Rect |
|---|---|---|---|
| 1 | A Place to Work (#ffd277) | `! Talk to Village Elder Plop` (1) | [10, 26] .. [-10, 64] |
| 2 | Slime Basics (#d9ecff) | `• Open your bag (E)` (1), `• Look at the Crafting tab (E, then its tab)` (44 chars, 2), `• Read your Journal (E, then its tab)` (1), `• Open the map (M)` (1), `• Sprint (hold Shift)` (1), `• Pause to save or change settings (Esc)` (40 chars, 1) | [10, 72] .. [-10, 218] |

Card [16, 96] .. [300, 336], heading `QUESTS · 2`.

### 4.5 NPC quest markers (`QuestNpcController.ts:259-283`, `NpcNameTags.ts`)

`markerFor(npcId)`: `turn-in` if any turn-in; `main-offer` if any mandatory offer; `side-offer` if
any optional offer or any reoffer; `talk` if an active quest's current stage has an unfinished
`talk-to-npc` objective for this NPC (unreachable in content); `in-progress` if an active quest has
`npc-turn-in` completion listing this NPC; else none.

| Marker | Symbol | Colour | Size |
|---|---|---|---|
| `main-offer` | `!` | `#ffd277` | 30 |
| `side-offer` | `!` | `#72d8ff` | 26 |
| `turn-in` | `?` | `#ffd277` | 30 |
| `in-progress` | `?` | `#a7bbd6` | 24 |
| `talk` | `…` | `#f5f7ff` | 24 |

Text bold, stroke `#081022` 6 px, origin (0.5, 1), at `(x, round(nameTagY - 18 + bob))` with
`nameTagY = npc.y - 73.28 - 2` (NPC sprite bottom minus display height 229 × 0.32, minus 2) and
`bob = sin(sceneTime / 900 · 2π) · 3`; a new marker pops scale 0.4 → 1 in 220 ms `Back.Out`;
hidden with the sprite; depth = name tag depth (just above the NPC in the y-sort). Markers refresh
only when the router polls the NPC provider after a `quest.changed` (dirty flag, `:54-55, 99-101`),
so they never change while the game is paused or the router is suppressed (sleep).

### 4.6 Waypoint (`QuestWaypoint.ts`, `QuestWaypointPresenter.ts`, `WorldScene.ts:1148-1189`)

Shown only while the tracker's waypoint is on and the game is not paused (`updateGameplay`). Every
250 ms (scene time) the tracked quest's target is resolved from the player position **[CENTRE]**:

```
available NPC quest -> nearest giver NPC present on this map: "Talk to <name>"
active, ready, npc-turn-in -> nearest turn-in NPC: "Return to <name>"
active -> first unfinished objective of the current stage that resolves:
   kill:            nearest enemy-spawn area holding any enemyKinds -> its stay rect centre
   defeat-boss:     camp root position of the first bossId whose camp is on this map
   discover-area:   nearest exit (WorldExitScript parent) or in-tree door whose target area is it
   collect:         nearest pile with remaining > 0 of those items, or standing resource node whose
                    drop yields one of them
   craft-item:      station of the first recipe whose output is in itemIds; 'portable' -> nothing;
                    else nearest in-tree station that serves it (workshop also serves workbench)
   activate-object: nearest in-tree restoration site whose objectId matches
   talk-to-npc:     nearest NPC: "Talk to <name>"; place-item/use-control/escort/survive: nothing
label = objective.label (except talk)
```

Presenter (depth above everything): gold `#ffd277` / ink `#081022`; marker pin (ink circle r 13 +
triangle to y 24, gold circle r 10 + triangle to 20, ink dot r 4) at `(tx, ty - 58 + bob)`, alpha
`0.8 + 0.2·pulse`; label 13 px `#ffe8a8` stroke 4 at `(tx, ty - 86 + bob)` origin (0.5, 1), only
while the target is on screen (inside the camera view inset 48); arrow (chevron, tip +x) at
`player + (cos a, sin a)·(72 + 6·pulse) - (0, 16)` rotated `a`, and `"<m> m"` (12 px, `m =
round(dist / 64)`) at radius + 30, shown only when the target is off screen and `m > 1`. `pulse =
0.5 + 0.5 sin(t/220)`, `bob = 5 sin(t/260)`, `t` = accumulated gameplay delta. Level-1 targets:
worm camp `(1130, 1514)`, Fatty's camp `(2528, 1472)`, exit to gloop-forest `(3552, 576)`, forge
site `(1190, 1068)`, workshop site `(640, 392)`. The minimap also shows the target [OUT].

### 4.7 Journal [OUT]

Menu tab (`QuestJournalSurfacePort.ts`): lists active, available, completed, failed/abandoned
quests; actions Abandon (active optional retryable), Retry (failed retryable; abandoned automatic
retryable), with `window.confirm`. It is the only way to abandon, so reoffers (§5.2) are
unreachable until it exists. Opening it emits `control.used menu:journal` and plays `JournalOpen`.

---

## 5. NPC quest interaction (`QuestNpcController.ts`) [IN]

### 5.1 Registration and reach

Every `NpcScript` with a known definition is a record `{instanceId, npcId = npcDefinitionId, actor}`
(`:77-81`); `isActive` = in the tree (a story variant can park it). Reach 96 from the NPC position
(sprite bottom) to the player **[CENTRE]**; badge anchor NPC + (30, -30); pointer origin NPC −
(0, 24); every NPC in reach is a candidate (`getCandidates`, interaction spec §2.3-2.4: equal
priorities are decided by the smaller id, not distance).

### 5.2 Candidate per NPC (`candidateFor :130-210`), evaluated every poll

| Order | Condition | Id suffix | Prompt | Priority | Execute |
|---|---|---|---|---|---|
| 1 | `turnInsForNpc(npcId)[0]` | `:turn-in` | `Return to <name>` | **100** | `converse(complete pages, "Claim reward  ▸", openTurnIn)` |
| 2 | `offersForNpc(npcId)[0]` | `:offer` | `Talk to <name>` | **90** | `converse(offer pages, "Continue  ▸", openOffer)` |
| 3 | `reoffersForNpc(npcId)[0]` | `:reoffer` | `Resume quest with <name>` | **85** | lock; `questService.reoffer`; on failure: red big text `reason` at NPC − (0, 52), release after 700 ms; else `openOffer(refreshed, talked, release)` (no dialogue pages) |
| 4 | otherwise | `:talk` | `Talk to <name>` | **50** | plain talk (§5.4) |

Id = `quest-npcs:<instanceId>:<suffix>`; `<name>` = `displayName` (Village Elder Plop, Mossy,
Lili, Pip, Sunny, Lily the Fishergirl), else the id. Offer and talk prompts are identical; only the
priority (and so the winner against doors 90 / benches 88) differs.

### 5.3 `converse(record, pages, finishLabel, decide)` (`:228-252`)

```
release = actor.acquireInteractionLock()            # NPC stops, idles
if pages empty: decide(release); return true        # never in content
dialogue.open({speaker: name, pages, finishLabel,
               onFinished: () -> decide(release),   # read through the last page
               onClosed: release})                  # Esc / ✕ / teardown: no decision, quest unchanged
return true

decide = offer:   modal.openOffer({quest, npcId}, onFinished = talked(npcId), onClosed = release)
         turn-in: modal.openTurnIn(quest, npcId,  onFinished = talked(npcId), onClosed = release)
```

The offer window (§6.6) then runs: Accept → `accept` (offer) / `turnIn` (turn-in); on `ok` →
`talked(npcId)` (record talk + `npc.talked`) → close → `release`. Decline on an offer → `decline`
(no state change) → `talked` → close. "Close" on a turn-in → `talked` → close (no turn-in). Esc /
✕ → close → `release` only (no talk recorded). A failing command shows its reason in the window's
error label and keeps it open.

### 5.4 Plain talk (`:189-209`, `progressLine :316-324`)

```
waiting = first active quest whose ACQUISITION npcIds include this NPC (activeQuestFrom :254-257)
pages = waiting ? waiting.dialogue.progress + [progressLine(waiting)]
                : definition.dialogue ?? [definition.description ?? 'Hello!']
release = lock; dialogue.open({speaker: name, pages, onClosed: release}); talked(npcId)  # at OPEN
```

`progressLine`: `Still to do for "<title>":\n• <label> (<p>/<t>)` one `•` line per unfinished
objective of the current stage (raw `label`, no control keys, count always shown), or
`"<title>" — come back to me when you're ready.` when none is unfinished (unreachable in content).
Example, `a-place-to-work` accepted: `["A workbench is the heart of every camp. Wood is scattered
all over the clearing.", "Still to do for \"A Place to Work\":\n• Craft a Workbench (40 wood)
(0/1)"]`. Automatic quests from an NPC (`the-one-eyed-guardian`, `the-matrons-nest`) also produce
progress pages while active.

### 5.5 Teardown (`destroy :212-222`)

Closes the offer window and the dialogue (their `onClosed` release the locks), runs pending
releases, forgets records. Phaser reloads the page on travel, so a conversation never survives a
world change.

---

## 6. Dialogue box and offer window [IN]

### 6.1 Dialogue model (`NpcDialogueSurfacePort.ts`)

```
REVEAL_CHARS_PER_SECOND = 45; REVEAL_TICK_MS = 30; ADVANCE_KEYS = Space, Enter, NumpadEnter
open(request {speaker, pages, onClosed?, onFinished?, finishLabel?}):       # :58-67
    if destroyed: return
    close()                                   # an open session is closed first (its onClosed runs)
    pages = request.pages.map(trim).filter(non-empty); if none: ['...']
    session = {..request, pages, page: 0, revealed: 0}
    pause source 'npc-dialogue' on; modal 'npc-dialogue' opens (MenuOpen); start reveal
advance():                                    # :70-84  (Next button, Space/Enter)
    if typing (revealed < len(page)): revealed = len; stop reveal       # "skip"
    elif last page: close(finished = true)
    else: page += 1; revealed = 0; start reveal
close(finished = false):                      # :86-99  (Esc, ✕, teardown, end of pages)
    stop reveal; if no session: return
    session = null; modal closes (MenuClose); pause source off
    finished and onFinished ? onFinished() : onClosed?()   # exactly one of them, once
reveal tick (every 30 ms, wall clock):        # :143-154
    revealed = min(len, floor((now - pageStartedAt) / 1000 * 45)); stop at len
```

Keys (`:162-168`): a capture-phase `keydown` handler takes Space / Enter / NumpadEnter while a
session exists (`preventDefault` + `stopPropagation`, so Space never jumps); repeats are ignored
(`event.repeat`). Esc reaches the modal stack, which closes the top surface (= `close()`). **[QUIRK]**
The class comment says "F/Space/Enter" but `F` is not an advance key (interact is the right mouse
button now); right-click does not advance either. Mouse: Next button → `advance()`, ✕ → `close()`.

Presentation model (`snapshot :101-119`):

| Field | Value |
|---|---|
| `speaker` | request speaker |
| `text` | `page.slice(0, revealed)` (newlines kept: `white-space: pre-line`) |
| `pageLabel` | `"<page+1> / <count>"` when count > 1, else `""` |
| `nextLabel` | typing → `"Skip  ▸▸"`; last page → `finishLabel ?? "Done  ✓"`; else `"Next  ▸"` |
| `hint` | `"Space / Enter  continue   ·   Esc  close"` |
| rect | width `w = min(760, max(1, viewport width - 24))`, height 196, bottom gap 24: bottom-centre anchored, `[-w/2, -220] .. [w/2, -24]` |

At 1280 × 720 the box is (260, 500)-(1020, 696). A 120-character page reveals in 2667 ms.

### 6.2 Dialogue layout (`ui/npc-dialogue.scene.json`, `styles.css:3647-3672`)

Offsets relative to the box (anchors in brackets: TL top-left, TR top-right, BR bottom-right, BL
bottom-left, F full):

| Node | Rect | Look |
|---|---|---|
| root `npc-dialogue` (ModalRoot, z 88) | as §6.1 | `DialoguePanel`: 2 px warning border at 55 %, radius 14, shadow `0 16 44 #080e1ad9` |
| Speaker (Label, TL) | (18, -18) .. (300, 16) | `NamePlate` pill riding the top edge: 16 px bold warning, padding 0 14, max width 300, 2 px warning 70 % border, inset surface |
| Page (Label, TR) | (-120, 10) .. (-52, 34) | 12 px muted, right aligned |
| Close ✕ (Button, TR) | (-44, 8) .. (-12, 38) | muted, aria "Close conversation" |
| Text (Label, F) | (24, 34) .. (-24, -58) | 17 px, wrap, primary text, line height 1.5 |
| Hint (Label, BL→BR) | (24, -46) .. (-170, -14) | 11 px muted |
| Next (Button, BR) | (-156, -50) .. (-18, -12) | accent, bold, radius 8; nudges 3 px right every 1.2 s (not with reduced motion) |
| ClickSfx | `sfx.ui.click`, `minIntervalMs 40` | on Next and ✕ pressed |

### 6.3 Pause semantics (Phaser)

`onPausedChange` = `setSimulationPaused('npc-dialogue')` / `('quest-npc')` (`WorldScene.ts:2283-2284`):
the world stops (physics, scripts, enemy timers) while either is open; the interaction prompt keeps
its last text (interaction spec §2.5); the music ducks; input to the player is cleared when the
pause starts (`UniversalSceneWorldController.ts:789-793`). Because `close()` clears the dialogue's
source before calling `onFinished`, which opens the offer window and sets `quest-npc`, the handoff
is synchronous: no gameplay step runs between the two windows.

### 6.4 Offer / turn-in window (`QuestOfferSurfacePort.ts`)

```
openOffer(offer, onFinished, onClosed) / openTurnIn(quest, npcId, onFinished, onClosed):  # :41-47
    close(); session = {quest, npcId, kind}; error = ''; pause 'quest-npc' on; modal opens
invoke('close') -> close()                                         # Esc (close_requested), no button
invoke('decline'): turn-in -> onFinished(); close()                # "Close" on a turn-in
invoke('accept'|'decline'):                                         # :101-106, runCommand :128-137
    result = turn-in ? turnIn(id, npc) : accept ? accept(id, npc) : decline(id, npc)
    thrown error -> error = message (else 'The quest action failed.'), stay open
    not ok -> error = result.reason, stay open
    ok -> onFinished(); close()
close(): session = null; error = ''; modal closes; pause off; onClosed()        # :49-61
```

Model (`snapshot :63-83`):

| Field | Offer | Turn-in |
|---|---|---|
| title | quest title | `Complete: <title>` |
| description | `description + "\n\n" + objectives + "\n\n" + reward summary` (objectives of the last visible stage, else stage 1: `• <label> (<p>/<t>)` each, raw labels) | same |
| acceptLabel | `Accept quest` | `Turn in and claim reward` |
| declineLabel | `Decline / close` | `Close` |
| error | last failure reason, else `""` | same |
| rect | centred, `w = min(720, vw - 32)`, `h = min(460, vh - 32)` | same |

Layout (`ui/quest-offer-modal.scene.json`, z 90, `WindowPanel`): vertical ScrollContainer > content
(height 460): Title (24, 18)..(-24, 64) 24 px bold warning centred; Description (28, 76)..(-28,
-126) 14 px muted wrap; Error (28, -116)..(-28, -76) 12 px danger wrap; Accept (left half,
(28, -62)..(-8, -16), accent) and Decline (right half, (8, -62)..(-28, -16), muted); buttons radius
6. ClickSfx on both. Opening focuses the first enabled button (Accept).

Example, `a-place-to-work` offer description:
`Every good slime needs a workbench. Build one and set it up in the clearing.\n\n• Craft a
Workbench (40 wood) (0/1)\n\nReward: 20× Wood · New recipe: Stone Axe · New recipe: Stone
Pickaxe`.

---

## 7. Content: every quest

Givers and where they stand (old Phaser NPC positions = sprite bottom; they wander in their
`npc-wander` area, world spec §5):

| npcId (definition) | Name | World / instance | Position |
|---|---|---|---|
| `village-elder-plop` | Village Elder Plop | level-1 `level-1-npc-village-elder-plop` | (524.8, 716.8) |
| `lili` | Lili | level-1 `level-1-npc-lili` | (435.2, 921.6) |
| `red-slime-boy` | Pip | level-1 `level-1-npc-red-slime-boy` | (633.6, 940.8) |
| `fisherman-slime` | Lily the Fishergirl | level-1 `level-1-npc-fisherman-slime` | (1350.4, 742.4) |
| `level-1-spider-giver` | Mossy | level-1 `level-1-npc-mossy-scout` (in `chapter-1-villagers`, parked once `chapter-1-complete` is set); gloop-forest `gloop-ch2-npc-mossy` (camp) | (857.6, 697.6); (1816, 1768) |
| `yellow-blond-slime-girl` | Sunny | level-1 `level-1-npc-yellow-blond-slime-girl` (same variant); gloop-forest `gloop-ch2-npc-sunny` | (857.6, 947.2); (1952, 1904) |

### 7.1 Chapter 1 (`chapterOne.ts`), catalog order

| # | Id / title / v | Giver → turn-in | Cat. | Prerequisites | Stages: objectives (target) | Rewards | Policies | Unlocks |
|---|---|---|---|---|---|---|---|---|
| 1 | `a-place-to-work` "A Place to Work" v1, chapter "Chapter 1 — The Clearing" | Elder → Elder | mandatory | area-entered level-1 (true on a new run) | `build-workbench`: `craft-workbench` craft-item `workbench` (1) "Craft a Workbench (40 wood)"; `place-workbench`: `place-workbench` place-item `workbench` (1) | 20 wood; recipes `craft-stone-axe`, `craft-stone-pickaxe` | fail permanent, abandon forbidden | stone-tools, a-tonic-for-lili |
| 2 | `slime-basics` "Slime Basics" v1 | automatic → automatic | optional | area-entered level-1 **and** a-place-to-work `available` | `learn-the-basics`: use-control `open-bag` menu:inventory, `see-crafting` menu:crafting, `read-journal` menu:journal, `open-map` menu:map, `sprint` sprint, `pause` pause (1 each) | 10 coins | abandon retryable (quest) | — |
| 3 | `stone-tools` "Stone Tools" v1 | Elder → Elder | mandatory | a-place-to-work completed | `craft-tools`: `craft-axe` stone-axe (1), `craft-pickaxe` stone-pickaxe (1); `use-tools`: `switch-tools` use-control weapon-switch (1), `chop-wood` collect wood (20), `mine-stone` collect stone (20) | 20 coins, 10 wood, recipe `craft-wooden-spear`, ability `dodge` | forbidden | worm-trouble |
| 4 | `worm-trouble` "Worm Trouble" v2 | Mossy → Mossy | mandatory | stone-tools completed | `arm-yourself`: `craft-wooden-spear` (1); `clear-camp`: `defeat-worms` kill `worm-swordsman` (3) | 30 coins, recipe `craft-stone-spear`, ability `jump` | forbidden | the-one-eyed-guardian |
| 5 | `the-one-eyed-guardian` "The One-Eyed Guardian" v1 | Elder → **automatic** | mandatory | worm-trouble completed | `stone-spear`: `craft-stone-spear` stone-spear (1); `defeat-fatty`: `defeat-fatty` defeat-boss `fatty-one-eye` (1); `verdant-gate`: `enter-gloop-forest` discover-area `gloop-forest` (1) | 100 coins, flag **`chapter-1-complete`** | forbidden; no `complete` pages | beyond-the-verdant-gate |
| 6 | `the-old-workshop` "The Old Workshop" v1 | Elder → automatic | optional | world-flag `chapter-2-complete` (parked until then) | `restore-workshop`: activate-object `workshop` (1) "Restore the Workshop (60 wood, 40 stone)" | 25 coins | abandon retryable (quest) | — |
| 7 | `a-tonic-for-lili` "A Tonic for Lili" v1 | Lili → Lili | optional | a-place-to-work completed | `brew-tonic`: craft-item `hp-potion` (1) | 2 purple berries (`purple-berry-mat`) | retryable (quest) | snack-for-the-road |
| 8 | `snack-for-the-road` "Snack for the Road" v1 | Lily → Lily | optional | a-tonic-for-lili completed | `cook-snack`: `cook-berry-basket` craft-item `berry-basket` (1) | 25 coins, 1 `hp-potion` | retryable (quest) | — |

### 7.2 Chapter 2 (`chapterTwo.ts`)

| # | Id / title / v | Giver → turn-in | Cat. | Prerequisites | Stages: objectives (target) | Rewards | Policies | Unlocks |
|---|---|---|---|---|---|---|---|---|
| 9 | `beyond-the-verdant-gate` "Beyond the Verdant Gate" v2, chapter "Chapter 2 — Gloop Forest" | Mossy → Mossy | mandatory | the-one-eyed-guardian completed | `thin-the-weavers`: `defeat-orb-weavers` kill `orb-weaver` (5), `collect-fangs` collect `weaver-fang` (3) | 30 coins, ability `stretch-lash`, recipe `craft-reinforced-pickaxe` | forbidden | a-harder-pick, sunnys-basket |
| 10 | `a-harder-pick` "A Harder Pick" v2 | Mossy → Mossy | mandatory | beyond completed | `craft-pickaxe`: craft-item `reinforced-pickaxe` (1); `mine-iron`: collect `iron-ore` (6) | 20 coins | forbidden | rekindle-the-forge |
| 11 | `rekindle-the-forge` "Rekindle the Forge" v1 | Pip → Pip | mandatory | a-harder-pick completed | `restore-forge`: activate-object `forge` (1); `smelt`: `smelt-charcoal` craft-item charcoal (2), `smelt-iron-bars` craft-item iron-bar (3) | 40 coins, recipe `craft-iron-spear` | forbidden | iron-gear |
| 12 | `iron-gear` "Iron Gear" v1 | Elder → Elder | mandatory | rekindle completed | `iron-spear`: craft-item `iron-spear` (1) | 40 coins, recipe `craft-iron-axe` | forbidden | the-matrons-nest |
| 13 | `sunnys-basket` "Sunny's Basket" v1 | Sunny → Sunny | optional | beyond completed | `fetch-basket`: `collect-basket` collect `berry-basket` (1) | 20 coins, 2 purple berries | retryable (quest) | — |
| 14 | `the-matrons-nest` "The Matron's Nest" v1 | Mossy → **automatic** | mandatory | iron-gear completed | `defeat-matron`: defeat-boss `orb-weaver-matron` (1) | 100 coins, ability `squash-slam`, flag **`chapter-2-complete`** | forbidden; no `complete` pages | the-old-workshop |

Every quest has `failurePolicy: permanent` (none can fail in practice). Every NPC quest has
`offer` and `progress` pages; every `npc-turn-in` quest has `complete` pages.

### 7.3 Reward lines (exact, §4.2)

| Quest | Summary (offer window) / `+ ` lines on completion |
|---|---|
| a-place-to-work | Reward: 20× Wood · New recipe: Stone Axe · New recipe: Stone Pickaxe |
| slime-basics | Reward: 10 coins |
| stone-tools | Reward: 20 coins · 10× Wood · New recipe: Wooden Spear · New ability: Dodge |
| worm-trouble | Reward: 30 coins · New recipe: Stone Spear · New ability: Jump |
| the-one-eyed-guardian | Reward: 100 coins |
| the-old-workshop | Reward: 25 coins |
| a-tonic-for-lili | Reward: 2× Purple Berry |
| snack-for-the-road | Reward: 25 coins · Slime Tonic |
| beyond-the-verdant-gate | Reward: 30 coins · New recipe: Reinforced Pickaxe · New ability: Stretch Lash |
| a-harder-pick | Reward: 20 coins |
| rekindle-the-forge | Reward: 40 coins · New recipe: Iron Spear |
| iron-gear | Reward: 40 coins · New recipe: Iron Axe |
| sunnys-basket | Reward: 20 coins · 2× Purple Berry |
| the-matrons-nest | Reward: 100 coins · New ability: Squash Slam |

### 7.4 Chapter flags and what reads them

- `chapter-1-complete` (guardian reward, granted on the `area.enter gloop-forest` that completes
  stage 3): level-1 `chapter-1-villagers-variant` parks Sunny and Mossy in level-1 (they live at
  the gloop-forest camp from then on); no end card.
- `chapter-2-complete` (Matron reward): end card (`content/story/endCards.ts:16`, shell spec §6),
  gloop-forest `matron-heart-variant` shows the Goo Heart `gloop-ch2-matron-goo-heart`, and
  `the-old-workshop` becomes available from the Elder.
- Restoration flags `forge.restored` / `workshop.restored` are set by the sites, not by quests; the
  sites require `rekindle-the-forge` / `the-old-workshop` **active** (abilities spec §13.8).

### 7.5 Content quirks

- **[QUIRK] Sunny's basket can soft-lock.** The basket (`gloop-ch2-sunny-basket`, collectible
  `berry-basket` × 1 at (1696, 168), across water, reachable with the Stretch Lash) is an authored
  pile that never returns. The Lash is the reward of `beyond-the-verdant-gate`, which unlocks
  `sunnys-basket` at the same moment; lashing the basket **before** accepting the quest uses up the
  only pile, and nothing else counts (`collect` = pickups during the active stage only; a crafted
  or re-dropped basket does not count: bag drops are `recovered`).
- `snack-for-the-road` accepts any berry basket crafted after acceptance; a carried basket does not
  count (craft-item, not inventory).
- `a-tonic-for-lili` counts any `hp-potion` craft (`brew-tonic` gives 1, `weave-tonics` gives 2 →
  capped at 1).
- `rekindle-the-forge` "Smelt charcoal" (2) completes with one `smelt-charcoal` craft (output 2).
- `stone-tools` "Chop wood" / "Mine stone" count any wood/stone pickups during stage 2 (loose piles
  included), not chopping.
- Weaver fangs drop from orb-weavers with chance 0.6 (`characters/orb-weaver/character.json:62-77`)
  as ground loot (origin `'loot'`, counts); 5 kills give 3 fangs on average.

### 7.6 Dependencies on systems not ported (written 2026-10-05; state column updated the same evening)

| Quest | Needs | State in Godot |
|---|---|---|
| a-place-to-work | crafting (`craft-workbench`, portable), furniture placement (`place-item`) | ported 2026-10-05: completable in play |
| slime-basics | inventory, crafting tab, journal, world map windows; sprint; pause menu | bag, crafting tab, map, sprint and pause count; the journal is being ported |
| stone-tools | crafting at a workbench (placed bench or restored Workshop), belt weapon switch, axe/pickaxe as weapons, pile pickups | ported (`test_chapter_one_flow.gd::test_stone_tools_by_hand`) |
| worm-trouble | crafting; `enemy.died` for worm swordsmen | ported (`enemy_loot.gd` sends `enemy.died`; `test_worm_trouble_kills_count`) |
| the-one-eyed-guardian | crafting; Fatty (ported, `boss_camp.gd boss_defeated`); travel to gloop-forest (ported); key from the guarded chest | ported (the chest window is being ported; the take-all stand-in works meanwhile) |
| the-old-workshop | restoration site (ported) | reachable only after chapter 2 |
| a-tonic-for-lili, snack-for-the-road | crafting | ported (`test_lili_tonic_and_snack`) |
| beyond-the-verdant-gate | `enemy.died` for orb-weavers; weaver-fang loot piles | systems ported; not played end to end yet |
| a-harder-pick | crafting; iron ore piles (iron nodes need tier 2: the reinforced pickaxe) | systems ported; not played end to end yet |
| rekindle-the-forge | restoration (ported); forge crafting | ported (`test_chapter_two_flow.gd`) |
| iron-gear | crafting | ported (`test_chapter_two_flow.gd`) |
| sunnys-basket | Stretch Lash pull of a pile (ported) | portable now |
| the-matrons-nest | the Matron (`matron.gd`, other engineer) and its camp's `boss_defeated`; end card (Shell) | systems ported; not played end to end yet |
| all | saves | `RunState.serialize/install` already carry `quests` |

Crafting and furniture placement are ported, so every chapter 1 and 2 quest can be finished in play;
the `debug_*` helpers and `--quest=` stay as dev and test paths (§10.9, Q3).

---

## 8. Data the port needs and how to export it

### 8.1 What is needed

| Data | Source | Used for |
|---|---|---|
| Quest catalogue (14 definitions, incl. dialogue pages) | `chapterOne.ts` `CHAPTER_ONE_QUESTS`, `chapterTwo.ts` `CHAPTER_TWO_QUESTS` | everything |
| Catalogue order and retired ids | `QuestCatalog.ts:5-8, 17-20` | concatenation order; `["gather-building-materials"]` |
| NPC names and default pages | `npc-definitions.json` (already exported) | prompts, speaker, plain talk |
| Item names | `items.json` (already copied) via `ItemCatalog.item_name` | reward lines |
| Recipe names, stations, outputs | `recipes/RecipeCatalog.ts` `RECIPE_CATALOG` (15 recipes) | "New recipe: …", waypoint station lookup; the crafting port needs it too |
| Ability titles and actions | Godot `game/player/abilities/ability_definitions.gd` (`title(id)`, `action(id)`) | "New ability: …" and the ability banner |
| Control labels | Godot `game/shell/control_labels.gd` (`control_label(action)`) | tracker keys, ability banner |

### 8.2 Import check (done, read-only)

`TS_DATA_EXPORTS` (`scripts/godot/lib/inputs.mjs:84-103`) imports a module with Node's type
stripping. On Node 24.12 (this machine):
- `content/quests/quests/chapterOne.ts` and `chapterTwo.ts` **import fine** (their only import is
  `import type { QuestDefinition } from '../types'`, which type stripping erases): 8 and 6 quests,
  12 112 bytes of JSON for chapter 1.
- `content/recipes/RecipeCatalog.ts` imports fine (`import type` only): 15 recipes.
- `content/quests/QuestCatalog.ts` **fails** (`ERR_MODULE_NOT_FOUND`: extensionless value import
  `./validateQuestCatalog`), so it cannot be exported as is.

### 8.3 Proposal (converter owner)

Add three rows; no content file changes (so the scene conversion ledger is untouched):

```js
export const TS_DATA_EXPORTS = [
  ['npcs/NpcDefinitions.ts', 'NPC_DEFINITIONS', 'npc-definitions.json'],
  ['quests/quests/chapterOne.ts', 'CHAPTER_ONE_QUESTS', 'quests-chapter-1.json'],
  ['quests/quests/chapterTwo.ts', 'CHAPTER_TWO_QUESTS', 'quests-chapter-2.json'],
  ['recipes/RecipeCatalog.ts', 'RECIPE_CATALOG', 'recipes.json'],
];
```

and reword the comment ("self-contained modules: no value imports; `import type` is erased").
`quest_catalog.gd` concatenates chapter 1 then chapter 2 (the `QUEST_DEFINITIONS` order) and keeps
the retired list as a const. A new chapter file means one more row and one more file name in
`quest_catalog.gd` (`CHAPTER_FILES`). Alternative if one file is preferred: let a row name several
`[source, export]` pairs concatenated into one target (`quests.json`); not needed now. CONVENTIONS'
`generated/data/` list needs the new files (doc owner). Validation stays on the TS side (it runs
on import in the Phaser build and in `pnpm quests:check`); `quest_catalog.gd` only checks shape and
push_errors.

JSON numbers: `GameConstants.data_file` returns Godot's parsed JSON (numbers as `float`); the
catalogue casts `target`, `count`, `coins`, `definitionVersion`, `minimumCount` with `int()`.
`data_file` caches and shares the parsed value: never mutate it.

---

## 9. Behaviour summary for the port (sequences)

New run, boot in level-1 (`main._ready`): `start()` creates 14 `locked` states → evaluation:
`a-place-to-work` → `available` (toast "New quest available: A Place to Work" yellow at centre −
(0, 112)); `slime-basics` → `active` stage `learn-the-basics` (toast "Quest accepted: Slime Basics"
green at centre − (0, 70), cue QuestAccept); `area.enter level-1` changes nothing else. Elder marker
`main-offer`, tracker as §4.4.

Talking to the Elder (offer, priority 90): dialogue (3 pages, finish "Continue  ▸") → offer window
"A Place to Work" → Accept: `active` at `build-workbench`, banner "Chapter 1 — The Clearing",
toast "Quest accepted: A Place to Work", talk recorded, `npc.talked` (NpcBlip), window closes, NPC
released; Elder marker `in-progress`; tracker: `A Place to Work` (rank 0, `• Craft a Workbench (40
wood)`), `Slime Basics`.

Turn-in (priority 100, "Return to Village Elder Plop", marker `turn-in`): dialogue (2 complete
pages, "Claim reward  ▸") → window "Complete: A Place to Work" → "Turn in and claim reward":
+20 wood, 2 recipes learned, `completed`; "QUEST COMPLETE: A Place to Work" + `+ 20× Wood`, `+ New
recipe: Stone Axe`, `+ New recipe: Stone Pickaxe`; `stone-tools` and `a-tonic-for-lili` available
(two toasts); talk recorded; NPC released. Elder marker `main-offer` (stone-tools), Lili
`side-offer`.

Gate to chapter 2: guardian at stage `verdant-gate` → travel through exit-1 → gloop-forest build →
`area.enter gloop-forest` → objective 1/1 → stage complete → automatic `complete`: +100 coins, flag
`chapter-1-complete` → `beyond-the-verdant-gate` available (Mossy at the camp, `main-offer`).

---

## 10. Godot port plan

### 10.0 As built (2026-10-05)

The port follows this plan with these differences (structure only; behaviour as specified):

- No `QuestWindows` CanvasLayer: the dialogue box and the offer window are Controls on main's
  `GameWindows` (`game/ui/screens/game_windows.gd`, layer 40), which owns the `modal` pause, the
  MenuOpen / MenuClose cues and Escape for the top window; they push `npc-dialogue` / `quest-offer`.
  The quest service mounts them and keeps them as `dialogue` / `offer_window`.
- The tracker is `game/ui/quest_tracker.tscn` mounted by the HUD; it finds the service on its own.
- The `control.used sprint` edge is watched by the quest service (as the control hints do), not by
  `player.gd`. Menu ids come from `GameWindows.window_opened` and `Shell.menu_opened`.
- No new `class_name`s (headless runs know only scanned ones): everything is reached by preload.
- Owner decisions: Q1 parity (documented by `test_quests_gloop.gd`), Q2 parity, Q3 `debug_*` plus
  the `quest` launch option, Q4 the interact button advances the dialogue, Q5 toasts shown in the
  same frame stack 22 px apart, Q6 markers at `z_index` 1, Q7 a broken record resets with a warning.
- The ability banner ("<title> learned: press <key>", #9ff0c8) lives in
  `quest_notifications.gd` on `RunState.ability_learned`; the AbilityLearned cue for quest rewards
  plays in the reward grant (ability lessons play their own).
- The waypoint target is also the maps' `waypoint` marker (`MapUi.set_marker`, id `quest-waypoint`).

### 10.1 Files

| File | Kind | Content |
|---|---|---|
| `game/quests/quest_catalog.gd` | `RefCounted`, static, `class_name QuestCatalog` | loads `quests-chapter-1.json` + `quests-chapter-2.json` once via `Services.constants().data_file`, ints normalised; `definitions() -> Array`, `definition(id) -> Dictionary`, `stage(def, stage_id)`, `stage_index(def, stage_id)`, `objective(def, objective_id)`, `RETIRED_IDS`; `recipe(id)` / `recipe_name(id)` from `recipes.json`; `npc_name(id)` and `npc_default_pages(id)` (`dialogue ?? [description ?? "Hello!"]`) from `npc-definitions.json` |
| `game/quests/quest_objectives.gd` | static | the matchers of §2.5: `match(objective, event, payload) -> {"matched", "amount", "fact_id"}` |
| `game/quests/quest_service.gd` | `Node`, `class_name QuestService`, child **"Quests"** of main (made once in `_ready`, kept across worlds), group `quests` | §2 state machine over `RunState.quests`; commands; queries; NPC candidate kind; signals (§10.2) |
| `game/quests/quest_events.gd` | static, `class_name QuestEvents` | the event API world scripts call (§10.4); finds the service by group and does nothing when there is none (title screen) |
| `game/quests/quest_npc_talk.gd` | `RefCounted` owned by the service | §5.2-5.4: candidate kind, `execute(kind, npc)`, converse, progress line |
| `game/quests/quest_notifications.gd` | `RefCounted` owned by the service | §4.1-4.3 toasts, banner, cues, QUEST COMPLETE lines |
| `game/quests/quest_waypoint.gd` | static | §4.6 resolver over Godot groups/areas |
| `game/ui/screens/dialogue_box.tscn` / `.gd` | Godot-owned copy of `ui.npc-dialogue` on the UI theme (`DialoguePanel`, `NamePlate`, `PrimaryButton`, `MutedButton`, `CaptionLabel`) | §6.1-6.2 |
| `game/ui/screens/quest_offer_window.tscn` / `.gd` | copy of `ui.quest-offer-modal` (`WindowPanel`, `PanelTitle`, `MutedLabel`, `DangerLabel`) | §6.4 |
| `game/ui/screens/quest_windows.gd` | `CanvasLayer` **40** "QuestWindows" under main, PROCESS_MODE_ALWAYS | holds the two windows, owns the modal pause (§10.6), group `quest_windows` |
| `game/ui/quest_tracker.tscn` / `.gd` | copy of `ui.quest-tracker` (`TrackerPanel`, `HudLabel`, `GhostButton`), child of `Hud` (layer 10, ALWAYS) | §4.4 |
| `game/ui/npc_quest_markers.gd` | `Node2D` under main (world space, survives swaps), `z_index = 1` | §4.5: one bold `Label` per in-tree NPC with a definition |
| `game/ui/quest_waypoint_view.gd` | `Node2D` under main, `z_index = 2` | §4.6 presenter (`_draw` + two Labels) |
| `godot/tests/test_quests.gd` | tests | §10.10 |

The three UI scenes join CONVENTIONS' "Scenes Godot owns" table like the shell windows (loaded by
path, not in `OWNED_SCENES`). ARCHITECTURE §1 tree, §10 file map and the `game.npc` row need the new
nodes (architect).

**Why a child of main, not an autoload:** the state lives in `RunState.quests` (saved with the run),
so the service holds no state of its own; a child of main is recreated with every `main.tscn`
(fresh per test, absent on the title screen, as Phaser's title mode never emits `area.enter`),
mirrors the `Interaction` child, and needs no `services.gd` change. World scripts reach it only
through `QuestEvents` (group lookup), the interaction controller through group `quests`.

### 10.2 `quest_service.gd` API

```gdscript
extends Node
class_name QuestService
const GROUP := &"quests"
signal quest_available(payload: Dictionary)       # {"questId", "source": "npc"|"condition"}
signal quest_accepted(payload: Dictionary)        # {"questId", "source": "npc"|"automatic"|"debug"}
signal quest_progressed(payload: Dictionary)      # {"questId", "stageId", "objectiveId", "before", "after"}
signal quest_stage_completed(payload: Dictionary) # {"questId", "stageId"}
signal quest_completed(payload: Dictionary)       # {"questId", "title", "rewards"}
signal quest_failed(payload: Dictionary)          # {"questId", "reason"}
signal quest_abandoned(payload: Dictionary)       # {"questId"}
signal quest_changed(payload: Dictionary)         # {"questId"}; tracker, markers, autosave
signal npc_talked(payload: Dictionary)            # {"npcId"}; NpcBlip, tests

func on_world_built(map_id: String) -> void       # main: first call start(), later evaluate; then area.enter
func start() -> void
func evaluate_prerequisites() -> void
func handle_event(event: StringName, payload: Dictionary) -> void
func accept(quest_id: String, npc_id: String) -> Dictionary     # {"ok": true, "state"} | {"ok": false, "code", "reason"}
func decline(quest_id: String, npc_id: String) -> Dictionary
func turn_in(quest_id: String, npc_id: String) -> Dictionary
func abandon(quest_id: String) -> Dictionary
func reoffer(quest_id: String, npc_id: String) -> Dictionary
func retry_failed(quest_id: String) -> Dictionary
func retry_abandoned_automatic(quest_id: String) -> Dictionary
func fail(quest_id: String, reason: String) -> Dictionary
func state(quest_id: String) -> Dictionary        # copy of the RunState record, {} when unknown
func status(quest_id: String) -> String           # "locked" when unknown
func view(quest_id: String) -> Dictionary         # state + "definition", "visible_stages", "ready_to_turn_in"
func list(status_filter: String = "") -> Array[Dictionary]      # views, catalog order
func offers_for_npc(npc_id) / reoffers_for_npc(npc_id) / turn_ins_for_npc(npc_id) -> Array[Dictionary]
func active_quest_from(npc_id: String) -> Dictionary
func npc_candidate(npc_id: String) -> Dictionary  # {"kind": "turn-in"|"offer"|"reoffer"|"talk", "priority", "quest_id"}
func marker_for(npc_id: String) -> String         # "" | "main-offer" | "side-offer" | "turn-in" | "in-progress" | "talk"
func tracked_views() -> Array[Dictionary]         # §4.4 order
func talk_to(npc: Node, kind: String) -> bool     # §5.2 execute (delegates to QuestNpcTalk)
func close_conversations() -> void                # teardown: closes both windows (releases locks)
# dev / tests only (§10.9)
func debug_activate(quest_id: String, stage_id: String = "") -> void
func debug_mark_completed(quest_id: String) -> void
```

Rules that differ in form only: commands return Dictionaries; the reward grant failure is a
result, not an exception: `turn_in` (and an automatic `complete`) first checks that every reward
item fits **together** (simulate the inserts on a copy of the slots, `RunState.item_capacity`
per item is not enough for two different new stacks), and on failure returns `{"ok": false,
"code": "reward-items", "reason": "Could not grant all reward items for quest '<id>'."}` with no
change (Phaser throws the same message, the window shows it). Phaser's separate fact sets become
RunState reads (§10.3). Everything else follows §2 line by line, including the event order of
`activate`, `complete` and `handle_event`.

### 10.3 `RunState` shape (save-ready) and additions

`RunState.quests: Array` of records in catalog order, snake_case like the rest of RunState:

```gdscript
{
  "quest_id": "a-place-to-work",
  "definition_version": 1,
  "status": "active",                # locked|available|active|completed|failed|abandoned
  "active_stage_id": "build-workbench",   # "" when none (Phaser null)
  "progress": {"craft-workbench": 0},     # objective id -> int
  "consumed_fact_ids": {},                # objective id -> Array[String]
  "rewards_granted": false,
  "accepted_at": 1791234567890,     # optional epoch ms, floorf(Time.get_unix_time_from_system() * 1000)
  "completed_at": ..., "failed_at": ..., "failure_reason": "...", "abandoned_at": ...,
  "resume_stage_id": "..."          # optional, failed/abandoned only
}
```

Whole epoch ms keep `_integers()` round trips exact. Tracker ties on `accepted_at` fall back to
catalog order (GDScript `sort_custom` is not stable: sort by `(rank, -accepted_at, catalog index)`).

Known facts read straight from RunState (no copies): discovered set = `world.discovered_areas`;
talked set = `story.talked_npc_ids`; world flag `f` = `has_flag(f)` or (`f` begins with `boss:`
and the rest is in `world.defeated_boss_ids`). `handle_event` still records the fact first
(`record_talk`, `mark_area_discovered`, defeated id append) so an event fired by a test or a
future caller that skipped it behaves as Phaser's.

Additions (world-objects owner, small):

| Member | Behaviour |
|---|---|
| `learn_recipes(ids: Array) -> Array[String]` | appends new ids to `story.learned_recipe_ids`, returns the new ones; emits `recipes_learned {"recipe_ids"}` when any |
| `knows_recipe(id) -> bool` | for crafting |
| `has_talked_to(npc_id)`, `is_area_discovered(area_id)`, `is_boss_defeated(boss_id)` | reads |
| `quest_status(quest_id) -> String` | the record's status, `"locked"` when absent |
| `is_quest_active(quest_id)` | `quest_status(id) == "active" or id in debug_active_quests` (keeps `test_restoration_needs_materials` and `restoration_site.gd` unchanged) |
| `signal quests_changed(payload)` | emitted by the service (`notify_quests_changed(quest_id)`) after each `quest_changed`; added to the autosave list in `_ready` |

The service binds to the array it reads (`is_same(run.quests, _bound)`); when `new_run()` or
`install()` replaced it, the next call rebuilds the id → index map, validates (§10.8) and, if the
array is empty, `start()` recreates the 14 locked states.

### 10.4 Event API for world scripts (`QuestEvents`) and hooks

```gdscript
class_name QuestEvents extends RefCounted
const COLLECTIBLE_COLLECTED := &"collectible.collected"   # {mapId, instanceId, objectId, itemId, quantity, recovered?}
const ENEMY_DIED := &"enemy.died"                         # {enemyId, areaId, kind, tags?}
const NPC_TALKED := &"npc.talked"                         # {npcId}
const CRAFT_COMPLETED := &"craft.completed"               # {recipeId, itemId, quantity}
const BOSS_DEFEATED := &"boss.defeated"                   # {bossId, factId?}
const OBJECT_ACTIVATED := &"object.activated"             # {objectId, instanceId, areaId}
const AREA_ENTER := &"area.enter"                         # {areaId}
const CONTROL_USED := &"control.used"                     # {controlId}
const FURNITURE_PLACED := &"furniture.placed"             # {mapId, placementId, itemId, sceneId, x, y}
const ESCORT_COMPLETED := &"escort.completed"; const SURVIVAL_COMPLETED := &"survival.completed"
static func emit(event: StringName, payload: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var service := tree.get_first_node_in_group(&"quests") if tree != null else null
	if service != null: service.call(&"handle_event", event, payload)
```

Payload keys are Phaser's camelCase (ARCHITECTURE §5 scene payload rule); quest records are
snake_case. Hooks, in Phaser order:

| Where | Change | Owner |
|---|---|---|
| `collectible.gd _on_collected(player, moved)` (after the "+N" text, sparkle, berry coins) | `QuestEvents.emit(COLLECTIBLE_COLLECTED, {"mapId": map_id, "instanceId": instance_id, "objectId": object_id, "itemId": item_id, "quantity": moved})`; add `"recovered": true` when `source_inventory_drop_id` is a bag drop whose origin is not `"loot"` (bag/loot drops are not ported yet; loot piles must count) | world objects |
| enemy defeat award (the port of `CombatController.awardEnemyDefeat`: coins `+Nc`, loot roll, `enemy.died`), once per **ordinary** enemy, not for bosses | `QuestEvents.emit(ENEMY_DIED, {"enemyId": <unique int>, "areaId": map_id, "kind": <enemy type id: worm-swordsman, worm-archer, worm-brawler, slime-spider, orb-weaver>})` | enemy engineer (name only) |
| boss camps (`boss_camp.gd`, group `boss_camp`) | the service connects every camp's `boss_defeated({campId, bossId})` on `WorldService.world_registered` (and on `on_world_built`), and forwards `handle_event(BOSS_DEFEATED, {"bossId": bossId})`. The camp already recorded `defeated_boss_ids` before emitting | quests (no boss file change) |
| `restoration_site.gd restore()` right after `run.set_flag(flag_id)` | `QuestEvents.emit(OBJECT_ACTIVATED, {"objectId": object_id, "instanceId": <persistence_key meta of the nearest ancestor that has one, e.g. "level-1.level-1-forge">, "areaId": world map id})`; the quest check (`run.is_quest_active`) stays as is | abilities |
| `main.gd _build_world` end (after `setup_ui`, player present) | `quests.on_world_built(target_map_id)`: first time `start()`, else `evaluate_prerequisites()`; then `handle_event(AREA_ENTER, {"areaId": map_id})`. Also after `load_run` (it calls `_build_world`) | world builder |
| `main.gd _teardown_world` | `quests.close_conversations()`, markers and waypoint cleared | world builder |
| NPC talk (interaction) | §10.5 | interaction |
| `player.gd` movement step | sprint rising edge: `moving and _input.is_held(&"sprint")` while alive, not sleeping, tree running → `emit(CONTROL_USED, {"controlId": "sprint"})` | player |
| Shell | the service connects `Services.shell().menu_opened(surface_id)` when the Shell exists: `pause-menu` → `pause`; later `inventory`, `crafting`, `quest-journal`, `world-map` → the menu ids | quests |
| crafting port | `emit(CRAFT_COMPLETED, {"recipeId", "itemId", "quantity": output_count * crafts})` | crafting [BLOCKED] |
| furniture placement / belt switch | `FURNITURE_PLACED` / `CONTROL_USED weapon-switch` | later [BLOCKED] |
| workbench | nothing (`workbench.opened` has no quest meaning) | — |

### 10.5 Interaction controller changes (`game/interaction/interaction_controller.gd`)

- `_npc_candidates`: per NPC in reach with a definition, `c = quests.npc_candidate(npc_id)` (no
  service → talk 50); id `"quest-npcs:%s:%s" % [instance_key, c.kind]`; prompt `Return to <name>`
  (turn-in) / `Resume quest with <name>` (reoffer) / `Talk to <name>`; priority from `c`;
  `execute: quests.talk_to(npc, c.kind)`. Anchor and origin unchanged.
- Remove the `_talk` stand-in (first page as floating text) once the dialogue box exists.
- `QuestNpcTalk.execute(kind, npc)`:

```gdscript
func execute(kind: String, npc: Node) -> bool:
	var npc_id := str(npc.get(&"npc_definition_id"))
	var speaker := QuestCatalog.npc_name(npc_id)
	var release: Callable = npc.call(&"acquire_interaction_lock")
	match kind:
		"turn-in":
			var quest: Dictionary = _service.turn_ins_for_npc(npc_id)[0]
			_converse(speaker, _pages(quest, "complete"), "Claim reward  ▸", release,
				func() -> void: _windows.offer.open_turn_in(quest["quest_id"], npc_id, _talked.bind(npc_id), release))
		"offer":
			var quest: Dictionary = _service.offers_for_npc(npc_id)[0]
			_converse(speaker, _pages(quest, "offer"), "Continue  ▸", release,
				func() -> void: _windows.offer.open_offer(quest["quest_id"], npc_id, _talked.bind(npc_id), release))
		"reoffer":
			var quest_id: String = _service.reoffers_for_npc(npc_id)[0]["quest_id"]
			var result := _service.reoffer(quest_id, npc_id)
			if result["ok"]:
				_windows.offer.open_offer(quest_id, npc_id, _talked.bind(npc_id), release)   # no pages
			else:
				_temporary_message(npc, str(result["reason"]), release)   # red big at NPC - (0, 52); release after 700 ms
		_:  # "talk"
			var waiting := _service.active_quest_from(npc_id)
			var pages: Array = (_pages(waiting, "progress") + [progress_line(waiting)]) if not waiting.is_empty() \
				else QuestCatalog.npc_default_pages(npc_id)          # dialogue ?? [description ?? "Hello!"]
			_windows.dialogue.open({"speaker": speaker, "pages": pages, "on_closed": release})
			_talked(npc_id)                                          # at OPEN (Phaser :206)
	return true

func _converse(speaker: String, pages: Array, finish_label: String, release: Callable, decide: Callable) -> void:
	if pages.is_empty():
		decide.call(); return
	_windows.dialogue.open({"speaker": speaker, "pages": pages, "finish_label": finish_label,
		"on_finished": decide, "on_closed": release})

func _talked(npc_id: String) -> void:
	Services.run().record_talk(npc_id)
	service.npc_talked.emit({"npcId": npc_id})          # NpcBlip
	service.handle_event(QuestEvents.NPC_TALKED, {"npcId": npc_id})
```

The 700 ms release of a failed reoffer is a `SceneTreeTimer(0.7, process_always = true)`
(Phaser's scene timer runs during the simulation pause); practically unreachable.

### 10.6 Dialogue box and offer window in Godot

- **Process and layer.** Both live under `QuestWindows` (CanvasLayer 40: above the HUD 10, the
  prompt 9 and floating text 8, below the Shell 50, so the pause menu and end cards draw on top).
  PROCESS_MODE_ALWAYS. Hidden when closed; while open the root Control has `mouse_filter = STOP`
  (only the box; clicks elsewhere reach the world, which is paused).
- **Pause.** `QuestWindows` keeps a set of open surface ids (`npc-dialogue`, `quest-offer`) and
  holds `Services.world().set_pause_reason(WorldService.PAUSE_MODAL, true)` while the set is
  non-empty (one owner of the `modal` reason, so one window closing never unpauses another).
  `PAUSE_MODAL` is what `MusicDirector.is_menu_paused()` already watches for the 0.35 duck.
  Dialogue → offer handoff runs synchronously inside one call (close removes `npc-dialogue`, the
  callback adds `quest-offer`), as in Phaser. Other game windows (chest, inventory, crafting)
  should register with the same owner later (architect).
- **Input.** Handle keys in `_input` (before GUI and before `PlayerScript._unhandled_input`), call
  `get_viewport().set_input_as_handled()` for every key the window uses: dialogue `ui_accept`-like
  keys = physical Space, Enter, KP Enter (non-echo → `advance()`; echo swallowed), Escape (`pause` /
  `ui_cancel`) → `close()`; offer window Escape → `invoke("close")`, Enter/Space echo swallowed so a
  held key from the dialogue cannot press the focused Accept. The Shell hears Escape only in
  `_unhandled_input`, so it never opens the pause menu over a conversation. On every close call
  `player.clear_input()` (as the Shell does) so presses buffered while paused do not fire.
- **Reveal.** `_process` (ALWAYS) on real time (`Time.get_ticks_msec()`), Phaser's 30 ms interval
  becomes per-frame `revealed = min(len, floori(elapsed_ms / 1000.0 * 45))`; `advance_reveal(ms)`
  test hook. Characters by `String.length()` (all text is BMP; same as JS `slice`).
- **Cues.** Open → `GameFeel.audio_cue(&"MenuOpen")`, close → `&"MenuClose"`; buttons keep the
  scene's `ClickSfx` (`sfx.ui.click`, min interval 40 ms).
- **API.**

```gdscript
# dialogue_box.gd (group "dialogue_box")
signal opened(payload: Dictionary)                  # {"speaker", "pages"}
signal closed(payload: Dictionary)                  # {"finished": bool}
func open(request: Dictionary) -> void              # {"speaker", "pages", "finish_label"?, "on_finished"?: Callable, "on_closed"?: Callable}
func advance() -> void
func close(finished: bool = false) -> void
func is_open() -> bool
func page_index() -> int; func page_count() -> int
func visible_text() -> String; func page_label() -> String; func next_label() -> String; func hint_text() -> String
func advance_reveal(ms: float) -> void              # tests

# quest_offer_window.gd (group "quest_offer_window")
func open_offer(quest_id: String, npc_id: String, on_finished: Callable, on_closed: Callable) -> void
func open_turn_in(quest_id: String, npc_id: String, on_finished: Callable, on_closed: Callable) -> void
func invoke(action: String) -> void                 # "accept" | "decline" | "close"
func is_open() -> bool
func title_text() -> String; func description_text() -> String; func error_text() -> String
func accept_label() -> String; func decline_label() -> String
```

### 10.7 Tracker, markers, notifications, waypoint in Godot

- Tracker: rebuild on `quest_changed`, and on `world_registered` (labels); `visible` false with no
  entry; CSS sizes as §4.4 (1 CSS px = 1 game px under `apply_viewport_scale`). Objective text from
  `ControlLabels.control_label(&"menu"|&"map"|&"sprint"|&"weapon_next"|&"pause")` with Phaser's
  wrappers (`(E)`, `(E, then its tab)`, `(hold Shift)`, …). Rows by `ceil(text.length() / 40)`
  (Phaser's estimate; Godot's own wrap may differ slightly with the theme font: keep the computed
  rects so slots never overlap). The four `GhostButton`s toggle the waypoint; mouse clicks on them
  are consumed by the GUI, so no sword swing. Only the buttons take the mouse
  (`mouse_filter = IGNORE` elsewhere).
- Markers: refresh all on `quest_changed` and on `world_registered` (Phaser waits for the next
  router poll; invisible difference except during sleep). Position per frame from
  `npc.get_phaser_position()`: `Vector2(p.x, roundf(p.y - 93.28 + bob))` bottom-centre, `bob =
  sin(Time.get_ticks_msec() / 900.0 * TAU) * 3`; Label outline 6 `#081022`, bold font size per
  kind; pop tween 220 ms `TRANS_BACK EASE_OUT` from scale 0.4. Hidden for NPCs out of the tree.
  `z_index = 1` draws above the y-sorted world (Phaser sorts it with the NPC; owner question Q6).
  Name tags are not ported (world spec §5.6): the offset already includes the tag.
- Notifications: `QuestNotifications` connects to the service signals and writes §4.1 with
  `Services.feel().floating_text(player.get_centre() - Vector2(0, lift), text, color, big,
  duration_ms)`; banners with `Services.shell().show_area_title(chapter, Color("#ffd277"))` (no-op
  without the Shell); cues with `GameFeel.audio_cue`. The ability banner ("<title> learned: press
  <key>", `#9ff0c8`) belongs on `RunState.ability_learned` (abilities owner); if nobody owns it yet,
  this file adds it.
- Waypoint: `quest_waypoint.gd` resolves from Godot data: NPCs (group `npc`, `npc_definition_id`,
  in tree), camps (group `boss_camp`, `boss_id`, parent position), enemy-spawn areas
  (`WorldService.areas("enemy-spawn")`, `data.enemies[].type`, `stay_perimeter` rect centre),
  exits/doors (`world_exit.gd` parent / `door.gd` with `target_area_id`), piles (group
  `collectible`, `remaining() > 0`, `pickup_area`/parent position) and resource nodes (not
  destroyed, drop item), stations (group `crafting_station`, `station()`; workshop serves workbench),
  sites (group `restoration_site`, `object_id`). Resolve every 250 ms of gameplay time, hide while
  paused, view-inset test against the camera's visible world rect.

### 10.8 Load validation (Godot)

On (re)bind: drop records of retired ids; unknown ids, unknown stages/objectives, statuses outside
the six, `rewards_granted != (status == "completed")` or progress outside `[0, target]` →
`push_warning` and reset that record to a fresh `locked` state **[DIFF]** (Phaser rejects the whole
save; Godot saves are new and a broken record should not lose the run); `definition_version`
mismatch → `push_warning`, keep the record (no reconciler yet). Missing quests are appended as
`locked`. Then `evaluate_prerequisites()` on the next `on_world_built`.

### 10.9 Dev and test helpers

- `debug_activate(quest_id, stage_id = "")`: status `active` at that stage (default first),
  progress of that stage initialised to 0 (earlier stages' objectives at their targets), emits
  `quest_accepted {"source": "debug"}` + `quest_changed`; no prerequisite or NPC checks; no known
  facts.
- `debug_mark_completed(quest_id)`: status `completed`, `rewards_granted = true` **without**
  granting, `completed_at` set, `quest_changed`, then `evaluate_prerequisites()`.
- Keep `RunState.debug_active_quests` (restoration test).
- Optional dev launch option `--quest=<id>[:<stage>]` (`?quest=` on the web) folded into the first
  `on_world_built` (owner question Q3).

### 10.10 Tests (`godot/tests/test_quests.gd`, level-1 unless stated)

Helpers: `_quests(t)` = `t.tree.get_first_node_in_group(&"quests")`; `_dialogue(t)`,
`_offer(t)` by group; `_npc(t, instance_id)` and `_place_npc(npc, point)` as in
`test_interaction.gd` (place, lock); place the player with `t.teleport_player(centre)` and an NPC at
`centre + (40, 0)`, wait 1 step, `interaction.refresh(null)`. Use `centre = (900, 1200)` (no other
target in reach). Real-time reveal through `advance_reveal(ms)`.

| Test | Setup and action | Expected |
|---|---|---|
| `test_new_run_states` | fresh level-1, 2 steps | `RunState.quests.size() == 14` in catalog order; `a-place-to-work` `available`; `slime-basics` `active`, stage `learn-the-basics`, progress `{open-bag:0, see-crafting:0, read-journal:0, open-map:0, sprint:0, pause:0}`; the other 12 `locked`; `RunState.is_quest_active("slime-basics")` true |
| `test_elder_offer_candidate_and_marker` | place the Elder | candidate id `quest-npcs:level-1-npc-village-elder-plop:offer`, priority 90, prompt `Right-click: Talk to Village Elder Plop`; `marker_for("village-elder-plop") == "main-offer"`; Lili `""` |
| `test_offer_conversation_accept` | as above; `interaction.handle_interact()` | dialogue open, speaker `Village Elder Plop`, `page_label() == "1 / 3"`, `next_label() == "Skip  ▸▸"`; `t.tree.paused`; `has_pause_reason(&"modal")`; NPC `is_interaction_locked()`. `advance()` → whole page shown, `next_label() == "Next  ▸"`; advance through pages 2 and 3 (last label `Continue  ▸`) → dialogue closed, offer open: title `A Place to Work`, `accept_label() == "Accept quest"`, description as §6.4 example; still paused. `invoke("accept")` → `status == "active"`, stage `build-workbench`, `quest_accepted {"questId": "a-place-to-work", "source": "npc"}` once, `npc_talked {"npcId": "village-elder-plop"}`, `"village-elder-plop" in story.talked_npc_ids`, window closed, tree unpaused, NPC unlocked; marker `in-progress` |
| `test_escape_during_lines_changes_nothing` | open the offer conversation; push `pause` (Escape) | dialogue closed, offer never opened, status still `available`, talked ids empty, NPC unlocked, unpaused, no pause menu (`Services.shell()` has no open window when present) |
| `test_decline_records_talk` | reach the offer window, `invoke("decline")` | `available`; talk recorded; closed; candidate still `:offer` |
| `test_reveal_speed` | talk to Pip (`level-1-npc-red-slime-boy`, plain talk, 3 default pages of 72, 61, 51 characters) | `page_label() == "1 / 3"`, `next_label() == "Skip  ▸▸"`; `advance_reveal(1000)` → `visible_text().length() == 45`; Space (`InputEventKey` physical `KEY_SPACE`) → 72 characters, `next_label() == "Next  ▸"`; Space → page 2, 0 characters; an echo Space does nothing; on page 3 after the reveal `next_label() == "Done  ✓"`; `npc_talked {"npcId": "red-slime-boy"}` was emitted at open; Escape → closed, Pip unlocked |
| `test_talk_progress_pages` | `debug_activate("a-place-to-work")`, talk to the Elder | candidate `:talk` priority 50; pages `["A workbench is the heart of every camp. Wood is scattered all over the clearing.", "Still to do for \"A Place to Work\":\n• Craft a Workbench (40 wood) (0/1)"]`; `npc_talked` emitted at open |
| `test_stage_advance_and_turn_in` | active a-place-to-work; `handle_event("craft.completed", {"recipeId": "craft-workbench", "itemId": "workbench", "quantity": 1})` | progressed `{before 0, after 1}`; stage-completed `build-workbench`; stage `place-workbench`, progress has `place-workbench: 0`. `handle_event("furniture.placed", {"placementId": "p1", "itemId": "workbench", "mapId": "level-1", "sceneId": "", "x": 0, "y": 0})` → `view().ready_to_turn_in`; candidate `:turn-in` priority 100 prompt `Right-click: Return to Village Elder Plop`; marker `turn-in`. Converse → window title `Complete: A Place to Work`, accept label `Turn in and claim reward`; accept → `completed`, `rewards_granted`, `item_count("wood") == 20`, `learned_recipe_ids == ["craft-stone-axe", "craft-stone-pickaxe"]`, coins 50; `stone-tools` and `a-tonic-for-lili` `available` (two `quest_available`, source `condition`, in that order); `quest_completed.rewards` equals the definition's |
| `test_place_fact_counts_once` | stage `place-workbench`; same `placementId` twice | first counts, second no event; `consumed_fact_ids == {"place-workbench": ["p1"]}` |
| `test_reward_items_must_fit` | ready a-place-to-work; fill the bag (every slot a full stack of something else) | `turn_in` → `{"ok": false, "code": "reward-items", "reason": "Could not grant all reward items for quest 'a-place-to-work'."}`; window stays open with that error; still `active` and ready; no recipe learned |
| `test_collect_only_in_current_stage` | `debug_activate("stone-tools")` (stage `craft-tools`); pick up `level-1-loose-wood-04` (10 wood at (608, 576): teleport to `(608, 576) - (0, 14.56)`) | `chop-wood` absent / 0; then `debug_activate("stone-tools", "use-tools")`, pick up `level-1-loose-wood-03` ((704, 512)) → `chop-wood == 10`; payload had `quantity 10`, no `recovered` |
| `test_kill_counts_kind_only` | `debug_activate("worm-trouble", "clear-camp")` | `enemy.died {kind "worm-archer"}` → 0; three `worm-swordsman` → 3, stage done, ready; a fourth → no `quest_progressed` |
| `test_known_boss_fact_on_accept` | `defeated_boss_ids = ["orb-weaver-matron"]`; `debug_mark_completed("iron-gear")` (Matron's nest `available`); `accept("the-matrons-nest", "level-1-spider-giver")` | `completed` at once; `has_learned_ability("squash-slam")`; `has_flag("chapter-2-complete")`; coins +100; `the-old-workshop` `available` |
| `test_known_facts_skip_later_stages` | `defeated_boss_ids = ["fatty-one-eye"]`; `debug_activate("the-one-eyed-guardian")`; `craft.completed stone-spear` | stage `defeat-fatty` with `defeat-fatty == 0` (no fact applied); emitting the level-1 camp's `boss_defeated({"campId": "level-1-fatty-one-eye-camp", "bossId": "fatty-one-eye"})` → stage `verdant-gate` |
| `test_guardian_completes_on_gloop_forest_arrival` | guardian at `verdant-gate`; `t.main.travel_to("gloop-forest", "west")`, wait for arrival | `completed`; coins +100; `has_flag("chapter-1-complete")`; `beyond-the-verdant-gate` `available`; `"gloop-forest" in discovered_areas`; Mossy (`gloop-ch2-npc-mossy`) marker `main-offer` |
| `test_restoration_progresses_forge_quest` | `debug_activate("rekindle-the-forge")`; add stone 40, wood 20, iron-ore 6; call `restore()` on the site with `quest_id == "rekindle-the-forge"` (debug list empty) | flag `forge.restored`; stage `smelt`, progress `{restore-forge: 1, smelt-charcoal: 0, smelt-iron-bars: 0}`; `consumed_fact_ids["restore-forge"] == ["level-1.level-1-forge"]` |
| `test_tracker_fresh_run` | fresh run | tracker visible; heading `QUESTS · 2`; slot 1 `A Place to Work` `#ffd277` objectives `! Talk to Village Elder Plop` rect [10, 26]..[-10, 64]; slot 2 `Slime Basics` `#d9ecff`, 6 lines as §4.4, rect [10, 72]..[-10, 218]; card [16, 96]..[300, 336]; hint `Click a quest to show the way` (with keys E/M/Shift/Esc) |
| `test_tracker_order_after_accept` | accept a-place-to-work | slot 1 `A Place to Work` lines `• Craft a Workbench (40 wood)`; slot 2 `Slime Basics` |
| `test_sprint_and_pause_controls` | hold `move_right` + `sprint` 3 steps; open the Shell pause menu (if registered) | `slime-basics.sprint == 1` (fact `sprint` consumed); `pause == 1`; a second sprint edge adds nothing |
| `test_save_round_trip` | after accepting a-place-to-work: `var data := RunState.serialize()`; JSON stringify/parse through `RunState._integers`; `RunState.install(data)`; next service call | identical records (ints, `active_stage_id` String); no warnings; `is_quest_active("a-place-to-work")` |
| `test_teardown_releases_npc` | dialogue open with the Elder locked; call `quests.close_conversations()` (what `_teardown_world` calls) | NPC unlocked (`is_interaction_locked()` false), both windows closed, `has_pause_reason(&"modal")` false, tree unpaused |
| `test_sunny_basket_soft_lock` (documents the quirk, Q1) | gloop-forest; collect `gloop-ch2-sunny-basket` before accepting; `debug_mark_completed("beyond-the-verdant-gate")`; accept `sunnys-basket` | progress stays 0 and the pile is gone (`collectible_record("gloop-forest", "gloop-ch2-sunny-basket") == {"remaining": 0}`); move to `KNOWN_FAILURES` or rewrite if the owner fixes it |

### 10.11 Deferred

[OUT] journal window and abandon/retry UI (service commands are ported), reoffer reachable only
through it; minimap waypoint dot; NPC name tags; reconciliation of old definition versions; quest
failure content; escort/survival objectives; control hints (`hint.*` flags). [BLOCKED] crafting,
furniture placement, belt switching, menu windows (inventory/crafting/journal/map control ids),
enemy loot and `enemy.died`, the Matron's camp in gloop-forest.

---

## 11. Phaser → Godot mapping summary

| Phaser | Godot |
|---|---|
| `questService` module singleton, rebuilt per page | `QuestService` child "Quests" of main; state in `RunState.quests` |
| `gameEvents` + `QuestEventBridge` | `QuestEvents.emit` → `handle_event` |
| `restoreKnownFacts` sets | RunState reads (`discovered_areas`, `talked_npc_ids`, `defeated_boss_ids`, `world_flags`) |
| `storyProgress.learnRecipes / learnAbilities / setFlags`, `gameState.addCoins`, `playerInventory.transact` | `RunState.learn_recipes / learn_ability / set_flag / add_coins / add_item` (after a joint fit check) |
| `setSimulationPaused('npc-dialogue' / 'quest-npc')` | `QuestWindows` holds `WorldService.PAUSE_MODAL` |
| ModalStack Esc, capture keydown | `_input` + `set_input_as_handled`, `player.clear_input()` on close |
| `floatingText.spawn` / `showAreaTitle` / AudioEventBridge | `GameFeel.floating_text` / `Shell.show_area_title` / `GameFeel.audio_cue` |
| `NpcNameTags.setMarker` | `npc_quest_markers.gd` |
| `UniversalSceneWorldController` waypoint helpers | `quest_waypoint.gd` over groups and `WorldService.areas` |

---

## 12. Quirks (port as is unless decided otherwise)

1. Known facts apply only to the first stage on activation (§2.3): a boss defeated before a later
   `defeat-boss` stage must be defeated again; `the-matrons-nest` completes on accept if the Matron
   is already dead.
2. Only the current stage of active quests counts; earlier pickups/kills are lost (§2.4).
3. Sunny's basket can be taken before the quest and the quest can then never finish (§7.5).
4. `slime-basics` cannot be restarted after abandoning it once A Place to Work was accepted (§2.8).
5. `workbench.opened` has no listener; opening a bench never counts (§3).
6. The dialogue class comment promises `F`; only Space / Enter / KP Enter advance (§6.1).
7. Several quest toasts share one spot and overlap (§4.1).
8. Markers update only on router polls (not while paused or asleep) (§4.5); Godot refreshes on change.
9. `progressLine`'s "come back to me" branch and the `talk` marker are unreachable with this content.
10. `fail()` and `retryFailed` have no caller: no quest can fail.
11. Reward grant failure leaves the quest ready and shows a raw message in the offer window.
12. Plain talk records the talk when the box opens; offers only after Accept/Decline (Esc records
    nothing).

## 13. Open questions for the owner

| # | Question | Recommendation |
|---|---|---|
| Q1 | Sunny's basket soft-lock: keep, or make the pile appear only while `sunnys-basket` is active (a story variant on a flag the quest sets), or count a carried basket on accept? | Fix in content (variant): the port then needs nothing special |
| Q2 | Apply known facts on every stage advance (Fatty defeated early counts)? | Keep Phaser (bosses respawn; the matron case is a nice shortcut) |
| Q3 | Dev path for craft/place objectives until crafting exists: launch option `--quest=<id>[:<stage>]`, a debug key, or tests only? | Launch option + the service's `debug_*` (tests use them anyway) |
| Q4 | Let the interact button (right click) and `F` also advance the dialogue? | Add right click (it is how the talk started); keep Space/Enter |
| Q5 | Stack simultaneous quest toasts (offset each by 22 px)? | Yes, small polish; Phaser parity is overlapping text |
| Q6 | Markers above everything (`z_index 1`) or y-sorted with the NPC (hidden behind trees in front)? | `z_index 1`, like the key badge |
| Q7 | Godot load of a broken quest record: reset that quest (proposed) or reject the save like Phaser? | Reset with a warning |
