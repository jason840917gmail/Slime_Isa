# Weapon Icon Source of Truth Implementation Plan

## Status

Ready for implementation. This is a bounded refactor: one authored icon pair
drives Crafting, Inventory, and the hotbar, and Weapon Studio can set that pair
with a live preview. Runtime, Studio, save-boundary, and repository checks all
reject an invalid manifest frame instead of allowing Phaser's first-frame
fallback.

## Player / author outcome

- Crafting cards, inventory slots/details, and hotbar slots show the same
  weapon tile.
- That tile is exactly `weapon.iconKey` + `weapon.iconFrame`.
- If either field is missing, or the Phaser texture is not loaded, no image
  is drawn. There is no silent fallback to an animation frame.
- Weapon Studio authors the pair on the animation workbench, with a preview.
- Save refuses a weapon that is missing either field and shows the reason in
  the existing studio notice.

## Current baseline

| Surface | Current source | Problem |
|---|---|---|
| Crafting | Item `icon` + `iconFrame` copied from the weapon at boot | Already the authored pair; Stone Spear is wrong only because `iconFrame` is `0` on the stone-tools sheet |
| Inventory | `createWeaponThumbnail` first, then item icon/frame | Thumbnail uses the first right-attack animation tile, so it usually wins and ignores the authored icon |
| Hotbar | Same thumbnail helper; fallback is `item.icon` with **no** frame | Same animation-tile preview; fallback can show the wrong sheet tile |
| Weapon Studio | No icon UI | `iconKey` / `iconFrame` are hand-edited in `weapon.json`. New weapons get `iconKey: 'weapon-generic'` and no frame |
| Save validation | `typeof iconKey === 'string'` | Empty string passes. `iconFrame` is never checked |

`iconKey` is a Phaser **texture key** (`weapon-player-stone-tools-tiles`), not
a manifest asset id (`weapon.player.stone-tools-tiles`). Studio animation
layers use asset ids. The icon picker must write `entry.textureKey`.

## Decisions and invariants

- `iconKey` + `iconFrame` are the only runtime thumbnail source for weapons.
- `iconFrame` is required for v2 and normalized weapons and is an integer
  `>= 0`. Single-image / procedural textures use `0`.
- Missing or unloadable icon means **no image**, not a substitute tile.
- Studio writes `iconKey` as the catalog `textureKey`. It never writes an
  asset id into `iconKey`.
- Save uses the shared `validateWeaponDefinition`. The first issue becomes
  the studio notice. Do not add a second notification system.
- New weapons start with `iconKey: ''` and `iconFrame: 0`. The empty key keeps
  the draft type complete while save still forces an explicit pick. Do not
  keep the `weapon-generic` default.
- Existing weapons that only have `iconKey` get `iconFrame: 0` in this slice.
- `migrateLegacyWeaponDefinition` preserves an authored `iconFrame` and uses
  `0` when a legacy definition omitted it. This compatibility default belongs
  in the existing migration boundary, not in runtime thumbnail rendering.
- Procedural keys (`weapon-generic`, `weapon-gauntlet`, `weapon-hammer`,
  `weapon-spear`) remain legal at runtime. Studio preview shows a labeled
  placeholder for them because they have no manifest `sourcePath`.
- The procedural key catalog has one owner shared by procedural texture
  generation, Studio validation, and `weapons:check`; do not maintain three
  unrelated allowlists.
- Do not change recipe data, item registry shape, or combat behavior.
- Do not teach Crafting to invent weapon thumbnails for potion outputs.
  Non-weapon items keep their own `items.json` icons.

## Work sequence

### 1. One pure resolver and one Phaser renderer

Add `src/game/content/weapons/procedural-weapon-icons.json` as the single
catalog for the four procedural texture keys. Import it from
`ProceduralAssetScene.ts`; `scripts/check-weapons.mjs` reads the same JSON.

Add a Phaser-free `src/game/content/weapons/WeaponIcon.ts` containing:

- `resolveWeaponIcon(definition)`, which returns `{ iconKey, iconFrame }` only
  for a non-empty key and an integer frame `>= 0`;
- `weaponIconSelection(entry, frame)`, which returns the catalog
  `entry.textureKey` plus the selected frame. Studio uses this helper so an
  asset id cannot accidentally be stored in `iconKey`;
- `isProceduralWeaponIconKey`, backed by the shared JSON catalog.

Keeping this module free of Phaser and `WeaponCatalog` is required. The
existing esbuild-based Node test loader cannot bundle `WeaponThumbnail.ts`
because importing Phaser reaches the optional `phaser3spectorjs` dependency.

Change `src/game/ui/WeaponThumbnail.ts` so `createWeaponThumbnail`:

1. loads the weapon definition;
2. resolves the pair with `resolveWeaponIcon`;
3. returns `undefined` unless the pair exists and
   `scene.textures.exists(iconKey)`;
4. obtains the texture and confirms the requested frame exists. Accept either
   `texture.has(iconFrame)` or the procedural/single-image case where
   `iconFrame === 0` and the texture only exposes its `__BASE` frame;
