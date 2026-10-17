extends Node2D
## Fatty's Lair's director (the `LairDirector` node of world.fatty-lair; docs/godot/DUNGEONS.md
## "Fatty's Lair (built)"; docs/design/2026-10-16-dungeon-fattys-lair.md): what in the Lair is story,
## not a lock of its own.
##
## - **Burr's cell** (question 134): Burr (`burr`, game/fattys_lair/burr_actor.gd) waits behind his
##   cell door (`cell_door`: the dungeon kit's door with two keyholes, a node with `is_open()` and an
##   `opened` signal). The first time the slime comes into the Pit Hall (`call_rect`) he calls out
##   (once, the flag FLAG_CALLED); later he calls the short line over his hatch. When his door opens
##   he is freed (`free_burr`): his lines, he winds the Inner Stair's hatch up (`hatch`,
##   game/scripts/stair_hatch.gd), the only way down to the Deep, and walks out (`burr_exit`). The
##   flag FLAG_FREED keeps him gone; after Fatty he waits at the bolt-hole's mouth in daylight (the
##   overworld's side, built with level-1-d4).
## - **Fatty One Eye** (`camp`, game/scripts/boss_camp.gd): when the camp spawns him, his phase two is
##   turned on (`phase_two`: game/scripts/fatty.gd `configure_phase_two`) and his landings drop light
##   mud clods (`clods_requested`): at `clod_spots` (the children of that node, ground points), the
##   free ones nearest the slime, after a shadow of `clod_shadow_ms`; a clod landing on the slime hurts
##   (`clod_damage`); then it lies there as a liftable mud ball (kind `mud-ball`), at most `max_clods`
##   at once. His phase two is the Heavy skin's exam (a Heavy Roll knocks him off balance: fatty.gd).
##   Beaten, he never comes back (the camp stops for good once `defeated_boss_ids` has him): the
##   boss heart (`heart`) shows. The Pearl is no longer his prize: it lies in the Larder, guarded by
##   the Big Squint (since 2026-10-17, the Pearl before the boss), and shows by its own `boss_id`.
##   The arena's shutters (the dungeon kit's game/dungeon/shutter.gd with `boss_shutter_fight` as
##   their `fight_id`) shut while he lives and open when he falls. His fall is kept in the dungeon's
##   record too (DungeonState mark_boss_beaten). Until then the director, standing in the arena, is
##   the compass's boss mark (group `dungeon_map_mark`, `mark` "boss").
## - **Blocked gaps** (`blocked_gaps`: the map nook): a Node2D holding light things (liftables) and a
##   `Barrier` body; once every light thing is taken the barrier goes and the secret jingle plays.
## - **Heavy blocks reset with their room** (the guide's no-softlock rule): every heavy block and
##   statue in the world (group `heavy_blocks`) is put back where it stood when the world was built
##   each time the slime walks into the room it started in (the Dungeon node's `room_entered`), as
##   the room's enemies and pots come back. A statue pushed into a corner never blocks the way.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PrologueScene := preload("res://game/prologue/prologue_scene.gd")
const ClodShadow := preload("res://game/fattys_lair/clod_shadow.gd")
const BurrActor := preload("res://game/fattys_lair/burr_actor.gd")

