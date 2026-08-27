# Resource Tag Source of Truth Implementation Plan

## Status

Ready for implementation. `game-constants.json` becomes the authoritative
closed catalog for harvesting resource tags. Editors only offer configured
tags, and save/check boundaries reject unknown values.

## Outcome

- Resource tags are configured once under `resources.tags`.
- The initial catalog is `wood`, `stone`, `iron`, `charcoal`, and `grain`.
- Weapon Studio harvest capabilities use only configured resource tags.
- Map Studio harvest requirements use only configured resource tags.
- Authored object and weapon files keep stable string IDs such as
  `"targetTag": "wood"`; array indexes never become persisted data.
- Existing unknown tags remain visible and removable, but block saving until
  corrected. They are never silently converted or deleted.
- Damage modifier tags remain open because they also target `enemy`,
  `resource`, and other non-harvest classifications.

## Decisions

- `src/game/content/game-constants.json` owns the ordered authoring catalog.
- Add `src/game/content/ResourceTags.ts` as the typed runtime/editor boundary.
  It exports `RESOURCE_TAGS`, `ResourceTag`, `isResourceTag`, and a validation
  helper.
- `ResourceTag` is a branded string because the JSON-derived list is typed as
  `readonly string[]`; no literal union can be inferred without duplicating
  the catalog. `isResourceTag` is the type guard that applies the brand after
  runtime membership validation. JSON and record keys still require runtime
  validation at every trust boundary.
- Resource tags are stable lowercase kebab-case IDs. Their list order controls
  dropdown presentation only and has no gameplay meaning.
- Do not replace item IDs, recipe IDs, texture keys, or general object tags
  merely because they contain words such as `wood` or `stone`; those are
  separate domains.
- `iron` is the harvesting category even when its drop item is `iron-ore`.
- JSON schemas continue checking structural string shape. Membership in the
  configured runtime list is enforced by TypeScript validators, editor save
  paths, and repository checkers because JSON Schema cannot safely import the
  constants document as a dynamic enum.
- Every server save request reads and validates the current
  `game-constants.json` before checking resource-tag membership. Open editor
  dropdowns are module snapshots and require a page reload after constants
  change; stale clients receive a validation response telling the author to
  reload. Repository checkers also read the current document each run.

## Work Sequence

### 1. Expand and expose the catalog

Update `src/game/content/game-constants.json`:

```json
"resources": {
  "tags": ["wood", "stone", "iron", "charcoal", "grain"]
}
```

Keep the existing schema and runtime validation requirements for a non-empty,
unique list of lowercase kebab-case strings.

Add `src/game/content/ResourceTags.ts`:

- derive `RESOURCE_TAGS` from the normalized, deeply frozen `GAME_CONSTANTS`;
- define a branded `ResourceTag` and expose membership through
  `isResourceTag(value: string): value is ResourceTag`;
- expose an optional issue helper for consistent unknown-tag messages;
- do not duplicate the five tag literals in TypeScript.

### 2. Close Weapon Studio harvest capabilities

Update `src/game/editor/WeaponTargetingEditor.ts`:

- populate the Harvest Capability select from `RESOURCE_TAGS`;
- add the first configured tag that is not already assigned;
- prevent reducers from adding or renaming a capability to an unknown tag;
- keep an existing unknown tag visible as an `unconfigured` option so it can
  be removed or replaced;
- block save through validation while an unknown tag remains;
- leave `damageModifiers.targetTag` as an open text field with suggestions
  defined exactly as `['enemy', 'resource', ...RESOURCE_TAGS]`.

Update weapon validation boundaries:

- `src/game/content/weapons/validation.ts` rejects capability keys absent from
  `RESOURCE_TAGS`;
- `scripts/lib/weapon-targeting-validation.mjs` accepts the configured tag set
  and rejects unknown keys;
- `scripts/check-weapons.mjs` loads `resources.tags` from
  `game-constants.json` and passes it to the helper.

### 3. Close Map Studio harvest requirements

