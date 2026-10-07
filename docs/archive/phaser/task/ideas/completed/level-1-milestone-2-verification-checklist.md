# Level 1 and Milestone 2 Verification Checklist

## Status

Completed — the user verified Milestone 2 and the Roadmap P persistence
foundation in a playtest of the refactored build on 2026-09-28. Unchecked
boxes below were covered by that playtest and were not ticked one by one. The
Map Studio items were replaced by Scene Studio (see Roadmap tasks 2.4, 2.5, and
S.4).

Originally: the durable close-out checklist for Roadmap Milestone 2,
**Stone and starter tools**, and the parallel Roadmap P persistence foundation.

Do not mark Milestone 2 complete until every required checkbox below passes in
a genuinely fresh run without debug commands or automatic production gear
grants. Record short evidence beside each completed section: a screenshot,
save name, test output, or one-line playtest note is sufficient.

## Level 1 definition

`level-1` is the current authored starting/tutorial map. It is not the player's
experience level.

The intended player journey is:

`collect -> craft -> harvest -> fight -> chest -> key -> exit -> reload`

The authored starter budget is:

- four loose wood piles containing 40 wood total;
- two loose stone piles containing 20 stone total;
- reachable trees and stone nodes for the additional Stone Spear materials;
- one guarded camp leading to one persistent green key and the east exit to
  Gloop Forest.

## Confirmed decisions and remaining reconciliation

- [x] `level-1` is the canonical starter map. Confirmed 2026-08-24.
- [x] Retired starter-map references were removed from active code, tooling, and
  current roadmap documentation. Completed 2026-08-24.
- [x] Level 1 intentionally contains stone nodes with `80` life. Confirmed
  2026-08-24.
- [x] The stale roadmap text was corrected and the Map Studio test that expected
  `40` stone-node life was removed. Completed 2026-08-24.
- [x] Level 1 intentionally uses multiple stone-node visual variants. Confirmed
  2026-08-24.
- [x] A normal fresh player starts with no attack, including no Goo Gauntlet,
  and no equipped weapon. Confirmed 2026-08-24.
- [x] The initial-state, save schema, loadout, combat runtime, and UI accept an
  empty attack/loadout state; the old arsenal is development-only. Completed
  2026-08-24.

Evidence/notes:

> Pending.

## A. Fresh start and authored map

- [x] **New Run** starts on authored `level-1`.
- [x] **Reset Run** starts on the same authored map and spawn.
- [x] The player appears at the authored spawn with the expected facing.
- [x] The player initially has no attack and no equipped weapon.
- [x] No sword, spear, axe, pickaxe, hammer, or production test potion is
  automatically granted.
- [x] The legacy starter arsenal is available only through an explicit,
  development-only grant.
- [x] All loose starter materials are reachable without a tool, combat, or
  crossing a blocking collider.
- [x] The camp and east progression route do not block the safe collection area.

Evidence/notes:

> Pending.

## B. Walk-over starter materials

- [x] Walking over the four loose wood piles grants exactly **40 wood** total.
- [x] Walking over the two loose stone piles grants exactly **20 stone** total.
- [x] Loose materials require no `F` interaction and show no `F` pickup prompt.
- [x] Pressing `F` near loose material does not grant an additional pickup.
- [x] Each pile grants its contents exactly once.
- [x] Collection feedback and inventory counts agree.
- [x] Quest/event reactions do not double-count collection.
- [x] With a full inventory, the untransferred quantity remains in the world.
- [x] After freeing inventory capacity, the remaining quantity can be collected.
- [x] Saving after partial collection restores the exact remaining quantities.

Evidence/notes:

> Automated evidence: `pnpm test:collectibles` verifies authoritative event
> name, exact-once publication, transferred quantities, depletion before
> publication, berry reactions, and listener cleanup. `pnpm test:quests`
> verifies collection matching and staged quest progress with synthetic quest
> definitions; the production quest catalog intentionally starts empty.
> The remaining partial-inventory and save/reload rows still require verification.

## C. Starter crafting

- [x] Wooden Spear costs exactly `20 wood`.
- [x] Stone Axe costs exactly `10 wood + 10 stone`.
- [x] Stone Pickaxe costs exactly `10 wood + 10 stone`.
- [x] Stone Spear costs exactly `20 wood + 20 stone`. Issue (the tile is wrong, how is the tile pick, stope tile is in  2nd position )
- [x] The initial 40 wood and 20 stone can fund Wooden Spear, Stone Axe, and
  Stone Pickaxe in any order without a permanent softlock.
- [x] A failed craft consumes no ingredients and shows one clear reason.
- [x] A full-inventory craft consumes no ingredients.
- [x] Consumed ingredients may safely free a slot for the crafted output.
- [x] Each unique weapon/tool can be crafted only once.
- [x] A successful craft emits one inventory change and grants one output.
- [x] A crafted weapon/tool is assigned when a loadout slot is available.
- [x] When all loadout slots are occupied, the item remains safely owned and the
  UI explains that manual assignment is required.
