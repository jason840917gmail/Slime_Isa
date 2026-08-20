# Game Roadmap — Playable Task Checklist

> **Status: active living checklist.** Follow this in small vertical slices and
> update it as the game changes. The design direction lives in
> [Game Guidelines](./GAME_GUIDELINES.md); the larger beta reference remains
> [BETA_PLAN.md](./BETA_PLAN.md).

This roadmap is ordered for visible progress. A milestone is complete only when
the player can perform the loop in the running game and the authored map/editor
workflow supports the content it introduces.

The Wood Gathering tiles are implemented in code and content. The complete
loop has been verified in a fresh-game playtest.

## How To Use The Checklist

- `[ ]` not started, `[~]` in progress, `[x]` verified in the running game.
- Finish one milestone before expanding its next tier.
- After each milestone, do a short playtest and record one screenshot or note
  describing what became possible.
- Keep unresolved design choices in the open-question tasks instead of silently
  inventing rules.

## Progress Board

| Milestone | Player-visible result | Status |
|---|---|---|
| 1. Wood gathering | Chop a visible tree and collect wood | `[x]` |
| 2. Stone and starter tools | Gather stone and craft/use basic tools | `[ ]` |
| 3. Home exterior | Find and use one authored player home | `[ ]` |
| 4. Home interior | Enter a real interior, move inside, and return outside | `[ ]` |
| 5. Workbench | Craft the first improved tool at home | `[ ]` |
| 6. Iron region | Reach a tougher region and harvest iron with the right tool | `[ ]` |
| 7. Enemy materials | Fight enemies for special drops and access | `[ ]` |
| 8. Forge | Craft a stronger weapon or metal tool | `[ ]` |
| 9. Kitchen | Cook healing or buff food at the kitchen | `[ ]` |
| 10. Alchemy table | Brew a potion, antidote, or bomb from monster materials | `[ ]` |
| 11. Builder’s table | Upgrade and move the home while keeping its interior | `[ ]` |
| 12. Safety and persistence | Understand danger, recover, store items, and reload safely | `[ ]` |
| 13. Progression pass | Discover recipes and complete a balanced material path | `[ ]` |
| 14. Beta slice | Play a complete gather → fight → craft → upgrade loop | `[ ]` |

## Task Tile Format

Use this shape when adding a new task:

```md
### [ ] 1.1 — Short task name

- Build: the smallest implementation or content change.
- Player proof: what the player can see or do afterward.
- Done when: the concrete acceptance check passes.
```

## 1. Wood Gathering — First Complete Resource Loop

### [x] 1.0 — Add numeric resource damage modifiers

- Build: weapons now carry direct `{ targetTag, modifier }` entries; existing
  weapons use `resource: 0.1`, with normal damage as the fallback.
- Player proof: resource targets can be balanced independently from enemy damage.
- Done when: the weapon catalog and combat pipeline validate and apply numeric
  resource modifiers.

### [x] 1.1 — Add wood as a persistent material

- Build: define the stable wood item, stack rules, inventory display, and save data.
- Current: `wood` is registered, stackable, shown in the inventory, and included
  in saved inventory/world progress.
- Player proof: wood appears as a named resource instead of an anonymous pickup.
- Done when: collect, reload, and still have the same wood count.

### [x] 1.2 — Author harvestable tree objects

- Build: create tree object definitions with a harvest state, drop payload, and
  collision layer; place several instances in an authored map.
- Current: authored trees have colliders, health, wood drops, persistent state,
  and replace themselves with the catalog wood-pile visual.
- Player proof: trees are visible world objects that occupy space.
- Done when: the runtime and map validator accept the same tree IDs.

### [x] 1.3 — Add wood visuals and feedback

- Build: add the tree variants, hit/harvest feedback, wood pickup icon, and a
  small collection notification.
- Current: tree/pile art, wood inventory art, hit feedback, collection prompts,
  floating reward text, and the independent resource-impact effect are present.
- Player proof: chopping feels like an action, not an invisible counter change.
- Done when: the player can identify the tree, the hit, and the reward.

### [x] 1.4 — Add the starter gathering tool

- Build: add a starter axe or equivalent tool, equip/use flow, and the resource
  interaction that lets it harvest wood.
