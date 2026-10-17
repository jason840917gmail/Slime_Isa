extends Node2D
class_name PearlScript
## Scene script `game.pearl` (`object.pearl`, game/scenes/objects/pearl.tscn; roadmap 5.9; Fatty's
## Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"): a Pearl of the Wellspring, the prize a boss
## held. It shows only once its boss (`boss_id`, RunState `defeated_boss_ids`) is beaten, rising
## with a glow; the slime takes it by walking into it (within `take_radius`). Taking it plays the full
## ceremony (game/ui/ceremony/ability_ceremony.gd `request_entry`: the Pearl's card), sets the story
## flags `pearl.<pearl_id>` and `skin_flag` (the skin it grants: Pearl 1's is the Heavy skin,
## "skin.heavy", which game/fattys_lair/heavy_check.gd reads until roadmap 7.8 builds the skins), and
## it is gone for good. Its altar is a separate prop.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")

const GROUP := &"pearl"
const FLAG_PREFIX := "pearl."
const CUE_APPEAR := &"SecretFound"
const SPARKLE := &"loot-sparkle"
const BOB_PX := 5.0
const BOB_PERIOD_S := 2.2
const APPEAR_S := 0.9

## Taken. Payload: {"pearlId", "skinFlag"}.
signal taken(payload: Dictionary)
## Shown (its boss beaten). Payload: {"pearlId"}.
signal appeared(payload: Dictionary)

@export var pearl_id: String = "fatty-one-eye"
## The boss whose defeat shows it ("" = always shown).
@export var boss_id: String = "fatty-one-eye"
## Which of the eight Pearls it is.
@export var number: int = 1
## The story flag of the skin it grants.
@export var skin_flag: String = "skin.heavy"
@export var card_name: String = "Heavy skin"
@export var card_line: String = "Fatty's weight is yours: you sink heavy plates and push statues and blocks."
@export var card_how: String = "Your Roll smashes old, broken things: planks, rubble, rotten wood."
@export var take_radius: float = 40.0
@export var visual: Sprite2D

var _shown := false
var _taken := false
var _clock := 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	var run := Services.run()
	_taken = run != null and run.has_flag(FLAG_PREFIX + pearl_id)
	_shown = not _taken and _boss_beaten()
	visible = _shown


func is_taken() -> bool:
	return _taken


func is_shown() -> bool:
	return _shown


## Shows it now (its boss was just beaten): it rises and glows.
func appear() -> void:
	if _shown or _taken:
		return
	_shown = true
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, APPEAR_S)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_APPEAR)
		feel.particles(SPARKLE, global_position - Vector2(0.0, 20.0))
	appeared.emit({"pearlId": pearl_id})


func _process(delta: float) -> void:
	if not _shown or visual == null:
		return
	_clock += delta
	visual.position.y = sin(_clock * TAU / BOB_PERIOD_S) * BOB_PX


func _physics_process(_delta: float) -> void:
	if _taken:
		return
	if not _shown:
		if _boss_beaten():
			appear()
		return
	var world := Services.world()
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	var centre: Vector2 = world.player.call(&"get_centre")
	if centre.distance_to(global_position) <= take_radius:
		take()


## The slime takes it: the flags, the ceremony, gone.
func take() -> void:
	if _taken:
		return
	_taken = true
	var run := Services.run()
	if run != null:
		run.set_flag(FLAG_PREFIX + pearl_id)
		if not skin_flag.is_empty():
			run.set_flag(skin_flag)
	var icon: Texture2D = visual.texture if visual != null else null
	# Only while main's ceremonies are on (off in the test runner, whose queued card would otherwise
	# pause the next test's world: the ceremony lives under the tree's root).
	if AbilityCeremony.enabled(get_tree()):
		AbilityCeremony.request_entry(get_tree(), {"kicker": "Pearl of the Wellspring (%d of 8)" % number,
			"name": card_name, "line": card_line, "how": card_how, "icon": icon})
	var feel := Services.feel()
	if feel != null:
		feel.particles(SPARKLE, global_position)
	taken.emit({"pearlId": pearl_id, "skinFlag": skin_flag})
	visible = false


func _boss_beaten() -> bool:
	if boss_id.is_empty():
		return true
	var run := Services.run()
	return run != null and boss_id in (run.world.get("defeated_boss_ids", []) as Array)
