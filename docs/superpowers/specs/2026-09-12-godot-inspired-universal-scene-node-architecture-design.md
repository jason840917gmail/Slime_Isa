# Godot-Inspired Universal Scene and Node Architecture Design

## Status

Revised design for replacing Slime Isa's separate map, character, animation,
weapon, projectile, and effect authoring models with one Godot-inspired scene
tree, one runtime node model, and one Scene Studio.

The user has approved the universal architecture and a coordinated full
refactor, including temporary breakage during development. This revision
strengthens the implementation contracts and product acceptance criteria. It
defines one integration target with internal milestones, not a requirement for
independently shipped migrations or approval of every technical step. Final
gameplay acceptance belongs exclusively to the user.

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
9. Complete one coordinated migration with bounded commits, focused checks,
   and a complete content conversion; temporary development breakage is allowed.
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
- Do not release the replacement as gameplay-accepted before the user verifies
  it. Legacy source may be removed during the refactor when its replacement is
  covered and recoverable through version control.
- Do not use the migration as permission for unrelated gameplay redesigns.

## Core Concepts

### Product principles and Godot boundary

The author learns one operation once: selecting a visual, shape, animation,
audio, or script node always exposes the same controls, regardless of its
entity's category. Different exported script properties are expected; different
editor shells, duplicate save locations, and category-specific implementations
of the same property editor are not.

Godot is the reference for scene composition and editor vocabulary, not a claim
of API compatibility. Godot attaches a script to a node and treats `PackedScene`
as a resource. This project deliberately presents behavior as a dedicated
`ScriptNode` child backed by TypeScript, and uses a typed scene-reference field
distinct from media-resource fields. Stable serialized IDs, detached backend
cleanup, and queued mutation boundaries are also project contracts. Godot
examples must be translated to these contracts rather than copied literally.

