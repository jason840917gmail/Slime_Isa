extends Node2D
## Glimmerhill's goo fountain (`game/scenes/objects/town/props/goo-fountain.tscn`; docs/godot/VILLAGERS.md
## "Asleep until its Pearl comes home"; owner, 2026-11-17: each Pearl home gives the Wellspring the
## strength to fill one more fountain). Standing in a part of the town that sleeps (the wake table,
## glimmerhill_wake.gd), it is dry: its dry picture (`dry_sheet_path`, one frame on the flowing
## sheet's canvas) and no animation. When the part's wake flag is set it bursts into flow: the flowing
## sheet and its loop again, a splash of goo out of the spout (`spout_rise` over its feet), a jolt of
## its picture and the splash cue. Anywhere else (a part awake, or no part) it simply flows.
##
## It is in the group `goo_fountains`: the homecoming (wellspring_homecoming.gd) pans the camera to the
## fountain of the part that wakes when it stands in the same world.
##
## **A drink** (owner, 2026-11-17, question 153: a woken fountain refills energy, taking over
## Slimeshire's well, whose refill "grows back after a while", question 113): it is in the
## interaction's `usable` group. Flowing, it offers "Drink": the slime's energy fills up in full
## (`restore_energy`; the PotionDrink and EnergyRestore cues, a sparkle and a cyan "+N"), then the
## fountain rests `fountain.drinkRestMs` of play before it gives another (a short line meanwhile).
## The rest is kept for the session by world and place, so leaving and coming back does not
## shorten it (not saved). With full energy it says so and does not rest. Dry, it offers a look and
## a short line, nothing more.
##
## Owner: world (Glimmerhill).

const Services := preload("res://game/shared/services.gd")
const GlimmerhillWake := preload("res://game/glimmerhill/glimmerhill_wake.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const GROUP := &"goo_fountains"
const CUE_BURST := &"WaterSplash"
const SPLASH := &"slime-splash"
const SPARKLE := &"loot-sparkle"
const VISUAL_NAME := "Visual"
const ANIMATION_NAME := "AmbientAnimation"
const USABLE_GROUP := &"usable"
const CUE_DRINK := &"PotionDrink"
const CUE_ENERGY := &"EnergyRestore"
const LINE_COLOR := &"white"
const GAIN_COLOR := &"cyan"

## The flowing sheet's Sprite2D and its AnimationPlayer (found by name when unset).
@export var visual: Sprite2D
@export var animation: AnimationPlayer
## The dry picture: one frame, the size of one frame of the flowing sheet.
@export_file("*.webp", "*.png") var dry_sheet_path: String = "res://asset/MAPS/town/props/goo-fountain-dry.webp"
## Where its goo comes out, over its feet (world units): the burst splashes there.
@export var spout_rise: float = 100.0
## The interaction: how near the slime's centre must be, where its key badge floats, its prompts.
@export var interact_radius: float = 110.0
@export var badge_rise: float = 140.0
@export var drink_prompt: String = "Drink"
@export var dry_prompt: String = "Look at the fountain"
## The short lines: dry, resting after a drink, and full of energy already.
@export var dry_line: String = "Dry as dust. The Wellspring is too weak to fill it yet."
@export var resting_line: String = "The goo is still welling up. Come back in a while."
@export var full_line: String = "You're already brimming with energy."

## The prompt the interaction shows (the fountain's state decides).
var prompt: String:
	get:
		return dry_prompt if _dry else drink_prompt

## When each fountain may give a drink again (Services.now_ms()), by world and place: the session's.
static var _rested_at_ms: Dictionary = {}

var _part := ""
var _dry := false
var _flow_texture: Texture2D
var _flow_hframes := 1
var _flow_vframes := 1


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(USABLE_GROUP)
	if _dry:
		GlimmerhillWake.listen(_on_story_flag_changed)


func _exit_tree() -> void:
	GlimmerhillWake.unlisten(_on_story_flag_changed)


func _ready() -> void:
	if visual == null:
		visual = get_node_or_null(NodePath(VISUAL_NAME)) as Sprite2D
	if animation == null:
		animation = get_node_or_null(NodePath(ANIMATION_NAME)) as AnimationPlayer
	_part = GlimmerhillWake.part_at(GlimmerhillWake.world_id_of(self), global_position)
	if not _part.is_empty() and not GlimmerhillWake.is_awake(_part):
		_run_dry()


## The part of Glimmerhill it stands in ("" none).
func part_id() -> String:
	return _part


func is_dry() -> bool:
	return _dry


## Where the camera looks at it (its middle).
func view_point() -> Vector2:
	return global_position - Vector2(0.0, spout_rise * 0.6)


## The point the interaction measures from (its foot).
func origin() -> Vector2:
	return global_position


## True while it rests after a drink.
func is_resting() -> bool:
	return Services.now_ms() < float(_rested_at_ms.get(_rest_key(), -INF))


## The interact key: a drink when it flows and has rested, else its short line. True when it acted.
func use() -> bool:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return false
	if _dry:
		_say(dry_line)
		return true
	if is_resting():
		_say(resting_line)
		return true
	var gained := float(player.call(&"restore_energy", float(player.call(&"get_max_energy"))))
	if gained <= 0.0:
		_say(full_line)
		return true
	_rested_at_ms[_rest_key()] = Services.now_ms() + GlimmerhillWake.tunable_number("fountain", "drinkRestMs", 60000.0)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_DRINK)
		feel.audio_cue(CUE_ENERGY)
		feel.particles(SPARKLE, global_position - Vector2(0.0, spout_rise * 0.5))
		var at: Vector2 = player.call(&"get_centre") if player.has_method(&"get_centre") else global_position
		feel.floating_text(at - Vector2(0.0, 30.0), "+%d" % roundi(gained), GAIN_COLOR, true)
	return true


