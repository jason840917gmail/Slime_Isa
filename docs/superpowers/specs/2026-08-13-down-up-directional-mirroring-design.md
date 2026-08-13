# DOWN-to-UP Directional Mirroring Design

## Summary

Weapon attacks and confirmed-hit effects will support two directional inheritance
pairs:

- RIGHT is the master for optional LEFT.
- DOWN is the master for optional UP.

An omitted child direction is not copied. It is resolved from its master at load
and preview time, so later edits to the master are immediately reflected. LEFT is
a horizontal reflection of RIGHT. UP is a true vertical reflection of DOWN, not a
180-degree rotation. Either inherited direction may be converted into a complete
custom package in Weapon Studio and later restored to inheritance.

The implementation must use one shared directional-inheritance resolver and the
existing shared layered-animation transform pipeline. Weapon and effect adapters
may supply domain-specific fallback policy, but they must not duplicate direction
selection or mirror-axis calculations.

## Goals

- Make DOWN the master vertical attack/effect direction.
- Let UP inherit DOWN's complete authored package by default.
- Reflect all layered artwork and placement across the horizontal axis.
- Preserve correct UP hitbox direction and offsets while inheriting DOWN geometry.
- Support the same mirror/custom workflow for weapon attacks and on-hit effects.
- Keep current RIGHT-to-LEFT behavior unchanged.
- Keep existing authored UP packages custom and visually unchanged.
- Prevent Studio preview and runtime mirroring from drifting apart.

## Non-Goals

- Mirroring character or enemy animation libraries in this delivery.
- Adding diagonal directions.
- Rotating DOWN artwork by 180 degrees to synthesize UP.
- Copying inherited data into saved child directions.
- Changing attack timing, damage, hitbox activation, or confirmed-hit placement.
- Automatically deleting existing authored UP data during migration.

## Directional Inheritance Model

Create a domain-neutral resolver with a result equivalent to:

```ts
interface ResolvedDirectionalVariant<T, TDirection extends string> {
  readonly value: T;
  readonly requestedDirection: TDirection;
  readonly sourceDirection: TDirection | 'default';
  readonly authored: boolean;
  readonly mirrorX: boolean;
  readonly mirrorY: boolean;
}
```

The resolver accepts exact variants plus an explicit inheritance policy. It
resolves in this order:

1. Exact authored direction.
2. LEFT from RIGHT when that inheritance pair is enabled.
3. UP from DOWN when that inheritance pair is enabled.
4. Domain-provided Default fallback, used only by effects.
5. Unresolved.

The master must exist for an active mirror rule to resolve. A mirror flag is
active only when its exact child is absent. Default effect artwork is not silently
mirrored as if it were a missing master. An exact child always wins and makes the
corresponding mirror flag dormant.

The shared result owns source and mirror-axis metadata. Weapon and effect
normalizers convert only the resolved value into their domain's normalized
animation package.

Resolution is deterministic for each child direction:

| Exact child | Mirror enabled | Master exists | Default exists | Result |
|---|---:|---:|---:|---|
| yes | either | either | either | exact child, no host mirror |
| no | yes | yes | either | master with the pair's host mirror axis |
| no | no | either | yes | Default, no host mirror |
| no | yes | no | yes | resolver returns Default, but persisted effect validation rejects the active contradictory mirror configuration |
| no | either | no | no | unresolved and invalid |

Weapons do not have Default and always enable both mirror pairs, so their required
RIGHT/DOWN masters guarantee resolution. Effects use authored mirror flags. An
effect with a disabled UP mirror, no exact UP, and a Default resolves Default. An
effect with `mirrorUpFromDown: true`, no exact UP, and no DOWN is invalid even if
Default could render, because the saved document explicitly requests an
impossible active inheritance relationship. When exact UP exists, the flag is
dormant and missing DOWN does not invalidate that exact child. If exact UP is
later removed, validation requires DOWN or a disabled mirror flag.

