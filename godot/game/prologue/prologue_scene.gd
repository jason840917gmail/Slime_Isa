extends RefCounted
## What the prologue's scripted scenes share (game/prologue/prologue_director.gd, town_edge_meeting.gd;
## docs/godot/PROLOGUE.md): a line in the dialogue box, a wait on game time, waiting out the ceremony,
## and holding the slime still. Static helpers; the waits are coroutines (await them).
##
## Owner: prologue.

const DIALOGUE_GROUP := &"dialogue_box"
const CEREMONY_NODE := "AbilityCeremony"
## A held slime's movement stays suppressed this long after the last hold step (ms).
const HOLD_STEP_MS := 120.0


## Shows `pages` in the dialogue box as `speaker` and waits until it closes (at once without a box).
static func say(tree: SceneTree, speaker: String, pages: Array[String]) -> void:
	if tree == null:
		return
	var box := tree.get_first_node_in_group(DIALOGUE_GROUP)
	if box == null or not box.has_method(&"open"):
		return
	box.call(&"open", {"speaker": speaker, "pages": pages.duplicate()})
	if bool(box.call(&"is_open")):
		await box.closed


## Waits `ms` of game time (it stops while the game is paused: a window, a hit-stop, the ceremony).
static func wait(tree: SceneTree, ms: float) -> void:
	if tree == null:
		return
	await tree.create_timer(maxf(0.0, ms) / 1000.0, false, true).timeout


## Waits until no ceremony plays or waits for its turn (game/ui/ceremony/ability_ceremony.gd).
static func ceremony_done(tree: SceneTree) -> void:
	if tree == null:
		return
	await tree.process_frame
	while true:
		var ceremony := tree.root.get_node_or_null(CEREMONY_NODE)
		if ceremony == null or (not bool(ceremony.call(&"is_playing")) and int(ceremony.call(&"waiting")) == 0):
			return
		await tree.process_frame


## One physics step of holding the slime still: no walk, no buffered input.
static func hold(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.call(&"stop_movement")
	player.call(&"clear_input")
	player.call(&"suppress_movement", HOLD_STEP_MS)
