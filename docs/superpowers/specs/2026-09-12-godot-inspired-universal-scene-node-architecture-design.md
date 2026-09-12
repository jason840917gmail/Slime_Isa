# Godot-Inspired Universal Scene and Node Architecture Design

## Status

Approved design for replacing Slime Isa's separate map, character, animation,
weapon, projectile, and effect authoring models with one Godot-inspired scene
tree, one runtime node model, and one Scene Studio.

This document defines the destination architecture and the staged migration
boundary. It does not authorize a flag-day rewrite or removal of an existing
runtime path before its replacement has passed automated checks and user-run
gameplay acceptance.

## Problem

The project currently represents similar runtime entities through different
data shapes, editors, factories, and controllers. Character Studio exposes a
full gameplay inspector for ordinary enemies, but Fatty One Eye is represented
as a separate `boss` character kind whose combat properties live in a second
boss-definition file. Fatty therefore receives a reduced Character Studio
interface even though gameplay already treats it as a hostile enemy target.

The same fragmentation appears more broadly:

- players, NPCs, ordinary enemies, and bosses construct visuals, animation,
  physics, and cleanup differently;
- weapons, projectiles, effects, map objects, maps, and UI use separate
  authoring surfaces despite sharing transforms, assets, timelines, shapes,
  events, and persistence concepts;
- gameplay meaning is sometimes embedded in geometry-specific types instead
  of being decided by programmatic behavior;
- ownership is duplicated across character packages, boss definitions, visual
  sets, maps, and runtime controllers; and
- adding a new entity category tends to require a new editor branch rather
  than composing existing capabilities.

The result is difficult to author, inconsistent to validate, and increasingly
expensive to extend.

## Goals

1. Introduce a focused Godot-inspired `Node` and `SceneTree` layer over Phaser.
2. Represent every live game entity and UI composition as a saved or runtime
   scene made from reusable nodes.
3. Replace separate content editors with one universal Scene Studio whose
   interface responds to selected node types rather than entity categories.
4. Keep visuals, animation, physics, collision detection, audio, and behavior
   as distinct reusable concerns.
5. Put entity-specific gameplay code in registered TypeScript `ScriptNode`
   implementations without embedding a code editor in Scene Studio.
6. Treat Fatty One Eye as an enemy whose rank is `boss`, with `FattyScript`
   extending shared enemy behavior while retaining its custom mechanics.
7. Generalize damage areas, weapon vulnerabilities, immunities, and modifiers
   so ordinary enemies may use the same capabilities as bosses.
8. Support reusable scene instances and per-instance property overrides.
9. Migrate incrementally through compatibility adapters so the game remains
   buildable and playable throughout the program.
10. Reserve gameplay acceptance for the user. Automated checks may verify
    deterministic contracts and simulations but must never claim that gameplay
    was tested or approved.

## Non-goals

- Do not replace Phaser's renderer, Arcade Physics, audio, cameras, or input
  backends.
- Do not reproduce every Godot engine feature or API.
- Do not add an integrated TypeScript or JavaScript code editor.
- Do not permit executable code in scene JSON.
- Do not implement inherited scenes in the first version. Reusable scene
  instances and local property overrides are in scope; derived scenes such as
  `Elite Worm extends Worm` are deferred until a concrete use case justifies
  their merge semantics.
- Do not force static definitions such as recipes, quests, and item catalogs
  into live nodes when a resource or project-data record is the correct model.
- Do not remove an existing authoring or runtime path until its replacement is
  proven and the user approves the corresponding manual gameplay checklist.
- Do not use the migration as permission for unrelated gameplay redesigns.

## Core Concepts

### Node

`Node` is the base runtime unit. Every node has:

- a serialization-stable ID used by references and property overrides;
- a human-readable name used in the Scene Studio tree and node paths;
- one optional parent and an ordered collection of children;
- a reference to its owning `SceneTree` while it is inside the tree;
- process and physics-process enablement;
- signal connection ownership;
- deterministic cleanup ownership for timers, listeners, Phaser resources,
  and other disposables; and
- metadata supplied by its registered node type.

The base API follows the Godot mental model:

```ts
add_child(node: Node): void
remove_child(node: Node): void
get_node(path: NodePath): Node
get_parent(): Node | undefined
get_children(): readonly Node[]
get_child(index: number): Node | undefined
get_child_count(): number
has_node(path: NodePath): boolean
queue_free(): void
duplicate(): Node
reparent(parent: Node): void
is_inside_tree(): boolean
get_tree(): SceneTree | undefined
set_process(enabled: boolean): void
set_physics_process(enabled: boolean): void
```

Public naming may retain Godot's underscore-style lifecycle callbacks even
though the implementation is TypeScript:

```ts
_enter_tree(): void
_ready(): void
_process(deltaSeconds: number): void
_physics_process(deltaSeconds: number): void
_input(event: InputEvent): void
_unhandled_input(event: InputEvent): void
_exit_tree(): void
```

Node instances move through these states:

```text
detached -> entering -> inside/not-ready -> ready -> exiting -> detached
                                                   `-> queued-for-free -> freed
