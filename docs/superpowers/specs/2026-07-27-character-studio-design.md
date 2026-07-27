# Character Studio

## Status

Approved design for implementation planning.

## Goal

Add a development-only Character Studio workspace for editing the existing
player and enemy content with a Godot-like spritesheet and animation workflow.
The studio must let an author:

- inspect, edit, preview, validate, and save existing character packages;
- duplicate an existing character into an independent package;
- create freely named animations from ordered spritesheet frames;
- set animation frames per second and looping;
- edit default and per-source-frame visual alignment;
- edit one stable movement body and named animation-timed hitboxes;
- edit the player's and enemies' current gameplay properties; and
- attach optional gameplay event tracks to any freely named animation.

Character Studio is a dedicated workspace in the existing Vite development
editor. It is not a narrow panel inside the map canvas.

## Product decisions

### Free-form animations

The editor and schemas must not define a fixed list of actions or directions.
There are no required `idle`, `walk`, `attack`, `die`, `up`, `down`, or `side`
slots. An author creates any stable clip ID, chooses any ordered frames, and
later calls that clip programmatically.

Examples include `walk-up`, `jump`, `sleep`, `sword-swing`, and
`victory-dance`. Adding a future `jump` clip must not require a schema change.
Direction is only part of a user-chosen clip name when the author wants it to
be.

Runtime animation keys are derived from `visualSetId + clipId`. They are not
authored or exposed as a normal editor field.

### Stable body

Each character has one stable movement body/hurtbox in world units. Animation
frames, source-art offsets, visual scale, and origin never resize or relocate
that body. Attack geometry is represented by separately named hitboxes with
animation-timed activation spans.

The first version supports rectangular bodies and rectangular attack hitboxes.
Additional shapes are future work.

### Existing spritesheet grids

The first version reads spritesheet frame dimensions, columns, rows, and frame
count from `asset/assets.json`. Character Studio shows that grid but does not
edit its slicing metadata.

A later Create New Character workflow may register a new manifest asset and
define a new spritesheet grid. That workflow is not part of this specification.

### Preview, not runtime hot reload

The studio preview updates immediately from the unsaved draft. Saving updates
content on disk. A running gameplay map does not hot-reload character changes
in the first version; the author reloads or reopens the map after saving.

## Non-goals

The following require separate follow-up designs:

- importing or slicing a brand-new spritesheet;
- a complete Create New Character wizard;
- animated world-object authoring;
- arbitrary AI behavior graphs;
- live hot reload into an active gameplay scene;
- polygon, circle, or skeletal collision shapes;
- animation blending or state-machine graph editing;
- per-frame movement-body resizing;
- replacing current player weapon hitboxes or enemy attack timing/damage with
  character tracks;
- enemy spawn-area authoring; and
- changing map files from Character Studio.

## Content organization

Editable character content moves into self-contained packages:

```text
src/game/content/characters/
├── character.schema.json
├── player-slime/
│   ├── character.json
│   └── visual-set.json
├── worm-archer/
│   ├── character.json
│   └── visual-set.json
├── worm-brawler/
│   ├── character.json
│   └── visual-set.json
└── worm-swordsman/
    ├── character.json
    └── visual-set.json
```

`character.json` owns gameplay identity and behavior:

- stable character ID and display name;
- character kind;
- visual-set reference;
- stable body geometry;
- named attack hitboxes;
- animation gameplay tracks;
- player movement and progression values; or
- enemy health, combat, movement, AI, projectile, effect, and drop values.

`visual-set.json` owns presentation:

- stable visual-set and manifest asset IDs;
- default origin, scale, and source offset;
- optional source-frame transform overrides; and
- freely named visual clips.

`asset/assets.json` remains the source of truth for media paths, texture keys,
spritesheet frame dimensions, columns, rows, and frame count.

The character schema lives at
`src/game/content/characters/character.schema.json`. Package character files
use `$schema: "../character.schema.json"`. The visual schema remains at
`src/game/content/visuals/visual-set.schema.json`; character-package visual
sets use `$schema: "../../visuals/visual-set.schema.json"`, while
non-character sets under `content/visuals/<folder>/` use
`$schema: "../visual-set.schema.json"`.

The visual catalog must discover validated `visual-set.json` files instead of
maintaining a hand-written TypeScript import list. The character catalog must
similarly discover validated `character.json` files. Character Studio must
never rewrite TypeScript imports to register duplicated content.

Discovery is provided by a Vite `characterContentModulesPlugin` virtual module,
not by client-side filesystem assumptions. For normal builds and development,
the plugin emits imports for:

- `src/game/content/characters/**/character.json`;
- `src/game/content/characters/**/visual-set.json`; and
- `src/game/content/visuals/**/visual-set.json`.

The plugin accepts server-owned character and non-character visual roots for
tests. Both browser code and server authoring endpoints receive the same roots,
so a fixture catalog and post-duplication reload see the same files. After a
duplicate, the development plugin invalidates the virtual module and requests
a full page reload. Production builds use only repository roots; clients
cannot supply or alter them.

The runtime may expose typed player and enemy adapters over the package catalog
so existing controllers retain focused interfaces. Gameplay systems must not
depend on editor document types.

## Character schema

Character definitions use a discriminated `kind` field. Shared fields are
validated identically, while player and enemy properties retain distinct
owners and constraints. The fields in this section are the complete editable
version-1 property surface. Adding another gameplay property requires a
schema, runtime-adapter, validator, and inspector-metadata change.

Normative enemy example:

```json
{
  "$schema": "../character.schema.json",
  "version": 1,
  "characterId": "worm-swordsman",
  "displayName": "Worm Swordsman",
  "kind": "enemy",
  "visualSetId": "enemy.worm.swordsman",
  "body": {
    "width": 36,
    "height": 26,
    "centerOffsetX": 0,
    "centerOffsetY": 9
  },
  "hitboxes": {
    "sword": {
      "shape": "rectangle",
      "width": 34,
      "height": 18,
      "offsetX": 25,
      "offsetY": 2,
      "mirrorX": true
    }
  },
  "animationTracks": {
    "sword-swing": {
      "hitboxSpans": [
        {
          "hitboxId": "sword",
          "from": 2,
          "through": 4
        }
      ],
      "events": [
        {
          "at": 2,
          "eventId": "attack-impact",
          "payload": {
            "strength": 1
          }
        }
      ]
    }
  },
  "enemy": {
    "maxHp": 90,
    "ai": {
      "aggroRange": 220,
      "attackRange": 38,
      "wanderSpeed": 28,
      "chaseSpeed": 75,
      "attackCooldownMs": 1500,
      "attackWindupMs": 400,
      "attackRecoveryMs": 400,
      "contactDamage": 37,
      "knockbackStrength": 260,
      "isRanged": false,
      "knockbackResist": 0.45
    },
    "drop": {
      "xp": 50,
      "coins": 10
    }
  }
}
```

### Common fields

| Field | Rule and editor metadata |
| --- | --- |
| `version` | Required integer `1`; hidden read-only field. |
| `characterId` | Required unique `^[a-z0-9]+(?:-[a-z0-9]+)*$` stable ID, 1–80 characters; read-only after creation. |
| `displayName` | Required trimmed string, 1–80 characters; Identity section. |
| `kind` | Required `player` or `enemy`; read-only after creation. |
| `runtimeRole` | Optional; only `primary-player` is valid and only on `player`. |
| `visualSetId` | Required unique `^[a-z0-9]+(?:[.-][a-z0-9-]+)+$` ID, 3–120 characters, owned by the same package; read-only after creation. |
| `body.width`, `body.height` | Finite numbers greater than zero, world units; Body section. |
| `body.centerOffsetX`, `body.centerOffsetY` | Finite numbers, world units from the character anchor; Body section. |
| `hitboxes` | Map of unique stable IDs to version-1 rectangle definitions. |
| `animationTracks` | Map keyed by a known clip ID in the package visual set. |

Exactly one saved player package has `runtimeRole: "primary-player"`.
Duplicating that package removes `runtimeRole`; duplication never changes the
active player. The Character Library lists every player package and marks the
primary one, so a non-primary duplicate remains reopenable. Changing the
primary player is not part of version 1 and remains a programmatic content
operation.

### Player fields

The `player` object is required when `kind` is `player` and forbidden for an
enemy. It contains the exact editable values currently owned by
`PLAYER_CONFIG`:

| Field | Rule | Unit / inspector section |
| --- | --- | --- |
| `name` | Non-empty string, at most 80 characters | Identity |
| `movement.baseSpeed` | Finite number `>= 0` | world units/second, Movement |
| `movement.boostSpeed` | Finite number `>= 0` | world units/second, Movement |
| `movement.dodgeSpeed` | Finite number `>= 0` | world units/second, Movement |
| `movement.dodgeInvulnerabilityMs` | Integer `>= 0` | milliseconds, Movement |
| `progression.baseMaxHp` | Finite number `> 0` | points, Progression |
| `progression.baseMaxEnergy` | Finite number `> 0` | points, Progression |
| `progression.hpPerLevel` | Finite number `>= 0` | points/level, Progression |
| `progression.attackPerLevel` | Finite number `>= 0` | points/level, Progression |
| `progression.defensePerLevel` | Finite number `>= 0` | points/level, Progression |
| `progression.energyPerLevel` | Finite number `>= 0` | points/level, Progression |

### Enemy fields

The `enemy` object is required when `kind` is `enemy` and forbidden for a
player:

| Field | Rule | Unit / inspector section |
| --- | --- | --- |
| `maxHp` | Finite number `> 0` | points, Combat |
| `ai.aggroRange`, `ai.attackRange` | Finite number `>= 0` | world units, AI |
| `ai.leapRange`, `ai.fleeRange` | Optional finite number `>= 0` | world units, AI |
| `ai.wanderSpeed`, `ai.chaseSpeed` | Finite number `>= 0` | world units/second, Movement |
| `ai.attackCooldownMs`, `ai.attackWindupMs`, `ai.attackRecoveryMs` | Integer `>= 0` | milliseconds, Combat |
| `ai.contactDamage`, `ai.knockbackStrength` | Finite number `>= 0` | points / world units per second, Combat |
| `ai.isRanged`, `ai.isLeaper` | Required boolean / optional boolean | AI |
| `ai.projectileSpeed` | Required finite number `> 0` when ranged; otherwise optional | world units/second, Combat |
| `ai.knockbackResist` | Finite number from `0` through `1` | ratio, Combat |
| `drop.xp`, `drop.coins` | Integer `>= 0` | rewards, Drop |
| `drop.items[*].itemId` | Known item-catalog ID | Drop |
| `drop.items[*].chance` | Finite number from `0` through `1` | probability, Drop |
| `drop.items[*].count` | Optional integer `>= 1` | quantity, Drop |
| `projectile.assetId` | Optional known manifest projectile asset ID; required when ranged | Projectile |
| `projectile.damage` | Finite number `>= 0` | points, Projectile |
| `impactEffect.visualSetId` | Optional known non-character visual-set ID | Effects |
| `impactEffect.clipId` | Known clip in that visual set | Effects |
| `impactEffect.distance` | Finite number `>= 0` | world units, Effects |

