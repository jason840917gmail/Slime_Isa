# WP15 ownership audit — final state

The read-only audit began with 250 ledger rows: 153 `convert`, 97 `retain`, and 204 `writerState: legacy`. Conversion proceeded one owner at a time, with consumers checked before retiring each writer or constructor. The ledger now has 143 `convert` rows, all `writerState: scene`, and 107 intentionally retained project-data rows. `node scripts/reconcile-scene-ledger.mjs` verifies all 143 conversion outputs against their preserved source hashes and stable IDs.

| Family | Decision | Live owner |
| --- | --- | --- |
| Maps, characters, combat, objects, effects, UI, audio, shared animations, terrain | Converted | Authored scenes and external resources; Scene Studio is the sole writer |
| NPC identity (5 rows) | Retained | Read-only `NpcDefinitions` project data used by quests and map references |
| NPC placement templates (5 rows) | Retained | Read-only object archetype project data used to resolve persisted map placements |
| Other project data and asset metadata (97 rows) | Retained | Domain catalog, map/save compatibility, or asset manifest as recorded per row |

The 22 converted object families have authored scenes and no legacy writer endpoint. Their source JSON and `ObjectCatalog` remain read-only for map and save validation; unused mutable visual override and placement editor APIs were removed. Source-hash-audited inputs and exact frozen copies of retired UI and terrain modules remain for deterministic conversion replay. Retained data stays outside scene nodes where it represents identity, economy, quests, assets, or backward-compatible persistence references.

`config.ts` mounts only Scene Studio. Legacy editor URLs redirect through `LegacyRouteRedirects.ts`. The old category editor shells and Vite write endpoints, `MapBuilder`, `ObjectFactory`, `NpcActor`, `Enemy`, `LegacyWorldAdapter`, and the chest/boss UI bridges have been removed. `WorldScene` delegates authored populations and interaction construction to the universal scene host. The player health domain service moved out of the compatibility directory.

`node scripts/check-scene-ownership.mjs` rejects unresolved conversion owners, retired paths, legacy constructor sites, category editor imports and Vite writers, production procedural generation imports, and browser persistence outside its infrastructure owner. `node scripts/reconcile-scene-ledger.mjs` checks conversion replay and output metadata. The final technical gate and user-only gameplay checklist are recorded in `universal-scene-final-report.md`.
