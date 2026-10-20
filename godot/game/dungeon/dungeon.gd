@tool
extends Node2D
class_name Dungeon
## Marks its world as a dungeon, or as one world of a dungeon (docs/godot/DUNGEONS.md "The Dungeon
## node"; decisions archive question 109). Place one `Dungeon` node in each world of the dungeon,
## all with the same `dungeon_id`. While its world is played:
##
## - **No saving** (RunState `saving_blocked_reason` is "dungeon", DungeonState.is_inside): Save is
##   greyed out, the autosave waits until the slime is out. A quit or a closed window writes the
##   resume save (`resume_saves`): the run with the slime at the entrance and all it did kept.
## - **Fainting resumes at the entrance**: this node is the player's respawn override
##   (player.gd RESPAWN_OVERRIDE_GROUP): `respawn_point` is the entrance marker's spot in this
##   world; in another world of the dungeon `respawn_elsewhere` travels there.
## - **Rooms**: its world's CameraRooms (game/world/camera_room.gd) are the dungeon's rooms. The
##   room the slime stands in is visited (the map shows it); walking into another room brings back
##   the beaten placed enemies (EnemyPopulation.spawn_placed: "ordinary room enemies come back when
##   a room is entered again"; room fights keep their own, game/dungeon/room_fight.gd) and the
##   room's pots and other light things that were taken (`room_resets`).
## - **The HUD**: the dungeon's key chip (game/dungeon/dungeon_hud.gd), its rooms on the minimap
##   (dungeon_minimap.gd) and its map on the map screen (dungeon_map_page.gd).
## - **The seal** (docs/godot/DUNGEONS.md "The seal"): `boss_id` is the dungeon's boss. Taking the
##   dungeon's Pearl (game/scripts/pearl.gd) calls `seal_now`: DungeonState seals the dungeon until
##   he falls, his roar sounds as the Pearl's card closes and the view glimpses the entrance's seal
##   slamming shut (game/dungeon/seal_moment.gd). While sealed every seal shutter in its worlds is
##   shut (game/dungeon/dungeon_seal.gd), a travel out refuses with `seal_text`, his roar sounds far
##   off now and then (`dungeon.seal.distantRoar*`), and he shows his rage when his fight starts
##   (game/bosses/enraged_look.gd: presentation only). His fall (in the record or in
##   `defeated_boss_ids`) breaks the seals: "The seals break!". Set `boss_id`, `boss_name`,
##   `seal_color`, `roar_sound` (and `roar_pitch`) on the Dungeon node of every world of the dungeon.
## - **Dev launch options** (once a session): `keys=<n>` small keys, `bigkey`, `dmap` (the map and
##   the compass), `room=<CameraRoom name>` (start in that room, at its `RoomEntry` child or its
##   middle), `sealed` (the Pearls in this world taken quietly, their skins lent, and the dungeon
##   sealed: the second half; `skins=` lends skins in a world without its Pearl).
##
## In the editor it draws its name.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DoorwayArt := preload("res://game/dungeon/doorway_art.gd")
const RoomMask := preload("res://game/dungeon/room_mask.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")
const DungeonHud := preload("res://game/dungeon/dungeon_hud.gd")
const DungeonMinimap := preload("res://game/dungeon/dungeon_minimap.gd")
const DungeonMapPage := preload("res://game/dungeon/dungeon_map_page.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")
const SealMoment := preload("res://game/dungeon/seal_moment.gd")
const EnragedLook := preload("res://game/bosses/enraged_look.gd")

const BOSS_CAMP_GROUP := &"boss_camp"
const ROOM_FIGHT_GROUP := &"room_fight"
const PEARL_GROUP := &"pearl"
## pearl.gd FLAG_PREFIX: a Pearl taken is the flag "pearl.<id>".
const PEARL_FLAG_PREFIX := "pearl."
const SkinState := preload("res://game/player/skins/skin_state.gd")
const BREAK_TEXT := "The seals break!"
const BREAK_TEXT_RISE := 60.0
const CUE_BREAK := &"SecretFound"

## player.gd RESPAWN_OVERRIDE_GROUP.
const RESPAWN_OVERRIDE_GROUP := &"respawn_override"
const WORLD_MAIN_GROUP := &"world_main"
const ROOM_ENTRY_NAME := "RoomEntry"
const LABEL_COLOR := Color(1.0, 0.8, 0.35, 0.95)

