# Spec: Interaction, doors, gates, chests, beds, workbenches, story flags

Area owner: interaction (the interact button, prompt and key badge) and the interactable scene
scripts `game.interaction`, `game.door`, `game.gate`, `game.chest`, `game.bed`, `game.workbench`,
`game.story-flag`, `game.story-variant`. Binding inputs: [GODOT_MIGRATION.md](../../GODOT_MIGRATION.md),
[CONVENTIONS.md](../CONVENTIONS.md), [ARCHITECTURE.md](../ARCHITECTURE.md). Every Phaser reference
is a read-only `src/game/...` path with line numbers as of 2026-10-05.

Legend: **[IN]** = port now (Phase 2 gameplay). **[OUT]** = exists in Phaser, deferred (full UI
screens, saves, quests, furniture placement, ...); recorded so later phases know. **[QUIRK]** =
Phaser behaviour that looks unintended; port it as is unless the owner decides otherwise (§9).
**[FEET]** = a place where Phaser measures from a root that is not the feet; convert as in
[world.md §0](world.md).

Godot state this spec was written against: the committed trial (`765436d`) plus the uncommitted
world-travel work in the working tree (`godot/game/main.gd` `request_exit` / `travel_to`,
`godot/game/world/area_travel.gd`, `godot/game/autoload/run_state.gd`, `world_exit.gd` level
trigger). Those files were still changing; §8.4 says what doors need from them.

---

## 0. Phaser file map

| Concern | File |
|---|---|
| Candidate choice, prompt, key badge | `features/interaction/InteractionRouter.ts` (221 lines) |
| NPC talk provider (+ quest offers, turn-ins) | `features/interaction/QuestNpcController.ts` |
| Door / gate / chest / bed / workbench providers, script services | `features/world/UniversalSceneWorldController.ts` |
| Interact press, hold, suppression, exits, sleep and crafting entry points | `scenes/WorldScene.ts` |
| Area travel handoff (page reload) | `features/world-navigation/AreaNavigation.ts`, `world/Area.ts` |
| Door arrival points | `infrastructure/scenes/WorldSceneLoader.ts:157-175` |
| Gate unlock / chest transfer transactions | `features/progression/InventoryWorldTransaction.ts` |
| Persisted gate and chest records | `features/progression/WorldProgress.ts:535-575` |
| Story flags | `features/progression/StoryProgress.ts` |
| Sleep | `features/rest/SleepController.ts`, `features/rest/RespawnDestination.ts` |
| Chest window | `features/ui/ChestInventorySurfacePort.ts` (ported: [journal-and-chest.md](journal-and-chest.md) §2, §3.4) |
| Scene scripts | `features/scripts/{Interaction,Door,Gate,Chest,Bed,Workbench,StoryFlag,StoryVariant}Script.ts` |
| Descriptors | `features/scripts/registrations.ts` (line numbers in §3) |
| Input binding | `features/player/PlayerInputActions.ts:16` (`interact: ['Mouse2']`), `features/player/ControlLabels.ts` |

---

## 1. Coordinates [FEET]

Every distance in this spec is Euclidean (`Phaser.Math.Distance.Between`) between two old Phaser
positions:

| Who | Phaser value | Godot value |
|---|---|---|
| Player | `managedPlayer.getPosition()` (`PlayerNodePorts.ts:29-31`, body root) or `this.player.x/y` (Arcade sprite) - both the **sprite centre** | `player.get_centre()` (feet - (0, 27.56)) |
| NPC | `NpcScript.getPosition()` (`NpcScript.ts:121-123`) - the **sprite bottom-centre** | `npc.get_phaser_position()` |
| Door, gate, bed, workbench, chest | global position of the script's **parent** node (`script.get_parent().get_global_transform().position`) | `(script.get_parent() as Node2D).global_position` |

None of the object scenes in scope (`gate-verdant`, `chest-wooden`, `cave-ladder`,
`cracked-ground`, `workshop`, `forge`, the 37 bed scenes, the workbench scenes) has a
`depthAnchor`, so their converted roots are not re-anchored: the Godot `global_position` *is* the
Phaser position. Use `FeetAnchor.phaser_position(parent)` anyway (it returns `global_position`
when there is no `depth_anchor` meta) so a future re-anchored interactable stays correct.

There is **no line-of-sight test** anywhere: a target behind a wall is offered if it is within
reach [QUIRK, harmless in the current maps].

---

## 2. The interaction system

### 2.1 Pieces and per-step flow

```
WorldScene.create (WorldScene.ts:326-337)
  interactionRouter = new InteractionRouter(scene)          # prompt Text + badge Container
  questNpcController = new QuestNpcController({router, ...}); buildWorld(); questNpcController.finalize()
                                                             # registers provider 'quest-npcs'
  createPlayer() -> UniversalSceneWorldController ctor (UniversalSceneWorldController.ts:773-779)
     registers 'managed-chests', 'world-doors', 'world-gates', 'world-beds',
               'world-workbenches', 'world-restorations', 'placed-furniture'
  createGulp() (WorldScene.ts:1109-1128) registers 'gulp-spots'

every fixed step (60 Hz), only while the world is not paused (WorldScene.updateGameplay :814-886,
run from lifecycle.beforeFixedStep, PhaserSceneTreeHost.ts:97-101):
  router.setSuppressed(sleeping || furniturePlacement.active)              (:820)
  router.update(pointerSeen ? pointerWorldPosition() : undefined)          (:822)
  ... dead -> return; sleeping -> sleepController.update -> return;
  ... movement suppressed (roll/knockback) -> return; actionLocked -> return; eat hold -> return
  handleActionInput()  (:1773-1829): ... interact press -> router.handleInteract()
```

Provider registration order (matters only for pointer ties, §2.4): `quest-npcs`,
`managed-chests`, `world-doors`, `world-gates`, `world-beds`, `world-workbenches`,
`world-restorations`, `placed-furniture`, `gulp-spots`.

`register(id, provider)` returns an unregister function that also clears the current candidate
when its id starts with `"<id>:"` (`InteractionRouter.ts:72-78`). The world controller unregisters
all seven of its providers on dispose (`UniversalSceneWorldController.ts:1678-1684`).

### 2.2 Candidate contract (`InteractionRouter.ts:7-25`)

```ts
interface InteractionCandidate {
  id: string;            // "<providerId>:<key>", unique; also drives the badge pop (2.6)
  prompt: string;        // verb phrase without the key: "Open chest"
  priority: number;      // higher wins
  anchor?: () => {x, y}; // world point of the badge's bottom centre; no anchor -> no badge
  origin?: () => {x, y}; // where the pointer must be to pick it (falls back to anchor)
  secondary?: { prompt: string; execute(): boolean };  // hold action [OUT]
  execute(): boolean;    // return value is ignored by WorldScene
}
interface InteractionProvider { getCandidate(); getCandidates?() }   // getCandidates wins when present
```

Constants: `POINTER_PICK_PX = 64` (`InteractionRouter.ts:44`), `TARGET_BODY_RISE_PX = 24`
(`UniversalSceneWorldController.ts:345`), `CHEST_BADGE_RISE_PX = 56` (`:343`),
`NPC_INTERACT_DISTANCE = 96`, `NPC_BADGE_OFFSET = (30, -30)`, `NPC_BODY_RISE_PX = 24`
(`QuestNpcController.ts:12-16`).

### 2.3 Providers

Each object provider returns **at most one** candidate: the nearest of its kind within that
object's own reach (`distance <= reach && distance < nearestDistance`, first registered wins an
exact tie). The NPC provider returns **every** NPC in reach (`getCandidates`). `o` is the object
origin (§1), `p` the player centre.

| Provider | Source | Skips | Reach | Priority | Candidate id | Prompt (`prompt`) | Badge anchor | Pointer origin | [IN]/[OUT] |
|---|---|---|---|---|---|---|---|---|---|
| `quest-npcs` turn-in | `QuestNpcController.ts:133-141` | NPC out of tree (`isActive`) | 96 from NPC root | **100** | `quest-npcs:<instanceId>:turn-in` | `Return to <name>` | NPC + (30, -30) | NPC + (0, -24) | [OUT] (quests) |
| `world-gates` | `UniversalSceneWorldController.ts:962-1001` | out of tree; `isOpen` | `gate.interactRadius` (150) | **95** | `world-gates:<gateId>` | `gate.prompt` | o + (0, -badgeRise) | o + (0, -24) | [IN] |
| `world-doors` | `:919-960` | out of tree | `door.interactRadius` (96) | **90** | `world-doors:<doorId>` | `door.prompt` | o + (0, -badgeRise) | o + (0, -24) | [IN] |
| `quest-npcs` offer | `QuestNpcController.ts:142-151` | | 96 | **90** | `quest-npcs:<instanceId>:offer` | `Talk to <name>` | as above | as above | [OUT] (quests) |
| `world-restorations` | `:1038-1071` | out of tree | `site.interactRadius` | **89** | `world-restorations:<runtimeId>` | `site.prompt` | o + (0, -badgeRise) | o + (0, -24) | [OUT] (restoration spec) |
| `world-workbenches` | `:1010-1035` | out of tree | `bench.interactRadius` (90) | **88** | `world-workbenches:<runtimeId>` | `bench.prompt` | o + (0, -badgeRise) | o + (0, -24) | [IN] |
| `world-beds` | `:1097-1125` | out of tree | `bed.interactRadius` (90) | **85** | `world-beds:<runtimeId>` | `bed.prompt` | o + (0, -badgeRise) | o + (0, -24) | [IN] |
| `quest-npcs` reoffer | `QuestNpcController.ts:152-188` | | 96 | **85** | `quest-npcs:<instanceId>:reoffer` | `Resume quest with <name>` | as above | as above | [OUT] |
| `managed-chests` | `:891-917` | (no tree check) | **112** (literal) | **80** | `managed-chests:<instanceId>` | see §3.4 | o + (0, -56) | o + (0, -24) | [IN] |
| `gulp-spots` | `WorldScene.ts:1109-1128` | | spot radius | **60** | `gulp-spots:<round x>:<round y>` | `Gulp the <material>` | none (no badge) | spot | [OUT] |
| `quest-npcs` talk | `QuestNpcController.ts:189-209` | | 96 | **50** | `quest-npcs:<instanceId>:talk` | `Talk to <name>` | NPC + (30, -30) | NPC + (0, -24) | [IN] (§2.9) |
| `placed-furniture` | `:1074-1095` | furniture with its own script | 90 (literal) | **40** | `placed-furniture:<placementId>` | `Pick up` | (x, y - 72) | (x, y - 24) | [OUT] |

Notes:
- Doors and gates evaluate `anchor()`/`origin()` from the parent's **current** position each call;
  beds, benches, sites capture the origin when the candidate is built (same step, same result).
- Every provider except chests and NPCs first checks `this.playerBody` (no player, no
  candidate). The chest provider calls `managedPlayer.getPosition()`, which throws without a
  player; never reached in practice.
- The chest provider also runs `syncChestFrame` on **every** chest on every poll (§3.4), whether
  or not it is in reach.
- An NPC is registered only if `getNpcDefinition(npcDefinitionId)` exists
  (`QuestNpcController.ts:77-81`); all six level-1 NPCs have one.
- `<name>` = `NpcDefinition.displayName` (`content/npcs/NpcDefinitions.ts`): Village Elder Plop,
  Mossy (`level-1-spider-giver`), Lili, Pip (`red-slime-boy`), Sunny (`yellow-blond-slime-girl`),
  Lily the Fishergirl. Fallback: the definition id.
