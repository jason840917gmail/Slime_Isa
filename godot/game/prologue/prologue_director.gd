extends Node2D
## The prologue's director (roadmap 5.18 to 5.23; docs/design/2026-10-16-prologue.md;
## docs/godot/PROLOGUE.md): the node `Prologue` in west-village-b4, the Wellspring's and the glade's
## chunk, which plays the prologue's beats there while it runs (PrologueState.is_running) and leaves
## both places as they are after it otherwise.
##
## The beats, each a story flag (PrologueState) once played:
## 1. **The birth** (`prologue.born`): no HUD, letterbox bars; a bubble rises out of the pool, wobbles,
##    drifts to the shore and pops (game/prologue/birth_bubble.gd), and the slime is there; then the
##    HUD fades in and the bars go (question 113).
## 2. **Moving, the blocked path** (`prologue.path-cleared`): the only way out of the clearing is
##    choked with light things (the children of `path_blocked`, liftables); an invisible `barrier`
##    keeps the slime in until every one is gone (sucked in and thrown, or broken), then the secret
##    jingle plays and the barrier goes.
## 3. **The attack** (`prologue.fight-seen`, roadmap 5.19): stepping into `glade_trigger` holds the
##    slime, the bars come in, the camera pans and zooms in on Yoi (`fight_view`); he thrusts, two
##    worms on one line fall (`worm_struck_a`, `worm_struck_b`), a third bites him (`worm_biter`), he
##    sinks and calls for help; the camera comes back and the two worms left turn on the slime.
## 4. **The rescue** (`prologue.rescued`, 5.21): the worms die from one throw each (prologue worms,
##    1 HP). The glade's light things (`glade_things`) come back `refill_ms` after each is gone, so a
##    pot is always near. Fainting wakes the slime at `wake` (the player's respawn override group),
##    the worms back where they stood: the prologue has no game over.
## 5. **The veteran** (`prologue.spear`, 5.20): Yoi tells his story and teaches the Spear (the "New
##    shape" ceremony); his last lines point at the barred gate.
## 6. **The first lock** (`prologue.gate-open`, 5.22): the Spear's thrust through the bars pulls the
##    lever (game/scripts/barred_gate.gd); Yoi says goodbye and limps off. The path beyond leads out of
##    the chunk into Slimeshire (level-1-c4), where Plop meets the slime
##    (game/prologue/town_edge_meeting.gd ends the prologue).
## While a scene plays the slime is held still (`_holding`: no movement, no input). The Roll is not
## the slime's yet (player.gd `dodge_learned` off while the prologue runs). Timings are this node's
## properties (roadmap 5.19).
##
## A run that is not playing the prologue (it is done, or never started: an old save, a launch
## option, the tests) sees the places after it (`_settle`): the path open, the gate open, no Yoi, no
## worms (their PlacedEnemy nodes are taken out before the world's enemies are spawned).
##
## Owner: prologue.