## The slime walked into another room. Payload: {"room": the room key, "from": the room key left ("" at first)}.
signal room_entered(payload: Dictionary)

## The dungeon's id, the same in every world of it ("fatty-lair"); its record in RunState.
@export var dungeon_id: String = "":
	set(value):
		dungeon_id = value
		queue_redraw()
## Its name on the map screen and the HUD ("Fatty's Lair").
@export var display_name: String = ""
## The Node2D (a marker) where a faint or a quit resumes: its position is the slime's centre there.
## Looked up by name in the world of `entrance_map_id`.
@export var entrance_marker: String = "dungeon-entrance"
## The world of the entrance ("" = this world).
@export var entrance_map_id: String = ""
## A quit or a closed window inside writes the resume save to the autosave slot (off in the dev
## lab, so the title's Continue never starts there, as for the playground).
@export var resume_saves: bool = true
## Walking into another room brings back its beaten enemies and its taken pots.
@export var room_resets: bool = true
## The id this world keeps its kit records under ("" = its map id). Every room world of a dungeon
## that is one world per room (Fatty's Lair) sets the dungeon's id here, so a room's records
## ("fatty-lair:fatty-lair-drawbridge") do not change with its world (DungeonState.object_key).
@export var record_map_id: String = ""
## The dungeon's map layout (a DungeonLayout scene, game/dungeon/dungeon_layout.gd) when it is one
## world per room: the map and the minimap draw every room of the layout, this world's room among
## them; null = the CameraRooms of this world only.
@export var layout: PackedScene

@export_group("The seal")
## The dungeon's boss: his camp's (boss_camp.gd, the Colossus's arena) or his room fight's `boss_id`.
## Taking the Pearl seals the dungeon until he falls ("" = the Pearl seals nothing).
@export var boss_id: String = ""
## His name in the seal's lines ("Fatty One Eye").
@export var boss_name: String = ""
## The seal's ring of light and his rage's glow: the boss's colour (Fatty's mud red, the Matron's
## violet, the Colossus's smoky violet).
@export var seal_color: Color = Color("#d4482e")
## His roar: as the Pearl's card closes, and far off while sealed (null = no roar).
@export var roar_sound: AudioStream
@export var roar_pitch: float = 1.0
## The dust that falls over the screen at his roar (crystal dust in the Mine, silk in the Hollow).
@export var dust_color: Color = Color("#e6d8b4")
## The take's glimpse when the entrance's seal is in another world (a dungeon of one world per room):
## pictures of the entrance made in advance (`tools/capture_lair_seal.gd`), shown full screen for
## `seal.glimpseMs`: the first (the doorway open), then from `seal.glimpseSlamMs` with the boom the
## second (the seal up). Empty: no glimpse there (the line and the map's red bar tell it).
@export var glimpse_pictures: Array[Texture2D] = []
@export_group("Dev")
## `?sealed` in a world without the Pearl (a room of a dungeon of one world per room): the Pearl's
## id (its flag `pearl.<id>`), its guard's `boss_id` and its skin, taken quietly.
@export var dev_pearl_id: String = ""
@export var dev_pearl_guard: String = ""
@export var dev_pearl_skin: String = ""

## Dev launch options apply once a session per dungeon.
static var _dev_applied: Dictionary = {}

var _sealed := false
var _next_roar_ms := -1.0
var _break_at_ms := -1.0
var _roar_player: AudioStreamPlayer