The root allows optional string `$schema` plus `version`, `characterId`,
`displayName`, `kind`, `runtimeRole`, `visualSetId`, `body`, `hitboxes`,
`animationTracks`, and the kind-specific `player` or `enemy` object. The common
required fields are `version`, `characterId`, `displayName`, `kind`,
`visualSetId`, `body`, `hitboxes`, and `animationTracks`. `hitboxes` and
`animationTracks` may be empty objects. `runtimeRole` is optional. Every
schema-owned object uses `additionalProperties: false`, except the explicitly
free-form event `payload` value described below.

The complete enemy `ai` required set is `aggroRange`, `attackRange`,
`wanderSpeed`, `chaseSpeed`, `attackCooldownMs`, `attackWindupMs`,
`attackRecoveryMs`, `contactDamage`, `knockbackStrength`, `isRanged`, and
`knockbackResist`. `leapRange`, `fleeRange`, `projectileSpeed`, and `isLeaper`
are optional subject to these cross-field rules:

- `isRanged: true` requires `projectile` and `ai.projectileSpeed`;
- `isRanged: false` forbids `projectile` and `ai.projectileSpeed`;
- `isLeaper: true` requires `ai.leapRange`;
- absent or false `isLeaper` forbids `ai.leapRange`; and
- `impactEffect` is independent and optional for either melee or ranged
  enemies.

`drop` requires `xp` and `coins`; `items` is optional. `projectile`, when
allowed, requires exactly `assetId` and `damage`. `impactEffect`, when present,
requires exactly `visualSetId`, `clipId`, and `distance`.

### Hitbox and animation-track shapes

Hitbox IDs, clip IDs, and event IDs use
`^[a-z0-9]+(?:[.-][a-z0-9-]+)*$` and are limited to 1–80 characters.

A hitbox requires exactly `shape`, `width`, `height`, `offsetX`, `offsetY`, and
`mirrorX`. Version 1 accepts only `shape: "rectangle"`;
`width` and `height` are finite numbers greater than zero; offsets are finite
numbers; and `mirrorX` is boolean.

An animation-track value allows exactly optional `hitboxSpans` and `events`
arrays; omitted arrays behave as empty. A hitbox span requires exactly
`hitboxId`, integer `from >= 0`, and integer `through >= from`. An event
requires exactly integer `at >= 0`, `eventId`, and optional JSON `payload`.

JSON Schema supplies constraints and carries `x-editor` annotations for
`section`, `label`, `unit`, `step`, and `help`. Runtime validation owns
cross-field and catalog-reference rules that JSON Schema cannot express.
Character Studio uses these annotations for fields but retains purpose-built
body, hitbox, item-drop, projectile, and effect controls instead of rendering
an arbitrary recursive JSON form.

Duplicated enemies become complete catalog entries and therefore become
available to map spawn rules after the required page reload.

## Visual-set schema version 1

The current unversioned visual-set format is legacy version 0. Version 1
removes persisted Phaser runtime keys and exposes authoring concepts directly:

```json
{
  "$schema": "../visual-set.schema.json",
  "version": 1,
  "visualSetId": "enemy.worm.swordsman",
  "assetId": "enemy.worm.swordsman",
  "defaults": {
    "origin": [0.5, 0.5],
    "scale": [1, 1],
    "sourceOffset": [0, 0]
  },
  "frameVisuals": {
    "17": {
      "sourceOffset": [-2, 1]
    }
  },
  "clips": {
    "walk-up": {
      "frames": [8, 9, 10, 11],
      "framesPerSecond": 8,
      "loop": true
    },
    "jump": {
      "frames": [28, 29, 30, 31],
      "framesPerSecond": 10,
      "loop": false
    },
    "sword-swing": {
      "frames": [16, 17, 18, 19, 20],
      "framesPerSecond": 12,
      "loop": false
    }
  }
}
```

The visual set requires exactly `version`, `visualSetId`, `assetId`,
`defaults`, optional `frameVisuals`, and `clips`, plus optional `$schema`.
`visualSetId` uses the 3–120-character dotted-ID rule above. `assetId` uses the
same syntax and must resolve through the manifest. `clips` requires at least
one entry.

`defaults` requires exactly `origin`, `scale`, and `sourceOffset`.
`origin` is two finite numbers from `0` through `1`; `scale` is two finite
numbers greater than zero; `sourceOffset` is two finite numbers.
`frameVisuals` keys are non-negative decimal source-frame indices. Each frame
override contains at least one of `origin`, `scale`, or `sourceOffset`, uses the
same ranges, and rejects other fields.

Every clip ID uses the 1–80-character stable-ID rule above. A clip requires
exactly a non-empty `frames` array, `framesPerSecond`, and `loop`. Frames are
non-negative integers within the manifest source-frame count;
`framesPerSecond` is finite, greater than zero, and no more than 240; `loop` is
boolean.

The shared runtime-key helper returns the collision-proof opaque encoding
`visual:<visualSetId.length>:<visualSetId>:<clipId>`. Callers never construct
or persist this value themselves.