const Services := preload("res://game/shared/services.gd")
const PrologueState := preload("res://game/prologue/prologue_state.gd")
const BirthBubble := preload("res://game/prologue/birth_bubble.gd")
const CinemaBars := preload("res://game/prologue/cinema_bars.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const PlacedEnemyScript := preload("res://game/enemy/placed_enemy.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")
const PrologueScene := preload("res://game/prologue/prologue_scene.gd")

const RESPAWN_OVERRIDE_GROUP := &"respawn_override"
const MAIN_GROUP := &"world_main"
const LIFTABLE_SCENE := "res://game/scenes/objects/liftable.tscn"
const CUE_SECRET := &"SecretFound"
const CUE_POP_IN := &"DropPop"

enum Phase { SETTLED, BIRTH, WELLSPRING, SCENE, RESCUE, TALK, GATE, FAREWELL }

## The lines (drafts from the design; the first is before Yoi has given his name).
const SPEAKER_SHOUT := "Old soldier"
const SPEAKER_YOI := "Yoi"
const CALL_FOR_HELP: Array[String] = ["You there! Kid! Throw something, anything!"]
const STORY: Array[String] = [
	"Ha... not bad, kid. Not bad at all. You saved an old soldier's hide.",
	"Yoi of the Thorn Guard, at your service. I held the gate against Gorge's monsters in the great war.",
	"When the war was lost, Slimeshire hid under its own floor. I stayed out here to keep watch.",
	"Those worms are Fatty One Eye's. They've grown bold.",
	"You've got goo in you, kid. Let me show you something. Gather all of yourself, and push it out to one point.",
]
const GATE_LESSON: Array[String] = [
	"That's it! That's the Spear.",
	"The old Thorn Guard gate there is shut from the far side. Its lever is behind the bars, and only a thrust fits between them.",
	"Go on. Stand at the bars and thrust right through.",
]
const FAREWELL: Array[String] = [
	"Ha! Good thrust.",
	"Find old Yoi if you need a soldier's advice. Now go, the town needs every slime it has.",
]

@export_group("Places")
## The slime's centre after the bubble pops (the new game's arrival marker, PrologueState.BIRTH_MARKER).
@export var birth: Node2D
## Where the bubble rises (the pool's middle).
@export var bubble_from: Node2D
## The glade's edge: where a fainted slime wakes.
@export var wake: Node2D
## Where the camera looks during the attack.
@export var fight_view: Node2D
## Where Yoi limps off to.
@export var yoi_exit: Node2D
## Stepping into it (the slime's centre, world units) plays the attack.
@export var glade_trigger: Rect2 = Rect2()
@export_group("Actors")
@export var yoi: Node2D
@export var worm_struck_a: PlacedEnemyScript
@export var worm_struck_b: PlacedEnemyScript
@export var worm_biter: PlacedEnemyScript
@export var worm_other: PlacedEnemyScript
## The light things that choke the path (liftables).
@export var path_blocked: Node2D
## Keeps the slime in the clearing until the path is clear.
@export var barrier: StaticBody2D
## The glade's light things (they come back during the rescue).
@export var glade_things: Node2D
## The barred gate (game/scripts/barred_gate.gd).
@export var gate: Node2D
@export_group("Timing")
@export var dawn_ms: float = 1200.0
@export var born_hold_ms: float = 700.0
@export var hud_fade_ms: float = 600.0
@export var pan_ms: float = 1400.0
@export var fight_zoom: float = 1.6
@export var return_ms: float = 900.0
## The attack's beats: from the thrust's start to the two worms falling, then to the bite, then to
## the call for help.
@export var thrust_hit_ms: float = 330.0
@export var after_thrust_ms: float = 1000.0
@export var bite_ms: float = 420.0
@export var call_ms: float = 900.0
## A breath before Yoi talks after the rescue, and before his goodbye once the gate opens.
@export var lesson_pause_ms: float = 500.0
@export var farewell_delay_ms: float = 700.0
@export var lesson_delay_ms: float = 900.0
## The dawn: the world's light at the birth, warming to plain daylight over `sunrise_ms` from the pop.
@export var dawn_tint: Color = Color(0.74, 0.76, 0.93)
@export var sunrise_ms: float = 4000.0
## A glade thing comes back this long after it is gone (rescue only).
@export var refill_ms: float = 3500.0
## The rescue worms see the slime from this far (their scene's 200 would let them idle).
@export var rescue_targeting_radius: float = 900.0
## A worm woken for the rescue waits this long before its first bite.
@export var rescue_attack_delay_ms: float = 900.0

var phase: Phase = Phase.SETTLED
var _player: Node
var _started := false
var _holding := false
var _cinema: CinemaBars
var _glade_spots: Array[Dictionary] = []
var _rescue_won_at := -1.0
var _dawn: CanvasModulate


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var run := Services.run()
	if not PrologueState.is_running(run):
		_settle()
		return
	_cinema = CinemaBars.new()
	add_child(_cinema)
	add_to_group(RESPAWN_OVERRIDE_GROUP)
	if gate != null and gate.has_signal(&"opened"):
		gate.connect(&"opened", _on_gate_opened)
	_remember_glade_things()
	if PrologueState.has_beat(run, PrologueState.PATH_CLEARED):
		_open_path(false)
	if PrologueState.has_beat(run, PrologueState.FIGHT_SEEN):
		_take_out(worm_struck_a)
		_take_out(worm_struck_b)
	if PrologueState.has_beat(run, PrologueState.RESCUED):
		_take_out(worm_biter)
		_take_out(worm_other)
	if not PrologueState.has_beat(run, PrologueState.BORN):
		# Dawn: no HUD yet, the bars in from the first frame (the arrival fade opens on them), and the
		# cool light before the sun is up.
		_set_hud_visible(false)
		_cinema.show_bars(true)
		_dawn = CanvasModulate.new()
		_dawn.name = "Dawn"
		_dawn.color = dawn_tint
		add_child(_dawn)


func _exit_tree() -> void:
	# A world built again shows the HUD whatever this one was doing.
	if phase == Phase.BIRTH:
		_set_hud_visible(true)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or phase == Phase.SETTLED and _started:
		return
	if not _started:
		_start()
		return
	if _player == null or not is_instance_valid(_player):
		return
	if _holding:
		PrologueScene.hold(_player)
	match phase:
		Phase.WELLSPRING:
			if not PrologueState.has_beat(Services.run(), PrologueState.PATH_CLEARED) and _path_clear():
				_open_path(true)
			if PrologueState.has_beat(Services.run(), PrologueState.PATH_CLEARED) \
					and glade_trigger.has_point(_player.call(&"get_centre")):
				_play_attack()
		Phase.RESCUE:
			_refill_glade_things()
			_check_rescue()


## Where a defeated slime wakes while the prologue runs (player.gd RESPAWN_OVERRIDE_GROUP): the
## glade's edge once the attack has played, else the birth spot.
func respawn_point() -> Variant:
	var run := Services.run()
	if not PrologueState.is_running(run):
		return null
	if PrologueState.has_beat(run, PrologueState.FIGHT_SEEN) and wake != null:
		return wake.global_position
	return birth.global_position if birth != null else null


# --- the beats ---------------------------------------------------------------------------------

## The first physics step with the slime: the Roll is not the slime's yet; the worms stand still in
## their tableau; the birth plays unless it already did.
func _start() -> void:
	var world := Services.world()
	_player = world.player if world != null else null
	if _player == null or not is_instance_valid(_player):
		return
	_started = true
	var run := Services.run()
	_player.set(&"dodge_learned", false)
	if _player.has_signal(&"respawned"):
		_player.connect(&"respawned", _on_player_respawned)
	_freeze_worms()
	if not PrologueState.has_beat(run, PrologueState.BORN):
		_play_birth()
	elif not PrologueState.has_beat(run, PrologueState.FIGHT_SEEN):
		phase = Phase.WELLSPRING
	elif not PrologueState.has_beat(run, PrologueState.RESCUED):
		_activate_rescue()
	elif not PrologueState.has_beat(run, PrologueState.GATE_OPEN):
		phase = Phase.GATE
	else:
		phase = Phase.FAREWELL


func _play_birth() -> void:
	phase = Phase.BIRTH
	_holding = true
	var root := _player_root()
	if root != null:
		root.visible = false
	await PrologueScene.wait(get_tree(), dawn_ms)
	var bubble := BirthBubble.new()
	bubble.name = "BirthBubble"
	bubble.z_index = 1
	add_child(bubble)
	var from := bubble_from.global_position if bubble_from != null else global_position
	var to := birth.global_position if birth != null else from
	await bubble.play(from, to)
	if root != null and is_instance_valid(root):
		root.visible = true
		_squash_in(root)
	if _dawn != null:
		var sunrise := _dawn.create_tween()
		sunrise.tween_property(_dawn, "color", Color.WHITE, sunrise_ms / 1000.0).set_trans(Tween.TRANS_SINE)
		sunrise.tween_callback(_dawn.queue_free)
	await PrologueScene.wait(get_tree(), born_hold_ms)
	PrologueState.mark(Services.run(), PrologueState.BORN)
	_fade_hud_in()
	_cinema.hide_bars()
	_holding = false
	phase = Phase.WELLSPRING


## True when every light thing on the path is gone.
func _path_clear() -> bool:
	if path_blocked == null:
		return true
	for child: Node in path_blocked.get_children():
		if child.is_queued_for_deletion() or not _is_liftable(child):
			continue
		return false
	return true


func _open_path(jingle: bool) -> void:
	if barrier != null and is_instance_valid(barrier):
		barrier.queue_free()
	barrier = null
	PrologueState.mark(Services.run(), PrologueState.PATH_CLEARED)
	if jingle:
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_SECRET)