## Shared Layered Transform

Extend `LayeredAnimationHostTransform` with `mirrorY`. Both mirror axes are applied
by `composeAnimationVisualTransform`, the same pure function used by Phaser
runtime adapters and testable preview calculations.

For vertical reflection:

- X offsets remain unchanged.
- The sum of layer and block Y offsets is negated.
- Host `mirrorY` participates in XOR composition with layer/block `flipY`.
- Local rotation is negated when exactly one host mirror axis is active.
- Local rotation is preserved when neither or both host mirror axes are active.
- Scale magnitudes, origin, relative depth, timeline frames, and source frames are
  preserved.

Let the authored composition offset be `p = layer.offset + block.offset`, the host
reflection be `H = diag(mirrorX ? -1 : 1, mirrorY ? -1 : 1)`, and host rotation be
`R`. Final position is `anchor + R * H * p`. Layer and block rotation values are
summed before host reflection. Their sign is negated when `mirrorX XOR mirrorY` is
true and preserved otherwise. Host rotation is applied last. The rendered flip
flags are `hostMirrorX XOR layer.flipX XOR block.flipX` and the equivalent Y
expression.

Origin remains the authored normalized sprite pivot. Phaser and Studio reflection
both flip pixels around that unchanged pivot; mirroring the composed offset moves
the pivot to its reflected composition position. This is the required true
reflection even for asymmetric origins. Tests use non-centered origins plus
independent layer and block offsets so an implementation that flips pixels but
fails to reflect placement cannot pass.

Horizontal reflection retains its current behavior. Combined X/Y mirroring is
defined and tested even though no current direction pair requests both axes.

## Weapon Contract and Normalization

Version 2 weapon documents require authored RIGHT and DOWN attack packages. LEFT
and UP are optional custom overrides.

Weapon normalization uses the shared resolver with both fixed inheritance pairs
enabled. The normalized presentation result distinguishes exact authored attacks,
horizontal RIGHT mirrors, and vertical DOWN mirrors. This may be represented by
the existing presentation union extended with `mirror-down`, or by normalized
mirror-axis fields, provided runtime consumers receive source, authored state,
`mirrorX`, and `mirrorY` from one resolver result.

When UP is absent, its normalized package reuses all DOWN-owned data:

- layered animation and transparent gaps;
- layer and block transforms;
- frames per second and duration;
- character action ID;
- attack track, events, and hitbox activation spans;
- named hitbox definitions and combat multipliers.

The combat runtime still evaluates that inherited hitbox package using requested
direction UP. Existing directional hitbox math therefore maps forward/side
offsets into UP coordinates and aims sectors upward. The hitbox document itself is
not vertically flipped or copied.

For authored hitbox offsets `(forward, side) = (offsetX, offsetY)`, preview and
runtime must use these exact centers:

- RIGHT: `(offsetX, offsetY)`
- LEFT: `(-offsetX, offsetY)`
- UP: `(offsetY, -offsetX)`
- DOWN: `(-offsetY, offsetX)`

An inherited UP therefore uses DOWN's unchanged hitbox document but resolves its
center as `(offsetY, -offsetX)`. Sector direction is `-Math.PI / 2` for UP and
`Math.PI / 2` for DOWN. Rectangle dimensions, ellipse/circle radii, sector radii/arc width, damage
multipliers, and activation spans remain unchanged. Studio preview must call the
same geometry resolver and match runtime coordinates exactly.

Validation requires RIGHT and DOWN, permits missing LEFT/UP, and validates a child
only when it is authored. Legacy migration continues generating explicit UP when
the legacy source has distinct UP data. Loading or normalizing never mutates disk.

## Effect Contract and Normalization

Effect documents add `mirrorUpFromDown?: boolean`, parallel to the existing
`mirrorLeftFromRight?: boolean`.

Effect resolution uses the same shared resolver:

