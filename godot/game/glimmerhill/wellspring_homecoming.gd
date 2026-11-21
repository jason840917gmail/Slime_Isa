extends Node2D
## A Pearl comes home (docs/godot/PROLOGUE.md "The homecoming"; owner, 2026-11-17 and 2026-11-19,
## question 159): the node `WellspringHomecoming` under B4's `Wellspring` (`west-village-b4`). When the
## slime comes within `trigger_radius` of the pool with a Pearl taken (`pearl.<id>`) and not yet home
## (`pearl.<id>.home`), a short scene plays, one Pearl after another when it brings several (the
## wake table's order, game/glimmerhill/glimmerhill_wake.gd):
##
## 1. the bars come in and the slime holds still, facing the pool; Bob says nothing;
## 2. the Pearl (the `object.pearl` scene's picture and glow) rises out of the slime, floats over the
##    pool, hovers and sinks in with a splash; the pool's glow flares and settles one step brighter
##    (`glow_step_alpha`, `glow_step_scale` a Pearl home, kept on every later visit);
## 3. `pearl.<id>.home` is set (the main quest's stage, quests spec 14.2) and a card
##    (AbilityCeremony.request_entry, its bubble over the slime) names the part of Glimmerhill that
##    wakes;
## 4. the part wakes: its wake flag and the Pearl's `alsoFlags` (Pearl 2: `workshop.restored`,
##    Slimeshire's Workshop; Pearl 3: `forge.restored`, its Forge). When that part's fountain stands in this world (Market Hill's, for Pearl
##    1), the camera pans to it first, so the fountain bursts into flow, the grey lifts and the
##    villagers stretch awake on screen, then pans back to the slime.
##
## Nothing happens while the prologue runs. The campfire beside the pool is a plain prop of the
## chunk. Every timing is a property here.
##
## Owner: world (Glimmerhill).

const Services := preload("res://game/shared/services.gd")
const GlimmerhillWake := preload("res://game/glimmerhill/glimmerhill_wake.gd")
const PrologueScene := preload("res://game/prologue/prologue_scene.gd")
const PrologueState := preload("res://game/prologue/prologue_state.gd")
const CinemaBars := preload("res://game/prologue/cinema_bars.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")

const PEARL_SCENE := "object.pearl"
const FOUNTAINS_GROUP := &"goo_fountains"
const CUE_RISE := &"BubbleRise"
const CUE_SINK := &"WaterSplash"
const SPLASH := &"slime-splash"
const SPARKLE := &"loot-sparkle"
const KICKER := "Pearl of the Wellspring home (%d of 8)"
## Over the slime and the pool's things while it floats.
const PEARL_Z := 5
const BOB_PX := 5.0
const BOB_PERIOD_S := 1.6
## The glow's strongest alpha, however many Pearls are home.
const GLOW_MAX_ALPHA := 0.9

## The pool (its middle is where the Pearl sinks) and its glow (soft_glow.gd).
@export var pool: Node2D
@export var glow: Node2D
## How near the pool's middle (units) the slime's middle sets the scene off.
@export var trigger_radius: float = 300.0
## The scene's beats (ms of game time) and the Pearl's flight (units).
@export var intro_ms: float = 600.0
@export var rise_px: float = 70.0
@export var rise_ms: float = 900.0
@export var glide_ms: float = 1400.0
@export var over_pool_rise: float = 64.0
@export var hover_ms: float = 900.0
@export var sink_ms: float = 1000.0
@export var after_sink_ms: float = 700.0
## The glow's flare as the Pearl sinks in (alpha added, ms), and its step a Pearl home.
@export var glow_flare_alpha: float = 0.35
@export var glow_flare_ms: float = 1400.0
@export var glow_step_alpha: float = 0.1
@export var glow_step_scale: float = 0.08
## The pan to the waking part's fountain (when it stands in this world), the look at it, the way back.
@export var pan_ms: float = 1600.0
@export var watch_ms: float = 2600.0
@export var return_ms: float = 1300.0
## A part woken elsewhere (its fountain in another world): the pause after it wakes.
@export var elsewhere_ms: float = 500.0
@export var outro_ms: float = 400.0

