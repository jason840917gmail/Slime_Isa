extends Node2D
## The Gulp hints (abilities spec 11.5; redesigned 2026-10-08). Over the nearest thing the slime
## could suck in now, "[Q] Suck" (#ffe89a); while it holds something, over the slime, "[Q] Throw",
## and "[R] Swallow" too for a held essence once Swallow is learned. Key names come from the
## bindings. The form badge lives on the HUD console (roadmap 4.12); forms have no timer. World
## space, drawn over everything.
##
## Owner: abilities.

const ControlLabels := preload("res://game/shell/control_labels.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")

const FONT_SIZE := 14
const OUTLINE := 4
const HINT_COLOR := Color("#ffe89a")
const OUTLINE_COLOR := Color("#101a31")
const TARGET_RISE := 40.0
const HELD_RISE := 70.0

## player.gd: get_centre, is_dead, held, nearest_suckable, is_learned.
var player: Node
var _hint: Label


func _ready() -> void:
	top_level = true
	z_index = 100
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font_size = FONT_SIZE
	settings.font_color = HINT_COLOR
	settings.outline_size = OUTLINE
	settings.outline_color = OUTLINE_COLOR
	_hint.label_settings = settings
	_hint.visible = false
	add_child(_hint)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")):
		_hint.visible = false
		return
	var held: Dictionary = player.call(&"held")
	if not held.is_empty():
		var text := "[%s] Throw" % ControlLabels.control_label(&"eat")
		if str(held.get("kind", "")) == "essence" and bool(player.call(&"is_learned", AbilityDefinitions.SWALLOW)):
			text += "  [%s] Swallow" % ControlLabels.control_label(&"swallow")
		_show(text, (player.call(&"get_centre") as Vector2) - Vector2(0.0, HELD_RISE))
		return
	var target: Node = player.call(&"nearest_suckable")
	if target == null:
		_hint.visible = false
		return
	_show("[%s] Suck" % ControlLabels.control_label(&"eat"), (target.call(&"origin") as Vector2) - Vector2(0.0, TARGET_RISE))


## Bottom-centre of the hint at `at`.
func _show(text: String, at: Vector2) -> void:
	_hint.text = text
	_hint.visible = true
	var size := _hint.get_minimum_size()
	_hint.position = (at - Vector2(size.x / 2.0, size.y)).round()