Clip IDs are stable programmatic references. Renaming a clip updates
package-local animation-track references but cannot rewrite arbitrary
TypeScript callers. The rename and delete confirmations list known
package-local references and explicitly warn that programmatic callers may
require code changes.

`frameVisuals` remains keyed by source-frame index. A source frame therefore
has consistent alignment wherever it appears. Per-occurrence timeline
transform overrides are not part of the first version.

## Timeline mutation semantics

Timeline and track positions are zero-based indices into a clip's ordered
`frames` array. `from` and `through` are both inclusive.

Spans are persisted in canonical `(from, through, hitboxId)` ascending order.
Spans for the same hitbox may not overlap or be adjacent; direct editing merges
overlapping or adjacent spans into one continuous activation before
validation. Spans for different hitboxes may overlap. Events intentionally
remain in persisted array order, and multiple events at one position dispatch
in that order. Canonical JSON preserves array order.

Frame and clip commands update tracks deterministically:

- inserting positions before a marker or span shifts the affected indices;
- inserting inside a hitbox span extends `through`, so the new position is
  active;
- removing a position deletes events at that position, shifts later events,
  and shrinks or shifts spans; a span with no remaining positions is removed;
- reordering existing frame occurrences leaves event and span positions
  unchanged because tracks describe playback time, not source-frame identity;
- duplicating a clip copies its frame sequence and all associated tracks under
  the new clip ID;
- renaming a clip moves its package-local track entry to the new key; and
- deleting a clip requires confirmation and deletes its package-local tracks.

Repeated source frames are valid and remain distinct timeline positions.

## Event contract

Events are deliberately as free-form as clip IDs. An event contains:

```json
{
  "at": 2,
  "eventId": "attack-impact",
  "payload": {
    "strength": 1
  }
}
```

`eventId` is a non-empty stable ID. `payload` is optional JSON data and the
complete serialized package remains subject to the editor request-size limit.
There is no fixed event registry in version 1. Validation checks JSON shape and
timeline bounds, not business meaning.

`payload` is the sole `additionalProperties: false` exception: it accepts any
recursive JSON value (`null`, boolean, finite number, string, array, or object
with arbitrary string keys and JSON values). It cannot contain `undefined`,
non-finite numbers, functions, binary values, or cyclic references.

At runtime the track runner emits
`{ characterId, clipId, playbackId, loopIteration, position, eventId, payload }`
through a caller-provided callback. Programmatic consumers decide what an
event means. Typed sound, effect, movement-impulse, and invulnerability tracks
remain future extensions.

## Hitbox coordinate and ownership contract

Body and hitbox values use world units. Their coordinate origin is the stable
character anchor: positive X points right and positive Y points down. A
rectangle's offset locates its center relative to that anchor.

When `mirrorX` is true, runtime facing multiplies `offsetX` by `1` or `-1`;
width and height do not change. The preview supplies facing explicitly and
draws the resolved rectangle.

`CharacterHitboxController` owns pooled Arcade overlap geometry and receives
active hitbox IDs from the track runner. Entity-specific combat code supplies
the target group and an `onHit(hitboxId, target, activationId)` callback.
The controller records targets per activation ID and reports each target at
most once during one continuous activation span. It does not calculate damage,
choose collision targets, or select animations. Existing player weapon and
enemy combat owners continue to calculate damage and knockback from their
configured properties.

### Version-1 combat coexistence

Character tracks are authored, previewed, validated, and exposed through the
opt-in runner/controller interfaces in version 1. They do not silently replace
existing combat:

- player weapon and ability sector hitboxes remain owned by their weapon or
  ability definitions and are not copied into `character.json`;
- enemy `attackWindupMs`, melee range checks, projectile timing, damage, and
  impact effects retain their current production behavior; and
- no current production controller opts into character-track hitboxes during
  this feature.

The studio still supports named character hitboxes so content can be prepared
and the generic runtime interfaces can be tested. Connecting those tracks to
player weapons, melee enemies, projectiles, parries, or damage is a separate
combat-integration design that must explicitly choose which existing owner it
replaces. This avoids duplicate damage paths and preserves current combat
behavior throughout this specification.

## Runtime interfaces

The content and runtime boundary exposes independently understandable units:

### `CharacterCatalog`

Loads, validates, and resolves saved character packages by stable ID. It
provides focused lookups for all characters, the primary player, and enemies.
It has no draft, DOM, Phaser scene, or filesystem-writing responsibilities.

### `VisualCatalog`

Discovers and validates saved visual sets. It resolves source-frame transforms
and freely named clips. It derives opaque runtime animation keys through one
shared helper.

### `VisualDefinitionResolver`

Defines the read interface needed by rendering and registration:
`getVisualSet(visualSetId)`, `getClip(visualSetId, clipId)`,
`resolveFrameVisual(visualSetId, sourceFrame)`, and
`runtimeKey(visualSetId, clipId)`. `VisualCatalogResolver` reads saved content;
`DraftVisualResolver` reads one validated editor projection. This injection
allows the preview to use runtime composition without mutating the saved
catalog. `DraftVisualResolver.runtimeKey()` delegates to
`PreviewAnimationRegistrar.previewRuntimeKey(sessionId, previewRevision,
visualSetId, clipId)`; the same registrar uses that exact helper when
registering Phaser animations. Preview playback can therefore request only
keys that the current preview revision registered.

### `AnimatedVisual`

Continues to render separately from the stable physics anchor. It gains a
clip-ID-oriented API such as `playClip(clipId)` and must not require semantic
action names. It receives a `VisualDefinitionResolver`, defaulting to the saved
catalog resolver in gameplay.