- an exact UP variant remains custom;
- when exact UP is absent and `mirrorUpFromDown` is true, DOWN is reflected
  vertically;
- when mirroring cannot resolve, the existing Default fallback remains available
  without reflection.

`NormalizedEffectVariant` exposes mirror axes rather than an ambiguous single
`mirrored` flag. `WorldEffectAdapter` and `WorldEffectPool` pass both axes to the
shared layered renderer.

Validation checks the new flag type, validates its DOWN dependency when the flag
is active, and still requires all four normalized directions to resolve. Existing
effects without the new flag retain their current behavior. New effects created
by Weapon Studio enable both mirror pairs and omit duplicate LEFT/UP variants.

Validation resolves RIGHT, LEFT, UP, and DOWN independently through the table
above. One Default variant may satisfy any number of directions that have neither
an exact variant nor an enabled, usable mirror master. The entire effect document
is invalid if any one requested direction remains unresolved. It is also invalid
when an active mirror flag names a missing master, even if Default would otherwise
satisfy that child, because the authored inheritance declaration is contradictory.
An enabled flag is dormant when its exact child exists, so exact-child precedence
and validation use the same rule.

## Weapon Studio Behavior

Direction controls show two master/child groups:

- `SIDE - RIGHT master + LEFT mirror/custom`
- `VERTICAL - DOWN master + UP mirror/custom`

Direction status is explicit:

- RIGHT and DOWN: `MASTER`
- inherited LEFT: `MIRROR RIGHT`
- inherited UP: `MIRROR DOWN`
- exact children: `CUSTOM`

Selecting an inherited child previews the requested direction using the shared
resolver and mirror axes. The complete timeline, hitboxes, event track, character
action, and layered composition are visible, but authoring controls are locked.

The mode card uses pair-neutral behavior and labels:

- `MAKE CUSTOM LEFT` clones the complete resolved RIGHT package into LEFT.
- `RESTORE RIGHT MIRROR` removes authored LEFT.
- `MAKE CUSTOM UP` clones the complete resolved DOWN package into UP.
- `RESTORE DOWN MIRROR` removes authored UP.

Creating a custom child is one atomic document mutation. It deep-clones animation,
transforms, action, hitboxes, and tracks so later edits are independent. Restoring
inheritance removes only the child package and selects the resolved inherited
preview. Save remains explicit.

Custom conversion must preserve the currently visible inherited composition. It
does not merely copy raw DOWN artwork and then remove host mirroring. A shared
materialization helper deep-clones the master and bakes the selected reflection
into visual animation data:

- negate the mirrored axis in every layer offset and every block offset;
- negate every layer and block rotation when exactly one mirror axis is active;
- toggle the corresponding flip flag once per visual layer, leaving block flip
  flags otherwise intact;
- preserve origin, scale magnitude, depth, timing, source frames, and gaps.

Gameplay data is copied without baking: character action, hitbox documents,
activation spans, events, and multipliers continue to resolve using requested
child direction. The new exact child then has `mirrorX: false` and `mirrorY: false`
and initially renders/contacts identically to the inherited preview. Later master
edits cannot affect it. The same materializer also replaces the existing raw-copy
behavior for MAKE CUSTOM LEFT so horizontal custom conversion gains parity.

The same pair-neutral mode UI and mutation helpers apply when editing the assigned
on-hit effect. Effect restoration also enables the relevant mirror flag; custom
creation adds the exact child variant, which takes precedence over that flag.

The layered Studio's manual CSS preview must consume the same resolved mirror-axis
metadata as runtime. It must not independently infer `direction === 'left'` or
`direction === 'up'` in scattered render functions.

## Compatibility and Migration

- Existing authored UP weapon attacks remain authored custom packages.
- Existing authored UP effect variants remain exact custom variants.
- Existing effects without `mirrorUpFromDown` keep current Default behavior.
- RIGHT-to-LEFT normalization, preview, runtime, and save semantics remain stable.
- New weapon drafts author RIGHT and DOWN only unless the user creates custom
  children.
