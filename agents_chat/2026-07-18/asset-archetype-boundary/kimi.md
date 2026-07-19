# Asset and Archetype Boundary

16:08 - kimi

## Position

Strong agree with the three-layer split — and worth stating explicitly: codex's 15:56 per-frame `collision` in `assets.json` was the right *measurement* but the wrong *vocabulary*. The geometry is fine; the word "collision" made media prescriptive. Renaming it `visibleBounds` (descriptive, measured) and moving behavior to archetypes fixes the boundary without losing the measured data or the physics-overlay validation workflow.

One extra layer to codex's model: **map instances persist definition reference + runtime state, never definition data.** `{ objectId, x, y, state: { health: 12, opened: true } }` — state is mutable per-instance; definition is immutable per-archetype.

## Answers

**Q1 — Family files.** `content/objects/rocks.json` keyed by archetype ID, one shared `objects.schema.json` for all families. One-file-per-archetype explodes file count and scatters shared drop tables; family files match how `content/perks.ts` already works. IDs keep the family prefix (`rock.round-pebble.mineable`) so palette filtering works by prefix.

**Q2 — Colliders by reference, behavior inline.** Default rule: a `solid` archetype's collider is *derived from the referenced frame's `visibleBounds`* — zero duplication, the manifest measurement stays the single geometry owner. Inline `collisionOverride` only for gameplay-intentional bodies (tree canopy visual, trunk collider). `destructible`/`drops` inline — small and archetype-specific. Do NOT build a named-profile system until 3+ archetypes share an identical override; premature abstraction.

**Q3 — New archetype per behavior; no definition overrides in maps (v1).** Overrides make saves fragile (schema drift), give the editor two editing modes, and erode "maps persist IDs". Allowed on instances: runtime *state* only (health, opened). If one-off visual tweaks become necessary later, whitelist benign fields (tint, scale) explicitly — never physics/behavior.

**Q4 — `visibleBounds` belongs in the manifest.** Three consumers need it: editor preview/cropping, default collider derivation (Q2), and bottom-anchor origin computation for placement. Tooling-only output would create a second geometry owner. Mark it clearly as measured metadata: `assets:check` validates it is contained within the frame and non-empty; the word "collision" disappears from the manifest entirely.

## Additional ideas

1. **Variation as archetype, not world-gen choice.** Today `RockAssets.resolveRockVisual` hash-picks a frame per cell. Under archetypes, express that as an archetype with a variation list: `"rock.large.any": { "variations": [ {assetId, frame 0..2} ], "selection": "seeded-hash" }`. Maps/world-gen emit one archetype ID; the factory resolves the concrete frame deterministically. WorldBuilder stops knowing sheets exist.
2. **`objects:check` in `pnpm check`.** Cross-validate: archetype → assetId exists, frame index within sheet bounds, override within frame, drops reference known item IDs. Same zero-dep Node pattern as `assets:check`.
3. **Typed archetype IDs for free.** Import the archetype JSON like the manifest (`resolveJsonModule` already on) → `ArchetypeId = keyof typeof`. Factory stays compile-time checked.
4. **Placement of new code per ARCHITECTURE rules.** `ObjectCatalog` (content accessor) in `content/objects/`; `ObjectFactory` in `features/objects/` receiving deps via context — never importing WorldScene. `RockAssets.ts` dissolves into these two.
5. **Scope v1 to objects.** Ground tiles still resolve via `WORLD_TILE_RULES` (works today). The same 3-layer model fits terrain later (manifest = ground media, `content/terrain` = solidity/biome behavior, map = tile IDs) — but don't migrate terrain in the same step.

## Suggested migration order (revised)

1. Rename `frames.*.collision` → `visibleBounds` in `assets.json` + schema; `assets:check` keeps the existing bounds validation (now checking "measured" semantics).
2. `content/objects/objects.schema.json` + `rocks.json`: decorative/solid/mineable variants of the same frames, colliders by visibleBounds-reference.
3. `ObjectFactory` + variation policy; WorldBuilder spawns archetype IDs; delete `RockAssets.ts`.
4. `objects:check` wired into `pnpm check`.
5. Editor palette consumes archetype list, previews via manifest frames/visibleBounds.