const GROUP := &"lair_director"
const FLAG_CALLED := "fatty-lair.burr-called"
const FLAG_FREED := "fatty-lair.burr-freed"
const SPEAKER := "Burr"
const LIFTABLE_SCENE := "res://game/scenes/objects/liftable.tscn"
const CLOD_KIND := "mud-ball"
const CLOD_GROUP := &"fatty_lair_clod"
const CLOD_HIT_RADIUS := 34.0
const CLOD_KNOCKBACK := 160.0
const CLOD_SPOT_FREE_PX := 40.0
const CUE_CLOD := &"DropPop"
const SHORT_CALL_EVERY_MS := 6000
const SHUTTER_GROUP := &"shutter"
## game/dungeon/dungeon_map_draw.gd MARK_GROUP: the compass marks this node's spot.
const MAP_MARK_GROUP := &"dungeon_map_mark"
const LIFTABLE_SCRIPT := preload("res://game/scripts/liftable.gd")
const CUE_SECRET := &"SecretFound"
const BLOCK_GROUP := &"heavy_blocks"
const SoftGlow := preload("res://game/prologue/soft_glow.gd")
## His fall's stream of light into the Pearl (presentation): the sparkles, their step, their arc.
const POWER_PARTICLES := &"loot-sparkle"
const CUE_POWER := &"SecretFound"
const POWER_SPARKS := 12
const POWER_STEP_MS := 70.0
const POWER_ARC_PX := 60.0
const POWER_GLOW_S := 1.2
## A block is put back only when the slime's body is this far from its start (world units).
const BLOCK_RESET_CLEAR_PX := 72.0

const CALL_LINES: Array[String] = [
	"Is someone there? ... A slime? Out here, in Fatty's burrow?",
	"The worms took my keys to their dens, one east and one west. Two locks: they wanted me to stay.",
]
const SHORT_CALL := "Two keys: the dens east and west!"
const FREED_LINES: Array[String] = [
	"Both keys! You got me out. I am Burr, the gatekeeper of this old fort.",
	"My boy taught you the trick, didn't he? Curl up and roll. Good lad.",
	"This hatch is the Inner Stair. The worms never learned the trick of its winch. There.",
	"Mind the bones below: my old comrades of the Thorn Guard. Gorge's lot raised them to stand guard.",
	"I'll wait for you outside, by the fort's old bolt-hole, if it still opens. Then come and see me at home.",
]

## Burr freed. Payload: {}.
signal burr_freed(payload: Dictionary)

@export var burr: NodePath
## Where Burr walks out: through `burr_door` (out of his cell's doorway) first, then `burr_exit`.
@export var burr_door: NodePath
@export var burr_exit: NodePath
@export var cell_door: NodePath
@export var hatch: NodePath
## Where Burr calls out from his cell (the Pit Hall, world units).
@export var call_rect: Rect2 = Rect2()
@export var camp: NodePath
## A Node2D whose children are the clods' ground points.
@export var clod_spots: NodePath
@export var clod_shadow_ms: float = 600.0
@export var clod_damage: float = 12.0
@export var max_clods: int = 4
## Fatty's phase two (game/scripts/fatty.gd `configure_phase_two`: the `phase_two_*` exports' names without the prefix).
@export var phase_two: Dictionary = {}
@export var heart: NodePath
@export var boss_id: String = "fatty-one-eye"
## The Larder's Pearl and the glint over its altar (seen from the door all through the Big Squint's
## fight): the glint goes once the Pearl is taken.
@export var pearl: NodePath
@export var pearl_glint: NodePath
## The arena's shutters' `fight_id`.
@export var boss_shutter_fight: String = ""
## Gaps choked with light things (Node2Ds with liftables and a `Barrier` child).
@export var blocked_gaps: Array[NodePath] = []

## Read by the dungeon map (dungeon_map_draw.gd `boss_points`).
var mark: String = "boss"
var _freeing := false
var _was_inside := false
var _next_short_call_ms := 0
var _bound_boss: Node = null
## Every heavy block's start: [{"block": Node2D, "at": Vector2 (global)}].
var _block_starts: Array[Dictionary] = []


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var run := Services.run()
	if run != null and run.has_flag(FLAG_FREED):
		_remove_burr()
	var door := get_node_or_null(cell_door)
	if door != null and door.has_signal(&"opened"):
		door.connect(&"opened", func(_payload: Variant = null) -> void: free_burr())
	var camp_node := get_node_or_null(camp)
	if camp_node != null:
		if _boss_beaten():
			camp_node.set_physics_process(false)
		elif camp_node.has_signal(&"boss_engaged"):
			camp_node.connect(&"boss_engaged", _on_boss_engaged)
			camp_node.connect(&"boss_defeated", _on_boss_defeated)
			camp_node.connect(&"boss_disengaged", func(payload: Dictionary) -> void:
				if not bool(payload.get("defeated", false)):
					_set_boss_shutters(false))
	_show_heart(_boss_beaten())
	if not _boss_beaten():
		add_to_group(MAP_MARK_GROUP)
	_snapshot_blocks.call_deferred()
	var prize := get_node_or_null(pearl)
	if prize != null and prize.has_signal(&"taken"):
		if prize.has_method(&"is_taken") and bool(prize.call(&"is_taken")):
			_drop_glint()
		else:
			prize.connect(&"taken", func(_payload: Dictionary) -> void: _drop_glint())