```

`freed` is terminal. `remove_child()` detaches a subtree without destroying it;
detached nodes retain their serializable state and may be added again. Runtime
backend objects and tree-owned connections are released on exit and recreated
on a later entry. `queue_free()` schedules terminal destruction of the complete
subtree. A freed node may never be re-added.

Tree mutations requested during lifecycle callbacks, processing, input, physics,
or signal delivery are queued. The tree flushes mutations after each input
event, after every fixed physics step and its contact signals, after the
render-frame process pass, and during shutdown. One flush processes removals
and frees before additions and reparents. Mutations requested by a mutation
callback wait for the next flush, preventing recursive structural edits.

Every queued mutation retains the owning tree that accepted it. Mutation
requests affecting the same node coalesce with this precedence:
`free > remove > reparent > add`. `queue_free()` on a pending addition cancels
the addition and frees the detached subtree at the accepting tree's next flush;
on a pending removal or reparent it upgrades that operation to free. Repeated
free requests are no-ops. A detached node with no accepting tree is freed
immediately, without entry/exit callbacks; descendants and detached-owned
disposables are still exhausted. Adding, removing, or reparenting a node already
queued for free is rejected with a development diagnostic.

Insertion into an active tree calls `_enter_tree()` parent-first and then calls
`_ready()` child-first after the full inserted subtree is indexed. `_ready()`
runs once per node lifetime; detaching and re-adding the same node does not run
it again. Removal calls `_exit_tree()` child-first. Reparenting within one tree
is atomic, emits no exit or entry lifecycle callbacks, and preserves the global
transform of `Node2D` nodes. Reparenting across trees is rejected; callers must
detach and then add the subtree explicitly.

`duplicate()` returns a detached deep copy of the complete subtree. It assigns
new stable node IDs, resets runtime and lifecycle state, copies exported
properties, shares immutable external resources, deep-copies inline
subresources, remaps signal connections whose endpoints are both inside the
copied subtree, and omits connections to outside nodes. Duplicating a resolved
scene-instance root produces another instance of the same source scene with the
same overrides and a new instance ID. Scene Studio uses the same rules for its
document-level duplicate operation.

### SceneTree

`SceneTree` owns one active root and coordinates:

- lifecycle entry, readiness, processing, and exit;
- indexed lookup by stable node ID and resolved node path;
- process and physics-process lists containing only enabled nodes;
- ordered input and unhandled-input propagation;
- synchronous signals;
- queued deletion after the current processing step;
- safe subtree insertion, removal, duplication, and reparenting; and
- development diagnostics with complete scene and node paths.

A Phaser scene hosts a `SceneTree` and forwards update, physics, input, and
shutdown boundaries. Phaser remains an implementation dependency of
specialized runtime nodes, not a dependency of gameplay scripts.

Node names must be non-empty, may not contain `/`, and must be unique among
siblings. Human-readable runtime paths use `/Root/Child`, `Child/Grandchild`,
`.` and `..`. Renaming changes the human path but never changes the stable node
ID.

Serialized node references do not store fragile name paths. They use:

```ts
interface NodeReferenceDocument {
  readonly instancePath?: readonly string[];
  readonly nodeId: string;
}
```

The editor may display the current human path beside the reference. Signals,
animation targets, script exports, and overrides serialize stable node IDs plus
property names. `get_node(path)` remains available to scripts for Godot-like
runtime navigation, but exported dependencies should use stable node references
so renaming does not break authored content.

### Scene

A scene is a versioned, saved node tree. Once saved, it becomes a reusable
blueprint that may be instantiated as a node inside another scene. Maps,
characters, weapons, projectiles, effects, props, chests, encounter assemblies,
and UI layouts may all be scenes.

A serialized scene reference is distinct from a resource reference:

```ts
interface SceneReferenceDocument {
  readonly sceneId: SceneId;
}
```

Validation resolves it through the scene catalog, checks load permissions and
instance-cycle constraints in the owning document, and provides a packed scene
blueprint to `SceneTree.instantiate_scene()`. It never passes through the media
resource registry.

### Resource

A resource is reusable data consumed by nodes but does not independently exist
in the live scene tree. Examples include textures, sprite sheets, animation
libraries, audio streams, collision shapes, fonts, and themes. Resources may be
external shared records or inline subresources when sharing is unnecessary.

The existing asset manifest remains the source of truth for raw media. It is
adapted into the resource selection system instead of being converted into
nodes.

### Project data

Definitions that do not represent live objects remain project data or typed
resources. Item definitions, recipes, quests, localization, and global balance
tables should not become nodes merely to make all JSON look alike.

### Identifier vocabulary

The implementation uses distinct branded string types and never passes them
interchangeably:

| Identifier | Scope and purpose |
| --- | --- |
| `SceneId` | Project-wide ID of a saved scene blueprint |
| `ResourceId` | Project-wide ID of a non-node resource |
| `AuthoredNodeId` | Immutable node ID unique within one source scene |
| `InstanceId` | Immutable nested-scene placement ID unique within its containing scene |
| `RuntimeNodeId` | Canonical tree-wide ID produced from runtime namespace, instance path, and authored node ID |
| `PersistenceKey` | Stable save identity explicitly derived from authored instance IDs or supplied by an owning script |

Display names and human-readable node paths are not identifiers and never own
persistence or serialized cross-node references.

## Node Type Model

The first implementation supports the node families required by the current
game. Names intentionally follow Godot where the concepts align:

```text
Node
|- Node2D
|  |- Sprite2D
|  |- PhysicsBody2D
|  |  |- CharacterBody2D
|  |  `- StaticBody2D
|  |- Area2D
|  |- CollisionShape2D
|  |- TileMapLayer2D
|  |- AudioStreamPlayer2D
|  `- Camera2D
|- AnimationPlayer
|- ScriptNode
`- Control
   `- project-specific reusable UI control nodes
```

This list may grow through the node registry, but a new node type is justified
only when it owns genuinely different engine behavior. Gameplay labels such as
`WeakPoint`, `EnemyAttack`, or `BossCollider` do not justify new engine node
types.

### Node2D

`Node2D` adds local position, rotation, scale, visibility, and derived world
transform. Child transforms resolve relative to their parent. The runtime
maintains these transforms independently of any specific Phaser object.

### Sprite2D

`Sprite2D` owns visual presentation:

- texture or sprite-sheet resource reference;
- frame;
- origin and visual offset transform;
- visibility, alpha, tint, flip, and render depth; and
- creation and cleanup of its Phaser sprite.

It contains no AI, damage, movement, or interaction rules.

### PhysicsBody2D, CharacterBody2D, and StaticBody2D

`PhysicsBody2D` is the abstract owner of a blocking Phaser physics body,
collision layers, collision masks, and child collision shapes. It is registered
for validation and shared inspection but cannot be instantiated directly.

`CharacterBody2D` owns velocity, controlled movement, blocking collision, and a
Phaser Arcade dynamic body. It provides focused movement and collision methods
that fit the existing top-down game instead of pretending Arcade Physics
supports every Godot `CharacterBody2D` feature.

`StaticBody2D` owns immovable world collision for terrain, walls, buildings,
and solid props.

Both use collision layers and masks and receive geometry from child
`CollisionShape2D` nodes.

### Area2D and CollisionShape2D

`Area2D` detects overlaps without blocking movement. It exposes collision
layers, collision masks, monitoring enablement, and signals equivalent to:

- `body_entered`;
- `body_exited`;
- `area_entered`; and
- `area_exited`.

`CollisionShape2D` only describes geometry and enablement. Initial supported
shapes are rectangle, circle, and ellipse. It must be a child of a compatible
physics body or area.

Geometry reports where contact happened. Script code decides what the contact
means. The collision system does not encode concepts such as damage, weakness,
loot, dialogue, or boss rank.

### TileMapLayer2D

`TileMapLayer2D` owns one ordered tile layer and references a `TileSetResource`.
Its cell data is an external `TileMapDataResource` so large maps do not turn
scene-node properties into unwieldy arrays. The node exposes layer transform,
visibility, render depth, collision participation, and editor-lock state.

A world scene contains one node per authored terrain or decoration layer plus
nested scene instances for objects and actors. `TileSetResource` maps stable
terrain tile IDs to asset frames, collision, and editor metadata;
`TileMapDataResource` stores coordinates and stable tile IDs. Production
gameplay loads only authored tile resources and never invokes procedural map
generation.

### AnimationPlayer

`AnimationPlayer` targets exposed properties through serialized stable node
references plus property names. A single
timeline may:

- change sprite frames or transforms;
- enable and disable an `Area2D` or `CollisionShape2D`;
- change visual presentation properties;
- trigger audio playback;
- emit named events or signals; and
- notify script behavior when an animation completes.

This replaces separate character, weapon, projectile, and effect timeline
implementations. Existing animation resources are migrated without discarding
their authored timing.

### AudioStreamPlayer2D

`AudioStreamPlayer2D` owns an audio resource, volume, pitch, looping, positional
settings supported by the game, playback state, and cleanup. It does not decide
when a sound represents an attack, death, interaction, or UI response.

### Control

`Control` is the root of reusable UI composition. It provides anchors, offsets,
layout, focus, visibility, input consumption, and theme/resource references.
Concrete controls may wrap Phaser UI objects or DOM presentation where the
current application requires it, but they participate in the same scene,
serialization, lifecycle, and inspection model.

### ScriptNode

`ScriptNode` owns entity-specific programmatic behavior. It references a
registered TypeScript implementation by stable script ID. Scene Studio does not
edit source code.

Every serialized script node uses `type: "ScriptNode"` and a required top-level
`scriptId`; `scriptId` is not duplicated inside the generic property bag:

```json
{
  "id": "script",
  "name": "Script",
  "type": "ScriptNode",
  "scriptId": "enemy.fatty-one-eye",
  "parentId": "fatty",
  "properties": {
    "rank": "boss",
    "maxHp": 140
  }
}
```

`ScriptNode` construction first resolves the generic node type and then resolves
`scriptId` through a separate script registry. The script ID is immutable for
the node's lifetime. Replacing a script in Scene Studio creates a replacement
ScriptNode through a validated property-migration preview; it never mutates the
implementation behind a live node.

A registered script supplies:

- stable ID, display name, description, and TypeScript source path;
- constructor/factory;
- exported property schema, defaults, labels, help, and constraints;
- required or expected stable node references;
- configuration warnings;
- signals it emits or commonly consumes; and
- optional inheritance from another registered script implementation.

Script metadata inheritance merges base definitions before child definitions.
Child scripts may add properties or override labels, help, defaults, and
narrower validation constraints, but may not change an inherited property's
serialized type. Duplicate signal names or incompatible property overrides fail
registry startup. Renamed script IDs and exported properties require explicit
versioned migrations; unknown IDs are validation errors.

The inspector shows the script ID and source location, exported
properties, expected node references, connected signals, and warnings. Selecting a
different script is not an arbitrary runtime attachment operation. Authors
create a concrete `ScriptNode` of a registered type in the scene tree; its
implementation identity is stable after creation unless the node is explicitly
replaced.

Generic node implementations contain reusable engine mechanics. Gameplay
meaning belongs in ScriptNode implementations.

## Script Inheritance and Character Roles

Shared behavior uses TypeScript inheritance where it produces a clear contract:

```text
ScriptNode
`- CharacterScript
   |- PlayerScript
   |- NpcScript
   `- EnemyScript
      `- FattyScript
```

