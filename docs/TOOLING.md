# Tooling Reference

Commands and scripts beyond everyday development. `package.json` is the source of truth for script names; this page explains what they touch. Script-only tools are run with `node` or `python` directly.

Python tools need Pillow; the ones marked **numpy** also need numpy.

## Verification

| Command | What it checks |
| --- | --- |
| `pnpm typecheck` | Three strict `tsc --noEmit` passes: `src/`, `vite.config.ts` (+ the dev plugins it imports), and the Playwright specs |
| `pnpm scenes:check` | Authored scene documents in `src/game/content/scenes/authored/` |
| `pnpm scene-ownership:check` | Retired editor/construction paths stay retired; reconciles the scene ownership ledger |
| `pnpm assets:check` | `asset/assets.json` against disk (paths, dimensions, orphans) |
| `pnpm maps:check` | Legacy `src/game/content/maps/*.map.json` conversion inputs (still read for new-run spawn and save validation) |
| `pnpm constants:check` | `game-constants.json` against its schema and the generated types (`pnpm constants:generate` after a schema edit) |
| `pnpm audio:check` | Scene audio wiring matches `scripts/audio/wire-scene-audio.mjs` |
| `pnpm quests:check` | Quest content |
| `pnpm visuals:check`, `characters:check`, `projectiles:check`, `weapons:check`, `effects:check`, `enemies:check`, `objects:check` | Per-domain content checks |
| `pnpm interiors:check` | Interior scenes match `scripts/interiors/interior_catalog.py` (Python; not part of `pnpm check`) |
| `pnpm functions:check` | Single-use function report (not part of `pnpm check`) |
| `pnpm test:<suite>` | Node `--test` suites under `scripts/tests/` (scene-*, combat, bosses, quests, npcs, persistence, progression, …) |
| `pnpm test:scene-browser` | Playwright specs; starts its own Vite server on `127.0.0.1:3101` |
| `pnpm check` | Everything above that is listed in its script, then `build` and Playwright. Slow — run it deliberately, not after every edit |

## Scene conversion

- `pnpm scenes:convert [-- --check | --apply]` — converts legacy content into scene documents (dry run by default).
- `pnpm scenes:regenerate` — **overwrites scene-owned documents** from conversion inputs. Hand edits made in Scene Studio are lost; only run it when replacing them is intended.
- `scripts/migrations/universal-scene-conversion-ledger.json` stores content hashes of the conversion inputs (`asset/assets.json`, `items.json`, `enemy-types.json`, `NpcDefinitions.ts`, `RecipeCatalog.ts`, `game-constants.json`, …). After editing one of them, `pnpm scene-ownership:check` fails with "Source hash changed"; review the diff, then run `node scripts/rehash-scene-ledger.mjs` and, if it reports stale output metadata, `node scripts/reconcile-scene-ledger.mjs --write`.

## Maps and worlds

The game plays world scenes (`src/game/content/scenes/authored/worlds/<id>.scene.json`, scene ID `world.<id>`). See [AUTHORED_MAPS.md](AUTHORED_MAPS.md).

- `node scripts/maps/build-level-1.mjs [--write] [--ascii]` — regenerates level-1 ("Slimeshire Meadow") from its deterministic layout: terrain, forest-wall border, Slimeshire town, Fatty's hedge maze, worm ruins, Webwood, river/lake/bridges, the Verdant Gate pocket, enemy/NPC areas and ground decals. Generated content lives under `gen-*` group nodes and `area-level-1-gen-*` areas and is replaced on each run; pinned nodes/instances (NPCs, Fatty camp, exit-1, resources) are kept and only moved. Hand edits to generated content are lost; hand-placed content (for example Goo Hearts) belongs under the world root, not a `gen-*` group. Dry run by default; after `--write`, run `pnpm audio:wire` (it re-sorts the ambience resource the builder moves).
- `node scripts/maps/scatter-decorations.mjs <world-id>... [--write]` — scatters walk-over ground decorations (leaves, twigs, roots, moss, pebbles, small mushrooms) over forest grounds as instances under a `decorations` node. Re-running replaces the previous scatter. Dry run by default.
- `pnpm maps:smooth -- <world-id>... [--write]` — removes single-cell terrain speckle in world scenes; only ever makes terrain more walkable. Dry run by default.
- `pnpm maps:bake` — rewrites the legacy `gloop-forest.map.json` and `crystal-caverns.map.json` from the deterministic generator in `scripts/lib/procedural-map-generator.mjs`. It does not touch world scenes. Gameplay never imports the generator.
- `node scripts/maps/convert-wall-tiles.mjs <world-id>... [--write]` — converts any remaining `crystal-wall`/`tree-wall` tiles into floor plus wall object instances. Dry run by default.