func is_burr_freed() -> bool:
	var run := Services.run()
	return run != null and run.has_flag(FLAG_FREED)


func _physics_process(_delta: float) -> void:
	_watch_blocked_gaps()
	if is_burr_freed() or _freeing:
		return
	var door := get_node_or_null(cell_door)
	if door != null and door.has_method(&"is_open") and bool(door.call(&"is_open")):
		free_burr()
		return
	var world := Services.world()
	if world == null or world.player == null or not is_instance_valid(world.player) or call_rect.size == Vector2.ZERO:
		return
	var inside := call_rect.has_point(world.player.call(&"get_centre"))
	if inside and not _was_inside:
		_call_out()
	_was_inside = inside


## Burr calls from his cell: the full call the first time, the short line after.
func _call_out() -> void:
	var run := Services.run()
	var actor := get_node_or_null(burr) as BurrActor
	if run != null and not run.has_flag(FLAG_CALLED):
		run.set_flag(FLAG_CALLED)
		if actor != null:
			actor.wave(1.0)
		await PrologueScene.say(get_tree(), SPEAKER, CALL_LINES)
		return
	var now := Time.get_ticks_msec()
	if now < _next_short_call_ms or actor == null:
		return
	_next_short_call_ms = now + SHORT_CALL_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(actor.global_position - Vector2(0.0, 90.0), SHORT_CALL, &"white", false, 2400.0)


## The freeing: his lines, the hatch, his walk out (once).
func free_burr() -> void:
	if _freeing or is_burr_freed():
		return
	_freeing = true
	var run := Services.run()
	var actor := get_node_or_null(burr) as BurrActor
	var world := Services.world()
	var player: Node = world.player if world != null else null
	var hold := func() -> void: PrologueScene.hold(player)
	get_tree().physics_frame.connect(hold)
	if actor != null:
		actor.wave(1.2)
	await PrologueScene.say(get_tree(), SPEAKER, FREED_LINES.slice(0, 3))
	var stair := get_node_or_null(hatch)
	if stair != null:
		stair.call(&"open", true)
	await PrologueScene.wait(get_tree(), 500.0)
	await PrologueScene.say(get_tree(), SPEAKER, FREED_LINES.slice(3))
	if run != null:
		run.set_flag(FLAG_FREED)
	if get_tree().physics_frame.is_connected(hold):
		get_tree().physics_frame.disconnect(hold)
	burr_freed.emit({})
	var door := get_node_or_null(burr_door) as Node2D
	if actor != null and door != null:
		await actor.walk_to(door.global_position, 90.0)
	var exit := get_node_or_null(burr_exit) as Node2D
	if actor != null and exit != null:
		await actor.walk_to(exit.global_position, 90.0)
		await actor.fade_out(0.5)
	_remove_burr()
	_freeing = false


func _remove_burr() -> void:
	var actor := get_node_or_null(burr)
	if actor != null:
		actor.queue_free()


# --- Fatty One Eye --------------------------------------------------------------------------------

## Opens the gaps whose light things are all gone (the barrier goes, the secret jingle).
func _watch_blocked_gaps() -> void:
	for path: NodePath in blocked_gaps:
		var gap := get_node_or_null(path)
		if gap == null:
			continue
		var barrier := gap.get_node_or_null(^"Barrier")
		if barrier == null:
			continue
		var left := false
		for child: Node in gap.get_children():
			if child != barrier and not child.is_queued_for_deletion() and child.get_node_or_null(^"LiftableScript") is LIFTABLE_SCRIPT:
				left = true
				break
		if left:
			continue
		barrier.queue_free()
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_SECRET)


