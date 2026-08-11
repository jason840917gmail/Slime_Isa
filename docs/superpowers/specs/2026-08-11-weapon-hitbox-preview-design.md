# Weapon Hitbox Preview Design

**Date:** 2026-08-11  
**Status:** Approved for implementation planning

## Summary

Weapon Studio must make the currently selected weapon attack's hitboxes obvious
in the combined preview. The preview uses the weapon's existing authored
geometry and attack-track windows. It does not introduce hitbox animation,
change combat behavior, or change the weapon document format.

The hitbox is owned by the weapon, not by the character. Each weapon can define
different named hitboxes, and each attack direction can override its geometry
and activation track. "Player-relative" describes only the coordinate origin:
the weapon hitbox is placed relative to the player anchor during the attack.

## Current Problem

Weapon Studio already emits hitbox guide elements, but the overlay is easy to
miss and does not communicate activation state strongly enough. Sector hitboxes
are represented as full circles instead of their authored wedge. The attack
event panel also does not put the currently selected direction in its heading,
which makes the ownership of the displayed windows unclear.

The runtime currently activates a static, player-relative weapon hitbox for an
authored timeline window. Per-keyframe weapon artwork transforms do not move or
rotate that hitbox. This project preserves that behavior and makes the editor
preview accurately explain it.

## Goals

- Always show every named hitbox owned by the selected weapon attack direction
  in the combined preview.
- Make inactive and active hitboxes visually distinct.
- Redraw geometry immediately when existing size, shape, or offset fields change.
- Make the attack-track heading identify the selected attack direction.
- Render rectangle, circle, ellipse, and sector guides in a way that matches the
  current runtime geometry.
- Preserve weapon ownership, directional inheritance, saved documents, and
  gameplay behavior.

## Non-goals

- Attaching hitboxes to per-keyframe weapon artwork transforms.
- Adding per-frame hitbox transforms or another animation track.
- Adding new drag or resize controls to the preview.
- Changing collision calculations, damage, knockback, hit suppression, or
  activation timing.
- Migrating or rewriting weapon JSON.
- Changing Character Studio hitbox authoring.

## Ownership and Direction Resolution

The preview resolves hitbox data from the normalized form of the currently
selected weapon. It must use the same normalization boundary as combat rather
than reconstructing directional fallback rules inside the renderer. `RIGHT`,
`UP`, and `DOWN` may each own independent hitbox geometry and attack tracks.
Legacy `side` feeds resolved Right. A mirrored `LEFT` resolves through Right. A
materialized Custom Left owns each value it explicitly authors, while omitted
Left geometry or track values still inherit their resolved Right counterparts.

Switching weapons must replace the displayed geometry and windows with those of
the newly selected weapon. No preview state may leak between weapon documents.

Root weapon hitboxes and attack tracks remain compatibility fallbacks according
to `normalizeWeaponDefinition()`. The normalized directional attack is the
single preview input, including root, legacy `side`, mirrored Left, and partial
Custom Left inheritance.

## Preview Behavior

While `ATTACK` is selected, the combined preview always draws every named hitbox
from the normalized selected direction, even when it is not active at the
current timeline frame:

- inactive hitboxes use a high-contrast cyan outline, a light translucent fill,
  and a readable hitbox ID;
- active hitboxes use a red outline, stronger translucent fill, and glow;
- overlays remain above both the character and weapon artwork;
- overlays do not intercept pointer input intended for weapon transform tools.

The current preview timeline frame, not merely the selected animation tile,
determines activation. Scrubbing or playback checks whether that exact frame is
inside an inclusive `from`/`through` span and updates the overlay state without a
full-page navigation or scroll reset.

`IDLE` and `IMPACT` do not have weapon attack tracks, so their combined previews
do not draw attack hitbox guides. Returning to `ATTACK` restores the selected
direction's guides and active state.

Existing Inspector fields remain the only geometry authoring controls. Changing
shape, size, radius, arc width, or offsets re-renders the preview immediately.
No extra preview handles are added.

## Geometry and Coordinates

Hitbox guides remain static relative to the player anchor and do not inherit the
weapon tile's occurrence offset, scale, or rotation. The preview displays the
same authored geometry used at runtime. Player progression does not scale weapon
reach or arc width.

The preview uses the same directional coordinate convention as runtime:

- `RIGHT`: `(offsetX, offsetY)`;
- `LEFT`: `(-offsetX, offsetY)`;
- `UP`: `(offsetY, -offsetX)`;
- `DOWN`: `(-offsetY, offsetX)`.

Rectangle guides remain axis-aligned because current runtime rectangle collision
is axis-aligned and use authored `width` and `height`. Circle and ellipse guides
use the same radius precedence as combat independently on each axis:
`radiusX ?? radius ?? width / 2` and
`radiusY ?? radius ?? height / 2`. This preserves even unusual legacy circle
documents whose two resolved radii differ.

