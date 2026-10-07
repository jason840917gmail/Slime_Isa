extends RefCounted
## Music and global audio (docs/godot/specs/audio.md): the music director claims level-1's
## `MusicPlayer` and fades it in over 1500 ms; Fatty One Eye's camp crossfades to `BossMusic` over
## 1200 ms and back after the defeat or the player's death; a travel fades the music out with the
## 320 ms leave fade and the next world's music in, and a world leaving without a travel fades it
## out too; a menu pause ducks the music to 0.35 in 250 ms (a hit-stop does not); locked audio
## freezes the fades; `apply_mix` sets the buses; arrival and victory cues play on the Effects bus.
##
## Runs against `Services.music()` when the autoload is registered, otherwise against an instance
## added under main (freed with it). Exact numbers are stepped with `advance(ms)` while the
## director's own processing is off (switched back on when main leaves the tree); the travel test
## runs on real time.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const MusicDirectorScript := preload("res://game/audio/music_director.gd")
const BossCampScript := preload("res://game/scripts/boss_camp.gd")
const FattyScript := preload("res://game/scripts/fatty.gd")
const WorldServiceType := preload("res://game/autoload/world_service.gd")

const LEVEL1_MUSIC := "res://asset/audio/music/level-1-home-town.ogg"
const GLOOP_MUSIC := "res://asset/audio/music/gloop-forest.mp3"
## Authored volumes: level-1 MusicPlayer 0.55, gloop-forest 0.5, audio.global BossMusic 0.5.
const LEVEL1_BASE := 0.55
const GLOOP_BASE := 0.5
const BOSS_BASE := 0.5
const BOSS_PITCH := 1.12
const CAMP_ID := "level-1-fatty-one-eye-camp"
## Inside Fatty's activation circle (test_boss.gd FAR_INSIDE).
const FAR_INSIDE := Vector2(2528.0, 1852.0)
const TRAVEL_MAP := "gloop-forest"
const GAIN_EPS := 0.001
const VOLUME_EPS := 0.002


func test_level1_music_is_claimed_and_fades_in(t: TestContext) -> void:
	var director := _director(t)
	var track := director.world_track()
	if not t.check(track != null, "level-1 has no world track"):
		return
	t.check(_same_stream(track.stream, LEVEL1_MUSIC), "world track stream is not %s" % LEVEL1_MUSIC)
	t.equal(String(track.bus), "Music", "world track bus")
	t.check(track.get_parent() == director, "the world track is not under the director")
	t.check(track.playing, "the world track is not playing")
	t.equal(track.process_mode, Node.PROCESS_MODE_ALWAYS, "world track process mode")
	var world_root := t.world().world_root
	for node: Node in world_root.find_children("*", "AudioStreamPlayer", true, false):
		var player := node as AudioStreamPlayer
		t.check(not (player.bus == &"Music" and player.playing), "%s plays on the Music bus inside the world" % player.get_path())
	var ambience := world_root.get_node_or_null(^"Ambience") as AudioStreamPlayer
	if t.check(ambience != null, "level-1 has no Ambience player"):
		t.equal(String(ambience.bus), "Ambience", "ambience bus")
		t.check(ambience.playing, "the ambience is not playing")
	# The fade-in: 1500 ms from 0 to 1 (a registered director has already run a frame or two).
	var start := director.world_gain()
	t.between(start, 0.0, 0.3, "world gain right after the arrival")
	director.advance(750.0)
	t.near(director.world_gain(), minf(1.0, start + 0.5), GAIN_EPS, "world gain 750 ms later")
	t.near(track.volume_linear, LEVEL1_BASE * director.world_gain(), VOLUME_EPS, "world track volume mid-fade")
	director.advance(800.0)
	t.near(director.world_gain(), 1.0, GAIN_EPS, "world gain after the fade-in")
	t.near(track.volume_linear, LEVEL1_BASE, VOLUME_EPS, "world track volume after the fade-in")
	t.equal(director.boss_gain(), 0.0, "boss gain without a fight")