### `AnimationRegistrar`

Registers saved definitions under the shared opaque runtime key. The editor
uses a `PreviewAnimationRegistrar` with revision-scoped keys prefixed by a
studio session ID and preview revision. Before registering a new preview
revision, it stops playback and removes the previous revision's Phaser
animations. Draft edits therefore cannot collide with saved runtime
animations or retain stale frame sequences. The registrar implements
`dispose()`, which stops its active preview, removes every animation key owned
by its studio session, and detaches registration listeners.

### `CharacterAnimationTrackRunner`

Observes the current clip and timeline position, activates or disables named
hitboxes, and dispatches named events. It does not decide which animation to
play or what an event means.

Playback semantics are deterministic:

- starting or force-restarting a clip creates a new `playbackId`, sets loop
  iteration to zero, disables all prior hitboxes, enters position zero, and
  dispatches position-zero events once;
- normal advancement processes every crossed timeline position in order, even
  when a low frame rate causes multiple positions to be crossed in one update;
- entering a position first deactivates spans that are no longer active, then
  activates spans beginning at that position in canonical span order, then
  dispatches that position's events in persisted array order; event consumers
  therefore observe the final active-hitbox state for that position;
- an event dispatches once per playback ID and loop iteration when its position
  is crossed;
- a looping clip increments `loopIteration` and may dispatch the same markers
  once again in the new iteration;
- crossing a loop boundary first deactivates all hitboxes from the previous
  iteration, then enters position zero with fresh activation IDs, even when a
  span ended at the previous last position and another begins at zero;
- pause causes no transitions or dispatches; resume continues the same
  playback ID;
- replacing, stopping, completing a non-looping clip, destroying the owner, or
  cancelling an attack disables every active hitbox immediately;
- gameplay never scrubs; editor scrub and frame-step recompute visible hitbox
  state but suppress callbacks and side effects unless a future explicit event
  preview feature is added; and
- if elapsed time crosses more than four complete loops in one update, the
  runner processes hitbox end state but suppresses historical event replay and
  emits one diagnostic, preventing an unbounded catch-up burst.

An activation ID is the stable tuple
`(playbackId, loopIteration, clipId, hitboxId, spanIndex)`. Merged span order
defines `spanIndex`. This ID resets hit-once bookkeeping at every new span and
loop iteration.

### `CharacterHitboxController`

Owns active Arcade overlap geometry and hit-once-per-activation bookkeeping
according to the coordinate and ownership contract above. It depends only on
the scene physics service, anchor/facing accessors, a target group, and an
`onHit` callback.

### Player and enemy adapters

Translate validated character packages into the focused configuration consumed
by existing gameplay systems. They preserve current gameplay behavior during
the content migration.

### `CharacterClipUsageRegistry`

Code-owned runtime integrations register clip IDs they request for a character
or character kind. This registry is not persisted content, does not define
editor animation slots, and does not prevent authors from creating arbitrary
additional clips. Repository validation checks that every registered
programmatic usage resolves. Character Studio shows these known usages during
rename/delete confirmation while still warning that dynamically constructed
or otherwise unregistered string calls cannot be rewritten.

Missing programmatically requested clips fail loudly with the character ID,
visual-set ID, and clip ID.

## Character Studio workspace

Character Studio uses the existing development editor shell and has a
dedicated route such as `?studio=characters`. The map editor and Character
Studio link to each other but maintain separate document state.

```text
┌ Character Library ┬──────── Anchor-Locked Preview ────────┬ Inspector ┐
│ Player            │ zoom / onion skin / overlays / play   │ Visual    │
│ Enemies           │                                       │ Body      │
│  Worm Archer      ├────────── Spritesheet Grid ────────────┤ Hitboxes  │
│  Worm Brawler     │ selectable source frames              │ Gameplay  │
│  Worm Swordsman   │                                       │ AI/Drop   │
├───────────────────┴──────── Animation Timeline ────────────┴───────────┤
│ animations | ordered frames | hitbox spans | events | playback        │
└────────────────────────────────────────────────────────────────────────┘
```

The visual direction extends the current Field Cartographer language into an
animation workbench:

- charcoal preview canvas;
- moss work surfaces;
- parchment text;
- amber selected frames and anchor guides;
- red stable-body geometry;
- cyan attack hitboxes;
- violet event markers; and
- mint selection and playback indicators.

Its signature interaction is the anchor-locked stage. Artwork moves around a
fixed world anchor while the stable body and optional hitboxes remain visible.
Previous and next frames can appear as low-opacity onion skins.

### Character library

Lists every player package and active enemy with search and kind grouping. The
primary player carries a visible badge; non-primary player duplicates remain
editable.
Selecting another character with a dirty draft requires confirmation.
Duplicate asks for a display name and unique stable character ID.

### Spritesheet grid

Displays the manifest-defined uniform grid with source-frame numbers. It
supports click selection, range selection, and drag selection. Selected frames
can be appended to or inserted into the active clip.

### Animation library and timeline

Authors can create, rename, duplicate, and delete arbitrary clips. No action
templates or direction slots are required.

The timeline supports:

- adding selected source frames;
- selecting, reordering, duplicating, and removing occurrences;
- playback, pause, scrub, previous frame, and next frame;
- frames-per-second and looping controls;
- named hitbox activation spans; and
- generic named event markers.

### Preview stage

Uses the real visual transform composition and animation playback path. It
provides zoom, background contrast, onion skin, mirroring, and independently
toggleable overlays for:

