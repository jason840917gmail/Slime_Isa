extends Node
## Autoload `MusicDirector` (Phaser `features/audio/MusicDirector.ts`, the music half of
## `UniversalSceneWorldController` and the `area.enter` cue of `AudioEventBridge`).
## docs/godot/specs/audio.md. Access: `Services.music()` (null while unregistered).
##
## Owns every music-bus player: the registered world's music node, claimed and moved under this
## node (so a world teardown does not free it), and `audio.global`'s `Music/BossMusic`. A track's
## heard volume is `volume_linear = authored volume x fade gain x menu duck`; the buses carry the
## player's settings (`apply_mix`). PROCESS_MODE_ALWAYS: fades run on real time through hit-stops
## and menus, as Phaser's presentation update did.
##
## Hooked up through signals: `WorldService.world_registered` (adopt the world; `AreaTransition`
## for main's worlds), the `boss_camp` group's `boss_engaged` / `boss_disengaged`,
## `SceneTree.node_added` (a music-bus autoplay is switched off before it can start at full
## volume) and the adopted world root's `tree_exiting` (fade out if no leave fade ran, e.g. quit to
## title). Two reads each frame: main's `is_transitioning()` (the 320 ms leave fade) and the tree's
## pause reasons (the menu duck). The player's `defeated` needs no listener: the camps turn it into
## a disengage.
##
## Works unregistered too: an instance added anywhere in the tree adopts the current world in
## `_ready` and then follows the same signals.
##
## Owner: audio.

const Services := preload("res://game/shared/services.gd")
const AreaTravel := preload("res://game/world/area_travel.gd")
const WorldServiceType := preload("res://game/autoload/world_service.gd")

## World music rises this slowly after arriving (MusicDirector.ts:22).
const MUSIC_FADE_IN_MS := 1500.0
## World and boss music swap over this long (MusicDirector.ts:24).
const MUSIC_CROSSFADE_MS := 1200.0
## Music level under a pause menu, reached in MUSIC_DUCK_MS (MusicDirector.ts:26-27).
const MUSIC_PAUSE_DUCK := 0.35
const MUSIC_DUCK_MS := 250.0
## Phaser's frame delta sanity rule (TimeStep.js:99, 174, 576-585): a frame longer than
## 1000 / minFps (5) counts as the last sane one, so a loading stall never jumps a fade.
const MAX_SANE_FRAME_MS := 200.0
const MUSIC_BUS := &"Music"
const GLOBAL_AUDIO_SCENE_ID := "audio.global"
const BOSS_MUSIC_PATH := ^"Music/BossMusic"
const BOSS_CAMP_GROUP := &"boss_camp"
## main.gd's group (`travel_to`, `is_transitioning`); only its worlds play the arrival cue.
const MAIN_GROUP := &"world_main"
## Phaser `area.enter` -> `AreaTransition` (AudioEventBridge.ts:102, WorldScene.ts:515).
const ARRIVAL_CUE := &"AreaTransition"
const WORLD_TRACK_NAME := "WorldMusic"
const BOSS_TRACK_NAME := "BossMusic"
const FADING_TRACK_NAME := "FadingMusic"
## Set on a music-bus player whose autoplay this director switched off.
const CLAIMED_META := &"music_director_claimed"

## The Web Audio unlock gate (spec 4): fades wait for it and tracks start only once it is open.
## Desktop: open from the start. Web: opened by the first key, mouse button or touch.
var audio_unlocked: bool = not OS.has_feature("web")
## Play `AreaTransition` when one of main's worlds registers (Phaser `area.enter`; never for a
## title backdrop, which is not under main). Off: no arrival cue at all.
var play_arrival_cue: bool = true