func test_boss_music_crossfades_in_and_returns_after_the_defeat(t: TestContext) -> void:
	var director := _director(t)
	director.advance(2000.0)
	var world_track := director.world_track()
	var boss_track := director.boss_track()
	if not t.check(world_track != null and boss_track != null, "missing world or boss track"):
		return
	t.check(not boss_track.playing, "the boss track plays before any fight")
	t.check(_same_stream(boss_track.stream, LEVEL1_MUSIC), "boss track stream is not %s" % LEVEL1_MUSIC)
	t.equal(String(boss_track.bus), "Music", "boss track bus")
	t.near(boss_track.pitch_scale, BOSS_PITCH, GAIN_EPS, "boss track pitch")
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	t.check(director.is_boss_fight(), "the director missed boss_engaged")
	t.check(boss_track.playing, "the boss track did not start on engage")
	director.advance(600.0)
	t.near(director.world_gain(), 0.5, GAIN_EPS, "world gain 600 ms into the crossfade")
	t.near(director.boss_gain(), 0.5, GAIN_EPS, "boss gain 600 ms into the crossfade")
	t.near(boss_track.volume_linear, BOSS_BASE * 0.5, VOLUME_EPS, "boss track volume mid-crossfade")
	director.advance(600.0)
	t.near(director.world_gain(), 0.0, GAIN_EPS, "world gain after the crossfade")
	t.near(director.boss_gain(), 1.0, GAIN_EPS, "boss gain after the crossfade")
	t.check(world_track.playing, "the world track stopped during the fight (it should run silently)")
	# Five spear hits defeat Fatty (140 hp); the camp's defeat bookkeeping is deferred a step.
	var fatty: FattyScript = fight["fatty"]
	var hits := 0
	while not fatty.is_defeated() and hits < 6:
		_hit(t, fatty, 30.0)
		hits += 1
	if not t.check(fatty.is_defeated(), "Fatty survived %d spear hits" % hits):
		return
	await t.steps(2)
	t.check(not director.is_boss_fight(), "the director still counts a fight after the defeat")
	var victory := _global_cue(&"Victory")
	if t.check(victory != null, "audio.global has no Effects/Victory"):
		t.check(victory.playing, "the Victory cue did not play on the defeat")
		t.equal(String(victory.bus), "Effects", "Victory bus")
	director.advance(600.0)
	t.near(director.world_gain(), 0.5, GAIN_EPS, "world gain 600 ms after the defeat")
	t.near(director.boss_gain(), 0.5, GAIN_EPS, "boss gain 600 ms after the defeat")
	t.check(boss_track.playing, "the boss track stopped before it was silent")
	director.advance(600.0)
	t.near(director.world_gain(), 1.0, GAIN_EPS, "world gain back after the defeat")
	t.near(director.boss_gain(), 0.0, GAIN_EPS, "boss gain after the defeat")
	t.check(not boss_track.playing, "the boss track still plays at silence")


func test_player_death_hands_the_music_back(t: TestContext) -> void:
	var director := _director(t)
	director.advance(2000.0)
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	director.advance(1200.0)
	t.near(director.boss_gain(), 1.0, GAIN_EPS, "boss gain during the fight")
	var fatty: FattyScript = fight["fatty"]
	var player := t.player()
	var router := Services.router()
	var areas: Array[Area2D] = [fatty.attack_area]
	var activation := router.begin_activation(fatty, areas)
	router.route({"activation_id": activation, "source": fatty, "attack_area": fatty.attack_area,
		"target_area": player.get_damage_area(), "weapon_id": "test", "weapon_tags": ["test"],
		"damage_types": ["physical"], "base_damage": 1000.0, "effects": [],
		"impact": {"position": fatty.get_centre(), "knock": Vector2.ZERO}})
	router.end_activation(activation)
	if not t.check(player.is_dead(), "the player survived 1000 damage"):
		return
	t.check(not director.is_boss_fight(), "the fight reset did not reach the director")
	director.advance(1200.0)
	t.near(director.world_gain(), 1.0, GAIN_EPS, "world gain 1200 ms after the death")
	t.near(director.boss_gain(), 0.0, GAIN_EPS, "boss gain 1200 ms after the death")
	var boss_track := director.boss_track()
	t.check(boss_track != null and not boss_track.playing, "the boss track still plays after the reset")