- world anchor;
- rendered frame bounds;
- source-offset guide;
- stable body;
- named attack hitboxes; and
- current source-frame and timeline-position labels.

Mirroring is a preview/runtime behavior and does not duplicate source clips.
`CharacterPreviewScene` owns the draft resolver, preview registrar, track
preview, geometry handles, and listeners through explicit disposables. Scene
shutdown and destroy both call the idempotent disposal path, leaving no global
Phaser animation keys or callbacks owned by the closed studio.

### Inspector

The inspector is contextual rather than one unbounded form:

- **Visual:** defaults and selected source-frame origin, scale, and offset;
- **Body:** stable body dimensions and center offset;
- **Hitboxes:** named geometry and mirroring;
- **Gameplay:** player or enemy health, movement, combat, projectile, and
  effect values; and
- **AI/Drop:** existing enemy AI values and rewards.

Geometry supports numeric fields and direct move/resize handles. The interface
labels source-pixel values and world-unit values distinctly.

## Editor state and commands

`CharacterDocumentState` owns an isolated mutable draft, current selections,
undo/redo history, validation errors, dirty state, save state, revision, and
preview revision.

Each logical authoring action is one command:

- add, rename, duplicate, or remove a clip;
- add, reorder, duplicate, or remove timeline frames;
- update clip playback settings;
- edit a default or source-frame transform;
- edit body or hitbox geometry;
- edit a gameplay property;
- add, move, or remove a hitbox span; or
- add, move, edit, or remove an event.

Continuous pointer drags coalesce into one undoable command. Map-editor history
and Character Studio history are independent.

Invalid numeric drafts remain visible so the author can correct them. The
preview retains the last valid geometry when an invalid value cannot be
rendered safely.

## Preview data flow

```text
saved package
  -> CharacterCatalog and VisualCatalog
  -> CharacterDocumentState draft
  -> validated preview projection + previewRevision
  -> DraftVisualResolver
  -> PreviewAnimationRegistrar revision-scoped keys
  -> CharacterPreviewScene
  -> AnimatedVisual + geometry overlays + side-effect-free track preview
```

Drafting never mutates the saved runtime catalogs. Successful save returns a
normalized document and new revision, after which the editor refreshes the
saved baseline. Invalid drafts do not register animations; the preview keeps
the last valid projection while the inspector displays current errors.

## Development-only persistence API

Character Studio uses explicit development-only endpoints:

```text
GET  /__character-studio/package/:characterId
POST /__character-studio/package/update
POST /__character-studio/package/duplicate
```

The browser sends stable IDs and serializable document values, never
filesystem paths. Each request body is limited to 2 MiB, matching the existing
development editor's defensive payload limit.

Update request:

```json
{
  "characterId": "worm-swordsman",
  "expectedRevision": "<sha256>",
  "character": {},
  "visualSet": {}
}
```

Duplicate request:

```json
{
  "sourceCharacterId": "worm-swordsman",
  "characterId": "worm-swordsman-ice",
  "newDisplayName": "Ice Worm Swordsman",
  "character": {},
  "visualSet": {}
}
```

The `{}` values above stand for the complete draft documents described by
their schemas; partial patch payloads are not accepted.

Success responses use `{ "ok": true, "data": { ... } }`. Failures use:

```json
{
  "ok": false,
  "error": {
    "code": "validation",
    "message": "Character package is invalid",
    "issues": [
      {
        "path": "visualSet.clips.jump.frames[4]",
        "message": "Frame 92 is outside 0..47"
      }
    ]
  }
}
```

Stable error codes are `invalid-request`, `not-found`, `validation`,
`conflict`, `recovery`, and `unknown-commit`. Conflict responses include the
current revision. `unknown-commit` means the connection failed after the
directory transaction may have committed; the client reloads the package and
compares returned content before offering retry.

Loading returns both documents plus a SHA-256 revision hash calculated from
their normalized saved contents. Canonical serialization recursively sorts
object keys, preserves array order, emits UTF-8 JSON without insignificant
whitespace, and hashes a length-prefixed character-document byte sequence
followed by a length-prefixed visual-document byte sequence. All reads and
writes for one character ID run inside a development-server package mutex. The
mutex covers revision checking, validation, directory replacement, and the
final response; concurrent saves therefore cannot pass the same revision
check.

Updating:

1. resolves the server-owned package directory from the stable character ID;
2. reloads both files and compares the revision hash;
3. requires submitted `character.characterId`, `character.kind`,
   `character.visualSetId`, `character.runtimeRole`,
   `visualSet.visualSetId`, and `visualSet.assetId` to equal the saved baseline;
4. validates request shape and body-size limits;
5. validates the character and visual set together;
6. validates asset, clip, hitbox, projectile, effect, and drop
   references;
7. writes a complete normalized package into a sibling temporary directory;
8. renames the saved directory to a uniquely named backup directory;
9. renames the complete temporary directory to the package's target name;
10. restores the backup if the second rename fails;
11. removes the backup after the new target validates from disk;
12. returns the normalized package and new revision; and
13. preserves the draft and reports exact field errors on failure.

Update therefore cannot rename a package, change its kind, switch its
spritesheet, or grant/remove the primary-player role. Those identity operations
remain outside version 1.

An external-edit conflict must not overwrite disk. The UI offers reload or
duplicate-draft recovery.