## Art pipelines

Sources live in `asset/Originals/` (unmapped in `assets.json`); packed runtime sheets land in `asset/MAPS/`. Register new runtime media in `asset/assets.json` and run `pnpm assets:check`. See [assets/README.md](assets/README.md).

- `pnpm grounds:pack [-- --only <sheet>]` (**numpy**) — builds each 19x19 (64x64 tile) `asset/MAPS/grounds/64x64-tile_19x19_<ground>.png` from `asset/Originals/grounds/{generated,legacy-sheets}/`, graded and made wrap-seamless for `sheet-wrap` tiling.
- `pnpm props:pack` (**numpy**) — packs `asset/Originals/props/` into bottom-anchored `asset/MAPS/rocks/<frame>x<frame>-tile_<cols>x<rows>-<name>.png` atlases (crystal cluster art for the `crystal-cluster-wall` object scenes).
- `python scripts/props/generate-wall-prop-scenes.py` (**numpy**) — generates the `object.crystal-cluster-wall.*` and `object.tree-forest-wall.*` wall scenes.
- `python scripts/props/pack-gulp-props.py` — packs the Gulp and secret props (cracked ground, sinkhole, cave ladder, silk cocoon, spider web, Goo Heart, pressure plate up and down) from `asset/Originals/props/gulp/` into `asset/MAPS/props/256x256-tile_8x1-gulp-props.png`, and the Gulp form badges from `asset/Originals/ui/gulp/` into `asset/UI/ui-gulp-form-icons-2x1.png`.
- `python scripts/props/pack-level-1-landmarks.py` — packs the level-1 landmarks (Verdant Gate closed/open, village well, footbridge) from `asset/Originals/props/level-1/` into `asset/MAPS/landmarks/320x256-tile_4x1-level-1-landmarks.png`.
- `pnpm items:pack` (**numpy**) — slices the item icon sources in `asset/Originals/items/` into the 64x64 atlases in `asset/MAPS/items/`; `asset/Originals/items/atlas-index.json` names every frame, including ones not yet wired to an item.
- `pnpm interiors:scenes` — regenerates one `object.interior-*` scene per interior atlas sprite from `scripts/interiors/interior_catalog.py` into `objects/interiors/<category>/`. Solid sprites get a shallow footprint collider; the catalog's `FOOTPRINT_SHARES` gives beds, tables, hearths and basins a deeper one that covers their floor depth. `python scripts/interiors/normalize-interior-sheets.py` (**numpy**) rebuilds the atlases themselves.
- `python scripts/houses/normalize-mushroom-houses.py` — packs the mushroom house exteriors from `asset/Originals/houses/` into a 320 px house sheet.
- `python scripts/houses/pack-workshop.py` — packs the Workshop exterior (frame 0 ruined, frame 1 restored) from `asset/Originals/houses/generated/workshop-*-source.png` into `asset/MAPS/Houses/320-workshop-2x1.png`, one shared crop box so the building does not shift when restored.

## Audio

- `pnpm audio:bake [-- --library <dir>]` — renders the synthesized SFX in `scripts/audio/cues.mjs` to `asset/audio/sfx/synth/` and rewrites the generated `audio.sfx.*` block of `assets.json`; `--library` re-imports the library takes listed in `asset/audio/CREDITS.md` (it empties `asset/audio/sfx/library/` first, so the parent folder must also hold a `magnific` copy of `asset/Originals/audio/magnific/`). Without `--library` the existing library files are kept.
- `pnpm audio:wire` — writes audio nodes/connections into scene JSON from the table in `scripts/audio/wire-scene-audio.mjs`.

## Dev server endpoints

`pnpm dev` adds dev-only Vite plugins that **write to the repository**: Scene Studio saves through `/__scene-studio/content` (into `src/game/content/scenes/authored/`, hash-checked) and `/__game-constants` serves and saves `src/game/content/game-constants.json` (no UI uses it since Character Studio was retired). An open Studio tab can therefore overwrite files you are editing by hand.