var _rooms: Array[CameraRoom] = []
var _room_key := ""
var _templates: Array[Dictionary] = []
var _hud: Node
var _minimap: Control
var _page: Control
var _registered := false
var _room_mask: CanvasLayer
## The layout's rooms, read once at registration: [{"key", "name", "world", "rect", "outline",
## "node", "scene"}] in this world's coordinates, and its marks [{"mark", "at", "rotation"}].
var _layout_rooms: Array[Dictionary] = []
var _layout_marks: Array[Dictionary] = []


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(DungeonState.GROUP)
	add_to_group(RESPAWN_OVERRIDE_GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	var world := Services.world()
	if world != null:
		world.world_registered.connect(_on_world_registered)
		if world.world_root != null and world.world_root.is_ancestor_of(self):
			_on_world_registered.call_deferred({})


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var world := Services.world()
	if world != null and world.world_registered.is_connected(_on_world_registered):
		world.world_registered.disconnect(_on_world_registered)
	for template: Dictionary in _templates:
		var node: Node = template.get("template")
		if is_instance_valid(node):
			node.free()
	_templates.clear()
	if is_instance_valid(_minimap):
		_minimap.queue_free()
	if is_instance_valid(_page):
		_page.call(&"detach")
		_page.queue_free()


func _on_world_registered(_payload: Dictionary) -> void:
	if _registered:
		return
	var world := Services.world()
	if world == null or world.world_root == null or not world.world_root.is_ancestor_of(self):
		return
	_registered = true
	DoorwayArt.apply(world.world_root)
	_room_mask = RoomMask.new()
	_room_mask.name = "RoomMask"
	add_child(_room_mask)
	_rooms.clear()
	for node: Node in get_tree().get_nodes_in_group(CameraRoom.GROUP):
		if node is CameraRoom and world.world_root.is_ancestor_of(node):
			_rooms.append(node as CameraRoom)
	_record_entrance()
	_read_layout()
	if room_resets:
		_snapshot_light_things()
	_hud = DungeonHud.new()
	_hud.set(&"dungeon", self)
	add_child(_hud)
	_minimap = DungeonMinimap.attach(self)
	_page = DungeonMapPage.attach(self)
	_sealed = is_sealed()
	if _sealed:
		_schedule_distant_roar(false)
	_bind_bosses()
	_apply_dev_options.call_deferred()


# --- the entrance and fainting ------------------------------------------------------------------

## The world of the entrance.
func entrance_world() -> String:
	if not entrance_map_id.is_empty():
		return entrance_map_id
	var world := Services.world()
	return world.map_id() if world != null else ""


## The entrance marker's spot (an old centre) when it is in this world, else null.
func entrance_point() -> Variant:
	var world := Services.world()
	if world == null or world.world_root == null or entrance_world() != world.map_id():
		return null
	var marker := world.world_root.find_child(entrance_marker, true, false) as Node2D
	return marker.global_position if marker != null else null


## player.gd's respawn override: a fainted slime wakes at the entrance (null when it is in another
## world: `respawn_elsewhere` then travels there).
func respawn_point() -> Variant:
	return entrance_point()


## A fainted slime whose entrance is in another world of the dungeon travels there (main.gd
## `respawn_in_world`). False when the entrance is in this world or not known yet.
func respawn_elsewhere() -> bool:
	var world := Services.world()
	var run := Services.run()
	if world == null or run == null or entrance_world() == world.map_id():
		return false
	var at := DungeonState.entrance(run, dungeon_id)
	if at.is_empty() or str(at.get("map_id", "")) == world.map_id():
		return false
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	return main != null and main.has_method(&"respawn_in_world") and bool(main.call(&"respawn_in_world", at))


func _record_entrance() -> void:
	var at: Variant = entrance_point()
	var run := Services.run()
	var world := Services.world()
	if at is Vector2 and run != null and world != null:
		DungeonState.set_entrance(run, dungeon_id, world.map_id(), at)


# --- rooms --------------------------------------------------------------------------------------

## The dungeon's rooms: [{"key", "name", "rect", "outline", "node"}] (global; "node" the CameraRoom,
## null for a room of another world). With a `layout`, every room of the layout (this world's own
## camera rooms among them, laid where the layout puts them); else this world's camera rooms.
func rooms() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var own := {}
	for room: CameraRoom in _rooms:
		if is_instance_valid(room):
			own[String(room.name)] = true
			out.append({"key": room_key_of(room), "name": String(room.name), "rect": room.rect(), "outline": room.outline_global(), "node": room})
	for room: Dictionary in _layout_rooms:
		if not own.has(str(room["name"])):
			out.append(room)
	return out


## The layout's marks ({"mark": "boss" | "seal", "at": global point, "rotation"}); [] without one.
func layout_marks() -> Array[Dictionary]:
	return _layout_marks


## The layout's rooms in other worlds than this one ([] without a layout): {"key", "name", "world",
## "rect" (this world's coordinates), "outline", "scene" (the room's world scene)}.
func layout_rooms_elsewhere() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var world := Services.world()
	var here := world.map_id() if world != null else ""
	for room: Dictionary in _layout_rooms:
		if str(room["world"]) != here:
			out.append(room)
	return out


## The world of the layout's room `room_name` ("" when the layout has no such room).
func layout_world_of(room_name: String) -> String:
	for room: Dictionary in _layout_rooms:
		if str(room["name"]) == room_name:
			return str(room["world"])
	return ""


## A room's key in the record: "<record id>/<room name>" (the record id: `record_map_id`, else the
## map id).
func room_key_of(room: CameraRoom) -> String:
	return "%s/%s" % [_record_id(), room.name]


func _record_id() -> String:
	if not record_map_id.is_empty():
		return record_map_id
	var world := Services.world()
	return world.map_id() if world != null else ""


## Reads the `layout` scene: its rooms and marks, moved into this world's coordinates (this world's
## room's place on the layout taken off).
func _read_layout() -> void:
	_layout_rooms.clear()
	_layout_marks.clear()
	if layout == null:
		return
	var scene := layout.instantiate()
	var world := Services.world()
	var here := world.map_id() if world != null else ""
	var offset := Vector2.ZERO
	for child: Node in scene.get_children():
		# a world of several rooms (R5) has a map room per CameraRoom: any of them places the world
		if child.has_method(&"outline_points") and str(child.get(&"world_id")) == here:
			offset = (child as Node2D).position - (child.get(&"camera_offset") as Vector2)
			break
	for child: Node in scene.get_children():
		if child.has_method(&"outline_points"):
			var points := PackedVector2Array()
			for point: Vector2 in child.call(&"outline_points"):
				points.append(point - offset)
			var rect: Rect2 = child.call(&"rect")
			rect.position -= offset
			_layout_rooms.append({"key": "%s/%s" % [_record_id(), child.get(&"room_name")], "name": str(child.get(&"room_name")),
				"world": str(child.get(&"world_id")), "rect": rect, "outline": points, "node": null,
				"scene": str(child.get(&"room_scene"))})
		elif &"mark" in child and child is Node2D:
			_layout_marks.append({"mark": str(child.get(&"mark")), "at": (child as Node2D).position - offset,
				"rotation": (child as Node2D).rotation})
	scene.free()


## The room that holds `point` (global), or null.
func room_at(point: Vector2) -> CameraRoom:
	for room: CameraRoom in _rooms:
		if is_instance_valid(room) and room.contains(point):
			return room
	return null


## The key of the room the slime is in ("" before it stood in one).
func current_room_key() -> String:
	return _room_key


func _physics_process(_delta: float) -> void:
	if not _registered:
		return
	_watch_seal()
	var world := Services.world()
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	var room := room_at(world.player.get_centre())
	if room == null:
		return
	var key := room_key_of(room)
	if key == _room_key:
		return
	var left := _room_key
	_room_key = key
	var run := Services.run()
	if run != null:
		DungeonState.visit_room(run, dungeon_id, key)
	if room_resets and not left.is_empty():
		_reset_room(room)
	room_entered.emit({"room": key, "from": left})


## The room's beaten enemies come back (every placed enemy that is not standing: EnemyPopulation
## spawns them again) and its taken light things are put back.
func _reset_room(room: CameraRoom) -> void:
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	var population: Node = main.get(&"enemy_population") if main != null else null
	if population != null and is_instance_valid(population) and population.has_method(&"spawn_placed"):
		population.call(&"spawn_placed")
	var rect := room.rect()
	for template: Dictionary in _templates:
		var current: Variant = template.get("current")
		if is_instance_valid(current) and not (current as Node).is_queued_for_deletion():
			continue
		if not rect.has_point(template["position"]):
			continue
		var parent: Node = template.get("parent")
		var source: Node = template.get("template")
		if not is_instance_valid(parent) or not is_instance_valid(source):
			continue
		var copy := source.duplicate() as Node2D
		parent.add_child(copy)
		copy.global_position = template["position"]
		template["current"] = copy


## Keeps a copy of every light thing (a liftable: pots, crates, ...) standing in a room, so it can
## be put back when the room is entered again.
func _snapshot_light_things() -> void:
	var world := Services.world()
	for node: Node in get_tree().get_nodes_in_group(LiftableScript.GROUP):
		var root := node.get_parent() as Node2D
		if root == null or world.world_root == null or not world.world_root.is_ancestor_of(root):
			continue
		if room_at(root.global_position) == null:
			continue
		_templates.append({"template": root.duplicate(), "parent": root.get_parent(), "position": root.global_position,
			"current": root})


# --- the seal -----------------------------------------------------------------------------------

## True while the dungeon is sealed (its Pearl taken, its boss standing).
func is_sealed() -> bool:
	return DungeonState.is_sealed(Services.run(), dungeon_id)


## The line every way out refuses with while sealed.
func seal_text() -> String:
	return "Sealed. %s's rage holds it shut." % (boss_name if not boss_name.is_empty() else "The boss")


## The line over the slime as the boss roars on the take.
func roar_text() -> String:
	return "%s roars! The way out slams shut." % (boss_name if not boss_name.is_empty() else "The boss")


## The Pearl's take (`by`: the Pearl's id): seals the dungeon until `boss_id` falls. With `moment`,
## his roar as the Pearl's card closes and the glimpse of the entrance's seal slamming shut
## (seal_moment.gd); without it (a dev option, a test) every seal shuts quietly. False when nothing
## was sealed: no `boss_id`, he is beaten already, or it is sealed already.
func seal_now(by: String = "", moment: bool = true) -> bool:
	var run := Services.run()
	if run == null or not DungeonState.seal(run, dungeon_id, boss_id, by):
		return false
	_sealed = true
	_break_at_ms = -1.0
	_schedule_distant_roar()
	var target: Node = glimpse_seal() if moment else null
	for seal: Node in seals():
		if seal != target:
			seal.call(&"shut_quietly")
	if target != null:
		# It holds the doorway at once; it rises in the glimpse.
		target.call(&"engage")
	if moment:
		var sequence := SealMoment.new()
		sequence.name = "SealMoment"
		sequence.dungeon = self
		sequence.target = target
		add_child(sequence)
	return true


## The seal shutters (dungeon_seal.gd) of this world.
func seals() -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(DungeonState.SEAL_GROUP):
		if not node.is_queued_for_deletion() and _in_world(node):
			out.append(node)
	return out


## The seal the take's glimpse shows: one with `glimpse` on, else the one nearest the entrance
## marker when the entrance is in this world; null when none.
func glimpse_seal() -> Node:
	var at: Variant = entrance_point()
	var best: Node = null
	var best_distance := INF
	for seal: Node in seals():
		if bool(seal.get(&"glimpse")):
			return seal
		if at is Vector2:
			var distance := (seal as Node2D).global_position.distance_to(at)
			if distance < best_distance:
				best_distance = distance
				best = seal
	return best


## His roar (the dungeon's `roar_sound`), `volume_db` louder or softer and at `pitch_share` of
## `roar_pitch`. Real time: it plays through a pause.
func play_roar(volume_db: float = 0.0, pitch_share: float = 1.0) -> void:
	if roar_sound == null:
		return
	if _roar_player == null or not is_instance_valid(_roar_player):
		_roar_player = AudioStreamPlayer.new()
		_roar_player.name = "RoarPlayer"
		_roar_player.bus = &"Effects"
		_roar_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_roar_player)
	_roar_player.stream = roar_sound
	_roar_player.volume_db = volume_db
	_roar_player.pitch_scale = maxf(0.05, roar_pitch * pitch_share)
	_roar_player.play()


