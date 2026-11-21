extends "res://game/crystal_mine/mine_cart.gd"
class_name SmithCart
## The smith's ore cart in his cave (`crystal-caverns-smith-cave`; roadmap 12.9, the owner's order of
## 2026-11-20): the Lantern's first lock is his lamp beside it (candle.gd lit for good, its story flag
## `lamp_flag`); lit, the cart rides once, one way, down the old line to the mine's gate: the screen
## fades and the slime comes out in G4's yard at the door `target_door_id` (main.gd `request_exit`, as
## a door). The yard's station (a MineCartStation with `cart_flag` = `ridden_flag`) shows the cart
## there from then on and never sends it back. Here the cart is gone once ridden: `empty_text`.
##
## Owner: dungeons (the Crystal Mine).

const MAIN_GROUP := &"world_main"

## The world the line ends in and the door (an arrival point) the slime comes out at.
@export var target_area_id: String = "crystal-caverns-g4"
@export var target_door_id: String = "yard-cart"
## The lamp's flag (candle.gd `candle_flag`): the cart's brake comes off once it burns.
@export var lamp_flag: String = "candle-lit.smith-cave-lamp"
## Set when the cart has gone down the line (the yard's station reads it).
@export var ridden_flag: String = "smith-cart.ridden"
@export var locked_text: String = "The brake is chained. The lamp by the cart is cold."


func has_cart() -> bool:
	var run := Services.run()
	return run == null or not run.has_flag(ridden_flag)


## No partner in this world: the ride leaves it.
func can_use() -> bool:
	return has_cart()


## Rides down to the gate once the lamp burns; else says why not. False when it did not ride.
func use() -> bool:
	var run := Services.run()
	if not has_cart() or run == null:
		return false
	var feel := Services.feel()
	if not run.has_flag(lamp_flag):
		if feel != null:
			feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), locked_text, &"white", false, TEXT_MS)
		return false
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if main == null or not main.has_method(&"request_exit"):
		return false
	var world := Services.world()
	var result: Dictionary = main.call(&"request_exit", {"map_id": world.map_id() if world != null else "",
		"exit_id": "smith-cart", "target_area_id": target_area_id, "entry": "", "target_door_id": target_door_id,
		"entry_marker": "", "gate": {}, "transition": "fade", "door_side": "", "lead_ms": 0.0})
	if str(result.get("status", "")) != "queued":
		return false
	run.set_flag(ridden_flag)
	if feel != null:
		feel.audio_cue(CUE_RIDE)
	_show()
	return true