var _player: Node
var _cinema: CinemaBars
var _playing := false
var _holding := false
var _pearl: Node2D
var _pearl_visual: Node2D
var _bob := false
var _clock := 0.0
var _glow_base_color := Color(0, 0, 0, 0)
var _glow_base_radius := Vector2.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if glow != null:
		_glow_base_color = glow.get(&"color")
		_glow_base_radius = glow.get(&"radius")
		_apply_glow(GlimmerhillWake.pearls_home())


func _physics_process(_delta: float) -> void:
	if _holding:
		PrologueScene.hold(_player)
	if _playing or pool == null:
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	if (player.call(&"get_centre") as Vector2).distance_to(pool.global_position) > trigger_radius:
		return
	if PrologueState.is_running(Services.run()) or GlimmerhillWake.pearls_waiting().is_empty():
		return
	_player = player
	_play()


func _process(delta: float) -> void:
	if not _bob or _pearl_visual == null or not is_instance_valid(_pearl_visual):
		return
	_clock += delta
	_pearl_visual.position.y = sin(_clock * TAU / BOB_PERIOD_S) * BOB_PX


## True while the scene plays.
func is_playing() -> bool:
	return _playing


## The scene (a coroutine): every Pearl waiting, one after another.
func _play() -> void:
	_playing = true
	_holding = true
	if _cinema == null:
		_cinema = CinemaBars.new()
		add_child(_cinema)
	_cinema.show_bars()
	if _player != null and pool != null:
		_player.call(&"face", (pool.global_position - (_player.call(&"get_centre") as Vector2)).normalized())
	await PrologueScene.wait(get_tree(), intro_ms)
	for entry: Dictionary in GlimmerhillWake.pearls_waiting():
		await _bring_home(entry)
	await PrologueScene.wait(get_tree(), outro_ms)
	_cinema.hide_bars()
	_holding = false
	_playing = false
	var run := Services.run()
	if run != null:
		run.schedule_autosave()


