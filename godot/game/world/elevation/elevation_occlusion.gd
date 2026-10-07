@tool
extends Node
## The terrain's depth map and the bodies hidden behind higher ground (docs/godot/ELEVATION.md).
##
## Elevation hands `build` one mesh of the terrain (every top, wall and rim core of the elevated part
## of the world, then the flights of stairs) whose vertex colours encode depth (`encode`); it is drawn once into
## a SubViewport ("DepthMap", UNITS_PER_TEXEL world units per texel) whose texture the shaders read:
## the body shaders (elevation_occlusion.gdshaderinc, in hit_flash.gdshader and form_skin.gdshader)
## to hide what lies behind, the cast shadows (elevation_cast_shadow.gdshader) to find what is
## higher. `update_body` gives a body's sprites the map and, every physics step, the body's depth
## (its feet's y + 64 · its level, or its depth in the air); sprites without a material get the
## neutral hit-flash one. Hidden parts show as a ghost: the body's own colours, faded and tinted,
## stronger for the player.
##
## Owner: world (elevation).

const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")

## World units per texel of the depth map; coarser when the elevated part would need a texture
## side over MAX_TEXELS (many phones stop at 4096).
const UNITS_PER_TEXEL := 2.0
const MAX_TEXELS := 4096
const LEVEL_UNITS := 64.0
## Opacity of a body's hidden parts (its ghost): the player's, everyone else's.
const PLAYER_GHOST := 0.6
const OTHER_GHOST := 0.35
const PLAYER_LAYER := 2
const DEPTH_UNIFORM := &"elevation_body_depth"

## The depth map, its rect in the ground layer's space and in the world.
var texture: Texture2D
var local_rect := Rect2()
var world_rect := Rect2()

var _viewport: SubViewport
var _build_id := 0
## Shader -> whether it has the occlusion uniforms.
var _shader_has := {}
## body -> its sprites (CanvasItems), rescanned when a child enters it.
var _sprites := {}
var _dirty := {}


## A depth texel (elevation_occlusion.gdshaderinc): `level`, how far `dy` the point lies below its
## wall's top edge or past its rim (world units); `stairs`: a structure, whose height
## (level − dy / 64) the cast shadows read.
static func encode(level: int, dy: float, stairs: bool = false) -> Color:
	return Color((float(level) + 4.0) / 8.0, clampf((dy + 128.0) / 512.0, 0.0, 1.0), 0.5 if stairs else 1.0, 1.0)


## Draws `depth` (ground-layer space) into a new depth map covering `rect`; `origin` = the ground
## layer's global position.
func build(depth: MeshData, rect: Rect2, origin: Vector2) -> void:
	if _viewport != null:
		_viewport.free()
		_viewport = null
	texture = null
	if depth.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var units := UNITS_PER_TEXEL
	while maxf(rect.size.x, rect.size.y) / units > MAX_TEXELS:
		units *= 1.5
	_viewport = SubViewport.new()
	_viewport.name = "DepthMap"
	_viewport.size = Vector2i(ceili(rect.size.x / units), ceili(rect.size.y / units))
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)
	# Its canvas exists once it is in the tree.
	_viewport.canvas_transform = Transform2D(0.0, Vector2.ONE / units, 0.0, -rect.position / units)
	var mesh := MeshInstance2D.new()
	mesh.mesh = depth.to_mesh()
	_viewport.add_child(mesh)
	texture = _viewport.get_texture()
	local_rect = rect
	world_rect = Rect2(rect.position + origin, rect.size)
	_build_id += 1


## Draws `mesh` (ground-layer space, vertex colours as `encode`) over the terrain in the depth map,
## through `material` (which may discard where its art is see-through), and renders the map again:
## things standing on the terrain that hide what is behind them like it does (fences,
## fences/elevation_fences.gd). Call after `build`; the next `build` drops them.
func add_occluder(mesh: Mesh, material: Material) -> void:
	if _viewport == null:
		return
	var instance := MeshInstance2D.new()
	instance.mesh = mesh
	instance.material = material
	_viewport.add_child(instance)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The map's rect as a shader vec4 (origin, size).
func rect_uniform(rect: Rect2) -> Vector4:
	return Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)


## Feeds `body`'s sprites the depth map and the body's depth at `level` (`flight_depth` instead
## when it is a number: a body in the air).
func update_body(body: CharacterBody2D, level: int, flight_depth: float = NAN) -> void:
	if texture == null or body == null:
		return
	if not _sprites.has(body) or _dirty.has(body):
		_sprites[body] = _scan(body)
		_dirty.erase(body)
	var depth := flight_depth if not is_nan(flight_depth) else body.global_position.y + float(level) * LEVEL_UNITS
	var silhouette := PLAYER_GHOST if body.collision_layer & PLAYER_LAYER != 0 else OTHER_GHOST
	for sprite: CanvasItem in _sprites[body]:
		if not is_instance_valid(sprite):
			continue
		var material := sprite.material as ShaderMaterial
		if material == null or not _has_uniforms(material.shader):
			continue
		if int(material.get_meta(&"elevation_build", 0)) != _build_id:
			material.set_meta(&"elevation_build", _build_id)
			material.set_shader_parameter(&"elevation_depth", texture)
			material.set_shader_parameter(&"elevation_rect", rect_uniform(world_rect))
			material.set_shader_parameter(&"elevation_silhouette", silhouette)
		material.set_shader_parameter(DEPTH_UNIFORM, depth)


func forget(body: Node) -> void:
	_sprites.erase(body)
	_dirty.erase(body)


## The body's sprites; ones without a material get the hit-flash material (neutral until a hit).
func _scan(body: CharacterBody2D) -> Array:
	if not body.child_entered_tree.is_connected(_on_child_entered):
		body.child_entered_tree.connect(_on_child_entered.bind(body))
	var sprites := []
	for node: Node in body.find_children("*", "", true, false):
		if not (node is Sprite2D or node is AnimatedSprite2D):
			continue
		var sprite := node as CanvasItem
		if sprite.material == null:
			HitFlash.install(sprite)
		sprites.append(sprite)
	return sprites


func _on_child_entered(_child: Node, body: CharacterBody2D) -> void:
	_dirty[body] = true


func _has_uniforms(shader: Shader) -> bool:
	if shader == null:
		return false
	if not _shader_has.has(shader):
		var found := false
		for uniform: Dictionary in shader.get_shader_uniform_list():
			if StringName(uniform.get("name", "")) == DEPTH_UNIFORM:
				found = true
		_shader_has[shader] = found
	return bool(_shader_has[shader])
