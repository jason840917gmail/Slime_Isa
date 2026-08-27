# Studio Tabs Contract

This document is the working reference for Character Studio, Projectile Studio,
and Weapon Studio. Shared layered animation packages are authored through
Weapon Studio and consumed by runtime adapters and Map Studio; object animation
does not have a separate editor route.

## 1. Shared architecture

The three tabs are editor views over different authored documents. They share the same visual language and asset catalog, but their gameplay data remains separate.

| Area | Owner | Responsibility |
| --- | --- | --- |
| Character editor | `src/game/editor/CharacterStudio.ts` and `CharacterDocumentState.ts` | Character package, visual set, clips, body, hitboxes, runtime behavior |
| Projectile editor | `src/game/editor/ProjectileStudio.ts` | Reusable projectile profile, move/impact clips, visual alignment, flight body |
| Weapon editor | `src/game/editor/WeaponStudio.ts` | Reusable weapon profile, idle/attack/impact clips, visual alignment, combat values |
| Shared tab navigation | `src/game/editor/StudioModeTabs.ts` | Switches between Characters, Projectiles, and Weapons |
| Shared animation library | `src/game/content/animations/` and `src/game/shared/animation/` | Complete layered packages, stable IDs, validation, catalog resolution, timing, rendering, and transforms |
| Media catalog | `asset/assets.json` and `characterAssetCatalog.ts` | Registered source paths, frame dimensions, grid size, tags, and runtime texture metadata |
| Editor server | `src/game/content/characters/characterContentModulesPlugin.ts` | Loads catalogs, imports PNG sheets, validates data, and writes authored packages |
| Runtime definitions | `src/game/content/characters`, `projectiles`, and `weapons` | TypeScript types, schemas, validators, and runtime-facing content |

The editor must not create a second asset registry. A source sheet is registered once in the manifest and then selected by its stable `assetId` from any compatible tab.

### Shared three-column layout

- Left: library/roster and create controls.
- Center: preview, source frames, animation timeline, and playback controls.
- Right: inspector fields for the selected document.

Projectile and Weapon Studio deliberately use the right inspector for authoring. The center keeps only visual preview and animation editing, matching Character Studio.

### Numeric field rule

Gameplay number controls use `step="1"`, integer input formatting, and integer normalization on update. Visual transform controls may use fractional steps where sub-pixel offsets, scale, or rotation are required for animation cleanup. This applies specifically to animation-occurrence transforms and existing scale/coefficient controls; gameplay dimensions and timing remain integer-authored.

The rule is about authored editor values. Boolean fields, IDs, labels, animation names, loop modes, and source paths remain non-numeric values. Weapon target damage modifiers are coefficients and deliberately allow fractional values; harvest capability tiers remain integers.

### Preview rule

Every preview has two independent layers:

1. The stable gameplay body/hitbox, positioned from world-unit fields.
2. The artwork sprite, positioned from visual offset fields.

Changing an artwork offset must move the sprite around the anchor without moving the body. Changing a body center or hitbox must move the collision guide without silently changing artwork alignment.

The preview must update in both paths:

- immediately while typing in a numeric field;
- after a full render caused by changing a select, checkbox, animation, source, or frame.

Use stable `data-*` markers when moving inspector sections. Do not depend on a numeric `nth-child` index because adding a field section changes the index.

### Source-sheet workflow

The common source flow is:

1. Open Source Library.
2. Show existing manifest entries filtered by the tab tag.
3. Either select an existing `assetId` or enter import metadata.
4. Choose a PNG file.
5. POST `metadata` and `file` to `/__character-studio/asset/register`.
6. Refresh `/__character-studio/assets`.
7. Assign the returned `assetId` to the current draft.
8. Rebuild animation defaults/clamped frames for the new frame count.
9. Close the shelf and render the selected source in the center preview.

Import metadata fields are `assetId`, `frameWidth`, `frameHeight`, optional `populatedCount`, `kind`, and the tab tag. Frame width and height must divide the PNG dimensions evenly. The server owns the final validation and writes the source under `asset/characters/authored/` using a safe dashed filename.

The shelf must be part of the tab's main render output, not appended by a separate one-off DOM path. That keeps the dialog, hidden file input, notices, and event delegation alive through every state update.

## 2. Character Studio

### Purpose and build

Character Studio edits a character package and its visual set together. The package owns runtime identity and behavior; the visual set owns the source sheet, clips, frame order, alignment, and visual transforms.

The editor loads the character package catalog from the virtual character-content module and saves through the package endpoints:

- `POST /__character-studio/package/update`
- `POST /__character-studio/package/duplicate`
- `POST /__character-studio/create`

Character source creation uses the shared asset registration route and then creates a package from the selected source.

### Center features

- Anchor-locked character preview.
- Grid, body, mirror, and onion-skin toggles.
- Source-sheet frame selection.
- Timeline frame ordering and drag/reorder.
- Clip tabs with add, rename, duplicate, and remove actions.
- Playback, previous/next frame, FPS, loop mode, and frame removal.
- Named hitbox span tracks and one-frame event markers.

### Inspector fields