- Current: the Wooden Axe is a fifth starter hotbar item with directional art,
  wood `1.0` damage, non-wood resource `0.1` damage, enemy `0.2` damage, and a
  resource-only impact effect.
- Player proof: the tool visibly performs the action and produces wood.
- Done when: the player can harvest several trees without a debug shortcut.

### [x] 1.5 — Verify the first playtest loop

- Build: add any missing pickup, HUD, sound, or save feedback needed to make the
  loop readable.
- Player proof: explore → find tree → harvest → collect → see inventory.
- Current: user-verified in a fresh-game playtest; the complete loop works
  reliably.
- Done when: a five-minute fresh-game playtest completes the loop reliably.

**Milestone 1 complete:** the player can gather and keep wood through a normal
play session, verified in the running game.

## 2. Stone And Starter Tools

### [ ] 2.1 — Author stone resource nodes

- Build: add stone material, visible rock nodes, collision, map placement, deterministic three-pile drops, and reload-safe depletion state.
- Current: stone nodes use the large stone frame, carry 40 health, break into up to three adjacent small stone piles, and three test nodes are authored in Meadow Crossing. Partial node health resets on reload while broken piles and their remaining amounts persist.
- Player proof: wood and stone are distinct resources with distinct visuals.
- Done when: both resources can be collected and saved.

### [ ] 2.2 — Add basic tool recipes

- Build: make simple survival recipes for the starter axe, pick, or equivalent harvesting tools; keep these recipes portable where appropriate.
- Current: the Pickaxe is available in the sixth starter hotbar slot for testing, with directional art and an independent stone-chip impact effect. Crafting the Pickaxe remains a follow-up once the first recipe tier is authored.
- Player proof: gathered materials turn into a usable tool.
- Done when: a new save can craft and equip the basic tools without cheats.

### [~] 2.4 — Add shared Object Studio animation authoring

- Build: create a dedicated Object Studio using the shared Weapon/Character
  animation component. Keep a static base image required, with optional idle
  animation and resource-owned hit-effect packages. Add an Edit object link and
  animated preview to Map Studio without introducing per-instance overrides.
- Player proof: authored object motion and material-hit feedback are visible in
  the editor and consistent across every placed instance.
- Current: Object Studio route, shared object animation preview, static fallback,
  resource-owned hit effects, Map Studio linking, and runtime cleanup are
  implemented. A manual editor playtest remains before marking this task done.
- Done when: an object with no idle clip falls back to its static image, an
  authored idle clip updates all instances, and a resource hit effect plays only
  after positive damage.

### [ ] 2.3 — Enforce tool-gated harvesting

- Build: give resource nodes a required tool tier and show a clear feedback state
  when the tool is insufficient.
- Player proof: the player understands why a harder node cannot be harvested yet.
- Done when: the gate works consistently in runtime and authored maps.

**Milestone 2 complete when:** wood and stone form a readable starting economy
and basic tools open the first small progression gate.

## 3. Home Exterior

### [ ] 3.1 — Author the one player home

- Build: place one stable player-home instance in an authored map with its visual,
  collider, depth bounds, and interaction point.
- Player proof: the player can recognize a home and walk up to its entrance.
- Done when: the map editor, map check, and runtime agree on the same instance.

### [ ] 3.2 — Add home ownership and persistence

- Build: give the home a stable identity and save its placement, ownership, and
  current upgrade state.
- Player proof: the same home remains the player’s home after reload.
- Done when: no duplicate or fallback player home appears.

### [ ] 3.3 — Make the exterior functional

- Build: add the entrance interaction, home prompt, and the first home action
  such as resting or opening the home interface.
- Player proof: the player has a reliable reason to return home.
- Done when: entering the interaction range and leaving it are both clear.

**Milestone 3 complete when:** one authored, persistent home exists in the world
and is usable without procedural fallback.

## 4. Home Interior — Visuals, Logic, And Editor Support

### [ ] 4.1 — Define the interior map link

- Build: define a stable relationship between the exterior home instance and its
  authored interior map/room, including entry and return points.
- Player proof: entering a particular home always leads to its matching interior.
- Done when: the link is validated and survives save/load.

### [ ] 4.2 — Author the first interior visual kit

- Build: create an interior floor, walls, doorway, bed, and a small set of
  furniture visuals that follow the project’s object/depth conventions.
