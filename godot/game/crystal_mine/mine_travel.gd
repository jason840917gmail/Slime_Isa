extends RefCounted
## A short trip inside the Crystal Mine's world (docs/godot/DUNGEONS.md "The Crystal Mine (built)"):
## the mine cart's ride and the ore lift move the slime to another spot of the same world behind a
## fade, as a Zelda screen change: the slime is held, the screen fades to black, the slime is put at
## the other end (its level taken from the ground there), the camera snaps to it, and the screen
## fades back in. Nothing else in the world is rebuilt, so its enemies and doors stay as they are.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const AreaTravel := preload("res://game/world/area_travel.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

## The fade's layer (AreaTravel's, above the world, below the HUD), and its times (real time).
const FADE_LAYER := 5
const FADE_OUT_MS := 260.0
const HOLD_MS := 220.0
const FADE_IN_MS := 300.0


## Moves the slime's centre to `centre` (facing `facing`) behind a fade; `cue` plays as it leaves,
## `arrived` is called once it is there (before the fade in). False when there is no slime.
static func warp(centre: Vector2, facing: Vector2, cue: StringName = &"", arrived: Callable = Callable()) -> bool:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return false
	var tree := player.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	player.call(&"stop_movement")
	player.call(&"suppress_movement", FADE_OUT_MS + HOLD_MS + FADE_IN_MS + 200.0)
	if cue != &"":
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(cue)
	AreaTravel.fade(parent, FADE_LAYER, 0.0, 1.0, FADE_OUT_MS, func() -> void:
		_arrive(player, centre, facing)
		if arrived.is_valid():
			arrived.call()
		var hold := tree.create_timer(HOLD_MS / 1000.0, true)
		hold.timeout.connect(func() -> void: AreaTravel.fade(parent, FADE_LAYER, 1.0, 0.0, FADE_IN_MS))
	)
	return true


## Puts the slime at `centre` at once (no fade): teleport, its level from the ground there, the camera
## on it. The tests call it too.
static func place(player: Node, centre: Vector2, facing: Vector2) -> void:
	_arrive(player, centre, facing)


static func _arrive(player: Node, centre: Vector2, facing: Vector2) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.call(&"teleport", centre)
	var world := Services.world()
	var body := player.get(&"body") as CharacterBody2D
	if world != null and world.elevation != null and body != null:
		world.elevation.track(body)
	if facing != Vector2.ZERO:
		player.call(&"face", facing)
	# The camera follows the player's root, its CharacterBody2D (main.gd `player_root`).
	var camera: Node = world.camera if world != null else null
	if camera != null and body != null and camera.has_method(&"start_follow"):
		camera.call(&"start_follow", body, true)
