extends Node2D
## Plop at the town's edge (roadmap 5.24; docs/godot/PROLOGUE.md): the node `PrologueMeeting` in
## level-1-c4, by the forest path that comes out of the prologue on Slimeshire's west edge. When the
## slime comes out of the forest while the prologue runs (the barred gate open), Elder Plop stands
## here (`spot`, a child marker), the "!" over him, and meets it: amazed that a slime came out of the
## Wellspring, he gives it his satchel, the 10-slot bag (roadmap 5.7: the slime was born with none),
## with the ceremony, and his first tips; then the prologue is over (PrologueState.finish): saving
## works again, Slimeshire's banner shows, and Plop fades back to his place in the village. At any
## other time it does nothing.
##
## Owner: prologue.

const Services := preload("res://game/shared/services.gd")
const PrologueState := preload("res://game/prologue/prologue_state.gd")
const PrologueScene := preload("res://game/prologue/prologue_scene.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const AreaTitles := preload("res://game/shell/area_titles.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const PLOP_DEFINITION := "village-elder-plop"
const NPC_GROUP := &"npc"
const SPEAKER := "Elder Plop"
const REGION_WORLD := "level-1"
const SATCHEL_ICON := "res://asset/UI/items/plops-satchel.webp"
const CUE_HELLO := &"NpcBlip"
const CUE_BAG := &"Ceremony"
const MARK_TEXT := "!"
const MARK_COLOR := Color("#ffd277")
const MARK_SIZE := 30
const MARK_RISE := 93.0

const MEETING: Array[String] = [
	"Oh! Oh my, my... a newborn slime, out of the forest!",
	"No slime has come out of the Wellspring in years... and here you are.",
	"And you have met old Yoi, I see. A spear of your own goo already! The Thorn Guard never did like to wait.",
	"I am Plop, the elder of Slimeshire. Goo is no good for carrying things, little one. Here, my old satchel. Ten pockets, and only one hole.",
]
const TIPS: Array[String] = [
	"Now, a few tips from an old slime.",
	"The village is just up the path. Talk to everyone: every slime here knows something worth knowing.",
	"Fatty One Eye's worms come up out of the old burrow east of the village. Keep your spear ready, and your distance.",
	"And when you are tired, rest. A slime that never rests goes flat. Come and find me in the village!",
]
const BAG_CARD := {"kicker": "New bag", "name": "Plop's satchel",
	"line": "Ten pockets, and only one hole: what you pick up goes in here."}

## Where Plop waits (his feet).
@export var spot: Node2D
## The bag Plop gives (roadmap 5.7: Release 1's one bag).
@export var bag_slots: int = 10
## The slime holds still while Plop comes to it (ms after the arrival, the fade's length).
@export var arrival_ms: float = 600.0
## Plop fades home rather than trying to walk down the plateau stairs.
@export var home_fade_ms: float = 250.0

var _player: Node
var _plop: Node
var _release: Callable = Callable()
var _started := false
var _holding := false
var _mark: Label
var _home_position := Vector2.ZERO
var _home_modulate := Color.WHITE


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var run := Services.run()
	if not (PrologueState.is_running(run) and PrologueState.has_beat(run, PrologueState.GATE_OPEN)):
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if _holding:
		PrologueScene.hold(_player)
	if _started:
		return
	var world := Services.world()
	_player = world.player if world != null else null
	if _player == null or not is_instance_valid(_player):
		return
	_started = true
	_meet()


func _process(_delta: float) -> void:
	if _mark == null or _plop == null or not is_instance_valid(_plop):
		return
	var body: Variant = _plop.get(&"body")
	if body is Node2D:
		_mark.global_position = (body as Node2D).global_position - Vector2(_mark.size.x / 2.0, MARK_RISE + _mark.size.y)


## The meeting (a coroutine).
func _meet() -> void:
	_holding = true
	_plop = _find_plop()
	if _plop != null:
		var body: Variant = _plop.get(&"body")
		if body is Node2D and spot != null:
			_home_position = (body as Node2D).global_position
			_home_modulate = (body as Node2D).modulate
			(body as Node2D).global_position = spot.global_position
			(body as CharacterBody2D).reset_physics_interpolation()
			_track_plop(body as CharacterBody2D)
		if _plop.has_method(&"acquire_interaction_lock"):
			_release = _plop.call(&"acquire_interaction_lock")
		# The "!" over him: the quest markers' own when they show one (his first quest), else this one.
		if _quest_mark_kind().is_empty():
			_show_mark()
	await PrologueScene.wait(get_tree(), arrival_ms)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HELLO)
	await PrologueScene.say(get_tree(), SPEAKER, MEETING)
	_give_bag()
	await PrologueScene.ceremony_done(get_tree())
	await PrologueScene.say(get_tree(), SPEAKER, TIPS)
	_finish()