Reference: [Godot nodes and scene instances](https://docs.godotengine.org/en/stable/tutorials/scripting/nodes_and_scene_instances.html).

Physics configuration chooses blocking versus overlap detection before a
physics step. Scripts may configure that participation and interpret contacts;
they cannot retroactively undo physical separation by calling a contact
"non-solid" after the step. Visuals and collision geometry remain independent.

### Node

`Node` is the base runtime unit. Every node has:

- an authored identity for references/overrides and a separate runtime identity;
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
detached nodes retain their configuration and script state and may be added
again. Runtime backend objects and external subscriptions are released on exit
and recreated on a later entry. `queue_free()` schedules terminal destruction of the complete
subtree. A freed node may never be re-added.

There are two explicit lifetime scopes:

- Node lifetime: authored references and node-to-node signal connections survive
  detach/re-entry. They deliver only while both endpoints are active in the same
  tree, and disconnect permanently when either endpoint is freed. Connection
  handles are idempotent; re-entry cannot multiply a connection made in `_ready()`.
- Tree-entry lifetime: Phaser objects, DOM/input subscriptions, and backend
  timers belong to an entry disposable bag. `_enter_tree()` recreates these
  leases and `_exit_tree()` releases them. `_ready()` must not own a lease that
  must be reacquired after detachment. Stable node wrappers never expose cached
  backend objects to scripts.

Logical animation position, velocities, and script timers survive detachment
but do not advance while detached. Re-entry reconstructs backend state from
those logical values. One-shot audio is stopped, not replayed by re-entry;
explicitly playing loops resume from their logical state where supported.

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

Parent targets are revalidated at flush: absent/freed parents, ancestry cycles,
duplicate names, and invalid physics transforms reject the operation without
partially moving a subtree. Freeing an ancestor suppresses pending work in that
subtree. Use `reparent()` for an atomic move; a same-flush remove-then-add of an
attached node is rejected as ambiguous rather than silently losing the add.
Unattached document construction uses immediate child operations before entry.

Insertion into an active tree calls `_enter_tree()` parent-first and then calls
`_ready()` child-first after the full inserted subtree is indexed. `_ready()`
runs once per node lifetime; detaching and re-adding the same node does not run
it again. Removal calls `_exit_tree()` child-first. Reparenting within one tree
is atomic, emits no exit or entry lifecycle callbacks, and preserves the global
transform of `Node2D` nodes. Reparenting across trees is rejected; callers must
detach and then add the subtree explicitly.

`duplicate()` creates a detached copy of authored configuration, never a snapshot
of health, AI state, active attacks, callbacks, or backend objects. It assigns
new stable node IDs, resets runtime and lifecycle state, copies configured
exported properties, shares immutable external resources, and deep-copies inline
subresources. It remaps every internal node reference, animation target, override,
and authored signal endpoint. External node references become unresolved and
external signal connections are omitted; required unresolved references prevent
insertion until the caller supplies them. Runtime subscriptions are not copied.
Duplicating a resolved
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

Node names must be non-empty, may not equal `.` or `..`, may not contain `/`, and must be unique among
siblings. Human-readable runtime paths use `/Root/Child`, `Child/Grandchild`,
`.` and `..`. Renaming changes the human path but never changes the stable node
ID.

Serialized node references do not store fragile name paths. They use:

```ts
interface NodeReferenceDocument {
  readonly instancePath?: readonly InstanceId[];
  readonly nodeId: AuthoredNodeId;
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

Validation resolves it through the scene catalog and checks authored instance
cycles. A dynamic scene reference is not an eagerly expanded instance edge;
otherwise projectile or spawn references could falsely form construction cycles.
Resource loading may deduplicate cyclic dependency requests, but only the
authored `instances` graph must be acyclic. Loading provides a packed scene
blueprint to `SceneTree.instantiate_scene()`. It never passes through the media
resource registry.

Loading is explicitly separate from instantiation: `prepare_scene(sceneId,
abortSignal)` asynchronously resolves documents and required assets into a
validated immutable packed scene; `instantiate_scene(packedScene)` synchronously
constructs a detached tree. Lifecycle callbacks never await I/O. A spawn/load
request belongs to its initiating node or host: exit/cancellation invalidates
late completion so it cannot insert into a departed map. Failed preparation
leaves the active scene intact. Cached documents/assets have reference-counted
leases; failed construction and cancellation release only their own leases.

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

IDs use a validated delimiter-safe alphabet; canonical runtime IDs encode each
segment, not unchecked string concatenation. A runtime ID stays constant for a
node's lifetime even after rename/reparent; its instance path is its construction
namespace, not its current human path. Reparenting must not alter save identity.
Runtime-created roots receive runtime provenance without inventing authored
placement IDs. Persisted placement keys are explicit and unique within a map;
nested reused scenes derive keys from the full authored placement path unless
conversion supplies an existing legacy key.

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
|- AudioStreamPlayer
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

Scripts set velocity (world units/second) during `_physics_process()` and the
host advances motion once. They read the previous completed step's blocking
contact records, or consume this step's post-physics contact signal. Records
contain collider runtime ID, optional live node, normal, and contact position
where the backend can provide it. A teleport queues a position change for the
pre-step sync. There is no synchronous `move_and_slide()`/`move_and_collide()`
promise on top of a backend that is stepped later by the host.

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
shapes are rectangle, circle, ellipse, and directional sector. It must be a child of a compatible
physics body or area.

The backend capability contract is explicit:

| Owner | Supported geometry | Shape count | Transform limits |
| --- | --- | --- | --- |
| CharacterBody2D / StaticBody2D | Axis-aligned rectangle or circle | Exactly one enabled shape when collision is enabled; disabled alternate shapes allowed | Translation and positive scale; circles require uniform world scale; no world rotation or shear |
| Area2D | Axis-aligned rectangle, circle, ellipse, directional sector | One or more enabled shapes, combined as a union | Translation and positive scale; circles/sectors require uniform scale; ellipses may scale independently on each axis; sector direction is an explicit geometry angle; no node world rotation or shear |
| Visual nodes | Backend-supported visual transforms | Independent of physics | Rotation, flipping, and scale do not implicitly alter sibling physics geometry |

The inspector, animation validator, and runtime enforce these constraints,
including ancestor transforms. Unsupported combinations produce an actionable
error; the engine never silently substitutes a bounding rectangle. A body may
temporarily disable collision explicitly without removing its shape nodes.
Changing among disabled alternatives is applied atomically before the step.
Complex static outlines use multiple static body children under a neutral
Node2D. Compound moving-body collision and arbitrary rotated rectangle/ellipse
shapes are out of scope. A sector stores finite `angleRad`, `arcWidthRad`,
`innerRadius`, and `outerRadius`, with 0 < arcWidthRad <= 2*pi and
0 <= innerRadius < outerRadius. It is sensor-only and preserves the directional
sword/gauntlet geometry already used by production weapons. Facing updates its
geometry angle/offset through script or animation; it does not rotate an Arcade
body. Conversion tests cover front/back, inner/outer radius, and arc boundaries.

Arcade supplies blocking-body resolution. Area sensors use spatially filtered
candidate pairs and shared geometry routines, including the project's current
ellipse approximations and directional-sector calculations, rather than claiming
Arcade supports those bodies. Preserve those algorithms and characterize their boundary behavior with
fixtures during migration; changing their accuracy is a separate gameplay
change. Editor diagnostics can show both the authored outline and effective
contact region. Reference: [Phaser 3.90 Body geometry](https://docs.phaser.io/api-documentation/3.90.0/class/physics-arcade-body).

Legacy authored ellipse bodies currently use conservative rectangular movement
bounds in `shared/collisionShapes.ts`. Conversion creates an explicitly authored
rectangle BodyShape with those exact bounds/offsets, and retains an ellipse
Area2D shape only where the old runtime used ellipse sensing. The report records
this deliberate split; it is not a new runtime fallback or a change in coverage.
Do not infer an extra damage sensor merely because the old document said ellipse.

Layers identify membership; masks identify what an observer queries. Area
monitoring is directional: A receives a contact when its mask intersects B's
layer and B is monitorable, independently of B monitoring A. Blocking requires
both bodies' masks to accept the other's layer. Multiple shape contacts produce
one enter/exit pair per owner pair, plus shape IDs in detailed contact data.
The sensor service retains current overlaps for attacks that stay in contact;
combat does not rely only on an initial `area_entered` signal.

Disable, detach, or free invalidates contacts immediately for damage routing.
At the next contact reconciliation, each still-active observer receives one
exit for a removed pair, with stable IDs and an optional live-node reference.
Dead endpoints never receive callbacks. Enabling an already-overlapping sensor
produces an enter on the next physics step.

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

Each player has one master clock and an explicit physics or render domain.
Tracks that affect collisions, attack activation, or gameplay events require
physics mode. A character's associated visual tracks use that same clock so the
visible contact frame and active shape cannot drift. Render interpolation may
smooth presentation but cannot advance gameplay state.

Property descriptors declare value type, interpolation (step or numeric),
animatability, override eligibility, and clock restrictions. Boolean, enum,
resource, and frame changes are stepped. Events crossed by a normal advance
fire once in timestamp then authored-track order, including loop boundaries.
Seeking for preview applies properties without firing gameplay events. Stop,
replacement, or cancellation restores transient attack/shape overrides to their
pre-play baseline and ends the attack activation. Two active animation players
may not write the same property; validation rejects the conflict.

Shared animation resources address named typed bindings, such as `visual` or
`attackArea`; each AnimationPlayer maps these to stable node references in its
own scene. An inline animation may use local references directly. This lets one
animation library work across scenes with different authored node IDs.

### AudioStreamPlayer and AudioStreamPlayer2D

`AudioStreamPlayer` handles non-positional music and UI audio.
`AudioStreamPlayer2D` handles world-positioned audio. Both use the same inspector
for resource, volume, pitch, looping, playback state, and cleanup; the 2D node
adds positional settings supported by the backend. Neither decides
when a sound represents an attack, death, interaction, or UI response.

Both honor existing music/effects volume and mute preferences. Browser audio
unlock occurs only through the existing user-gesture service. Preview playback
requires an explicit action and stops when its preview context closes.

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
  "order": 5,
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

Creating a ScriptNode selects an existing registered implementation. Adding new
behavior source is normal external TypeScript development; Scene Studio shows
the source path and can open it externally, but cannot edit or execute source
text. Multiple ScriptNodes may coexist when they own distinct responsibilities.
Required capabilities declare exclusive ownership, so two scripts cannot both
drive the same body's movement or register the same area as their damage target.
Adding or replacing a script reports conflicts before saving.

Script constructors receive a typed context of runtime-node access and required
services. Shared calculations and domain services remain reusable modules;
"all code in the ScriptNode" means entity orchestration lives there, not that
inventory, persistence, animation engines, or damage math must be copied into
each script. Scripts may request domain operations, but only the persistence
infrastructure accesses browser storage.

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

Rank is classification metadata, not an automatic behavior switch. Faction
owns hostility policy; rank may be observed by UI or encounter scripts. A boss
may use shared EnemyScript without custom logic, and an ordinary enemy may use
a specialized script. Common health/damage helpers do not require inheriting
CharacterScript when the receiver is a destructible object.

## General Damage and Vulnerability Model

Damage reception is a shared capability implemented by any relevant ScriptNode:
player, enemy, destructible prop, or another damageable entity. Ordinary `Area2D`
nodes supply contacts. A typed `DamageReceiver` interface and pure resolver own
the common request/result contract; `EnemyScript` is one consumer. This is not a
new engine node type or a requirement to inherit enemy behavior.

The receiver registers its area references with a tree-scoped routing service
on entry and unregisters on exit. One area belongs to at most one receiver.
The attacking script submits contact candidates through that service without
searching entity classes. The receiver owns health, effect application, and
state-dependent acceptance. Accepted damage/effects and defeat state commit
together before publishing feedback; a defeated receiver cannot award twice.

A damage-area rule identifies a stable node reference and describes
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
  readonly sourceNodeId: RuntimeNodeId;
  readonly attackAreaNodeId: RuntimeNodeId;
  readonly targetAreaNodeId: RuntimeNodeId;
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

Requests with non-finite or negative damage or potency, non-finite impact data,
duplicate tags/types/effects, or unknown runtime nodes are rejected as `invalid`.
An inactive attack area or mismatched activation ID yields `inactive-attack`.
An absent effect response means multiplier `1`; invalid final numeric results
are rejected before any mutation. For an accepted source, final damage is
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
activation ID containing its source runtime ID and a monotonically increasing
sequence; ending or cancelling
the attack invalidates it. Contacts gathered during one physics step are grouped
by target damage-receiver ScriptNode. Candidate area rules first filter by
current overlap and accepted source, then sort by highest `priority` and lowest
runtime area ID as a tie-break. Only the highest candidate is evaluated; immunity
or script state on that candidate does not fall through to a less-preferred
area. No accepted-source candidate yields `source-blocked`.
The attacking script records one accepted attempt per
`(activationId, targetReceiverRuntimeId)`, so persistent overlap callbacks
cannot apply repeated frame damage or double-hit through overlapping body and
weak-point areas. Non-retryable rejections are cached only for the selected
area (or rejected area set when no source matches), not the whole receiver:
touching armor must not prevent a later eye hit in the same swing. A changed
candidate area set is evaluated again unless an accepted hit already consumed
that receiver. A retryable `state-blocked` result may be evaluated again on a
later fixed step while the same active area still overlaps. A deliberately
multi-hit attack starts a new activation for
each authored pulse. Attack cancellation, scene removal, and node disablement
clear pending contacts before they can resolve.

Existing attack damage, knockback, effect timing, vulnerability, reward, and
invulnerability behavior must be captured in conversion fixtures. The formulas
above define the shared route; they do not authorize balance changes. Compound
damage types here are multiplicative classifications, not independently weighted
damage components. Multi-component damage and new stacking policies are out of
scope. Combat feedback is emitted after confirmed results, preserving the current
rule that animation events cannot independently synthesize a successful impact.

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

`property` names one registered top-level exported property; structured values
replace that property atomically. The inspector may edit nested fields through
the same descriptor, then write the complete property value. Arbitrary dotted
paths, executable setters, and patch expressions are not supported.

Override precedence is source defaults, source-scene values, inner instance
overrides, then outer containing-scene overrides. Duplicate entries for the same
target/property in one override list are invalid. Each value retains its authoring
scope: a node-reference value supplied by an override resolves relative to the
scene document containing that instance record, while an inherited source value
resolves relative to its source scene. The resolver validates and translates
references using that scope before constructing nodes; flattening may not discard
it. Thus a parent can inject a sibling node reference into an instance's exported
dependency without changing the reusable source or adding upward references there.

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

Every authored resolved instance root retains immutable runtime provenance:

```ts
interface SceneInstanceProvenance {
  readonly sourceSceneId: SceneId;
  readonly authoredInstanceId: InstanceId;
  readonly containingInstancePath: readonly InstanceId[];
  readonly overrides: readonly SceneOverrideDocument[];
}
```

Dynamic roots instead retain their source scene and configured overrides with
an absent authored placement identity; their runtime namespace is allocated by
the tree. Duplicating them creates another transient instance and never copies
an explicit persistence key. A caller must assign a new key before persisting it.

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

### Authoring quality and safe preview

One shell does not mean a wall of generic fields. Property descriptors group
related fields, carry units and help, expose defaults and reset actions, and
provide reusable controls for shapes, assets, references, and vulnerability
rules. A field shows whether its value comes from a default, its source scene,
or a local override. Validation links directly to the affected node and field.
Searchable scene templates assemble ordinary nodes for an enemy, prop, or UI
panel; they are starting documents, never special editor modes or runtime types.

Node creation and structural edits are document transactions with undo/redo.
Deleting a referenced node lists affected references and requires an explicit
repair or removal choice within that command; the editor never silently clears
unrelated data. Invalid development documents may be saved as drafts but cannot
be used by production gameplay. Unknown fields/nodes survive a repair round trip
as opaque data until explicitly removed or migrated.

External resources are shared and immutable at runtime. Editing one shows its
consumers and offers edit-shared or make-unique through the same resource editor.
An instance property override cannot silently mutate a resource used elsewhere.
Save operations compare the version/hash read from disk; a stale editor cannot
overwrite newer content. Changes spanning scene and resource files use a
validated write set with recoverable originals. Failed writes restore the set
and keep edits dirty. The editor's persistence adapter stays in infrastructure.

Preview uses a disposable presentation tree with gameplay ScriptNodes disabled.
It may display visuals, play/seek timelines, inspect shapes, and explicitly play
audio. It cannot award items, spawn gameplay populations, invoke domain services,
or write player saves. Gameplay event tracks are shown as markers, not executed.
Closing/reloading a preview releases its resources and restores edited property
baselines. Runtime debugging is a separate read-only view; observations never
write back to authored documents. No hot replacement of live scripts is required.

### Required authoring walkthroughs

These are acceptance scenarios for the product, not optional demonstrations:

1. Create an enemy scene from an ordinary-node template. Add/select its sprite,
   body shape, animation player, audio, and an existing ScriptNode implementation.
   Configure health and weapon vulnerability through exported properties. Save,
   close, and reopen; values, references, shape placement, and timeline timing
   are preserved without editing JSON.
2. Open Fatty and the ordinary enemy consecutively. Edit their visuals,
   animation, audio, and colliders using the same controls. Fatty exposes boss
   rank and specialized script fields; the shell and common inspectors do not
   change. Add a second damage area to the ordinary enemy and assign its response
   without adding an engine node type or editor branch.
3. Place two instances in an authored world scene. Override one instance's
   health or visual resource. Edit the source and confirm non-overridden values
   update both, the override survives, and revert restores the source value.
   Rename and reorder instances without breaking signals or saved identities.
4. Repeat common visual, shape, animation, and audio edits on a projectile,
   prop, and UI composition where applicable. Shared resources are discoverable
   in the same browser, and make-unique isolates a change intentionally.
5. Undo a deletion, repair a missing reference, resolve a disk save conflict,
   and close/reopen preview. No unrelated fields, runtime state, or saved progress
   change; diagnostics describe the failed operation in plain language.

Keyboard navigation, visible focus, searchable node creation, unit labels, and
readable errors are required for the editor. Selection and viewport context stay
stable across save and validation. These workflows supplement technical tests;
interactive gameplay remains reserved for the user.

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
   b. Route to focused/modal Control handlers and bridge DOM consumption.
   c. If still unhandled, invoke _unhandled_input in the same order.
   d. Flush mutations after each input event.
3. Run each accumulated fixed physics step:
   a. Invoke the legacy adapter's pre-physics hook while legacy code remains.
   b. Advance physics-mode AnimationPlayer nodes.
   c. Invoke enabled _physics_process handlers in stable tree order.
   d. Synchronize managed body/area transforms and enabled shapes to Phaser.
   e. Advance Arcade Physics exactly once. Existing legacy collider callbacks
      run synchronously inside this backend step and may enqueue legacy work.
   f. Copy authoritative post-step body positions/velocities into Node2D state,
      recompute descendant area transforms, then collect sensor/body contacts.
      Canonicalize their order and emit
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
While temporary adapters remain, legacy systems and managed nodes share exactly one Arcade
step and the legacy hooks occupy exactly the positions above. Legacy input and
render updates run after managed input dispatch and before step 4's render-mode
animations, respectively. No integration may leave Phaser automatic stepping enabled
while also manually stepping the managed tree.

Signals are synchronous within an active processing step. Connection records
follow the node-lifetime rules above; tree delivery indexes contain active
endpoints only. Node-to-node connections use a typed signal ID, source reference,
target ScriptNode reference, and registered handler ID with compatible payload
metadata. JSON contains no handler source. Delivery uses connection creation
order and a snapshot; disconnected/freed endpoints are skipped before invocation.
Structural edits requested by a handler defer to the normal mutation boundary.

Gameplay action handlers belong in `_unhandled_input()` so text fields, menus,
and modals can consume events first; `_input()` is for deliberately global input.
One event carries a handled flag across DOM, Control, and script routing. While
paused, gameplay physics/timers/process lists stop; controls explicitly marked
`processWhenPaused` continue to receive UI input and render updates. Resume
clears accumulated physics time and stale held-action transitions.

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

One declarative property descriptor owns serialized type, default, validation,
inspector metadata, and animatable/overridable flags. Runtime TypeScript types and
document validators must derive from that contract or have automated equivalence
checks; do not hand-maintain three disagreeing schemas. Runtime-only state is
marked non-serialized and never appears as authored configuration. Required
references declare the expected node type/capability and multiplicity. Registries
validate inheritance and type compatibility before opening a scene.

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

Insertion has a private lookup scope for the complete staged subtree. Exported
references resolve before callbacks; `_enter_tree()` must not assume a child's
backend is already created. Public lookup, gameplay queries, and signal delivery
include the subtree only after readiness succeeds. Lifecycle callbacks configure
local state and leases only: they cannot grant rewards, change persistent domain
state, or emit externally delivered gameplay signals. Requested post-insertion
commands queue until commit and are discarded on failure. This boundary prevents
rollback from leaving external effects that disposing nodes cannot reverse.

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
4. Insert and ready the replacement as the tree's sole root, keeping domain
   commands and public signal delivery suspended until commit.
5. On success, free the detached old root and resume the host.
6. On insertion or readiness failure, exhaustively clean the replacement,
   reinsert the old root without rerunning its ready-once callbacks, recreate
   its backend resources through entry, and then resume.

No staging tree acquires visible Phaser resources, and two roots are never
active simultaneously. If restoration of the old root also fails, the host
remains paused and shows the fatal-error presentation rather than exposing a
partial tree.

On a handled replacement failure, the old logical state and node-lifetime
connections remain intact; entry leases are reacquired exactly once. Restore
animation positions, logical timers, and body state before resuming. This is a
recoverable load failure shown to the user, not silent success. Any failure
outside this explicit recovery path follows the production fatal-error rule.

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

## Implementation and Integration Strategy

This is one coordinated full refactor with one implementation plan. The user
accepts temporary breakage on the development branch. The milestones below are
dependency boundaries and reviewable commits, not separate approval workflows.
Implementation continues through them without asking the user to approve
routine technical steps. Do not spend the project maintaining two complete
engines or editors in production.

### Milestones and dependency order

| Milestone | Concrete deliverable | Evidence before moving dependent work forward |
| --- | --- | --- |
| M1: Contracts and thin runtime | Registry/schema, stable IDs, node lifetimes, references, signals, instance resolution, and minimal Phaser host | Pure contracts, lifecycle/rollback fixtures, and a sprite/body/area/script fixture prove the highest-risk boundaries |
| M2: First complete authoring slice | Minimum Scene Studio tree, inspector, shapes, animation, audio, save/reload, overrides, and preview for ordinary enemy + Fatty | Both use identical common controls; existing combat adapters exercise damage and animation parity; technical checks pass |
| M3: All entity families | Player, remaining enemies, NPCs, weapons, projectiles, effects, props, collectibles, chests, and encounters use nodes | Conversion inventory is complete for these families; domain contracts and cleanup checks pass |
| M4: World and UI integration | Tile resources, authored placements, navigation, UI controls/panels, global audio, and complete Scene Studio contexts | Production maps load with preserved identities; all authoring walkthroughs can be performed; old/new save fixtures agree |
| M5: Consolidation and handoff | Remove obsolete writers, editors, factories, and temporary adapters; update architecture and contributor docs | Full technical checks, conversion report, performance report, and one grouped user gameplay checklist |

M2 deliberately precedes a complete tile or UI editor: prove the user-facing
reason for the refactor early. M1 physics feasibility must be settled before
mass conversion. Work within a milestone is split into bounded commits, but
there is no requirement for a separate plan per node type. Dependent work cannot
claim a contract verified while its required fixture still fails.

Compatibility adapters are temporary bridges needed to run mixed fixtures or
integrate families during development. Each has a named owner and deletion
milestone, reads one authoritative content format, and cannot introduce a
second writer. Keep an adapter only while a specific dependency requires it.
Do not add independent per-family production feature flags by default.

### Baseline and conversion inventory

Before conversion, record the current worktree's behavior-bearing content,
including user changes that are not yet committed. Unrelated edits are preserved.
The implementation plan inventories every production scene/map, character,
weapon, projectile, effect, object family, UI entry point, editor save endpoint,
shared animation path, and persistence dependency.

Each inventory row identifies its old owner, destination owner, conversion
method, preserved IDs, focused checks, and legacy files to remove. Migrators are
repeatable, reject lossy or unresolved fields, and produce a report. Unknown
gameplay values may not be discarded to make validation pass. Examples are
insufficient: conversion must cover all authored production content.

During conversion, generated scene output is read-only until the owning content
family changes writer. The old writer then becomes unavailable or redirects to
Scene Studio immediately; legacy reader adapters may remain temporarily.
At completion there is one writable source for each value and one save workflow.
Source snapshots and version control provide recovery, so obsolete editors do
not need to remain accessible to authors.

A family may have its legacy source removed once conversion and technical parity
checks pass and the implementation remains recoverable. Final integration is
not labeled gameplay-approved until the user completes the checklist. If a
milestone is temporarily unbuildable, record the failing boundary and fix it
before treating the dependent milestone as verified.

### Existing architecture and single ownership

The node model changes runtime composition, not the ownership of every game rule.
Retain the existing dependency direction:

- Scene documents and immutable resource definitions belong in content.
- Engine-independent tree/registry contracts belong in a focused runtime module.
- Phaser node implementations and SceneTreeHost form the backend adapter.
- Feature ScriptNodes orchestrate behavior through typed runtime and service
  interfaces; they cannot import WorldScene or Phaser.
- Domain services continue to own inventory, quests, progression, transactions,
  and shared combat calculations.
- Infrastructure exclusively owns browser persistence, content-file writes,
  resource loading, and platform integrations.
- Scene Studio consumes document/registry contracts without importing gameplay
  factories. Its preview capability set excludes gameplay services.

Global defaults and balance already owned by game-constants remain there,
including primary-player attributes, movement, and progression. Scene exports
must not create a second editable copy. The inspector may expose a resource
reference or navigate to the owning project-data editor inside the same shell.
Enemy-specific values belong to that enemy's script configuration. Raw-media
metadata stays in the asset manifest; node behavior and collision stay outside
it. Existing shared animation infrastructure is reused or evolved, not copied
into each node implementation.

Update docs/ARCHITECTURE.md and repository validators during M5 so contributors
have one current ownership contract. MobileVersion remains an independent Godot
application; this migration targets the Phaser application only.

### Persistence and recovery

Preserve the current versioned GameSaveData contract and SaveSystem/
SaveRepository path. Node runtime changes alone do not justify a new save schema.
Scripts use typed domain adapters to read and modify existing persisted state.
Player state, inventory, quests, location, world progress, and play time remain
one coherent snapshot. Runtime node IDs, backend objects, script source, and
live node trees never enter that snapshot.

MapId plus the existing authored object/encounter key remains the persisted
identity. Scene composition must not change those keys on rename, reparent, or
conversion. A map instantiation builds a unique key index and rejects duplicate
keys; dynamic transient nodes remain unsaved unless their owning domain service
assigns a stable key. New reusable placements derive unique keys as described
in the identifier contract.

Use a schema migration only when an identified existing field cannot represent
the preserved domain state. Such a migration belongs to the persistence layer,
must cover every supported input version, and must preserve the complete save.
No hybrid envelope, runtime-owner tag, or fixed future schema version is
required by this design.

Cross-domain actions such as chest transfer, consumed-key gate unlock, and
quest rewards continue to use a transaction coordinator. Prepare and validate
all participating changes, install them together, and emit notifications only
after commit. Autosave runs from a coherent committed snapshot. Injected failures
must preserve item totals and gate/chest/reward consistency.

If a format conversion is necessary:

1. Retain the untouched source save and its metadata.
2. Convert and validate the whole snapshot in memory.
3. Install through the repository's recoverable save operation, keeping the
   previous complete snapshot if validation or writing fails.
4. Verify load/save equivalence, including inventory/world relationships.

Rollback never mixes independently dated save sections. First attempt recovery
using compatible code that can read the current complete snapshot. If restoring
a backup would lose progress, retain the current save and require an explicit
user choice of whole snapshot; technical failure does not authorize replacing
newer progress. Migration fixtures use isolated copies and never alter the
user's live saves. An old-save reader may remain when required by supported
saves; old editor/runtime code need not remain merely to support that reader.

### Normative conformance map

| Contract | Milestone and required verification |
| --- | --- |
| IDs, document schema, registry descriptors, nested references and overrides | M1: invalid/valid fixtures, round trips, duplicate/remap tests |
| Node and entry lifetimes, signals, detach/re-entry, mutation ordering | M1: lifecycle traces and no duplicate leases/connections |
| Physics capabilities and host ordering | M1: supported/unsupported geometry, authoritative post-step sync, one backend step |
| Transactional insertion/root recovery | M1: constructor/entry/ready failure injection and restored logical state |
| Shared combat and weak-point behavior | M2-M3: common receiver contract, candidate changes, deduplication, confirmed feedback |
| Editor common controls, resources, preview and undo | M2-M4: required authoring walkthroughs plus document/preview tests |
| Animation clock and bindings, audio lifetime | M2-M3: event boundaries, cancellation, resource reuse, no preview domain effects |
| Content completeness and persistent identities | M3-M4: complete conversion inventory, map/key validation |
| Saves and cross-domain transactions | M3-M4: complete-snapshot equivalence and fault injection |
| Retirement, documentation and final product acceptance | M5: single-writer audit, full checks, performance evidence, user checklist |

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
- signal suspension on detach, restoration on re-entry, and disconnection on free;
- queued deletion, same-tree reparenting, and exhaustive cleanup after errors;
- duplication ID regeneration, remapping of all internal references and authored
  signals, resource sharing, runtime-state reset, and unresolved external references;
- scene instance namespace generation, internal/cross-instance reference
  remapping, property overrides, and recursive-cycle rejection;
- serialization round trips and version migrations; and
- invalid hierarchy and reference rejection.

### Runtime integration

- Phaser resources follow entry leases while logical state survives detachment;
- host integration proves the required input, fixed-physics, contact, attack,
  render-process, presentation-sync, and mutation-flush order with exactly one
  Arcade Physics step per fixed tick;
- bodies and areas respect layers/masks, supported transform restrictions,
  multi-shape union semantics, directional sector boundaries, legacy effective
  body conversion, and contact invalidation;
- animation tracks change properties and area enablement at exact positions;
- attack activations deduplicate persistent and overlapping area contacts, use
  deterministic damage-area priority, and permit a later weak-point candidate
  after a rejected armor contact;
- timers, audio, collisions, and listeners stop after scene removal;
- input routing honors Control/DOM consumption, handled/unhandled phases, and pause;
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
- save adapter equivalence, complete-snapshot recovery, compatibility reads,
  coherent transaction/autosave boundaries, and persistence-key preservation.

### Scene Studio contracts

- create, remove, rename, duplicate, reorder, and reparent nodes;
- edit and validate properties;
- edit shapes in the viewport;
- add and revert instance overrides;
- animate arbitrary exposed properties;
- inspect ScriptNode exports and warnings;
- undo/redo, save conflicts, recoverable multi-file writes, and save/reload;
- preview isolation from scripts, gameplay events, and live saves;
- shared resource editing, make-unique, and instance override origin; and
- open and repair invalid development scenes without losing unrelated data.

Every completed milestone runs its focused checks plus relevant content
validators, TypeScript checking, and production build verification. M5 runs the
complete repository verification sequence. This documentation revision itself
requires document consistency review, not a claim that runtime tests were run.

## User-Only Gameplay Acceptance

Interactive gameplay verification is reserved exclusively for the user. The AI
may prepare a checklist and support diagnosis, but it must report:

```text
Gameplay testing: Not performed - reserved for user verification.
```

The final implementation handoff provides one checklist grouped by authoring,
combat, world/progression, UI/audio, and save/load. Earlier playable milestones
may supply optional subsets without making user availability a blocker for
independent implementation. Each scenario contains:

- exact setup and required save state;
- actions to perform;
- expected visual, audible, input, and gameplay results;
- failure symptoms;
- regression checks;
- relevant Scene Studio workflow; and
- default plus edge-case scenarios.

Final gameplay acceptance requires:

1. automated technical checks pass;
2. the manual gameplay checklist is delivered;
3. the user performs the checklist; and
4. the user explicitly approves gameplay behavior.

Legacy paths need not remain accessible during this process; version control,
preserved content snapshots, and complete save backups provide recovery. Report
technical implementation completion and pending user acceptance separately.

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
10. all automated technical gates and required authoring walkthrough contracts
    pass, with any user-run checks identified honestly; and
11. final gameplay acceptance is explicitly confirmed by the user.