- [x] Wrong-context and locked recipes cannot be crafted.

Evidence/notes:

> Pending.

## D. Harvesting gates and resource persistence

- [x] Innate attacks and spears cannot damage trees.
- [x] Innate attacks and spears cannot damage stone nodes.
- [x] Stone Pickaxe cannot harvest trees.
- [x] Stone Axe cannot harvest stone nodes.
- [x] Every wrong-tool attempt shows the authored requirement message.
- [x] A rejected hit does not change node life, play a successful-hit effect,
  persist damage, or spawn a drop.
- [x] Stone Axe damages and depletes trees normally.
- [x] Stone Pickaxe damages and depletes stone nodes normally.
- [x] Depletion spawns exactly the authored number of collectible pieces.
- [x] Drop placement remains deterministic when nearby cells are occupied.
- [x] Partially collected generated drops survive save/load with the same
  positions and remaining quantities.
- [x] Fully depleted sources remain depleted after reload.
- [x] Additional harvested materials are sufficient to craft the Stone Spear.

Evidence/notes:

> Pending.

## E. Guarded camp, chest, key, and exit

- [x] The existing worm camp keeps its ordinary refill behavior unchanged.
- [x] Fatty One Eye spawns only through the separate authored boss camp.
- [ ] Fatty has a round, mouthless body and one eye embedded at its exact center.
- [ ] Only Wooden Spear and Stone Spear hits that intersect the central eye deal damage.
- [ ] Fatty ignores knockback through the shared enemy effect-immunity field.
- [ ] Body collision requests one stationary 300 ms contact hop and deals no immediate damage.
- [ ] The contact hop shows its marker/shadow, is harmless while airborne, and applies at most one 64 px landing hit.
- [ ] Dodging or leaving the contact-hop circle before landing avoids the hit; repeated collision callbacks respect the one-second cooldown.
- [ ] A contact hop never cancels or postpones the three-hop special.
- [ ] Three small stationary hops telegraph a one-second leap to the player's locked position.
- [ ] The leap shows a moving shadow and landing marker, then deals landing-area damage and plays temporary ground cracks.
- [ ] Saving/loading, leaving, or dying mid-fight resets Fatty to full life without starting the defeat timer.
- [ ] A true defeat starts the authored three-minute wall-clock respawn timer.
- [ ] An eligible respawn waits for the player to exit and re-enter the activation perimeter.
- [ ] The reward chest is locked while Fatty is alive.
- [ ] Left-clicking a chest item shows its properties; right-click transfers the maximum stack amount that fits.
- [ ] With limited inventory space, the transferred amount is removed and the remainder stays in the chest.
- [ ] Partially looted contents survive save/load and the chest relocks if Fatty respawns.
- [ ] The Level 1 chest contains exactly one `green-key`; repeated interaction and reload cannot duplicate it.
- [ ] Once emptied, the chest remains visibly open and never relocks.
- [ ] The east exit refuses transition without the key and shows clear feedback.
- [ ] One green key unlocks the east exit and is consumed exactly once.
- [ ] The unlocked gate remains open after reload without another key.
- [ ] The exit transitions to Gloop Forest.
- [ ] Returning to Level 1 preserves resources, encounter, chest, and gate state.

Evidence/notes:

> 2026-09-11 implementation evidence: `pnpm assets:check`, `pnpm objects:check`,
> and `pnpm maps:check` validate the new sprite sheets, reusable chest object,
> authored Fatty One Eye camp, chest contents, and keyed exit. The combat suite
> passes 21/21, persistence passes 20/20 (including boss timers and partial
> chest contents), Map Studio passes 20/20 (including chest contents), and the
> strict production build succeeds. The rows above remain unchecked until the
> complete encounter, three-minute respawn, partial-loot, and reload flow is
> verified hands-on.

## F. Named save, load, recovery, and reset

- [ ] Existing records appear when **Save Game** opens.
- [ ] A new save requires a valid name and receives a stable ID.
- [ ] A duplicate name never overwrites silently.
- [ ] Canceling overwrite changes nothing.
- [ ] Confirming overwrite changes only the selected record.
- [ ] Save A and Save B remain independent and loadable.
- [ ] Loading restores inventory, equipment, hotbar, stats, quests, current map,
  position, facing, and every visited map's runtime state.
- [ ] Partial gathering and depleted resources agree after a named load.
- [ ] Camp, chest, and gate states agree after a named load.
- [ ] Level 1 and Gloop Forest retain independent runtime state.
- [ ] **Reset Run** restores the initial player plus untouched authored Level 1.
- [ ] Reset does not remove or modify named saves.
- [ ] Deleting one save removes only that selected snapshot.
- [ ] A corrupt save reports an error without mutating the active session or
  damaging valid saves.
- [ ] Recovery reflects the latest safe state without creating named save
  history.