- Player proof: the interior feels like a room rather than a camera overlay.
- Done when: the complete room renders with coherent collision and depth.

### [ ] 4.3 — Add interior authoring to Field Cartographer

- Build: support creating/opening an interior map, painting its floor, placing
  furniture, setting the entrance/exit, and editing object visual/collider/depth
  guides with the same stable-ID rules as outdoor maps.
- Player proof: an editor change appears in the playable interior.
- Done when: an interior can be authored and saved without hand-editing JSON.

### [ ] 4.4 — Implement enter, move, and leave logic

- Build: transition from the exterior door into the interior, place the player at
  the authored entry, constrain the camera, and return to the exterior door.
- Player proof: walk inside, move around, then leave through the door.
- Done when: repeated enter/leave cycles do not duplicate players or lose state.

### [ ] 4.5 — Add interior collision and interaction

- Build: block walls and solid furniture, keep walkable floor clear, and connect
  bed/home interactions to the existing home system.
- Player proof: the room has believable boundaries and a useful bed/interior action.
- Done when: collision, interaction, and depth remain correct from every direction.

### [ ] 4.6 — Persist interior state

- Build: save the home interior’s furniture/upgrades and restore them when the
  player re-enters or reloads.
- Player proof: a change made inside the home is still there later.
- Done when: the exterior home, interior map, and save data remain in sync.

**Milestone 4 complete when:** the player can enter a visibly authored home,
walk through it, use it, leave it, and see the same interior after reload; the
map editor can create and validate the room.

## 5. Workbench — First Station-Gated Crafting

### [ ] 5.1 — Place the workbench in the interior

- Build: add a workbench object with interaction, collision, visual, and map-editor support.
- Player proof: the workbench is a real object in the home, not a menu-only button.
- Done when: it can be moved or replaced through the authored-map workflow.

### [ ] 5.2 — Give the workbench its recipe family

- Build: assign basic tools, repairs, storage, and building-part recipes to the
  workbench; show locked recipes clearly.
- Player proof: the player knows which recipes belong at this station.
- Done when: station proximity/interaction is required for progression recipes.

### [ ] 5.3 — Add the first workstation upgrade tier

- Build: add one upgrade step with a visible station change and a next-tier recipe.
- Player proof: improving the workbench immediately unlocks something useful.
- Done when: the tier and unlock survive save/load.

**Milestone 5 complete when:** the home is the first meaningful crafting destination.

## 6. Iron And Tool-Gated Regions

### [ ] 6.1 — Author the first tougher region

- Build: add a connected authored region with a distinct visual identity, map
  connection, and clear reason it is more dangerous.
- Player proof: leaving the starter area feels like progress.
- Done when: the region is reachable through the map editor’s authored links.

### [ ] 6.2 — Add iron nodes and improved harvesting

- Build: add iron material/nodes and the improved tool tier that can harvest them.
- Player proof: returning with a better tool opens previously blocked resources.
- Done when: the old tool fails clearly and the improved tool succeeds.

### [ ] 6.3 — Verify the tool-gated path

- Build: add map placement, feedback, inventory, and save coverage for the full
  wood → stone → iron path.
- Player proof: the player can name the next resource they are working toward.
- Done when: a fresh playthrough reaches iron without debug grants.

**Milestone 6 complete when:** tool upgrades open a new region and a new material.

## 7. Enemy Drops And Dangerous Access

### [ ] 7.1 — Add special enemy materials

- Build: define one enemy-gated material and add it to an authored enemy drop table.
- Player proof: fighting has a resource purpose beyond XP or coins.
- Done when: the material is collectible, visible, saved, and counted correctly.

### [ ] 7.2 — Make danger affect access

- Build: author a dangerous area with enemy presence, readable boundaries, and a
  reward path that uses the new material.
- Player proof: the player chooses whether the reward is worth the risk.
- Done when: enemies cannot appear in authored safe zones and the area remains fair.

### [ ] 7.3 — Connect enemy materials to crafting

- Build: add one recipe that cannot be completed without the enemy material.
- Player proof: defeating the enemy visibly advances a recipe goal.
- Done when: the complete fight → drop → craft chain works in one playtest.

**Milestone 7 complete when:** enemies gate a real crafting outcome and a dangerous
area has a meaningful reward.