var _world_track: AudioStreamPlayer
var _world_base: float = 1.0
var _world_wanted: bool = false
var _boss_track: AudioStreamPlayer
var _boss_base: float = 1.0
var _boss_wanted: bool = false
var _boss_track_missing: bool = false
var _world_gain: float = 0.0
var _boss_gain: float = 0.0
var _duck: float = 1.0
## camp_id -> true for every camp whose boss fight is on.
var _engaged: Dictionary = {}
## The leave fade's duration in ms, < 0 when not leaving.
var _leaving_ms: float = -1.0
## Old world tracks still fading out: {"player", "base", "gain", "rate" (gain per ms)}.
var _fading: Array[Dictionary] = []
## Instance ids of the boss camps whose signals are connected.
var _bound_camps: Dictionary = {}
var _world_service_bound: bool = false
## An explicit pause source (`set_menu_paused`), on top of the tree's pause reasons.
var _menu_paused_explicit: bool = false
## Instance id of the adopted world root (0 = none).
var _world_root_id: int = 0
var _was_transitioning: bool = false
var _last_sane_frame_ms: float = 1000.0 / 60.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	_bind_world_service()
	var world := Services.world()
	if world != null and world.world_root != null and is_instance_valid(world.world_root):
		_adopt_world(world.world_root)


## Real frame time (paused or not), with Phaser's 200 ms sanity rule.
func _process(delta: float) -> void:
	var frame_ms := delta * 1000.0
	if frame_ms > MAX_SANE_FRAME_MS:
		frame_ms = _last_sane_frame_ms
	else:
		_last_sane_frame_ms = frame_ms
	advance(frame_ms)


## Phaser unlocks on touchstart/touchend/mousedown/mouseup/keydown (WebAudioSoundManager.js).
func _input(event: InputEvent) -> void:
	if audio_unlocked:
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch \
			or (event is InputEventKey and event.is_pressed()):
		audio_unlocked = true


# --- Phaser MusicDirector API ----------------------------------------------------------------

## `setBossFight` for one camp (MusicDirector.ts:48-51): the fight is on while any camp is
## engaged; engaging starts the boss track from the top unless it still plays (fading out).
func set_boss_fight(active: bool, camp_id: String = "") -> void:
	if not active:
		_engaged.erase(camp_id)
		return
	_engaged[camp_id] = true
	if _has_boss_track() and not _boss_wanted:
		_boss_wanted = true
		_start_wanted_tracks()


## Phaser `setPaused` for a menu that does not pause the tree (the title screen: Phaser's
## `title-screen` is a pause source, so its music plays ducked). The caller clears it again.
## Pausing the tree with any reason but `hit-stop` ducks without this.
func set_menu_paused(paused: bool) -> void:
	_menu_paused_explicit = paused


## `fadeOut` (MusicDirector.ts:58-60): every track falls to silence over `duration_ms` (before
## leaving the area). Cleared when the next world registers.
func fade_out(duration_ms: float) -> void:
	_leaving_ms = maxf(1.0, duration_ms)


## One Phaser `update(deltaMs)` (MusicDirector.ts:62-81), plus binding new boss camps and
## watching main's travel. `_process` calls it every frame; tests may call it directly.
func advance(delta_ms: float) -> void:
	_bind_world_service()
	_bind_new_camps()
	_watch_travel()
	var step := maxf(0.0, delta_ms)
	var duck_target := MUSIC_PAUSE_DUCK if is_menu_paused() else 1.0
	_duck = _approach(_duck, duck_target, step / MUSIC_DUCK_MS * (1.0 - MUSIC_PAUSE_DUCK))
	if not audio_unlocked:
		_apply_volumes()
		return
	_start_wanted_tracks()
	var boss_active := is_boss_fight() and _has_boss_track()
	var leaving := is_leaving()
	var world_target := 0.0 if leaving or boss_active else 1.0
	var boss_target := 1.0 if not leaving and boss_active else 0.0
	var world_duration := MUSIC_FADE_IN_MS
	if leaving:
		world_duration = _leaving_ms
	elif boss_active or _boss_gain > 0.0:
		world_duration = MUSIC_CROSSFADE_MS
	var boss_duration := _leaving_ms if leaving else MUSIC_CROSSFADE_MS
	_world_gain = _approach(_world_gain, world_target, step / world_duration)
	_boss_gain = _approach(_boss_gain, boss_target, step / boss_duration)
	_advance_fading(step)
	_apply_volumes()
	# A finished boss track stops at silence so the next fight starts from the top.
	if _boss_gain <= 0.0 and not boss_active and _boss_wanted:
		_boss_wanted = false
		_stop(_boss_track)


