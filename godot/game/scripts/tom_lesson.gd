extends Node
class_name TomLesson
## Tom's Goo Bomb lesson (owner, 2026-10-16, questions 95 and 113; the plan of 2026-11-19, step A3):
## the node `TomLesson` of `object.tom-web` (game/scenes/objects/tom-web.tscn). When the web tears
## (game/scripts/tom_web.gd `torn`), Tom stands by the torn strands (`tom`, hidden until then), the
## slime is held still (PrologueScene.hold every physics step) and he speaks: he got caught studying
## the webs, the Matron's brood wrapped him up, thanks. Then he teaches the **Goo Bomb** right there
## (`RunState.learn_ability("goo-bombs")`: QuestNotifications plays its ceremony card), sets
## TAUGHT_FLAG, points at the cracked wall in the ledge beside his hollow (gloop-forest-e3
## `RiverRoads/tom-crack`, game/scripts/cracked_wall.gd: blown, the old raft landing, a ride back to
## the camp's jetty) and fades away
## to Mossy's camp, where he waits (gloop-forest-e4 `camp/tom-at-camp`, shown on `tom-freed`).
##
## A run that tore the web without the lesson (a save from before 2026-11-19, or a game closed during
## it) learns it from Tom at the camp instead: his `goo-bomb-lesson` talk in npc-definitions.json.
## Timings are this node's properties.
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")
const PrologueScene := preload("res://game/prologue/prologue_scene.gd")

const SPEAKER := "Tom"
const GOO_BOMBS := "goo-bombs"
## Set as he teaches (the camp's talk then skips the lesson).
const TAUGHT_FLAG := "tom.goo-bomb-taught"
const CUE_HELLO := &"NpcBlip"

const THANKS: Array[String] = [
	"Phew! Free at last! Thank you, thank you!",
	"I came to study their webs up close. A bit too close: the Matron's brood wrapped me up before I could blink.",
	"You cut me loose, so here's my best trick. Brew a little bomb of goo inside you, nice and slow... then spit it out!",
]
const AFTER: Array[String] = [
	"See the cracked rock in that ledge? One bomb, and the old raft takes you back to camp.",
	"Mind the blast, though! I'm off to Mossy's camp. Come and find me there.",
]

## The web whose tearing starts the lesson (its TomWebScript).
@export var web: Node
## Tom as he stands by the torn web (hidden outside the lesson).
@export var tom: CanvasItem
## Tom fades in this long after the web tears, rising `hop_px` as he does (ms, real time: a look).
@export var appear_ms: float = 450.0
@export var hop_px: float = 10.0
## The pause before he speaks (game time).
@export var speak_after_ms: float = 300.0
## He fades away this long once the lesson is over (ms, real time).
@export var leave_ms: float = 600.0

var _player: Node
var _holding := false
var _playing := false
var _tom_rest := Vector2.ZERO


func _ready() -> void:
	if tom != null:
		tom.visible = false
		if tom is Node2D:
			_tom_rest = (tom as Node2D).position
	set_physics_process(false)
	if web != null and web.has_signal(&"torn") and not web.is_connected(&"torn", _on_torn):
		web.connect(&"torn", _on_torn)


func _physics_process(_delta: float) -> void:
	if _holding:
		PrologueScene.hold(_player)


## True while the lesson plays.
func is_playing() -> bool:
	return _playing


func _on_torn(_payload: Dictionary) -> void:
	var run := Services.run()
	if _playing or run == null or run.has_flag(TAUGHT_FLAG):
		return
	_lesson()


## The lesson (a coroutine).
func _lesson() -> void:
	_playing = true
	var world := Services.world()
	_player = world.player if world != null else null
	_holding = true
	set_physics_process(true)
	_show_tom()
	await PrologueScene.wait(get_tree(), speak_after_ms)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HELLO)
	await PrologueScene.say(get_tree(), SPEAKER, THANKS)
	teach()
	await PrologueScene.ceremony_done(get_tree())
	await PrologueScene.say(get_tree(), SPEAKER, AFTER)
	_holding = false
	set_physics_process(false)
	_hide_tom()
	_playing = false


## The lesson's gift: TAUGHT_FLAG, then the Goo Bomb (its ceremony). True when it was new.
func teach() -> bool:
	var run := Services.run()
	if run == null:
		return false
	run.set_flag(TAUGHT_FLAG)
	return run.learn_ability(GOO_BOMBS)


func _show_tom() -> void:
	if tom == null:
		return
	tom.visible = true
	tom.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(tom, ^"modulate:a", 1.0, appear_ms / 1000.0)
	if tom is Node2D:
		(tom as Node2D).position = _tom_rest + Vector2(0.0, hop_px)
		tween.parallel().tween_property(tom, ^"position", _tom_rest, appear_ms / 1000.0) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_tom() -> void:
	if tom == null:
		return
	var tween := create_tween()
	tween.tween_property(tom, ^"modulate:a", 0.0, leave_ms / 1000.0)
	tween.tween_callback(func() -> void: tom.visible = false)
