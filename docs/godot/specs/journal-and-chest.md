# Spec: the quest journal and the chest window

**As built (2026-10-05):** both windows are ported (`game/ui/screens/quest_journal_model.gd`,
`quest_journal_window.gd`, `chest_model.gd`, `chest_window.gd`, `window_style.gd`; tests
`test_journal.gd`, `test_chest_window.gd`). Differences from the plan below: main adds the journal
to GameWindows (no `QuestService._mount_windows` hook; the window finds the service by the `quests`
group), GameWindows is unchanged (each window pushes with `quiet` and plays its own cue: the journal
`JournalOpen`, the chest window nothing), and the journal's marks are Phaser's `✓ ★ ◆ ▶ ○`
(game/ui/glyphs.gd; the stand-ins `√ * ◊ » –` were used until the symbol font came, J2).

Two Phaser game windows the Godot 4.7.2 port does not have yet: the **quest journal** ("Quest
Book", the Journal tab of the menu) and the **chest window** (what opens when the player uses a
chest). The spec covers how the Phaser build behaves today, then how the Godot port builds both as
Godot-owned windows on `GameWindows`.

Source of truth: the Phaser app on `feat/godot-migration` (read 2026-10-05). Paths are under
`src/game/` unless they start with `src/`, `godot/`, `scripts/` or `asset/`; `file:line` is the
current tree. Godot files that were uncommitted work in progress when this was written
(`quest_service.gd`, `game_window.gd`, `item_cell.gd`, `crafting_screen.gd`, `dialogue_box.gd`)
are cited by function name.

Binding inputs: [ARCHITECTURE.md](../ARCHITECTURE.md), [CONVENTIONS.md](../CONVENTIONS.md),
[UI_THEME.md](../UI_THEME.md); [quests.md](./quests.md) (§2.8 commands, §2.9 views, §4.4 tracker
texts, §4.7 journal [OUT], §10 port plan), [interaction.md](./interaction.md) (§3.4 chest, §8.6
stand-ins, §10 I1), [crafting.md](./crafting.md) (§5 menu key and tab strip, §11.7 window rules),
[map.md](./map.md) (the world map window, the same pattern), [audio.md](./audio.md) §5.

Legend: **[IN]** port now. **[OUT]** deferred. **[QUIRK]** Phaser behaviour that looks unintended;
port it as is unless the owner decides otherwise (§6). **[DIFF]** a deliberate Godot difference.

---

## 0. Scope and Phaser file map

| Concern | Phaser | Tag |
|---|---|---|
| Journal model and commands | `features/ui/QuestJournalSurfacePort.ts` (236 lines) | [IN] |
| Journal layout | `content/scenes/authored/ui/quest-journal.scene.json` | [IN] |
| Quest commands it calls | `quests/QuestService.ts:322-337` (`abandon`), `:355-363` (`retryFailed`), `:365-377` (`retryAbandonedAutomatic`), `:256-260` (`list`), `:571-582` (`view`) | [IN] (ported in `quest_service.gd`) |
| Reward and objective texts | `features/quests/QuestRewardText.ts:15-28`, `features/ui/QuestTrackerSurfacePort.ts:40-57` (`objectiveLabel`) | [IN] (`QuestCatalog.reward_summary`, `objective_label`) |
| Chest window model | `features/ui/ChestInventorySurfacePort.ts` (144 lines) | [IN] |
| Chest window layout | `ui/chest-inventory-panel.scene.json` | [IN] |
| Chest script (open, guard, transfer, close) | `features/scripts/ChestScript.ts:39-97` | [IN] (`chest.gd`, domain done) |
| Chest wiring and services | `features/world/UniversalSceneWorldController.ts:464-470, 517-519, 607-613, 722-724, 891-917` | [IN] |
| Stack transfer | `features/progression/InventoryWorldTransaction.ts:24-49` | [IN] (`RunState.transfer_chest_stack`) |
| Window CSS | `src/styles.css:3529-3564` (chest), `:3613-3645` (journal), `:3176-3238` (every window and list) | [IN] (theme roles) |
| Menu ids, pause sources, menu key | `scenes/WorldScene.ts:141-147, 215-225, 545, 594-603, 750-772, 2045-2080, 2279-2285` | [IN] |
| Escape, open/close notifications | `ui/ModalStack.ts:55-61, 88-102, 130-144` | [IN] (`GameWindows`) |
| Open/close cues | `features/audio/AudioEventBridge.ts:53-54, 104-108` | [IN] |
| Tab strip | `features/ui/MenuTabsSurfacePort.ts:7, 48-51, 74-83` | [IN] with the tab strip (crafting §5.2) |
| List rendering, focus, right click | `infrastructure/phaser-nodes/ui/HtmlControlPresentationAdapter.ts:61-69, 98-112, 305-363, 417-425`, `ControlNodes.ts:318-362, 420-426` | [IN] |
| `ui/QuestJournal.ts` (Phaser-object journal) | legacy, not mounted (`config.ts` mounts `ui.quest-journal`) | not ported |

Both live windows are scene-JSON DOM surfaces: the authored ModalRoot renders and a
`UiSurfacePort` (`snapshot()` model + `invoke(actionId, payload)`) owns the state. The port keeps
that split, as the crafting window does: a pure static model builder per window, and a
`GameWindow` subclass that renders it.

---

## 1. The quest journal (Phaser)

### 1.1 Opening and closing

