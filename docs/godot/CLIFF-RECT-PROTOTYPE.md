# Rectangular cliff art prototype

Independent visual experiment, 2026-10-09. Existing cliff systems and scenes are untouched.

## Try it

Open `res://game/scenes/worlds/cliff-rect-prototype.tscn` and press F6.
It runs directly; it is intentionally not registered as a game world in the scene index.

- Mouse wheel: zoom at the pointer. Right-drag or WASD: pan. Home: overview.
- 1: height comparison. 2: terrace. 3: editable rectangle.
- Up/down: editable rectangle's wall height (1–8 cells).
- Left/right: width (4–32 cells).
- Shift + up/down: grass depth (2–24 cells).

The lab contains equal-size grass tops with one-, two-, and four-cell walls, a nested
three-level terrace, and one adjustable rectangle. Elder Plop's first sprite frame is shown
at the scale used in his own scene; this is a static visual reference, not a playable character.

## Use the sprite

Instance `res://game/world/cliffs/rect_prototype/rect_cliff.tscn` in a new scene.
Inspector properties: `width_cells`, `depth_cells`, `wall_levels`; one cell is 64 world units.
It renders in the editor as well as at runtime. The node's origin is its top-left corner.

Master sprite: `godot/asset/MAPS/cliffs/rect-prototype/plateau-master.png` (1536 × 1024,
transparent). Source copy and generation prompt:
`asset/Originals/elevation/cliff-rect-prototype/`.

The shader measures regions from this specific sprite. It preserves the left/right caps,
north rim, front turf lip and wall foot, and maps grass depth independently from wall height.
Long grass interiors use an odd number of reflected runs, with both endpoint connections
preserved. Rock middles stretch vertically; the central width stretches horizontally.
There is no crossfade between unrelated painted cells.

## What this proves, and its limits

This explores a less crowded turf edge and natural rock outcrop art, variable rectangular
dimensions, and nested terraces from one consistent painting. It is not a finished modular
tileset. Wider faces stretch rock features; taller walls elongate them; reflected grass may
show symmetry. Minimum-height walls compress most of the rock body. Additional authored
rock modules and matching connectors would be needed to keep feature scale at extreme sizes.

Separate rectangles can nest. Touching rectangles do not merge outlines: L/T shapes and
inner corners are not supported. No collision, stairs, walking behind, height-aware movement,
world registration, low-ground shade integration or gameplay changes are included.

## Validation

Both scripts passed the MCP editor's parse validation. The lab was launched and its rendered
output inspected. Runtime key events changed width 10→11, height 3→4 and depth 5→6, then the
defaults were restored. Screenshot: `cliff-rect-prototype-preview.png`.
No integration suite, scene verifier, web export or headless import was run.

The editor reported a startup Compatibility renderer error,
`texture_set_size_override: Parameter "texture" is null`, without a script source.
The game subsequently became live and rendered correctly; the error is unresolved.