5. otherwise returns `scene.add.image(x, y, iconKey, iconFrame)` at the
   requested size, with **no** rotation from animation transforms.

The explicit frame check is mandatory. Phaser's `Texture.get` falls back to
`firstFrame` when a named frame is absent, which would silently display the
wrong tile.

Update callers:

- `InventoryUI` slot + detail: keep `createWeaponThumbnail(...) ??` only for
  equipment. Remove the item-icon fallback for weapons. Non-equipment items
  still use `def.icon` / `def.iconFrame`.
- `WeaponHotbar`: same helper; if it returns nothing, keep the existing `×`
  empty mark. Do not draw `item.icon` without a frame.
- `CraftingUI.drawRecipe`: if `outputDef.equipment?.weaponId` is set, use
  `createWeaponThumbnail`. Otherwise keep the current item icon path.

### 2. Studio animation-strip editor

Live studio is `mountLayeredWeaponStudio`. The animation workbench is
`renderScopeControls` + `renderTimeline` in
`src/game/editor/LayeredWeaponStudio.ts`.

Add a compact **UI icon** control to `renderScopeControls`, always visible
(IDLE / ATTACK / ON-HIT). It is package-level, not clip-level.

Contents:

- a `frameSprite` preview when `iconKey` maps to a catalog spritesheet;
- a labeled placeholder chip when the key is procedural, and `No icon` when
  unset;
- sheet label + frame index;
- a `CHOOSE ICON` button that opens a dedicated picker, not the animation
  tile picker;
- a `CLEAR ICON` button that writes `iconKey: ''` and `iconFrame: 0` through
  the normal history/dirty mutation path.

Give the dedicated popup its own state so it cannot collide with the existing
animation tile picker: `iconPickerOpen` and `iconPickerAssetId`. Include those
fields in the appropriate reset/restore paths. Icon selection and clearing
must go through the existing `mutate` history wrapper so undo/redo and dirty
tracking remain correct.

Picker (new popup, modeled on `renderPicker` 918–924):

- list weapon-tagged spritesheets from `state.assets`;
- initialize the selected sheet from the current `iconKey` texture-key match,
  falling back to the first weapon-tagged sheet;
- show every frame with `frameSprite`;
- selecting a frame uses `weaponIconSelection(entry, frame)`, writes both
  fields through `mutate`, and closes.

`createWeaponDraft` must stop setting `iconKey: 'weapon-generic'`. Leave
`iconKey` as `''` and set `iconFrame: 0`.

Do not add this UI to legacy `WeaponStudio.ts`. That editor is not mounted.

### 3. Save-time validation and user notice

Tighten `validateCommonWeaponFields` in
`src/game/content/weapons/validation.ts`:

- `iconKey` must be a non-empty string;
- `iconFrame` must be an integer `>= 0`.

Add a separate pure catalog validator in `WeaponIcon.ts`. Given the Studio
asset-catalog shape, it must:

- accept a manifest spritesheet only when `iconFrame < frame.count`;
- accept a manifest single-image only with frame `0`;
- accept a shared-catalog procedural key only with frame `0`;
- reject an unknown texture key or an out-of-range frame.

Run that catalog validation in both the Studio client save path and the Vite
save endpoint in `characterContentModulesPlugin.ts`. Pass the asset manifest
path/catalog into the weapon package handler rather than trusting that every
write came from the current browser UI. Both checks feed the existing error
response/topbar notice; do not create another notification system.

`savePackage` already does:

```
const weaponIssues = validateWeaponDefinition(state.draft);
if (weaponIssues.length) throw new Error(weaponIssues[0]);
```

The mount error path already puts that message in `state.notice` with
`is-error`. Confirm the thrown icon message is readable, e.g.
`weapon.iconKey: choose a UI icon before saving`. No extra modal.

Mirror the required pair in both v1 and v2 branches of `weapon.schema.json`:
`iconKey` has `minLength: 1` and `iconFrame` is required.

In `types.ts`, keep `LegacyWeaponDefinition.iconFrame` optional migration
input, but redeclare it as required on `LayeredWeaponDefinition` and
`NormalizedWeaponDefinition`. `normalize.ts` then copies it unconditionally.

In `migrateLegacyWeapon.ts`, write
`iconFrame: definition.iconFrame ?? 0`. Preserve a nonzero authored frame.

### 4. Content backfill and `weapons:check`

Set `iconFrame: 0` on every authored weapon that currently omits it
(pickaxe, basic-sword, basic-spear, wooden-axe, goo-gauntlet, slam-hammer).
Leave already-correct stone-tool / wooden-spear frames alone.

Do **not** “fix” Stone Spear’s frame in this slice unless playtest confirms
the wrong tile. The authored value stays `0` until the studio picker is used
to choose the real stone tile.

Extend `scripts/check-weapons.mjs`:

- require non-empty `iconKey` and integer `iconFrame >= 0`;
- if `iconKey` matches an `assets.json` `runtime.textureKey` whose source is
  a spritesheet, require `iconFrame < frame.count`;
