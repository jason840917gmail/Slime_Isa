extends Node
class_name MineCamp
## The smith's camp in his ore cave on the Crystal Caverns' main road (`crystal-caverns-smith-cave`,
## in the peak's south face; roadmap 12.3 and 12.9, the owner's order of 2026-11-20; docs/godot/
## DUNGEONS.md "Outside: the Spiral"): the node `MineCamp` of the cave. It speaks for the smith
## (game/crystal_mine/smith_actor.gd, `smith`).
##
## - **First talk:** he meets the slime and gives it the **Lantern**, the Forge's ember
##   (`RunState.learn_ability("lantern")`: the ceremony plays its card), and in the same visit the
##   **Smith's Crystal** (`mine-crystal`, once: CRYSTAL_FLAG, set only when it fits in the bag; a full
##   bag keeps it with him, a line, and he offers it first at the next talk; not when the Bow is
##   learned already) for
##   his son Pip in Slimeshire, who carves the Bow's rune from it, wood and the Matron's thread (the
##   mine's Chasm needs the Bow). Then the Lantern's first lock: "My ore cart ... Give its lamp a
##   flame." The story flag GIFT_FLAG keeps the gift once.
## - **The cart:** his lamp (`lamp`, candle.gd lit for good: its flag LAMP_FLAG) takes the brake off
##   his cart (game/crystal_mine/smith_cart.gd), a one-way ride down to the mine's gate in G4's yard,
##   where one flame on the gate's brazier (its flag GATE_FLAG) opens the gate for good. He calls out
##   when the lamp catches.
## - **Later talks:** while the lamp is cold, the hint again; then "ride it down"; until the Bow is
##   learned, the crystal's errand again; then tips.
## - **After the Colossus falls** (`chapter-3-complete`, or RunState `defeated_boss_ids`): he stays
##   in his cave, his mine his own again (owner, 2026-11-20: Pip keeps the Workshop and the Forge).
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const PrologueScene := preload("res://game/prologue/prologue_scene.gd")
const SmithActorScript := preload("res://game/crystal_mine/smith_actor.gd")

const SPEAKER := "The smith"
const LANTERN := "lantern"
const COLOSSUS := "crystal-colossus"
## The flag the Colossus's fall sets (game-constants.json `story.bossFlags`).
const COLOSSUS_FLAG := "chapter-3-complete"
const GIFT_FLAG := "mine-camp.lantern-given"
const CRYSTAL_FLAG := "mine-camp.crystal-given"
const CRYSTAL_ITEM := "mine-crystal"
const BOW := "bow"
## candle.gd `candle_flag` of his lamp (instance id `smith-cave-lamp`) and of the gate's brazier in
## G4 (instance id `mine-gate-brazier`), both lit for good.
const LAMP_FLAG := "candle-lit.smith-cave-lamp"
const GATE_FLAG := "candle-lit.mine-gate-brazier"
const CUE_HELLO := &"NpcBlip"
const CALL_RISE := 120.0
const CALL_MS := 2600.0
const LAMP_POLL_MS := 250.0

const MEETING: Array[String] = [
	"Well now! A slime, all the way out here? Over the webs and the falling slabs, too. Ha!",
	"I'm the smith. Slimeshire's smith, before the worms came. My boy Pip still waits for me, I know. Tell him his dad is fine.",
	"My mine is back by the gate where you came in. Or it was, until the Crystal Colossus moved in. He walled my deep shafts with his black crystal and put out my lamps, every one. So I camp out here, in my old ore cave.",
	"His crystal shrinks from fire light. So you will want a light. Here: the Forge's own ember, in my old lantern. It never goes out.",
]
const CRYSTAL: Array[String] = [
	"Past the dark in there is my chasm. The bridge answers to a lens on the far side, and nobody can reach it from here. That wants a bow.",
	"Here: the clearest crystal this mine ever gave me. I was saving it for something special.",
	"Take it to my boy Pip, in Slimeshire. He has my hands. With this, a little wood and a string strong as wire, he can carve you a bow rune.",
]
const TEACH: Array[String] = [
	"My ore cart runs down the old line to the gate. Its lamp went out with the others. Give it a flame, and the cart is yours.",
]
const RIDE: Array[String] = [
	"Off you go! The cart takes you down to the gate. Its lamp cups want a flame too.",
]
const CRYSTAL_AGAIN: Array[String] = [
	"Take that crystal to Pip, in Slimeshire. Some wood and a string strong as wire, and he'll carve you the rune.",
]
## His crystal does not fit in the bag: he keeps it until the slime comes back with room.
const CRYSTAL_BAG_FULL: Array[String] = [
	"I have a crystal for my boy Pip too, but your bag is stuffed full. Make some room and come back for it.",
]
const AFTER_COLOSSUS: Array[String] = [
	"Ha! Rubble, the lot of him. My lamps burn again, and the mine is mine.",
	"I'll stay and get her working. Tell Pip his dad is proud of him, keeping the Workshop going at his age!",
]
const TIPS: Array[String] = [
	"Rest by the fire when you need to. My cot is yours, and this cave is out of his reach.",
	"Down in the Great Shaft, the ore lift runs once its crank is worked from below.",
]
const LAMP_CALL := "That's it! The brake's off. Ride her down."