# --- state ---------------------------------------------------------------------------------

func world_gain() -> float:
	return _world_gain


func boss_gain() -> float:
	return _boss_gain


func duck() -> float:
	return _duck


func is_boss_fight() -> bool:
	return not _engaged.is_empty()


func is_leaving() -> bool:
	return _leaving_ms > 0.0


## Phaser `setPaused` source: `set_menu_paused(true)`, or the tree is paused by a menu, i.e. by
## any reason but a hit-stop (a hit-stop is not a pause source in Phaser), or by `modal` even
## during a hit-stop.
func is_menu_paused() -> bool:
	if _menu_paused_explicit:
		return true
	if not is_inside_tree() or not get_tree().paused:
		return false
	var world := Services.world()
	if world == null:
		return true
	return world.has_pause_reason(WorldServiceType.PAUSE_MODAL) \
		or not world.has_pause_reason(WorldServiceType.PAUSE_HIT_STOP)


## The current world's music player (under this node), null when the world has none.
func world_track() -> AudioStreamPlayer:
	return _world_track if _valid(_world_track) else null


## `audio.global`'s BossMusic (under this node), null when the scene has none.
func boss_track() -> AudioStreamPlayer:
	return _boss_track if _valid(_boss_track) else null


# --- mix (the shell's hook; spec 6) ----------------------------------------------------------