## The attack (roadmap 5.19): a coroutine.
func _play_attack() -> void:
	phase = Phase.SCENE
	_holding = true
	_cinema.show_bars()
	var camera := _camera()
	var view := fight_view.global_position if fight_view != null else (yoi.global_position if yoi != null else global_position)
	if camera != null:
		# The close-up may show a little past the glade's room (the gate's beam under the top bar).
		camera.call(&"release_room")
		camera.call(&"pan_to", view, pan_ms, false)
		_tween_zoom(camera, 1.0, fight_zoom, pan_ms)
	await PrologueScene.wait(get_tree(), pan_ms + 250.0)
	# He thrusts once, and the two worms on his line fall.
	if yoi != null:
		var toward := _x_toward(yoi, worm_struck_a)
		yoi.call(&"thrust", toward)
	await PrologueScene.wait(get_tree(), thrust_hit_ms)
	_kill(worm_struck_a)
	_kill(worm_struck_b)
	var feel := Services.feel()
	if feel != null:
		feel.shake(180.0, 0.006)
	await PrologueScene.wait(get_tree(), after_thrust_ms)
	# A third bites him from the side.
	_worm_lunge(worm_biter, yoi)
	await PrologueScene.wait(get_tree(), bite_ms)
	if yoi != null:
		yoi.call(&"take_bite")
	await PrologueScene.wait(get_tree(), call_ms)
	await PrologueScene.say(get_tree(), SPEAKER_SHOUT, CALL_FOR_HELP)
	if camera != null and _player != null:
		camera.call(&"pan_to", _player.call(&"get_centre"), return_ms, true)
		_tween_zoom(camera, fight_zoom, 1.0, return_ms)
	await PrologueScene.wait(get_tree(), return_ms + 50.0)
	if camera != null:
		camera.call(&"reset_zoom")
	_cinema.hide_bars()
	_holding = false
	_take_out(worm_struck_a)
	_take_out(worm_struck_b)
	PrologueState.mark(Services.run(), PrologueState.FIGHT_SEEN)
	_activate_rescue()


