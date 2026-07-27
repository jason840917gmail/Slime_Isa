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
- enemy spawn-area authoring; and
- changing map files from Character Studio.

## Content organization

Editable character content moves into self-contained packages:

```text
src/game/content/characters/
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

The visual catalog must discover validated `visual-set.json` files instead of
maintaining a hand-written TypeScript import list. The character catalog must
similarly discover validated `character.json` files. Character Studio must
never rewrite TypeScript imports to register duplicated content.

The runtime may expose typed player and enemy adapters over the package catalog
so existing controllers retain focused interfaces. Gameplay systems must not
depend on editor document types.

## Character schema

Character definitions use a discriminated `kind` field. Shared fields are
validated identically, while player and enemy properties retain distinct
owners and constraints.

Illustrative shape:

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
          "event": "play-sound",
          "value": "sword-whoosh"
        }
      ]
    }
  },
  "enemy": {
    "maxHp": 90,
    "movement": {
      "wanderSpeed": 28,
      "chaseSpeed": 75
    },
    "combat": {
      "aggroRange": 220,
      "attackRange": 38,
      "attackCooldownMs": 1500,
      "attackWindupMs": 400,
      "attackRecoveryMs": 400,
      "contactDamage": 37,
      "knockbackStrength": 260,
      "knockbackResist": 0.45
    },
    "drop": {
      "xp": 50,
      "coins": 10
    }
  }
}
```

The final schema should preserve the existing runtime concepts instead of
inventing a generic property bag. The property inspector is schema-backed and
uses explicit labels, descriptions, units, ranges, and validation. Complex AI
graphs are not inferred from the current numeric AI configuration.

Player duplication does not replace the active primary player. A duplicated
player package is independently addressable content but has no primary runtime
role until programmatic configuration selects it. Duplicated enemies become
complete catalog entries and therefore become available to map spawn rules.

## Visual-set schema version 2

The authored clip format removes persisted Phaser runtime keys and exposes the
authoring concepts directly:

```json
{
  "$schema": "../visual-set.schema.json",
  "version": 2,
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
    }
  }
}
```

Clip IDs are stable programmatic references. Renaming a clip updates
package-local animation-track references but cannot rewrite arbitrary
TypeScript callers. The editor must warn that a rename may require code
changes.

`frameVisuals` remains keyed by source-frame index. A source frame therefore
has consistent alignment wherever it appears. Per-occurrence timeline
transform overrides are not part of the first version.

Timeline positions in `animationTracks` refer to positions in a clip's ordered
frame sequence, not source-frame indices. This distinction supports repeated
source frames.

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

### `AnimatedVisual`

Continues to render separately from the stable physics anchor. It gains a
clip-ID-oriented API such as `playClip(clipId)` and must not require semantic
action names.

### `CharacterAnimationTrackRunner`

Observes the current clip and timeline position, activates or disables named
hitboxes, and dispatches named events. It does not decide which animation to
play or what an event means.

### Player and enemy adapters

Translate validated character packages into the focused configuration consumed
by existing gameplay systems. They preserve current gameplay behavior during
the content migration.

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

Lists the primary player and active enemies with search and kind grouping.
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
  -> validated preview projection
  -> CharacterPreviewScene
  -> AnimatedVisual + geometry overlays + track preview
```

Drafting never mutates the saved runtime catalogs. Successful save returns a
normalized document and new revision, after which the editor refreshes the
saved baseline.

## Development-only persistence API

Character Studio uses explicit development-only endpoints:

```text
GET  /__character-studio/package/:characterId
POST /__character-studio/package/update
POST /__character-studio/package/duplicate
```

The browser sends stable IDs and serializable document values, never
filesystem paths.

Loading returns both documents plus a revision hash calculated from their
saved contents.

Updating:

1. resolves the server-owned package directory from the stable character ID;
2. reloads both files and compares the revision hash;
3. validates request shape and body-size limits;
4. validates the character and visual set together;
5. validates asset, clip, hitbox, event, projectile, effect, and drop
   references;
6. writes both normalized documents to temporary files;
7. replaces both files with rollback protection if either replacement fails;
8. returns the normalized package and new revision; and
9. preserves the draft and reports exact field errors on failure.

An external-edit conflict must not overwrite disk. The UI offers reload or
duplicate-draft recovery.

Duplicating:

1. resolves the source by stable ID;
2. validates the new stable character and visual-set IDs;
3. refuses existing destinations;
4. copies both documents while regenerating package-owned IDs;
5. preserves the spritesheet asset reference, frames, transforms, gameplay
   properties, hitboxes, and tracks;
6. creates the new directory through temporary output and a final rename; and
7. opens the duplicate only after successful creation.

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
4. Move the player and three enemy visual sets beside their character files.
5. Discover visual sets and character definitions automatically.
6. Convert existing clip `runtimeKey`, `frameRate`, and `repeat` fields to
   derived runtime keys, `framesPerSecond`, and `loop`.
7. Preserve every existing clip ID and frame sequence.
8. Update player and enemy animation callers to request freely named clip IDs
   without introducing schema-required actions.
9. Keep authored map enemy IDs unchanged.

The migration is complete only when the player and all three active worms
behave identically before Character Studio editing begins.

## Delivery slices

### Slice 1: content foundation

- package schemas and shared validators;
- automatic character and visual discovery;
- runtime adapters;
- content migration; and
- behavior-preserving checks and smoke tests.

### Slice 2: read-only studio

- dedicated route and navigation;
- character library;
- spritesheet grid;
- anchor-locked preview;
- animation list and read-only timeline; and
- real arbitrary-clip playback.

### Slice 3: free-form animation editing

- clip and timeline editing;
- frames-per-second and looping;
- playback, scrubbing, stepping, zoom, and onion skin;
- undo/redo and dirty-state protection; and
- visual-set save support.

### Slice 4: visual alignment

- default and source-frame transform editing;
- direct offset manipulation and numeric controls;
- frame bounds and offset guides;
- multi-frame copy/reset operations; and
- transform persistence.

This is the first usable checkpoint: existing characters can be opened,
duplicated, animated with arbitrary clip names, aligned, previewed, validated,
and saved.

### Slice 5: body, hitboxes, and tracks

- stable body editing;
- named rectangular hitboxes;
- hitbox activation spans;
- generic event markers; and
- runtime track execution.

### Slice 6: gameplay properties

- schema-backed player fields;
- schema-backed enemy movement, combat, AI, projectile, effect, and drop
  fields; and
- units, ranges, descriptions, and reset controls.

### Slice 7: persistence completion and integration

- revision-aware package updates;
- complete package duplication;
- conflict recovery;
- map-editor links;
- documentation; and
- end-to-end browser and runtime smoke tests.

## Verification

Automated verification covers:

- character and visual schema validation;
- catalog discovery and duplicate-ID rejection;
- version-1 visual-set migration;
- generated runtime-key uniqueness;
- JSON load/edit/save/reload round trips;
- package duplication with independent IDs and files;
- external-revision conflicts;
- frame-range and frames-per-second validation;
- arbitrary clip IDs, including `jump`;
- repeated source frames and timeline-position semantics;
- stable-body invariants under frame offset, scale, origin, and mirroring;
- hitbox-span activation and cleanup;
- undo/redo command coalescing;
- failed-save draft preservation;
- runtime adapter parity with current player and enemy values;
- map references to migrated enemy IDs;
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