## Phaser `applyMix` (SettingsSurfacePort.ts:81-87) onto the Godot buses: Master = `master`
## (`muted` mutes Master), Effects and Ambience = `effects` (ambience follows effects), Music =
## `music`. Linear 0..1 like Phaser's gains; the Master bus multiplies the others as
## `GlobalAudioServices.volume` (bus x master) did. Static: callable before registration.
static func apply_mix(master: float, effects: float, music: float, muted: bool) -> void:
	set_bus_volume_linear(&"Master", master)
	var master_index := AudioServer.get_bus_index(&"Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, muted)
	set_bus_volume_linear(&"Effects", effects)
	set_bus_volume_linear(&"Ambience", effects)
	set_bus_volume_linear(&"Music", music)


## Sets one bus to a linear volume clamped to [0, 1]; a non-finite value is ignored.
static func set_bus_volume_linear(bus: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("MusicDirector: no audio bus '%s'" % bus)
		return
	if not is_finite(value):
		return
	AudioServer.set_bus_volume_linear(index, clampf(value, 0.0, 1.0))


# --- world adoption --------------------------------------------------------------------------

func _bind_world_service() -> void:
	if _world_service_bound:
		return
	var world := Services.world()
	if world == null:
		return
	_world_service_bound = true
	if not world.world_registered.is_connected(_on_world_registered):
		world.world_registered.connect(_on_world_registered)


func _on_world_registered(_payload: Dictionary) -> void:
	var world := Services.world()
	if world == null or world.world_root == null:
		return
	_adopt_world(world.world_root)
	if play_arrival_cue and _is_main_world(world.world_root):
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(ARRIVAL_CUE)


## The Godot stand-in for Phaser's page reload (spec 7.4): forget the leave fade and the old
## world's fights, let the old world track fade out (or drop it when silent), claim the new
## world's track at gain 0, and bind the new world's camps.
func _adopt_world(root: Node) -> void:
	if root.get_instance_id() == _world_root_id:
		_bind_new_camps()
		return
	var old_fade_ms := _leaving_ms if is_leaving() else MUSIC_CROSSFADE_MS
	_leaving_ms = -1.0
	_engaged.clear()
	for id: int in _bound_camps.keys():
		if not is_instance_id_valid(id):
			_bound_camps.erase(id)
	_retire_world_track(old_fade_ms)
	_ensure_boss_track()
	_world_root_id = root.get_instance_id()
	root.tree_exiting.connect(_on_world_exiting.bind(_world_root_id), CONNECT_ONE_SHOT)
	var music := _claim_world_music(root)
	if music != null:
		_world_track = music
		_world_wanted = true
		_apply_volumes()
		_start_wanted_tracks()
	_bind_new_camps()


func _retire_world_track(fade_ms: float) -> void:
	var old := _world_track
	_world_track = null
	_world_wanted = false
	var gain := _world_gain
	_world_gain = 0.0
	if not _valid(old):
		return
	if gain > 0.0 and old.playing:
		old.name = FADING_TRACK_NAME
		_fading.append({"player": old, "base": _world_base, "gain": gain, "rate": 1.0 / maxf(1.0, fade_ms)})
	else:
		_release(old)


## Phaser's world track: the first AudioStreamPlayer on the music bus under the world root in
## tree order (UniversalSceneWorldController.ts:1743). Stopped, moved under this node, silenced.
## Further music-bus players (none are authored) get their autoplay back, as in Phaser.
func _claim_world_music(root: Node) -> AudioStreamPlayer:
	var found: AudioStreamPlayer = null
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		var player := node as AudioStreamPlayer
		if player == null or player.bus != MUSIC_BUS:
			continue
		if found == null:
			found = player
		elif player.has_meta(CLAIMED_META):
			player.remove_meta(CLAIMED_META)
			player.set(&"autoplay_cue", true)
			_play(player)
	if found == null:
		return null
	_stop(found)
	if found.has_meta(CLAIMED_META):
		found.remove_meta(CLAIMED_META)
	_world_base = db_to_linear(found.volume_db)
	found.get_parent().remove_child(found)
	found.owner = null
	found.name = WORLD_TRACK_NAME
	found.volume_linear = 0.0
	add_child(found)
	return found


## `audio.global`'s Music/BossMusic from a private instance of the scene (the rest is freed).
func _ensure_boss_track() -> void:
	if _valid(_boss_track) or _boss_track_missing:
		return
	var world := Services.world()
	if world == null:
		return
	if world.scene_path(GLOBAL_AUDIO_SCENE_ID).is_empty():
		_boss_track_missing = true
		return
	var instance := world.instantiate_scene(GLOBAL_AUDIO_SCENE_ID)
	if instance == null:
		_boss_track_missing = true
		return
	var boss := instance.get_node_or_null(BOSS_MUSIC_PATH) as AudioStreamPlayer
	if boss == null:
		instance.free()
		_boss_track_missing = true
		return
	boss.get_parent().remove_child(boss)
	boss.owner = null
	instance.free()
	boss.name = BOSS_TRACK_NAME
	_boss_base = db_to_linear(boss.volume_db)
	boss.volume_linear = 0.0
	add_child(boss)
	_boss_track = boss


## Switches off the autoplay of every music-bus player entering the tree outside this node
## (before its `_ready`), so a world track never sounds before this director has it
## (MusicDirector.ts:43-46). In Phaser every music-bus node is a world track or BossMusic.
func _on_node_added(node: Node) -> void:
	if not (node is AudioStreamPlayer):
		return
	var player := node as AudioStreamPlayer
	var autoplay: Variant = player.get(&"autoplay_cue")
	if player.bus != MUSIC_BUS or not (autoplay is bool and autoplay) or is_ancestor_of(player):
		return
	player.set(&"autoplay_cue", false)
	player.set_meta(CLAIMED_META, true)


## The adopted world leaves the tree without a leave fade (quit to title, a test teardown): fade
## its music out over the leave time instead of letting it outlive the world at full volume.
func _on_world_exiting(root_id: int) -> void:
	if root_id == _world_root_id and not is_leaving():
		fade_out(AreaTravel.LEAVE_FADE_MS)


## True when `root` is one of main's worlds (not a title backdrop).
func _is_main_world(root: Node) -> bool:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP) if is_inside_tree() else null
	return main != null and main.is_ancestor_of(root)


# --- camps and travel ------------------------------------------------------------------------

## Binds every camp in BOSS_CAMP_GROUP once (as the boss bar does); a camp whose boss already
## lives counts as engaged.
func _bind_new_camps() -> void:
	if not is_inside_tree():
		return
	for camp: Node in get_tree().get_nodes_in_group(BOSS_CAMP_GROUP):
		var id := camp.get_instance_id()
		if _bound_camps.has(id):
			continue
		_bound_camps[id] = true
		if camp.has_signal(&"boss_engaged"):
			camp.connect(&"boss_engaged", _on_boss_engaged)
		if camp.has_signal(&"boss_disengaged"):
			camp.connect(&"boss_disengaged", _on_boss_disengaged)
		if camp.has_method(&"get_live_boss") and camp.call(&"get_live_boss") != null:
			set_boss_fight(true, str(camp.get(&"camp_id")))


func _on_boss_engaged(payload: Dictionary) -> void:
	set_boss_fight(true, str(payload.get("campId", "")))


func _on_boss_disengaged(payload: Dictionary) -> void:
	set_boss_fight(false, str(payload.get("campId", "")))


## Phaser `fadeOutMusic(AREA_LEAVE_FADE_MS)` (WorldScene.ts:1011-1016): starts the leave fade when
## main starts a travel. main.gd may call `fade_out` itself instead; then this does nothing.
func _watch_travel() -> void:
	if not is_inside_tree():
		return
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	var transitioning := main != null and main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning"))
	if transitioning and not _was_transitioning and not is_leaving():
		fade_out(AreaTravel.LEAVE_FADE_MS)
	_was_transitioning = transitioning


# --- tracks ----------------------------------------------------------------------------------

func _has_boss_track() -> bool:
	return _valid(_boss_track)


## Starts the tracks that want to play once audio is unlocked (Phaser `startWhenUnlocked`).
func _start_wanted_tracks() -> void:
	if not audio_unlocked or not is_inside_tree():
		return
	if _world_wanted and _valid(_world_track) and not _world_track.playing:
		_play(_world_track)
	if _boss_wanted and _valid(_boss_track) and not _boss_track.playing:
		_play(_boss_track)


func _advance_fading(step_ms: float) -> void:
	for index in range(_fading.size() - 1, -1, -1):
		var entry: Dictionary = _fading[index]
		var player: Variant = entry["player"]
		if not is_instance_valid(player):
			_fading.remove_at(index)
			continue
		entry["gain"] = _approach(float(entry["gain"]), 0.0, step_ms * float(entry["rate"]))
		if float(entry["gain"]) <= 0.0:
			_fading.remove_at(index)
			_release(player)


func _apply_volumes() -> void:
	if _valid(_world_track):
		_world_track.volume_linear = _world_base * _world_gain * _duck
	if _valid(_boss_track):
		_boss_track.volume_linear = _boss_base * _boss_gain * _duck
	for entry: Dictionary in _fading:
		var player: Variant = entry["player"]
		if is_instance_valid(player):
			(player as AudioStreamPlayer).volume_linear = float(entry["base"]) * float(entry["gain"]) * _duck


func _release(player: Variant) -> void:
	if not _valid(player):
		return
	var stream_player := player as AudioStreamPlayer
	_stop(stream_player)
	if stream_player.get_parent() != null:
		stream_player.get_parent().remove_child(stream_player)
	stream_player.queue_free()


## `play_cue` on converted players (loop rules), `play` otherwise.
static func _play(player: AudioStreamPlayer) -> void:
	if player.has_method(&"play_cue"):
		player.call(&"play_cue")
	else:
		player.play()


static func _stop(player: Variant) -> void:
	if not is_instance_valid(player):
		return
	var stream_player := player as AudioStreamPlayer
	if stream_player.has_method(&"stop_cue"):
		stream_player.call(&"stop_cue")
	else:
		stream_player.stop()


## Untyped on purpose: the argument may be a freed player.
static func _valid(player: Variant) -> bool:
	return is_instance_valid(player) and not (player as Node).is_queued_for_deletion()


## MusicDirector.ts:84-88.
static func _approach(value: float, target: float, max_step: float) -> float:
	if value < target:
		return minf(target, value + max_step)
	if value > target:
		return maxf(target, value - max_step)
	return value