- The NPC `instanceId` is the authored instance id (`level-1-npc-lili`, ...), the same string as
  Godot's `npc.get_instance_id_key()` (body meta `instance_id`).
- `game.interaction` scripts are **never** offered: no provider looks for them (§3.1).

### 2.4 Choosing one candidate (`InteractionRouter.ts:90-107`, `:205-221`)

```gdscript
func choose(candidates: Array[Dictionary], pointer: Variant) -> Dictionary:
	var best := {}
	if pointer is Vector2:                       # only after the pointer was seen (2.7)
		var best_distance := POINTER_PICK_PX      # 64
		for c in candidates:                      # provider order, then provider's own order
			var at = c.origin.call() if c.has("origin") else (c.anchor.call() if c.has("anchor") else null)
			if at == null: continue
			var d: float = (at as Vector2).distance_to(pointer)
			if d <= best_distance:                # '<=': a later candidate wins an exact tie
				best = c; best_distance = d
	if best.is_empty():
		for c in candidates:
			if not best.is_empty() and (c.priority < best.priority \
					or (c.priority == best.priority and c.id > best.id)):
				continue
			best = c                              # equal priority: the SMALLER id wins
	return best
```

- The pointer pick ignores priority: pointing within 64 px of an NPC's body picks the NPC even
  when a door (90) is also in reach.
- **[QUIRK] NPC ties are decided by id, not distance.** `getCandidates()` hands every NPC in reach
  to the router, and two NPCs of the same priority are separated by `id` comparison (string `>`).
  Two "talk" NPCs in reach: the alphabetically smaller instance id wins even if it is farther
  (`quest-npcs:level-1-npc-lili:talk` beats `quest-npcs:level-1-npc-red-slime-boy:talk`). The
  "highest priority, then nearest" sort in `QuestNpcController.inReach` (`:127`) only affects
  `getCandidate()`, which the router never calls because `getCandidates` exists.
  Level-1 talk ids in winning order: fisherman-slime < lili < mossy-scout < red-slime-boy <
  village-elder-plop < yellow-blond-slime-girl.
- Across kinds, priority wins regardless of distance (a door 85 px away beats a bed 10 px away).
- Ties between object kinds of equal priority (door 90 vs quest offer 90) go to the smaller id:
  `quest-npcs:...` < `world-doors:...`.

### 2.5 The prompt (`InteractionRouter.ts:27-31, 59-66, 105, 199-201`)

- Text: `"<verb>: <prompt>"` with `<verb> = controlVerb('interact')` = `"Right-click"`
  (`ControlLabels.ts:19-21, 72-75`: code `Mouse2` -> "Right click" -> "Right-click"). With a
  secondary action: `"<main>     Hold: <secondary.prompt>"` (5 spaces) [OUT].
  Examples: `Right-click: Enter house`, `Right-click: Open chest`, `Right-click: Talk to Lili`.
  Godot addition: a mouse control scheme names its order button instead ("Click: Open chest";
  [../MOUSE_CONTROLS.md](../MOUSE_CONTROLS.md)).
- Style: Phaser Text, font `Trebuchet MS, Segoe UI Variable, sans-serif` 14 px, colour
  `#e7fff5`, background `#101a31cc` (alpha 0.8), padding left/right 12, top/bottom 7, origin
  (0.5, 0.5), `scrollFactor 0`, depth 250, drawn by the **UI camera** (zoom 1, never faded:
  `WorldScene.syncCameraLayers :1550-1572` puts scroll-factor-0 objects on it).
- Position: centre at `(viewport.width / 2, viewport.height - 42)`; re-placed on resize.
- Shown whenever `update` picked a candidate (`setText(...).setVisible(!!best)`).
- Hidden: no candidate; `setSuppressed(true)` (sleeping, placing furniture); its provider
  unregistered; router destroyed.
- **Not** hidden while paused (modal window, hit-stop: `update` simply stops running, so the last
  text stays), while the player is dead (`update` runs before the dead check) [QUIRK], or during
  the 320 ms leave fade of a door/exit (UI camera is not faded).

### 2.6 The key badge (`InteractionRouter.ts:33-35, 145-197`)

World-space Container at depth `DEPTH_BANDS['overhead-artwork']` (above every world-sorted
sprite, below `reveal-effects`; runtime spec §5.3 maps the band to `z_index = 1`). It is drawn by
the main camera, so it zooms with the world and fades with the leave/arrive fades.

Geometry in local coordinates, origin = **bottom centre** (`BADGE_SIZE = 22`, `half = 11`):

| Part | Phaser call | Value |
|---|---|---|
| Shadow | `fillStyle(0x000000, 0.35).fillRoundedRect(-10, -20, 22, 22, 5)` | 1 px right, 2 px down |
| Plate | `fillStyle(0x101a31, 0.92).fillRoundedRect(-11, -22, 22, 22, 5)` | |
| Border | `lineStyle(2, 0x9dffc8, 1).strokeRoundedRect(-11, -22, 22, 22, 5)` | 2 px, centred on the edge |
| Glyph (interact is a mouse button) | `drawMouseGlyph(centerY = -11, button = 2)` (`:167-182`) | mouse 11 x 15 at left -5.5, top -18.5 |
| - lit right button | `fillStyle(0x9dffc8).fillRoundedRect(0, -18.5, 5.5, 6.75, {tr: 4})` | top-right corner radius 4 |
| - outline | `lineStyle(1.5, 0xe7fff5).strokeRoundedRect(-5.5, -18.5, 11, 15, 4)` | |
| - divider lines | `(0, -18.5)-(0, -11.75)` and `(-5.5, -11.75)-(5.5, -11.75)` | button split |

(A keyboard binding would instead show the key label: bold 14 px `#e7fff5` text centred at
(0, -11). Not reachable with the current binding.)

Per `update` (`:184-197`):

```gdscript
var a = candidate.anchor.call()                       # no anchor -> badge.visible = false
var bob := sin(Time.get_ticks_msec() / 1400.0 * TAU) * 2.5    # BADGE_BOB_PERIOD_MS, BADGE_BOB_PX
badge.global_position = Vector2(floor(a.x + 0.5), floor(a.y + bob + 0.5))   # Math.round
badge.visible = true
if candidate.id != previous_id:                       # new target (also after "none")
	kill old tween; badge.scale = Vector2(0.5, 0.5); badge.modulate.a = 0.0
	tween scale -> 1, alpha -> 1, 140 ms, TRANS_BACK + EASE_OUT ('Back.Out', overshoot 1.70158)
```

`scene.time.now` is real time; the position only changes when `update` runs (fixed steps, not
while paused). The pop tween is a scene tween and is frozen during hit-stop
(`tweens.timeScale = 0`). `badgeRise` (per script, §3) is therefore "how many world pixels above
the target origin the badge's bottom edge floats"; the badge's top is 22 px higher.

### 2.7 The interact press

- Binding: `interact = Mouse2` (right mouse button) (`PlayerInputActions.ts:16`). The browser
  context menu is disabled over the game (`WorldScene.ts:2056-2057`). Godot: action `interact` =
  `InputEventMouseButton button_index 2` already in `project.godot`.
- Buffered like every player action: `consumeActionPress` (`PlayerScript.ts:170-176`) returns
  true only if the press is at most `input.bufferMs` = **150** ms old on the simulation clock;
  an older press is dropped, never fired late.
