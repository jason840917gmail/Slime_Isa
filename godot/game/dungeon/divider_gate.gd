@tool
extends Node2D
class_name DividerGate
## A gate in a dungeon divider (docs/godot/FENCES.md "Dungeon dividers"; `object.divider-gate`):
## the one special piece in a low divider line, standing on the cell between two divider posts, its
## foot on the posts' foot line. Two kinds (owner, 2026-10-19): the **eye** block, a carved stone
## block that sinks into the floor (secret or latch-opened passages), and the **pen** gate, low
## iron bars that swing open against a post (switch or key gates).
##
## Its GateScript child (game/scripts/gate.gd) is the gate: plates, bells, eye latches and keys
## find it by `gate_id` and open it (`open`, `open_for_good`, a push with the key), its records are
## the gate's own; this node only shows it shut or open and its `Doors` body blocks the gap between
## the posts while shut. Painted on the `fences` layer with a gate tile (`lair-divider-eye`,
## `lair-divider-pen`), the fence layer keeps one on the cell (fence_layer.gd `sync_gates`).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const PICTURES := {"eye": "res://asset/MAPS/objects/dungeon/divider-eye-block.png",
	"pen": "res://asset/MAPS/objects/dungeon/divider-pen-gate.png"}
## How long the block sinks or the bars swing (real time: presentation).
const OPEN_MS := 650.0
## The pen gate swings to this share of its width (it folds against the west post).
const PEN_FOLDED := 0.12
## The art's density (px a unit).
const DENSITY := 2.0

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


func _ready() -> void:
	_show_picture()
	var gate := _gate()
	if gate == null or Engine.is_editor_hint():
		return
	gate.connect(&"opened", func(_payload: Variant = null) -> void: _move(1.0))
	gate.connect(&"closed", func(_payload: Variant = null) -> void: _move(0.0))
	_settle.call_deferred()


func _gate() -> Node:
	return get_node_or_null(^"GateScript")


func _look() -> Sprite2D:
	return get_node_or_null(^"Look") as Sprite2D


func _show_picture() -> void:
	var look := _look()
	if look == null:
		return
	look.texture = SheetSprite.load_picture(str(PICTURES.get(kind, PICTURES["eye"])))
	look.centered = false
	look.scale = Vector2.ONE / DENSITY
	_place(0.0)


func _settle() -> void:
	var gate := _gate()
	if gate != null and bool(gate.call(&"is_open")):
		_share = 1.0
		_place(1.0)


func _move(to: float) -> void:
	_from = _share
	_to = to
	_started_ms = float(Time.get_ticks_msec())
	_moving = true
	var feel := Services.feel()
	if feel != null and to > 0.5:
		feel.particles(&"dodge-dust", global_position)


func _process(_delta: float) -> void:
	if not _moving:
		return
	var t := clampf((float(Time.get_ticks_msec()) - _started_ms) / OPEN_MS, 0.0, 1.0)
	_share = lerpf(_from, _to, t * t * (3.0 - 2.0 * t))
	_place(_share)
	if t >= 1.0:
		_moving = false


## Shows the gate `open` (0 shut … 1 open): the eye block sunk by that share into the floor (cut
## from its foot up), the pen gate folded toward its west post.
func _place(open: float) -> void:
	var look := _look()
	if look == null or look.texture == null:
		return
	var size := look.texture.get_size()
	look.visible = open < 0.98
	look.region_enabled = true
	if kind == "pen":
		look.region_rect = Rect2(Vector2.ZERO, size)
		var fold := lerpf(1.0, PEN_FOLDED, open)
		look.scale = Vector2(fold, 1.0) / DENSITY
		look.position = Vector2(-size.x / DENSITY * 0.5, -size.y / DENSITY)
	else:
		var shown := size.y * (1.0 - open)
		look.region_rect = Rect2(0.0, 0.0, size.x, maxf(1.0, shown))
		look.scale = Vector2.ONE / DENSITY
		look.position = Vector2(-size.x / DENSITY * 0.5, -shown / DENSITY)
