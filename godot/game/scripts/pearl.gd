extends Node2D
class_name PearlScript
## Scene script `game.pearl` (`object.pearl`, game/scenes/objects/pearl.tscn; roadmap 5.9; Fatty's
## Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"): a Pearl of the Wellspring, the prize a boss
## held. It shows only once its boss (`boss_id`, RunState `defeated_boss_ids`) is beaten, rising
## with a glow; the slime takes it by walking into it (within `take_radius`). Taking it plays the full
## ceremony (game/ui/ceremony/ability_ceremony.gd `request_entry`: the Pearl's card), sets the story
## flag `pearl.<pearl_id>`, grants its skin (`skin_id`: SkinState.grant, docs/godot/SKINS.md: won
## for good, always on, its short ceremony line the first time; the everyday look stays as it was, a
## skin shows only while it works; Pearl 1's is
## the Heavy skin, 2's the Silk skin, 3's the Feral skin), and it is gone for good. Its altar is a
## separate prop. With `boss_id` empty it shows from the start (a Pearl found inside its dungeon,
## before its boss: owner, 2026-10-17).
##
## **Inside a dungeon** (docs/godot/DUNGEONS.md "The seal"; owner, 2026-10-17: the Pearl inside the
## dungeon): set `boss_id` to its guard's id (the mini-boss's room fight `boss_id`), so it rises on
## its altar once he falls. Taking it (`seals_dungeon`) seals the dungeon until the dungeon's boss
## falls: the Dungeon node's `seal_now` (his roar as the card closes, the glimpse of the entrance's
## seal slamming shut: game/dungeon/seal_moment.gd). A Pearl taken after its dungeon's boss fell (an
## old save) seals nothing.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const GROUP := &"pearl"
const FLAG_PREFIX := "pearl."
const CUE_APPEAR := &"SecretFound"
const SPARKLE := &"loot-sparkle"
const BOB_PX := 5.0
const BOB_PERIOD_S := 2.2
const APPEAR_S := 0.9

## Taken. Payload: {"pearlId", "skinId"}.
signal taken(payload: Dictionary)
## Shown (its boss beaten). Payload: {"pearlId"}.
signal appeared(payload: Dictionary)

@export var pearl_id: String = "fatty-one-eye"
## The boss whose defeat shows it ("" = always shown).
@export var boss_id: String = "fatty-one-eye"
## Which of the eight Pearls it is.
@export var number: int = 1
## The skin it grants (SkinState: heavy, silk, feral; "" = none).
@export var skin_id: String = "heavy"
@export var card_name: String = "Heavy skin"
## The card's texts; `{<action>}` names that action's key (ControlLabels.with_keys: "{interact}" reads
## "W" in the keys-only scheme).
@export var card_line: String = "Fatty's weight is yours: you sink heavy plates, and holding {interact} you push or pull heavy statues and blocks."
@export var card_how: String = "Your Roll smashes old, broken things: planks, rubble, loose rocks, rotten wood."
@export var take_radius: float = 40.0
## Taken inside a dungeon whose boss stands, it seals the dungeon (the Dungeon node's `seal_now`).
@export var seals_dungeon: bool = true
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


## The slime takes it: its flag, the skin, the ceremony, the dungeon's seal, gone. `quiet` (the
## `?sealed` dev option): no card, and the seal shuts without the roar and the glimpse.
func take(quiet: bool = false) -> void:
	if _taken:
		return
	_taken = true
	var run := Services.run()
	if run != null:
		run.set_flag(FLAG_PREFIX + pearl_id)
	# Only while main's ceremonies are on (off in the test runner, whose queued card would otherwise
	# pause the next test's world: the ceremony lives under the tree's root).
	var card := not quiet and AbilityCeremony.enabled(get_tree())
	# The card is the skin's celebration and description: first the card, and once the player
	# accepts it the boss's roar and the seal's glimpse (owner, 2026-11-21, question 141). The skin's
	# own floating lines show only without a card (they ran on after it, under the roar's line).
	if not skin_id.is_empty():
		SkinState.grant(StringName(skin_id), not card)
	var icon: Texture2D = visual.texture if visual != null else null
	if card:
		AbilityCeremony.request_entry(get_tree(), {"kicker": "Pearl of the Wellspring (%d of 8)" % number,
			"name": card_name, "line": ControlLabels.with_keys(card_line), "how": ControlLabels.with_keys(card_how),
			"icon": icon})
	var feel := Services.feel()
	if feel != null and not quiet:
		feel.particles(SPARKLE, global_position)
	if seals_dungeon:
		var dungeon := DungeonState.current(get_tree())
		if dungeon != null and dungeon.has_method(&"seal_now"):
			dungeon.call(&"seal_now", pearl_id, not quiet)
	taken.emit({"pearlId": pearl_id, "skinId": skin_id})
	visible = false


func _boss_beaten() -> bool:
	if boss_id.is_empty():
		return true
	var run := Services.run()
	return run != null and boss_id in (run.world.get("defeated_boss_ids", []) as Array)
