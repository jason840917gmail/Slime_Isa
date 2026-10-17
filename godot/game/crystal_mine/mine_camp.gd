extends Node
class_name MineCamp
## The smith's mine camp outside the Crystal Mine (G4, `crystal-caverns-g4`; roadmap 12.3; the design's
## "Outside: the smith's mine camp"; docs/godot/DUNGEONS.md "The Crystal Mine (built)"): the node
## `MineCamp` of the camp the tool tools/build_mine_outside.gd lays in G4. It speaks for the smith
## (game/crystal_mine/smith_actor.gd, `smith`).
##
## - **First talk:** he meets the slime and gives it the **Lantern**, the Forge's ember
##   (`RunState.learn_ability("lantern")`: the ceremony plays its card), then teaches its first lock:
##   "The lamp by the gate. Give it a flame." The story flag GIFT_FLAG keeps the gift once.
## - **The gate:** the mine's gate (game/crystal_mine/lantern_gate.gd, `gate`) and the cold brazier
##   beside it (`brazier`, candle.gd lit for good, its group's `gate_id` the gate's): one flame and
##   the gate opens for good. He calls out when it does.
## - **Later talks:** while the gate is shut, the hint again; once it is open, he sends the slime to
##   Burr (question 134, naming no key) once, then his tips.
## - **After the Colossus falls** (RunState `defeated_boss_ids`): he has gone home to Slimeshire, so
##   he is not at the camp (his place in Slimeshire is the village's work, roadmap 12.3).
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const PrologueScene := preload("res://game/prologue/prologue_scene.gd")
const SmithActorScript := preload("res://game/crystal_mine/smith_actor.gd")

const SPEAKER := "The smith"
const LANTERN := "lantern"
const COLOSSUS := "crystal-colossus"
const GIFT_FLAG := "mine-camp.lantern-given"
const BURR_FLAG := "mine-camp.sent-to-burr"
const CUE_HELLO := &"NpcBlip"
const CALL_RISE := 120.0
const CALL_MS := 2600.0

const MEETING: Array[String] = [
	"Well now! A slime, all the way out here? Through the webs, too. Ha!",
	"I'm the smith. Slimeshire's smith, before the worms came. My boy Pip still waits for me, I know. Tell him his dad is fine.",
	"This is my mine. Or it was, until the Crystal Colossus moved in. He walled my deep shafts with his black crystal and put out my lamps, every one.",
	"His crystal shrinks from fire light. So you will want a light. Here: the Forge's own ember, in my old lantern. It never goes out.",
]
const TEACH: Array[String] = [
	"The lamp by the gate. Give it a flame.",
]
const BURR: Array[String] = [
	"The Colossus walled my deep shafts with his crystal. Past the dark is my chasm. The bridge answers to a lens on the far side, and nobody can reach it from here.",
	"Burr, the gatekeeper in the West village, is building something that might. He has been asking after you.",
]
const TIPS: Array[String] = [
	"Rest by the fire when you need to. My cot is yours, and the camp is out of his reach.",
	"Down in the Great Shaft, the ore lift runs once its crank is worked from below.",
]
const GATE_CALL := "That's it! Mind the dark in there."

@export var smith: SmithActorScript
@export var gate: Node2D
@export var brazier: Node2D

var _talking := false


func _ready() -> void:
	if smith == null:
		return
	if _colossus_beaten():
		# Home in Slimeshire since the Colossus fell.
		smith.visible = false
		smith.process_mode = Node.PROCESS_MODE_DISABLED
		var body := smith.body
		if body != null:
			body.collision_layer = 0
		return
	smith.talked.connect(_on_talked)
	if gate != null and gate.has_signal(&"opened"):
		gate.connect(&"opened", _on_gate_opened)


func is_lantern_given() -> bool:
	var run := Services.run()
	return run != null and run.has_flag(GIFT_FLAG)


func is_gate_open() -> bool:
	return gate != null and bool(gate.call(&"is_open"))


func _on_talked(_payload: Dictionary) -> void:
	if _talking:
		return
	_talking = true
	smith.set_busy(true)
	_face_slime()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HELLO)
	var run := Services.run()
	if not is_lantern_given():
		await PrologueScene.say(get_tree(), SPEAKER, MEETING)
		smith.hold_pose(SmithActorScript.FRAME_LANTERN)
		give_lantern()
		await PrologueScene.ceremony_done(get_tree())
		smith.hold_pose(SmithActorScript.FRAME_POINT)
		await PrologueScene.say(get_tree(), SPEAKER, TEACH)
	elif not is_gate_open():
		smith.hold_pose(SmithActorScript.FRAME_POINT)
		await PrologueScene.say(get_tree(), SPEAKER, TEACH)
	elif run != null and not run.has_flag(BURR_FLAG):
		run.set_flag(BURR_FLAG)
		await PrologueScene.say(get_tree(), SPEAKER, BURR)
	else:
		await PrologueScene.say(get_tree(), SPEAKER, TIPS)
	if is_instance_valid(smith):
		smith.release_pose()
		smith.set_busy(false)
	_talking = false


## The gift: the Lantern learned (its ceremony), once. True when it was given now.
func give_lantern() -> bool:
	var run := Services.run()
	if run == null or run.has_flag(GIFT_FLAG):
		return false
	run.set_flag(GIFT_FLAG)
	run.learn_ability(LANTERN)
	return true


func _on_gate_opened(_payload: Variant = null) -> void:
	var feel := Services.feel()
	if feel != null and smith != null and smith.visible:
		feel.floating_text(smith.global_position - Vector2(0.0, CALL_RISE), GATE_CALL, &"white", false, CALL_MS)


func _face_slime() -> void:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player != null and is_instance_valid(player):
		smith.face((player.call(&"get_centre") as Vector2).x - smith.global_position.x)


func _colossus_beaten() -> bool:
	var run := Services.run()
	return run != null and COLOSSUS in (run.world.get("defeated_boss_ids", []) as Array)