Update `src/game/editor/MapEditorInspector.ts`:

- replace the Required tool tag text input with a select;
- include an empty `No requirement` option;
- populate choices only from `RESOURCE_TAGS`;
- display an existing unknown value as `unconfigured` until replaced or
  removed.

Update `src/game/editor/GameplayAttributeEditorState.ts`:

- reject non-empty `harvestTargetTag` values not present in `RESOURCE_TAGS`;
- apply minimum-tier and failure-message validation only while
  `harvestTargetTag` is non-empty, so selecting `No requirement` cannot be
  blocked by stale values that will not be serialized;
- continue omitting `harvestRequirement` when the selected tag is empty.

Update the object save endpoint in `vite.config.ts` to read and validate the
current constants document on every request, then reject an unknown
`resourceNode.harvestRequirement.targetTag` before writing content.

Update weapon save handlers in
`src/game/content/characters/characterContentModulesPlugin.ts` to receive the
constants path, read and validate it on every create/update/save-package
request, and reject unknown capability keys before writing content.

### 4. Align repository object validation

Update `scripts/check-objects.mjs`:

- load and validate `resources.tags` from `game-constants.json`;
- require every harvest requirement target tag to be a configured member;
- retain existing tier and failure-message checks;
- report the object ID, invalid tag, and configured alternatives.

Current content should remain valid: the tree requires `wood`, the stone node
requires `stone`, and current weapon capabilities use only those tags.

### 5. Tests

Extend game-constants tests to verify:

- the checked-in list is exactly `wood`, `stone`, `iron`, `charcoal`, `grain`;
- the list is unique, validated, and deeply frozen;
- `isResourceTag` accepts configured tags and rejects unknown strings.

Extend Weapon Studio tests to verify:

- the dropdown contains exactly the configured list;
- add chooses the first unused configured tag;
- all configured tags already assigned produces the existing useful notice;
- reducer rename rejects an unknown tag;
- legacy unknown content remains visible as unconfigured and removable;
- weapon validation and `weapons:check` reject unknown capability keys;
- damage modifiers still accept `enemy` and other non-resource tags.

Extend Map Studio tests to verify:

- Required tool tag renders as a select with `No requirement` plus the five
  configured options;
- unknown draft values produce a validation error and cannot be saved;
- selecting an empty value removes the authored harvest requirement;
- selecting each configured value round-trips the stable string ID.

Add checker regression fixtures proving both object and weapon repository
checks reject an unknown tag such as `crystal`.

Add real endpoint tests with fixture constants and content files proving:

- `crystal` returns HTTP 400 from object and weapon save endpoints;
- rejected requests leave the target file byte-for-byte unchanged;
- configured tags are accepted and persisted;
- an empty Map Studio requirement removes `harvestRequirement`;
- changing the fixture constants while the server remains running affects the
  next save request, proving request-time catalog freshness.

### 6. Documentation and Verification

Update `docs/STUDIO_TABS.md` and relevant authored-map/object documentation to
state that harvesting resource tags are constants-owned stable IDs.

Run:

1. Focused game-constants, Weapon Studio, and Map Studio tests.
2. `pnpm constants:check`.
3. `pnpm weapons:check`.
4. `pnpm objects:check`.
5. `pnpm typecheck`.
6. `pnpm check`.
7. Browser verification in Weapon Studio and Map Studio, including unknown
   legacy-value handling and narrow inspector widths.

## Acceptance Criteria

- `resources.tags` contains all five requested tags and is the only harvesting
  tag catalog.
- Weapon Studio and Map Studio cannot author a tag outside that catalog.
- Client validation, save endpoints, and repository checks reject unknown
  harvest tags.
- Existing unknown values are visible and removable without silent mutation.
- Authored JSON stores stable string IDs rather than list indexes.
- Damage modifier tags remain open and retain current combat behavior.
- Existing tree, stone-node, and tool content remains valid.
- Focused tests and the complete repository check pass.