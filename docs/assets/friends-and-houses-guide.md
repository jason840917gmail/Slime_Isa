# Friends And Houses Guide

This guide covers NPC part sizes, house sizes, and props tied to buildings and interaction zones.

## Friend Asset Rules

Current friend system structure:

- Face texture size: `24 x 24 px`
- Ear accessory size: `24 x 24 px`
- Default runtime scale: `1`
- Physics body size: `28 x 28`

Important assumptions:

- All interchangeable friend parts share the same center origin.
- Ear overlays are positioned above the face using the same visual center.
- Runtime tinting is applied to faces and ears.

If you add more parts:

- Keep all variants on the same canvas size.
- Leave transparent margin so accessories do not clip.
- Prefer neutral base colors if the asset should accept runtime tinting.

## Friend Template

- Face: `24 x 24 px`
- Ears or head accessory: `24 x 24 px`
- Shared center alignment for all layers

## House Asset Rules

Current house and prop measurements:

- House texture: `128 x 128 px`
- Bed texture: `48 x 20 px`
- Door interaction zone: `28 x 18 px`

Important assumptions:

- Houses are placed as centered static images.
- The door interaction zone is derived from the displayed house height.
- The entrance should sit near the bottom-center of the art.
- Beds and similar props are positioned relative to the displayed house size.

## House Authoring Tips

- Keep the main silhouette inside the `128 x 128` canvas.
- Put the doorway near the bottom-center.
- Compare the house against a `64 x 64` tile grid before exporting.
- Leave enough empty room for roof shapes without moving the entrance too high.

## Prop Tips For Buildings

- Keep interior or nearby props visually compatible with the house scale.
- Use separate small textures for beds, signs, crates, and similar items.
- A bed-sized prop around `48 x 20 px` is currently safe.

## Safe Template

- House: `128 x 128 px`
- Door near bottom-center
- Bed or small interaction prop: around `48 x 20 px`