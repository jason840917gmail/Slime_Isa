extends RefCounted
## The skins' looks on the slime (docs/godot/SKINS.md "Looks"; Direction "The skins": a skin shows
## while it works, and the player may pick one as the everyday look). Owned by player.gd, which
## hands it the Visual's material (form_skin.gdshader) and calls `update` every frame (real time:
## presentation only).
##
## What the slime shows, first that applies:
## 1. a Gulp form's own skin (the classic game's Stone, Silk and Swim forms: `set_form_skin`);
## 2. a skin that works right now (`show_working`, from SkinState.show: the Heavy skin on a heavy
##    plate, grabbing a block or in a Heavy Roll; the Silk skin in a web or a web wall, or as the
##    Spear cuts silk; the Feral skin while it climbs), for `skins.lookShowMs` after the last call;
## 3. the everyday look picked in the bag (SkinState.look), a won skin or none;
## 4. the slime's own goo.
## A change fades the old pattern out (`skins.lookFadeOutMs`) and the new one in
## (`skins.lookFadeInMs`) through the shader's `skin_amount`; a form's skin shows at once.
##
## Owner: skins.

const SkinState := preload("res://game/player/skins/skin_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const SKIN_PARAM := &"skin"
const AMOUNT_PARAM := &"skin_amount"
const TEXTURE_PARAM := &"look_texture"
const HAS_TEXTURE_PARAM := &"has_look_texture"
## Each skin's painted look (scripts/art/pack-skin-art.py); a skin without one keeps its code
## pattern (form_skin.gdshader).
const LOOK_TEXTURE := "res://asset/player/skins/%s-look.webp"

## Skin id -> its look texture (or null when it has none), loaded once.
static var _textures: Dictionary = {}

var _material: ShaderMaterial
var _form_skin: int = 0
var _working: StringName = &""
var _working_until_ms: float = -1.0
## The skin whose pattern the shader paints now, and how much of it shows.
var _shown: StringName = &""
var _amount: float = 0.0
var _last_ms: float = -1.0


## `skin_material` is the Visual's form_skin.gdshader material (null: nothing to paint).
func setup(skin_material: ShaderMaterial) -> void:
	_material = skin_material
	_apply()


## A Gulp form's skin (0 when none): it shows at once and over every skin's look.
func set_form_skin(skin: int) -> void:
	_form_skin = maxi(0, skin)
	_apply()


## Skin `id` works now (`now_ms`: real time): its look shows for `skins.lookShowMs`.
func show_working(id: StringName, now_ms: float) -> void:
	if String(id).is_empty():
		return
	_working = id
	_working_until_ms = now_ms + SkinState.setting("lookShowMs", 900.0)


## The skin the slime looks like now (&"" for the goo; a Gulp form's skin is not a skin).
func shown() -> StringName:
	return _shown if _amount > 0.0 else &""


## The shader's `skin` and `skin_amount` now (the shape weapons wear the same: shape_visuals.gd).
func shader_skin() -> int:
	if _form_skin > 0:
		return _form_skin
	return SkinState.look_index(_shown) if not String(_shown).is_empty() else 0


func shader_amount() -> float:
	return 1.0 if _form_skin > 0 else _amount


## Every frame (real time): picks the look and fades toward it.
func update(now_ms: float) -> void:
	var dt := 0.0 if _last_ms < 0.0 else maxf(0.0, now_ms - _last_ms)
	_last_ms = now_ms
	var target := _target(now_ms)
	if target != _shown:
		# Fade the old one out first (from nothing, the new one starts at once).
		if _amount > 0.0 and not String(_shown).is_empty():
			_amount = maxf(0.0, _amount - dt / maxf(1.0, SkinState.setting("lookFadeOutMs", 320.0)))
		if _amount <= 0.0 or String(_shown).is_empty():
			_shown = target
			_amount = 0.0
	elif not String(_shown).is_empty() and _amount < 1.0:
		_amount = minf(1.0, _amount + dt / maxf(1.0, SkinState.setting("lookFadeInMs", 140.0)))
	_apply()


func _target(now_ms: float) -> StringName:
	if not String(_working).is_empty() and now_ms < _working_until_ms and SkinState.is_on(null, _working):
		return _working
	_working = &""
	var everyday := SkinState.look()
	return everyday if SkinState.is_on(null, everyday) else &""


## The painted texture of the look shown now (null for a form or the goo, or a skin without one).
func shader_texture() -> Texture2D:
	if _form_skin > 0 or String(_shown).is_empty():
		return null
	return texture_of(_shown)


## Skin `id`'s painted look (read through SheetSprite, so a texture not imported yet loads too).
static func texture_of(id: StringName) -> Texture2D:
	if not _textures.has(id):
		_textures[id] = SheetSprite.load_picture(LOOK_TEXTURE % String(id))
	return _textures[id] as Texture2D


## Writes the look into `skin_material` (the Visual's, or a shape weapon's).
func apply_to(skin_material: ShaderMaterial) -> void:
	if skin_material == null:
		return
	var texture := shader_texture()
	skin_material.set_shader_parameter(SKIN_PARAM, shader_skin())
	skin_material.set_shader_parameter(AMOUNT_PARAM, shader_amount())
	skin_material.set_shader_parameter(HAS_TEXTURE_PARAM, texture != null)
	skin_material.set_shader_parameter(TEXTURE_PARAM, texture)


func _apply() -> void:
	apply_to(_material)