## 8. Forge — Stronger Weapons And Metal Tools

### [ ] 8.1 — Place and author the forge

- Build: add the forge workstation, interior placement, collision, visual/depth
  guides, and interaction.
- Player proof: the forge has a distinct purpose from the workbench.
- Done when: the editor and runtime expose the same forge instance.

### [ ] 8.2 — Add forge recipe tiers

- Build: add weapons, metal tools, armor, and ore-upgrade recipes with workstation
  tier requirements.
- Player proof: the player sees a concrete next weapon/tool target.
- Done when: the first stronger weapon can be crafted from gathered and enemy-gated materials.

### [ ] 8.3 — Upgrade the forge once

- Build: add one forge upgrade with a visible change and a newly available recipe tier.
- Player proof: upgrading the station changes the player’s options immediately.
- Done when: the upgrade is persistent and cannot be bypassed by portable crafting.

**Milestone 8 complete when:** the player can turn rare materials into a stronger
weapon or metal tool at home.

## 9. Kitchen — Food, Healing, And Buffs

### [ ] 9.1 — Place the kitchen station

- Build: author the kitchen station and its map-editor/runtime interaction path.
- Player proof: the kitchen is visually distinct and easy to find inside the home.
- Done when: its recipe family is separate from workbench and forge recipes.

### [ ] 9.2 — Add food and buff recipes

- Build: add at least one healing recipe and one temporary buff recipe with readable
  item descriptions and use feedback.
- Player proof: preparation changes how the next exploration trip feels.
- Done when: crafted food persists and applies its intended effect once.

### [ ] 9.3 — Add one kitchen tier upgrade

- Build: add a station upgrade and one stronger recipe tier.
- Player proof: the kitchen has a reason to be upgraded.
- Done when: the next tier is locked until the station upgrade is complete.

**Milestone 9 complete when:** the player can prepare for exploration at home.

## 10. Alchemy Table — Potions And Monster Materials

### [ ] 10.1 — Place and author the alchemy table

- Build: add the table with collision, visual/depth guides, interaction, and save identity.
- Player proof: it reads as a separate progression station.
- Done when: it can be placed and edited through the map editor.

### [ ] 10.2 — Add potion-family recipes

- Build: add potions, antidotes, bombs, and at least one monster-material recipe.
- Player proof: enemy drops now unlock several preparation choices.
- Done when: ingredients, output capacity, and recipe feedback are reliable.

### [ ] 10.3 — Add the alchemy tier step

- Build: upgrade the table once and unlock a stronger recipe tier.
- Player proof: the player can see what the next expedition requires.
- Done when: tier ownership and crafted items survive reload.

**Milestone 10 complete when:** enemy materials support a clear preparation loop.

## 11. Builder’s Table — Upgrades And Moving The Home

### [ ] 11.1 — Place the builder’s table

- Build: author the station and its editor/runtime interaction path.
- Player proof: the home now has a visible construction center.
- Done when: its recipe family is distinct from crafting consumables and weapons.

### [ ] 11.2 — Add visible home upgrades

- Build: add one home upgrade that changes interior or exterior visuals, capacity,
  or available functionality.
- Player proof: resources spent at home produce a visible improvement.
- Done when: the upgrade is represented in authored content and saved state.

### [ ] 11.3 — Add furniture, storage, and defenses

- Build: add the first placeable furniture/storage piece and one defensive piece,
  each with clear collision and interaction rules.
- Player proof: the home becomes more useful and more personal over time.
- Done when: placed pieces are editable, persistent, and not duplicated on reload.

### [ ] 11.4 — Make the one home movable

- Build: add the move-home flow through the builder’s table; preserve the home’s
  stable identity, interior link, upgrades, furniture, and storage contents.
- Player proof: the player can relocate the home without losing its progress.
- Done when: moving once and reloading produces the same home at its new location.

### [ ] 11.5 — Verify map-editor support for moving home content

- Build: support placing/editing the exterior anchor, interior link, furniture,
  defenses, visual bounds, and collision guides in the editor.
- Player proof: editor-authored home content matches what appears in play.
- Done when: the map checker rejects broken home/interior references clearly.

**Milestone 11 complete when:** the home is visibly upgradable, useful, and movable
without losing its interior or persistent contents.