## The record's seal against what this world shows: sealed elsewhere (a test, a dev option) shuts
## the seals; his fall breaks them `dungeon.seal.breakDelayMs` later (after "defeated!"). While
## sealed, his roar sounds far off every `distantRoarMinMs` to `distantRoarMaxMs`.
func _watch_seal() -> void:
	var sealed := is_sealed()
	if sealed != _sealed:
		_sealed = sealed
		if sealed:
			_break_at_ms = -1.0
			for seal: Node in seals():
				seal.call(&"shut_quietly")
			_schedule_distant_roar()
		else:
			_next_roar_ms = -1.0
			_break_at_ms = Services.now_ms() + DungeonState.number("seal.breakDelayMs", 900.0)
	if _break_at_ms >= 0.0 and Services.now_ms() >= _break_at_ms:
		_break_at_ms = -1.0
		_break_seals()
	if _sealed and _next_roar_ms >= 0.0 and Services.now_ms() >= _next_roar_ms:
		_schedule_distant_roar()
		if not _boss_fighting():
			_distant_roar()


## His fall: every seal sinks with a chime and stays down; "The seals break!" over the slime.
func _break_seals() -> void:
	DungeonState.unseal(Services.run(), dungeon_id)
	for seal: Node in seals():
		seal.call(&"break_seal")
	var feel := Services.feel()
	var world := Services.world()
	if feel == null:
		return
	feel.audio_cue(CUE_BREAK)
	if world != null and world.player != null and is_instance_valid(world.player):
		feel.floating_text(world.player.get_centre() - Vector2(0.0, BREAK_TEXT_RISE), BREAK_TEXT, &"yellow", true)


