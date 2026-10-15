extends Resource
## A world's elevation baked (docs/godot/ELEVATION.md "Baked cache"): what Elevation builds from the
## painted layers that takes time and changes only when they do: the drawing (every group's meshes,
## by the key their material is made from), the depth map's mesh, the sides look's shapes and each
## level's collision outline. Elevation saves one per world scene
## (`res://game/scenes/worlds/elevation_cache/`, `Elevation.cache_path`) and, when its `key` still
## matches the painting, loads it instead of building them. Materials are not stored: they are made
## at load from the keys (they hold textures and the live depth map).
##
## Owner: world (elevation).

## The painting it was baked from (`Elevation._cache_key`): layers, metadata, settings, version.
@export var key := ""
## The build scripts' sources it was baked with (`Elevation._code_hash`), checked in debug runs.
@export var code := ""
## The drawing, bottom to top: [group name, [[key, ArrayMesh], ...]] per group.
@export var groups: Array = []
## The depth map's mesh (elevation_occlusion.gd) and its rect, Elevation space.
@export var depth_vertices := PackedVector2Array()
@export var depth_colors := PackedColorArray()
@export var depth_rect := Rect2()
## The sides look's shapes for walking (ElevationSides.shapes, without their tracing edges).
@export var side_shapes: Array = []
## Each level's collision: level -> segments (PackedVector2Array, Elevation space).
@export var collision: Dictionary = {}
