extends Node2D
## The sleep look of a part of Glimmerhill (docs/godot/VILLAGERS.md "Asleep until its Pearl comes
## home"; owner, 2026-11-19: "shader first", a dimmed and greyed part of town): made by main when it
## builds a world of the wake table (glimmerhill_wake.gd) whose part sleeps, over the town's rectangle
## of a chunk (B4's leaves out the Wellspring and the prologue glade) or the whole room. A
## BackBufferCopy and then a rectangle drawing town_sleep.gdshader, at z `sleep.overlayZ` (30: over the
## ground, the props, the villagers and the slime's own things up to z 6; under the item pop-ups, the
## dark rooms and the effects drawn over everything; the HUD is a layer of its own), which reads the
## screen under it and greys (`sleep.grey`, toward `sleep.tint`) and darkens (`sleep.darken`) it. The
## rectangle's sides inside the world fade over `sleep.edgeSoftPx`; a soft circle of
## `sleep.slimeClearPx` round the slime keeps its colour (the slime is the Wellspring's, and awake).
## When the part's wake flag is set it fades out over `sleep.fadeMs` and is freed. Presentation
## only (real time); every number is in game-constants.json `story.glimmerhill.sleep`.
##
## Owner: world (Glimmerhill).

const Services := preload("res://game/shared/services.gd")
const GlimmerhillWake := preload("res://game/glimmerhill/glimmerhill_wake.gd")
const SHADER := preload("res://game/glimmerhill/town_sleep.gdshader")

const SCRIPT_PATH := "res://game/glimmerhill/town_sleep.gd"
const NODE_NAME := "TownSleep"
## The slime's middle over its feet (world units): where the clear circle is centred.
const SLIME_MIDDLE_RISE := 22.0

var _part := ""
var _rect := Rect2()
var _shade: ColorRect
var _material: ShaderMaterial
var _fading := false


## Puts the sleep look over `world_root` (already registered as `map_id`) when its part sleeps; null
## when it is awake or no part of the town.
static func mount(world_root: Node2D, map_id: String) -> Node2D:
	if world_root == null:
		return null
	var part_id := GlimmerhillWake.part_of_world(map_id)
	if part_id.is_empty() or GlimmerhillWake.is_awake(part_id):
		return null
	var world := Services.world()
	var world_rect: Rect2 = world.world_rect() if world != null else Rect2()
	var rect := GlimmerhillWake.town_rect(map_id)
	if not rect.has_area():
		rect = world_rect
	if not rect.has_area():
		return null
	var overlay: Node2D = (load(SCRIPT_PATH) as GDScript).new()
	overlay.name = NODE_NAME
	overlay.call(&"setup", part_id, rect, world_rect)
	world_root.add_child(overlay)
	return overlay


func setup(part_id: String, rect: Rect2, world_rect: Rect2) -> void:
	_part = part_id
	_rect = rect
	position = rect.position
	z_as_relative = false
	z_index = int(GlimmerhillWake.tunable_number("sleep", "overlayZ", 30.0))
	var copy := BackBufferCopy.new()
	copy.name = "ScreenCopy"
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"strength", 1.0)
	_material.set_shader_parameter(&"grey", GlimmerhillWake.tunable_number("sleep", "grey", 0.82))
	_material.set_shader_parameter(&"darken", GlimmerhillWake.tunable_number("sleep", "darken", 0.42))
	_material.set_shader_parameter(&"tint", _tint())
	_material.set_shader_parameter(&"rect_size", rect.size)
	var soft := GlimmerhillWake.tunable_number("sleep", "edgeSoftPx", 112.0)
	# Only the sides inside the world fade: at the world's edge the next chunk takes over.
	_material.set_shader_parameter(&"edge_soft", Vector4(
		soft if rect.position.x > world_rect.position.x + 0.5 else 0.0,
		soft if rect.position.y > world_rect.position.y + 0.5 else 0.0,
		soft if rect.end.x < world_rect.end.x - 0.5 else 0.0,
		soft if rect.end.y < world_rect.end.y - 0.5 else 0.0))
	_material.set_shader_parameter(&"clear_radius", GlimmerhillWake.tunable_number("sleep", "slimeClearPx", 42.0))
	_material.set_shader_parameter(&"clear_soft", GlimmerhillWake.tunable_number("sleep", "slimeClearSoftPx", 20.0))
	_shade = ColorRect.new()
	_shade.name = "Shade"
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.position = Vector2.ZERO
	_shade.size = rect.size
	_shade.material = _material
	add_child(_shade)


func _enter_tree() -> void:
	GlimmerhillWake.listen(_on_story_flag_changed)


func _exit_tree() -> void:
	GlimmerhillWake.unlisten(_on_story_flag_changed)


func _process(_delta: float) -> void:
	if _material == null:
		return
	var world := Services.world()
	var slime: Node2D = world.player_body if world != null and is_instance_valid(world.player_body) else null
	var at := Vector2(-100000.0, -100000.0)
	if slime != null and slime.is_visible_in_tree():
		at = to_local(slime.global_position - Vector2(0.0, SLIME_MIDDLE_RISE))
	_material.set_shader_parameter(&"clear_at", at)


## The part it greys ("").
func part_id() -> String:
	return _part


func _on_story_flag_changed(payload: Dictionary) -> void:
	if not _fading and GlimmerhillWake.wakes(payload, _part):
		wake()


## Fades out over `sleep.fadeMs`, then frees itself.
func wake() -> void:
	_fading = true
	var fade_s := maxf(0.05, GlimmerhillWake.tunable_number("sleep", "fadeMs", 1800.0) / 1000.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(func(value: float) -> void:
		if _material != null:
			_material.set_shader_parameter(&"strength", value), 1.0, 0.0, fade_s).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(queue_free)


static func _tint() -> Vector3:
	var raw: Variant = GlimmerhillWake.tunable("sleep", "tint", [0.8, 0.86, 1.0])
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3(0.8, 0.86, 1.0)