func test_travel_fades_out_then_the_next_world_fades_in(t: TestContext) -> void:
	var director := _director(t, false)
	director.advance(2000.0)
	var old_track := director.world_track()
	if not t.check(old_track != null, "level-1 has no world track"):
		return
	var arrival := _global_cue(&"AreaTransition")
	if not t.check(t.main.travel_to(TRAVEL_MAP, "west"), "travel to %s was refused" % TRAVEL_MAP):
		return
	var seen := {"gain": 1.0, "cue": false, "arrival_gain": -1.0}
	var arrived := func() -> bool:
		if t.world().map_id() == TRAVEL_MAP and t.player() != null:
			seen["cue"] = arrival != null and arrival.playing
			seen["arrival_gain"] = director.world_gain()
			return true
		seen["gain"] = director.world_gain()
		return false
	var travelled := await t.until(arrived, 3000.0, 6000.0)
	if not t.check(travelled, "the player did not reach %s" % TRAVEL_MAP):
		return
	var arrived_at := Time.get_ticks_msec()
	t.check(director.is_leaving() == false, "the leave fade outlived the arrival")
	t.between(float(seen["gain"]), 0.0, 0.15, "old world gain on the last frame before the arrival")
	t.check(bool(seen["cue"]), "AreaTransition did not play on the arrival")
	if arrival != null:
		t.equal(String(arrival.bus), "Effects", "AreaTransition bus")
	t.between(float(seen["arrival_gain"]), 0.0, 0.05, "new world gain at the arrival")
	var track := director.world_track()
	if not t.check(track != null and track != old_track, "no new world track after the travel"):
		return
	t.check(_same_stream(track.stream, GLOOP_MUSIC), "world track stream is not %s" % GLOOP_MUSIC)
	t.check(track.get_parent() == director and track.playing, "the new world track is not playing under the director")
	t.check(director.boss_track() != null, "the boss track did not survive the travel")
	await t.steps(3)
	t.check(not is_instance_valid(old_track) or old_track.is_queued_for_deletion(), "the old world track was not freed")
	var risen := await t.until(func() -> bool: return director.world_gain() >= 1.0, 3000.0, 5000.0)
	t.check(risen, "the new world music never reached full gain")
	t.between(float(Time.get_ticks_msec() - arrived_at), 1300.0, 2500.0, "real ms from the arrival to full gain")
	t.near(track.volume_linear, GLOOP_BASE, VOLUME_EPS, "gloop-forest music volume after the fade-in")


## A world that leaves the tree without the travel fade (quit to title, a teardown) still fades
## its music out over the leave time instead of letting it play on at full volume.
func test_world_leaving_without_a_travel_fades_the_music_out(t: TestContext) -> void:
	var director := _director(t)
	director.advance(2000.0)
	t.near(director.world_gain(), 1.0, GAIN_EPS, "world gain before the world leaves")
	var main := t.main
	main.get_parent().remove_child(main)
	t.check(director.is_leaving(), "the world left the tree without starting the fade-out")
	director.advance(160.0)
	t.near(director.world_gain(), 0.5, GAIN_EPS, "world gain 160 ms after the world left")
	director.advance(160.0)
	t.near(director.world_gain(), 0.0, GAIN_EPS, "world gain 320 ms after the world left")
	main.queue_free()


