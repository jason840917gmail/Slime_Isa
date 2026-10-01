# Simple Mouse-And-Keyboard Controls (roadmap 4.10)

## Status

Agreed with the owner on 2026-09-30 and built the same day; only the glyph art
is still open. It now waits for the owner's playtest and the choice of attack
direction. [As Built](#as-built-2026-09-30) lists where the build differs
from the plan below. It replaces today's controls with one scheme:
**left hand on WASD, right hand on the mouse**. The model is Stardew Valley and
Minecraft (left click uses, right click interacts), plus a dodge roll aimed at
the pointer.

Revised the same day:

- Space is Jump and 1 is Dodge. Both are abilities the story teaches; neither
  is available on a new game.
- Attacking toward the pointer is not final. Both attack directions are built
  with a switch, and the owner picks one after playing (see
  [Attack direction](#attack-direction-under-test)).

Out of scope, and parked in the roadmap's
[Interface and platform](../../GAME_ROADMAP.md#interface-and-platform) list:
gamepad, touch, a key-rebinding screen, and choosing which ability sits on
which number. The binding table below is built so that rebinding later only
needs a settings screen.

## Why

In the owner playtest of 2026-09-30, attacking with clicks while walking with
the arrows felt odd, and too many keys each did only one thing. Today's code:

- **17 separate controls**
  ([ControlsSurfacePort.ts](../../../src/game/features/shell/ControlsSurfacePort.ts)).
  - Movement (arrows or IJKL) and clicking both need the right hand.
  - WASD does not move the slime, because W is Gulp.
- **Clicks don't aim.** A click attacks toward the facing (the last move
  direction), snapped to 4 directions (`resolveAttackDirection` in
  `CombatController.ts`). The pointer position is ignored.
- **Bindings live in three places:**
  - `PlayerInputActions.ts` maps key codes to actions;
  - Phaser keys in `WorldScene.bindHotkeys` and `bindDebugCheats`;
  - raw `document` listeners for Esc, M and dialogue.
- **Key names are typed by hand** in the controls screen, the dev Controls
  panel, the hints, the ability bar, `PlayerAbilityDefinitions.key`, the Gulp
  HUD, the interaction prompts, and quest and item text.
- **A key press is kept until it is used, however late.** A press made during
  knockback fires when the knockback ends.
- **Shift+1…8 debug cheats run in production builds.** Only Shift+2 checks
  `import.meta.env.DEV`.

## The Controls

| Do | Input | Notes |
|---|---|---|
| Move | **WASD** | 8 directions, as today. Arrow keys also move. |
| Attack / harvest | **Left click** | Swings toward the pointer or toward the facing, snapped to 4 directions; the choice is under test. Clicking again within the combo window gives hits 2 and 3. |
| Jump | **Space** | A learned ability (Worm Trouble, as today). Follows the movement keys. |
| Dodge roll | **1** | A learned ability (Stone Tools). Rolls 0.5 s toward the pointer, snapped to 4 directions. See [Dodge roll](#dodge-roll). |
| Sprint | **Hold Shift** | Walks faster (`boostSpeed`). No roll, no invulnerability. |
| Interact | **Right click** | Acts on whatever the pointer is on: talk, open, sleep, craft at a station, restore a building, eat at a Gulp spot, pick up plain furniture. |
| Gulp (the mouth) | **Q** | Same rules as W today: tap to eat or burp, hold for the quick wheel. |
| Abilities | **1 – 0** | 1 Dodge, 2 Stretch Lash, 3 Squash Slam, 4 Teleport. 5–0 stay empty for now. |
| Switch weapon | **Mouse wheel** | Cycles through up to 3 equipped weapons. |
| Menu | **E** | One window with tabs: Inventory, Crafting, Journal, Map. **M** opens it on the Map tab. |
| Zoom | **+ / −** | The mouse wheel did this before. |
| Pause / close | **Esc** | Unchanged. |

Normal play uses WASD, both mouse buttons, the wheel, Space, Shift, Q, E, 1–4
and Esc. These keys stop doing anything in play: IJKL, F, G, R, T, Y, Tab, C
and U, plus 5–6 as weapon keys. W stops being Gulp and becomes movement.

### Rules Behind It

- **The hands stay put.** The left hand stays on WASD, Space, Shift, Q, E and
  1–4, and the right hand stays on the mouse. Nothing in play needs the right
  hand on the keyboard.
- **Abilities aim at the pointer.** That covers the dodge, Stretch Lash and
  Teleport. Two exceptions:
  - Jump follows the movement keys, because that is how you cross gaps and
    land on cracked ground. Standing still jumps in place, as today.
  - Squash Slam hits all around the slime.
- **Attacks may aim at the pointer too.** That is still under test.
- **Left click uses, right click interacts**, the same split as Stardew and
  Minecraft.
- **In play, each key does one thing.** Modes (placing furniture, the Gulp
  wheel, dialogue, menus) show on screen what their keys do.
- **Shift is only ever held, never tapped.** Windows' Sticky Keys prompt
  (five Shift taps) is therefore not a risk. Ctrl and Alt are never used,
  because Ctrl+W closes the browser tab.

## Dodge Roll

**Today** (`PlayerController.tryDodge`, `PlayerScript.beginDodge`): Q rolls
toward the movement input, or the facing if the slime is standing still.

- It rolls at `dodgeSpeed` 380 for `dodgeInvulnerabilityMs` 400. The roll and
  its invulnerability are the same 400 ms, about 150 px.
- There is no cooldown.
- Holding Q sprints and plays the roll animation.

**New:**

- **Dodge is a learned ability on key 1.** Elder teaches it when Stone Tools
  is handed in, just before the first worm camp, with a line of dialogue.
  - Until then, 1 does nothing and the ability bar shows the slot locked
    ("Quest").
  - Old saves that already finished Stone Tools learn it on load. The save
    loader already grants every ability whose quest is complete
    (`withQuestTaughtAbilities` in `SaveRepository.ts`).
  - The dev "learn every ability" cheat and the playground's ability lesson
    include it.
- **1** rolls toward the **pointer**, snapped to up, down, left or right with
  the same rule as attacks: whichever of the horizontal and vertical distances
  is larger wins. Movement keys do not steer the roll.
- **No energy cost.** The roll is limited only by its cooldown, which the
  ability bar shows like any other.
- The roll lasts **0.5 s**. During it the slime ignores the movement keys,
  cannot attack or use abilities, and stops at walls as it does today.
- **Invulnerability** covers the first 400 ms. The last 100 ms is recovery, so
  a roll is a commitment.
- **Cooldown:** a new roll can start 250 ms after the previous one ends, so
  rolls can't be chained into permanent invulnerability.
- **Fallbacks for the direction:**
  - If the pointer is on the slime (under about 16 px away), the roll goes
    toward the facing.
  - If the pointer has never been over the game, the roll also goes toward the
    facing.
  - Once the pointer leaves the game canvas, its last position is used.
- **Stuck in a web** (rooted): no roll, as today.
- **The roll animation belongs to the dodge only.** Sprint no longer uses it,
  so the roll always means "invulnerable".

Starting values live in `content/game-constants.json` under
`character.player.movement`. They are tuned in the `playground` map against
the target dummy.

| Constant | New value | Today |
|---|---|---|
| `dodgeSpeed` | 380 (190 px over 0.5 s) | 380 |
| `dodgeDurationMs` (new) | 500 | same as invulnerability |
| `dodgeInvulnerabilityMs` | 400 | 400 |
| `dodgeCooldownMs` (new) | 250 | none |

## Attack Direction (Under Test)

The owner wants to try both before deciding, so both are built:

- **Pointer:** a left click turns the slime toward the pointer, snapped to 4
  directions, and swings. While moving, the slime faces its movement again
  after the swing.
- **Facing:** a left click swings toward the facing (the last movement
  direction), as today.

The choice is the `attackAim` value (`pointer` or `facing`) in the settings
store (`gameSettings`), so it survives a reload. For now only the dev panel
(`pnpm dev`) shows the switch. It starts on `pointer`. Once the owner picks:

- **If one mode wins,** the other is deleted.
- **If players should choose,** the switch moves to Settings → Controls.

In both modes, the dodge, Stretch Lash and Teleport aim at the pointer.

## Three Weapons On The Mouse Wheel

**Today:**

- The belt has six slots (`WEAPON_HOTBAR_SLOT_COUNT = 6` in `core/types.ts`).
  You pick one with 1–6 or by clicking the HUD. The inventory's assign row only
  offers slots 1–5.
- Axes and pickaxes sit on the belt too. A resource node only takes damage from
  a weapon whose `harvestCapabilities` meets the node's tier
  (`ResourceNodeScript.canReceiveDamage`).

**New:**

- **The belt has 3 slots** (`WEAPON_HOTBAR_SLOT_COUNT = 3`).
- **Wheel steps:** one step up or down selects the previous or next filled
  slot. It wraps around and skips empty slots. With only one weapon equipped,
  the wheel does nothing.
- **Trackpads and free-spinning wheels:** scrolling adds up until it reaches
  one notch of a normal mouse wheel. After a switch, the wheel is ignored for
  150 ms, so one swipe moves exactly one weapon.
- **HUD and inventory:** the HUD belt shows 3 slots, and clicking a slot still
  equips it. The inventory's **Equip to slot** row offers 1–3.
- **Old saves:** a saved belt with more than 3 weapons keeps the equipped
  weapon plus the next filled slots, up to 3. The rest stay owned in the
  inventory, so nothing is lost. The belt is fixed up when the save loads.
- **Tools pick themselves.** (Removed after the 2026-10-01 playtest: the
  swap lost fights against enemies behind a tree; the weapon in hand always
  swings and the belt has four slots. Roadmap 4.11.) Left-clicking a tree, rock or other resource node
  within reach swings the best owned tool that can harvest it, then the
  equipped weapon comes back.
  - The tool can be anywhere in the inventory, not only on the belt.
  - If no owned tool can harvest the node, the equipped weapon swings and
    today's "needs a better tool" message shows.
  - So harvesting never needs the wheel, and the 3 slots are for fighting. A
    tool can still go on the belt to fight with.

## Right Click Interacts

**Today:**

- F acts on the one candidate the `InteractionRouter` picked (the nearest in
  range) and shows its prompt.
- G is a second action on the same target: pick up a placed workbench or bed.
- Dialogue advances with F, Space or Enter.

**New:**

- **Target:** right click acts on the interactable under the pointer, if it is
  within interaction range. If the pointer is on nothing interactable, right
  click uses the nearest candidate, as F does today, so it is never worse than
  F.
- **Hover:** pointing at an interactable within range highlights it and shows
  its prompt with a right-click glyph.
- **Gulp spots** are interactables, so right click eats them, the same as Q.
- **G goes away:**
  - a bed's prompt offers Sleep and Pick up;
  - the crafting window of a placed workbench gets a Pick up button;
  - plain furniture is picked up with right click, as with F today.
- **Dialogue** advances with a left or right click, Space or Enter.
- **The browser's right-click menu is blocked** over the game canvas with
  `this.input.mouse.disableContextMenu()`. HTML menus keep their own
  right-click handling, such as "take the stack" in the chest list.

## Q Is The Mouth

Gulp keeps every rule in
[Game Guidelines](../../GAME_GUIDELINES.md): one key is the slime's mouth, and
no menu ever opens to eat. Only the key changes. W is now movement, so the
mouth moves to Q, right next to it.

- **Tap near a Gulp spot** to eat from it.
- **Tap elsewhere while in a form** to burp the form away.
- **Hold for 250 ms** (`GULP_WHEEL_HOLD_MS`) to open the quick wheel. Choose
  with the mouse (WASD also steers it) and release to eat.

When this ships, the guideline and the Gulp controls table in the roadmap
(Milestone 7) change W to Q.

## Abilities On The Number Keys

- **Jump stays on Space.** It is still taught when Worm Trouble is handed in,
  and Space does nothing before that.
- **Fixed number slots,** in the order the story teaches them:
  - **1** Dodge (Stone Tools)
  - **2** Stretch Lash (a Chapter 2 quest)
  - **3** Squash Slam (the Chapter 2 boss)
  - **4** Teleport (later)
- **The bar:** it shows Jump (Space) and slots 1–4, with unlearned ones locked
  as today. Keys 5–0 are bound, but their slots stay hidden until something can
  go there.
- **Directions:**
  - **Jump** follows the movement keys. Standing still jumps in place.
  - **Dodge** rolls toward the pointer, snapped to 4 directions.
  - **Stretch Lash** flies toward the pointer at any angle. The lash already
    draws along any direction.
  - **Teleport** lands at the pointer, up to its 240 px range, using today's
    safe-landing search.
  - **Squash Slam** hits all around the slime.
- **Weapons:** the number keys no longer choose weapons.
- **Labels:** ability definitions lose their hand-typed `key` field. Their
  labels come from the binding table.

## One Menu

- **Opening it:** E opens one window with four tabs: Inventory, Crafting,
  Journal and Map. Clicking a tab switches to it. E or Esc closes the window,
  and M opens it on the Map tab.
- **Stations:** right-clicking a crafting station opens the window on the
  Crafting tab for that station.
- **Built from today's windows:** `inventorySurface`, `craftingSurface`,
  `questJournalSurface` and `worldMapSurface` stay as they are. They share a
  tab strip and open and close as one, so only one of them shows at a time.
- **Other keys and the pause menu:** Tab, C and U stop opening windows. The
  pause menu's Journal, Inventory and Map buttons open the matching tab.

## Placing Furniture

- The ghost follows the pointer, as today.
- Left click places the item, and the mouse wheel changes its variant (R did
  this before).
- Right click or Esc cancels. The placement hint says so.
- Other actions stay blocked while placing, as today.

## One Binding Table

- **One table** in `features/player/` replaces `PLAYER_INPUT_ACTIONS`. It
  lists every player action and its inputs:
  - key codes (`KeyboardEvent.code`, so physical key positions);
  - mouse buttons;
  - the wheel.
- **All gameplay input goes through `InputRouter`**, which learns mouse buttons
  and the wheel (via `InputEvent`).
  - These go away: `WorldScene.bindHotkeys`, the M listener, and the Phaser
    `addKey` calls for player actions.
  - Menus keep their own keys (arrows, Enter, Tab focus inside a window).
- **Labels come from `controlLabel(action)`**, which returns what to show
  ("Space", "Left click", "1"). Every UI text uses it:
  - the Settings → Controls list and the dev Controls panel (`config.ts`);
  - `ControlHints`, the ability bar, the Gulp HUD and the interaction and NPC
    prompts;
  - quest and item text, which writes tokens such as `{key:interact}` that are
    filled in when the text is shown, so text never names a stale key.
- **Keyboard layouts:** where the browser reports the player's layout
  (`navigator.keyboard.getLayoutMap()`, Chromium only), labels use it, so an
  AZERTY player sees "Z Q S D" for the same four keys. Other browsers show
  QWERTY names.
- **Presses expire.** A press not used within 150 ms (`input.bufferMs`) is
  dropped. A press during knockback, while the Gulp wheel is open, or during an
  action lock never fires later. Held inputs (Shift, Q) read the live key
  state.
- **Debug cheats leave Shift+number**, since Shift is sprint and the numbers
  are abilities now. They become dev-panel buttons that only exist in
  `pnpm dev`. The quick fix that limits the cheats to dev builds can land
  before this work; if it hasn't, this step does that too.
- **Rebinding later:** the table is the data a future rebinding screen needs;
  that screen would only write to the table.

## What Changes When It Is Built

**Code:**

- Input: `PlayerInputActions.ts`, `InputEvent.ts`, `InputRouter.ts`,
  `PlayerScript` (held and pressed actions, sprint), and `WorldScene`
  (`handleActionInput`, `bindHotkeys`, `bindDebugCheats`, the camera wheel, the
  Gulp hold). Also `WorldMapSurfacePort` (M) and `NpcDialogueSurfacePort`
  (advance keys).
- Dodge as an ability: `content/abilities.ts` (a `dodge` id),
  `PlayerAbilityDefinitions` (earned by "Quest", cooldown, no energy), the
  ability bar, and the Stone Tools reward plus Elder's new line in
  `chapterOne.ts`.
- Aim:
  - `CombatController`: attack direction from the pointer or the facing
    (`attackAim`), and picking the tool.
  - `PlayerController.tryDodge` and `PlayerScript.beginDodge`: roll duration
    separate from invulnerability, plus the cooldown.
  - `PlayerAbilityService`: Lash direction and Teleport target.
- Belt: `core/types.ts`, `systems/WeaponLoadout.ts`, `GameState`,
  `WeaponHotbarSurfacePort`, the `InventorySurfacePort` assign row, and the
  fix-up of old saves on load.
- Interact: `InteractionRouter` (pointer target and hover), the prompts in
  `UniversalSceneWorldController`, the Pick up options for beds and
  workbenches, and `FurniturePlacementController`.
- Menus: a tab strip shared by the four windows, and `PauseMenuSurfacePort`.
- Labels:
  - `ControlsSurfacePort`, the dev panel in `config.ts`, `ControlHints`;
  - `AbilityBarSurfacePort`, `PlayerAbilityDefinitions`, `GulpHud`,
    `QuestNpcController`;
  - text in `chapterOne.ts` (Tab, Space, F), and the workbench text in
    `items.json` and `RecipeCatalog.ts` ("press F at it").
- Not updated: the old `src/game/ui/*` windows that the game no longer imports
  (`CraftingUI`, `AbilityBar`, `InventoryUI`, `WorldMapUI`, `QuestJournal`,
  `WeaponHotbar`, `QuestOfferModal`).

**Content and constants:**

- `game-constants.json` and its schema gain `dodgeDurationMs`,
  `dodgeCooldownMs`, `input.bufferMs` and `input.weaponWheelStepLockMs`. After
  the schema edit, run `pnpm constants:generate`.
- `items.json`, `RecipeCatalog.ts` and `game-constants.json` are
  scene-conversion inputs, so re-hash the ledger afterwards
  ([TOOLING.md](../../TOOLING.md#scene-conversion)).

**Docs:**

- [GAME_GUIDELINES.md](../../GAME_GUIDELINES.md): the mouth is Q.
- [GAME_ROADMAP.md](../../GAME_ROADMAP.md): the Gulp controls table, and this
  task.
- [ARCHITECTURE.md](../../ARCHITECTURE.md): keys 1–6 and Shift+1–8.
- [camera-and-minimap-guide.md](../../camera-and-minimap-guide.md): zoom keys.
- [Player action dashboard](../../task/ideas/open/player-action-dashboard-and-loadout.md):
  3 belt slots, and the number keys belong to abilities.

**Art:** the control-hint key and mouse glyphs from the Milestone 4 asset
list: left click, right click, wheel, and a keycap.

**Tests:**

- Update the Playwright specs that press old keys: `ability-bar`,
  `chest-inventory`, `crafting`, `inventory`, `level-1-verdant-gate`,
  `quest-ui`, `weapon-hotbar` and `world-map`.
- Also update `scene-runtime/input-router.test.mjs` and
  `scene-integration/player-ability-nodes.test.mjs`.
- Add cases for:
  - attacks in both aim modes, and the pointer-aimed dodge;
  - dodge timing and cooldown, and the dodge staying locked until learned;
  - wheel stepping and wrap-around;
  - the belt fix-up for old saves (`pnpm test:persistence`);
  - tool choice;
  - presses expiring;
  - labels coming from the table.

## Build Order

Each step ends with `pnpm typecheck` and the targeted tests for what it
touched.

1. **Binding table and input plumbing.** Build the table (holding today's keys
   at first), add mouse buttons and the wheel to `InputRouter`, and add
   `controlLabel`. Presses expire, the browser menu is blocked, and the cheats
   move to the dev panel. Players see no change yet.
2. **New bindings.** WASD, Space jump, Shift sprint, Q mouth, 1–4 abilities,
   E menu, +/− zoom. Lash and Teleport aim at the pointer, and attacks get the
   `attackAim` switch.
3. **Dodge rework:** a learned ability on 1 (taught at Stone Tools), lasting
   0.5 s, aimed at the pointer, with the cooldown. Tune it in the playground.
4. **Right click interacts.** G is retired, and placement uses the wheel for
   variants.
5. **Three-slot belt on the mouse wheel,** the fix-up for old saves, and tools
   that pick themselves.
6. **One menu with tabs.**
7. **Text, docs and glyphs:** hints (plus a new "scroll to switch weapons" hint
   the first time a second weapon is on the belt), prompts, quest and item
   text, and the docs listed above. Re-hash the conversion ledger.
8. **Verify** against the list below, then the owner plays it.

## Done When

- **Chapter 1:** a fresh save can finish it using only WASD, the mouse (both
  buttons and the wheel), Space, Shift, Q, E, 1–4 and Esc.
- **Attack:**
  - in `pointer` mode, clicking attacks toward the pointer in each of the 4
    directions;
  - in `facing` mode, clicking attacks toward the facing;
  - the owner has picked a mode, and the plan and roadmap say which.
- **Jump and dodge:**
  - on a fresh save, Space and 1 do nothing until Worm Trouble and Stone Tools
    teach them;
  - an old save past Stone Tools has the dodge;
  - 1 rolls for 0.5 s toward the pointer;
  - rolls can't come faster than the cooldown allows;
  - a hit during the first 400 ms of a roll does no damage.
- **Weapons:**
  - the wheel moves one weapon per notch across up to 3 equipped weapons, and
    wraps around;
  - a trackpad swipe moves one weapon;
  - a save with 6 belt weapons loads with 3 on the belt and none lost;
  - clicking a tree or rock with a sword equipped harvests it with the best
    owned tool.
- **Interact:** right click talks to the NPC under the pointer even when
  another NPC is nearer. With nothing under the pointer, it uses the nearest.
- **Presses:** no key press fires more than 150 ms after it was made.
- **Labels:** every key name in the game (controls list, hints, prompts,
  ability bar, quest and item text) comes from the binding table, so changing
  one binding changes every label.
- **Cheats:** Shift+number does nothing in a production build.
- **Owner:** accepts the feel after a playground session and a Chapter 1 run.

## As Built (2026-09-30)

These points differ from the sections above.

- **Picking up placed furniture:** hold right click on it (450 ms). A tap
  still uses it, so a bed sleeps and a bench opens crafting. The prompt reads
  "Right-click: Use workbench     Hold: Pick up". There is no Pick up button
  or menu.
- **Dialogue** advances with Space, Enter or the window's Next button. A click
  anywhere else does not advance it.
- **Keys 5–0** are not bound yet; nothing can go there.
- **Content text** names no keys at all ("open your bag", "use it to
  craft"), so it needs no tokens. Keys are named only by UI built from the
  table: hints, prompts, the ability bar, the controls lists, and the "learned"
  banner.
- **The menu tabs** are a small strip (`ui.menu-tabs`,
  `MenuTabsSurfacePort`) at the top of the screen, shown while any of the four
  windows is open. The menu key works in the capture phase, so it also closes
  a window that holds keyboard focus. M still opens the map on its own when
  nothing else is open.
- **Pointing:** a target counts as pointed at within 64 px of its body. NPC
  providers offer every NPC in reach, so the pointer can choose one that is
  not the nearest. The bobbing badge over the chosen target is the hover
  highlight; it draws a small mouse with the right button lit until the glyph
  art exists.
- **Tools that pick themselves** look for a tree or rock within 120 px and
  about 50 degrees of the swing direction. The tool is mounted for that one
  swing; the belt and HUD never change.
- **Known issue, not new:** the shared prompt line is drawn behind the
  ability bar at the bottom of the screen. The badge and the hint banner still
  show; moving the prompt is a separate fix.
- **Verified:**
  - `pnpm typecheck` and the targeted suites pass: scene-runtime,
    scene-integration, shell, progression, game-constants, gulp, quests,
    persistence, combat (with the new `controls.test.mjs`), ui and
    scene-content.
  - Two headless Brave playtests against the dev server passed 34 of 34
    checks, covering:
    - WASD movement;
    - Dodge locked, then a 0.5 s roll toward the pointer with 400 ms of
      invulnerability and a cooldown;
    - Space jump;
    - three weapons cycled by the wheel, one per swipe and wrapping;
    - attacks in both aim modes;
    - E with the tabs;
    - right-click on a Gulp spot, and Q burping away from it;
    - Shift+1 doing nothing, and number keys not changing weapons;
    - the axe swung at a tree with a sword equipped, the sword coming back;
    - placing with left click and cancelling with right click;
    - a bench tap and a bench hold.
  - Of the updated Playwright specs, 8 of 9 pass. The quest journal spec
    expects "A Place to Work" to be active at the start, but that quest must
    first be accepted from Elder Plop, even when the journal is opened
    directly. That failure is not caused by the controls.

## Later (Not In This Plan)

- Gamepad and touch.
- A rebinding screen.
- Choosing which ability or potion sits on 5–0, and quick-use potions. See the
  [action dashboard idea](../../task/ideas/open/player-action-dashboard-and-loadout.md).
