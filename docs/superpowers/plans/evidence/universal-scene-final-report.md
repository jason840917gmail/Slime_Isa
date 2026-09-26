# Universal Scene Node refactor — final implementation report

Date: 2026-09-26. Branch: `main`.

## Ownership and conversion

The initial WP15 audit found 250 ledger rows: 153 conversions, 97 retained project-data rows, and 204 rows marked with a legacy writer. The final ledger records 143 scene-owned conversions and 107 intentionally retained rows. The ten rows reclassified as retained are five NPC identities and five NPC placement templates whose IDs, character mapping, dialogue labels, and persisted map references are project data. All conversion outputs are replayed and checked against stable source hashes by `node scripts/reconcile-scene-ledger.mjs`; source-hash-audited inputs were preserved, including exact frozen copies of retired TypeScript owners.

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
| Single writable owner | 143 scene conversion rows reconciled; no unresolved `convert` rows; ownership guard and retired writer scan |
| Explicit cleanup | Browser fixture canvas teardown, Phaser body/object counts, and scene lifecycle tests |
| Command and browser gates | `pnpm check`, production build, and 36 real Chromium cases passed; performance exception remains pending |
| Final gameplay acceptance | Pending user-only checklist below |

## Verification

- `pnpm check`: passed on the final code, including all local content, conversion, runtime, integration, editor, UI, persistence, TypeScript, build, and browser stages.
- `pnpm build`: passed as part of `pnpm check`; Vite transformed 936 modules.
- `node scripts/reconcile-scene-ledger.mjs`: passed, 143 checked conversion units.
- `node scripts/check-scene-ownership.mjs`: passed.
- `node scripts/check-scenes.mjs`: passed, 235 scenes and 120 resources.
- Real Chromium/Phaser browser suite: 36/36 passed in 5.6 minutes.
- `git diff --check`: passed.

The final full-suite performance sample used the same map order, viewport, 120 warmup frames, and 300 sampled frames as the recorded baseline in `universal-scene-baseline.md`:

| Map | Load ms baseline → final | Median frame ms baseline → final | p95 frame ms baseline → final | Final objects / bodies / cleanup |
| --- | ---: | ---: | ---: | ---: |
| `test-rectangle` | 4265.9 → 4123.3 (−3.3%) | 16.7 → 17.6 (+5.4%) | 16.8 → 18.3 (+8.9%) | 53 / 5 / 58 |
| `tiktok` | 4374.2 → 4698.4 (+7.4%) | 16.7 → 17.6 (+5.4%) | 16.8 → 34.9 (+107.7%) | 5623 / 1432 / 7055 |

Both final map runs released the fixture canvas. The large-map p95 exceeds the plan's 10% limit. Occlusion alpha-mask work was moved off world mount and batched by source frame; unchanged sprite presentation now avoids redundant Phaser writes. A viewport-culling experiment showed no p95 improvement and was removed. Repeated full and focused samples varied substantially (large-map p95 from 18.4 to 83.4 ms), so this result is not evidence of a stable 10% frame-time gate. WP15 requires a recorded user-approved performance exception if the limit is not met; that approval is pending.

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