`CharacterScript` supplies common character state and helpers without owning
player, NPC, or hostile policy. `EnemyScript` owns shared hostile behavior and
exports common configurable properties such as:

- faction and rank;
- maximum health and attributes;
- movement and targeting settings;
- damage reception and effect responses;
- rewards and death signals; and
- references to the nodes used for presentation, body, animation, and damage
  areas.

Fatty is an enemy with `rank: "boss"`. `FattyScript` extends `EnemyScript` and
adds only Fatty-specific state and transitions: contact hop, small-hop
telegraph, large leap, airborne state, landing, recovery, and its special
damage rules. Boss rank may affect UI, encounter signals, reward presentation,
or targeting, but it does not move Fatty into an unrelated character category.

Other ordinary or elite enemies may use any shared enemy capability. A weak
point, weapon restriction, resistance, or immunity is not intrinsically a boss
feature.

## General Damage and Vulnerability Model

Damage reception is driven by ordinary `Area2D` nodes referenced by
`EnemyScript` exports. A damage-area rule identifies a stable node reference and describes
the accepted attack characteristics and response:

```ts
interface AttackSourceMatcherDocument {
  readonly weaponIds?: readonly string[];
  readonly allWeaponTags?: readonly string[];
  readonly anyDamageTypes?: readonly string[];
}

interface DamageAreaRuleDocument {
  readonly area: NodeReferenceDocument;
  readonly priority: number;
  readonly damageMultiplier: number;
  readonly acceptedSources?: readonly AttackSourceMatcherDocument[];
  readonly blockedWeaponTags?: readonly string[];
  readonly damageTypeMultipliers?: Readonly<Record<string, number>>;
  readonly effectResponses?: Readonly<Record<string,
    | { readonly mode: 'immune' }
    | { readonly mode: 'multiplier'; readonly multiplier: number }
  >>;
}
```

`damageMultiplier` and every configured multiplier must be finite and
non-negative, and `priority` must be a safe integer. `blockedWeaponTags` reject
before acceptance matching. An absent `acceptedSources` accepts every source.
When present, it must be non-empty and at least one matcher must pass. Matchers
are OR alternatives; fields inside one matcher are AND requirements. A
`weaponIds` field requires a present matching weapon ID, `allWeaponTags`
requires every listed tag, and `anyDamageTypes` requires at least one listed
type. This expresses "an explicitly allowed weapon OR any spear-tagged weapon"
without ambiguous AND semantics.

Unknown weapon IDs, tags, damage types, effects, node references, empty matcher
clauses, and duplicate list entries fail content validation. State-dependent
rules such as Fatty's airborne protection remain programmatic decisions in its
script rather than serialized expressions.

Damage routing uses one normalized immutable request and response contract:

```ts
interface DamageRequest {
  readonly activationId: string;
  readonly sourceNodeId: string;
  readonly attackAreaNodeId: string;
  readonly targetAreaNodeId: string;
  readonly weaponId?: string;
  readonly weaponTags: readonly string[];
  readonly damageTypes: readonly string[];
  readonly baseDamage: number;
  readonly effects: readonly { readonly effectId: string; readonly potency: number }[];
  readonly impact: Readonly<{ x: number; y: number; knockX: number; knockY: number }>;
}

type DamageResult =
  | {
      readonly status: 'accepted';
      readonly actualDamage: number;
      readonly defeated: boolean;
      readonly appliedEffects: readonly { readonly effectId: string; readonly potency: number }[];
      readonly rejectedEffects: readonly { readonly effectId: string; readonly reason: 'immune' | 'zero-potency' }[];
    }
  | {
      readonly status: 'rejected';
      readonly actualDamage: 0;
      readonly reason: 'invalid' | 'inactive-attack' | 'duplicate' | 'source-blocked' | 'state-blocked' | 'immune' | 'dead';
      readonly retryable: boolean;
    };
```

Requests with non-finite or negative damage or potency, duplicate tags/types/
effects, unknown runtime nodes, inactive attack areas, or a mismatched
activation ID are rejected as invalid. For an accepted source, final damage is
`Math.round(baseDamage * damageMultiplier * matchingTypeMultipliers)`, clamped
to zero and the target's remaining health. Each unique requested damage type
contributes its configured multiplier, or `1` when absent; identifiers are
canonicalized into stable sorted order before calculation. Effect responses
independently accept, reject, or scale each requested effect, and the result
reports final scaled potency. Zero computed damage does not reject effects. If
at least one effect remains applicable, the request is accepted with
`actualDamage: 0`; when neither damage nor any effect can apply, it is rejected
as `immune`.

Only `state-blocked` is retryable within the same activation. It represents a
temporary script state such as an airborne target. `invalid`, `inactive-attack`,
`duplicate`, `source-blocked`, `immune`, and `dead` are terminal. The shared
damage resolver constructs the reason and `retryable` value; individual scripts
cannot invent new strings or disagree about classification.

For example, an ordinary enemy may expose one body area accepting all weapon
attacks. A future armored enemy may reject slashing attacks on its body but
accept blunt attacks. Fatty may expose only the eye as a damage area and require
a spear-tagged or explicitly allowed weapon while grounded.

The shape itself remains gameplay-neutral:

```text
Fatty: CharacterBody2D
|- BodyShape: CollisionShape2D
|- Visual: Sprite2D
|- Eye: Area2D
|  `- EyeShape: CollisionShape2D
|- ContactAttack: Area2D
|  `- ContactShape: CollisionShape2D
|- Animation: AnimationPlayer
|- Audio: AudioStreamPlayer2D
`- Script: FattyScript
```

Fatty does not require two blocking Phaser colliders. `BodyShape` supplies
solid movement geometry. `Eye` is a non-blocking overlap area. `FattyScript`
interprets the named area's signal and the incoming attack data.

Weapons use the same model. A weapon attack is an area enabled by an animation
track. When an attack area overlaps a target damage area, the scripts exchange
a normalized immutable damage request and result. Shared combat services may
perform pure calculations, but routing does not depend on `instanceof Enemy`
or a hard-coded boss branch.

The attacking script owns attack lifetime. Starting an attack creates an
activation ID unique within the attacking scene instance; ending or cancelling
the attack invalidates it. Contacts gathered during one physics step are grouped
by target damage-receiver ScriptNode. The receiver chooses exactly one matching
damage-area rule: highest `priority`, then lowest stable node ID as a tie-break.
The attacking script records one accepted or non-retryable rejected attempt per
`(activationId, targetReceiverRuntimeId)`, so persistent overlap callbacks
cannot apply repeated frame damage or double-hit through overlapping body and
weak-point areas. A retryable `state-blocked` result may be evaluated again on a
later fixed step while the same active area still overlaps. A deliberately
multi-hit attack starts a new activation for
each authored pulse. Attack cancellation, scene removal, and node disablement
clear pending contacts before they can resolve.

## Encounter Composition

An enemy's combat behavior and an encounter's lifecycle are separate scenes and
scripts. Fatty handles its own combat; the boss camp handles when Fatty exists.

```text
FattyCamp: Node2D
|- ActivationArea: Area2D
|  `- ActivationShape: CollisionShape2D
|- ArenaArea: Area2D
|  `- ArenaShape: CollisionShape2D
|- BossSpawn: Node2D
|- ActiveBosses: Node
|- GuardedChest: [instance of object.chest]
`- Script: BossCampScript
```

`BossCampScript` owns activation, spawning, arena exit/reset, respawn timing,
boss-health presentation, and chest locking. `FattyScript` owns only Fatty's
combat state. The two communicate through stable node references and signals such as
`defeated` and `spawned`.

The authored camp does not contain an eagerly created Fatty instance.
`BossCampScript` exports a `bossScene: SceneReferenceDocument`, a stable reference to
`BossSpawn`, and a stable reference to `ActiveBosses`. When activation rules
permit spawning, it asks `SceneTree` to instantiate `bossScene`, adds the
detached root beneath `ActiveBosses`, and applies the spawn node's world
transform before insertion. Only one active child may carry the camp's boss
runtime role. Despawn or reset queues that child for deletion; respawn creates a
fresh instance from the same packed scene. The guarded chest is an eager nested
scene instance because it exists independently of the boss's live state.

The same approach supports enemy camps, quest encounters, dungeon rooms, and
scripted sequences without adding those policies to the enemy entity itself.

## Scene Documents

Scene documents use a versioned JSON format. Locally owned nodes are serialized
as a flat ordered list with parent IDs, and nested scene instances are stored in
a separate instance list. Scene Studio displays both as one hierarchy. Stable
IDs make references, overrides, diffs, migrations, and validation more reliable
than array-index or display-name ownership.

Illustrative shape:

```json
{
  "version": 1,
  "sceneId": "character.fatty-one-eye",
  "rootNodeId": "fatty",
  "nodes": [
    {
      "id": "fatty",
      "name": "Fatty One Eye",
      "type": "CharacterBody2D",
      "parentId": null,
      "order": 0,
      "properties": {
        "position": [0, 0],
        "collisionLayer": ["characters"]
      }
    },
    {
      "id": "visual",
      "name": "Visual",
      "type": "Sprite2D",
      "parentId": "fatty",
      "order": 0,
      "properties": {
        "texture": "character.boss.fatty-one-eye",
        "scale": [1.5, 1.5]
      }
    }
  ],
  "instances": []
}
```

The exact property encoding is registry-owned and validated. Live Phaser
objects, functions, closures, and executable source are never serialized.

Every local node and instance record has a non-negative safe-integer `order`.
For each parent, the combined local-node and instance children must use the
dense unique sequence `0..childCount-1`. Resolution merges both arrays by that
value before constructing the child list. Scene Studio reordering rewrites the
dense sequence transactionally, so lifecycle, input, processing, saving, and
reload all observe the same order.

## Scene Instances and Overrides

A saved scene may be instantiated as a child of another scene. Editing the
source scene updates all instances except properties explicitly overridden by
an instance.

```json
{
  "instanceId": "fatty-camp-instance",
  "name": "Fatty Camp",
  "sceneId": "encounter.level-1-fatty-camp",
  "parentNodeId": "encounters",
  "order": 2,
  "overrides": [
    {
      "sourceInstancePath": [],
      "sourceNodeId": "camp-root",
      "property": "position",
      "value": [2528, 1472]
    }
  ]
}
```

An instance record is a serialization and editor construct, not a runtime node
type. During resolution, the loader clones the source scene's root beneath
`parentNodeId`, applies overrides before construction, and recursively expands
nested instances. No `SceneInstance` wrapper survives at runtime. The resolved
source root receives the instance transform because position, rotation, and
scale overrides target that root's properties. Removing or freeing the resolved
root removes the complete instance subtree.

The instance record's `name` replaces the resolved source root's display name
for that placement. It must be unique among the combined local-node and instance
children of `parentNodeId`; two instances of the same source therefore receive
distinct human paths. Descendant names continue to come from the source scene.

Overrides are keyed by `sourceInstancePath`, source-node stable ID, and property
name. The instance path starts inside the referenced source scene and identifies
nested instance records before selecting the final source node. Scene Studio
marks overridden values and provides a revert action. Invalid or stale override
paths are surfaced as configuration errors rather than silently discarded.

```ts
interface SceneOverrideDocument {
  readonly sourceInstancePath: readonly InstanceId[];
  readonly sourceNodeId: AuthoredNodeId;
  readonly property: string;
  readonly value: JsonValue;
}
```

Stable node IDs are unique within their source scene, not globally. Each runtime
scene instantiation receives a unique runtime namespace. Canonical runtime IDs
are formed from the containing runtime namespace, the complete authored
instance-ID path, and the source node ID:

```text
world-run-17/fatty-camp-instance/guarded-chest/chest-root
world-run-17/fatty-camp-instance/guarded-chest/script
```

Two instances of the same source scene therefore never collide in the
`SceneTree` index. Internal node references are remapped into the instance's
namespace during resolution. Serialized cross-instance references use the
optional `instancePath` in `NodeReferenceDocument`, relative to the owning
scene.

An empty `instancePath` addresses a locally owned node. Each path segment is an
authored instance ID, so nested references remain independent of display names.
Source scenes are self-contained and may not reference upward into an unknown
parent scene; the parent may connect to or override exported nodes inside an
instance.