Sector guides originate at the player anchor. Their cardinal facing angle is
derived from direction: Right `0`, Left `π`, Up `-π/2`, and Down `π/2`. The inner
radius defaults to `0`; the outer radius uses `outerRadius` and retains the legacy
fallback `offsetX + width / 2` only for malformed pre-validation input. Arc width
uses authored `arcWidthRad`, which is required for newly validated sector
hitboxes. Pre-authored documents missing that property normalize to the legacy
`0.8`-radian value. The Studio's existing world-unit-to-preview scale remains the
source of display dimensions.

SVG sector paths clamp finite arc widths to `[0, 2π]`. A full-circle sector is
drawn with two arc segments. A zero-width sector renders its two radial boundary
lines without a filled area. Non-finite values, a non-positive outer radius, or
an inner radius greater than or equal to the outer radius produce no shape for
that draft render; the hitbox ID remains visible with an invalid-geometry state
so the user is not shown a plausible but incorrect collision area.

Draft values are passed through the editor's existing numeric normalization.
Normal weapon validation remains authoritative for saving; preview guards only
prevent malformed in-progress values from emitting invalid CSS or SVG.

## Attack Track Heading

The panel heading identifies its scope as `ATTACK / RIGHT`, `ATTACK / LEFT`,
`ATTACK / UP`, or `ATTACK / DOWN`, followed by `Hitbox activation windows`.
Mirrored Left also retains its existing locked/mirrored explanation and disabled
editing behavior.

Each cell still represents one animation timeline frame. Clicking a cell toggles
that weapon hitbox for the exact frame, and adjacent active cells continue to be
stored as inclusive spans. Event behavior is unchanged.

For an authored attack track, overlay activation comes only from that normalized
track. For a legacy weapon with no attack track, the preview preserves the
Studio's existing synthetic authoring track: the first resolved hitbox is shown
active across the attack timeline and all other named hitboxes are inactive.
This is explicitly an editor compatibility preview, not a simulation of the
legacy runtime timer, which activates only `primary` for
`max(hitboxDurationMs, 200)` milliseconds. Editing the synthetic cells continues
to materialize an authored directional track through the existing save flow.

## Components and Data Flow

`WeaponStudio` continues to own selection and draft editing. A focused resolver
accepts the current weapon draft and direction and returns the normalized
directional attack plus whether its track is authored or synthetic. The preview
renderer consumes only this resolved result, its normalized timeline, and the
current timeline frame. A focused hitbox-guide rendering helper converts each
resolved shape into preview markup. Rectangles, circles, and ellipses may use
styled DOM elements; sectors use SVG path geometry so their arc is represented
accurately.

Initial render computes both geometry and active state. The existing lightweight
preview playback update only toggles active/inactive presentation for the current
timeline frame. Inspector changes that affect hitboxes continue through the
existing draft mutation and render path, producing fresh geometry immediately.

This work does not add a new persistence owner, shared animation state, or runtime
adapter. It consumes the existing weapon and timeline sources of truth.

## Error Handling and Compatibility

- Missing directional overrides resolve through `normalizeWeaponDefinition()`;
  partial Custom Left values inherit resolved Right values exactly as combat does.
- Mirrored Left never creates an implicit custom override while previewing.
- Missing attack tracks preserve the explicitly documented synthetic Studio
  presentation and never claim to simulate the legacy millisecond timer.
- Missing or invalid optional geometry does not crash the editor; save validation
  remains responsible for actionable errors.
- Hitbox overlays remain non-interactive and cannot interfere with artwork move,
  scale, or rotate tools.
- Idle and Impact never retain stale attack overlays after tab changes.

## Verification

Automated checks must cover:

- different weapons resolving different hitbox geometry;
- root and legacy `side` fallback through the normalized directional package;
- each attack direction resolving its own geometry and activation track;
- mirrored Left matching resolved Right, including partial Custom Left fallback;
- timeline-frame activation using inclusive span boundaries;
- inactive and active overlay presentation;
- attack overlays being absent for Idle and Impact;
- immediate geometry updates after Inspector mutations;
- rectangle, circle, and ellipse runtime radius precedence;
- sector direction angles, legacy arc fallback, zero/full arc handling, and
  invalid draft guards;
- synthetic no-track presentation remaining distinct from authored-track timing;
- scoped `ATTACK / DIRECTION` panel headings;
- no weapon document or runtime collision changes caused by preview rendering.

Live browser verification must scrub and play at least one directional attack,
edit hitbox size and offsets, switch weapons and directions, and confirm that the
overlay stays visible, changes color at authored windows, preserves scroll, and
produces no console errors.

## Acceptance Criteria

The feature is complete when a user can select any weapon attack direction and
immediately see that direction's weapon-owned hitbox in the combined preview,
understand whether it is active at the current time, and observe existing
Inspector edits without guessing. Gameplay collision and saved weapon data must
remain unchanged.
