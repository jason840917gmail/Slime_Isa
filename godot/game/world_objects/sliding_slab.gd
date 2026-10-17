extends Sprite2D
## The stone slab of `object.latch-door` (game/scenes/objects/latch-door.tscn; Fatty's Lair,
## docs/godot/DUNGEONS.md "Fatty's Lair (built)"): a door with no lock of its own, opened by what
## stands beside it (a stone eye latch, a bell). It follows its GateScript (game/scripts/gate.gd, the
## node `gate`): when the gate opens the slab slides up into the lintel (its picture cut from the top,
## over `slide_ms` of real time) and hides; when it shuts it slides back down; built open, it is
## gone. Presentation only.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const CUE_SLIDE := &"GateOpen"
const DUST := &"dodge-dust"

@export var gate: NodePath
@export var slide_ms: float = 700.0
## The slab's picture (loaded as game/runtime/sheet_sprite.gd does, before an import).
@export_file("*.webp", "*.png") var sheet_path: String = ""

var _region := Rect2()
var _from := 0.0
var _to := 0.0
var _started_ms := 0.0
var _moving := false


func _ready() -> void:
	if texture == null and not sheet_path.is_empty():
		texture = SheetSprite.load_picture(sheet_path)
	if texture != null:
		_region = Rect2(Vector2.ZERO, texture.get_size())
		region_enabled = true
		region_rect = _region
	var target := get_node_or_null(gate)
	if target == null:
		return
	if target.has_signal(&"opened"):
		target.connect(&"opened", func(_payload: Variant = null) -> void: _slide(1.0))
	if target.has_signal(&"closed"):
		target.connect(&"closed", func(_payload: Variant = null) -> void: _slide(0.0))
	_settle.call_deferred()


func _settle() -> void:
	var target := get_node_or_null(gate)
	if target != null and target.has_method(&"is_open") and bool(target.call(&"is_open")):
		_show(1.0)


func _slide(to: float) -> void:
	_from = _lift()
	_to = to
	_started_ms = float(Time.get_ticks_msec())
	_moving = true
	visible = true
	var feel := Services.feel()
	if feel != null and to > 0.5:
		feel.particles(DUST, global_position + Vector2(0.0, -4.0))


func _process(_delta: float) -> void:
	if not _moving:
		return
	var t := clampf((float(Time.get_ticks_msec()) - _started_ms) / maxf(1.0, slide_ms), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	_show(lerpf(_from, _to, eased))
	if t >= 1.0:
		_moving = false


func _lift() -> float:
	if _region.size.y <= 0.0:
		return 0.0
	return clampf(region_rect.position.y / _region.size.y, 0.0, 1.0)


func _show(lift: float) -> void:
	var cut := _region.size.y * lift
	visible = cut < _region.size.y - 1.0
	region_rect = Rect2(Vector2(0.0, cut), Vector2(_region.size.x, maxf(1.0, _region.size.y - cut)))
