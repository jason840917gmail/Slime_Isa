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

The preview resolves hitbox data from the currently selected weapon and attack
direction. `RIGHT`, `UP`, and `DOWN` may each own independent hitbox geometry and
attack tracks. A mirrored `LEFT` resolves through `RIGHT`; a materialized Custom
Left owns independent geometry and windows.

Switching weapons must replace the displayed geometry and windows with those of
the newly selected weapon. No preview state may leak between weapon documents.

Global weapon hitboxes and attack tracks remain compatibility fallbacks when a
direction does not author an override. A legacy weapon without an authored track
continues to preview its hitbox as active, matching its immediate-hit fallback.

## Preview Behavior

The combined preview always draws named weapon hitboxes, even when they are not
active at the current timeline frame:

- inactive hitboxes use a high-contrast cyan outline, a light translucent fill,
  and a readable hitbox ID;
- active hitboxes use a red outline, stronger translucent fill, and glow;
- overlays remain above both the character and weapon artwork;
- overlays do not intercept pointer input intended for weapon transform tools.

The current preview timeline frame, not merely the selected animation tile,
determines activation. Scrubbing or playback checks whether that exact frame is
inside an inclusive `from`/`through` span and updates the overlay state without a
full-page navigation or scroll reset.

Existing Inspector fields remain the only geometry authoring controls. Changing
shape, size, radius, arc width, or offsets re-renders the preview immediately.
No extra preview handles are added.

## Geometry and Coordinates

Hitbox guides remain static relative to the player anchor and do not inherit the
weapon tile's occurrence offset, scale, or rotation.

The preview uses the same directional coordinate convention as runtime:

- `RIGHT`: `(offsetX, offsetY)`;
- `LEFT`: `(-offsetX, offsetY)`;
- `UP`: `(offsetY, -offsetX)`;
- `DOWN`: `(-offsetY, offsetX)`.

Rectangle guides remain axis-aligned because current runtime rectangle collision
is axis-aligned. Circle and ellipse guides use the authored radii or dimensions.
Sector guides originate at the player anchor and render the authored inner
radius, outer radius, facing angle, and arc width as an actual wedge. The Studio's
existing world-unit-to-preview scale remains the source of display dimensions.

Draft values are passed through the editor's existing numeric normalization.
If an in-progress value cannot produce finite positive display dimensions, the
guide is omitted for that render instead of emitting invalid CSS or breaking the
preview; normal weapon validation remains authoritative for saving.

## Attack Track Heading

The panel heading identifies its scope as `ATTACK / RIGHT`, `ATTACK / LEFT`,
`ATTACK / UP`, or `ATTACK / DOWN`, followed by `Hitbox activation windows`.
Mirrored Left also retains its existing locked/mirrored explanation and disabled
editing behavior.

Each cell still represents one animation timeline frame. Clicking a cell toggles
that weapon hitbox for the exact frame, and adjacent active cells continue to be
stored as inclusive spans. Event behavior is unchanged.

## Components and Data Flow

`WeaponStudio` continues to own selection and draft editing. Its preview renderer
resolves the selected directional attack, named hitboxes, normalized timeline,
and attack track. A focused hitbox-guide rendering helper converts each resolved
shape into preview markup. Rectangles, circles, and ellipses may use styled DOM
elements; sectors use SVG path geometry so their arc is represented accurately.

Initial render computes both geometry and active state. The existing lightweight
preview playback update only toggles active/inactive presentation for the current
timeline frame. Inspector changes that affect hitboxes continue through the
existing draft mutation and render path, producing fresh geometry immediately.

This work does not add a new persistence owner, shared animation state, or runtime
adapter. It consumes the existing weapon and timeline sources of truth.

## Error Handling and Compatibility

- Missing directional overrides resolve through the established weapon fallback.
- Mirrored Left never creates an implicit custom override while previewing.
- Missing attack tracks preserve legacy active-hitbox presentation.
- Missing or invalid optional geometry does not crash the editor; save validation
  remains responsible for actionable errors.
- Hitbox overlays remain non-interactive and cannot interfere with artwork move,
  scale, or rotate tools.

## Verification

Automated checks must cover:

- different weapons resolving different hitbox geometry;
- each attack direction resolving its own geometry and activation track;
- mirrored Left matching Right and Custom Left remaining independent;
- timeline-frame activation using inclusive span boundaries;
- inactive and active overlay presentation;
- immediate geometry updates after Inspector mutations;
- rectangle, circle, ellipse, and sector preview geometry;
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