- Order inside `handleActionInput` (`WorldScene.ts:1773-1829`), first match ends the step:
  1. furniture placement mode: interact cancels placement (ported: [furniture.md](furniture.md) §5);
  2. weapon wheel switching (no early return) (ported with the belt);
  3. `updateInteractHold()` (secondary hold, `INTERACT_HOLD_MS = 450`, `:151, :1836-1853`) (ported
     with furniture: a placed bench's "Hold: Pick up");
  4. **interact**: if consumed -> `if router.hasCandidate(): hints.learn('interact'); if
     hasSecondary: start hold else router.handleInteract()`; **return true even without a
     candidate**;
  5. abilities (jump, dodge, stretch-lash, squash-slam, teleport), 6. attack, 7. eat.
  So interact is checked **before dodge and attack**. Returning true skips this step's
  `playerController.move()` (velocity keeps last step's value once) [QUIRK, invisible].
- When the press is *not* consumed (it waits in the buffer, and dies after 150 ms): paused; dead;
  sleeping (the sleep controller consumes it as a wake input, §3.5); movement suppressed (roll,
  knockback); `actionLocked` (weapon swing: `CombatController.ts:254-267` locks for the whole
  swing; eat/ability animations); eat wheel open.
- `handleInteract()` executes the candidate chosen by `update` earlier in the **same** step.
- No cooldown exists. Repeated presses re-execute (a locked gate shows its message every time).

### 2.8 Pause, suppression, travel

| State | `update` runs? | Prompt / badge | Press handled? |
|---|---|---|---|
| Modal window open (chest, crafting, dialogue, inventory, menus) | no (tree paused) | frozen, still visible | no; `setPaused(true)` clears input (`UniversalSceneWorldController.ts:789-793`) |
| Hit-stop | no (`advanceFrame(0)`) | frozen | buffered (sim clock frozen) |
| Sleeping | yes, but suppressed | hidden | consumed as wake input |
| Dead | yes | visible [QUIRK] | no |
| Door / exit leave fade (320 ms, `transitioning`) | yes | prompt visible, badge fades | yes; a door returns `ignored`, other interactions still run |

### 2.9 NPC talk (`QuestNpcController.ts`)

- Registration: `UniversalSceneWorldController.registerNpcPlacement` (`:1962-1987`) builds an
  `NpcActorHandle {instanceId, npcId, isActive = script.isActive() (in tree), getPosition,
  acquireInteractionLock}` for each `NpcScript` at mount and passes it to
  `QuestNpcController.register`.
- Candidate kind is chosen per NPC by quest state: turn-in (100) > offer (90) > reoffer (85) >
  talk (50). Prompt text is the same for offer and talk ("Talk to <name>"), only the priority
  differs; turn-in is "Return to <name>", reoffer "Resume quest with <name>". **Ported with the
  quests** (2026-10-05): the controller asks the quest service (group `quests`,
  `npc_candidate(npc_id)`) for the kind and priority and runs `talk_to(npc, kind)`
  ([quests.md](quests.md) §5, §10.5).
- Talk execute (`:193-208`):
  ```
  pages = active npc quest waiting ? quest.dialogue.progress + progressLine [OUT]
        : definition.dialogue ?? [definition.description ?? 'Hello!']
  release = actor.acquireInteractionLock()        # NPC velocity 0, plays idle, emits interaction_lock_changed
  dialogue.open({speaker: name, pages, onClosed: release})   # modal: pauses the game [OUT screen]
  talked(npcId): storyProgress.recordTalk(npcId); gameEvents 'npc.talked' {npcId}   # at OPEN, not close
  return true
  ```
- The dialogue box (`NpcDialogueSurfacePort.ts`): reveal 45 chars/s, Space/Enter skip or
  advance, Esc closes, pauses gameplay while open. Ported with the quests:
  `game/ui/screens/dialogue_box.gd` (also the interact button advances, owner decision Q4).
- Quest markers over NPCs and the `npc.talked` listeners: ported with the quests
  (`game/ui/npc_quest_markers.gd`, `game/quests/quest_service.gd`).

### 2.10 Control hints [OUT]

`ControlHints` shows "interact" while `router.hasCandidate()` (`WorldScene.ts:580`) and learns it
on the first press with a candidate (flag `hint.interact`).

---

## 3. Scene scripts

General Phaser rules shared by all of them: `ScriptNode` subclasses; `service(id)` throws when
the service is missing (`runtime/scene/scripts/ScriptNode.ts:55-58`); properties are read once in
the constructor; the converter writes only authored properties, so **every GDScript default
below must equal the TS fallback** (runtime spec §3, line 94).

### 3.1 `game.interaction` (`InteractionScript.ts`, descriptor `registrations.ts:444-459`) [OUT]

| Property | TS read | Fallback |
|---|---|---|
| `interactionId` | string | `''` |
| `instanceId` | string | `''` |
| `prompt` | string | `'Interact'` |
| `priority` | finite number, `Math.trunc` | `0` |
| `action` | raw JSON, passed through untouched | `{}` |

Signal `interaction_resolved` (payload `InteractionResult`). Method
`requestInteraction(actorNodeId)` builds `{interactionId, instanceId, actorNodeId, action}` and
calls the `world.interaction` service's `execute`, falling back to
`{status: 'blocked', message: 'Interaction unavailable'}`; emits and returns the result.

**Action kinds: none.** The script defines no action vocabulary; `action` is opaque JSON handed to
`WorldInteractionPort.execute`. Nothing in the game implements or provides
`WORLD_INTERACTION_SERVICE` (`'world.interaction'`), so an instance would throw in `_enter_tree`
("requires unavailable service"). No provider offers it to the router. **No authored scene uses
it** (0 instances); the only use is a unit test fixture with
`action: {type: 'unlock-gate', itemId: 'green-key'}` and a fake service
(`scripts/tests/scene-integration/object-script-foundation.test.mjs:585-614`). [QUIRK: dead
feature.] Port decision: do **not** create `game/scripts/interaction.gd`; it stays on
`unported_script.gd` (CONVENTIONS: add a file only when porting a used script).

### 3.2 `game.door` (`DoorScript.ts`, descriptor `registrations.ts:481-497`) [IN]

| Property | TS read (`DoorScript.ts:29-40`) | Fallback | Godot export |
|---|---|---|---|
| `mapId` | string | `''` | `map_id: String = ""` |
| `doorId` | string | `''` | `door_id: String = ""` |
| `targetAreaId` | string | `''` | `target_area_id: String = ""` |
| `targetDoorId` | string | `''` | `target_door_id: String = ""` |
| `prompt` | string (empty allowed) | `'Use door'` | `prompt: String = "Use door"` |
| `interactRadius` | finite and `> 0` | `96` | `interact_radius: float = 96.0` (sanitise) |
| `badgeRise` | finite (any sign) | `56` | `badge_rise: float = 56.0` (sanitise) |

No signals, no handlers, no services. The door is a data holder; the world controller does the
work:

- **Reach / candidate**: §2.3 row `world-doors` (priority 90, id `world-doors:<doorId>`).
- **Execute** (`UniversalSceneWorldController.ts:947-958`): `requestExit({mapId, exitId: doorId,
  targetAreaId, entry: '', targetDoorId, actorNodeId: playerBody.runtimeId, gate: {}})`, returns
  `status === 'queued'` (ignored).
- **`WorldScene.requestAuthoredExit`** (`WorldScene.ts:1018-1066`):
  1. `mapId !== loaded map` -> `ignored`; `transitioning` -> `ignored`.
  2. `entry = targetDoorId ? {entryDoor: targetDoorId} : isDirection(entry) ? {entryEdge} :
     undefined`; no `targetAreaId` or no entry -> `blocked "Navigation unavailable"` (silent).
  3. `gate` `{}` passes (§3.3 for non-empty gates).
  4. `transitionTo(targetAreaId, entry)` -> `queued`.
- **`transitionTo` / `leaveAreaThen`** (`:1005-1016`): `transitioning = true`; stop the player once
  (it can walk again during the fade [QUIRK]); `fadeOutMusic(320)`;
  `cameras.main.fadeOut(320, 11, 16, 32)` (#0b1020, world camera only); after 320 ms
  `navigateToArea(areaId, entry, false)`.
- **How the target world loads** (`AreaNavigation.ts:68-124`): the run is serialised into a
  session-storage handoff `{version 1, kind 'area', mapId, entryDoor, data}` (data = full save with
  `location` = the player's position in the **old** map, `capturePlayerLocation :1515-1523`), the
  URL gets `?area=<id>&door=<doorId>&t=<now>`, and the page **reloads**. `MapLoadScene` loads
  `world.<mapId>` (area ids without an `AREAS` entry fall back to `mapId = areaId`,
  `world/Area.ts:76-87`), `WorldScene.init` stores `entryDoor` (`:280-294`), `create` installs the
  handoff, fades in 400 ms (#0b1020), shows the area title card [OUT] and writes a recovery save
  [OUT].
- **Where the player appears** (`createPlayer :1437-1446`, `getEntryAnchor :1607-1614`,
  `findSpawnPoint :1616-1638`):
  1. a restored location is used only if its `mapId` equals the new map - never the case after a
     door (the handoff holds the old map's location);
  2. anchor = `doors[entryDoor]` ?? `entries[entryEdge]` ?? `player-spawn` marker;
     `doors[id]` = global position of the target door's parent's child **named `arrival`**, or of
     the parent itself, each coordinate `Math.round`ed (`WorldSceneLoader.ts:157-175`; duplicate
     door ids in one world throw);
  3. **always** `findSpawnPoint(anchor)`: the centre of the first non-solid tile in rings around
     the anchor's tile, so the player lands on a **tile centre**, not on the arrival node
     [QUIRK]. Values per door in §5.2.
  4. An unknown `targetDoorId` silently falls back to the spawn marker.
- **Facing after arrival**: no restored location, so `applyFacing` is skipped and the
  `PlayerController` default facing `(0, 1)` = down applies (`PlayerController.ts:28`); the slime
  idles.
- **Camera**: interiors (`slime-home`, `mushroom-home`, `gloop-hut`) are `cameraMode: "fixed"`
  (world spec 4.6); caverns follow.
- Arriving next to a door does **not** block re-using it: e.g. back in level-1 the player stands
  35.4 px from `home-door` and the prompt shows at once (§5.2).

### 3.3 `game.gate` (`GateScript.ts`, descriptor `registrations.ts:499-524`) [IN]

| Property | TS read (`GateScript.ts:51-67`) | Fallback | Godot export |
|---|---|---|---|
| `mapId` | string | `''` | `map_id: String = ""` |
| `gateId` | string | `''` | `gate_id: String = ""` |
| `requiredItemId` | string | `''` | `required_item_id: String = ""` |
| `consumeOnUnlock` | `!== false` | `true` | `consume_on_unlock: bool = true` |
| `prompt` | string | `'Unlock gate'` | `prompt: String = "Unlock gate"` |
| `lockedPrompt` | string, **never used** [QUIRK] | `'Locked'` | `locked_prompt: String = "Locked"` |
| `lockedMessage` | string | `'The gate is locked.'` | `locked_message: String = "The gate is locked."` |
| `unlockedMessage` | string | `'The gate unlocks!'` | `unlocked_message: String = "The gate unlocks!"` |
| `interactRadius` | finite | `150` | `interact_radius: float = 150.0` |
| `badgeRise` | finite | `120` | `badge_rise: float = 120.0` |
| `closedFrame` | finite | `0` | `closed_frame: int = 0` |
| `openFrame` | finite | `1` | `open_frame: int = 1` |
| `visual` | reference (Sprite2D, required) | | `visual: Sprite2D` |
| `doors` | reference (StaticBody2D, required) | | `doors: StaticBody2D` |

Signal `opened` payload `{gateId}` (no listener in any authored scene). Handler `open` (payload
ignored). Service `world.gate-lock` = `{isUnlocked(mapId, gateId)}` ->
`WorldProgress.isGateUnlocked` (`UniversalSceneWorldController.ts:668-670`).

Behaviour:
- `_enter_tree` (`:73-77`): `apply(isUnlocked(mapId, gateId))`; `_ready` (`:79-82`):
  `apply(opened)` again (siblings ready).
- `apply(open)` (`:95-101`): `opened = open`; `visual.frame = open ? openFrame : closedFrame`;
  `doors.collisionEnabled = !open`. Phaser's setter only ever *disables* the body
  (`PhysicsBody2DNode.ts:81-85`, `if (!value) body.enable = false`) [QUIRK, never hit: gates only
  open]. The pillars stay solid. The door body is on the world layer (1), so a closed gate also
  blocks enemy sight.
- `open()` (`:89-93`): no-op when already open; `apply(true)`; emit `opened {gateId}`. **Does
  not persist anything** - plates and bells open gates for the current visit only (§3.3.2).
- Candidate: not offered while open (§2.3). Prompt is always `prompt`, even without the key.
- Execute (`UniversalSceneWorldController.ts:984-999`):
  ```
  result = transaction.unlockGate({mapId, gateId, requiredItemId, consumeOnUnlock})
  at = (o.x, o.y - badgeRise)
  if result in ['unlocked', 'already-unlocked']:
      gate.open(); showMessage(at, unlockedMessage, 'green', important=true)
  else:
      showMessage(at, result == 'missing-item' ? lockedMessage : 'The gate will not budge.', 'white', true)
  return true
  ```
- `unlockGate` (`InventoryWorldTransaction.ts:83-102`): already unlocked -> `'already-unlocked'`;
  `inventory.count(requiredItemId) < 1` -> `'missing-item'`; else one atomic commit of "remove 1
  key if `consumeOnUnlock`" + "append `gateId` to `mapStates[mapId].unlockedGateIds`"; a failed
  commit rolls both back -> `'failed'`.
- `showMessage(x, y, text, color, important)` = `floatingText.spawn` (`important` = big: 22 px,
  900 ms in the Godot GameFeel port).

#### 3.3.1 Shared record with gated world exits

`game.world-exit` has a `gate` JSON property `{id, requiredItemId, consumeOnUnlock,
lockedMessage}`. `requestAuthoredExit` (`WorldScene.ts:1027-1063`) checks the same record
`worldProgress.isGateUnlocked(mapId, gate.id)`; without the key it shows `lockedMessage`
(throttled 900 ms, at player - (0, 42), white big) and blocks; with the key it unlocks through
the same transaction, shows the hard-coded `"The Verdant Gate unlocks!"` (green big) and travels.
Level-1's gate object and its exit use the same id `level-1-east-verdant-gate`, so unlocking
either one opens both (the object on its next `_enter_tree`). The Godot `main._pass_gate` already
ports the exit half.

#### 3.3.2 Plates and bells (callers of `open`)

`PressurePlateScript.openLinkedGates` (`PressurePlateScript.ts:88-98`) and `LashBellScript`
(`:121`) walk the whole tree and call `open()` on every `GateScript` whose `gateId` equals their
own `gateId` property (no scene connection). Gates parked in a story variant are not found.
[QUIRK] Because `open()` does not persist, a plate-opened gate is closed again the next time the
world loads (the plate is up again too). [QUIRK] The plate/bell gates still have
`requiredItemId: "green-key"`, so a player holding a green key can unlock (and permanently open)
them by interacting, spending the key (§5.3).

### 3.4 `game.chest` (`ChestScript.ts`, descriptor `registrations.ts:239-256`) [IN domain, OUT screen]

| Property | TS read | Fallback | Godot export |
|---|---|---|---|
| `mapId` | string | `''` | `map_id: String = ""` |
| `instanceId` | string | `''` | `instance_id: String = ""` |
| `initialContents` | object of positive safe integers (`recordOfPositiveIntegers :32-37`) | `{}` | `initial_contents: Dictionary = {}` |

Signals (`registrations.ts:250-255`) and their only listeners (connections in
`objects/chest-wooden.scene.json`, converted to `play_cue`):

| Signal | Payload (Phaser) | Godot payload | Listener |
|---|---|---|---|
| `guard_blocked` | `{instanceId}` | `{"instanceId"}` | `LockedSfx.play` (`sfx.world.chest-locked`, `minIntervalMs 400`) |
| `open_requested` | the `ChestViewModel` | `{"mapId", "instanceId", "contents"}` | `OpenSfx.play` (`chest-open`) |
| `stack_transferred` | `{itemId, moved}` | `{"itemId", "moved"}` | `TakeSfx.play` (`pickup.generic`, pitch randomness 0.06) |
| `closed` | `{instanceId}` | `{"instanceId"}` | `CloseSfx.play` (`chest-close`) |

Services (`UniversalSceneWorldController.ts:607-613`):
- `world.chest-transaction`: `ensureInitialized(mapId, instanceId, contents)` ->
  `WorldProgress.ensureChestInitialized` (creates the record only when none exists, keeping
  integer counts > 0); `getRemaining(mapId, instanceId)` -> a copy of
  `mapStates[mapId].chests[instanceId].remaining` or `{}`; `transferStack(mapId, instanceId,
  itemId)` -> `InventoryWorldTransaction.transferChestStack`.
- `world.chest-guard`: `isLocked(instanceId)` = any boss camp's
  `isChestGuarded(instanceId)` = `liveBoss && guardedChestInstanceId === instanceId`
  (`BossCampScript.ts:143-146`). Fatty's camp guards `level-1-fatty-guarded-chest`, the matron's
  `gloop-matron-guarded-chest`. Godot: `boss_camp.gd.is_chest_guarded()` in group `boss_camp`.
- `ui.chest-view`: the chest window. Godot: `game/ui/screens/chest_window.gd`, the first node of
  group `chest_window` (`open_chest(chest)`, `close_for(instance_id)`).

Script behaviour (`ChestScript.ts:53-96`):
- `_enter_tree`: `ensureInitialized(mapId, instanceId, initialContents)`; on leaving the tree the
  view is closed for this instance.
- `remaining` = record copy; `empty` = no keys.
- `requestOpen()`: guarded -> emit `guard_blocked {instanceId}`, return `'guarded'`; else build
  the model `{mapId, instanceId, contents: remaining, transferStack, close}`, emit
  `open_requested`, `view.open(model)`, return `'opened'`. An **empty** chest still opens.
- `transferStack(itemId)`: `moved = transferChestStack(...)`; if `moved > 0` emit
  `stack_transferred {itemId, moved}`; return `moved`.
- `close()`: `view.close(instanceId)`; emit `closed {instanceId}`.

`transferChestStack` (`InventoryWorldTransaction.ts:24-49`): `available = remaining[itemId]`;
binary search for the largest `count <= available` that `inventory.prepareTransaction([],
[{itemId, count}])` accepts (stack into non-full stacks of that item first, then new slots up to
`maxSlots`, each slot capped at `inventory.maxStackByItem[itemId]`; an item without a definition
never fits); commit inventory + chest record atomically; return the count (0 on no room or
failure).

Provider (`UniversalSceneWorldController.ts:891-917`):
- Every poll: `syncChestFrame` on **every** chest: first `Sprite2D` under the chest root
  (`Visual`, `hframes 2`) gets `frame = empty ? 1 : 0` (`:2208-2211`). Because polls stop while
  paused, a chest emptied in its window shows the empty frame on the first step after the window
  closes.
- Reach 112 from the chest root; priority 80; id `managed-chests:<instanceId>`.
- Prompt: `locked = !empty && isChestLocked(instanceId)`; `locked ? 'Chest locked by Fatty One
  Eye' : empty ? 'Inspect empty chest' : 'Open chest'`. [QUIRK] The Fatty text is hard-coded and
  also shows for the matron's chest.
- Execute: `requestOpen()`; on `'guarded'` show `'Fatty One Eye is guarding this chest!'` at
  `(o.x, o.y - 48)`, white, important. Returns true. [QUIRK] An empty guarded chest prompts
  "Inspect empty chest" but the press reports the guard.

Chest window (`ChestInventorySurfacePort.ts`; ported with [journal-and-chest.md](journal-and-chest.md),
which holds the full behaviour; Godot `chest.gd` leaves the tree silently, owner decision K4): opening pauses
gameplay (`setChestPaused`) and opens modal `chest-inventory` (Esc closes); list of
`"<name> ×<count>"` entries; intents `select-item {index}`, `take-selected-stack {index}` (right
click on an entry), `take-stack` (button, selected entry), `close`; status
`"Moved <n> × <name>"` / `"No inventory space for that item."`; closing via the window calls
`model.close()` -> `ChestScript.close()` -> `closed` (CloseSfx).

### 3.5 `game.bed` (`BedScript.ts`, descriptor `registrations.ts:701-715`) [IN]

| Property | TS read (`BedScript.ts:32-57`) | Fallback | Godot export |
|---|---|---|---|
| `prompt` | non-empty string | `'Sleep'` | `prompt: String = "Sleep"` |
| `interactRadius` | finite `> 0` | `90` | `interact_radius: float = 90.0` |
| `badgeRise` | finite | `70` | `badge_rise: float = 70.0` |
| `sleepPoint` | `[x, y]` finite, local to the bed root | `(0, -30)` | `sleep_point: Vector2 = Vector2(0, -30)` |
| `wakePoint` | `[x, y]` finite, local to the bed root | `(0, 28)` | `wake_point: Vector2 = Vector2(0, 28)` |

No signals, handlers or services. Typical authored values (37 bed object scenes): prompt
`"Sleep"` (all), `interactRadius` 96.25-133.99 (straw nest 102.625), `badgeRise` 89-181.16,
`sleepPoint.y` -96.6 to -45.9, `wakePoint` always `(x, 16)`.

Candidate: §2.3 `world-beds` (priority 85). Execute (`UniversalSceneWorldController.ts:1119-1123`):
`requestSleep({bedId, sleepPoint: o + sleepPoint, wakePoint: o + wakePoint})`.
`bedId` (`:1128-1141`) = the persistence key of the nearest authored instance above the script
(`provenance.persistenceKey ?? authoredInstanceId`, e.g. `world.slime-home.west-bed`), or
`placed-furniture:<placementId>` for placed beds [OUT].

`WorldScene.requestSleep` (`:1287-1290`) refuses when paused, transitioning, `actionLocked`, dead
or already asleep. `SleepController` (`features/rest/SleepController.ts`):

```
sleep(request):                                 # :74-93
  startedAt = now (sim); pendingHeal = 0; stopPlayerMotion; setActionLocked(true)
  teleport player to wakePoint                  # the body lies in FRONT of the bed
  art offset = sleepPoint - wakePoint           # only the picture moves onto the mattress
  phase = dozing; phaseEndsAt = now + duration('doze') (1000 ms); play 'doze' (restart)
                                                # Godot: face(DOWN) first; doze-down / sleep-down
                                                # face the viewer only (top-down art, 2026-10-05)
  nextZzzAt = phaseEndsAt
  onFellAsleep: respawn point = {areaId, mapId, x: round(wake.x), y: round(wake.y), bedId}
                floating "Respawn point set" cyan small at (sleep.x, sleep.y - 48)
update(deltaMs) every step while sleeping (WorldScene :848-853 replaces all player control):
  wake = consumeWakeInput()                     # any of interact, attack, jump, dodge, stretch-lash,
                                                # squash-slam, teleport, eat pressed, or a held
                                                # move direction; presses are consumed (drained) always
  if wake and now - startedAt >= 400: wake('input'); return       # WAKE_INPUT_GRACE_MS
  dozing and now >= phaseEndsAt -> phase sleeping, play 'sleep' (loop, 2000 ms), 'player.sleep' {asleep:true}
  sleeping: heal 2 HP/s (rest.sleepHpRegenPerSec), whole points only, fraction carried;
            at full HP once: 'player.rested', "Fully rested" green small at sleep - (0, 36)
            every 900 ms from the end of the doze: a 'z' (12-18 px bold #e7fff5, stroke #101a31 3)
            at sleep + (14, -24), tween +18/-38 over 1400 ms Sine.Out, alpha 0->1 yoyo 700 ms
wake(reason):                                    # 'input' | 'damage' (onPlayerHit) | 'death' | 'teardown'
  art offset 0; if was sleeping: 'player.sleep' {asleep:false}
  teardown: stop here; else teleport to wakePoint, unlock, play idle (not on death)
```

While sleeping the router is suppressed (no prompt, no badge). Respawning at the bed after death
(`planRespawn`, `RespawnDestination.ts`, `WorldScene.respawnPlayer :1942-1980`, may travel to the
bed's world) is [OUT] here (player spec owns respawn; the Godot trial respawns at the spawn).

### 3.6 `game.workbench` (`WorkbenchScript.ts`, descriptor `registrations.ts:717-731`) [IN]

| Property | TS read (`WorkbenchScript.ts:29-41`) | Fallback | Godot export |
|---|---|---|---|
| `prompt` | non-empty string | `'Use workbench'` | `prompt: String = "Use workbench"` |
| `recipeContext` | a `CraftingStation` other than `'portable'` (`workbench`, `workshop`, `forge`, `kitchen`) | `'workbench'` | `recipe_context: String = "workbench"` |
| `tier` | integer `>= 1` | `1` | `tier: int = 1` |
| `interactRadius` | finite `> 0` | `90` | `interact_radius: float = 90.0` |
| `badgeRise` | finite | `80` | `badge_rise: float = 80.0` |

`site = {station, tier}`. No signals or handlers. Candidate: §2.3 (priority 88; placed benches
get a "Hold: Pick up" secondary [OUT]). Execute: `openCraftingStation(site)`
(`WorldScene.ts:1279-1285`): refuses when paused or the crafting or inventory window is open;
else opens the crafting window for the site and emits `workbench.opened {mapId, context}`. Ported
with crafting (2026-10-05, [crafting.md](crafting.md) §4.1): `MenuWindows.open_station(site)`
and the InteractionController signal `workbench_opened` (no quest listens to it). Authored instances: workshop station "Use the Workshop" (workshop, tier
1, r 150, rise 150), forge station "Use the Forge" (forge, tier 1, r 130, rise 130), interior
benches "Use workbench" (r 90, rise 76-76.85). Placeable workbench items [OUT].

### 3.7 `game.story-flag` (`StoryFlagScript.ts`, descriptor `registrations.ts:691-699`) [IN]

| Property | Fallback | Godot export |
|---|---|---|
| `flagId` | `''` | `flag_id: String = ""` |

Handler `set` (payload ignored, `:30-32`): `if flagId: storyFlags.setFlags([flagId])`. No signal.
Service `world.story-flags` = `{setFlags, hasFlag}` -> `storyProgress.setFlags / hasFlag`
(`UniversalSceneWorldController.ts:664-667`). The converter renames the handler `set` -> `on_set`
(`scripts/godot/lib/scene.mjs:40`; `set` would override `Object.set`). One instance:
playground `end-card-flag` (`playground-end-card-test`), connected from the
`playground-end-card-plate` plate's `pressed` (the end card that reads it is [OUT]).

### 3.8 `game.story-variant` (`StoryVariantScript.ts`, descriptor `registrations.ts:635-650`) [IN]

| Property | Fallback | Godot export |
|---|---|---|
| `flagId` | `''` | `flag_id: String = ""` |
| `whenSet` | optional node reference | `when_set: Node` |
| `whenUnset` | optional node reference | `when_unset: Node` |

Signal `switched` payload `{flagId, set}` (no listener in any authored scene); handler `set`
(-> `on_set`). Behaviour (`:27-97`):

- `_ready`: `apply()`. `_process` (every frame while not paused): `if flagIsSet() !== shown:
  apply()` - it follows flags set by anything (quests, cracked ground, loads).
- `flagIsSet()` = `flagId != '' && port.hasFlag(flagId)`.
- `apply()`: `shown = set`; the inactive subtree, if in the tree, is **removed from its parent**
  and remembered with that parent ("parked"); the active one, if parked, is re-added with
  `parent.add_child` (appended last). Then emit `switched {flagId, set}` - also on the first
  `_ready` apply.
- `setFlag()` (the `set` handler): no-op if no flag, no port or already set; else
  `setFlags([flagId])` and `apply()`.
- `_exit_tree`: `queue_free` every parked subtree (the tree no longer owns them).
- Phaser removals are queued mutations, flushed at the next boundary. When the world mounts,
  `registerInteractables` (`UniversalSceneWorldController.ts:1789-1806`) runs **before** that
  flush, so doors/benches/beds in both variants are registered; the providers' `is_inside_tree()`
  checks hide the parked ones. A parked NPC is not offered (`isActive` = in tree).
- Story flags live in `StoryProgress` (`features/progression/StoryProgress.ts`): a `Set`;
  `setFlags` emits `story.changed` once when anything was added; saved with the run [OUT].

---

## 4. Supporting services the port needs

Only what interaction needs; inventory internals belong to `world-objects.md`.

| Need | Phaser | Godot (have / missing) |
|---|---|---|
| Player position, actions, lock | `PlayerScript.getPosition`, `consumeActionPress`, `actionLocked` | `player.get_centre()`, `consume_action_press()`, `is_action_locked()` - have. **Missing**: `interact` in `PlayerInputBuffer.ACTIONS`; the interact step in `_handle_action_input` (§8.3) |
| NPC position / lock / active | `NpcScript.getPosition`, `acquireInteractionLock`, `isActive` | `get_phaser_position()`, `acquire_interaction_lock()`, `is_inside_tree()` - have |
| NPC display name, dialogue pages | `content/npcs/NpcDefinitions.ts` | **Missing**: no `npc-definitions.json` in `game/data/` (converter copies only constants, enemy types, items, layers) |
| Item count / remove (gate key) | `playerInventory.count`, transaction remove | `RunState.item_count`, `remove_item`, `unlock_gate(map, gate, item, consume) -> bool` - have (bool only; the gate needs the 4-way result, §6.2) |
| Item add with stacking (chest) | `prepareTransaction` + `installTransactionSnapshot` | Planned in [world-objects.md](world-objects.md) §12.6: `RunState.item_capacity(item_id)`, `add_item(item_id, count) -> int`, signals `inventory_changed` / `world_progress_changed`, `ItemCatalog.item_name(id)`. **Missing** here: `transfer_chest_stack(...)` (§8.5) |
| Gate record | `WorldProgress.isGateUnlocked`, `prepareGateUnlockSnapshot` | `RunState.is_gate_unlocked`, `mark_gate_unlocked` - have |
| Chest record | `WorldProgress.chestState / ensureChestInitialized / setChestRemaining` | `RunState.map_record(map)["chests"]` exists; **missing** accessors `chest_remaining`, `ensure_chest`, `set_chest_remaining` |
| Story flags | `storyProgress.hasFlag / setFlags` | `RunState.has_flag / set_flag`, signal `story_flag_changed` - have |
| Talk record | `storyProgress.recordTalk` | **Missing** `RunState.record_talk(npc_id)` (key `talked_npc_ids` exists) |
| Respawn point | `worldProgress.setRespawnPoint` | `RunState.set_respawn_point` - have |
| Messages | `floatingText.spawn(scene, x, y, text, color, important)` | `Services.feel().floating_text(pos, text, color, big)` - have (colours white/green/cyan/...) |
| Exit / door travel | `WorldScene.requestAuthoredExit`, `transitionTo` | `main.request_exit(dict)` / `travel_to` via group `world_main` - in the working tree (§8.4) |
| Chest guard | `BossCampScript.isChestGuarded` | `boss_camp.gd.is_chest_guarded()` (group `boss_camp`) - in the working tree |
| Heal (sleep) | `PlayerHealthController.heal(amount, 'rest')` (`GameState.ts:206-214`: 0 when dead) | **Missing** `player.heal(amount) -> int` |
| Visual offset (sleep) | `Sprite2D.visualOffset` | **Missing** `player.set_art_offset(Vector2)` (the player's `Visual.offset` rest value is already stored) |
| Teleport (sleep) | `teleportPlayer` | `FeetAnchor.place_at_phaser_position(body, p)` + `reset_physics_interpolation()` (as tests do); a `player.teleport(centre)` helper is cleaner |

---

## 5. Content

### 5.1 Instances per world (authored scenes, nested instances expanded)

Counted from `content/scenes/authored/worlds/*.scene.json` with every nested instance flattened.
Context columns (exits, NPCs, other interactable kinds) help pick test worlds.

| World | door | gate | chest | bed | workbench | story-flag | story-variant | interaction | world-exit | NPC | other |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **level-1** | 2 | 1 | 1 | 0 | 2 | 0 | 3 | 0 | 1 | 6 | 2 restoration sites |
| gloop-forest | 2 | 1 | 1 | 0 | 1 | 0 | 2 | 0 | 2 | 2 | 1 plate, 4 gulp spots, 1 cracked ground |
| gloop-hut | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | |
| gloop-cavern | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| slime-home | 1 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | |
| mushroom-home | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | |
| playground (dev) | 1 | 2 | 4 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 2 plates, 2 gulp spots, 1 lash bell, 1 cracked ground |
| playground-cavern (dev) | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| crystal-caverns / emberleef / hot / icege / meadow-crossing | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 / 2 / 2 / 2 / 1 | 0 | |
| girls (dev) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 5 | |
| 174, 236, cole, depth-occlusion-test, jk, test-rectangle, tiktok | 0 | | | | | | | | | | |
| **Total** | **10** | **4** | **8** | **4** | **3** | **1** | **6** | **0** | 11 | 13 | |

Beds: 37 bed object **scenes** exist (`objects/interiors/beds/*` 33, `mushroom-large` 4), but only
**4 bed instances** are placed in worlds (the brief's "74" does not match the content).

level-1 interactables (old Phaser positions; "o" = origin):

| Thing | Where | Values |
|---|---|---|
| `home-door` (world node `home-door`) | o (1081, 903), `arrival` child (2, 51) -> (1083, 954) | r 90, rise 56 (default), "Enter house" -> `slime-home` / `house-door` |
| `mushroom-home-door` (node `mushroom-door-level-1`) | o (1492.2, 489.6), arrival (1, 48) -> (1493.2, 537.6) -> rounded (1493, 538) | r 96 (default), rise 56, "Enter house" -> `mushroom-home` / `house-door` |
| Verdant gate (`level-1-verdant-gate`, `object.gate-verdant`) | o (3776, 768) | gate `level-1-east-verdant-gate`, `green-key` consumed, r 150, rise 120 -> badge/messages at (3776, 648); prompt "Unlock the Verdant Gate"; locked "The Verdant Gate is locked. Fatty One Eye guards the Green Key."; unlocked "The Verdant Gate swings open!" |
| exit-1 (same gate record) | Area2D (3552, 576) | locked message "The eastern gate needs a green key." -> `gloop-forest` west |
| Guarded chest (`level-1-fatty-one-eye-camp/guarded-chest`) | o (2528, 1077) = camp (2528, 1472) + (0, -395) | `level-1-fatty-guarded-chest`, contents `{green-key: 1}`; inside Fatty's activation circle (r 440), so it is guarded whenever the player stands near it with Fatty alive |
| Workshop station (`level-1-workshop/station-script`) | o (640, 392) | in the `restored` variant (`workshop.restored`) - absent in a new run |
| Forge station (`level-1-forge/station-script`) | o (1190, 1068) | in the `restored` variant (`forge.restored`) - absent in a new run |
| Story variants | `chapter-1-villagers-variant` | `chapter-1-complete`, `whenUnset` = node `chapter-1-villagers` (instances `level-1-npc-yellow-blond-slime-girl`, `level-1-npc-mossy-scout`) |
| | `level-1-workshop/variant`, `level-1-forge/variant` | `workshop.restored` / `forge.restored`: `restored` vs `ruined` (the ruined one holds the restoration site [OUT]) |
| NPCs | world spec 3.2 / 5.1 | reach 96 from the sprite bottom; none is in reach of the spawn (640, 704) at start (the elder, 115.9 px away, can wander to 71.5 px) |

### 5.2 Door pairs and arrival points

Arrival = the target door's `arrival` point (rounded); spawn = `findSpawnPoint(arrival)` = centre
of its tile (no arrival tile is solid). "In reach on arrival" = the arriving player already sees
that world's door prompt.

| From world / door (origin, r) | To world / door | Arrival -> player centre on arrival | Facing | In reach of the target door on arrival? |
|---|---|---|---|---|
| level-1 `home-door` (1081, 903), r 90 | slime-home `house-door` | (448, 624) -> **(480, 608)** | down | no: 91.8 > 80 |
| slime-home `house-door` (448, 694), r 80, rise 84, "Leave house" | level-1 `home-door` | (1083, 954) -> **(1056, 928)** | down | yes: 35.4 <= 90 |
| level-1 `mushroom-home-door` (1492.2, 489.6), r 96 | mushroom-home `house-door` | (512, 540) -> **(544, 544)** | down | no: 175.0 > 80 |
| mushroom-home `house-door` (512, 716), r 80, rise 84, "Leave house" | level-1 `mushroom-home-door` | (1493, 538) -> **(1504, 544)** | down | yes: 55.7 <= 96 |
| gloop-forest `hut-door` (2114, 1884), r 90, rise 56, "Enter hut" | gloop-hut `house-door` | (448, 624) -> **(480, 608)** | down | no: 91.8 > 80 |
| gloop-hut `house-door` (448, 694), r 80, rise 84, "Leave hut" | gloop-forest `hut-door` | (2114, 1934) -> **(2144, 1952)** | down | yes: 74.3 <= 90 |
| gloop-forest `gloop-sinkhole` (1344, 2368), r 80, rise 70, "Climb down" - inside `gloop-ch2-cracked-ground` `broken` (flag `cracked.gloop-sinkhole`) | gloop-cavern `gloop-cavern-ladder` | (704, 260) -> **(736, 288)** | down | no: 93.6 > 90 |
| gloop-cavern `gloop-cavern-ladder` (704, 200), r 90, rise 150, "Climb up" | gloop-forest `gloop-sinkhole` | (1344, 2464) -> **(1376, 2464)** | down | no: 101.2 > 80 |
| playground `playground-sinkhole` (1600, 1040), r 80, rise 70 - `broken` (flag `cracked.playground-sinkhole`) | playground-cavern `playground-cavern-ladder` | (704, 260) -> **(736, 288)** | down | no: 93.6 > 90 |
| playground-cavern `playground-cavern-ladder` (704, 200), r 90, rise 150 | playground `playground-sinkhole` | (1600, 1136) -> **(1632, 1120)** | down | no: 86.2 > 80 |

Every pair is symmetric. Interior worlds: slime-home 14 x 11 tiles, mushroom-home 16 x 12, gloop-hut
14 x 11 (all `fixed` camera); caverns 22 x 14 (follow). [QUIRK] Phaser finds a door's arrival
from scene data, so it works even while the door is parked in an unset story variant (arriving
at `playground-sinkhole` from the cavern before the ground was cracked).

### 5.3 Other gates, chests, beds, benches (for tests in other worlds)

- Gates: gloop-forest `gloop-iron-hollow-gate` (2880, 2816), prompt "Sealed gate", locked
  message "Something heavy must press the plate.", opened by plate `gloop-iron-hollow-plate`
  (2880, 3016, latch); playground `playground-heavy-gate` (1344, 576, plate at (1344, 780)) and
  `playground-lash-gate` (1984, 1408, lash bell; message "Ring the bell across the water with the
  Stretch Lash."). All require `green-key` [QUIRK §3.3.2].
- Chests: gloop-cavern `gloop-cavern-hidden-chest` (1088, 640) `{iron-ore 6, charcoal 3,
  hp-potion 1}`; gloop-forest `gloop-matron-guarded-chest` (3200, 708) `{iron-bar 3, hp-potion 2}`;
  playground `playground-test-chest` (1120, 1440) `{stone-spear 1, stone-axe 1, stone-pickaxe 1,
  wood 20, stone 20, silk-clump 10, hp-potion 5, weaver-fang 3}`, `playground-reward-chest`
  (1344, 420), `playground-nook-chest` (384, 1624), `playground-lash-chest` (1984, 1270);
  playground-cavern hidden chest (1088, 640).
- Beds: slime-home `slime-home-west-bed` (160, 340) and `slime-home-east-bed` (740, 280) (straw
  nest: r 102.625, rise 122, sleep (-0.375, -64.05), wake (-0.375, 16)), bed ids
  `world.slime-home.west-bed` / `world.slime-home.east-bed`; mushroom-home `mushroom-home-bed`
  (238, 352) (r 118.78, rise 181.16, sleep (0, -96.642), wake (0, 16), id
  `world.mushroom-home.bed`); gloop-hut `gloop-hut-west-bed` (160, 340) (`world.gloop-hut.west-bed`).
- Workbench: gloop-forest `gloop-ch2-workbench` (1880, 1712), "Use workbench", r 90, rise 76.85.

---

## 6. Godot port: scene scripts

All in `godot/game/scripts/` (converter rule `game.<kebab>` -> `<snake>.gd`); exports exactly as
the tables in §3 (GDScript defaults = TS fallbacks); sanitise in `_ready` like the TS
constructors. Reach the run through `Services.run()`, messages through `Services.feel()`.

### 6.1 `door.gd` [IN]

```gdscript
extends Node
class_name DoorScript
const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const GROUP := &"door"              # contract of game/world/area_travel.gd (door_id, arrival_point())
const MAIN_GROUP := &"world_main"
@export var map_id := ""; @export var door_id := ""
@export var target_area_id := ""; @export var target_door_id := ""
@export var prompt := "Use door"
@export var interact_radius := 96.0; @export var badge_rise := 56.0

func _enter_tree() -> void: add_to_group(GROUP)
func _ready() -> void:
	if not (is_finite(interact_radius) and interact_radius > 0.0): interact_radius = 96.0
	if not is_finite(badge_rise): badge_rise = 56.0

## Old Phaser position of the door (its parent).
func origin() -> Vector2: return FeetAnchor.phaser_position(get_parent() as Node2D)

## WorldSceneLoader.doorArrivals: the parent's child named "arrival", else the parent; rounded.
func arrival_point() -> Vector2:
	var parent := get_parent() as Node2D
	var arrival := parent.get_node_or_null(^"arrival") as Node2D
	var p := (arrival if arrival != null else parent).global_position
	return Vector2(floorf(p.x + 0.5), floorf(p.y + 0.5))

## UniversalSceneWorldController.doorCandidate execute. Returns main's result dictionary.
func use() -> Dictionary:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if main == null or not main.has_method(&"request_exit"):
		return {"status": "blocked", "message": "Navigation unavailable"}
	return main.call(&"request_exit", {"map_id": map_id, "exit_id": door_id,
		"target_area_id": target_area_id, "entry": "", "target_door_id": target_door_id, "gate": {}})
```

### 6.2 `gate.gd` [IN]

Exports per §3.3 (`visual: Sprite2D`, `doors: StaticBody2D` resolve through `node_paths`).
Signal `opened(payload)` -> `{"gateId": gate_id}`. Group `gate` (plates and bells find gates by
`gate_id` there; they must skip parked ones, as Phaser does).

```gdscript
var _opened := false
func _enter_tree() -> void:
	add_to_group(&"gate")
	var run := Services.run()
	_apply(run != null and run.is_gate_unlocked(map_id, gate_id))
func _ready() -> void: _apply(_opened)
func is_open() -> bool: return _opened
## Handler `open` (plates, bells). Not persisted.
func open(_payload: Variant = null) -> void:
	if _opened: return
	_apply(true)
	opened.emit({"gateId": gate_id})
## InventoryWorldTransaction.unlockGate: "unlocked" | "already-unlocked" | "missing-item" | "failed".
func try_unlock() -> String:
	var run := Services.run()
	if run == null: return "failed"
	if run.is_gate_unlocked(map_id, gate_id): return "already-unlocked"
	if run.item_count(required_item_id) < 1: return "missing-item"
	return "unlocked" if run.unlock_gate(map_id, gate_id, required_item_id, consume_on_unlock) else "failed"
func _apply(open_now: bool) -> void:
	_opened = open_now
	if visual != null: visual.frame = open_frame if open_now else closed_frame
	if doors != null and open_now:          # Phaser only ever disables (QUIRK kept)
		for shape in doors.find_children("*", "CollisionShape2D", true, false):
			shape.set_deferred(&"disabled", true)
```

`set_deferred` because the unlock can run inside a physics step (the interact press). Disabled
shapes also stop blocking `WorldService.line_of_sight`.

### 6.3 `chest.gd` [IN domain]

Exports per §3.4; signals `guard_blocked`, `open_requested`, `stack_transferred`, `closed` (one
Dictionary each, camelCase keys, §3.4 table). Group `chest`.

```gdscript
func _enter_tree() -> void:
	add_to_group(&"chest")
	Services.run().ensure_chest(map_id, instance_id, _positive_integers(initial_contents))
func _exit_tree() -> void: if _view_open: close()      # entryDisposables: view.close(instanceId)
func remaining() -> Dictionary: return Services.run().chest_remaining(map_id, instance_id)  # copy
func is_empty() -> bool: return remaining().is_empty()
func is_guarded() -> bool:                              # any live boss camp guarding this id
	for camp in get_tree().get_nodes_in_group(&"boss_camp"):
		if camp.has_method(&"is_chest_guarded") and camp.is_chest_guarded(instance_id): return true
	return false
func request_open() -> String:
	if is_guarded():
		guard_blocked.emit({"instanceId": instance_id}); return "guarded"
	open_requested.emit({"mapId": map_id, "instanceId": instance_id, "contents": remaining()})
	_open_view()                                        # §8.6
	return "opened"
func transfer_stack(item_id: String) -> int:
	var moved: int = Services.run().transfer_chest_stack(map_id, instance_id, item_id)
	if moved > 0: stack_transferred.emit({"itemId": item_id, "moved": moved})
	return moved
func close() -> void:
	_close_view(); closed.emit({"instanceId": instance_id})
## syncChestFrame: the first Sprite2D under the chest root shows frame 1 when empty, else 0.
func sync_frame() -> void
```

`_positive_integers`: keep entries whose value is a number equal to its rounded value and `> 0`
(JSON ints arrive as `int` from the converter's generic encoding; accept `float` too).

### 6.4 `bed.gd`, `workbench.gd` [IN]

Data holders (exports per §3.5 / §3.6) that join groups `bed` / `crafting_station` and expose
`origin()`, plus:
- bed: `bed_id()` = walk up from the script to the first node with meta `persistence_key`
  (else `instance_id`) - instance roots carry both (ARCHITECTURE §12); fallback `str(get_path())`.
  `sleep_request() -> {"bed_id", "sleep_point": origin() + sleep_point, "wake_point": origin() +
  wake_point}`.
- workbench: `station()` = `recipe_context` if in `["workbench", "workshop", "forge", "kitchen"]`
  else `"workbench"`; `site() -> {"station", "tier"}`; `tier` sanitised to an int `>= 1`.

### 6.5 `story_flag.gd`, `story_variant.gd` [IN]

```gdscript
# story_flag.gd
@export var flag_id := ""
func on_set(_payload: Variant = null) -> void:      # converter: handler `set` -> `on_set`
	if not flag_id.is_empty(): Services.run().set_flag(flag_id)
```

```gdscript
# story_variant.gd
@export var flag_id := ""
@export var when_set: Node
@export var when_unset: Node
signal switched(payload: Dictionary)                # {"flagId", "set"}
var _shown: Variant = null                          # null until the first apply
var _parked: Dictionary = {}                        # Node -> its parent
func _enter_tree() -> void: add_to_group(&"story_variant")
func _ready() -> void: _apply()
func _process(_delta: float) -> void:               # PAUSABLE, like Phaser's _process
	if _flag_is_set() != _shown: _apply()
func on_set(_payload: Variant = null) -> void: set_flag()
func set_flag() -> void:
	var run := Services.run()
	if flag_id.is_empty() or run == null or run.has_flag(flag_id): return
	run.set_flag(flag_id); _apply()
func flag_shown() -> bool: return _shown == true
func parked_nodes() -> Array[Node]                  # for door arrivals (§8.4)
func _apply() -> void:
	var is_set := _flag_is_set()
	_shown = is_set
	var active := when_set if is_set else when_unset
	var inactive := when_unset if is_set else when_set
	if inactive != null and inactive.is_inside_tree() and not _parked.has(inactive):
		_parked[inactive] = inactive.get_parent()
		inactive.get_parent().remove_child.call_deferred(inactive)
	if active != null and _parked.has(active):
		var parent: Node = _parked[active]; _parked.erase(active)
		parent.add_child.call_deferred(active)
	switched.emit({"flagId": flag_id, "set": is_set})
func _exit_tree() -> void:
	for node in _parked.keys(): if is_instance_valid(node): node.queue_free()
	_parked.clear()
```

Why deferred: `_ready` runs while the parent is still propagating `_ready` to its children
(Godot refuses `remove_child` then: "Parent node is busy setting up children"), and a flag set
from a physics callback must not remove bodies mid-step. Phaser's removals are queued the same
way. Consequences to keep in mind: during the load frame the inactive subtree is still in the
tree (its `_ready` runs, NPCs join `npc`, doors join `door`); it is gone before the first physics
step, so no provider ever sees it.

---

## 7. Godot port: interaction controller, prompt, badge

### 7.1 Files

| File | Kind | Notes |
|---|---|---|
| `game/interaction/interaction_controller.gd` | Node2D, child "Interaction" of main (created once, survives world swaps) | the router + the providers + execute logic; group `interaction` |
| `game/interaction/interaction_prompt.gd` | CanvasLayer (layer 9) > PanelContainer > Label | §7.4 |
| `game/interaction/interaction_badge.gd` | Node2D (`z_index = 1`), `_draw()` | §7.5 |
| `game/rest/sleep_controller.gd` | RefCounted owned by the controller (or by player.gd) | §3.5 port |
| `game/scripts/door.gd`, `gate.gd`, `chest.gd`, `bed.gd`, `workbench.gd`, `story_flag.gd`, `story_variant.gd` | scene scripts | §6 |

Not created: `game/scripts/interaction.gd` (§3.1).

### 7.2 Controller API

```gdscript
extends Node2D
class_name InteractionController
## Phaser InteractionRouter + the providers of UniversalSceneWorldController / QuestNpcController.
const GROUP := &"interaction"
const POINTER_PICK_PX := 64.0
const TARGET_BODY_RISE_PX := 24.0
const CHEST_REACH := 112.0; const CHEST_BADGE_RISE := 56.0
const NPC_REACH := 96.0; const NPC_BADGE_OFFSET := Vector2(30, -30); const NPC_BODY_RISE := 24.0
const PRIORITY_GATE := 95; const PRIORITY_DOOR := 90; const PRIORITY_WORKBENCH := 88
const PRIORITY_BED := 85; const PRIORITY_CHEST := 80; const PRIORITY_TALK := 50
signal candidate_changed(payload: Dictionary)   # {"id", "prompt"} ("" when none); Godot-only, for tests/hints
signal message_shown(payload: Dictionary)       # {"text", "color", "x", "y"}; Godot-only test hook

func _ready() -> void:
	add_to_group(GROUP)
	process_physics_priority = -10               # before PlayerScript in the same tick (SimClock is -1000)
func _input(event: InputEvent) -> void:          # Phaser pointerSeen: any pointermove/pointerdown
	if event is InputEventMouse: _pointer_seen = true
func _physics_process(_delta: float) -> void:    # PAUSABLE: stops during hit-stop and modals
	set_suppressed(_sleep.sleeping)              # (furniture placement OUT)
	refresh(get_global_mouse_position() if _pointer_seen else null)

func refresh(pointer: Variant = null) -> void    # InteractionRouter.update (§2.4); updates prompt + badge
func handle_interact() -> bool                   # executes the current candidate; false when none
func has_candidate() -> bool
func current() -> Dictionary                     # {id, prompt, priority, anchor, origin, execute} or {}
func set_suppressed(value: bool) -> void         # true clears candidate, prompt, badge
func clear() -> void                             # world teardown: forget candidate, hide both
func prompt_text(candidate: Dictionary) -> String   # "Right-click: <prompt>"
func sleep_controller()                          # the SleepController (player.gd asks it, §8.3)
```

`_gather()` builds candidates in Phaser provider order (§2.1):

```gdscript
func _gather() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var player := Services.world().player
	if player == null or not is_instance_valid(player): return out
	var p := player.get_centre()                                      # [FEET]
	out.append_array(_npc_candidates(p))                              # quest-npcs (talk only)
	_append(out, _nearest_chest(p))                                   # managed-chests (+ sync_frame on every chest)
	_append(out, _nearest(p, &"door", PRIORITY_DOOR, "world-doors:", func(d): return d.door_id))
	_append(out, _nearest(p, &"gate", PRIORITY_GATE, "world-gates:", func(g): return g.gate_id, func(g): return not g.is_open()))
	_append(out, _nearest(p, &"bed", PRIORITY_BED, "world-beds:", func(b): return str(b.get_path())))
	_append(out, _nearest(p, &"crafting_station", PRIORITY_WORKBENCH, "world-workbenches:", func(w): return str(w.get_path())))
	return out
```

- `_nearest`: for each node of the group (only in-tree nodes are returned by
  `get_nodes_in_group`, which replaces Phaser's `is_inside_tree()` check), `d =
  p.distance_to(node.origin())`; keep it when `d <= node.interact_radius and d < best_d`.
  Candidate: `anchor = origin - (0, badge_rise)`, `origin = origin - (0, 24)`, prompt
  `node.prompt`, `execute` per kind (§7.3). `get_nodes_in_group` order is not guaranteed to be
  tree order; it matters only for exact distance ties (negligible).
- Bed/workbench ids: Phaser uses the runtime id; any unique, stable-per-load string works (the
  id only drives tie-breaks and the badge pop). The node path is unique and stable.
- `_npc_candidates`: every node in group `npc` with `d = p.distance_to(npc.get_phaser_position())
  <= 96` and a definition -> `c = quests.npc_candidate(npc_id)` (talk 50 without a quest service),
  `{id: "quest-npcs:%s:%s" % [npc.get_instance_id_key(), c.kind], prompt: "Talk to <name>" (offer,
  talk) / "Return to <name>" (turn-in) / "Resume quest with <name>" (reoffer), priority c.priority,
  anchor: pos + (30, -30), origin: pos - (0, 24), execute: quests.talk_to(npc, c.kind)}`;
  anchor/origin re-read the NPC position on each call.

### 7.3 Execute per kind

| Kind | Godot execute |
|---|---|
| door | `door.use()`; returns `status == "queued"` |
| gate | `r = gate.try_unlock()`; `at = gate.origin() - (0, gate.badge_rise)`; `r in ["unlocked", "already-unlocked"]` -> `gate.open()`, message `unlocked_message` green big; else message `locked_message` (missing-item) or `"The gate will not budge."`, white big; true |
| chest | `if chest.request_open() == "guarded": message "Fatty One Eye is guarding this chest!" at origin - (0, 48), white big`; true. Prompt: `"Chest locked by Fatty One Eye"` if `not empty and guarded`, `"Inspect empty chest"` if empty, else `"Open chest"` |
| bed | refuse (false) when paused, `main.is_transitioning()`, `player.is_action_locked()`, dead or already sleeping; else `_sleep.sleep(bed.sleep_request())` |
| workbench | refuse (false) when paused or a game window is open; else `MenuWindows.open_station(bench.site())` (group `menu_windows`; false when refused) and emit `workbench_opened {mapId, context}`; true ([crafting.md](crafting.md) §4.1) |
| NPC talk | the quest service's `talk_to(npc, kind)` (quests spec §5.2-5.4, §10.5): lock the NPC, then the dialogue box / offer / turn-in window, the talk recorded at open (plain talk) or after the decision (offer, turn-in); false while paused or without the service |

Messages go through one helper: `Services.feel().floating_text(at, text, color, true)` and
`message_shown.emit({...})`.

### 7.4 Prompt node [IN]

`CanvasLayer` layer **9**: above the fades (arrival/travel fade layer 5) and floating text (8),
like Phaser's unfaded UI camera; below the HUD (10). `process_mode` inherited (PAUSABLE): it
keeps showing its last text while paused, as in Phaser. `PanelContainer` with `StyleBoxFlat`
`bg_color = Color("#101a31", 0.8)`, `content_margin_left/right = 12`, `content_margin_top/bottom
= 7`, no border, no corner radius; `Label` 14 px, `font_color = #e7fff5`, theme font (the
project UI theme stands in for Trebuchet MS). Centre at `(vp.x / 2, vp.y - 42)` in CSS px
(viewport visible rect); re-place on `size_changed` and when the text changes (size changes).
`mouse_filter = IGNORE` everywhere. Text from `prompt_text()`:
`"Right-click: " + candidate.prompt`. Derive the verb from the `interact` action's first event
(mouse button 2 -> "Right-click", 1 -> "Left-click", key -> `OS.get_keycode_string`) so a
rebinding stays correct.

### 7.5 Key badge node [IN]

`Node2D` under the controller (so it is in world space and survives world swaps), `z_index = 1`
(overhead-artwork; parents at 0), `visible = false` initially, PAUSABLE. Draw in `_draw()` with
`StyleBoxFlat.draw(get_canvas_item(), rect)` for the rounded boxes (corner radius 5; border 2 px
`#9dffc8` drawn inside, which is 1 px tighter than Phaser's centred stroke - acceptable) and
`draw_line` for the glyph, using the exact geometry of §2.6. Update rules of §2.6: position
rounded, bob 2.5 px / 1400 ms on `Time.get_ticks_msec()`, pop tween 140 ms `TRANS_BACK`
`EASE_OUT` on a new id (the tween is bound to the node, so hit-stop freezes it like Phaser's
`tweens.timeScale = 0`).

---

## 8. Godot port: integration

### 8.1 Phaser -> Godot mapping of the per-step flow

| Phaser (one fixed step) | Godot (one physics tick) |
|---|---|
| `router.setSuppressed` + `router.update(pointer)` in `updateGameplay` (beforeFixedStep) | `InteractionController._physics_process` with `process_physics_priority = -10` |
| `handleActionInput` interact branch | `PlayerScript._handle_action_input` (runs later in the same tick) |
| `router.handleInteract()` | `controller.handle_interact()` |
| world not paused | tree not paused (hit-stop and modals pause it) |

### 8.2 Input

Add `&"interact"` to `PlayerInputBuffer.ACTIONS` (`game/player/player_input_buffer.gd:12-13`).
The action exists in `project.godot` (RMB). Verify on the web export that a right click never
opens the browser menu over the canvas (Phaser calls `disableContextMenu`).

### 8.3 `player.gd` hooks (player builder)

1. `_handle_action_input()`: before the dodge check
   ```gdscript
   if _input.consume(&"interact", now, _buffer_ms):
   	var interaction := _interaction()                  # get_first_node_in_group(&"interaction"), cached
   	if interaction != null and interaction.has_candidate():
   		interaction.handle_interact()
   	return true                                        # even with no candidate (Phaser :1795-1805)
   ```
2. Sleep: at the top of the alive branch of `_physics_process`, before reading the direction:
   `if sleep.sleeping: sleep.update(delta_ms, wake_input()); <keep velocity 0>; ArcadeMover.move;
   return` where `wake_input()` consumes every buffered press of `interact, attack, jump, dodge,
   stretch_lash, squash_slam, teleport, eat` and returns `any pressed or movement_vector() != 0`.
   Damage and death call `sleep.wake("damage"|"death")` (from `commit_damage` / `_die`).
3. New small APIs: `heal(amount: int) -> int` (0 when dead; emits `health_changed`),
   `set_art_offset(offset: Vector2)` (moves `visual.offset` from its rest value), `teleport(centre)`.
   `doze` (1000 ms) and `sleep` (2000 ms loop) clips already exist in
   `game/characters/player_slime.tscn`.

### 8.4 Door travel with the existing main.gd / WorldService

Already there (working tree, uncommitted): `main.request_exit(request)` (map check, transitioning
check, `target_door_id` wins over `entry`, gate check via `_pass_gate`, `travel_to`),
`travel_to(target, edge, door)` (stop + clear input + `suppress_movement(520)`, music fade, 320 ms
`#0b1020` fade on layer 5, then `RunState.capture_player`, `request_navigation`,
`_teardown_world`, `_build_world`), `AreaTravel.arrival_point(navigation, fallback)` (door arrival
via group `door` -> `door_id` / `arrival_point()`, else `player-entry-<edge>`, else spawn marker,
then `find_spawn_point`), fixed camera (`world_camera.hold_fixed`), HUD rebinding, the new player
instance facing down. That is exactly the Phaser flow minus the page reload, so a door only needs:

1. **`door.gd`** (§6.1): group `door`, `door_id`, `arrival_point()`, `use()` calling
   `request_exit` with `"target_door_id"` and `"entry": ""`.
2. **Parked doors**: `AreaTravel.door_arrival` only sees doors in the tree. With the deferred
   parking of §6.5 the lookup in `_build_world -> spawn_player` happens before the park, so it
   works; if parking ever becomes immediate, `door_arrival` must also search
   `story_variant.parked_nodes()` (Phaser reads the scene data, §5.2 quirk).
3. **`_teardown_world()` must call `interaction.clear()`** so a candidate holding freed nodes is
   never executed, and the prompt/badge disappear with the old world.
4. The interaction controller is created once in main `_ready` (before `_build_world`), not per
   world; providers find the new world's nodes through groups, so nothing needs re-registering.
5. Optional dev parity: a `door` launch option (`?door=<id>` / `--door=<id>`) folded into the
   first boot's navigation (Phaser accepts `?area=<id>&door=<id>`).

Differences to accept (or decide): Godot freezes the player for the 320 ms fade (Phaser lets it
walk); Godot rebuilds synchronously (no loading screen); no recovery save; no area title card.

### 8.5 RunState additions (world-objects builder)

On top of [world-objects.md](world-objects.md) §12.6 (`item_capacity`, `add_item`,
`inventory_changed`, `world_progress_changed`): `chest_remaining(map_id, instance_id) ->
Dictionary` (copy), `ensure_chest(map_id, instance_id, contents)` (only when absent; emits
`world_progress_changed` when it creates the record), `set_chest_remaining(...)` (drops counts
<= 0), `transfer_chest_stack(map_id, instance_id, item_id) -> int` = `n = min(remaining[item],
item_capacity(item))` (the closed form equals Phaser's binary search), then `add_item(item, n)`
and the new remaining in one step, emitting both signals; 0 when `n <= 0`; and
`record_talk(npc_id)` (into `story.talked_npc_ids`). The gate key removal should go through the
same first-slot-first `remove_item` world-objects asks for (the current `RunState.remove_item`
takes from the last slots; only which stack shrinks differs).

### 8.6 Screens [OUT] and the temporary stand-ins (owner decision, §10)

| Screen | Phaser | Proposed until Phase 3 |
|---|---|---|
| Chest window | `ChestInventorySurfacePort` (pauses) | ~~take everything at once~~ replaced by the real chest window (2026-10-05, [journal-and-chest.md](journal-and-chest.md) §2, §3.4; `chest.gd` lost `take_all`) |
| Dialogue box | `NpcDialogueSurfacePort` (pauses) | ~~first page as floating text~~ replaced by the real dialogue box with the quests (2026-10-05, [quests.md](quests.md) §6) |
| Crafting window | `CraftingSurfacePort` | ~~nothing~~ the real crafting window (2026-10-05, [crafting.md](crafting.md) §4) |

### 8.7 Converter / data dependencies

- `game/data/npc-definitions.json` from `content/npcs/NpcDefinitions.ts` (`id`,
  `displayName`, `description`, `dialogue`) - needed for "Talk to <name>" and pages.
- Handler renames already exist (`set` -> `on_set`); handler `open` and the four chest signals
  need nothing. After the scripts exist, re-run `pnpm godot:convert` so the converter writes the
  exports and `node_paths` (`visual`, `doors`, `when_set`, `when_unset`).
- `docs/godot/ARCHITECTURE.md` §6 table and §10 file map need the new scripts and the
  `game/interaction/` files (architect/integrator).

### 8.8 Tests (`godot/tests/test_interaction.gd`)

Helpers: `t.main` is main.gd; the controller is `t.tree.get_first_node_in_group(&"interaction")`.
Teleport with `t.teleport_player(centre)`; tests never move the mouse, so pointer picking is off
and `refresh(pointer)` is called directly for the pointer case. Wait 2 steps after a teleport.
Travel waits: `await t.until(func(): return t.world().map_id() == "<id>", 2000.0)` (320 ms fade +
rebuild), then `await t.steps(2)`; `t.player()` is a new instance after travel.

| Test | Setup and action | Expected |
|---|---|---|
| `test_no_candidate_at_spawn` | fresh level-1, 2 steps | `has_candidate()` false; prompt layer hidden; badge hidden |
| `test_door_prompt_and_badge` | teleport (1083, 954) | id `world-doors:home-door`, priority 90, prompt `Right-click: Enter house`; badge visible, x = 1081, y an integer in [845, 850] (round(847 +- 2.5)); teleport (1200, 954) (129.5 px) -> no candidate, both hidden |
| `test_door_travel_round_trip` | at (1083, 954) tap `interact` | map `slime-home`, camera mode fixed, player centre (480, 608) +- 0.01, facing down, no candidate (91.8 > 80); teleport (448, 624) -> prompt `Right-click: Leave house`; tap -> map `level-1`, centre (1056, 928), candidate `world-doors:home-door` at once (35.4 <= 90) |
| `test_mushroom_door_arrivals` | teleport (1493, 538), tap | `mushroom-home`, centre (544, 544); back via (512, 540) -> level-1 centre (1504, 544), candidate `world-doors:mushroom-home-door` |
| `test_door_ignored_while_travelling` | tap interact twice within the fade | exactly one travel (count `world_registered` emissions = 1) |
| `test_interact_dropped_during_swing` | at (1083, 954) tap `attack`, 2 steps, tap `interact` | still `level-1` after 1500 ms sim (the swing locks 292-417 ms, combat spec; the press is > 150 ms old when the lock ends) |
| `test_gate_locked_without_key` | teleport (3776, 840) | id `world-gates:level-1-east-verdant-gate`, priority 95, prompt `Right-click: Unlock the Verdant Gate`; tap -> `message_shown` text `The Verdant Gate is locked. Fatty One Eye guards the Green Key.` white at (3776, 648); Visual frame 0; gate not unlocked |
| `test_gate_unlock_consumes_key_and_persists` | give 1 `green-key`; tap at (3776, 840) | `RunState.is_gate_unlocked("level-1", "level-1-east-verdant-gate")`; `item_count("green-key") == 0`; Visual frame 1; every Doors shape disabled; message `The Verdant Gate swings open!` green; no gate candidate; after travelling to slime-home and back the gate is open at load |
| `test_gate_open_handler_not_persisted` | call `gate.open({})` | frame 1, `opened` emitted once with `{"gateId": "level-1-east-verdant-gate"}`, second call emits nothing; `is_gate_unlocked` false |
| `test_exit_passes_after_gate_unlock` | unlock the gate record, walk/teleport into exit-1 after the 650 ms grace | travels to `gloop-forest` without a key |
| `test_npc_tie_breaks_by_id` | place Pip's body so his phaser position is centre + (40, 0) and Lili's centre + (-80, 0) | candidate `quest-npcs:level-1-npc-lili:talk`, prompt `Right-click: Talk to Lili` (Lili wins although farther) |
| `test_pointer_picks_target` | same placement; `refresh(pip_position - Vector2(0, 24))` | candidate `quest-npcs:level-1-npc-red-slime-boy:talk`; `refresh(far point)` -> back to Lili |
| `test_priority_beats_distance` | `RunState.set_flag("workshop.restored")`, 2 frames; teleport to (640, 532) (station (640, 392) 140 px away, <= 150); place Lili's body so her phaser position is centre + (20, 0) | workbench candidate (88) wins over talk (50) |
| `test_story_variant_parks_villagers` | `set_flag("chapter-1-complete")`, 2 frames | Sunny's and Mossy's NPC bodies not inside the tree; `switched` emitted `{"flagId": "chapter-1-complete", "set": true}`; they are never offered |
| `test_workshop_station_appears` | `set_flag("workshop.restored")`, 2 frames, teleport (640, 470) | candidate id starts with `world-workbenches:`, prompt `Right-click: Use the Workshop`, priority 88 |
| `test_chest_domain` | level-1 chest script (`instance_id == "level-1-fatty-guarded-chest"`) | `remaining() == {"green-key": 1}`; `transfer_stack("green-key") == 1`; `item_count("green-key") == 1`; `remaining() == {}`; `stack_transferred` `{"itemId": "green-key", "moved": 1}`; Visual frame 1 after the next step; second transfer returns 0 and emits nothing |
| `test_chest_prompt` | teleport (2528, 1140) with no live boss (or boss camp absent) | id `managed-chests:level-1-fatty-guarded-chest`, priority 80, prompt `Right-click: Open chest`; with a live Fatty: `Right-click: Chest locked by Fatty One Eye`, tap -> `guard_blocked` and message `Fatty One Eye is guarding this chest!` at (2528, 1029) |
| `test_use_chest_opens_window` | `_use_chest` on the level-1 chest | the chest window opens on it (`GameWindows.is_open(&"chest-inventory")`, `current_chest()`); the bag and messages unchanged; `closed {instanceId}` only after Close. The window itself: `test_chest_window.gd` ([journal-and-chest.md](journal-and-chest.md) §3.7) |
| `test_bed_sleep_and_wake` | travel to slime-home, teleport (160, 400) | prompt `Right-click: Sleep` (priority 85); tap -> centre (159.625, 356), action locked, prompt hidden, respawn point `{"area_id": "slime-home", "map_id": "slime-home", "x": 160, "y": 356, "bed_id": "world.slime-home.west-bed"}`; a move press before 400 ms keeps sleeping, after 400 ms wakes at (159.625, 356) and the prompt returns |
| `test_sleep_heals` | as above with hp 50 | after 1000 ms doze + 3000 ms sleep: hp 56 +- 1 (2 HP/s from the end of the doze, whole points, fraction carried) |
| `test_story_flag_on_set` (playground) | `travel_to("playground")`; call `on_set({})` on `end-card-flag` | `has_flag("playground-end-card-test")` |

---

## 9. Quirks (port as is unless decided otherwise)

1. NPCs of equal priority are chosen by smallest id, not by distance (§2.4).
2. Arrivals snap to the centre of the arrival tile (§3.2, §5.2).
3. `GateScript.lockedPrompt` is read but never shown; the prompt never changes with the key.
4. Plate/bell gate openings are not persisted; those gates also accept a green key (§3.3.2).
5. Chest prompt and guard message name Fatty One Eye for every guarded chest (also the matron's).
6. An empty guarded chest prompts "Inspect empty chest" but reports the guard when pressed.
7. The prompt stays visible while dead and while a modal is open (frozen text).
8. An interact press with no candidate still ends the step's action handling (no attack/dodge
   that step; they stay buffered).
9. `game.interaction` is unusable dead code (no provider, no service).
10. No line-of-sight on interaction reach.
11. During the 320 ms leave fade Phaser lets the player walk; the Godot travel freezes it.
12. A door's arrival works from scene data even when the door is parked (§5.2).

## 10. Open questions for the owner

Interim choices made in the port on 2026-10-05 (the owner can change them): I1 take-all
stand-in, I2 first page as floating text, I3 **kept** as Phaser (id tie-break; parity until the
owner decides), I4 kept, I5 sleep ported now.

| # | Question | Recommendation |
|---|---|---|
| I1 | Chest without its Phase 3 window: take-all stand-in (§8.6) or nothing? | Take-all: level-1's green key lives in a chest. **Resolved** 2026-10-05: the chest window is ported, the stand-in is gone |
| I2 | NPC talk without the dialogue box: floating first page, or no NPC candidates? | Floating first page, so prompts and priorities already match Phaser. **Resolved** 2026-10-05: the dialogue box is ported (quests spec), the stand-in is gone |
| I3 | Keep quirk 1 (id tie-break) or use the nearest NPC? | Fix in the port (nearest, then id), like O3's combo fix - it is what `inReach` clearly intended |
| I4 | Keep quirk 4 (plate gates accept the key and plate openings reset)? | Keep for parity now; revisit with the puzzle design |
| I5 | Sleep in Phase 2 or with the rest/respawn work? | Phase 2 (beds are behind the first doors; clips exist); bed respawn after death stays with the player spec |
