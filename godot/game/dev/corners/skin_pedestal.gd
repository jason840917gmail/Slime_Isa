extends Node2D
## A playground skin pedestal (docs/godot/SKINS.md "The Skins corner"): a dev stand-in for a Pearl,
## so each skin can be tried with and without it. Interact (W / right click) lends skin `skin_id`
## for the session (SkinState.lend: always on, never saved; the look stays as it was, a skin shows
## only while it works, docs/godot/SKINS.md), and again gives it back (SkinState.give_back). A skin
## won for good stays: the pedestal says so. Its icon
## (asset/UI/skins/<skin>-icon.webp) floats over the stone, bright while the skin is on.
##
## Owner: skins (the playground).

const Services := preload("res://game/shared/services.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const USABLE_GROUP := &"usable"
const ICON := "res://asset/UI/skins/%s-icon.webp"
const ICON_RISE := 70.0
const ICON_SCALE := 0.42
const BOB_PX := 4.0
const BOB_PERIOD_S := 2.0
const TEXT_RISE := 110.0
const OFF_TINT := Color(0.55, 0.55, 0.6, 0.75)

@export var skin_id: String = "heavy"
@export var interact_radius: float = 80.0
@export var badge_rise: float = 96.0

## The interact prompt (read by the interaction controller every time it offers it).
var prompt: String:
	get:
		var title := SkinState.display_name(StringName(skin_id))
		if SkinState.is_won(StringName(skin_id)):
			return "%s (won)" % title
		return ("Give back the %s" if SkinState.is_on(null, StringName(skin_id)) else "Try the %s") % title

var _icon: Sprite2D
var _clock := 0.0


func _enter_tree() -> void:
	add_to_group(USABLE_GROUP)


func _ready() -> void:
	_icon = Sprite2D.new()
	_icon.name = "Icon"
	_icon.texture = SheetSprite.load_picture(ICON % skin_id)
	_icon.scale = Vector2(ICON_SCALE, ICON_SCALE)
	_icon.position = Vector2(0.0, -ICON_RISE)
	_icon.z_index = 1
	add_child(_icon)


func _process(delta: float) -> void:
	_clock += delta
	if _icon == null:
		return
	_icon.position.y = -ICON_RISE + sin(_clock * TAU / BOB_PERIOD_S) * BOB_PX
	_icon.modulate = Color.WHITE if SkinState.is_on(null, StringName(skin_id)) else OFF_TINT


func origin() -> Vector2:
	return global_position


func can_use() -> bool:
	return not SkinState.is_won(StringName(skin_id))


## Lends the skin, or gives it back.
func use() -> bool:
	var id := StringName(skin_id)
	var feel := Services.feel()
	if SkinState.is_won(id):
		return false
	var text := ""
	if SkinState.is_on(null, id):
		SkinState.give_back(id)
		text = "%s given back" % SkinState.display_name(id)
		if feel != null:
			feel.audio_cue(&"GulpBurp")
	else:
		SkinState.lend(id)
		text = "%s on (for this session)" % SkinState.display_name(id)
		SkinState.ceremony_line(id)
		if feel != null:
			feel.audio_cue(&"AbilityLearned")
	if feel != null:
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), text, &"cyan", false, 2000.0)
	return true