## One Pearl home: out of the slime, over the pool, in; its flags; the waking part; its card.
func _bring_home(entry: Dictionary) -> void:
	var run := Services.run()
	var pearl_id := str(entry.get("pearlId", ""))
	var feel := Services.feel()
	var tree := get_tree()
	var icon := _make_pearl()
	var from: Vector2 = _player.call(&"get_centre") if _player != null and is_instance_valid(_player) else global_position
	var over_pool := (pool.global_position if pool != null else global_position) - Vector2(0.0, over_pool_rise)
	if _pearl != null:
		_pearl.global_position = from
		_pearl.scale = Vector2(0.3, 0.3)
		_pearl.modulate.a = 0.0
		if feel != null:
			feel.audio_cue(CUE_RISE)
			feel.particles(SPARKLE, from)
		var rise := create_tween().set_parallel(true)
		rise.tween_property(_pearl, "global_position", from - Vector2(0.0, rise_px), rise_ms / 1000.0) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		rise.tween_property(_pearl, "scale", Vector2.ONE, rise_ms / 1000.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rise.tween_property(_pearl, "modulate:a", 1.0, rise_ms / 2000.0)
		await rise.finished
		_bob = true
		var glide := create_tween()
		glide.tween_property(_pearl, "global_position", over_pool, glide_ms / 1000.0).set_trans(Tween.TRANS_SINE) \
				.set_ease(Tween.EASE_IN_OUT)
		await glide.finished
		await PrologueScene.wait(tree, hover_ms)
		_bob = false
		var sink := create_tween().set_parallel(true)
		sink.tween_property(_pearl, "global_position", over_pool + Vector2(0.0, over_pool_rise), sink_ms / 1000.0) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		sink.tween_property(_pearl, "scale", Vector2(0.4, 0.4), sink_ms / 1000.0).set_trans(Tween.TRANS_QUAD) \
				.set_ease(Tween.EASE_IN)
		sink.tween_property(_pearl, "modulate:a", 0.0, sink_ms / 1000.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await sink.finished
		_pearl.queue_free()
		_pearl = null
		_pearl_visual = null
	if feel != null and pool != null:
		feel.audio_cue(CUE_SINK)
		feel.particles(SPLASH, pool.global_position)
		feel.particles(SPARKLE, pool.global_position - Vector2(0.0, 20.0))
	if run != null:
		run.set_flag(GlimmerhillWake.home_flag(pearl_id))
	_flare_glow(GlimmerhillWake.pearls_home())
	await PrologueScene.wait(tree, after_sink_ms)
	# The card first, while the camera is on the slime (the ceremony's bubble rises out of it).
	await _card(entry, icon)
	var fountain := _fountain_of(str(entry.get("part", "")))
	var camera := _camera()
	if fountain != null and camera != null:
		camera.call(&"release_room")
		camera.call(&"pan_to", fountain.call(&"view_point"), pan_ms, false)
		await PrologueScene.wait(tree, pan_ms + 150.0)
		GlimmerhillWake.wake_for_pearl(entry)
		await PrologueScene.wait(tree, watch_ms)
		if _player != null and is_instance_valid(_player):
			camera.call(&"pan_to", _player.call(&"get_centre"), return_ms, true)
		await PrologueScene.wait(tree, return_ms + 50.0)
	else:
		GlimmerhillWake.wake_for_pearl(entry)
		await PrologueScene.wait(tree, elsewhere_ms)


func _card(entry: Dictionary, icon: Texture2D) -> void:
	if not AbilityCeremony.enabled(get_tree()):
		return
	AbilityCeremony.request_entry(get_tree(), {"kicker": KICKER % int(entry.get("number", 1)),
		"name": str(entry.get("cardName", GlimmerhillWake.part_name(str(entry.get("part", ""))))),
		"line": str(entry.get("cardLine", "")), "how": "", "icon": icon})
	await PrologueScene.ceremony_done(get_tree())


## The Pearl's picture and glow (the `object.pearl` scene without its script, which would take it), in
## the world over the slime; returns its picture for the card.
func _make_pearl() -> Texture2D:
	var world := Services.world()
	var node: Node = world.instantiate_scene(PEARL_SCENE) if world != null else null
	if node == null or not node is Node2D:
		if node != null:
			node.free()
		return null
	node.set_script(null)
	_pearl = node as Node2D
	_pearl.name = "HomecomingPearl"
	_pearl.z_index = PEARL_Z
	_pearl_visual = _pearl.get_node_or_null(^"Visual") as Node2D
	var parent: Node = world.entities_root()
	(parent if parent != null else self).add_child(_pearl)
	var sprite := _pearl_visual as Sprite2D
	return sprite.texture if sprite != null else null


## The goo fountain of `part_id` standing in this world (none for a part elsewhere).
func _fountain_of(part_id: String) -> Node2D:
	if part_id.is_empty():
		return null
	for node: Node in get_tree().get_nodes_in_group(FOUNTAINS_GROUP):
		if node is Node2D and node.is_inside_tree() and str(node.call(&"part_id")) == part_id:
			return node as Node2D
	return null


## The glow as it is with `home` Pearls home.
func _apply_glow(home: int) -> void:
	if glow == null:
		return
	glow.set(&"color", _glow_color(home))
	glow.set(&"radius", _glow_base_radius * (1.0 + glow_step_scale * float(home)))


## The glow flares as a Pearl sinks in, then settles one step brighter.
func _flare_glow(home: int) -> void:
	if glow == null:
		return
	var settled := _glow_color(home)
	var flare := settled
	flare.a = minf(1.0, settled.a + glow_flare_alpha)
	var radius := _glow_base_radius * (1.0 + glow_step_scale * float(home))
	var tween := create_tween()
	tween.tween_property(glow, "color", flare, glow_flare_ms / 3000.0).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(glow, "radius", radius * 1.15, glow_flare_ms / 3000.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(glow, "color", settled, glow_flare_ms * 2.0 / 3000.0).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(glow, "radius", radius, glow_flare_ms * 2.0 / 3000.0).set_trans(Tween.TRANS_SINE)


func _glow_color(home: int) -> Color:
	var color := _glow_base_color
	color.a = minf(GLOW_MAX_ALPHA, _glow_base_color.a + glow_step_alpha * float(home))
	return color


func _camera() -> Object:
	var world := Services.world()
	return world.camera if world != null else null