Authored instance IDs are also the basis of persistent world keys. Existing map
object and encounter instance IDs are preserved by conversion. The random
top-level runtime namespace and transient dynamic spawn IDs are never written to
saves. A dynamically created scene must receive an explicit stable persistence
key from its owning script if its state is intended to survive reload.

Every resolved instance root retains immutable runtime provenance:

```ts
interface SceneInstanceProvenance {
  readonly sourceSceneId: SceneId;
  readonly authoredInstanceId: InstanceId;
  readonly containingInstancePath: readonly InstanceId[];
  readonly overrides: readonly SceneOverrideDocument[];
}
```

Only the resolved root carries this marker. Calling `duplicate()` on that exact
root duplicates the source instance record and its overrides with a new
`InstanceId`; duplicating a descendant performs an ordinary detached-subtree
copy. Freeing the root discards the runtime subtree and provenance without
changing the authored instance record.

### Resolved instance example

Assume `object.chest` owns `chest-root` and `script`. The
`encounter.guard-camp` scene owns `camp-root`, `coordinator`, and a nested chest
instance whose ID is `reward-chest` and whose display name is `Reward Chest`.
The world scene places that camp twice:

```json
{
  "instances": [
    {
      "instanceId": "north-camp",
      "name": "North Camp",
      "sceneId": "encounter.guard-camp",
      "parentNodeId": "world",
      "order": 0,
      "overrides": [
        {
          "sourceInstancePath": ["reward-chest"],
          "sourceNodeId": "script",
          "property": "contents",
          "value": [{ "itemId": "green-key", "quantity": 1 }]
        }
      ]
    },
    {
      "instanceId": "south-camp",
      "name": "South Camp",
      "sceneId": "encounter.guard-camp",
      "parentNodeId": "world",
      "order": 1,
      "overrides": []
    }
  ]
}
```

A locally owned quest script may reference the first chest script with:

```json
{
  "instancePath": ["north-camp", "reward-chest"],
  "nodeId": "script"
}
```

With runtime namespace `world-run-17`, resolution produces:

| Placement | Human path | `RuntimeNodeId` |
| --- | --- | --- |
| North camp root | `/World/North Camp` | `world-run-17/north-camp/camp-root` |
| North chest script | `/World/North Camp/Reward Chest/Script` | `world-run-17/north-camp/reward-chest/script` |
| South camp root | `/World/South Camp` | `world-run-17/south-camp/camp-root` |
| South chest script | `/World/South Camp/Reward Chest/Script` | `world-run-17/south-camp/reward-chest/script` |

The nested override affects only the north chest. The two source `script` node
IDs remain unchanged in their source scene while their runtime IDs and human
paths are unambiguous.

The loader detects direct and indirect scene-instance cycles before runtime
construction.

Inherited scenes are not part of version 1. If later required, they receive a
separate design for inherited-node ownership, deletion restrictions, resource
uniqueness, and three-way merge behavior.

## Universal Scene Studio

One Scene Studio replaces the separate Character, Animation, Weapon,
Projectile, Effect, and Map Studio workflows.

```text
+------------------+-----------------------------+------------------+
| Scene Tree       | 2D Viewport                 | Inspector        |
|                  |                             |                  |
| selected scene   | transforms and anchors      | selected node    |
| and child nodes  | shapes and visual preview   | properties       |
|                  | map and UI composition      | warnings         |
+------------------+-----------------------------+------------------+
| Context panel: Animation / Tile Map / Audio / Signals / Debug    |
+------------------------------------------------------------------+
```

The shell never changes because an entity is a player, NPC, enemy, boss,
weapon, projectile, map, or UI scene. Presentation is selected-node-driven:

- `Sprite2D` exposes texture, frame, transform, and render properties;
- `CollisionShape2D` exposes geometry and viewport handles;
- `AnimationPlayer` opens the common timeline;
- `Area2D` and physics bodies expose layers, masks, monitoring, and signals;
- audio nodes expose audio resources and playback properties;
- `Control` nodes expose layout and focus properties;
- `ScriptNode` exposes its registered identity, exported properties, node-reference
  dependencies, signals, and configuration warnings; and
- scene instances expose source navigation, local overrides, and revert
  controls.

Authors add nodes through one searchable creation dialog backed by the node
registry. They may create, rename, reorder, duplicate, reparent, and safely
remove nodes subject to validation. The inspector is generated from node and
script property descriptors rather than hard-coded character-kind branches.

Locally owned nodes permit all validated structural operations. Nodes resolved
from a nested scene instance are structurally read-only in the containing
scene: authors may edit only properties declared overridable, revert overrides,
rename/move/duplicate/remove the instance record itself, or open the source
scene. They may not add, remove, reorder, rename, or reparent descendants inside
the resolved instance. This avoids introducing inherited-scene or editable-child
merge semantics into version 1.

Animation, collision editing, tile-map authoring, audio inspection, signal
wiring, and debugging appear as context panels inside this workspace. They are
not separate applications with separate catalogs or save semantics.

Scene Studio supports undo/redo, dirty state, validation, save conflicts,
source-scene navigation, and repair of invalid development content.

## Runtime Loading and Lifecycle

Runtime creation follows one deterministic pipeline:

```text
scene document
  -> resolve nested instances
  -> apply validated local overrides
  -> validate complete resolved tree
  -> construct nodes through registry
  -> enter SceneTree
  -> lifecycle, processing, physics, input, and signals
  -> queued deletion and deterministic exit
```

Required lifecycle ordering:

1. `_enter_tree()` runs parent before children.
2. `_ready()` runs children before their parent after the complete subtree has
   entered.
3. `_process()` and `_physics_process()` visit only enabled nodes in stable
   tree order.
4. `_input()` receives an input event before consumption.
5. `_unhandled_input()` receives the event only if no earlier handler consumed
   it.
6. `queue_free()` marks a node and removes it safely after the active processing
   step.
7. `_exit_tree()` runs during subtree removal and guarantees owned-resource
   cleanup.

### Phaser host boundary

`SceneTreeHost` is the only object allowed to coordinate a managed tree with a
Phaser scene. It exposes input enqueueing, one variable render-frame step, zero
or more fixed physics steps, backend contact collection, presentation sync, and
shutdown. Gameplay scripts never call the Phaser scene update loop directly.

For every rendered frame the host performs this normative order:

```text
1. Flush structural mutations left from the previous frame.
2. Drain queued input in timestamp order.
   a. Invoke enabled _input handlers in input-priority then stable tree order.
   b. If still unhandled, invoke _unhandled_input in the same order.
   c. Flush mutations after each input event.
3. Run each accumulated fixed physics step:
   a. Invoke the legacy adapter's pre-physics hook while legacy code remains.
   b. Advance physics-mode AnimationPlayer nodes.
   c. Invoke enabled _physics_process handlers in stable tree order.
   d. Synchronize managed body/area transforms and enabled shapes to Phaser.
   e. Advance Arcade Physics exactly once. Existing legacy collider callbacks
      run synchronously inside this backend step and may enqueue legacy work.
   f. Collect managed body/area contacts, canonicalize their order, and emit
      managed signals.
   g. Resolve managed attack contacts and other post-contact transactions.
   h. Invoke the legacy adapter's post-physics hook.
   i. Flush legacy and managed structural mutations.
4. Advance render-mode AnimationPlayer nodes.
5. Invoke enabled _process handlers once with the render delta.
6. Synchronize sprites, cameras, audio, and Control presentation.
7. Flush structural mutations.
```