func _activate_rescue() -> void:
	phase = Phase.RESCUE
	_rescue_won_at = -1.0
	for placed: PlacedEnemyScript in _placed([worm_biter, worm_other]):
		var enemy := _enemy_of(placed)
		if enemy == null:
			continue
		enemy.set_physics_process(true)
		enemy.set(&"targeting_radius", rescue_targeting_radius)
		if enemy.has_method(&"delay_attack"):
			enemy.call(&"delay_attack", rescue_attack_delay_ms)


func _check_rescue() -> void:
	for placed: PlacedEnemyScript in _placed([worm_biter, worm_other]):
		if placed != null and is_instance_valid(placed) and placed.is_standing():
			_rescue_won_at = -1.0
			return
	if _player != null and bool(_player.call(&"is_dead")):
		return
	if _rescue_won_at < 0.0:
		_rescue_won_at = Services.now_ms()
	elif Services.now_ms() - _rescue_won_at >= lesson_delay_ms:
		PrologueState.mark(Services.run(), PrologueState.RESCUED)
		_take_out(worm_biter)
		_take_out(worm_other)
		_play_lesson()


## Yoi's story and the Spear (roadmap 5.20, 4.13): a coroutine.
func _play_lesson() -> void:
	phase = Phase.TALK
	_holding = true
	_cinema.show_bars()
	# The slime lets go of what it holds to listen (a held thing would keep the Spear from striking).
	var mouth: Variant = _player.call(&"get_mouth") if _player.has_method(&"get_mouth") else null
	if mouth is Object and (mouth as Object).has_method(&"drop"):
		(mouth as Object).call(&"drop")
		if _player.has_method(&"get_mouth_hold"):
			(_player.call(&"get_mouth_hold") as Object).call(&"cancel", "lesson")
	if yoi != null:
		yoi.call(&"recover")
		yoi.call(&"face", _player.call(&"get_centre").x - yoi.global_position.x)
	await PrologueScene.wait(get_tree(), lesson_pause_ms)
	await PrologueScene.say(get_tree(), SPEAKER_YOI, STORY)
	var run := Services.run()
	run.learn_ability(String(ShapeDefs.SPEAR))
	PrologueState.mark(run, PrologueState.SPEAR)
	await PrologueScene.ceremony_done(get_tree())
	var shapes: Variant = _player.call(&"get_shapes") if _player.has_method(&"get_shapes") else null
	if is_instance_valid(shapes) and shapes is Object and (shapes as Object).has_method(&"set_current"):
		(shapes as Object).call(&"set_current", ShapeDefs.SPEAR)
	await PrologueScene.say(get_tree(), SPEAKER_YOI, GATE_LESSON)
	_cinema.hide_bars()
	_holding = false
	phase = Phase.GATE