## The next far-off roar, kept in the session (DungeonState `session_value`) so that in a dungeon of
## one world per room the wait does not start again in every room; `again` picks a new time.
func _schedule_distant_roar(again: bool = true) -> void:
	var key := "%s:next-roar-ms" % dungeon_id
	var kept := float(DungeonState.session_value(Services.run(), key, -1.0))
	if not again and kept > Services.now_ms():
		_next_roar_ms = kept
		return
	var low := DungeonState.number("seal.distantRoarMinMs", 45000.0)
	var high := maxf(low, DungeonState.number("seal.distantRoarMaxMs", 60000.0))
	_next_roar_ms = Services.now_ms() + randf_range(low, high)
	DungeonState.set_session_value(Services.run(), key, _next_roar_ms)


## Far off: his roar, soft and low, a light shake and a little dust (presentation only).
func _distant_roar() -> void:
	play_roar(DungeonState.number("seal.distantRoarDb", -14.0), DungeonState.number("seal.distantRoarPitch", 0.85))
	var feel := Services.feel()
	if feel != null:
		feel.shake(DungeonState.number("seal.distantShakeMs", 320.0), DungeonState.number("seal.distantShakeIntensity", 0.0025))
	SealMoment.dust(self, dust_color, int(DungeonState.number("seal.distantDust", 14.0)))