- allow only procedural keys read from
  `src/game/content/weapons/procedural-weapon-icons.json`, and only at frame
  `0`;
- reject unknown texture keys instead of treating every non-manifest key as
  procedural.

### 5. Tests

Add `scripts/tests/weapon-studio/weapon-icon-source.test.mjs` (same loader
as the other weapon-studio tests):

- `resolveWeaponIcon` returns `{ iconKey, iconFrame }` only when both are
  populated;
- the test imports the Phaser-free `WeaponIcon.ts`, never
  `WeaponThumbnail.ts`;
- `weaponIconSelection` stores `entry.textureKey`, not `entry.assetId`;
- catalog validation accepts an in-range sheet frame and procedural frame
  `0`, and rejects unknown keys, out-of-range frames, and nonzero procedural
  frames;
- `validateWeaponDefinition` rejects missing / empty `iconKey` and missing /
  non-integer `iconFrame`;
- `normalizeWeaponDefinition` and `migrateLegacyWeaponDefinition` keep
  an authored `iconFrame`;
- migration defaults a legacy definition with no `iconFrame` to `0`;
- a fixture with both fields still validates.

Update the existing `weapon-v2-migration.test.mjs` assertions/fixtures where
needed so the stronger validation is exercised by the current migration
suite, not only by the new file.

Add a focused Studio state test for the exported icon selection/clear state
helpers: selection updates both fields, clear restores `''` + `0`, and both
paths mark the draft dirty through the same mutation boundary. If keeping
those helpers inside the DOM-heavy Studio prevents Node loading, extract only
the state transition into a small Phaser/DOM-free editor module.

No Phaser scene tests. Runtime proof is: craft / inventory / hotbar all show
the same authored tile after a studio save + game reload.

## Acceptance

1. Open Stone Spear in Weapon Studio. The animation strip shows the current
   icon preview (stone-tools frame 0).
2. Choose a different tile, save, reload the game. Crafting, inventory, and
   hotbar all show that tile.
3. Clear the icon on a draft and press Save. Save is blocked and the topbar
   notice names the missing field. `weapon.json` is unchanged.
4. Create a new weapon. Save is blocked until an icon tile is chosen.
5. A weapon with no valid icon shows an empty slot in inventory/hotbar and no
   output image in crafting.
6. Temporarily give a manifest-backed weapon an out-of-range frame. Studio
   save and the save endpoint reject it; runtime rendering does not substitute
   frame `0`.
7. `pnpm test:weapon-studio`, `pnpm weapons:check`, `pnpm typecheck`, and
   `pnpm build` pass. Run `pnpm check` when the complete local suite is
   available.

## Files

| File | Change |
|---|---|
| `src/game/content/weapons/WeaponIcon.ts` | Phaser-free pair resolver, selection helper, catalog validation |
| `src/game/content/weapons/procedural-weapon-icons.json` | Shared procedural texture-key catalog |
| `src/game/ui/WeaponThumbnail.ts` | Authored icon only; validate actual Phaser frame availability |
| `src/game/ui/InventoryUI.ts` | Drop weapon item-icon fallback |
| `src/game/ui/WeaponHotbar.ts` | Drop frameless `item.icon` fallback |
| `src/game/ui/CraftingUI.ts` | Weapon outputs use `createWeaponThumbnail` |
| `src/game/editor/LayeredWeaponStudio.ts` | Dedicated picker state/actions, preview, clear action, empty new-weapon default |
| `src/game/editor/character-studio.css` | Icon control and dedicated picker styling |
| `src/game/content/weapons/validation.ts` | Require populated `iconKey` + `iconFrame` |
| `src/game/content/weapons/types.ts` | Require frame on v2 and normalized weapons while legacy input remains optional |
| `src/game/content/weapons/normalize.ts` | Copy required normalized frame unconditionally |
| `src/game/content/weapons/weapon.schema.json` | Require `iconFrame` |
| `src/game/content/weapons/migrateLegacyWeapon.ts` | Preserve frame or default legacy input to `0` |
| `src/game/content/weapons/*/weapon.json` | Backfill missing `iconFrame: 0` |
| `src/game/infrastructure/assets/ProceduralAssetScene.ts` | Use shared procedural icon keys |
| `src/game/content/characters/characterContentModulesPlugin.ts` | Enforce catalog-backed icon validity at the save endpoint |
| `scripts/check-weapons.mjs` | Catalog-level icon checks |
| `scripts/tests/weapon-studio/weapon-icon-source.test.mjs` | New focused tests |
| `scripts/tests/weapon-studio/weapon-v2-migration.test.mjs` | Existing migration expectations for required/defaulted frame |

## Out of scope

- Changing Stone Spear’s authored frame (that is a content pick in Studio).
- Teaching Identity inspector or Combat inspector about icons.
- Generating image previews for procedural textures; labeled placeholders
  remain in scope.
- Item icons in `items.json`.
- Legacy `WeaponStudio.ts`.
