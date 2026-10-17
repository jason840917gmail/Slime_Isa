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
##   at once. Beaten, he never comes back (the camp stops for good once `defeated_boss_ids` has him):
##   the boss heart (`heart`, a goo heart worth two) shows, and the Pearl (`pearl`,
##   game/scripts/pearl.gd) rises on its altar by itself. The arena's shutters (the dungeon kit's
##   game/dungeon/shutter.gd with `boss_shutter_fight` as their `fight_id`) shut while he lives and
##   open when he falls. His fall is kept in the dungeon's record too (DungeonState
##   mark_boss_beaten). Until then the director, standing in the arena, is the compass's boss mark
##   (group `dungeon_map_mark`, `mark` "boss").
## - **Blocked gaps** (`blocked_gaps`: the map nook): a Node2D holding light things (liftables) and a
##   `Barrier` body; once every light thing is taken the barrier goes and the secret jingle plays.
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
@export var pearl: NodePath
@export var boss_id: String = "fatty-one-eye"
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
	var prize := get_node_or_null(pearl)
	if prize != null and prize.has_method(&"appear"):
		prize.call(&"appear")


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
