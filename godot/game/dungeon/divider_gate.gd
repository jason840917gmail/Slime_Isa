@tool
extends Node2D
class_name DividerGate
## A gate in a dungeon divider (docs/godot/FENCES.md "Dungeon dividers"; `object.divider-gate`):
## the one special piece in a low divider line, standing on its own painted cell between two divider
## posts, its foot on the posts' foot line. Two kinds (owner, 2026-10-19): the **eye** block, a carved
## stone block that sinks into the floor (secret or latch-opened passages), and the **pen** gate, low
## iron bars that swing open on their west hinge and fold back against the west post (switch or key
## gates).
##
## The fences join the gate to the posts beside it (fences.gd `_add_gate_links`: rails and their
## bands up to the block's edges, `block_half_width`), so a shut gate closes its whole cell; its own
## `Doors` body covers the block, a unit past its edges. In a north-south divider it turns its body
## with the line (`fit_to_line`; the picture, a front view of a block or bars, stays as it is).
##
## Its GateScript child (game/scripts/gate.gd) is the gate: plates, bells, eye latches and keys (an
## inventory key, or a dungeon small key with `required_item_id` "small-key") find it by `gate_id` and
## open it (`open`, `open_for_good`, a push), its records are the gate's own. This node shows it shut
## or open on the gameplay clock and opens the passage when the block has sunk or the bars have swung
## (GateScript `release_doors`); a gate opened while its room is being built (its record, a held
## plate) shows open at once, without the dust. A push counts only from the slime on the gate's level.
## Painted on the `fences` layer with a gate tile (`lair-divider-eye`, `lair-divider-pen`), the fence
## layer keeps one on the cell (fence_layer.gd `sync_gates`).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const Fences := preload("res://game/world/fences/fences.gd")
const PICTURES := {"eye": "res://asset/MAPS/objects/dungeon/divider-eye-block.png",
	"pen": "res://asset/MAPS/objects/dungeon/divider-pen-gate.png"}
## How long the block sinks or the bars swing (the gameplay clock: the passage opens at the end).
const OPEN_MS := 650.0
## The bars' narrowest share of their width, edge-on half way through their swing.
const PEN_EDGE_ON := 0.12
## The art's density (px a unit).
const DENSITY := 2.0
## An opening this few physics frames after the gate is ready comes from its room being built (a
## plate already held): shown open at once.
const BUILT_FRAMES := 2

@export_enum("eye", "pen") var kind: String = "eye":
	set(value):
		kind = value
		if is_node_ready():
			_show_picture()

var _from := 0.0
var _to := 0.0
var _started_ms := 0.0
var _moving := false
var _share := 0.0
var _ready_frame := 0


## Half the width of a `kind` gate's block (its picture's, at DENSITY): the fences' rails and bands
## reach its edges (fences.gd), its `Doors` body covers it.
static func block_half_width(gate_kind: String) -> float:
	var texture := SheetSprite.load_picture(str(PICTURES.get(gate_kind, PICTURES["eye"])))
	return texture.get_size().x / DENSITY * 0.5 if texture != null else 0.0


func _ready() -> void:
	_show_picture()
	fit_to_line()
	var gate := _gate()
	if gate == null or Engine.is_editor_hint():
		return
	_ready_frame = Engine.get_physics_frames()
	gate.set(&"doors_wait_for_look", true)
	gate.set(&"level_checked", true)
	gate.connect(&"opened", func(_payload: Variant = null) -> void: _move(1.0))
	gate.connect(&"closed", func(_payload: Variant = null) -> void: _move(0.0))
	# built open (its record, a held plate's session record): its GateScript is ready before it
	if bool(gate.call(&"is_open")):
		_share = 1.0
		_place(1.0)


func _gate() -> Node:
	return get_node_or_null(^"GateScript")


func _look() -> Sprite2D:
	return get_node_or_null(^"Look") as Sprite2D