@export var smith: SmithActorScript
## His lamp by the cart (candle.gd): he calls out when it catches.
@export var lamp: Node2D

var _talking := false
var _lamp_was_lit := false
var _next_poll_ms := 0.0


func _ready() -> void:
	_lamp_was_lit = is_lamp_lit()
	if smith == null:
		return
	smith.talked.connect(_on_talked)


func is_lantern_given() -> bool:
	var run := Services.run()
	return run != null and run.has_flag(GIFT_FLAG)


func is_lamp_lit() -> bool:
	var run := Services.run()
	return run != null and run.has_flag(LAMP_FLAG)


## The mine's gate in G4 opens for good when its brazier burns (another world: read its flag).
func is_gate_open() -> bool:
	var run := Services.run()
	return run != null and run.has_flag(GATE_FLAG)


func _physics_process(_delta: float) -> void:
	if _lamp_was_lit:
		return
	var now := float(Time.get_ticks_msec())
	if now < _next_poll_ms:
		return
	_next_poll_ms = now + LAMP_POLL_MS
	if is_lamp_lit():
		_lamp_was_lit = true
		_on_lamp_lit()


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
	var has_bow := run != null and run.has_learned_ability(BOW)
	if not is_lantern_given():
		await PrologueScene.say(get_tree(), SPEAKER, MEETING)
		smith.hold_pose(SmithActorScript.FRAME_LANTERN)
		give_lantern()
		await PrologueScene.ceremony_done(get_tree())
		if not has_bow:
			await _offer_crystal()
		smith.hold_pose(SmithActorScript.FRAME_POINT)
		await PrologueScene.say(get_tree(), SPEAKER, TEACH)
	elif _colossus_beaten():
		await PrologueScene.say(get_tree(), SPEAKER, AFTER_COLOSSUS)
	elif not has_bow and not is_crystal_given():
		# A full bag kept it last time: offered again before anything else.
		await _offer_crystal()
	elif not is_lamp_lit():
		smith.hold_pose(SmithActorScript.FRAME_POINT)
		await PrologueScene.say(get_tree(), SPEAKER, TEACH)
	elif not is_gate_open():
		smith.hold_pose(SmithActorScript.FRAME_POINT)
		await PrologueScene.say(get_tree(), SPEAKER, RIDE)
	elif not has_bow:
		smith.hold_pose(SmithActorScript.FRAME_POINT)
		await PrologueScene.say(get_tree(), SPEAKER, CRYSTAL_AGAIN)
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


func is_crystal_given() -> bool:
	var run := Services.run()
	return run != null and run.has_flag(CRYSTAL_FLAG)


## The Smith's Crystal into the bag, once (for Pip's bow rune). True when it was given now. A full
## bag keeps it with him (no flag): he says so and offers it again at the next talk.
func give_crystal() -> bool:
	var run := Services.run()
	if run == null or run.has_flag(CRYSTAL_FLAG):
		return false
	if run.add_item(CRYSTAL_ITEM, 1) <= 0:
		return false
	run.set_flag(CRYSTAL_FLAG)
	return true


## The crystal's errand: given with its lines, or the full-bag line when it does not fit.
func _offer_crystal() -> void:
	smith.hold_pose(SmithActorScript.FRAME_LANTERN)
	if give_crystal():
		await PrologueScene.say(get_tree(), SPEAKER, CRYSTAL)
	elif not is_crystal_given():
		await PrologueScene.say(get_tree(), SPEAKER, CRYSTAL_BAG_FULL)


func _on_lamp_lit() -> void:
	var feel := Services.feel()
	if feel != null and smith != null and smith.visible:
		feel.floating_text(smith.global_position - Vector2(0.0, CALL_RISE), LAMP_CALL, &"white", false, CALL_MS)


func _face_slime() -> void:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player != null and is_instance_valid(player):
		smith.face((player.call(&"get_centre") as Vector2).x - smith.global_position.x)


func _colossus_beaten() -> bool:
	var run := Services.run()
	return run != null and (run.has_flag(COLOSSUS_FLAG) or COLOSSUS in (run.world.get("defeated_boss_ids", []) as Array))