Physics uses a fixed accumulator and a project-owned fixed delta. A frame may
run at most five catch-up steps; excess accumulated time is dropped with a
development diagnostic to avoid a spiral of death. Contact pairs are sorted by
canonical runtime node IDs before signals are emitted, so Phaser callback order
cannot change gameplay results.

The Phaser host adapter must either use verified Phaser lifecycle hooks or own
manual Arcade stepping, but it must satisfy this order in integration tests.
During hybrid migration, legacy systems and managed nodes share exactly one Arcade
step and the legacy hooks occupy exactly the positions above. Legacy input and
render updates run after managed input dispatch and before step 4's render-mode
animations, respectively. No phase may leave Phaser automatic stepping enabled
while also manually stepping the managed tree.

Signals are synchronous within a processing step. Connections are owned by the
tree and automatically removed when either participating node exits. Nodes
must register timers, Phaser callbacks, DOM listeners, and other cleanup work
through node-owned disposable facilities.

Specialized nodes wrap Phaser objects instead of extending them. ScriptNode
implementations communicate through runtime nodes, stable authored references,
human-readable lookup paths, exported properties,
signals, and narrowly scoped services. They must not import `WorldScene`.

## Validation and Error Handling

Every node registration supplies:

- allowed parent and child constraints;
- a property schema and defaults;
- inspector metadata;
- runtime construction;
- configuration-warning logic; and
- serialization and migration rules.

Scene validation checks:

- exactly one root;
- unique stable node IDs;
- valid parent references and no hierarchy cycles;
- known node and script IDs;
- valid property types, constraints, and resource references;
- valid stable node references and any literal runtime lookup paths declared by scripts;
- valid collision layers and masks;
- valid signal endpoints and signal names;
- compatible node parenting, including collision shapes beneath bodies or
  areas;
- valid scene-instance overrides; and
- no recursive scene instancing.

Errors include the scene ID and full node/property path. Examples:

```text
character.fatty-one-eye/Fatty/BodyShape:
CollisionShape2D requires a PhysicsBody2D or Area2D parent.

character.fatty-one-eye/Fatty/Script.eyeArea:
Node reference "eye" does not resolve.

map.level-1/FattyCamp:
Scene instance cycle detected through "map.level-1".
```

Development and Scene Studio load recoverable invalid documents so authors can
repair them. Invalid nodes receive visible warnings in the tree and inspector.
Gameplay refuses to instantiate structurally invalid scenes, and production
builds reject invalid scene content.

Unknown scene versions require an explicit migration. They are not interpreted
loosely.

Construction and insertion are transactional. Node constructors are
side-effect-free and may only validate/copy resolved properties. Backend
resources are acquired in `_enter_tree()` through node-owned disposables. If
resolution, construction, `_enter_tree()`, or `_ready()` fails, the complete
staged subtree is removed from indexes, every successfully entered node receives
best-effort child-first exit, and every acquired disposable is released in
reverse order. The subtree is never exposed as partially ready.

Errors from `_process()`, `_physics_process()`, input, animation callbacks, or
signal handlers capture the scene ID, node path, active lifecycle phase, signal
name when applicable, and original error. Development disables the failing
ScriptNode and reports the diagnostic without invoking it again each frame.
Generic engine-node failures pause the tree because their invariants may be
compromised.

Exit and cleanup are best-effort and exhaustive: one `_exit_tree()` or disposer
failure is recorded but does not prevent remaining descendants, connections,
indexes, Phaser objects, timers, and listeners from being released. Removal
completes even when cleanup reports errors.

In production, any uncaught lifecycle, signal, constructor, or cleanup error
pauses the owning SceneTree and opens the existing fatal-error presentation
with the scene and node path. It does not silently continue a partially updated
simulation. A failed dynamic subtree insertion rolls back only that subtree; a
root replacement uses a single-root swap transaction:

1. Resolve, validate, and side-effect-free construct the replacement while the
   old root remains active.
2. Pause host input, physics, processing, and presentation synchronization.
3. Detach but do not free the old root, releasing its backend resources and
   indexes.
4. Insert and ready the replacement as the tree's sole root.
5. On success, free the detached old root and resume the host.
6. On insertion or readiness failure, exhaustively clean the replacement,
   reinsert the old root without rerunning its ready-once callbacks, recreate
   its backend resources through entry, and then resume.

No staging tree acquires visible Phaser resources, and two roots are never
active simultaneously. If restoration of the old root also fails, the host
remains paused and shows the fatal-error presentation rather than exposing a
partial tree.

## Performance Requirements

- Stable node IDs and resolved paths use indexed lookup rather than full-tree
  scans.
- Only enabled nodes appear in process and physics-process lists.
- Area overlap routing uses Phaser groups, collision masks, or spatial
  filtering rather than comparing every area with every node.
- Signals dispatch only to registered connections and never scan the global
  tree.
- Scene resolution caches immutable source documents without sharing mutable
  runtime state.
- Before each runtime-family cutover, the existing production path is measured
  on the same authored map and deterministic workload. The replacement may not
  regress median or 95th-percentile frame time or scene-load time by more than
  10 percent without explicit user approval and a recorded explanation.
- Destroyed scenes leave no Phaser objects, timers, listeners, signal
  connections, or indexed node references.

## Migration Strategy

The migration is a program of bounded phases. Each phase keeps current behavior
available through adapters until the new owner is proven. Every subphase gets a
separate implementation plan, focused automated checks, and a rollback point.
No plan may implement an entire numbered phase as one undifferentiated change.

### Phase 1: Scene foundation

1. **1A - Document and registry contracts:** scene/node/resource identifiers,
   node and script registries, property descriptors, and pure validators.
2. **1B - Node lifecycle:** `Node`, `Node2D`, tree mutation queue, indexed IDs,
   paths, lifecycle state machine, duplication, and exhaustive cleanup.
3. **1C - Signals and SceneTree:** typed signals, groups, process lists, input
   ordering, error boundaries, and root replacement.
4. **1D - Instance resolution:** nested scene resolution, namespaces,
   overrides, cycle detection, and scene-version migration fixtures.

No production entity changes ownership in Phase 1.

### Phase 2: Core runtime nodes

1. **2A - Presentation nodes:** `Sprite2D`, transforms, resource adapters,
   depth, cameras, and Phaser presentation cleanup.
2. **2B - Physics nodes and host:** `PhysicsBody2D`, `CharacterBody2D`,
   `StaticBody2D`, `Area2D`, `CollisionShape2D`, fixed-step host ordering,
   contacts, layers, and masks.
3. **2C - Timed presentation:** `AnimationPlayer`, animation-resource adapter,
   `AudioStreamPlayer2D`, timers, and event/signal tracks.
4. **2D - Scripts and input:** `ScriptNode`, export metadata inheritance,
   script lifecycle/error behavior, input routing, and the minimal `Control`
   support required by fixtures.
5. **2E - Tile layer runtime:** `TileMapLayer2D`, tile-set/data resources,
   authored collision generation, and production-map load measurement.

All Phase 2 nodes run only in fixtures until their owning feature subphase
explicitly cuts over.

