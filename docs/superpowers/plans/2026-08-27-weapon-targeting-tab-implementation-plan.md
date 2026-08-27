# Weapon Studio Targeting Tab Implementation Plan

## Status

Ready for implementation. Weapon Studio gains a separate **TARGETING**
inspector tab for target-specific damage and harvesting permissions. This is
an authoring change only: runtime combat semantics and the weapon JSON format
remain unchanged.

## Author outcome

- An author can add, edit, and remove `damageModifiers` without editing JSON.
- An author can add, edit, and remove `harvestCapabilities` in the same tab.
- The UI makes the distinction explicit: a harvest capability permits a hit,
  while a damage modifier controls the damage after permission succeeds.
- Existing weapon values load into the controls and round-trip without loss.
- Invalid tags, modifiers, or tiers prevent save through the existing Studio
  notice and validation flow.
- Targeting edits participate in the existing dirty state and undo/redo
  history.

## Current baseline

| Surface | Current state | Required change |
| --- | --- | --- |
| Weapon schema and types | Both properties are supported | No format change |
| Weapon normalization | Both properties pass through when present | No runtime change |
| Legacy-to-v2 migration | Drops both targeting properties | Preserve both properties during migration |
| Combat runtime | Capability is checked first, then the matching damage modifier is applied | Preserve behavior |
| Weapon Studio | Neither property has controls | Add TARGETING tab and row editors |
| Shared validation | `damageModifiers` is validated; `harvestCapabilities` is not | Add capability validation |
| Inspector CSS | Tab grid is fixed at four columns | Support five tabs without wrapping |
| Repository checker | Checks tiers but accepts malformed containers and whitespace-only keys | Align with shared validation semantics |
| Studio documentation | TARGETING is not documented | Add tab ownership and fields |

## Decisions and invariants

- Add **TARGETING** between **COMBAT** and **LAYER**.
- TARGETING contains two independent sections rather than one combined table.
- **Damage by target** edits `damageModifiers` rows with `targetTag` and
  `modifier`.
- **Harvest capabilities** edits `harvestCapabilities` entries with resource
  tag and integer tier.
- A modifier is finite and `>= 0`. `0` blocks damage and `1` applies normal
  damage. Fractional values remain supported.
- A capability tier is an integer `>= 1`.
- Tags are canonical trimmed, non-empty strings. Validation rejects leading
  or trailing whitespace rather than silently storing aliases.
- `src/game/editor/WeaponTargetingEditor.ts` owns the suggestion constants,
  pure row renderers, and targeting mutations. General suggestions initially
  contain `enemy`, `resource`, `wood`, and `stone`; harvest suggestions contain
  `wood` and `stone`. Custom tags remain legal because weapon content is
  extensible.
- Duplicate modifier tags are rejected. Capability keys are unique by their
  record shape; renaming a key to an existing key is rejected without
  overwriting either value.
- Removing the final row removes the optional property instead of saving an
  empty array or object.
- Modifier row order is not presented as priority. Runtime chooses the first
  matching tag from the target's ordered tags, not the first modifier row.
- Do not add these controls to legacy `WeaponStudio.ts`; the mounted editor is
  `LayeredWeaponStudio.ts`.

## Field ownership

No currently exposed field moves to TARGETING.

| Tab | Fields |
| --- | --- |
| IDENTITY | Stable ID, display name, category, default character action, description |
| COMBAT | Base damage, cooldown, knockback, unlock level, directional hitboxes |
| TARGETING | Damage modifiers, harvest capabilities |
| LAYER | Asset, depth, occurrence transforms, timing blocks |
| ON HIT | Confirmed-hit effect selection and editing |

Two currently unexposed properties remain outside this change:

- `scaling` belongs in COMBAT because it changes the weapon's base combat
  profile from player attributes, not from target identity.
- `vfxColor` belongs with ON HIT or presentation if it becomes runtime-owned
  and authorable later.

## Work sequence

### 1. Add the inspector route

Update `src/game/editor/LayeredWeaponStudioMutation.ts`:

- Add `'targeting'` to `WeaponStudioInspectorTab`.
- Keep inspector tab selection in the existing history snapshots.

Add `src/game/editor/WeaponTargetingEditor.ts` as a Phaser-free module:

- own the general and harvest suggestion constants;
- render both targeting sections and their stable `data-*` controls;
- expose pure targeting mutation actions/reducers so behavior and generated
  markup can be tested without mounting Phaser or adding a DOM dependency.

Update `src/game/editor/LayeredWeaponStudio.ts`:

- Insert `['targeting', 'TARGETING', 'targets']` after COMBAT in the inspector
  tab list.
- Route the new tab to `renderTargetingInspector(state)`.
- Reuse the existing inspector section, field, icon-button, notice, dirty, and
  history conventions.
- Route delegated input and click events to the pure targeting mutations.

Update `src/game/editor/character-studio.css`:

- change `.layered-inspector-tabs` from four to five equal columns;
- add only the targeting-row layout rules needed for compact tag/value/remove
  controls;
- verify the labels and controls remain usable at the narrowest supported
  inspector width without creating a second tab row.

### 2. Build Damage by target controls

Render one compact row per `damageModifiers` entry:

