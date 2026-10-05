# Handoff: Chapter 2 iron path (roadmap 8.3–8.6), 2026-09-30

> **Superseded** by [the 2026-10-01 handoff](2026-10-01-chapter-2-built-handoff.md):
> 8.3–8.11 are built. One correction to the plan below: the red forge house is
> the player's home, so the Forge became a separate furnace beside it.

For a new session picking up the roadmap. Read `AGENTS.md`, then this, then
`docs/GAME_ROADMAP.md` ("Immediate Next Sprint" and milestone 8) and
`docs/superpowers/specs/2026-09-30-chapter-2-outline.md`.

## The owner's standing instructions

- Work through the roadmap **as independently as possible**, advancing as
  far as you can; ask only when a decision is really theirs.
- Generating art and sound with Magnific is pre-authorized ("plenty of
  credits"); report what was generated and the spend.
- Commit only when asked (they also ask other agents to commit the whole
  tree). Never push.
- Their own dev server runs on :3000. Verify on the `dev-verify-b` preview
  config (:3007) or `dev-verify` (:3005, often used by other sessions).
- Decisions from 2026-09-30 to respect:
  - The Workshop is postponed until after Chapter 2, as a workbench upgrade
    once the Forge makes iron bars. Chapter 2 crafts at the **workbench**.
  - The Stretch Lash is a **hook**: light things come to the slime, heavy
    things pull the slime to them. It does no damage.
  - The goo trail is a passive learned ability that no quest teaches yet.
  - The quest tracker is WoW style: up to four quests, main first.
  - Gulp forms use real skins: a pebble slime and a silk slime.

## State of the working tree

Last commits: `23aba52` (controls, plus everything before it), `8daa01c`
(merge), `7dbfec3` (browser specs) and `3bd72f5` (the scene-conversion ledger
now covers every content unit), the last two from worktrees the controls
session brought onto main.

**Uncommitted from this session** (round 5 and the start of 8.3/8.4):

- The quest tracker shows up to four quests:
  - `src/game/features/ui/QuestTrackerSurfacePort.ts`
  - `ui/quest-tracker.scene.json` (slots Quest1..4, actions `track-1..4`)
  - `src/styles.css` (`[data-scene-control-id*="/track-"]`)
  - `WorldScene.updateQuestWaypoint`, which uses `tracker.waypointQuest()`
- The Workshop is postponed:
  - `chapterOne.ts`: `theOldWorkshop` now needs the `chapter-2-complete`
    world flag.
  - `objects/workshop.scene.json`: new `lockedMessage`.
  - Docs: the roadmap (milestone 6 note, 8.4/8.6 text, parking lot), the
    outline, and `GAME_GUIDELINES.md` (station table).
- Gulp form skins:
  - `Sprite2DNode.setSkin` and the `WorldVisual.setSkin` interface.
  - `gulpForms.ts` gained `skinTextureKey`.
  - `WorldScene.restorePlayerTint` now swaps the skin.
  - `asset/characters/slime-form-{heavy,sticky}.webp`, registered as
    `character.player.slime.heavy/.sticky` in boot.
  - The script `scripts/characters/build-gulp-form-skins.py`, sources in
    `asset/Originals/characters/` (including the lossless player sheet
    `slime_normalized.png`).
- Gulp hint text uses `controlLabel('eat')` (Q). `GulpController` and
  `GulpWheelLayout` comments now say Q.
- `ui/ability-bar.scene.json`: `pnpm audio:wire` only re-ordered its click-sfx
  connections.
- Chapter 2 art, packed and registered:
  - `asset/MAPS/items/chapter-2-5x2.webp` = `sheet.items.chapter-2.5x2`,
    textureKey `items-chapter-2-5x2`, 64 px. Frames: 0 weaver fang, 1 iron
    bar, 2 Reinforced Pickaxe, 3 iron spear, 4 iron axe. 5–9 are free; raise
    `count` when using them.
  - `asset/MAPS/rocks/128x128-tile_2x1-iron-ore.webp` = `sheet.rocks.iron-ore.2x1`,
    textureKey `rocks-iron-ore-2x1`. Frame 0 is the node, frame 1 the rubble.
  - Pack script: `scripts/items/pack-chapter-2-art.py`. Sources are in
    `asset/Originals/items/chapter-2/` and `asset/Originals/props/iron-ore/`.
  - Shared helpers: `scripts/lib/white_cutout.py` (white-background cut-out)
    and `scripts/lib/game_webp.py` (`save_game_webp`).
- `scripts/migrations/universal-scene-conversion-ledger.json` holds the rehash
  plus four synced asset rows for the new art
  (`character.player.slime.heavy`, `character.player.slime.sticky`,
  `sheet.items.chapter-2.5x2`, `sheet.rocks.iron-ore.2x1`). Commit it with
  the assets.
- Everything uncommitted in the tree is from this session (all the files
  above, plus `docs/TOOLING.md`, `docs/CREDITS.md` and this handoff).
  `.claude/ledger-export/` is not ours.

All checks passed at handoff: typecheck, assets (including world sets), scenes,
audio, scene-ownership, quests; `test:gulp`, `test:ui`, `test:quests`.

## Next: 8.3 weaver fang and 8.4 iron and the Reinforced Pickaxe

Research is done. These are the facts and the minimal change list.

1. **Fang item.** Add `weaver-fang` to `src/game/content/items/items.json`:
   ```json
   { "id": "weaver-fang", "name": "Weaver Fang", "category": "material",
     "icon": "items-chapter-2-5x2", "iconFrame": 0, "description": "…" }
   ```
   `icon` is a **textureKey**, not an asset id. Also add `"weaver-fang": 99`
   to `game-constants.json` → `inventory.maxStackByItem`; `ItemCatalog`
   requires the keys to match exactly. Both files are conversion inputs, so
   run `node scripts/rehash-scene-ledger.mjs`, then `pnpm constants:check`.
2. **Fang drop (60 %).** Add `{ "itemId": "weaver-fang", "chance": 0.6 }` in
   two places: `src/game/content/characters/orb-weaver/character.json`
   (`enemy.drop.items`, which runtime reads) and
   `scenes/authored/characters/orb-weaver.scene.json` (EnemyScript
   `rewards.items`, a converter copy; keep them in sync). Drops go straight
   into the bag (`CombatController.ts` ~302–321).
3. **Weapon `reinforced-pickaxe`.**
   - `src/game/content/weapons/reinforced-pickaxe/weapon.json`: copy
     `stone-pickaxe/weapon.json` and change these:
     - `weaponId` and `displayName`.
     - `harvestCapabilities {"stone":2,"iron":2}`.
     - `damageModifiers` with `iron:1` **first**, then `stone:1`,
       `resource:0`, `enemy:0`. The first matching tag in the node's tag
       order wins.
     - `iconKey "items-chapter-2-5x2"`, `iconFrame 2`.
     - Keep the swing art (stone-tools frame 3). Iron-looking swing art is a
       later improvement; `weapon.player.pickaxe-tiles` is an existing iron
       pickaxe sheet.
   - Import it in `src/game/content/weapons/virtual-weapon-content.ts` (an
     explicit list for tsc, checks and tests).
   - Copy `scenes/authored/weapons/stone-pickaxe.scene.json` to
     `reinforced-pickaxe.scene.json`: sceneId `weapon.reinforced-pickaxe`,
     script `weaponId` and `harvestCapabilities`, renamed resourceIds.
   - List `sceneId('weapon.reinforced-pickaxe')` in `src/game/config.ts`
     (~86–95).
   - Add the tag `"weapon"` to `sheet.items.chapter-2.5x2` in
     `assets.json`. `weapons:check` requires weapon icons to come from
     weapon-tagged assets.
4. **Recipe.** In `RecipeCatalog.ts`:
   ```ts
   { id: 'craft-reinforced-pickaxe', name: 'Reinforced Pickaxe', station: 'workbench', tier: 1, uniqueOutput: true,
     description: '…', ingredients: [{ itemId: 'wood', count: 10 }, { itemId: 'stone', count: 15 }, { itemId: 'weaver-fang', count: 3 }],
     output: { itemId: 'reinforced-pickaxe', count: 1 } }
   ```
   Add `learnedByQuest: true` only when quest Q2 exists (8.10). Until then it
   would be locked with no way to learn it; there is no dev cheat for
   recipes. A "learn all recipes" button in the playground panel
   (`src/game/devTools.ts`) is a good addition. Update the hard-coded
   workbench list in `scripts/tests/crafting/crafting-service.test.mjs`
   (~325–328) and rehash the ledger.
5. **Iron node scene.** Create `scenes/authored/objects/resource-iron-node.scene.json`
   as a copy of `resource-stone-node.scene.json`:
   - Sprite subresource `sheet.rocks.iron-ore.2x1`, frame 0, 128 px.
   - Script `objectId` `resource.iron-node`, `tags ["iron","resource","solid"]`
     (`iron` first), `maxHealth` about 120.
   - `drop {"objectId":"collectible.iron-ore-pile","visualId":"iron-ore-pile","pieces":2}`
     (a pile holds 5 ore).
   - `harvestRequirement {"targetTag":"iron","minimumTier":2,"failureMessage":"Requires a Reinforced Pickaxe"}`.
   - Ore-clink, wrong-tool and ore-shatter sfx, as on `rock-amber-ore-mineable`.
   - List `sceneId('object.resource-iron-node')` in `config.ts` (~57–59).
   - Add a rule in `scripts/audio/wire-scene-audio.mjs` (~163–171; the
     stone-node rule is a `startsWith`), then `pnpm audio:wire`.
   - Optional: an archetype `objects/resources/resource-iron-node.json` plus
     an `ObjectCatalog.ts` entry.
   - Regrowth works by itself (5.5).
   - **The rubble frame is unused today:** destroyed nodes are freed. Showing
     rubble needs a small code change; it's optional.
6. **Placement.**
   - Playground grove: free spots around (200,1240) and (640,980).
   - Gloop Forest south-east, the future iron hollow: (2880,2496),
     (3008,2624), (2752,2688).
   - Instance pattern: override `body.position`, `script.mapId` and
     `script.instanceId`, with `persistenceKey "<map>.<instanceId>"`.
   - Optionally seed the playground test chest
     (`playground-test-chest.initialContents`) with `"weaver-fang": 3`.
   - Then run `pnpm assets:worlds`.
7. **Checks:** `pnpm typecheck`, `constants:check`, `assets:check`,
   `weapons:check`, `characters:check`, `enemies:check`, `objects:check`,
   `scenes:check`, `audio:check`, `scene-ownership:check`, `quests:check`,
   `test:ui`, `test:combat`, `test:scene-conversion`. Then play it headless
   (below).
   - **New since `3bd72f5`:** `test:scene-conversion` fails when a content
     unit (item, weapon, scene, asset…) has no ledger row. After adding
     content, run `node scripts/inventory-scene-conversion.mjs --sync`, then
     `node scripts/rehash-scene-ledger.mjs`, then `pnpm scene-ownership:check`.

**Known gaps to fix by 8.10:**
- Enemy drops never emit `collectible.collected`, so a `collect` objective
  ("Collect 3 weaver fangs") won't advance.
- `WorldScene.spawnItemDropIcon` (~2003) ignores `iconFrame`.
- `nearestSource` (quest waypoint) maps a node's harvest tag to item ids, so
  `iron` ≠ `iron-ore`.

## After that (outline order)

- **8.5 Forge.** Use the red forge house in Slimeshire (`house-world-solid--forge-red`)
  as a ruin with a restoration site. Follow the Workshop pattern in
  `objects/workshop.scene.json`: a story variant on a flag, a
  `game.restoration-site`, then a `game.workbench` station with
  `recipeContext: forge`. It needs ruined Forge art (Magnific, using the
  forge house as reference) and an `iron-bar` item (icon frame 1). Recipes:
  Smelt Charcoal (5 wood → 2 charcoal) and Smelt Iron Bar (2 ore + 1
  charcoal → 1 bar). The Forge never outputs weapons.
- **8.6 Iron gear at the workbench:** Iron Spear (10 wood, 4 bars) and Iron
  Axe (10 wood, 3 bars). Icons are frames 3 and 4. Weapon art: reuse the
  stone weapon swings first.
- **8.7 the Matron boss** (write a short spec first), **8.8 the forest hut**,
  **8.9 the Gulp and lash puzzles and Goo Hearts**, **8.10 the quests in
  `chapterTwo.ts`**, **8.11 the locked Crystal Caverns exit and the end card**
  (which sets `chapter-2-complete` and so also unlocks The Old Workshop).

## Practical notes

- **Magnific:** `gpt-2` with `transparentBackground` fails server-side right
  now. Generate on "a plain flat pure white background" and cut it out with
  `scripts/lib/white_cutout.py`, as `pack-chapter-2-art.py` does. Save through
  `save_game_webp` (`scripts/lib/game_webp.py`).
  - Style reference images uploaded this session: the slime player crop,
    the props sheet, and the item icons. Upload again in a new session; the
    guide explains how.
  - Spend this session: about 2,700 credits (images 100 each; sfx 10 each;
    background removal 3).
- **Headless play:** see the memory note "Brave headless verification".
  - Pattern: Playwright with Brave, `?map=playground`, click
    `[data-startup-choice="new"]`, then drive `window.__slimeGame.scene.getScene('world')`.
  - To reach a game module from the page, import the exact URL the app
    loaded, `performance.getEntriesByType('resource')` → the
    `/src/.../X.ts` entry. Vite gives recently edited modules a `?t=` URL,
    and a plain `import('/src/...')` would get a second copy.
  - The dev panel's "Playground" section (checkboxes) teaches abilities.
    Click the `<label>`, not the hidden input.
- **Coordination:** other Claude sessions often work in this tree: an art and
  water session, the controls session, a Playwright-specs worktree. Before
  editing `asset/assets.json` or the scene-conversion ledger, message them
  (ListAgents / SendMessage) and serialize.
  - `pnpm audio:wire` **always writes** (`audio:check` only compares); it
    re-orders sfx nodes in any drifted scene.
  - `pnpm assets:worlds` must follow any new world art.
- **Playwright:** run with `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH="C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" pnpm test:scene-browser`.
  Known failures before this round: global-audio, production-blocking:140,
  quest-ui:3, studio-controls:3. `7dbfec3` may have fixed some of them.