### Phase 3: Scene Studio foundation

1. **3A - Document shell:** project/scene browser, open scene tabs, scene tree,
   node creation/removal/rename/reorder/reparent, and dirty state.
2. **3B - Generic inspector:** registry-driven fields, resource and stable-node
   references, validation warnings, save conflicts, and invalid-scene repair.
3. **3C - 2D viewport:** selection, transforms, anchors, sprite preview, shape
   handles, map navigation, zoom, and snapping.
4. **3D - Animation context:** common timeline, arbitrary property tracks,
   animation events, and playback preview.
5. **3E - Tile context:** tile-set selection, tile painting, layers, collision
   preview, and authored-map validation.
6. **3F - Audio, signals, and scripts:** audio preview, signal wiring,
   ScriptNode exports, required references, and configuration warnings.
7. **3G - Diagnostics:** runtime inspection, lifecycle errors, and tree/resource
   leak diagnostics.
8. **3H - Instances and history:** scene-instance browsing, override/revert,
   duplication semantics, undo/redo, and save/reload round trips.

Existing editors remain writable until the content family they own cuts over.

### Phase 4: Character vertical slice

1. **4A - Shared character/enemy scripts:** normalized character signals,
   health, damage rules, effect responses, targeting, rewards, and compatibility
   adapters to current combat consumers.
2. **4B - Ordinary enemy fixture:** convert Worm Brawler and prove generic
   movement, attacks, damage, death, visuals, and animation.
3. **4C - Fatty entity:** convert Fatty to `FattyScript extends EnemyScript`
   with `rank: "boss"`, generalized eye damage area, authored animation areas,
   and no separate boss character kind.
4. **4D - Boss camp assembly:** convert camp activation, dynamic Fatty
   instantiation, respawn, boss UI, and guarded-chest signals.
5. **4E - Vertical-slice cutover:** make the two characters and Fatty camp
   scene-authored, deliver their manual checklist, obtain user approval, and
   retain an immediate feature-flag rollback to their legacy runtime.

### Phase 5: Remaining characters

1. **5A - Remaining ordinary enemies:** convert one package at a time, then
   retire the generic Enemy factory after family-level user approval.
2. **5B - NPCs:** create shared NPC scripts, convert authored NPC scenes and
   wander/interaction signals, then retire `NpcActor` after approval.
3. **5C - Player:** convert player visuals, body, input, stats, health,
   equipment connections, and persistence last; retain the legacy player
   factory until explicit user approval.

### Phase 6: Combat and interactive entities

1. **6A - Weapons:** scene-authored weapon visuals, animation, attack areas,
   activation deduplication, and damage requests.
2. **6B - Projectiles:** pooled scene instances, movement, collision, impact,
   ownership, and cleanup.
3. **6C - Effects:** visual/audio scene instances and deterministic completion
   cleanup.
4. **6D - Collectibles and gatherable resources:** drops, pickups, stone/tree
   interactions, rewards, and persistence IDs.
5. **6E - Houses and props:** static presentation, solid bodies, occlusion, and
   map-placement identity.
6. **6F - Chests:** contents, guarded state signals, inventory transaction, UI
   opening, and persistence.
7. **6G - Interaction and gates:** interaction areas, prompts, gated exits,
   aggregate transactions, and navigation handoff.

Each family changes writable ownership and runtime routing independently.

### Phase 7: World scenes

1. **7A - Tile resources:** convert terrain legends and tile grids to tile-set
   and tile-data resources with visual and collision parity.
2. **7B - Placements:** convert authored objects, NPCs, and other stable map
   instances while preserving every persistence key.
3. **7C - Areas and navigation:** convert safe zones, wander/spawn areas,
   encounters, exits, gates, and navigation signals.
4. **7D - World cutover:** make world scenes authoritative only after map
   round trips, save migration, user gameplay approval, and rollback rehearsal.

### Phase 8: UI scenes

1. **8A - Control foundation:** layout, themes, focus, input consumption,
   accessibility metadata, and modal stacking.
2. **8B - HUD:** status, boss health, floating feedback, and responsive layout.
3. **8C - Gameplay panels:** inventory, chest, crafting, dialogue, and other
   modal workflows one panel family at a time.
4. **8D - Menus and cutover:** remaining menus, UI-scene ownership, manual
   workflow approval, and retirement of replaced presentation factories.

### Phase 9: Retirement

1. **9A - Authoring lock:** make retired editors read-only redirects into Scene
   Studio and audit that every content family has one writable owner.
2. **9B - Runtime removal:** remove obsolete factories, catalogs, schemas, and
   adapters only when no active feature flag or save reader depends on them.
3. **9C - Final compatibility release:** retain the old-save reader for at
   least one tagged production version after final cutover, then remove it only
   through a separately approved migration decision.

### Phase gate and rollback contract

Every subphase records these fields in its implementation plan and completion
handoff:

| Gate | Required evidence |
| --- | --- |
| Deliverable | One bounded node, editor capability, or content family |
| Active adapter | Exact old/new bridge and which side invokes it |
| Writable owner before | The only files or editor allowed to save the feature before cutover |
| Writable owner after | The only files or editor allowed to save it after cutover |
| Automated gate | Focused contracts, content validation, typecheck, and build |
| Manual gate | User-only checklist for gameplay-affecting work, or `not applicable` with reason |
| Approval | Explicit user acceptance before legacy retirement |
| Rollback | Feature flag or owner switch plus preserved pre-cutover content/save snapshot |
| Removal | Exact legacy files deferred until all dependents have moved |

Adapters may read from the active owner and present normalized runtime data, but
they may not make both formats writable. Cutover is an atomic owner switch. If
the switch fails validation or user acceptance, the feature flag returns to the
old owner and the generated new content remains diagnostic output rather than
authoritative data.

### Normative ownership and conformance map

This table is the minimum traceability checklist for implementation plans. A
subphase is incomplete until its listed contracts have focused automated
coverage and the phase-gate evidence above.

| Contract area | Owning subphase |
| --- | --- |
| Scene, resource, node, instance, runtime, and persistence identifiers; registries; validation | 1A |
| Lifecycle states, mutation queue, paths, reparenting, duplication, cleanup | 1B |
| Signals, groups, process/input order, error containment, root swap | 1C |
| Nested instances, namespaces, provenance, overrides, recursive-cycle rejection | 1D |
| Visual nodes and Phaser presentation ownership | 2A |
| Physics nodes, collision semantics, contacts, and exact host-step order | 2B |
| Animation, audio, timers, and timed signals | 2C |
| ScriptNode contracts, exports, inheritance, and input routing | 2D |
| Tile resources, tile nodes, and authored collision generation | 2E |
| Scene Studio document/tree/inspector/viewport contexts | 3A-3H, each capability in its named subphase |
| Shared damage, vulnerability, effects, character signals, and enemy rank | 4A |
| Damage emission and activation deduplication for weapons | 6A |
| Hybrid save envelope and legacy normalization | 1A |
| Per-section save ownership changes | The content-family subphase changing that section; world-wide reconciliation in 7D |
| Removal of legacy writers/readers and final compatibility window | 9B-9C |

### Content and save migration

