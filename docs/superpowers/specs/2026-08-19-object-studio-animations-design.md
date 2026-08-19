# Object Studio Animations and Resource Hit Effects

**Status: approved design, implementation pending.** This document extends the
Stone Gathering task with shared object-animation authoring. It is intentionally
small and focused on the first Object Studio slice.

## Goal

Give every authored object a dependable static visual while allowing optional
shared animations to be authored outside Map Studio. All map instances of the
same object visual consume the same animation package.

## Ownership boundaries

- **Map Studio** owns map composition: placement, movement, scale, collision,
  depth, occlusion, and preview. It links to Object Studio but does not contain
  the animation timeline.
- **Object Studio** owns shared object visual templates: the base frame, an
  optional looping idle animation, and an optional resource hit effect.
- **Weapon Studio** owns weapon animation and enemy-confirmed hit effects.
- **Resource definitions** own material feedback. A resource node may declare a
  `hitEffectId`; the weapon only supplies damage and modifiers.

Map Studio keeps the existing shared-template geometry controls (scale,
collider, depth, and occlusion). Object Studio adds animation authoring without
moving those geometry controls or introducing per-instance overrides.

## Content model

Every object visual keeps its static base asset/frame. Animation is optional:

- no idle package means the runtime renders the static image;
- an authored idle package is attached to the shared object visual through the
  existing visual-set/clip reference model;
- missing or invalid optional animation falls back to the static image instead
  of hiding the object.

The first pass uses adapters rather than forcing one content migration:

- object idle clips adapt the existing visual-set frame-clip document used by
  Character Studio;
- resource hit effects continue to use the layered animation document used by
  Weapon Studio and effects;
- both adapters plug into one shared timeline/source-picker/playback surface.

This preserves existing runtime content while allowing the editor surface to be
shared and extended later.

Resource nodes may declare an optional material-oriented `hitEffectId`. Object
Studio authors the referenced reusable one-shot package under
`content/effects/`; the resource definition stores only the stable effect ID.
The package may use a default animation or directional variants resolved by the
existing effect normalizer. The current tree and stone effects should be
migrated to material-oriented IDs (for example `wood-impact` and `stone-impact`).
A zero-damage hit never spawns the effect.

## Editor experience

Object Studio is a top-level `?studio=objects` editor route and accepts a
return-editor query plus an object/visual selection. Its first version contains:

1. Base visual/frame selection and preview.
2. Optional idle animation authoring.
3. Optional resource hit-effect authoring.
4. The shared source picker, timeline, frame holds, layer transforms, playback,
   validation, and save behavior used by Weapon/Character Studio.

Map Studio adds an **Edit object** link for the selected shared template and
previews authored idle animations. The link returns to the same map and keeps
the selected object/visual context. It does not create per-instance animation
overrides.

## Runtime data flow

1. `ObjectFactory` creates the stable object anchor and collider from the base
   visual.
2. It validates an optional idle visual set/clip and creates the animated layer
   transactionally. The base image is hidden only after successful setup; any
   missing optional animation asset, clip, registration, or playback error
   leaves the required static image visible. A missing required base asset is a
   content validation error, not an animation fallback case.
3. Reapplying a visual or replacing a resource disposes any existing
   `AnimatedVisual` before binding the new visual, preventing stale animation
   sprites from surviving a replacement.
4. Combat resolves the weapon's numeric damage modifier first.
5. The resource damage result snapshots the node's `hitEffectId` before applying
   damage and returns that metadata atomically with the accepted damage, so a
   final hit can remove the node record without losing its feedback. The
   world-effect pool plays the returned package only for positive damage.
6. Enemy hit effects continue to use the weapon's `onHitEffectId` path.

## Implementation plan

1. Extract the common animation editor surface and the visual-clip/layered
   document adapters from the existing Weapon/Character Studio components
   without changing their current behavior.
2. Add Object Studio route/query handling, object-template loading, optional
   idle package editing, resource-effect editing, and shared save/validation
   endpoints. The Object Studio save endpoint must atomically validate every
   `resourceNode.hitEffectId` against the effect catalog before writing.
3. Add `resourceNode.hitEffectId` to the object catalog/schema/checker and
   validate that referenced effect IDs exist.
4. Migrate the wood and stone effects away from weapon-owned
   `onResourceHitEffectId`; update weapon types, schema, normalization,
   migration helpers, UI, virtual content imports, and the effect IDs/packages.
5. Add a resource-owned hit-effect snapshot to the damage result and use it in
   `CombatController` after positive damage is accepted, before any depleted
   node record is removed.
6. Teach `ObjectFactory` and Map Studio preview to register visual-set
   animations, enable them in object/cursor/template previews, and retain the
   transactional static-image fallback described above.
7. Add Map Studio navigation to Object Studio for the selected shared template;
   preserve the return map plus selected object/visual query through tab
   switches and when reopening Object Studio.
8. Update content checks and focused tests for shared instances, fallback
   rendering, replacement cleanup, positive-damage effects, directional effect
   resolution, and zero-damage silence.

## Validation and acceptance

- A new object with no idle clip renders its static image in runtime and Map
  Studio.
- An object with a broken optional idle reference still renders its required
  static image and does not leave an orphaned animated sprite after visual
  replacement; a missing required base asset is reported as invalid content.
- Adding one idle clip in Object Studio updates every placed instance after a
  reload.
- A resource's hit effect is visible in Object Studio and plays for any tool
  that deals positive damage to that resource.
- A tool with a zero modifier does not damage the resource or spawn feedback.
- Weapon Studio still edits enemy hit effects without exposing resource-owned
  effects.
- Map Studio keeps geometry editing and returns to the same map/object selection
  after opening Object Studio.
- Object Studio refuses to save a resource effect reference that is absent from
  the effect catalog, without partially writing the object definition.
- `objects:check`, `effects:check`, `maps:check`, TypeScript, build, and focused
  editor/runtime tests pass.