| Path | What happens | Source |
|---|---|---|
| Pause menu "Journal" button | closes the pause menu (MenuClose), then `questJournalSurface.open()` | `PauseMenuSurfacePort.ts:49`, `WorldScene.ts:545` |
| Menu tab strip "Journal" tab | only while a tab window is open; closes the open tab window, then opens the journal | `MenuTabsSurfacePort.ts:74-83`, `WorldScene.ts:215-225` |
| Menu key (E) | never opens the journal (it opens the bag); while the journal is open it **closes** it, like any tab window | `WorldScene.ts:2067-2080` |
| A journal key | **none**: `PlayerInputActions.ts:34-35` binds only `menu` (KeyE) and `map` (KeyM); no `KeyJ` anywhere in `src/game` | — |
| Escape | the modal stack closes the top window (capture phase, before the pause menu's own Escape) | `ModalStack.ts:55-61, 130-144` |
| Close button / ModalRoot `close_requested` | `invoke('close')` | `quest-journal.scene.json:411-451` |

`open()` (`QuestJournalSurfacePort.ts:40-49`): no-op when open or destroyed; `openValue = true`;
`status = ''`; `selectedQuestId = undefined` ("each time the book opens it shows the first quest
listed"); pause source `journal` on (`WorldScene.ts:2282` → `setSimulationPaused`, `:750-772`);
modal `quest-journal` opens; publish. `close()` (`:50-57`): modal closes, pause source off,
`status = ''`, publish. `toggle()` (`:39`) has no caller.

There is no other guard: the journal opens whenever one of the paths above calls it (the pause
menu's own `canOpen` and the tab strip's "a tab window is open" are the only gates).

The modal opening fires two observers (`ModalStack.ts:90-96` notifies only on the closed → open
transition): `AudioEventBridge` plays **`JournalOpen`** (not MenuOpen, `AudioEventBridge.ts:107`),
and `WorldScene.ts:594-603` emits `control.used {controlId: 'menu:journal'}` (`MENU_CONTROL_IDS`,
`:141-147`), which the quest service handles at once. So the first time the book opens, the
tutorial objective "Read your Journal" is already ticked in what it shows.

Live updates: `quest.changed` and `quest.completed` republish (`:32-33`); a resize republishes
(`ResizeObserver`, `:34-35`).

### 1.2 Layout (`quest-journal.scene.json`; content offsets; `W` = panel width)

ModalRoot centred, `w = min(940, max(1, ui_w − 32))`, `h = min(620, max(1, ui_h − 32))`, offsets
`∓(round(w/2), round(h/2))` (`:65-70`). At 1280×720 the panel is **940 × 620**, on screen
**(170, 50)–(1110, 670)**. Inside: a vertical ScrollContainer filling the panel over a `Content`
node of fixed height **620** (`:58-78`), so smaller viewports scroll. zIndex 90, inputPriority
2000 (`:7-38`). Panel style `.game-ui--quest-journal`: radius 12, shadow `0 18px 48px #080e1abf`
(`styles.css:3613-3617`) = theme `WindowPanel`; base surface `#101a31` at 94 %, 1 px border
`#3b5c78` at 74 % (`:3176-3181`).

| Node | Rect (left, top)–(right, bottom) | At W = 940 | Text / props | Source |
|---|---|---|---|---|
| Title | (20, 14)–(W−20, 56) | (20, 14)–(920, 56) | "Quest Book", 24 bold, warning `#ffd277` | `:80-107` |
| Quests (ItemList, 1 column, gap 8) | (20, 66)–(0.42W−12, 600) | (20, 66)–(382.8, 600) | rows §1.3; scrolls (`overflow: auto`) | `:109-135` |
| DetailsName | (0.44W, 66)–(W−20, 96) | (413.6, 66)–(920, 96) | 22 bold, warning | `:137-164` |
| DetailsStatus | (0.44W, 98)–(W−20, 120) | (413.6, 98)–(920, 120) | 14 bold, accent `#86f0c3` | `:166-193` |
| Details | (0.44W, 126)–(W−20, 488) | (413.6, 126)–(920, 488) | 14, text `#f5f7ff`, wrap, `pre-line`, line-height 1.45, top-aligned, scrolls | `:195-221`, `styles.css:3637-3643` |
| Status | (0.44W, 498)–(W−20, 526) | (413.6, 498)–(920, 526) | 14, info `#72d8ff`, wrap | `:223-249` |
| Action (Button) | (0.44W, 568)–(0.70W, 608) | (413.6, 568)–(658, 608) | "No action" / "Abandon" / "Retry"; 16 bold, tone danger `#ff6f88` | `:251-278` |
| Close (Button) | (0.74W, 568)–(0.98W, 608) | (695.6, 568)–(921.2, 608) | "Close (Esc)"; 16 bold, tone muted `#8fbba3` | `:280-307` |

The bottom rows hang from the Content's bottom (620), so they do not move with the panel height.

List rows (`styles.css:3628-3636` over `:3206-3238`): `min-height 48`, radius 6, padding 8,
left-aligned, 12 px, `white-space: pre-line` (two lines), line-height 1.4 (each row is about 50 px:
two 16.8 px lines + 16 px padding); inset fill `#182b46`, 1 px border at 78 %. Hover (enabled):
accent text and border. Selected (`aria-selected`): warning text and border on the raised surface
`#192642`. Focus ring: 2 px warning, 2 px outside. Finished quests carry `metadata.locked` →
`.scene-item--locked { opacity: 0.5 }` (`styles.css:3605`; the grey `#9aa6b8` text rule is
crafting-only, `:3607`), and stay selectable. Buttons in every window: bold, centred
(`:3619-3627`), here radius 6 and padding 4 (`:3644-3645`); disabled at 45 % opacity.

### 1.3 The model (`snapshot`, `:59-85`)

**Listed quests** (`listedQuests`, `:147-158`): only quests the player has taken on, in this order:

```
mainFirst(list) = stable sort by (category == mandatory) desc, then acceptedAt desc (missing = 0)
listed = mainFirst(list('active')) + mainFirst(list('completed')) + list('failed') + list('abandoned')
```

`list(status)` is catalogue order (`QuestService.ts:256-260`). `locked` and **`available`** quests
are never listed (offers stay with their NPC; the tracker shows them). Note: quests.md §4.7 says the
journal lists available quests; it does not.

**Selection:** `selected = listed.find(id == selectedQuestId) ?? listed[0]`, and `selectedQuestId`
is rewritten to it (`:61-63`). The selection follows the quest id across re-sorts; when the quest
drops out of the list it falls back to the first row.

**Rows** (`:71-76`): `{id: questId, label: marker + " " + title + "\n" + state, metadata: {locked:
true} when finished}`; finished = completed, failed or abandoned (`:160-162`).

| Marker (`:164-167`) | When |
|---|---|
| `✓` (U+2713) | completed |
| `★` (U+2605) | otherwise, mandatory |
| `◆` (U+25C6) | otherwise, optional |

**State line** (`questState`, `:180-189`), `Kind` = `Main` (mandatory) / `Side` (optional), `·` is
U+00B7 with one space each side:

| Status | Text |
|---|---|
| active, ready to turn in | `<Kind> · Ready to turn in` |
| active | `<Kind> · In progress` + (` · Step <i>/<n>` when the quest has more than one stage and the active stage is found; `stepOf`, `:173-177`) |
| available (never listed) | `<Kind> · Talk to <first giver name>` or `<Kind> · Available` (dead code) |
| completed | `<Kind> · Done` |
| failed | `<Kind> · Failed` |
| abandoned | `<Kind> · Abandoned` |

**Action** (`actionFor`, `:191-197`), for the selected quest:

| Status and definition | Action | Label | Enabled |
|---|---|---|---|
| active, optional, `abandonmentPolicy.kind == retryable` | abandon | "Abandon" | yes |
| failed, `failurePolicy.kind == retryable` | retry | "Retry" | yes |
| abandoned, abandonment retryable, `acquisition.kind == automatic` | retry | "Retry" | yes |
| anything else (mandatory, completed, abandoned NPC quest, nothing selected) | — | "No action" | no |

With the current content (quests.md §7): every failure policy is `permanent` and nothing calls
`fail()`, so "Retry" for a failed quest is unreachable. Abandon is offered for the active optional
quests `slime-basics`, `the-old-workshop`, `a-tonic-for-lili`, `snack-for-the-road`,
`sunnys-basket`; Retry only for an abandoned `slime-basics` (the only automatic optional quest).

**Fields:**

| Key | Value |
|---|---|
| `open` | open flag |
| `quests` | rows above |
| `selectedIndex` | index of the selected row, −1 when none |
| `detailsName` | selected title, else `No quests yet` |
| `detailsStatus` | the selected quest's state line, else `""` |
| `details` | `detailsFor(selected)` below, else `Talk to the slimes marked with ! to take on a quest.` |
| `status` | the stored message (`""` after open, close and every selection) |
| `actionLabel`, `actionDisabled` | table above |

**Details page** (`detailsFor`, `:200-230`):

```
def = quest.definition
visible = quest.visibleStages if not empty else def.stages[0..0]        # visibleStages: QuestService.ts:571-582
activeIndex = index of quest.activeStageId in def.stages (−1 when null: abandoned/failed/completed)
finished = status == completed
steps = for each stage in visible (index = its index in def.stages):
    done    = finished or (activeIndex >= 0 and index < activeIndex)
    current = not finished and index == activeIndex
    heading (only when def has more than one stage):
        (done ? "✓" : current ? "▶" : "○") + " Step <index+1>: <stage.title>"     # ▶ U+25B6, ○ U+25CB
    one row per objective:
        p = done ? target : min(target, progress[objective.id] ?? 0)
        "   " + (p >= target ? "✓" : "•") + " " + objectiveLabel(objective) + (target > 1 ? "  <p>/<target>" : "")
    then ""                                             # a blank line after every stage
turnIn = (active and readyToTurnIn and completion is npc-turn-in)
         ? ["? Return to <npc name of completion.npcIds[0]> for your reward.", ""] : []
lines = [def.description, ""] + steps + turnIn + [questRewardSummary(def.rewards)]
        + (abandoned and acquisition is npc ? ["", "Return to the quest giver to continue."] : [])
details = lines joined with "\n"
```

Three leading spaces before each requirement; two spaces before a count. `objectiveLabel` appends
the key to `use-control` objectives: `(E)`, `(E, then its tab)`, `(M)`, `(hold Shift)`,
`(Mouse wheel)`, `(Esc)` (`QuestTrackerSurfacePort.ts:40-57`). `questRewardSummary` =
`"Reward: " + lines.join(" · ")` or `Reward: the elder's gratitude` (`QuestRewardText.ts:15-28`).
NPC names fall back to the id; `the quest giver` when no id (`:169-171`). For an abandoned quest
`activeIndex` is −1, so every heading reads `○` and the rows show the kept progress.

### 1.4 Actions (`invoke`, `:93-123`)

Everything except `close` is ignored while closed.

| Action (source) | Effect |
|---|---|
| `select-quest {index}` (Quests `item_selected`: click, ←→↑↓, Home/End, Enter/Space on a focused row) | ignore an index without a listed quest; select it; clear the status; publish |
| `quest-action` (Action `pressed`) | quest = the selected listed quest (none → ignore); action per §1.3. **abandon**: `confirmAbandon?.(title) ?? window.confirm('Abandon "<title>"? You can retry it later.')`; cancelled → return, nothing changes; else `questService.abandon(id)`. **retry**: `retryFailed(id)` when failed, else `retryAbandonedAutomatic(id)`. No action → ignore. Then status = ok ? (`Quest abandoned.` / `Quest restarted.`) : `result.reason`; publish |
| `close` (Close `pressed`, ModalRoot `close_requested`) | `close()` |

Service effects (quests.md §2.8): `abandon` → status `abandoned`, `resumeStageId` = the active
stage, `abandonedAt`, `quest.abandoned` (toast "Quest abandoned: <title>", red, not big) and
`quest.changed`. `retryAbandonedAutomatic` → reset per the abandonment policy (`quest`: progress
cleared, back to stage 1), status **`locked`**, `quest.changed`, then `evaluatePrerequisites()`,
which re-activates it at once if its prerequisites hold (`quest.accepted {source: automatic}`:
toast "Quest accepted: <title>", cue `QuestAccept`). Both run while the journal is open and paused;
the toasts spawn at the player under the window (floating text zIndex 20 < 90).

### 1.5 Pause, input, focus, sounds

- **Pause**: source `journal` (`WorldScene.ts:2282`): physics paused, bodies stopped, the player's
  input cleared (`UniversalSceneWorldController.ts:789-793`), music ducked, hints hidden.
- **Focus**: on open the first enabled button in DOM order gets focus
  (`HtmlControlPresentationAdapter.ts:61-69`): the first quest row; with no quests (Action
  disabled) the Close button. Tab / Shift+Tab cycle inside the window (`trapModalTab`, `:98-112`),
  which also stops every key from reaching the game.
- **List keys** (`ControlNodes.ts:340-362`, while a row has focus): ← / ↑ select the previous row,
  → / ↓ the next (one column), skipping disabled rows; Home / End the first / last; Enter / Space
  select the current row. Every selection emits `item_selected` (status cleared, SelectSfx).
- **Escape** closes the journal (modal stack); the pause menu does not open (`defaultPrevented`).
  The menu key closes it (tab window). No other key acts.
- **Sounds**: `JournalOpen` on open, `MenuClose` on close (`AudioEventBridge.ts:104-108`);
  `ClickSfx` (`sfx.ui.click`, min 40 ms) on Action and Close presses; `SelectSfx` (`sfx.ui.hover`,
  min 40 ms, volume 0.8) on every row selection (`quest-journal.scene.json:383-408, 452-481`).

### 1.6 What the player sees (texts for tests)

Fresh run, journal opened directly (so only "Read your Journal" was reported). `a-place-to-work`
is `available`, so it is **not** listed:

```
rows:           ["◆ Slime Basics\nSide · In progress"]        selected 0
detailsName:    Slime Basics
detailsStatus:  Side · In progress
details:
A first look at everything a slime can use: the bag and its tabs, the map, sprinting and the pause menu.

   • Open your bag (E)
   • Look at the Crafting tab (E, then its tab)
   ✓ Read your Journal (E, then its tab)
   • Open the map (M)
   • Sprint (hold Shift)
   • Pause to save or change settings (Esc)

Reward: 10 coins
action:         "Abandon", enabled          status: ""
```

`stone-tools` at stage `use-tools` with `chop-wood` 7 (row `★ Stone Tools\nMain · In progress ·
Step 2/2`, action "No action" disabled):

```
Craft a stone axe and pickaxe at your workbench, then put them to work on trees and rocks.

✓ Step 1: Make your tools
   ✓ Craft a Stone Axe
   ✓ Craft a Stone Pickaxe

▶ Step 2: Put them to work
   • Switch tools on your belt (Mouse wheel)
   • Chop wood from trees  7/20
   • Mine stone from rocks  0/20

Reward: 20 coins · 10× Wood · New recipe: Wooden Spear · New ability: Dodge
```

`a-place-to-work` ready to turn in (row `★ A Place to Work\nMain · Ready to turn in`):

```
Every good slime needs a workbench. Build one and set it up in the clearing.

✓ Step 1: Build a workbench
   ✓ Craft a Workbench (40 wood)

▶ Step 2: Set it up
   ✓ Place the Workbench

? Return to Village Elder Plop for your reward.

Reward: 20× Wood · New recipe: Stone Axe · New recipe: Stone Pickaxe
```

`a-tonic-for-lili` abandoned (row `◆ A Tonic for Lili\nSide · Abandoned`, dimmed, "No action"):

```
Lili wants to learn how berries become a healing tonic. Brew one to show her.

   • Brew a Slime Tonic (3 purple berries)

Reward: 2× Purple Berry

Return to the quest giver to continue.
```

Completed `a-place-to-work`: row `✓ A Place to Work\nMain · Done` (dimmed), both headings `✓`,
every row `✓`. Nothing listed: name `No quests yet`, details `Talk to the slimes marked with ! to
take on a quest.`, no rows, "No action" disabled, Close focused.

### 1.7 Journal quirks

1. **[QUIRK]** Retrying `slime-basics` after `a-place-to-work` was accepted: the quest goes back
   to `locked` and never restarts (its prerequisite `a-place-to-work == available` no longer
   holds, quests.md §2.8), yet the status reads `Quest restarted.` and the quest vanishes from
   the list (selection falls to the first row).
2. The abandon confirmation is the browser's native `window.confirm` (blocking).
3. "You can retry it later" is true for NPC quests only through the NPC ("Resume quest with
   <name>", priority 85, quests.md §5.2); the journal itself offers no action for them.
4. The `available` branch of `questState` is unreachable (available quests are not listed).
5. Finished rows are dimmed only (opacity 0.5); selected finished rows are still dimmed.
6. The selection resets to the first row on every opening; the status clears on any selection.

---

## 2. The chest window (Phaser)

### 2.1 Opening and closing

Interact with a chest (provider `managed-chests`, `UniversalSceneWorldController.ts:891-917`;
interaction.md §3.4): `script.requestOpen()`:

```
ChestScript.requestOpen (ChestScript.ts:70-85):
    if guard.isLocked(instanceId): emit guard_blocked {instanceId} (LockedSfx); return 'guarded'
        -> the provider shows "Fatty One Eye is guarding this chest!" at (o.x, o.y − 48), white, big
    model = {mapId, instanceId, contents: remaining, transferStack: script.transferStack, close: script.close}
    emit open_requested(model)            # OpenSfx (sfx.world.chest-open)
    view.open(model)                      # the chest window (CHEST_VIEW_SERVICE = chestUi, :613)
    return 'opened'                       # an EMPTY chest opens too ("Inspect empty chest")
```

`ChestInventorySurfacePort.open(model)` (`:35-44`): ignored when destroyed; if a chest is already
open, `finish(true)` it first (unreachable: the game is paused); store the model; select the first
stack (`entries()[0]`); status = `Select a stack to inspect. Right-click or press Take Stack to
collect it.`; pause source `managed-chest` on (`WorldScene.ts:2279`); modal `chest-inventory`
opens; publish.

Closing (`finish(notifyScript)`, `:122-131`): forget the model and the selection, modal closes,
pause source off, publish, then if `notifyScript`: `model.close()` → `ChestScript.close()` →
`view.close(instanceId)` (a no-op now) and `closed {instanceId}` (CloseSfx, `sfx.world.chest-close`).

| Close path | `notifyScript` | `closed` / CloseSfx |
|---|---|---|
| Close button, ModalRoot `close_requested`, Escape (modal stack calls the registration's `close`) | true | yes |
| World teardown (`destroy`, `:100-107`) | true | yes |
| The chest leaves the tree (`ChestScript._enter_tree` registers `view.close(instanceId)` on exit, `:59`; `close(instanceId)`, `:46-49`, only for the open chest) | false | no |

The window never closes by itself: emptying the chest leaves it open on "The chest is empty.".

### 2.2 Layout (`chest-inventory-panel.scene.json`; `W` = panel width)

ModalRoot centred, `w = min(920, max(1, ui_w − 32))`, `h = min(620, max(1, ui_h − 32))`
(`ChestInventorySurfacePort.ts:57-62`): **920 × 620** at 1280×720, on screen **(180, 50)–(1100,
670)**. ScrollContainer over a Content of height **620**. zIndex 90, inputPriority 2000. Style
`.game-ui--chest-inventory-panel` (`styles.css:3529-3564`): radius 12, shadow `0 18px 48px
#080e1abf` = `WindowPanel`.

| Node | Rect | At W = 920 | Text / props | Source |
|---|---|---|---|---|
| Title | (24, 14)–(W−24, 54) | (24, 14)–(896, 54) | "Chest", 22 bold, warning | `:80-107` |
| Items (ItemList, **5 columns**, gap 10) | (24, 68)–(0.62W−8, 530) | (24, 68)–(562.4, 530) | cells §2.3; scrolls | `:109-135` |
| Details | (0.64W, 72)–(W−24, 530) | (588.8, 72)–(896, 530) | 13, muted `#8fbba3`, wrap, line-height 1.4, top-aligned, scrolls | `:137-163`, `styles.css:3559-3563` |
| Status | (24, 542)–(W−24, 568) | (24, 542)–(896, 568) | 12, info, wrap | `:165-191` |
| Take (Button) | (24, 574)–(160, 612) | 136 × 38 | "Take Stack", 14 bold, tone accent | `:193-218` |
| Close (Button) | (W−112, 574)–(W−24, 612) | (808, 574)–(896, 612) | "Close", 14 bold, tone muted | `:220-245` |

Cells (`styles.css:3537-3558`, `HtmlControlPresentationAdapter.ts:323-344`): each column is
`(538.4 − 4·10) / 5 = 99.7` px wide, `min-height 52`, radius 5, 11 px text. An item with an
icon renders **illustrated**: a 30×30 icon (`object-fit: contain`, pixelated) above the stack
count (`metadata.shortcut`, 10 px, warning), centred, 2 px gap. The item **name is not drawn**:
`showLabel` is not set, so `"<name> ×<count>"` is only the tooltip (`title`) and the aria label.
An item without a definition (no metadata) shows the plain label text `"<id> ×<count>"` (none in
content). Selected / hover / focus / disabled as in §1.2. Buttons radius 5 (`:3564`).

### 2.3 The model (`snapshot`, `:51-78`)

`entries()` (`:109-112`) = `Object.entries(chest.remaining)` with count > 0, read **live** from
the chest record (`getContents`, `UniversalSceneWorldController.ts:466`) in record order (the
authored `initialContents` order; a transfer keeps the order and drops emptied keys,
`InventoryWorldTransaction.ts:41-45`).

| Key | Value |
|---|---|
| `items[i]` | `{id: itemId, label: "<name> ×<count>"}` (× U+00D7; name = item name or the id) + `metadata {iconKey, iconFrame (0), shortcut: "<count>"}` when the item is defined |
| `selectedIndex` | index of `selectedItemId`; if it is no longer listed it becomes the first entry's (or none) first |
| `details` | selected and count > 0: `"<name>\n<CATEGORY> · ×<count>\n\n<description>\n\nTake Stack transfers as much as your inventory can hold."` (category upper-cased: `MATERIAL`, `CONSUMABLE`, `KEY`, `WEAPON`, `COLLECTIBLE`); else entries exist: `Select an item` (only for an undefined item); else `The chest is empty.` |
| `status` | the stored message |
| `takeDisabled` | no selection |

Status texts: `Select a stack to inspect. Right-click or press Take Stack to collect it.` (on
open), `Moved <n> × <name>` (after a move), `No inventory space for that item.` (nothing moved).
The status is **not** cleared by a selection.

### 2.4 Actions (`invoke`, `:86-98`)

| Action (source) | Effect |
|---|---|
| `select-item {index}` (Items `item_selected`: left click, arrows, Home/End, Enter/Space) | ignore an index without an entry; select it; publish |
| `take-selected-stack {index}` (Items `item_secondary`: **right click** on a cell, or the ContextMenu key / Shift+F10 on the focused list for the selected entry, `ControlNodes.ts:334-338, 354-356`) | the right click first selects the cell (`secondarySelect` → `select` → `item_selected`: select-item + SelectSfx), then: select it and `take(itemId)` |
| `take-stack` (Take `pressed`) | `take(selectedItemId)` when there is a selection |
| `close` | `finish(true)` |

`take(itemId)` (`:114-120`): `moved = model.transferStack(itemId)` → `ChestScript.transferStack`
→ `transferChestStack` moves the largest count that fits (stacks of that item first, then free
slots, `maxStackByItem`; partial moves happen) and emits `stack_transferred {itemId, moved}`
(TakeSfx, `pickup.generic`, pitch ±0.06) when moved > 0. Status `Moved <moved> × <name>` or `No
inventory space for that item.`; if the item is gone, select the first remaining entry; publish.

### 2.5 Pause, input, focus, sounds

- **Pause**: source `managed-chest` (as §1.5). `MENU_CONTROL_IDS` has no chest entry: no
  `control.used`.
- **Focus**: the first cell on open (the first enabled button); an empty chest focuses Close
  (Take is disabled). Tab trap as §1.5. Grid keys: ←/→ ±1, ↑/↓ ±5 (columns), Home/End.
- **Escape** closes (notify: CloseSfx). The **menu key** does nothing: the chest is not a tab
  window and the game is paused (`toggleMenu`, `WorldScene.ts:2077`).
- **Sounds**: no MenuOpen / MenuClose: `chest-inventory` is in `SILENT_MODALS`
  (`AudioEventBridge.ts:53-54, 106`) because the chest's own scene sounds: OpenSfx on
  `open_requested`, TakeSfx per moved stack, CloseSfx on `closed` (`objects/chest-wooden.scene.json`;
  these `AudioStreamPlayer2D`s process while paused, `AudioStreamPlayer2DNode.ts:23-24`).
  ClickSfx on Take and Close; SelectSfx on every `item_selected` (also the one a right click makes).
  A right click itself plays no click.
- After closing, the chest's sprite shows the empty frame on the next interaction poll
  (`syncChestFrame`, `:2208-2211`), and the prompt becomes "Inspect empty chest".

### 2.6 What the player sees (texts for tests)

`level-1-fatty-guarded-chest` `{green-key: 1}` (Fatty not alive), empty bag:

```
cells:    1, icon items-keys-5x4 frame 0, count "1", tooltip "Verdant Key ×1"     selected 0
details:
Verdant Key
KEY · ×1

A leaf-shaped green key carried by Fatty One Eye's guarded chest.

Take Stack transfers as much as your inventory can hold.
status:   Select a stack to inspect. Right-click or press Take Stack to collect it.
Take enabled.  After Take: bag green-key 1, status "Moved 1 × Verdant Key",
no cells, details "The chest is empty.", Take disabled.
```

`gloop-cavern-hidden-chest` `{iron-ore: 6, charcoal: 3, hp-potion: 1}`: counts "6", "3", "1"
(tooltips `Iron Ore ×6`, `Charcoal ×3`, `Slime Tonic ×1`); first details `Iron Ore\nMATERIAL ·
×6\n\nDense iron-bearing ore ready to be refined into metal.\n\nTake Stack transfers as much as
your inventory can hold.`; Slime Tonic: `Slime Tonic\nCONSUMABLE · ×1\n\nRestores 40 HP.\n\n…`.

### 2.7 Chest quirks

1. The cells show only an icon and a count; the name is a tooltip (unreadable on touch).
2. No "Take all": every stack is taken separately.
3. An empty chest still opens a window (OpenSfx, "The chest is empty.", CloseSfx).
4. `Moved … ×` stays on screen while the player selects other stacks.
5. "Take Stack transfers as much as your inventory can hold." is part of every details text.
6. The guard and its texts name Fatty One Eye for every guarded chest (interaction.md §9.5).

---

## 3. Godot port plan

### 3.1 Integration facts from the current Godot code

- `GameWindows` (`game/ui/screens/game_windows.gd`): main's CanvasLayer 40 (above the HUD 10,
  below the Shell 50), made in `main._ready` before `Quests`. `add_window(window)`;
  `push(window, surface_id, quiet = false)` (first window sets `WorldService.PAUSE_MODAL`; cue
  `MenuOpen` unless quiet; `window_opened(surface_id)`); `pop(window, quiet = false)` (MenuClose
  unless quiet; the last pop clears the player's input; `window_closed`); `is_open(surface_id)`,
  `top()`, `close_all()` (main's `_teardown_world`); `_unhandled_input`: Escape (`ui_cancel` /
  `pause`) calls `top().close()`, every other key and mouse button is swallowed while a window is
  open. Its doc comment already names "later the chest, journal and map".
- `GameWindow` (`game_window.gd`, crafting/inventory UI, in progress): full-screen
  `MOUSE_FILTER_STOP` root with a centred `WindowPanel` sized `min(max_size, viewport − 32)`, a
  vertical ScrollContainer over `content` of `content_height`; `surface_id`, `open()` (refresh,
  `push`, `focus_initial()`), `close()` (`pop`), hooks `_build()`, `_layout(width)`,
  `_on_opening()`, `refresh()`; helpers `_label`, `_button` (ClickSfx), `_place`, `_rect`,
  `play_click`, `play_select`; ClickSfx/SelectSfx players (40 ms, select at −1.94 dB). The
  crafting screen builds lists with private `_grid` / `_sync_cells` / `_list_scroll` helpers.
- `ItemCell` (`item_cell.gd`): a `SlotButton` in toggle mode; layouts `ROW`, `TILE` (icon above a
  centred label, tag top-right), `TEXT`; `set_content(text, texture, tag)`, `set_selected`,
  `set_enabled` (disabled cells lose focus), `set_locked` (opacity 0.5 **and** the crafting grey
  text and greyscale icon), `set_text_color`, `index`.
- `ItemIcons.icon(item_id)` → cached `AtlasTexture` (placeholder for procedural/unknown keys);
  `ItemCatalog.definition(item_id)` (items.json, or a synthesized weapon with category `weapon`),
  `item_name(item_id)`.
- `QuestService` (`game/quests/quest_service.gd`, in progress): child "Quests" of main, group
  `quests`; `list(status_filter)` → views in catalogue order (record keys snake_case + `definition`,
  `visible_stages`, `ready_to_turn_in`; `active_stage_id` is `""` when none, `accepted_at` epoch ms,
  absent for `debug_mark_completed`); `abandon`, `retry_failed`, `retry_abandoned_automatic` return
  `{"ok", "state"}` / `{"ok": false, "code", "reason"}` with Phaser's reasons; signals
  `quest_changed`, `quest_completed`, `quest_abandoned`, `quest_accepted`; it connects
  `GameWindows.window_opened` and maps `&"quest-journal"` → `control.used menu:journal`
  (`MENU_CONTROL_IDS`, `_on_menu_opened`); `_mount_windows()` adds the dialogue box and the offer
  window to GameWindows; `debug_activate(id, stage)`, `debug_mark_completed(id)`.
- `QuestCatalog`: `definition`, `index_of`, `stages`, `stage_index`, `objectives`, `npc_name`,
  `reward_summary(rewards)`, `objective_label(objective)` (with `ControlLabels`).
- `ChestScript` (`game/scripts/chest.gd`): `request_open()` (`guard_blocked` / `open_requested`,
  sets `_open`), `transfer_stack(item_id)` (`stack_transferred`), `close()` (`closed`),
  `remaining()`, `is_empty()`, `origin()`, `sync_frame()`, and the stand-in `take_all()`;
  `_exit_tree` calls `close()` when open (emits `closed`, unlike Phaser). Its four SFX players are
  `PROCESS_MODE_ALWAYS` in the converted `chest-wooden.tscn`, so they sound while paused.
- `InteractionController._use_chest(chest)` (`interaction_controller.gd:334-348`): guarded →
  message; else the **take-all stand-in** (interaction.md §8.6, I1): one cyan "Moved <n> ×
  <name>" line per stack, then `chest.close()`. `test_interaction.gd:150-163`
  (`test_chest_take_all_stand_in`) asserts it.
- `RunState.chest_remaining(map, id)` (copy, record order), `set_chest_remaining`,
  `transfer_chest_stack(map, id, item)` = `min(remaining, item_capacity)` (Phaser's binary search
  result), emits `inventory_changed` and `world_progress_changed` (`run_state.gd:614-649`).
- `Shell.set_action(&"journal", callable)`: the pause menu's Journal button is disabled until a
  handler is registered; pressing it closes the pause menu, then `run_action(&"journal")`
  (`shell.gd:130-134, 384-386`).
- No tab strip (`menu_tabs.gd`, crafting §5.2) and no menu-key owner exist yet; `WorldMapWindow`
  closes itself on `menu` / `map` in its own `_input`.
- Fonts (J2, settled 2026-10-05): the theme uses Source Sans 3 with Noto Sans Symbols 2 as the
  fallback, which together have the journal's `✓ ★ ◆ ▶ ○` and `◉ ●`, not `━` (UI_THEME.md "Symbols").

### 3.2 Files

| File | Kind | Content |
|---|---|---|
| `game/ui/screens/quest_journal_model.gd` | static (`QuestJournalModel`) | pure builder of §1.3 over a list of views: `listed`, `marker`, `state_text`, `action_for`, `details`, `snapshot` (§3.3) |
| `game/ui/screens/quest_journal_window.gd` | `GameWindow` (`QuestJournalWindow`), group `quest_journal`, surface `quest-journal` | §1 on the theme; the abandon confirm (§3.3); the Shell `journal` action |
| `game/ui/screens/chest_model.gd` | static (`ChestModel`) | §2.3: `entries`, `snapshot`, `moved_text`, the texts |
| `game/ui/screens/chest_window.gd` | `GameWindow` (`ChestWindow`), group `chest_window`, surface `chest-inventory` | §2 on the theme; the view `chest.gd` opens |
| `godot/tests/test_quest_journal.gd`, `test_chest_window.gd` | tests | §3.7 |

Both windows are built in code like `crafting_screen.gd` (no `.tscn`), Godot-owned copies of
`ui.quest-journal` and `ui.chest-inventory-panel`; the converted `generated/scenes/ui/` copies stay
unused. Neither file lives in `game/scripts/`.

### 3.3 The journal

```gdscript
# quest_journal_model.gd (static)
const TITLE := "Quest Book"
const CLOSE_TEXT := "Close (Esc)"
const EMPTY_NAME := "No quests yet"
const EMPTY_DETAILS := "Talk to the slimes marked with ! to take on a quest."
const ACTION_LABELS := {"abandon": "Abandon", "retry": "Retry", "": "No action"}
const ABANDONED_STATUS := "Quest abandoned."
const RESTARTED_STATUS := "Quest restarted."
const CONFIRM_FORMAT := "Abandon \"%s\"? You can retry it later."
const RETURN_TO_GIVER := "Return to the quest giver to continue."

## views = QuestService.list() (catalogue order). Active then completed, each mandatory first,
## then accepted_at descending (missing = 0), then catalogue index (GDScript sorts are not stable);
## then failed, then abandoned, in catalogue order.
static func listed(views: Array) -> Array[Dictionary]
static func marker(view: Dictionary) -> String          # "✓" | "★" | "◆"
static func state_text(view: Dictionary) -> String      # §1.3 table
static func action_for(view: Dictionary) -> String      # "abandon" | "retry" | ""
static func details(view: Dictionary) -> String         # detailsFor, §1.3 pseudo-code, with
	# QuestCatalog.objective_label / npc_name / reward_summary; active index from active_stage_id
	# ("" -> -1); visible = view.visible_stages or [first stage]
## {"rows": [{"id", "label", "finished"}], "selected_index", "selected_id", "details_name",
##  "details_status", "details", "status", "action", "action_label", "action_disabled"}
static func snapshot(views: Array, selected_id: String, status: String) -> Dictionary
```

```gdscript
# quest_journal_window.gd
extends "res://game/ui/screens/game_window.gd"
class_name QuestJournalWindow
const SURFACE_ID := &"quest-journal"
const GROUP := &"quest_journal"
signal action_finished(payload: Dictionary)   # {"action", "questId", "ok", "status"} (test hook)
var service: Node                              # QuestService; set by QuestService._mount_windows
## Tests: (title: String) -> bool, answered at once (Phaser `confirmAbandon`). Empty: the in-window
## confirm below.
var confirm_abandon: Callable = Callable()
func model() -> Dictionary                     # the last snapshot
func select_quest(index: int) -> void          # select-quest
func quest_action() -> void                    # quest-action (Action button)
func is_confirming() -> bool
func answer_confirm(accept: bool) -> void      # the confirm's buttons
```

- **Size and content**: `max_size = Vector2(940, 620)`, `content_height = 620`; `_layout(W)`
  places every node at the §1.2 rects (bottom rows at 568-608 etc., fixed). At 1280×720 the panel
  is (170, 50)–(1110, 670); at 800×600 it is 768 × 568 and the 620 px content scrolls.
- **Nodes and roles** (UI_THEME.md): Title `PanelTitle`; Quests = a ScrollContainer (vertical)
  over a 1-column `GridContainer` (v-separation 8) of `ItemCell.new(ItemCell.Layout.TEXT, 0, 12)`
  rows: min height 48, left-aligned two-line label, radius 6 and padding 8 (override the
  `SlotButton` boxes as `WorldMapWindow._style_close_button` does); finished rows
  `modulate.a = 0.5` only (**not** `set_locked`, whose grey text and greyscale icon are the crafting
  window's); DetailsName `PanelTitle` @22; DetailsStatus `AccentLabel` @14 with the bold font;
  Details = a `Label` (14, `text` colour, `AUTOWRAP_WORD_SMART`, top-aligned, line pitch ≈ 20 px
  via `line_spacing`) inside a vertical ScrollContainer at the Details rect; Status `InfoLabel`
  @14, wrap; Action `DangerButton` @16 bold (`focus_mode` NONE while disabled, as the DOM skips
  disabled buttons); Close `MutedButton` @16 bold, text `Close (Esc)`.
- **State**: `_selected_id: String`, `_status: String`. `_on_opening()`: both `""`, the confirm
  hidden. `close()`: hide the confirm, `super()`, `_status = ""`.
- **refresh()**: `m = QuestJournalModel.snapshot(service.list(), _selected_id, _status)`;
  `_selected_id = m.selected_id`; sync the rows (`set_content(label)`, `set_selected(i ==
  selected_index)`, dimming, `index`); texts; action label / disabled. Connect
  `service.quest_changed` and `service.quest_completed` → `refresh()` while open.
- **Row press** (`pressed` of a cell, `play_select()`): `select_quest(cell.index)` = ignore an
  index without a row; `_selected_id = rows[index].id`; `_status = ""`; refresh (re-sets
  `button_pressed`, so re-clicking the selected row keeps it selected).
- **Keys on rows** (`gui_input` of each cell, accepted): `ui_up` / `ui_left` → previous row,
  `ui_down` / `ui_right` → next, `ui_home` / `ui_end` → first / last; each selects (SelectSfx, status
  cleared) and moves the focus to that row. Enter/Space press the focused row (`ui_accept`).
- **quest_action()**: no open window or no selected row → return. `action = action_for(view)`;
  `""` → return. Abandon: if `confirm_abandon.is_valid()` → `ok = confirm_abandon.call(title)`;
  false → return (nothing changes). Else show the confirm and return; its Abandon button runs the
  same continuation. Then `result = service.abandon(id)` / (`failed` ? `retry_failed` :
  `retry_abandoned_automatic`)(id); `_status = (ok ? ABANDONED / RESTARTED : result.reason)`;
  refresh; `action_finished.emit(...)`.
- **The confirm** [DIFF] (owner J1): a `ModalPanel` (radius 0, the shell windows' look) of about
  420 × 150 centred on the panel, over a full-panel Control that stops the mouse and dims (black
  35 %): `CONFIRM_FORMAT % title` (14, wrap, centred), buttons "Abandon" (`DangerButton`) and
  "Cancel" (`MutedButton`); focus on Cancel; ClickSfx on both. Escape while it shows cancels it
  only: the window's `_unhandled_input` runs before `GameWindows`' (children first) and marks it
  handled. Cancel / Escape = `confirm_abandon` returning false.
- **Opening**: `GameWindow.open()` (refresh, `push(self, &"quest-journal")`, focus). The push
  pauses the world, plays `JournalOpen` (§3.5 `game_windows.gd`), and emits `window_opened`, which
  the quest service turns into `control.used menu:journal` → `quest_changed` → refresh, so "Read
  your Journal" shows ✓ on the first opening, as in Phaser. Focus: the first row, else Close.
- **Menu key**: while open, the window's `_input` closes it on `menu` (not echo, no
  Ctrl/Alt/Meta) and marks it handled, like `WorldMapWindow._input`; when the menu-key owner exists
  it lists the journal as a tab window and this stays harmless (the child handles first).
- **Shell action**: in `_ready` the window calls `Services.shell().set_action(&"journal", open)`
  (enables the pause menu's Journal button); `_exit_tree` clears it (`Callable()`).

### 3.4 The chest window

```gdscript
# chest_model.gd (static)
const TITLE := "Chest"
const TAKE_TEXT := "Take Stack"
const CLOSE_TEXT := "Close"
const INITIAL_STATUS := "Select a stack to inspect. Right-click or press Take Stack to collect it."
const NO_ROOM_STATUS := "No inventory space for that item."
const TAKE_HINT := "Take Stack transfers as much as your inventory can hold."
const EMPTY_DETAILS := "The chest is empty."
const NO_SELECTION_DETAILS := "Select an item"
static func entries(remaining: Dictionary) -> Array    # [[item_id, count]], count > 0, record order
static func moved_text(moved: int, item_id: String) -> String   # "Moved %d × %s" or NO_ROOM_STATUS
## {"cells": [{"id", "label" ("<name> ×<count>"), "count_text", "defined"}], "selected_index",
##  "selected_id", "details", "status", "take_disabled"}
static func snapshot(remaining: Dictionary, selected_id: String, status: String) -> Dictionary
```

```gdscript
# chest_window.gd
extends "res://game/ui/screens/game_window.gd"
class_name ChestWindow
const SURFACE_ID := &"chest-inventory"
const GROUP := &"chest_window"
func open_chest(chest: ChestScript) -> void    # ChestInventorySurfacePort.open
func close_for(instance_id: String) -> void    # ChestViewPort.close: finish without notifying, only for the open chest
func close() -> void                           # override: finish(notify = true)
func select_item(index: int) -> void           # select-item
func take_selected() -> void                   # take-stack (Take button)
func take_at(index: int) -> void               # take-selected-stack (right click, ContextMenu key)
func current_chest() -> ChestScript            # null when closed
func model() -> Dictionary
```

- **Size and nodes**: `max_size = Vector2(920, 620)`, `content_height = 620`, the §2.2 rects.
  Title `PanelTitle` @22; Items = ScrollContainer over a 5-column `GridContainer` (h and v
  separation 10) of `ItemCell.new(ItemCell.Layout.TILE, 30, 10)`: `set_content(count_text,
  ItemIcons.icon(id))`, `set_text_color(UiTokens.WARNING)`, `tooltip_text = label`, min height 52,
  `SIZE_EXPAND_FILL`, radius 5 (box override); an undefined item: `set_content(label, null)` at
  11 px in the text colour. Details `MutedLabel` @13 (wrap, top, line pitch ≈ 18 px) in a
  ScrollContainer; Status `InfoLabel` @12, wrap; Take `PrimaryButton` @14 bold; Close
  `MutedButton` @14 bold; both radius 5.
- **open_chest(chest)**: if a chest is open, `_finish(true)` first; `_chest = chest`;
  `_selected_id = first entry or ""`; `_status = INITIAL_STATUS`; `GameWindow.open()` (refresh,
  push `chest-inventory`: `modal` pause, **no MenuOpen** (§3.5), focus the first cell or Close).
  `open()` alone (without a chest) does nothing.
- **_finish(notify)**: `chest = _chest`; `_chest = null`; `_selected_id = ""`; `GameWindow.close()`
  (pop, no MenuClose, the last window clears the player's input); then if `notify` and the chest
  is valid: `chest.close()` (→ `close_for` is a no-op, `closed {"instanceId"}`, CloseSfx).
  `close()` = `_finish(true)` (Close button, Escape via GameWindows, `close_all` at teardown);
  `close_for(id)` = `_finish(false)` when `id` is the open chest's.
- **refresh()**: `m = ChestModel.snapshot(_chest.remaining(), _selected_id, _status)`;
  `_selected_id = m.selected_id`; sync cells (count, icon, tooltip, selected), details, status,
  Take disabled (+ `focus_mode` NONE). Entries are re-read on every refresh (the record is live).
- **Cell press** (left click, `ui_accept`): `play_select()`; `select_item(index)`.
- **Right click**: connect each cell's `gui_input` (a signal, so tests can emit it): an
  `InputEventMouseButton` with `MOUSE_BUTTON_RIGHT`, pressed → `accept_event()`, `play_select()`,
  `take_at(index)`. `KEY_MENU` or Shift+F10 on a focused cell → `take_at(selected index)`.
  Arrow keys as the journal, with ↑/↓ moving by 5 (the column count).
- **take(item_id)**: `moved = _chest.transfer_stack(item_id)` (`stack_transferred` → TakeSfx);
  `_status = ChestModel.moved_text(moved, item_id)`; if the item is gone `_selected_id = ""` (the
  snapshot picks the first entry); refresh; when the focused cell was removed, focus the first
  cell, else Close. `take_selected()` needs a selection; `take_at(i)` selects `i` first.
- **chest.gd changes** (Phaser's `CHEST_VIEW_SERVICE`, `ChestScript.ts:53-96`): the view is the
  first node of group `chest_window`.

```gdscript
func request_open() -> String:
	if is_guarded():
		guard_blocked.emit({"instanceId": instance_id})
		return "guarded"
	_open = true
	open_requested.emit({"mapId": map_id, "instanceId": instance_id, "contents": remaining()})
	var view := _view()
	if view != null:
		view.call(&"open_chest", self)
	return "opened"

func close() -> void:                       # ChestScript.close: view.close(instanceId), then `closed`
	_open = false
	var view := _view()
	if view != null:
		view.call(&"close_for", instance_id)
	closed.emit({"instanceId": instance_id})

func _exit_tree() -> void:                  # entryDisposables: view.close(instanceId), no `closed`
	if _open:
		_open = false
		var view := _view()
		if view != null:
			view.call(&"close_for", instance_id)
```

### 3.5 Changes to existing files

| File | Owner | Change |
|---|---|---|
| `game/ui/screens/game_windows.gd` | UI | Port `AudioEventBridge`'s rule in one place: `const OPEN_CUES := {&"quest-journal": &"JournalOpen"}` and `const SILENT_SURFACES := [&"chest-inventory", &"furniture-placement"]`; `push` plays `OPEN_CUES.get(id, &"MenuOpen")` and `pop` plays `MenuClose` unless `quiet` or the id is silent. Update the header comment |
| `game/quests/quest_service.gd` | quests | `_mount_windows()` also instantiates `QuestJournalWindow`, sets `journal.service = self`, `add_window(journal)` (or `add_child` without GameWindows); `var journal` |
| `game/main.gd` | world | `_ready`, right after GameWindows: `game_windows.add_window(ChestWindow.new())` |
| `game/scripts/chest.gd` | interaction | §3.4: `request_open` opens the view, `close` calls `close_for`, silent `_exit_tree`; drop `take_all()` (K3); header comment |
| `game/interaction/interaction_controller.gd` | interaction | `_use_chest(chest)`: `if chest.request_open() == "guarded": _message(at, CHEST_GUARDED_MESSAGE, &"white")`; `return true` (Phaser `getCandidate.execute`). Remove the stand-in loop and `CHEST_LINE_SPACING`, `NO_ROOM_MESSAGE`; header "Phase 3 screens are stand-ins" loses the chest |
| `game/ui/screens/item_cell.gd` | crafting UI | none required; optional `set_dimmed(dimmed)` (opacity only) and a `corner_radius` setter so the journal (6) and chest (5) need no box overrides |
| tab strip `game/ui/screens/menu_tabs.gd` (crafting §5.2, to be written) | crafting UI | the Journal tab is enabled once a `quest_journal` window exists; tab `journal` ↔ surface `quest-journal`, window `get_first_node_in_group(&"quest_journal")`; `current()` = the first open of `inventory`, `crafting`, `quest-journal`, `world-map` (`GameWindows.is_open`); switching closes the current window then opens the target (MenuClose then JournalOpen) |
| menu-key owner (crafting §11.7) | crafting UI | `toggle_menu()` treats `quest-journal` as a tab window (closes it). The chest is not a tab window: the key stays refused while it is open (the tree is paused) |
| `godot/tests/test_interaction.gd` | interaction | replace `test_chest_take_all_stand_in` with `test_use_chest_opens_window` (§3.7) |

No change: `shell.gd` (the `journal` action and button exist), `run_state.gd`, `item_icons.gd`,
`item_catalog.gd`, `quest_catalog.gd`, the converter.

### 3.6 Pause, process, theme, glyphs

- **Pause**: both windows join `GameWindows` (the one `modal` reason, crafting §11.7); Phaser's
  `journal` and `managed-chest` sources become that reason. `PROCESS_MODE_ALWAYS` from `GameWindow`.
- **Mouse**: the full-screen root stops every click [DIFF] (Phaser lets clicks outside the panel
  reach the paused canvas; harmless).
- **Teardown**: `GameWindows.close_all()` closes either window; the chest window notifies its
  chest (`closed`), as Phaser's `destroy` does. Both windows outlive worlds (children of
  GameWindows); the journal reads the service on every refresh.
- **Theme**: the roles in §3.3 / §3.4; per-node overrides only for font sizes, the radius 6 / 5
  boxes, the dimmed rows and the cell count colour.
- **Glyphs**: keep Phaser's strings in the models (tests compare them). Rendering depends on J2.

### 3.7 Tests (expected values)

Helpers as in `test_interaction.gd` / `test_map.gd`: `t.main.get_node("GameWindows")`,
`t.tree.get_first_node_in_group(&"quest_journal" | &"chest_window" | &"quests")`,
`Services.run()`; cues from `GlobalAudio/Effects/<Cue>.playing` (`test_audio.gd::_global_cue`);
the bag reset with `run.inventory.slots = [...]` + `run.inventory_changed.emit({})`. Quest records
are edited in `RunState.quests` (find by `quest_id`), then `quests.quest_changed.emit(...)`.
Journal tests set `journal.confirm_abandon` unless they test the confirm.

`test_quest_journal.gd` (level-1, fresh run):

| Test | Setup | Expected |
|---|---|---|
| `test_open_fresh_run` | `journal.open()` | `GameWindows.is_open(&"quest-journal")`; `has_pause_reason(&"modal")`; title `Quest Book`; rows `["◆ Slime Basics\nSide · In progress"]`, row 0 selected and focused; name / status / details exactly §1.6; action `Abandon` enabled; status `""`; Close text `Close (Esc)`; `JournalOpen` playing, `MenuOpen` not; `slime-basics` progress `read-journal == 1` |
| `test_layout_1280` | open at 1280×720 | panel (170, 50)–(1110, 670); Title (20, 14)–(920, 56); Quests (20, 66)–(382.8, 600); DetailsName (413.6, 66)–(920, 96); DetailsStatus (413.6, 98)–(920, 120); Details (413.6, 126)–(920, 488); Status (413.6, 498)–(920, 526); Action (413.6, 568)–(658, 608); Close (695.6, 568)–(921.2, 608) (content coordinates, ±0.5) |
| `test_row_order` | `debug_mark_completed("a-place-to-work")`; `debug_activate("stone-tools")`, `debug_activate("a-tonic-for-lili")`; set `accepted_at` slime-basics 1000, stone-tools 2000, a-tonic 3000; refresh | rows `★ Stone Tools\nMain · In progress · Step 1/2`, `◆ A Tonic for Lili\nSide · In progress`, `◆ Slime Basics\nSide · In progress`, `✓ A Place to Work\nMain · Done`; only the last dimmed (`modulate.a == 0.5`); `available` quests absent |
| `test_multi_stage_details` | `debug_activate("stone-tools", "use-tools")`, record `progress["chop-wood"] = 7`, open | details exactly the §1.6 Stone Tools text; status line `Main · In progress · Step 2/2`; action `No action` disabled |
| `test_ready_to_turn_in` | `debug_activate("a-place-to-work", "place-workbench")`; `handle_event("furniture.placed", {"placementId": "p1", "itemId": "workbench", "mapId": "level-1", "sceneId": "", "x": 0, "y": 0})`; open | row `★ A Place to Work\nMain · Ready to turn in`; details the §1.6 text with `? Return to Village Elder Plop for your reward.` |
| `test_abandon_and_retry` | open; `confirm_abandon` records titles and returns true; `quest_action()` | titles `["Slime Basics"]`; status `Quest abandoned.`; record `abandoned`, `resume_stage_id == "learn-the-basics"`; row `◆ Slime Basics\nSide · Abandoned` dimmed, still selected; action `Retry`; `quest_abandoned` once. `quest_action()` again → status `Quest restarted.`; record `active`, every progress 0; row `… In progress`; `quest_accepted {"source": "automatic"}` |
| `test_abandon_cancelled` | `confirm_abandon` returns false | record still `active`; status `""`; no `quest_abandoned` |
| `test_confirm_overlay` | no `confirm_abandon`; `quest_action()` | `is_confirming()`; text `Abandon "Slime Basics"? You can retry it later.`; Cancel focused; push `ui_cancel` → overlay hidden, journal still open, record `active`; again + `answer_confirm(true)` → `abandoned`, status `Quest abandoned.` |
| `test_retry_quirk_after_accept` | abandon slime-basics; `quests.accept("a-place-to-work", "village-elder-plop")`; `quest_action()` (Retry) | status `Quest restarted.`; slime-basics `locked`; rows `["★ A Place to Work\nMain · In progress · Step 1/2"]`, selected 0 |
| `test_abandoned_npc_quest` | `debug_activate("a-tonic-for-lili")`; select it; abandon (confirmed) | details end `Reward: 2× Purple Berry\n\nReturn to the quest giver to continue.`; action `No action` disabled |
| `test_empty_journal` | every record `status = "locked"`, `active_stage_id = ""`; open | no rows; name `No quests yet`; details `Talk to the slimes marked with ! to take on a quest.`; action disabled; Close focused |
| `test_open_paths_and_close` | `Shell.open_pause()`, press the pause menu's Journal button | pause menu closed, journal open; `pause` and `read-journal` progress 1. Tap `menu` → journal closed, `MenuClose` playing, unpaused. Reopen, select row 1 (two rows after accepting a-place-to-work) → SelectSfx; close + reopen → row 0 selected, status `""`. Escape → closed, Shell pause menu not open |

`test_chest_window.gd` (level-1, chest `level-1-fatty-guarded-chest`, opened with
`interaction.call(&"_use_chest", chest)` so Fatty is never activated):

| Test | Setup | Expected |
|---|---|---|
| `test_use_chest_opens_window` | empty bag | window open (`GameWindows.is_open(&"chest-inventory")`, `current_chest() == chest`); `has_pause_reason(&"modal")`; OpenSfx playing, `MenuOpen` not; `open_requested` once; bag unchanged (no take-all); no `message_shown`; title `Chest`; 1 cell: count `1`, tooltip `Verdant Key ×1`, icon region (0, 0, 64, 64) of `keys-5x4.webp`; selected 0 and focused; details §2.6; status `Select a stack to inspect. Right-click or press Take Stack to collect it.`; Take enabled |
| `test_layout_1280` | as above | panel (180, 50)–(1100, 670); Title (24, 14)–(896, 54); Items (24, 68)–(562.4, 530), 5 columns, separation 10; Details (588.8, 72)–(896, 530); Status (24, 542)–(896, 568); Take (24, 574)–(160, 612); Close (808, 574)–(896, 612) |
| `test_take_stack` | press Take | `item_count("green-key") == 1`; `remaining() == {}`; `stack_transferred [{"itemId": "green-key", "moved": 1}]`; TakeSfx and ClickSfx playing; status `Moved 1 × Verdant Key`; no cells; details `The chest is empty.`; Take disabled; window still open |
| `test_right_click_takes` | `set_chest_remaining("level-1", id, {"iron-ore": 6, "charcoal": 3, "hp-potion": 1})`; open; emit cell 1's `gui_input` with a right-button press | counts were `6`, `3`, `1`; SelectSfx; `charcoal` 3 in the bag; status `Moved 3 × Charcoal`; cells now `6`, `1`; selected 0 (Iron Ore); details `Iron Ore\nMATERIAL · ×6\n\nDense iron-bearing ore ready to be refined into metal.\n\nTake Stack transfers as much as your inventory can hold.` |
| `test_partial_take_then_no_room` | bag: 19 × `{stone 25}` + `{hp-potion 7}`; chest `{hp-potion 5}`; Take, Take | first: status `Moved 2 × Slime Tonic`, chest `{hp-potion 3}`, cell `3` still selected; second: `No inventory space for that item.`, nothing moved, no second `stack_transferred` |
| `test_select_keeps_status` | after `test_right_click_takes`' take, select cell 1 | status still `Moved 3 × Charcoal`; details `Slime Tonic\nCONSUMABLE · ×1\n\nRestores 40 HP.\n\nTake Stack transfers as much as your inventory can hold.` |
| `test_close_button_and_escape` | Close; reopen; push `ui_cancel` | each: window closed, `closed [{"instanceId": id}]` once, CloseSfx playing, `MenuClose` not, tree unpaused, Shell pause menu not open |
| `test_empty_chest` | empty the record; prompt then use | prompt `Right-click: Inspect empty chest`; window opens with no cells, details `The chest is empty.`, Take disabled, Close focused; close → CloseSfx; 2 steps later Visual frame 1 |
| `test_guarded_chest_has_no_window` | a live Fatty (as `test_chest_prompt`) | `_use_chest` → message `Fatty One Eye is guarding this chest!`; LockedSfx; window not open; not paused |
| `test_keys_while_open` | open; tap `menu`, `interact`, `attack` | window still open; bag closed; no swing and no interaction after closing (input cleared) |
| `test_chest_leaves_tree` | open; remove the chest's root from the world | window closed; `closed` **not** emitted; unpaused |

### 3.8 Docs to update with the port

- interaction.md §3.4 (the window is ported), §7.3 and §8.6 (the stand-in is gone), §10 I1
  (resolved); quests.md §4.7 (ported; it does **not** list available quests) and §10.11;
  crafting.md §5.2 (the Journal tab is live).
- ARCHITECTURE.md §1 tree (`GameWindows > Root >` journal, chest), §10 file map (§3.2 files);
  CONVENTIONS.md "Scenes Godot owns" gains `ui.quest-journal`, `ui.chest-inventory-panel`
  (loaded by code); audio.md §5 (the cue rule now lives in `game_windows.gd`);
  GODOT_MIGRATION.md status.

---

## 4. Owner questions

| # | Question | Recommendation |
|---|---|---|
| J1 | Abandon asks with the browser's native `window.confirm`. Godot: an in-window confirm (§3.3), a Godot `ConfirmationDialog`, or no confirm? Which button has focus? | In-window confirm on the theme, Cancel focused (a destructive default is easy to hit with Enter) |
| J2 | `✓ ★ ◆ ▶ ○` are not in the UI font (web shows boxes; the tracker, dialogue and crafting windows use `✓ ▸` too). Add a symbol fallback font to the theme, draw icons, or ASCII? | One OFL fallback (e.g. Noto Sans Symbols 2, subset) in `ui_tokens.gd` / `build_ui_theme.gd` `fallbacks`: fixes every window at once and keeps Phaser's strings |
| J3 | Retrying `slime-basics` after accepting A Place to Work says "Quest restarted." but the quest goes `locked` and vanishes (§1.7.1). Keep? | Keep for parity (one tutorial quest, harmless); revisit with the quest content |
| J4 | Add a journal key (J)? Phaser has none: E then the Journal tab, or the pause menu | No (parity); the tracker's "E · Journal tab" hint already teaches the way |
| J5 | List available NPC offers in the journal (quests.md §4.7 assumed it does)? | No (parity); fix quests.md instead |
| K1 | Chest cells show only an icon and a count, the name is a tooltip (§2.7.1). Show the name? | Keep for parity now; the `TILE` cell can show "Iron Ore" with the count as a tag later |
| K2 | Add "Take all"? | Not now (parity) |
| K3 | Remove the take-all stand-in (`chest.gd.take_all`, the controller loop and its test)? | Yes, with this port |
| K4 | `chest.gd._exit_tree` emits `closed` (CloseSfx) today; Phaser closes the view silently | Make it silent (§3.4) |