## True while his fight is on (no far-off roar then: he is right there).
func _boss_fighting() -> bool:
	if boss_id.is_empty():
		return false
	for node: Node in get_tree().get_nodes_in_group(BOSS_CAMP_GROUP):
		if _in_world(node) and str(node.get(&"boss_id")) == boss_id and node.has_method(&"get_live_boss") \
				and node.call(&"get_live_boss") != null:
			return true
	for node: Node in get_tree().get_nodes_in_group(ROOM_FIGHT_GROUP):
		if _in_world(node) and str(node.get(&"boss_id")) == boss_id and bool(node.call(&"is_active")):
			return true
	return false


## His fight starts while sealed: his rage shows (EnragedLook). A boss camp's `boss_engaged` (Fatty's,
## the Matron's, the Colossus's arena) and a boss room fight's `started` (the lab's).
func _bind_bosses() -> void:
	if boss_id.is_empty():
		return
	for node: Node in get_tree().get_nodes_in_group(BOSS_CAMP_GROUP):
		if _in_world(node) and node.has_signal(&"boss_engaged"):
			var engaged := _on_boss_engaged.bind(node)
			if not node.is_connected(&"boss_engaged", engaged):
				node.connect(&"boss_engaged", engaged)
	for node: Node in get_tree().get_nodes_in_group(ROOM_FIGHT_GROUP):
		if _in_world(node) and str(node.get(&"boss_id")) == boss_id:
			var started := _on_boss_fight_started.bind(node)
			if not node.is_connected(&"started", started):
				node.connect(&"started", started)


func _on_boss_engaged(payload: Dictionary, camp: Node) -> void:
	if str(payload.get("bossId", "")) != boss_id or not is_sealed() or not is_instance_valid(camp):
		return
	var boss: Variant = camp.call(&"get_live_boss") if camp.has_method(&"get_live_boss") else null
	if boss is Node:
		EnragedLook.attach(boss as Node, seal_color)


