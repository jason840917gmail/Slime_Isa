# Cached terrain transitions

The approved investigation identified live geometry masks as the dominant cost
on transition-heavy maps. The user requested implementation globally, for every
map. Replace the shared TerrainTransitionRenderer used by MapBuilder and
MapEditorScene; do not add map-ID checks or change collision/content rules.

Build a deterministic transition command list using the existing material,
priority, seed, frame/flip, polygon, alpha, and global band ordering rules.
Partition commands into fixed-size world-space chunks. Bake each occupied chunk
once through Phaser's DynamicTexture path, which supports WebGL and Canvas.
Use a small gutter, render neighboring commands into it, and expose only the
interior texture frame to prevent linear-filter seams. Chunk bounds must work
for rectangular maps, partial edge chunks, arbitrary positive tile sizes, and
tiles crossing chunk boundaries. Empty/same-material maps allocate no chunks.

Only ordinary images survive baking: no live terrain masks or graphics, and no
transition images registered in physics. Cull these chunk images against each
camera's final world view while preserving Phaser visibility and camera filters.
Keep static terrain at its existing ground-decal depth; other entities retain
their depth and occlusion behavior. TileFactory continues to own texture/frame
selection and supplies detached visual copies for baking.

TerrainTransitionLayer owns images and generated texture keys. Cleanup must be
idempotent on explicit editor rebuild and scene shutdown, including cleanup on
partial bake failure. Allocate only occupied chunks, bounded individually to
512 pixels plus gutters, with retained texture bytes reported for verification.
This phase caches a loaded map's occupied chunks; streaming/LRU for worlds whose
occupied transition textures exceed the target device budget is a separate
extension, not a reason to reintroduce live masks.

Tests cover boundary rules against authored maps, global ordering, partitioning
and gutters, nonstandard dimensions, empty terrain, cleanup/error paths, and
camera culling. Browser checks cover Gloop Forest and Crystal Caverns at 1x and
0.5x, a same-material map, and Map Studio. Compare appearance and verify zero
live transition masks, texture counts, and FPS through development diagnostics.
Run pnpm check and the production build. Do not change unrelated gameplay.
