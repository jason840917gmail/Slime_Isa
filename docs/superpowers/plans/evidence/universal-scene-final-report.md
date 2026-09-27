# Universal Scene Node refactor — final implementation report

Date: 2026-09-26. Branch: `main`.

## Ownership and conversion

The initial WP15 audit found 250 ledger rows: 153 conversions, 97 retained project-data rows, and 204 rows marked with a legacy writer. The final ledger records 143 scene-owned conversions and 107 intentionally retained rows. The ten rows reclassified as retained are five NPC identities and five NPC placement templates whose IDs, character mapping, dialogue labels, and persisted map references are project data. All conversion outputs are replayed and checked against stable source hashes by `node scripts/reconcile-scene-ledger.mjs`; source-hash-audited inputs were preserved, including exact frozen copies of retired TypeScript owners. After the resource cleanup, the 34 shared animation package rows were removed with their sources, because weapons and trees embed those clips in their own scenes; the ledger now has 216 rows and 109 scene-owned conversions.

The production editor mounts Scene Studio only. Legacy editor URLs redirect to selected scene or resource contexts. Scene Studio edits common nodes and external resources, including tile sets and shared animation packages, with undo/redo and hash-checked saves. Authored SceneTrees mount maps, characters, combat, objects, effects, UI, and audio. Behavior is registered TypeScript ScriptNodes. The old category editor shells, Vite write endpoints, direct entity factories, world adapter, and temporary chest/boss UI bridges have been retired. The object catalog remains read-only for map and save validation; NPC identity and placement definitions remain project data. See [WP15 ownership audit](universal-scene-wp15-ownership-audit.md) and `docs/ARCHITECTURE.md`.

## Success criteria evidence

| Design criterion | Evidence |
| --- | --- |
| Common scene tree mounts live compositions | Scene integration and real Chromium/Phaser browser suites, including world, entity, UI, audio, pickup, combat, and transitions |
| One Scene Studio and shared inspector | Scene Studio route, resource editing, undo/redo, authoring handoff, and browser mounted-control suites; legacy route redirect coverage |
| No top-level family inspector branches | Shared property descriptors and `scripts/check-scene-ownership.mjs` source guard |
| Boss as ranked enemy and ordinary enemy capabilities | Boss and worm-brawler scene integration and browser combat fixtures |
| ScriptNode behavior with data-only documents | `scenes:check`, ScriptNode registry and scene runtime/integration tests |
| Reusable instances and reversible overrides | Scene content/runtime/integration tests for instance overrides and root swaps |
| Single writable owner | 109 scene conversion rows reconciled; no unresolved `convert` rows; ownership guard and retired writer scan |
| Explicit cleanup | Browser fixture canvas teardown, Phaser body/object counts, and scene lifecycle tests |
| Command and browser gates | `pnpm check`, production build, and 43 real Chromium cases passed; large-map performance is within the 10% gate (see below) |
| Final gameplay acceptance | Pending user-only checklist below |

## Verification

- `pnpm check`: passed on the final code, including all local content, conversion, runtime, integration, editor, UI, persistence, TypeScript, build, and browser stages.
- `pnpm build`: passed as part of `pnpm check`; Vite transformed 947 modules.
- `node scripts/reconcile-scene-ledger.mjs`: passed, 109 checked conversion units.
- `node scripts/check-scene-ownership.mjs`: passed.
- `node scripts/check-scenes.mjs`: passed, 235 scenes and 120 resources.
- Real Chromium/Phaser browser suite: 43/43 passed in 2.6 minutes (Microsoft Edge, via `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`).
- `git diff --check`: passed.

The final performance comparison ran the checked-in `baseline-performance.spec.ts` procedure (same map order, 1280 × 720 viewport, 120 warmup frames, 300 sampled frames) on the same machine for both trees: the pre-refactor baseline commit `eb6b5db` in a separate worktree, and the final code. The recorded Chrome executable is not installed on this machine, so both runs used Microsoft Edge (Chromium) through `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`; the earlier table in `universal-scene-baseline.md` came from a different browser run and is not mixed into this comparison.

| Map | Load ms baseline → final | Median frame ms baseline → final | p95 frame ms baseline → final | Final objects / bodies / cleanup |
| --- | ---: | ---: | ---: | ---: |
| `test-rectangle` | 1838.1 → 1760.2 (−4.2%) | 16.7 → 16.7 (0%) | 16.8 → 16.8 (0%) | 50 / 2 / 52 |
| `tiktok` | 2343.4 → 1930.9 (−17.6%) | 16.7 → 16.7 (0%) | 16.8 → 16.8 (0%) | 4664 / 457 / 5121 |

Both trees hold the display refresh rate at full speed, so wall-clock frame time alone cannot show a regression; that is why earlier samples swung between 18 and 83 ms p95 whenever the machine was busy. The stable measure is main-thread busy time per frame from a Chrome DevTools CPU profile over the same 300 sampled frames, also run at 4× CPU throttling to stand in for slower hardware. Three alternating runs per tree on `tiktok`:

| `tiktok` workload | Pre-refactor | Before performance fix | Final |
| --- | ---: | ---: | ---: |
| Busy ms per frame, 1× CPU | 6.27–6.55 | 8.27 | 5.39–5.64 |
| Busy ms per frame, 4× throttle | 28.7–31.4 | 89.3 | 25.6–26.4 |
| Median / p95 frame ms, 4× throttle | 16.7–33.3 / 33.4 | 83.3 / 100.0 | 16.7 / 33.4 |