- New effect drafts author RIGHT and DOWN, enable both mirror flags, and omit LEFT
  and UP.
- No content file is rewritten merely by opening Studio.

Legacy weapon migration remains explicit and lossless:

| Legacy input | Version 2 migration output |
|---|---|
| explicit DOWN and UP | explicit DOWN and custom UP |
| explicit DOWN, missing UP | explicit DOWN and explicit UP generated from the legacy root attack fallback, preserving current migration output |
| missing DOWN, explicit or missing UP | explicit DOWN generated from the legacy root attack fallback; explicit UP preserves its source or uses the same fallback |
| v2 missing DOWN | no migration; validation error |

Migration does not infer and delete a vertical child. Authors opt into inheritance
by using RESTORE DOWN MIRROR in Studio after reviewing the preview.

For each vertical legacy direction, precedence is exact directional package first,
then the legacy root Attack package. Thus explicit UP always wins over root
fallback, and explicit DOWN always wins over root fallback. A legacy DOWN-only
document is supported: migration preserves its explicit DOWN and emits explicit UP
from the root Attack fallback. A legacy explicit-UP/missing-DOWN document preserves
UP and emits DOWN from the root fallback. If the legacy root Attack package itself
is absent, the existing migration default Attack package supplies the fallback.
Every migration case writes valid explicit RIGHT, DOWN, and UP packages; it never
marks generated UP as inherited automatically.

## Error Handling

- A missing required master direction is a validation error with its exact path.
- An active mirror flag without its master is a validation error; Default does not
  satisfy the master requirement. A flag is dormant while its exact child exists.
- An effect with no exact child and a disabled mirror may resolve unmirrored
  Default. Without Default it is unresolved and invalid.
- An inherited child cannot be edited. Studio explains which master owns it and
  offers the custom conversion action.
- Custom conversion fails atomically if the master cannot resolve.
- Restore actions never alter the master package.
- Runtime normalization fails before playback if a required weapon/effect
  direction cannot resolve.

## Testing

Shared-animation tests cover exact selection, both inheritance pairs, Default
fallback order, vertical offset reflection, `flipY` XOR behavior, rotation under
one and two mirror axes, and unchanged horizontal mirroring.

Weapon tests cover required RIGHT/DOWN validation, optional LEFT/UP, normalized
`mirror-down`, exact UP precedence, inherited action/timing/tracks/hitboxes, UP
hitbox direction, legacy compatibility, and no input mutation.

Effect tests cover `mirrorUpFromDown`, exact UP precedence, unmirrored Default
fallback for every flag/master combination, missing-DOWN validation, and runtime
adapter mirror axes.

Studio tests cover master/custom labels, locked inherited controls, complete
custom materialization followed by later master edits, restoration, effect parity,
preview mirror metadata, and saved JSON omitting inherited children.

Migration fixtures cover legacy root-only, RIGHT-only, DOWN-only, explicit UP,
and all-direction packages. Transform fixtures use nested layer/block offsets,
rotations, flips, and asymmetric origins. Hitbox fixtures compare exact Studio and
runtime centers/sector angles for all four requested directions.

Final verification runs shared animation, Weapon Studio, combat, content checks,
typecheck, and production build.

## Acceptance Criteria

- A weapon with DOWN but no UP plays a vertically reflected DOWN composition when
  attacking upward.
- Its inherited hitboxes activate on the same timeline and point upward.
- A confirmed-hit effect with DOWN, no UP, and `mirrorUpFromDown: true` reflects at
  the enemy contact point when the attack direction is UP.
- Studio clearly shows DOWN as master and UP as inherited or custom.
- Custom UP can be created, edited independently, saved, and restored to DOWN.
- Editing DOWN immediately changes inherited UP without duplicating JSON.
- Existing custom UP and current LEFT mirroring do not regress.