Deterministic conversion scripts migrate existing content. They are repeatable,
preserve stable IDs, reject lossy conversion, and report every unresolved
field. Original files remain authoritative until the relevant cutover; after a
successful cutover they become read-only migration fixtures until Phase 9.

After the first persisted subsystem cuts over, saves use one versioned hybrid
envelope. Its sections match the current persistence aggregates and each
section records its own schema and sole writer:

```ts
interface HybridSaveEnvelope {
  readonly schemaVersion: 10;
  readonly savedAt: number;
  readonly sections: {
    readonly player: SaveSection<'legacy' | 'scene'>;
    readonly inventory: SaveSection<'legacy' | 'scene'>;
    readonly quests: SaveSection<'legacy' | 'scene'>;
    readonly location: SaveSection<'legacy' | 'scene'>;
    readonly world: SaveSection<'legacy' | 'scene'>;
    readonly session: SaveSection<'legacy' | 'scene'>; // play time and session metadata
  };
}

interface SaveSection<Owner extends 'legacy' | 'scene'> {
  readonly owner: Owner;
  readonly schemaVersion: number;
  readonly data: unknown;
}
```

The envelope is always validated and written atomically as a whole. Each
section has exactly one writer selected by that subsystem's feature flag; dual
writes are forbidden. A section that has not cut over is still serialized by
its legacy adapter inside the hybrid envelope. A subphase that cuts over a
persisted subsystem migrates and switches only its owned section or sections,
then validates the complete envelope. No global runtime flag may implicitly
choose the owner for unrelated sections.

Legacy whole-save versions remain readable. The compatibility repository
normalizes them into the hybrid shape in memory. The first successful
new-format save includes every section, including legacy-owned sections, so a
partially migrated build never creates a partial save.

Creating or changing the envelope uses this versioned transaction:

1. Read and retain the untouched source save bytes, whether whole-save legacy
   or an earlier hybrid envelope.
2. Convert into a new in-memory save using an explicit old-to-new persistence
   key table produced by content conversion.
3. Validate the complete converted save and every referenced scene instance.
4. Write a recoverable backup and then atomically install the new save.
5. If conversion, validation, or installation fails, retain every prior section
   owner and keep the original save active; never partially install the new
   representation.

Authored map object, NPC, chest, gate, encounter, and area IDs map directly to
authored scene-instance IDs. Dynamic transient nodes do not enter saves unless
their owning script supplies an explicit stable persistence key.

Rollback while a section's legacy writer remains available restores that
section from the pre-cutover backup, selects its legacy owner, validates the
whole envelope, and atomically writes it before loading gameplay. Other section
owners do not change. Once a section's legacy writer is removed, rollback may
use its compatibility reader but may not downgrade and overwrite newer data.
Failed-cutover backups are retained until the corresponding user gameplay
approval and one subsequent successful save/load checkpoint. The legacy
whole-save reader remains for the Phase 9C compatibility window.

## Automated Verification

Automated verification may establish deterministic technical behavior but must
not be called gameplay testing.

### Core contracts

- parent/child ownership and stable ordering;
- sibling-name constraints, absolute/relative paths, rename stability, and
  stable serialized references;
- lifecycle callback ordering, callback-time mutation deferral, flush
  boundaries, ready-once behavior, detach/re-entry, and terminal free behavior;
- process enablement;
- signal delivery and automatic disconnection;
- queued deletion, same-tree reparenting, and exhaustive cleanup after errors;
- duplication ID regeneration, internal signal remapping, resource sharing, and
  external-connection omission;
- scene instance namespace generation, internal/cross-instance reference
  remapping, property overrides, and recursive-cycle rejection;
- serialization round trips and version migrations; and
- invalid hierarchy and reference rejection.

### Runtime integration

- Phaser resources are created and destroyed with their nodes;
- host integration proves the required input, fixed-physics, contact, attack,
  render-process, presentation-sync, and mutation-flush order with exactly one
  Arcade Physics step per fixed tick;
- bodies and areas respect layers and masks;
- animation tracks change properties and area enablement at exact positions;
- attack activations deduplicate persistent and overlapping area contacts and
  use deterministic damage-area priority;
- timers, audio, collisions, and listeners stop after scene removal;
- input routing honors handled and unhandled phases;
- nested scene instances resolve deterministically;
- constructor, enter, ready, signal, processing, exit, and disposer failures
  exercise transactional rollback or exhaustive cleanup as specified;
- tile-map layers reproduce authored visual/collision data; and
- destroyed subtrees leave no registered runtime resources.

### Deterministic gameplay contracts

These tests exercise pure calculations and state transitions, not subjective or
interactive gameplay:

- ordinary enemy targeting, attack lifecycle, damage calculation, death, and
  reward contracts;
- Fatty weak-area filtering, weapon filtering, leap state transitions,
  immunity, defeat, and respawn calculations;
- player movement and combat state transitions;
- NPC wander policy and interaction locking;
- weapon, projectile, chest, gate, and persistence transactions; and
- old/new serialization migration equivalence, failed conversion rollback,
  compatibility reads, one writer per section, atomic envelope writes, and
  persistence-key preservation.

### Scene Studio contracts

- create, remove, rename, duplicate, reorder, and reparent nodes;
- edit and validate properties;
- edit shapes in the viewport;
- add and revert instance overrides;
- animate arbitrary exposed properties;
- inspect ScriptNode exports and warnings;
- undo/redo and save/reload; and
- open and repair invalid development scenes without losing unrelated data.

Every phase runs its focused checks plus relevant content validators,
TypeScript checking, and production build verification.

## User-Only Gameplay Acceptance

Interactive gameplay verification is reserved exclusively for the user. The AI
may prepare a checklist and support diagnosis, but it must report:

```text
Gameplay testing: Not performed - reserved for user verification.
```

For every migration checkpoint, the implementation handoff provides a manual
checklist with:

- exact setup and required save state;
- actions to perform;
- expected visual, audible, input, and gameplay results;
- failure symptoms;
- regression checks;
- relevant Scene Studio workflow; and
- default plus edge-case scenarios.

The replaced runtime path remains available until:

1. automated technical checks pass;
2. the manual gameplay checklist is delivered;
3. the user performs the checklist; and
4. the user explicitly approves gameplay behavior.

Automated state-machine or collision tests must never be presented as evidence
that gameplay feels correct or that manual acceptance passed.

## Success Criteria

The architecture program is complete when:

1. every live map, character, weapon, projectile, effect, object, encounter,
   and UI composition is instantiated through the common scene tree;
2. one Scene Studio creates and edits their common nodes and resources;
3. the inspector contains no top-level branches for player, NPC, enemy, boss,
   weapon, projectile, effect, or map categories;
4. Fatty is an enemy with boss rank and a specialized script, not a separate
   incompatible character document kind;
5. ordinary enemies can use the same damage-area, vulnerability, immunity,
   animation, collision, visual, audio, and signal capabilities as Fatty;
6. entity-specific TypeScript behavior is isolated in ScriptNode
   implementations and no executable code is stored in scene documents;
7. scenes may be reused through instances with explicit, reversible local
   property overrides;
8. authored content has one writable source of truth after migration;
9. scene and node lifecycles leave no listeners, timers, signals, or Phaser
   objects after cleanup;
10. all automated technical gates pass; and
11. every retired gameplay path has explicit user gameplay acceptance.