func _set_boss_shutters(shut: bool) -> void:
	# The camp also disengages when the world is freed (its `_exit_tree`): nothing to move then.
	if boss_shutter_fight.is_empty() or not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(SHUTTER_GROUP):
		if str(node.get(&"fight_id")) == boss_shutter_fight:
			node.call(&"shut" if shut else &"open")


func _on_boss_engaged(_payload: Dictionary) -> void:
	_set_boss_shutters(true)
	var camp_node := get_node_or_null(camp)
	if camp_node == null:
		return
	var boss: Object = camp_node.call(&"get_live_boss")
	if boss == null:
		return
	boss.call(&"configure_phase_two", phase_two)
	if boss.has_signal(&"clods_requested") and not boss.is_connected(&"clods_requested", _on_clods_requested):
		boss.connect(&"clods_requested", _on_clods_requested)
	_bound_boss = boss as Node


func _on_boss_defeated(_payload: Dictionary) -> void:
	_set_boss_shutters(false)
	if is_in_group(MAP_MARK_GROUP):
		remove_from_group(MAP_MARK_GROUP)
	DungeonState.mark_boss_beaten(Services.run(), DungeonState.current_id(get_tree()), boss_id)
	var camp_node := get_node_or_null(camp)
	if camp_node != null:
		camp_node.set_physics_process(false)
	_show_heart(true)
	var from := global_position
	if _bound_boss != null and is_instance_valid(_bound_boss) and _bound_boss.has_method(&"get_centre"):
		from = _bound_boss.call(&"get_centre")
	_pour_power(from)


## His fall: the Pearl's power he soaked up pours out through his eye into Pearl 1, which the slime
## carries (the Pearl-inside plan's "why he shrinks"): sparkles running from him to the slime, a
## flash of the Pearl's light on it. Presentation only.
func _pour_power(from: Vector2) -> void:
	var feel := Services.feel()
	var world := Services.world()
	if feel == null or world == null or world.player == null or not is_instance_valid(world.player):
		return
	feel.audio_cue(CUE_POWER)
	for i in POWER_SPARKS:
		if not is_inside_tree() or world.player == null or not is_instance_valid(world.player):
			return
		var to: Vector2 = world.player.call(&"get_centre")
		var t := float(i) / float(POWER_SPARKS - 1)
		feel.particles(POWER_PARTICLES, from.lerp(to, t) - Vector2(0.0, sin(t * PI) * POWER_ARC_PX))
		await PrologueScene.wait(get_tree(), POWER_STEP_MS)
	var body: Node2D = world.player_body
	if body == null or not is_instance_valid(body):
		return
	var glow := SoftGlow.new()
	glow.set(&"radius", Vector2(70, 56))
	glow.set(&"color", Color(1.0, 0.9, 0.55, 0.6))
	body.add_child(glow)
	glow.position = (world.player.call(&"get_centre") as Vector2) - body.global_position
	var tween := glow.create_tween()
	tween.tween_property(glow, "modulate:a", 0.0, POWER_GLOW_S)
	tween.tween_callback(glow.queue_free)


func _drop_glint() -> void:
	var glint := get_node_or_null(pearl_glint)
	if glint != null:
		glint.queue_free()


# --- heavy blocks reset with their room ------------------------------------------------------------

## Notes where every heavy block of the world stands, and listens for the slime's room changes.
func _snapshot_blocks() -> void:
	if not is_inside_tree():
		return
	var world := Services.world()
	_block_starts.clear()
	for node: Node in get_tree().get_nodes_in_group(BLOCK_GROUP):
		if node is Node2D and (world == null or world.world_root == null or world.world_root.is_ancestor_of(node)):
			_block_starts.append({"block": node, "at": (node as Node2D).global_position})
	var dungeon := DungeonState.current(get_tree())
	if dungeon != null and dungeon.has_signal(&"room_entered") and not dungeon.is_connected(&"room_entered", _on_room_entered):
		dungeon.connect(&"room_entered", _on_room_entered)