func test_menu_pause_ducks_and_hit_stop_does_not(t: TestContext) -> void:
	var director := _director(t)
	director.advance(2000.0)
	var track := director.world_track()
	var world := t.world()
	if not t.check(track != null, "level-1 has no world track"):
		return
	world.set_pause_reason(WorldServiceType.PAUSE_MODAL, true)
	t.check(director.is_menu_paused(), "a modal pause is not a menu pause")
	director.advance(125.0)
	t.near(director.duck(), 0.675, GAIN_EPS, "duck 125 ms into the pause")
	director.advance(125.0)
	t.near(director.duck(), 0.35, GAIN_EPS, "duck 250 ms into the pause")
	t.near(track.volume_linear, LEVEL1_BASE * 0.35, VOLUME_EPS, "world track volume under the duck")
	await t.steps(2)
	t.check(track.playing and not track.stream_paused, "the music paused with the tree")
	# A hit-stop during the menu keeps the duck.
	world.set_pause_reason(WorldServiceType.PAUSE_HIT_STOP, true)
	t.check(director.is_menu_paused(), "a hit-stop during a menu lifted the duck")
	world.set_pause_reason(WorldServiceType.PAUSE_MODAL, false)
	# A hit-stop alone is not a menu: the duck rises back.
	t.check(not director.is_menu_paused(), "a hit-stop counts as a menu pause")
	director.advance(250.0)
	t.near(director.duck(), 1.0, GAIN_EPS, "duck 250 ms after the menu closed, during a hit-stop")
	t.near(track.volume_linear, LEVEL1_BASE, VOLUME_EPS, "world track volume after the duck")
	world.set_pause_reason(WorldServiceType.PAUSE_HIT_STOP, false)
	# A menu that does not pause the tree (the title) ducks through set_menu_paused.
	t.main.tree_exiting.connect(director.set_menu_paused.bind(false))
	director.set_menu_paused(true)
	director.advance(250.0)
	t.near(director.duck(), 0.35, GAIN_EPS, "duck under set_menu_paused")
	director.set_menu_paused(false)
	director.advance(250.0)
	t.near(director.duck(), 1.0, GAIN_EPS, "duck after set_menu_paused(false)")


func test_locked_audio_freezes_the_fades(t: TestContext) -> void:
	var director := _director(t)
	t.main.tree_exiting.connect(func() -> void: director.audio_unlocked = true)
	director.advance(2000.0)
	var boss_track := director.boss_track()
	if not t.check(boss_track != null, "no boss track"):
		return
	t.check(not boss_track.playing, "the boss track plays before any fight")
	director.audio_unlocked = false
	director.fade_out(320.0)
	t.world().set_pause_reason(WorldServiceType.PAUSE_MODAL, true)
	director.advance(320.0)
	t.near(director.world_gain(), 1.0, GAIN_EPS, "world gain while locked")
	t.near(director.duck(), 0.35, GAIN_EPS, "duck while locked (it still moves)")
	t.world().set_pause_reason(WorldServiceType.PAUSE_MODAL, false)
	director.set_boss_fight(true, "probe")
	t.check(not boss_track.playing, "the boss track started while audio was locked")
	director.audio_unlocked = true
	director.advance(160.0)
	t.check(boss_track.playing, "the wanted boss track did not start on unlock")
	t.near(director.world_gain(), 0.5, GAIN_EPS, "world gain half way through the leave fade")
	t.near(director.boss_gain(), 0.0, GAIN_EPS, "boss gain while leaving")
	director.set_boss_fight(false, "probe")