## Turns the gate's body with the divider line it stands in (Fences.gate_axis on its world's
## `fences` layer): across a north-south line its `Doors` shape runs north-south. Called when it is
## ready and by the fence layer after it places the gate.
func fit_to_line() -> void:
	var shape := get_node_or_null(^"Doors/Shape") as Node2D
	var layer := _fence_layer()
	if shape == null or layer == null or not is_inside_tree():
		return
	var axis := Fences.gate_axis(layer, layer.local_to_map(layer.to_local(global_position)))
	var turn := PI * 0.5 if axis == Vector2i.DOWN else 0.0
	if not is_equal_approx(shape.rotation, turn):
		shape.rotation = turn


## The world's painted `fences` layer (beside the gate's `Objects`), or null.
func _fence_layer() -> TileMapLayer:
	var at := get_parent()
	while at != null:
		var layer := at.get_node_or_null(^"fences") as TileMapLayer
		if layer != null and layer.tile_set != null and layer.tile_set.has_custom_data_layer_by_name(Fences.STYLE_DATA_LAYER):
			return layer
		at = at.get_parent()
	return null


func _show_picture() -> void:
	var look := _look()
	if look == null:
		return
	look.texture = SheetSprite.load_picture(str(PICTURES.get(kind, PICTURES["eye"])))
	look.centered = false
	_place(_share)


func _move(to: float) -> void:
	if Engine.get_physics_frames() - _ready_frame <= BUILT_FRAMES:
		# its room is being built: no sinking, no swing, no dust
		_moving = false
		_share = to
		_place(to)
		if to >= 1.0:
			_release()
		return
	_from = _share
	_to = to
	_started_ms = Services.now_ms()
	_moving = true
	var feel := Services.feel()
	if feel != null and to > 0.5:
		feel.particles(&"dodge-dust", global_position)


func _process(_delta: float) -> void:
	if not _moving:
		return
	var t := clampf((Services.now_ms() - _started_ms) / OPEN_MS, 0.0, 1.0)
	_share = lerpf(_from, _to, t * t * (3.0 - 2.0 * t))
	_place(_share)
	if t >= 1.0:
		_moving = false
		if _to >= 1.0:
			_release()


## The block has sunk or the bars have swung: the passage opens (GateScript `release_doors`).
func _release() -> void:
	var gate := _gate()
	if gate != null and gate.has_method(&"release_doors"):
		gate.call(&"release_doors")


## Shows the gate `open` (0 shut … 1 open), its picture's foot on the gate's foot (the node sorts
## there, the picture drawn upward with `offset`): the eye block sunk by that share into the floor
## (cut from its foot up, gone when sunk); the pen gate's bars swung on their west hinge (the west
## rail's end): edge-on half way, then folded back flat behind the west rail up to the west post,
## sorted just behind the rails (their tops show over it).
func _place(open: float) -> void:
	var look := _look()
	if look == null or look.texture == null:
		return
	var size := look.texture.get_size()
	look.region_enabled = true
	look.scale = Vector2.ONE / DENSITY
	if kind == "pen":
		var fold := lerpf(1.0, -1.0, open)
		if absf(fold) < PEN_EDGE_ON:
			fold = PEN_EDGE_ON if open < 0.5 else -PEN_EDGE_ON
		var behind := 1.0 if open > 0.5 else 0.0
		look.visible = true
		look.region_rect = Rect2(Vector2.ZERO, size)
		look.scale = Vector2(fold, 1.0) / DENSITY
		look.position = Vector2(-size.x / DENSITY * 0.5, -behind)
		look.offset = Vector2(0.0, behind * DENSITY - size.y)
	else:
		var shown := size.y * (1.0 - open)
		look.visible = open < 1.0
		look.region_rect = Rect2(0.0, 0.0, size.x, maxf(1.0, shown))
		look.position = Vector2(-size.x / DENSITY * 0.5, 0.0)
		look.offset = Vector2(0.0, -maxf(1.0, shown))