At development-server startup and before each package operation, recovery
checks only transaction artifacts named
`.character-studio-<encoded-character-id>-<transaction-uuid>.tmp` or `.bak`.
A temporary directory includes a server-written `transaction.json` containing
the transaction UUID, operation kind (`update` or `duplicate`), source ID when
applicable, target ID, and pre-transaction revision when applicable. This
manifest is transaction metadata, not package content; successful commit or
recovery removes it from the target before final package validation.
A package operation examines artifacts matching its exact encoded character ID
while holding that package's mutex; it never classifies another package's
artifacts. Startup recovery parses each artifact's owner, acquires that owner's
mutex, and recovers owners independently. A valid target wins and its stale
artifacts are removed. For an update, if the target is missing and one valid
backup exists, the backup is restored. For a duplicate, if the target and
backup are both absent and one complete valid temporary package exists,
recovery finishes the duplicate by renaming that temporary directory to the
target. Multiple candidates, an invalid artifact, or a manifest mismatch stop
authoring for that package with a recovery error instead of guessing. This
makes process interruption between directory renames recoverable without
cross-package cleanup races.

Duplicating:

1. resolves the source by stable ID;
2. receives the current validated client draft, not only the saved source;
3. requires the draft's source `characterId`, `kind`, `visualSetId`, and
   `assetId` to match the saved source baseline;
4. validates `newDisplayName` and the new kebab-case character ID, then
   replaces `character.displayName` with `newDisplayName`;
5. derives the visual-set ID server-side as
   `enemy.<dot-separated-character-id>` for enemies or
   `character.<dot-separated-character-id>` for players;
6. refuses a character-directory, character-ID, or visual-set-ID collision;
7. replaces the draft's package-owned IDs and removes `runtimeRole` from a
   duplicated player;
8. preserves the spritesheet asset reference, frames, transforms, gameplay
   properties, hitboxes, and tracks;
9. validates the resulting package;
10. creates the destination through a sibling temporary directory and one final
   rename while holding source and destination package locks acquired in
   lexicographic character-ID order; and
11. returns `reloadRequired: true` and the new character ID.

Using the current draft allows duplication to preserve unsaved work and
provides the conflict-recovery path. Duplication never modifies the source and
does not require the source revision to remain current.

Top-level `displayName` describes the package in the studio. Player
`player.name` remains the gameplay-facing name and is copied unchanged; the two
fields are intentionally independent.

Newly created files require a browser page reload so Vite's eager content
discovery includes them. Character Studio reloads directly into the new
character after a successful duplicate. A development-server restart is not
required.

The endpoint does not modify map files or TypeScript source.

## Validation and errors

Repository checks, runtime loading, server persistence, and editor save
eligibility must share validation rules rather than independently approximating
the schemas.

Validation includes:

- unique character IDs and visual-set IDs;
- matching package and document ownership;
- known manifest asset IDs with supported image or spritesheet media;
- source-frame indices within the manifest frame count;
- non-empty clips;
- finite positive frames per second;
- valid boolean looping;
- finite origins, scales, and offsets;
- positive body and hitbox dimensions;
- known clip and hitbox references;
- known programmatic clip usages from `CharacterClipUsageRegistry`;
- timeline positions within the referenced clip sequence;
- valid per-kind player and enemy properties;
- known projectile, effect, and drop references; and
- exactly one primary player package.

Errors contain a stable field path and actionable message, for example:

```text
visualSet.clips.jump.frames[4]: frame 92 is outside 0..47
character.animationTracks.sword-swing.hitboxSpans[0].through:
position 8 exceeds the 6-position clip
```

The UI defines explicit loading, empty, dirty, validation-error, saving,
save-failure, and save-conflict states. Known errors disable save without
discarding the draft.

## Migration

Migration must preserve current gameplay and stable IDs:

1. Create package schemas and reusable validators.
2. Move editable player values from `content/player.ts` into the player
   package while keeping a focused runtime export.
3. Split active entries in `content/enemies/enemy-types.json` into enemy
   packages while retaining the enemy lookup API.
4. Move only the player and three enemy visual sets beside their character
   files.
5. Keep non-character sets, including `effect.enemy.worm-brawler-hit` and
   `object.tree.world`, under `content/visuals/`.
6. Discover visual sets from both
   `content/characters/**/visual-set.json` and
   `content/visuals/**/visual-set.json`; discover character definitions only
   from `content/characters/**/character.json`.
7. Treat every current unversioned visual set as legacy version 0 and migrate
   all six current sets to version 1.
8. Convert legacy clip `runtimeKey`, `frameRate`, and `repeat` fields to
   derived runtime keys, `framesPerSecond`, and `loop`. Current `repeat: -1`
   becomes `loop: true`; current `repeat: 0` becomes `loop: false`. Any other
   legacy repeat value is rejected because no current content uses it.
9. Preserve every existing visual-set ID, clip ID, source-frame transform, and
   frame sequence, including effect and object clips.
10. Update every animation caller and completion listener to use the shared
    visual resolver and freely named clip IDs without introducing
    schema-required actions.
11. Keep authored map enemy IDs unchanged.

The migration is complete only when the player and all three active worms
behave identically, the brawler impact effect still completes and cleans up,
and the animated tree still renders before Character Studio editing begins.

## Delivery slices

### Slice 1: content foundation

- package schemas and shared validators;
- automatic character and visual discovery;
- runtime adapters;
- content migration; and
- behavior-preserving checks and smoke tests.

Exit check: `characters:check`, migration fixtures, typecheck, build, and
runtime parity smoke tests pass for the player, all worms, the brawler impact
effect, and the animated tree.