| Section | Fields and features |
| --- | --- |
| Visual | Default offset X/Y, scale X/Y, selected animation offset X/Y, selected frame offset X/Y, reset buttons |
| Body | Shape, width/height or radius/radius X/radius Y, center X/Y |
| Attributes | Strength, Vitality, Agility, Intellect |
| Gameplay | Player movement/progression, or enemy AI behavior, health, ranges, speeds, cooldown, contact damage, knockback, resist |
| Capabilities | Enemy ranged attack, leap/charge, projectile asset, projectile damage, flee threshold, windup, recovery, leap range, projectile speed |
| Collision shapes | Named geometry primitives attached to authored hitboxes |
| Hitboxes | Width, height, offset X/Y, mirror flag, add/remove hitbox |
| Animation data | Source frames, FPS, loop, loop mode, hitbox spans, event IDs |

### Visual offset precedence

Character artwork resolves from least specific to most specific:

`visual.defaults.sourceOffset` → `visual.clips[clipId].sourceOffset` → `visualSet.frameVisuals[frame].sourceOffset`

The frame value wins when present. Scale and origin are resolved at the same default/frame level used by the visual transform. This exact precedence must be used by both the editor preview and runtime playback.

## 3. Projectile Studio

### Purpose and build

Projectile Studio edits a reusable projectile definition. It is not a character preview: the center shows only the projectile artwork, a world anchor, and the projectile collision body. The game supplies the player or target separately at runtime.

The editor uses `src/game/content/projectiles/types.ts` and validates/saves through:

- `GET /__character-studio/projectiles`
- `POST /__character-studio/projectile/create`
- `POST /__character-studio/projectile/update`

### Center features

- Projectile-only world-anchor preview.
- Source-sheet frame tiles.
- Separate MOVE and IMPACT animation tabs.
- Frame selection and comma-separated frame lists.
- FPS, loop, and loop mode controls.
- Collision body preview that stays separate from artwork.

### Inspector fields

| Section | Fields and features |
| --- | --- |
| Identity | Stable projectile ID, display name, tagged source asset, Source Library button |
| Animation tracks | MOVE and IMPACT frame lists, frame tiles, FPS, loop, loop mode |
| Visual | Default artwork offset X/Y; selected-frame override X/Y; reset selected-frame override |
| Physics | Shape, width/height or radius/radii, center X/Y, default speed, lifetime, rotate toward velocity |

### Projectile data and offset precedence

The data shape is:

```text
projectile
├─ projectileId, displayName, assetId
├─ animations.move
├─ animations.impact
├─ visual.sourceOffset
├─ visual.frameOffsets[frame]
├─ body
└─ movement
```

Projectile artwork resolves as:

`visual.sourceOffset` → `visual.frameOffsets[frame]`

The frame override wins when present. The body always remains anchored by `body.centerOffsetX/Y`; artwork offset never changes movement collision.

## 4. Weapon Studio

### Purpose and build

Weapon Studio edits a reusable weapon definition that can be selected by a character or loadout. The weapon artwork is a separate visual layer attached to the character anchor. No hands or player sprite belong in the weapon source sheet or the weapon preview.

The editor uses `src/game/content/weapons/types.ts`, `validation.ts`, and `weapon.schema.json`, and saves through:

- `GET /__character-studio/weapons`
- `POST /__character-studio/weapon/create`
- `POST /__character-studio/weapon/update`

Weapon source sheets use the shared asset catalog with the `weapon` tag. The source library now follows the same lifecycle as Projectile Studio: it is rendered from state, filters weapon-tagged assets, imports through the shared registration route, refreshes the catalog, selects the new asset on the draft, and rebuilds/clamps animation frames to the imported frame count.

### Center features

- Combined character-and-weapon preview around the character anchor, with Move, Scale, and Rotate drag tools plus onion skin.
- Separate red gameplay hitbox guide and artwork layer.
- SOURCE TILES bank containing immutable spritesheet tiles; clicking appends an occurrence.
- ANIMATION TILES strip containing the ordered clip occurrences, with multi-select, range-select, duplicate, delete, button reordering, and drag reordering.
- IDLE, ATTACK, and IMPACT animation tabs.
- A grouped four-direction ATTACK selector: RIGHT and LEFT appear under SIDE, while UP and DOWN appear under VERTICAL. Each direction owns its weapon clip, character-action pairing, hitbox geometry, hitbox track, and events.
- LEFT mirrors RIGHT by default. `MAKE CUSTOM LEFT` creates an independent left-facing package when mirrored artwork, offsets, timing, or hit points are not sufficient; `RESTORE RIGHT MIRROR` returns it to the linked mirror.
- Per-occurrence offset X/Y, scale X/Y, and rotation controls. Repeated uses of one source tile remain independently editable.
- Frame selection, advanced source-ID list, FPS, loop, and loop mode.
- Preview updates after editing visual offset, hitbox fields, frame, animation, or source asset.

### Inspector fields