- target-tag text input with the general suggestions;
- numeric modifier input with a fractional step and minimum `0`;
- icon-only remove button with an accessible label and tooltip.

Add an icon/text **Add target** command. It creates a valid row with modifier
`1` and chooses the first unused general suggestion, falling back to a unique
`target-N` placeholder. The new tag remains editable.

Use stable row indexes for modifier mutations. A tag edit must update only its
row, preserve array order, trim on commit, and reject a duplicate without
discarding the previous tag.

### 3. Build Harvest capabilities controls

Render one compact row per `Object.entries(harvestCapabilities)`:

- resource-tag text input with the harvest suggestions;
- integer tier input with step `1` and minimum `1`;
- icon-only remove button with an accessible label and tooltip.

Add an icon/text **Add capability** command. It creates tier `1` under the
first unused harvest suggestion, falling back to a unique
`resource-N` tag.

Capability key changes must be atomic: validate the trimmed replacement key,
then create the new key and remove the old key in one mutation. Never silently
overwrite an existing capability.

### 4. Preserve targeting during legacy migration

Update `src/game/content/weapons/migrateLegacyWeapon.ts` so
`migrateLegacyWeaponDefinition` copies authored `damageModifiers` and
`harvestCapabilities` into the v2 definition, following the existing optional
spread pattern used for `scaling`.

This compatibility path is required even though the current repository has no
authored v1 weapon files: `LegacyWeaponDefinition` legally contains both
properties, and the mounted Studio migrates v1 definitions before editing.

### 5. Complete shared and repository validation

Extend `validateCommonWeaponFields` in
`src/game/content/weapons/validation.ts` so an authored
`harvestCapabilities` value must be:

- a non-array object;
- composed of non-empty, trimmed keys;
- composed of integer tiers `>= 1`.

Strengthen the existing `damageModifiers` checks so each `targetTag` equals its
trimmed value and duplicate detection uses the trimmed value. This prevents
`stone` and ` stone ` from being treated as distinct runtime tags.

Update `scripts/check-weapons.mjs` to enforce the same capability-container,
canonical-key, and tier rules at the repository boundary. Direct checks are
acceptable here if importing the shared TypeScript validator would complicate
the existing checker; semantic parity and regression coverage are mandatory.

Studio save already validates both the live draft and the stripped save
document; surface the first issue through the existing notice.

Do not change `weapon.schema.json`, `normalize.ts`, `types.ts`, or runtime
combat unless implementation reveals a contract mismatch. They already own
the required data shape and behavior.

### 6. Focused tests

Add a targeting mutation test under `scripts/tests/weapon-studio/` using the
existing TypeScript module loader pattern. Cover:

- adding the first modifier and capability;
- editing tags and numeric values;
- removing the final row and restoring `undefined`;
- rejecting duplicate modifier tags;
- rejecting a capability-key collision without data loss;
- dirty tracking and undo/redo through `commitWeaponStudioMutation` and
  `applyWeaponStudioHistory`.

Add a Phaser-free renderer test for `WeaponTargetingEditor.ts` and a narrow
Studio integration/source test. Verify:

- five tabs are declared in IDENTITY, COMBAT, TARGETING, LAYER, ON HIT order
  and the CSS defines five columns;
- existing multi-row modifier and capability values appear in their controls;
- add, edit, and remove controls expose the intended stable action markers;
- modifier inputs use `min="0"` and a fractional step;
- tier inputs use `min="1"` and `step="1"`;
- remove buttons have specific accessible labels and tooltips.

Extend `scripts/tests/weapon-studio/weapon-v2-migration.test.mjs` to prove both
targeting properties survive v1-to-v2 migration. Add focused validation and
checker tests covering malformed capability containers, empty and
whitespace-padded tags, duplicate tags after trimming, fractional tiers, tier
`0`, and valid multi-entry targeting data.

### 7. Documentation and verification

Update `docs/STUDIO_TABS.md`:

- add TARGETING to Weapon Studio's inspector fields;
- document modifier and capability semantics;
- note that fractional modifiers are an allowed coefficient exception to the
  general integer gameplay-field rule.

Run, in order:

1. The focused Weapon Studio targeting and validation tests.
2. `pnpm typecheck`.
3. `pnpm check`.
4. Manual Studio verification: load the wooden axe and stone axe, add/edit/
   remove both row types, exercise undo/redo, save, reload, and confirm exact
  JSON round-trip. Resize the inspector to its narrowest supported width and
  confirm all five tabs stay on one row and targeting controls remain usable.

## Acceptance criteria

- TARGETING appears between COMBAT and LAYER in the mounted Weapon Studio.
- Both authored properties are fully editable without raw JSON changes.
- Existing weapons with missing, one, or several entries render correctly.
- Legacy v1 targeting data survives the mounted Studio's v2 migration.
- Invalid values cannot be saved and produce a useful existing-style notice.
- Shared validation and `weapons:check` reject the same malformed capability
  containers, non-canonical tags, and invalid tiers.
- Renaming a capability cannot overwrite another capability.
- Empty sections serialize by omitting their optional property.
- Undo and redo restore complete targeting data.
- Five inspector tabs remain usable without wrapping at supported widths.
- Runtime damage and harvesting behavior is unchanged.
- Focused tests, typecheck, and the complete local verification sequence pass.