### Slice 2: read-only studio

- package GET endpoint and revision hashing;
- `CharacterDocumentState` read-only draft projection;
- dedicated route and navigation;
- character library;
- spritesheet grid;
- anchor-locked preview;
- animation list and read-only timeline; and
- real arbitrary-clip playback.

Exit check: Playwright opens every package and every saved clip, while preview
resolver tests prove draft keys cannot collide with saved keys.

### Slice 3: free-form animation editing

- clip and timeline editing;
- frames-per-second and looping;
- playback, scrubbing, stepping, zoom, and onion skin;
- undo/redo and dirty-state protection; and
- package mutex, recoverable directory transaction, complete-package update,
  and draft-based duplication.

Exit check: Node transaction/command suites and Playwright edit-save-reload,
conflict, duplicate-draft, interrupted-update recovery, interrupted-duplicate
recovery, virtual-module invalidation, and page-reload cases pass against
fixture roots.

### Slice 4: visual alignment

- default and source-frame transform editing;
- direct offset manipulation and numeric controls;
- frame bounds and offset guides;
- multi-frame copy/reset operations; and
- transform persistence.

Exit check: transform unit tests and browser drag/numeric/save/reload cases
prove visual changes never alter the stable body.

This is the first usable checkpoint: existing characters can be opened,
duplicated, animated with arbitrary clip names, aligned, previewed, validated,
and saved.

### Slice 5: body, hitboxes, and tracks

- stable body editing;
- named rectangular hitboxes;
- hitbox activation spans;
- generic event markers; and
- side-effect-free preview execution plus opt-in runtime track and hitbox
  primitives; existing combat remains unchanged.

Exit check: timeline mutation, loop/event ordering, activation-ID, hit-once,
cleanup, mirroring, and preview-side-effect tests pass; current combat smoke
tests remain unchanged.

### Slice 6: gameplay properties

- schema-backed player fields;
- schema-backed enemy movement, combat, AI, projectile, effect, and drop
  fields; and
- units, ranges, descriptions, and reset controls.

Exit check: every schema field round-trips through the inspector, cross-field
errors render at exact paths, and player/enemy runtime adapter parity tests
pass.

### Slice 7: integration and verification

- conflict, recovery, and unknown-commit UI polish;
- map-editor links;
- documentation; and
- end-to-end browser and runtime smoke tests.

Exit check: `pnpm check`, `pnpm test:character-studio`, map-editor navigation,
and final gameplay smoke tests pass with no production fixture writes.

## Verification

The implementation adds:

- `scripts/check-characters.mjs` and a `characters:check` package command for
  package/schema/catalog/programmatic-clip-reference validation;
- Node built-in `node:test` suites under `scripts/tests/character-studio/` and
  a `test:characters` package command for validators, editor commands, track
  playback, transaction recovery, and migration fixtures;
- `@playwright/test`, `tests/character-studio.spec.ts`, and a
  `test:character-studio` command for browser behavior against a test-only
  character-content root; and
- `characters:check` and `test:characters` in `pnpm check`.

The Playwright suite copies package fixtures into a temporary writable
directory and launches Vite with test roots passed to
`characterContentModulesPlugin`. The virtual client catalog and server
endpoints therefore share the fixture roots through initial load, duplication,
module invalidation, and full reload. Tests never write production character
content. Browser tests remain an explicit command rather than part of every
production build.

Automated verification covers:

- character and visual schema validation;
- catalog discovery and duplicate-ID rejection;
- unversioned legacy visual-set migration to version 1;
- generated runtime-key uniqueness;
- registered programmatic clip usages and rename/delete warnings;
- JSON load/edit/save/reload round trips;
- package duplication with independent IDs and files;
- duplicate-draft conflict recovery and required page reload;
- external-revision conflicts;
- concurrent update serialization and interrupted directory-swap recovery;
- frame-range and frames-per-second validation;
- arbitrary clip IDs, including `jump`;
- repeated source frames plus insert/remove/reorder/rename/delete track
  semantics;
- loop, pause/resume, skipped-position, completion, cancellation, and destroy
  behavior in the track runner;
- stable-body invariants under frame offset, scale, origin, and mirroring;
- hitbox mirroring, hit-once activation, cancellation, and cleanup;
- undo/redo command coalescing;
- failed-save draft preservation;
- runtime adapter parity with current player and enemy values;
- map references to migrated enemy IDs;
- brawler impact-effect and animated-tree parity after visual discovery
  migration;
- editor loading, empty, dirty, invalid, conflict, and save states;
- asset, visual, character/enemy, object, and map repository checks;
- strict TypeScript checks and production build; and
- browser smoke tests for the studio plus gameplay smoke tests for the player
  and every active enemy.

## Acceptance criteria

- Character Studio opens as a dedicated development workspace.
- Existing player and enemy packages load without behavior regressions.
- Authors can create any clip ID without selecting an action or direction
  schema.
- Authors can choose and order source frames and set frames per second and
  looping.
- The preview uses the actual runtime visual-transform and animation path.
- Source-frame visual edits never move or resize the stable body.
- Authors can edit the stable body, named hitboxes, and arbitrary clip tracks.
- Authors can edit the current player and enemy gameplay properties within
  validated constraints.
- Save writes a complete validated package without accepting client paths.
- Conflicts and validation failures preserve the draft.
- Duplicate creates an independent package and never changes the original.
- Character Studio never writes map files or TypeScript import tables.
- All repository checks, type checks, builds, and required smoke tests pass.