- [ ] Complete a manual `Level 1 -> Gloop Forest -> Level 1` round trip using two
  named saves.

Evidence/notes:

> Pending.

## G. Animation, Weapon Studio, and Map Studio

- [ ] Migrated weapon animation packages preview correctly in Weapon Studio.
- [ ] Animation Studio can open, save, and reload the shared packages.
- [ ] A missing optional object animation uses the documented runtime fallback.
- [ ] Create one floor decoration from an existing spritesheet.
- [ ] Create one solid decoration, including an imported spritesheet case.
- [ ] Place both objects, save, reopen Map Studio, and verify visual identity,
  frame, scale, offsets, collision, depth, occlusion, and optional animation.
- [ ] Reopen the runtime and verify the placed objects match Map Studio.
- [ ] Wood, stone, and berries appear only under **Collectibles**.
- [ ] Trees and stone nodes appear only under **Resource Nodes**.
- [ ] Palette search finds objects by gameplay values such as item, quantity,
  life, tags, and tool requirement.
- [ ] **Visuals & Collision** and **Resource & Collectible Attributes** retain
  independent drafts, errors, and dirty state.
- [ ] Switching tabs or object selection never silently saves or discards edits.
- [ ] Keyboard tab navigation exposes the correct selected/tabpanel state.
- [ ] Edit and reload one collectible quantity and one resource-node life value.
- [ ] Choose a dropped collectible and visual, set 3 and 4 pieces, and verify the
  total-yield preview and exact runtime spawn count.
- [ ] **Use default** removes only the selected instance override and participates
  in undo/redo.
- [ ] Fatty remains visible in every Map Studio tool and selecting the preview opens the Boss Camp inspector.
- [ ] Activation and arena circles are independently editable, remain co-centered, and round-trip through undo/redo and save/reload.
- [ ] Guarded chest assignment supports **None**, prevents duplicate ownership, and preserves the chest when its camp is deleted.
- [ ] Camp mode, chest reward, and gated connection survive Map Studio save, reload, and validation.

Evidence/notes:

> Pending.

## H. Automated close-out

- [x] `pnpm weapons:check`
- [x] `pnpm objects:check`
- [x] `pnpm maps:check`
- [ ] Focused crafting and inventory transaction tests pass.
- [ ] Focused harvesting-gate tests pass.
- [ ] Focused encounter, chest, key, and gate tests pass.
- [x] Persistence tests pass.
- [x] Collectible runtime tests pass.
- [x] Map Studio tests pass, including gameplay-value palette search.
- [x] Shared animation and object-animation tests pass.
- [x] `pnpm typecheck`
- [x] `pnpm build`
- [ ] `pnpm check`

Evidence/notes:

> 2026-09-11: all content validators pass; combat passes 21/21, persistence
> passes 20/20, Map Studio passes 20/20, strict typecheck passes, and the
> production build succeeds. The literal `pnpm check` remains unchecked because
> it currently stops in an existing Character Studio fixture when Windows denies
> a temporary `assets.json` rename with `EPERM`. Resolve that fixture and add the
> focused encounter/chest/gate coverage before closing this section.

## I. Final fresh-run acceptance

- [ ] Start with cleared active/recovery progress and no debug query flags.
- [ ] Complete the full loop at default zoom:
  `collect -> craft -> harvest -> fight -> chest -> key -> exit`.
- [ ] Repeat the important navigation/combat checks at one overview zoom.
- [ ] Save/reload after partial collection.
- [ ] Save/reload after resource depletion.
- [ ] Save/reload after camp completion.
- [ ] Save/reload after chest opening.
- [ ] Save/reload after gate unlocking.
- [ ] Confirm no debug commands or automatic production grants were needed.
- [ ] Record a final screenshot or short playtest note.
- [ ] Mark Roadmap items 2.1–2.7 complete only after all relevant rows pass.
- [ ] Mark Roadmap P.1–P.5 complete only after the full persistence matrix passes.
- [ ] Mark Milestone 2 complete only after both groups are verified.

Final evidence/notes:

> Pending.

## Related documents

- [`docs/GAME_ROADMAP.md`](../../../../../GAME_ROADMAP.md)
- [`docs/superpowers/plans/2026-08-23-stone-and-starter-tools-implementation-plan.md`](../../../superpowers/plans/2026-08-23-stone-and-starter-tools-implementation-plan.md)
- [`docs/superpowers/plans/2026-08-24-walk-over-collectibles-and-editor-attributes-implementation-plan.md`](../../../superpowers/plans/2026-08-24-walk-over-collectibles-and-editor-attributes-implementation-plan.md)
- [`docs/superpowers/plans/2026-08-24-named-save-load-reset-implementation-plan.md`](../../../superpowers/plans/2026-08-24-named-save-load-reset-implementation-plan.md)
- [`docs/task/ideas/open/starter-stone-age-progression.md`](../../../../../task/ideas/completed/starter-stone-age-progression.md)