## 12. Safety, Recovery, And Storage

### [ ] 12.1 — Decide and document safety rules

- Build: resolve how map conditions and nearby enemies determine home safety,
  including what recovery is allowed when the home is unsafe.
- Player proof: the player can understand the current safety state.
- Done when: the rule is written before it is encoded in gameplay.

### [ ] 12.2 — Add safety and recovery feedback

- Build: show safe/unsafe state, recovery outcome, and any nearby-enemy reason.
- Player proof: returning home reduces uncertainty instead of creating a hidden rule.
- Done when: the same conditions always produce the same result.

### [ ] 12.3 — Add persistent storage

- Build: implement storage capacity, item transfer, save/load, and failure feedback.
- Player proof: the home can hold supplies for a later expedition.
- Done when: stored items remain correct after moving home and reloading.

### [ ] 12.4 — Verify recovery and no-loss behavior

- Build: test death, unsafe-home arrival, interrupted transitions, and full storage.
- Player proof: failure is understandable and does not silently erase progression.
- Done when: the agreed recovery/storage rules hold in repeated playtests.

**Milestone 12 complete when:** the home is a dependable planning point without
being an automatic invulnerability zone.

## 13. Recipe Discovery, Content, And Balance

### [ ] 13.1 — Decide recipe discovery

- Build: choose whether recipes are learned by station tier, exploration, quests,
  drops, or another documented rule.
- Player proof: the player knows how to find the next recipe.
- Done when: the discovery rule is written and testable.

### [ ] 13.2 — Set material tiers and biome distribution

- Build: define the exact wood/stone/iron/rare-material path and where each tier appears.
- Player proof: each new region introduces a recognizable resource goal.
- Done when: no recipe requires a material with no reachable source.

### [ ] 13.3 — Set enemy drops and recipe counts

- Build: author enemy drop tables and target recipe counts per workstation family.
- Player proof: fights and exploration advance the next station goal at a readable pace.
- Done when: early recipes are attainable and high-tier recipes remain aspirational.

### [ ] 13.4 — Tune progression pacing

- Build: balance harvest rates, station upgrade costs, tool durability/repairs if used,
  enemy difficulty, and recipe outputs.
- Player proof: the loop feels motivating rather than stalled or finished too quickly.
- Done when: a fresh playtest reaches the next milestone without debug grants.

**Milestone 13 complete when:** the resource, enemy, station, and recipe systems
form one understandable progression path.

## 14. Beta Slice — Complete Playable Loop

### [ ] 14.1 — Run the full first-version loop

- Build: connect exploration, resource gathering, combat, drops, home return,
  station crafting, home upgrade, and tougher-area access.
- Player proof: the player always has a clear next goal.
- Done when: a fresh save can complete the loop without debug shortcuts.

### [ ] 14.2 — Verify authored-map workflow end to end

- Build: create or edit an outdoor region, home exterior, interior, resource node,
  enemy camp, workstation, and exit through Field Cartographer.
- Player proof: editor-authored content is playable immediately after validation.
- Done when: `pnpm maps:check` and the runtime agree on every authored reference.

### [ ] 14.3 — Do the motivation and readability pass

- Build: improve task feedback, loot visibility, station lock messaging, map hints,
  and milestone notifications where playtests show confusion.
- Player proof: progress feels visible after every short session.
- Done when: a new player can explain what to gather, where to go, and what to upgrade.

### [ ] 14.4 — Harden saves, transitions, and performance

- Build: test reloads, home moves, interior transitions, full inventories, enemy
  camps, and repeated station use; fix duplication, loss, and softlock cases.
- Player proof: progress feels safe enough to keep playing.
- Done when: the target beta loop is stable and no known progression blocker remains.

**Milestone 14 complete when:** Slime Isa delivers a motivating gather → fight →
upgrade home → craft → tackle tougher area loop with authored interiors and maps.

## Immediate Next Sprint

Start with Milestone 1 only:

1. Add the wood item.
2. Create one visible tree object with a collider.
3. Add the starter gathering tool.
4. Make the tree drop wood.
5. Show pickup feedback and inventory count.
6. Save and reload the result.

When those six tiles are checked, the game already has a new playable loop. Then
move to stone and the first tool gate instead of expanding every resource at once.