func _on_gate_opened(_payload: Dictionary) -> void:
	var run := Services.run()
	if not PrologueState.is_running(run) or PrologueState.has_beat(run, PrologueState.GATE_OPEN):
		return
	PrologueState.mark(run, PrologueState.GATE_OPEN)
	phase = Phase.FAREWELL
	await PrologueScene.wait(get_tree(), farewell_delay_ms)
	await PrologueScene.say(get_tree(), SPEAKER_YOI, FAREWELL)
	if yoi != null and is_instance_valid(yoi):
		var exit := yoi_exit.global_position if yoi_exit != null else yoi.global_position + Vector2(160, 0)
		yoi.call(&"limp_off", exit)


# --- faint and wake ----------------------------------------------------------------------------

## A slime that fainted in the rescue wakes at the glade's edge (the respawn override) and the worms
## are back where they were.
func _on_player_respawned(_payload: Dictionary) -> void:
	if phase != Phase.RESCUE:
		return
	for placed: PlacedEnemyScript in _placed([worm_biter, worm_other]):
		var enemy := _enemy_of(placed)
		if enemy != null:
			var body: Variant = enemy.call(&"get_body")
			if body is Node:
				(body as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var population := _population()
	if population != null:
		population.call(&"spawn_placed")
	for spot: Dictionary in _glade_spots:
		spot["gone_at"] = -INF
	_refill_glade_things(true)
	_activate_rescue()


# --- the glade's light things ------------------------------------------------------------------

func _remember_glade_things() -> void:
	_glade_spots.clear()
	if glade_things == null:
		return
	for child: Node in glade_things.get_children():
		var script := _liftable_script(child)
		if script == null:
			continue
		_glade_spots.append({"node": child, "kind": script.kind, "variant": script.variant,
			"position": (child as Node2D).position, "gone_at": -1.0})


## A thing that was taken comes back at its spot `refill_ms` later (at once with `now`), unless the
## slime stands on it.
func _refill_glade_things(now: bool = false) -> void:
	var clock := Services.now_ms()
	for spot: Dictionary in _glade_spots:
		var node: Variant = spot["node"]
		if is_instance_valid(node) and node is Node and not (node as Node).is_queued_for_deletion():
			continue
		if float(spot["gone_at"]) < 0.0 and not now:
			spot["gone_at"] = clock
			continue
		if not now and clock - float(spot["gone_at"]) < refill_ms:
			continue
		var at: Vector2 = glade_things.to_global(spot["position"])
		if _player != null and (_player.call(&"get_centre") as Vector2).distance_to(at) < 56.0:
			continue
		spot["node"] = _spawn_liftable(str(spot["kind"]), int(spot["variant"]), spot["position"])
		spot["gone_at"] = -1.0


func _spawn_liftable(kind: String, variant: int, at: Vector2) -> Node2D:
	var packed := load(LIFTABLE_SCENE) as PackedScene
	var root := packed.instantiate() as Node2D
	var script := root.get_node_or_null(^"LiftableScript")
	if script != null:
		script.set(&"kind", kind)
		script.set(&"variant", variant)
	root.position = at
	root.scale = Vector2(0.2, 0.2)
	glade_things.add_child(root)
	var tween := root.create_tween()
	tween.tween_property(root, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_POP_IN)
	return root


# --- after the prologue --------------------------------------------------------------------------

## The places as they are after the prologue: path open, gate open, nobody here.
func _settle() -> void:
	phase = Phase.SETTLED
	_started = true
	set_physics_process(false)
	if path_blocked != null:
		for child: Node in path_blocked.get_children():
			if _is_liftable(child):
				path_blocked.remove_child(child)
				child.queue_free()
	if barrier != null:
		barrier.queue_free()
		barrier = null
	for placed: PlacedEnemyScript in _placed([worm_struck_a, worm_struck_b, worm_biter, worm_other]):
		_take_out(placed)
	if yoi != null:
		yoi.get_parent().remove_child(yoi)
		yoi.queue_free()
		yoi = null
	if gate != null and gate.has_method(&"open_now"):
		gate.call(&"open_now")


# --- helpers ---------------------------------------------------------------------------------------

## Takes a placed enemy out of the world now (before the world's enemies spawn, or after its scene):
## its enemy too, when it stands.
func _take_out(item: Variant) -> void:
	if not (is_instance_valid(item) and item is Object and item is PlacedEnemyScript):
		return
	var placed := item as PlacedEnemyScript
	if not placed.is_inside_tree():
		return
	var enemy := placed.get_enemy()
	if enemy != null and enemy.get_parent() != null and not bool(enemy.call(&"is_defeated")):
		enemy.get_parent().queue_free()
	placed.get_parent().remove_child(placed)
	placed.queue_free()


func _freeze_worms() -> void:
	for placed: PlacedEnemyScript in _placed([worm_struck_a, worm_struck_b, worm_biter, worm_other]):
		var enemy := _enemy_of(placed)
		if enemy == null:
			continue
		enemy.set_physics_process(false)
		var visual := enemy.get(&"visual") as Sprite2D
		var animation := enemy.get(&"animation") as AnimationPlayer
		if animation != null and animation.has_animation(&"idle-side"):
			animation.play(&"idle-side")
		if visual != null and yoi != null:
			visual.flip_h = yoi.global_position.x < (enemy.call(&"get_centre") as Vector2).x


func _kill(placed: Variant) -> void:
	var enemy := _enemy_of(placed)
	if enemy == null:
		return
	enemy.set_physics_process(true)
	enemy.call(&"take_reaction_damage", maxf(1.0, float(enemy.get(&"max_health"))))


## A worm's bite at `target` (the attack clip and a short lunge of its picture; its body stays).
func _worm_lunge(placed: Variant, target: Node2D) -> void:
	var enemy := _enemy_of(placed)
	if enemy == null or target == null:
		return
	var visual := enemy.get(&"visual") as Sprite2D
	var animation := enemy.get(&"animation") as AnimationPlayer
	if animation != null and animation.has_animation(&"attack-side"):
		animation.play(&"attack-side")
	if visual == null:
		return
	var toward := (target.global_position - visual.global_position).normalized()
	visual.flip_h = toward.x < 0.0
	var start := visual.position
	var tween := visual.create_tween()
	tween.tween_property(visual, "position", start + toward * 18.0, 0.18).set_delay(0.3)
	tween.tween_property(visual, "position", start, 0.3)
	tween.tween_callback(func() -> void:
		if animation != null and animation.has_animation(&"idle-side"):
			animation.play(&"idle-side"))


## The placed enemies of `list` that are still in the world (taken-out ones are freed).
static func _placed(list: Array) -> Array[PlacedEnemyScript]:
	var kept: Array[PlacedEnemyScript] = []
	for item: Variant in list:
		if is_instance_valid(item) and item is Object and item is PlacedEnemyScript:
			kept.append(item as PlacedEnemyScript)
	return kept


func _enemy_of(placed: Variant) -> Node:
	if not (is_instance_valid(placed) and placed is Object and placed is PlacedEnemyScript):
		return null
	return (placed as PlacedEnemyScript).get_enemy()


func _x_toward(from: Node2D, placed: Variant) -> float:
	if from == null or not (is_instance_valid(placed) and placed is Node2D):
		return -1.0
	return -1.0 if (placed as Node2D).global_position.x < from.global_position.x else 1.0


func _tween_zoom(camera: Object, from: float, to: float, ms: float) -> void:
	var tween := create_tween()
	tween.tween_method(func(z: float) -> void:
		if is_instance_valid(camera):
			camera.call(&"set_zoom_level", z), from, to, maxf(0.01, ms / 1000.0)).set_trans(Tween.TRANS_SINE)


func _camera() -> Object:
	var world := Services.world()
	return world.camera if world != null else null


func _population() -> Node:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	var population: Variant = main.get(&"enemy_population") if main != null else null
	return population as Node if is_instance_valid(population) and population is Node else null


func _player_root() -> Node2D:
	if _player == null:
		return null
	var body: Variant = _player.get(&"body")
	return body as Node2D if body is Node2D else null


## The slime pops out of the bubble: its picture squashes and springs back.
func _squash_in(root: Node2D) -> void:
	var visual: Variant = _player.get(&"visual")
	if not visual is Node2D:
		return
	var sprite := visual as Node2D
	var base := sprite.scale
	sprite.scale = base * Vector2(1.35, 0.55)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", base * Vector2(0.85, 1.2), 0.16).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(sprite, "scale", base, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var feel := Services.feel()
	if feel != null:
		feel.particles(&"slime-splash", root.global_position - Vector2(0.0, 12.0))


func _hud() -> CanvasLayer:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP) if is_inside_tree() else null
	var hud: Variant = main.get(&"hud") if main != null else null
	return hud as CanvasLayer if hud is CanvasLayer else null


func _set_hud_visible(shown: bool) -> void:
	var hud := _hud()
	if hud == null:
		return
	hud.visible = shown
	# The docked minimap hangs under a plain Node (MapUi): the layer's visibility does not reach it.
	var minimap := hud.get_node_or_null(^"MapUi/Minimap") as CanvasItem
	if minimap != null:
		minimap.visible = shown


## The HUD fades in after the birth (question 113).
func _fade_hud_in() -> void:
	var hud := _hud()
	if hud == null:
		return
	_set_hud_visible(true)
	for child: Node in hud.get_children():
		if not child is CanvasItem:
			continue
		var item := child as CanvasItem
		var shown := item.modulate.a
		if shown <= 0.0:
			continue
		item.modulate.a = 0.0
		var tween := item.create_tween()
		tween.tween_property(item, "modulate:a", shown, hud_fade_ms / 1000.0)


static func _is_liftable(node: Node) -> bool:
	return _liftable_script(node) != null


static func _liftable_script(node: Node) -> LiftableScript:
	if node == null:
		return null
	return node.get_node_or_null(^"LiftableScript") as LiftableScript