| Section | Fields and features |
| --- | --- |
| Identity | Stable weapon ID, display name, melee/ranged category, character action key, description, tagged source asset, Source Library button |
| Combat profile | Base damage, cooldown, hitbox width/height, hitbox offset, active duration, knockback, unlock level |
| Targeting | Target-tag damage modifiers and resource-tag harvest capability tiers |
| Attribute scaling | Damage, cooldown, and knockback coefficients by character attribute |
| Visual | Global attachment offset X/Y and global weapon scale X/Y in source pixels/multipliers |
| Animation data | IDLE and IMPACT clips; directional RIGHT/LEFT/UP/DOWN ATTACK packages; ordered occurrences; per-occurrence offset, scale, rotation; FPS, loop, loop mode |
| Presentation | Character action relationship and separate weapon-layer behavior |

Targeting keeps two independent rule sets together without conflating them. A
harvest capability authorizes a hit when its tier meets the resource's minimum
tier. A damage modifier is applied afterward using the target's ordered tags;
`0` blocks damage and `1` applies normal damage. Damage-modifier tags remain an
open canonical-string domain; Weapon Studio suggests `enemy`, `resource`, and
every configured resource tag without restricting custom combat tags.
Harvest-capability tags are a closed catalog owned by
`game-constants.json#resources.tags`. Weapon Studio offers those stable IDs in
configured order, keeps legacy unknown values visible as unconfigured, and
blocks saving until an unknown value is replaced or removed. Changing the
catalog while Studio is open requires a page reload.

### Weapon visual offset

The weapon document stores profile-level transforms:

`visual.sourceOffset` and `visual.scale`

The preview multiplies source-pixel offsets by the same visible stage scale used by the weapon sprite. These values remain independent from `hitboxOffset`, which moves the red gameplay guide. Each animation occurrence may add `animation.frameTransforms[position]` with offset, scale, and rotation. Position—not source tile ID—is the key, so repeated source tiles can form different poses.

Attack data is authored under `directionalAttacks.right`, `.left`, `.up`, and `.down`. The legacy `.side` package remains readable and is migrated to `.right` when edited. An absent `.left` package inherits RIGHT and uses a true horizontal mirror: local `(x, y)` becomes `(-x, y)`, so vertical offsets and hit-point height are preserved. Missing RIGHT, UP, or DOWN data normalizes to the legacy root attack package. This preserves old weapons while allowing every direction to be materialized independently.

## 5. Shared animation packages

The shared animation library owns complete layered packages under
`src/game/content/animations/`. Each package has one `animation.json` wrapper
with searchable metadata, a stable globally unique `animationId`, and one
validated layered animation document. Package assets always resolve through the
global `asset/assets.json` catalog.

Weapon Studio is the first authoring surface for these packages. Its future
library view will browse weapons and animation packages together while reusing
the existing layered timeline, source picker, preview, and validation
components. Selecting a package opens the standalone shared animation editor;
the editor state must not depend on a fake weapon wrapper.

Weapon definitions and object templates store animation IDs only. Map Studio
will provide a reusable searchable picker for object-template `idleAnimationId`
and `onHitAnimationId` fields, but it will not contain a second timeline editor.
Runtime adapters resolve IDs through the shared catalog and provide anchors;
the shared clock, layered renderer, and transforms remain in
`src/game/shared/animation`.

Map Studio uses the same `game-constants.json#resources.tags` catalog for
object-template harvest requirements. `No requirement` omits the authored
`harvestRequirement`; configured choices persist their stable string ID rather
than a list index. Existing unknown IDs remain visible as unconfigured and must
be replaced or removed before saving.

## 6. Change checklist for future fields

When adding a field to any tab, update all of these layers together:

1. Type/interface.
2. JSON schema, when that document has a schema.
3. Validator and defaults.
4. Editor render field and stable `data-*` path.
5. Editor update handler with integer normalization where numeric.
6. Preview update function.
7. Runtime consumer.
8. Save/load route or package writer.
9. This document and the tab-specific field table.

For offsets specifically, verify all four states:

- default offset changes the preview;
- animation or frame override changes the preview;
- reset removes the override and falls back correctly;
- changing body/hitbox fields does not move artwork.

For source sheets specifically, verify all six states:

- existing tagged asset appears in the library;
- source select changes the draft and preview;
- PNG import validates dimensions;
- imported asset appears after catalog refresh;
- imported asset is selected on the current draft;
- animation frames remain inside the new sheet's frame count.

## 7. Verification procedure

For each tab, manually verify:

1. Open an existing document.
2. Change a default numeric value and confirm the center preview changes without a decimal display.
3. Change the selected animation and frame, then change the visual offset again.
4. Change a body or hitbox value and confirm only the gameplay guide moves.
5. Open Source Library, select an existing tagged source, and confirm the preview and frame count update.
6. Import a small PNG sheet, confirm it is selected automatically, author at least one frame in every required animation, and save.
7. Reload the tab and confirm the saved values persist.

Run the repository checks after editor changes:

```text
pnpm typecheck
pnpm assets:check
pnpm build
```

The source of truth for a new studio behavior is the relevant type/schema plus this document. If the same behavior is needed in another tab, add it to the shared contract first and then implement the three tab-specific adapters.