func test_apply_mix_sets_the_buses(t: TestContext) -> void:
	t.main.tree_exiting.connect(func() -> void: MusicDirectorScript.apply_mix(1.0, 1.0, 1.0, false))
	MusicDirectorScript.apply_mix(0.8, 0.6, 0.7, true)
	t.near(_bus_volume(&"Master"), 0.8, VOLUME_EPS, "Master volume")
	t.near(_bus_volume(&"Effects"), 0.6, VOLUME_EPS, "Effects volume")
	t.near(_bus_volume(&"Ambience"), 0.6, VOLUME_EPS, "Ambience volume (follows effects)")
	t.near(_bus_volume(&"Music"), 0.7, VOLUME_EPS, "Music volume")
	t.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "Master not muted")
	MusicDirectorScript.set_bus_volume_linear(&"Music", 2.0)
	t.near(_bus_volume(&"Music"), 1.0, VOLUME_EPS, "Music volume clamped to 1")
	MusicDirectorScript.set_bus_volume_linear(&"Music", NAN)
	t.near(_bus_volume(&"Music"), 1.0, VOLUME_EPS, "Music volume after a NaN")
	MusicDirectorScript.apply_mix(1.0, 1.0, 1.0, false)
	t.check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "Master still muted")


# --- helpers ------------------------------------------------------------------------------------

## The registered director, else one added under main (freed with it). `manual` switches its
## processing off so the test steps it with `advance`; it comes back on when main leaves the tree.
static func _director(t: TestContext, manual: bool = true) -> MusicDirectorScript:
	var director := Services.music()
	if director == null:
		director = MusicDirectorScript.new()
		director.name = "TestMusicDirector"
		t.main.add_child(director)
	if manual:
		director.set_process(false)
		t.main.tree_exiting.connect(director.set_process.bind(true))
	return director


## Puts the player inside Fatty's activation circle and waits for the boss.
static func _start_fight(t: TestContext) -> Dictionary:
	var camp: BossCampScript = null
	for node: Node in t.tree.get_nodes_in_group(BossCampScript.GROUP):
		if node is BossCampScript and (node as BossCampScript).camp_id == CAMP_ID:
			camp = node as BossCampScript
	if not t.check(camp != null, "level-1 has no boss camp '%s'" % CAMP_ID):
		return {}
	t.teleport_player(FAR_INSIDE)
	var spawned := await t.until(func() -> bool: return camp.has_live_boss(), 200.0)
	if not t.check(spawned, "no boss spawned with the player at %s" % FAR_INSIDE):
		return {}
	var fatty := camp.get_live_boss() as FattyScript
	if not t.check(fatty != null, "the live boss is not a FattyScript"):
		return {}
	return {"camp": camp, "fatty": fatty}


## One spear hit on Fatty through the damage router (test_boss.gd `_hit`).
static func _hit(t: TestContext, fatty: FattyScript, damage: float) -> void:
	var router := Services.router()
	var player := t.player()
	var areas: Array[Area2D] = [player.get_damage_area()]
	var activation := router.begin_activation(player, areas)
	router.route({"activation_id": activation, "source": player,
		"attack_area": player.get_damage_area(), "target_area": fatty.damage_area,
		"weapon_id": "test-spear", "weapon_tags": ["spear"], "damage_types": ["physical"],
		"base_damage": damage, "effects": [],
		"impact": {"position": fatty.get_centre(), "knock": Vector2(1.0, 0.0)}})
	router.end_activation(activation)


## A cue player of GameFeel's `audio.global` (mounted on demand), or null.
static func _global_cue(cue: StringName) -> AudioStreamPlayer:
	var feel := Services.feel()
	if feel == null:
		return null
	feel.warm_up()
	return feel.get_node_or_null(NodePath("GlobalAudio/Effects/" + String(cue))) as AudioStreamPlayer


## True when `stream` is the file at `path` or a looping copy of it (sfx_player duplicates looped
## streams, which keeps the Ogg packets / MP3 data but not the resource path).
static func _same_stream(stream: AudioStream, path: String) -> bool:
	if stream == null:
		return false
	if stream.resource_path == path:
		return true
	var source := load(path) as AudioStream
	if stream is AudioStreamOggVorbis and source is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).packet_sequence == (source as AudioStreamOggVorbis).packet_sequence
	if stream is AudioStreamMP3 and source is AudioStreamMP3:
		return (stream as AudioStreamMP3).data == (source as AudioStreamMP3).data
	return false


static func _bus_volume(bus: StringName) -> float:
	return AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(bus))