Paired runs show the final code using 9–14% less main-thread time per frame than the pre-refactor game, so the 10% regression gate is met without an exception. Before the fix, the large-map cost grew faster than the throttle: each slow frame ran up to five fixed physics catch-up steps, and each step was dominated by these defects, now corrected:

- Area contact candidates were meant to come from Arcade's `overlapRect`, but the lookup read it from `physics.world` instead of the `ArcadePhysics` plugin. It was always undefined, so every area tested every contact participant each step (about 975 areas against 1432 participants on `tiktok`). `ContactRouter` now indexes participants in a uniform grid built from the same contact bounds the exact test uses. It only drops pairs whose bounds cannot intersect and visits candidates in registration order, so reported contacts and enter/exit order are unchanged. A randomized test checks this against an exhaustive scan, including edge-touching, oversized, and moving shapes.
- Each Area2D kept a hidden Arcade zone body re-synced every step only to feed that broken lookup; the zones were removed (1432 → 457 Arcade bodies on `tiktok`; the pre-refactor game had 1269).
- `CollisionShape2DNode.worldShape` rebuilt its shape and re-walked every ancestor for validation on each call. It now caches the shape by global-transform revision, resource, and angle, and still validates whenever any of those change.
- `Node2D` validated its cached world transform by recursing to the root on every read. Transform and ancestry changes now mark the subtree stale, so an unchanged read is constant-time; revisions still change only when the transform actually changes.
- HUD controls rewrote their text, classes, styles, attributes, and handlers every frame, and the layout adapter read element sizes between those writes, forcing a reflow per control per frame. Writes now happen only when the live DOM value differs, with identical resulting DOM.

The automated checks establish technical behavior; interactive gameplay acceptance remains with the user.

## User gameplay checklist

Gameplay testing: Not performed - reserved for user verification.

Perform these checks in the production build with a fresh new game and a backed-up existing save. For Scene Studio checks, run the development server and keep a copy of any scene/resource file before editing. A failure is any missing visual/audio cue, ignored input, stuck modal, incorrect state change, console error, or behavior that changes after saving and loading unexpectedly.

### Authoring

1. Open `?studio=scenes`, select a world scene and one object, character, combat, UI, audio, shared animation, and tile-set resource. Inspect common properties, change a reversible property, undo, redo, save, reload, and confirm the saved value and preview match. Check an instance override independently from its packed source; removing the override should restore the source value. Repeat with a resource referenced by two scenes and confirm both use the edited resource.
2. Open old character, animation, weapon, projectile, and map editor URLs. Each should land in Scene Studio with the intended scene/resource context and no alternate editing form. Report a blank route, wrong selection, duplicate writer, missing property, or stale preview.

### Combat

3. In a new game, equip a melee weapon and fight a normal enemy. Move and attack in all directions; verify contact timing, hit feedback, damage, immunity/knockback where expected, death/loot, and that attacks do not register outside the visible active region. Repeat near a wall and while quickly changing direction.
4. Fight Fatty in its authored encounter. Verify approach/engagement, phase changes, telegraphs, damage and invulnerability, boss UI, defeat, and respawn behavior after leaving and re-entering according to progression. Repeat after player death and after reloading a save. Report missing phase cues, duplicate bosses, stale health UI, or effects that linger after the encounter.
5. Use an ability/projectile against an enemy and a harvestable resource. Confirm collisions, effect placement, resource durability, requirement/failure feedback, drop quantity, and cleanup. Try an out-of-range target and a blocked path; no phantom hit or duplicated effect should occur.

### World and progression

6. Start a new game on an authored map, move through open ground, water/walls, doors/exits, and neighboring areas. Verify terrain transitions, blocking, camera, NPC/prop placement, minimap and world map alignment. Check a map edge, a tight corner, and return through an exit; no missing or duplicated population should appear.
7. Speak with a quest NPC, accept and advance a quest, collect an item from the world, harvest a node, and gain enough XP to level. Verify interaction prompts, quest text/progress, inventory quantities, level-up values, and that a depleted pickup/node stays depleted after leaving and returning.

### UI and audio

8. Open inventory, crafting, quest journal, map, pause/options, and chest UI with mouse and keyboard. Verify focus, close/reopen behavior, equipment/hotbar updates, crafting costs/results, chest transfer, and no click-through into gameplay. Repeat while another modal is open and after changing window size.
9. Check music/effects bus preferences, mute/unmute, and first-input browser audio unlock. The current asset catalog contains no audio files, so silence is expected; preference controls and persistence should still behave consistently. Report console audio errors or settings that reset unexpectedly.

### Save and load

10. Save after changing area, inventory, equipment, quest, chest, and resource state. Reload and verify the same map/position and domain state without duplicated pickups, enemies, props, or modal remnants. Load a backed-up older save as an edge case; report migration errors, lost progression, or invalid map references. Restore the backup after testing if needed.

Please report the build/commit, save type, map, steps to reproduce, expected and observed behavior, and a screenshot or console message for any failure. Explicit user approval after this checklist is required for final gameplay acceptance.