func _give_bag() -> void:
	var run := Services.run()
	if run == null:
		return
	run.inventory["max_slots"] = maxi(bag_slots, int(run.inventory.get("max_slots", 0)))
	run.inventory_changed.emit({})
	var card := BAG_CARD.duplicate()
	card["how"] = "Open it with %s" % _menu_key()
	card["icon"] = SheetSprite.load_picture(SATCHEL_ICON)
	if AbilityCeremony.enabled(get_tree()):
		AbilityCeremony.request_entry(get_tree(), card)
	else:
		var feel := Services.feel()
		if feel != null and _player != null:
			feel.floating_text(_player.call(&"get_centre") - Vector2(0.0, 60.0), "%s: %d pockets" % [card["name"], bag_slots], &"green", true)


## The prologue is over: saving again, Slimeshire's banner, Plop goes home.
func _finish() -> void:
	var run := Services.run()
	var shell := Services.shell()
	if shell != null:
		shell.show_area_title(AreaTitles.area_name(REGION_WORLD), AreaTitles.title_color(REGION_WORLD))
	if _mark != null:
		_mark.queue_free()
		_mark = null
	await _return_plop_home()
	if _release.is_valid():
		_release.call()
	_release = Callable()
	if _plop != null and is_instance_valid(_plop) and _plop.has_method(&"configure_wander"):
		var world := Services.world()
		var record: Dictionary = world.npc_wander_area(str(_plop.call(&"get_instance_id_key"))) if world != null else {}
		_plop.call(&"configure_wander", record.get("perimeter", {}))
	_holding = false
	set_physics_process(false)
	PrologueState.finish(run)
	if run != null:
		run.schedule_autosave()


func _find_plop() -> Node:
	for node: Node in get_tree().get_nodes_in_group(NPC_GROUP):
		if str(node.get(&"npc_definition_id")) == PLOP_DEFINITION:
			return node
	return null


func _show_mark() -> void:
	_mark = Label.new()
	_mark.name = "PlopMark"
	_mark.text = MARK_TEXT
	_mark.add_theme_font_size_override(&"font_size", MARK_SIZE)
	_mark.add_theme_color_override(&"font_color", MARK_COLOR)
	_mark.add_theme_color_override(&"font_outline_color", Color(0.15, 0.08, 0.02))
	_mark.add_theme_constant_override(&"outline_size", 6)
	_mark.z_index = 2
	add_child(_mark)


## The kind of mark the NPC quest markers (game/ui/npc_quest_markers.gd) show over Plop ("" none).
func _quest_mark_kind() -> String:
	var main := get_tree().get_first_node_in_group(&"world_main")
	var markers: Variant = main.get(&"quest_markers") if main != null else null
	if not is_instance_valid(markers) or _plop == null or not _plop.has_method(&"get_instance_id_key"):
		return ""
	return str((markers as Object).call(&"kind_for", str(_plop.call(&"get_instance_id_key"))))


static func _menu_key() -> String:
	return ControlLabels.control_label(&"menu")


func _return_plop_home() -> void:
	if not is_instance_valid(_plop):
		return
	var body := _plop.get(&"body") as Node2D
	if not is_instance_valid(body):
		return
	var fade := create_tween()
	fade.tween_property(body, "modulate:a", 0.0, home_fade_ms / 1000.0)
	await fade.finished
	if not is_instance_valid(body):
		return
	body.global_position = _home_position
	body.reset_physics_interpolation()
	_track_plop(body as CharacterBody2D)
	var appear := create_tween()
	appear.tween_property(body, "modulate", _home_modulate, home_fade_ms / 1000.0)
	await appear.finished


func _track_plop(body: CharacterBody2D) -> void:
	var world := Services.world()
	if world != null and world.elevation != null:
		world.elevation.track(body)