func _say(line: String) -> void:
	var feel := Services.feel()
	if feel != null and not line.is_empty():
		feel.floating_text(global_position - Vector2(0.0, badge_rise * 0.8), line, LINE_COLOR, false)


## The fountain's key in the session's rests: its world and its place.
func _rest_key() -> String:
	return "%s@%d,%d" % [GlimmerhillWake.world_id_of(self), roundi(global_position.x), roundi(global_position.y)]


func _run_dry() -> void:
	_dry = true
	if animation != null:
		animation.stop()
	if visual != null:
		_flow_texture = visual.texture
		_flow_hframes = visual.hframes
		_flow_vframes = visual.vframes
		var dry := SheetSprite.load_picture(dry_sheet_path)
		if dry != null:
			visual.texture = dry
			visual.hframes = 1
			visual.vframes = 1
			visual.frame = 0
	GlimmerhillWake.listen(_on_story_flag_changed)


func _on_story_flag_changed(payload: Dictionary) -> void:
	if _dry and GlimmerhillWake.wakes(payload, _part):
		flow(true)


## Runs again; `burst`: with the splash, the jolt and the cue.
func flow(burst: bool) -> void:
	if not _dry:
		return
	_dry = false
	GlimmerhillWake.unlisten(_on_story_flag_changed)
	if visual != null and _flow_texture != null:
		visual.texture = _flow_texture
		visual.hframes = _flow_hframes
		visual.vframes = _flow_vframes
		visual.frame = 0
	if animation != null and not String(animation.autoplay).is_empty():
		animation.play(animation.autoplay)
	if burst:
		_burst()


func _burst() -> void:
	var spout := global_position - Vector2(0.0, spout_rise)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_BURST)
		var splashes := int(GlimmerhillWake.tunable_number("fountain", "burstSplashes", 5.0))
		var spread := GlimmerhillWake.tunable_number("fountain", "burstSpreadPx", 46.0)
		for i in splashes:
			var aside := (float(i) / maxf(1.0, float(splashes - 1)) - 0.5) * 2.0 * spread
			feel.particles(SPLASH, spout + Vector2(aside, absf(aside) * 0.4))
		feel.particles(SPARKLE, spout)
	if visual == null:
		return
	var base := visual.scale
	var jolt := GlimmerhillWake.tunable_number("fountain", "burstScale", 0.12)
	var burst_s := maxf(0.05, GlimmerhillWake.tunable_number("fountain", "burstMs", 700.0) / 1000.0)
	var tween := create_tween()
	tween.tween_property(visual, "scale", base * Vector2(1.0 - jolt * 0.5, 1.0 + jolt), burst_s * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "scale", base, burst_s * 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