## The slime walked into a room: the blocks that started in it go back to their starts.
func _on_room_entered(payload: Dictionary) -> void:
	var dungeon := DungeonState.current(get_tree())
	if dungeon == null or not dungeon.has_method(&"room_at"):
		return
	var key := str(payload.get("room", ""))
	for entry: Dictionary in _block_starts:
		var block := entry.get("block") as Node2D
		var at: Vector2 = entry["at"]
		if block == null or not is_instance_valid(block) or block.global_position.is_equal_approx(at):
			continue
		var room: Node = dungeon.call(&"room_at", at)
		if room == null or str(dungeon.call(&"room_key_of", room)) != key:
			continue
		reset_block(block, at)


## Puts `block` back on `at` unless it is moving or the slime stands there. True when it moved.
func reset_block(block: Node2D, at: Vector2) -> bool:
	if block.has_method(&"is_moving") and bool(block.call(&"is_moving")):
		return false
	var world := Services.world()
	var body: Node2D = world.player_body if world != null else null
	if body != null and body.global_position.distance_to(at) < BLOCK_RESET_CLEAR_PX:
		return false
	block.global_position = at
	block.reset_physics_interpolation()
	return true


func _show_heart(shown: bool) -> void:
	var node := get_node_or_null(heart) as Node2D
	if node == null:
		return
	node.visible = shown
	node.process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED


func _boss_beaten() -> bool:
	var run := Services.run()
	return run != null and boss_id in (run.world.get("defeated_boss_ids", []) as Array)


## A phase-two landing: `count` clods at the free spots nearest the slime, after their shadows.
func _on_clods_requested(payload: Dictionary) -> void:
	var spots := _free_spots()
	var room := max_clods - _live_clods()
	var count := mini(int(payload.get("count", 2)), mini(room, spots.size()))
	for i in count:
		_drop_clod(spots[i])


func _free_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var root := get_node_or_null(clod_spots)
	if root == null:
		return out
	var taken: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group(CLOD_GROUP):
		if node is Node2D and is_instance_valid(node):
			taken.append((node as Node2D).global_position)
	for child: Node in root.get_children():
		if not child is Node2D:
			continue
		var at := (child as Node2D).global_position
		var free := true
		for point in taken:
			if point.distance_to(at) < CLOD_SPOT_FREE_PX:
				free = false
				break
		if free:
			out.append(at)
	var world := Services.world()
	if world != null and world.player != null and is_instance_valid(world.player):
		var centre: Vector2 = world.player.call(&"get_centre")
		out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(centre) < b.distance_to(centre))
	return out


func _live_clods() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group(CLOD_GROUP):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1
	return count


func _drop_clod(at: Vector2) -> void:
	var shadow := ClodShadow.new()
	shadow.set(&"grow_ms", clod_shadow_ms)
	shadow.global_position = at
	shadow.add_to_group(CLOD_GROUP)
	add_child(shadow)
	await PrologueScene.wait(get_tree(), clod_shadow_ms)
	if not is_instance_valid(shadow):
		return
	shadow.queue_free()
	var boss := _bound_boss
	if boss != null and is_instance_valid(boss) and not bool(boss.call(&"is_defeated")):
		boss.call(&"strike_at", at, CLOD_HIT_RADIUS, clod_damage, CLOD_KNOCKBACK)
	var packed := load(LIFTABLE_SCENE) as PackedScene
	var clod := packed.instantiate() as Node2D
	var script := clod.get_node_or_null(^"LiftableScript")
	if script != null:
		script.set(&"kind", CLOD_KIND)
	clod.add_to_group(CLOD_GROUP)
	var parent := get_parent()
	parent.add_child(clod)
	clod.global_position = at
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_CLOD)
		feel.particles(&"dodge-dust", at)