func _on_boss_fight_started(_payload: Dictionary, fight: Node) -> void:
	if not is_sealed() or not is_instance_valid(fight) or not fight.has_method(&"members"):
		return
	for member: Node in fight.call(&"members"):
		var enemy: Variant = member.call(&"get_enemy") if member.has_method(&"get_enemy") else member
		if enemy is Node:
			EnragedLook.attach(enemy as Node, seal_color)
	play_roar()


func _in_world(node: Node) -> bool:
	var world := Services.world()
	if node == null or not node.is_inside_tree():
		return false
	return world == null or world.world_root == null or world.world_root.is_ancestor_of(node)


# --- dev launch options -------------------------------------------------------------------------

func _apply_dev_options() -> void:
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	var run := Services.run()
	if main == null or run == null or not main.has_method(&"launch_option") or _dev_applied.has(dungeon_id):
		return
	var room_name := str(main.call(&"launch_option", "room"))
	if room_name.is_empty():
		room_name = str(main.get(&"direct_room_run"))
	var room_world := layout_world_of(room_name) if not room_name.is_empty() else ""
	if not room_world.is_empty() and room_world != Services.world().map_id():
		# A room of another world of the layout: go there, to its RoomEntry; the options apply there,
		# once (keys are not given twice).
		if main.has_method(&"travel_to"):
			main.call(&"travel_to", room_world, "", "", ROOM_ENTRY_NAME)
		return
	_dev_applied[dungeon_id] = true
	var keys := str(main.call(&"launch_option", "keys"))
	if keys.is_valid_int() and int(keys) > 0:
		DungeonState.add_small_key(run, dungeon_id, int(keys))
	if bool(main.call(&"has_launch_option", "bigkey")):
		DungeonState.give_item(run, dungeon_id, DungeonState.BIG_KEY)
	if bool(main.call(&"has_launch_option", "dmap")):
		DungeonState.give_item(run, dungeon_id, DungeonState.MAP)
		DungeonState.give_item(run, dungeon_id, DungeonState.COMPASS)
	if bool(main.call(&"has_launch_option", "sealed")):
		_dev_seal()
	if not room_name.is_empty():
		for room: CameraRoom in _rooms:
			if String(room.name) == room_name:
				var entry := room.get_node_or_null(ROOM_ENTRY_NAME) as Node2D
				var world := Services.world()
				if world != null and world.player != null:
					world.player.arrive_at(entry.global_position if entry != null else room.rect().get_center())


## `?sealed`: the second half at once. Every Pearl of this world is taken quietly (its guard's
## fight finished, its skin won), and the dungeon is sealed without the moment.
func _dev_seal() -> void:
	var run := Services.run()
	for pearl: Node in get_tree().get_nodes_in_group(PEARL_GROUP):
		if not _in_world(pearl) or not pearl.has_method(&"take") or bool(pearl.call(&"is_taken")):
			continue
		var guard := str(pearl.get(&"boss_id"))
		if not guard.is_empty() and guard != boss_id:
			for fight: Node in get_tree().get_nodes_in_group(ROOM_FIGHT_GROUP):
				if _in_world(fight) and str(fight.get(&"boss_id")) == guard and fight.has_method(&"finish_quietly"):
					fight.call(&"finish_quietly")
			DungeonState.mark_boss_beaten(run, dungeon_id, guard)
		pearl.call(&"take", true)
	# A room without the Pearl (one world per room): its flag, its guard and its skin, quietly.
	if not dev_pearl_id.is_empty() and not run.has_flag(PEARL_FLAG_PREFIX + dev_pearl_id):
		if not dev_pearl_guard.is_empty():
			DungeonState.mark_boss_beaten(run, dungeon_id, dev_pearl_guard)
		run.set_flag(PEARL_FLAG_PREFIX + dev_pearl_id)
		if not dev_pearl_skin.is_empty():
			SkinState.grant(StringName(dev_pearl_skin))
	seal_now("dev", false)


# --- the editor ---------------------------------------------------------------------------------

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 10.0, LABEL_COLOR)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(14, 6), "dungeon: " + dungeon_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, LABEL_COLOR)
