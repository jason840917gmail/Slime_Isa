extends RefCounted
## The game shell (docs/godot/specs/shell.md): settings defaults, storage and the bus mix, the
## pause menu and its tree pause (only while a world runs), the title's launch-option skip and
## menu, the area title card on world registration, end cards and the UI theme.
##
## Each test adds its own Shell (`ShellScript.new()`), with the settings file in TEST_SETTINGS_PATH
## and scene changes recorded instead of performed; a registered `Shell` autoload is taken out of
## the tree meanwhile (it then ignores worlds and flags) and put back afterwards. Tests that change
## the bus mix or GameFeel's motion settings put them back.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ShellScript := preload("res://game/shell/shell.gd")
const GameSettings := preload("res://game/shell/game_settings.gd")
const LaunchOptions := preload("res://game/shell/launch_options.gd")
const AreaTitleCard := preload("res://game/shell/area_title_card.gd")
const TitleScript := preload("res://game/shell/title.gd")
const ThemeBuilder := preload("res://tools/build_ui_theme.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const BossHealthBar := preload("res://game/ui/boss_health_bar.gd")

const TEST_SETTINGS_PATH := "user://test_shell_settings.cfg"
const TITLE_SCENE := "res://game/shell/title.tscn"
const BUSES: PackedStringArray = ["Master", "Effects", "Ambience", "Music"]
## Variations other screens are told to use (docs/godot/UI_THEME.md).
const DOCUMENTED_VARIATIONS: PackedStringArray = [
	"ModalPanel", "WindowPanel", "DialoguePanel", "NamePlate", "TabStripPanel", "BannerPanel",
	"HintPanel", "TrackerPanel", "BossPanel", "InsetPanel", "BarePanel", "DebugPanel",
	"PanelTitle", "MutedLabel", "SecondaryLabel", "TertiaryLabel", "AccentLabel", "InfoLabel",
	"WarningLabel", "DangerLabel", "SpecialLabel", "CaptionLabel", "KeyLabel", "HudLabel",
	"AreaTitle", "BossName", "DefeatTitle", "EndCardTitle", "DebugLabel",
	"PrimaryButton", "MutedButton", "DangerButton", "WarningButton", "TabButton", "SlotButton",
	"GhostButton", "BoldButton", "HudBar", "BossBar", "FloatingHealthBar",
	"HotbarSlot", "BeltSlot", "BeltSlotFilled", "DialogueNextButton", "TrackerObjectiveLabel",
]

## Stands in for game/building's furniture placement (group `furniture_placement`, `is_active()`).
class _FakePlacement extends Node:
	var active := true

	func _init() -> void:
		add_to_group(&"furniture_placement")

	func is_active() -> bool:
		return active


## The registered `Shell` autoload (if any), out of the tree while a test uses its own.
var _parked_shell: Node
var _parked_index: int = -1


# --- settings -----------------------------------------------------------------------------------

func test_settings_defaults_save_load_and_bus_mix(t: TestContext) -> void:
	var saved := _save_mix()
	_remove_settings_file()
	var settings := GameSettings.new(TEST_SETTINGS_PATH)
	t.check(not settings.read(), "a missing settings file read as stored settings")
	t.equal(settings.values(), GameSettings.DEFAULTS, "defaults")
	t.near(settings.shake_scale(), 1.0, 0.0001, "default shake scale")

	settings.update({"master": 0.5, "effects": -2.0, "music": 1.7, "muted": true, "screen_shake": 0.25,
		"reduce_motion": true, "attack_aim": "facing"})
	var values := settings.values()
	t.near(float(values["master"]), 0.5, 0.0001, "master")
	t.near(float(values["effects"]), 0.0, 0.0001, "effects clamped up to 0")
	t.near(float(values["music"]), 1.0, 0.0001, "music clamped down to 1")
	t.equal(values["muted"], true, "muted")
	t.equal(values["attack_aim"], "facing", "attack aim")
	t.near(settings.shake_scale(), 0.0, 0.0001, "reduce motion turns the shake scale off")
	t.near(_bus_linear("Master"), 0.5, 0.001, "Master bus volume")
	t.check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master bus not muted")
	t.near(_bus_linear("Effects"), 0.0, 0.001, "Effects bus volume")
	t.near(_bus_linear("Ambience"), 0.0, 0.001, "Ambience bus follows effects")
	t.near(_bus_linear("Music"), 1.0, 0.001, "Music bus volume")
	var feel := Services.feel()
	if feel != null:
		t.near(feel.screen_shake_scale, 0.25, 0.0001, "GameFeel shake scale")
		t.check(feel.reduce_motion, "GameFeel reduce motion not applied")

	var reloaded := GameSettings.new(TEST_SETTINGS_PATH)
	t.check(reloaded.read(), "the saved settings did not read back")
	t.equal(reloaded.values(), settings.values(), "settings after a reload")

	# Not numbers, out of range, another file version.
	var parsed := GameSettings.parse({"master": "loud", "music": NAN, "effects": 2, "muted": "yes"})
	t.near(float(parsed["master"]), 0.8, 0.0001, "non-number master falls back to the default")
	t.near(float(parsed["music"]), 0.7, 0.0001, "NaN music falls back to the default")
	t.near(float(parsed["effects"]), 1.0, 0.0001, "integer effects clamped")
	t.equal(parsed["muted"], false, "a non-boolean mute")
	var config := ConfigFile.new()
	config.set_value(GameSettings.META_SECTION, "version", 2)
	config.set_value(GameSettings.SECTION, "master", 0.1)
	config.save(TEST_SETTINGS_PATH)
	var other_version := GameSettings.new(TEST_SETTINGS_PATH)
	t.check(not other_version.read(), "a version-2 file read as version 1")
	t.equal(other_version.values(), GameSettings.DEFAULTS, "another version reads as defaults")

	settings.reset()
	t.equal(settings.values(), GameSettings.DEFAULTS, "Defaults restores every setting")
	t.near(_bus_linear("Master"), 0.8, 0.001, "Master bus after Defaults")
	t.check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master bus still muted")
	_restore_mix(saved)
	_remove_settings_file()


func test_settings_window_edits_the_settings(t: TestContext) -> void:
	var saved := _save_mix()
	_remove_settings_file()
	var shell := _make_shell(t)
	shell.open_settings()
	var menu := shell.settings_menu
	t.check(menu.is_open() and menu.visible, "Settings did not open")
	t.equal(shell.open_menus(), [&"settings"] as Array[StringName], "open windows")
	var music := menu.slider_for("music")
	t.near(music.value, 0.7, 0.0001, "music slider starts at the default")
	music.value = 0.4
	t.near(shell.settings.music(), 0.4, 0.0001, "the music slider did not change the setting")
	t.equal((menu.get_node(^"Panel/Margin/Rows/Sliders/Music/Caption") as Label).text, "Music  40%", "music caption")
	t.near(_bus_linear("Music"), 0.4, 0.001, "Music bus follows the slider")
	menu.motion_button.pressed.emit()
	t.check(shell.settings.reduce_motion(), "Reduce motion did not toggle")
	t.check(not menu.slider_for("screen_shake").editable, "the shake slider stayed editable under reduce motion")
	t.equal((menu.get_node(^"Panel/Margin/Rows/Sliders/Shake/Caption") as Label).text,
		"Screen shake  off (reduce motion)", "shake caption under reduce motion")
	t.equal(menu.motion_button.text, "Reduce motion: On", "motion button")
	menu.mute_button.pressed.emit()
	t.equal(menu.mute_button.text, "Unmute", "mute button")
	t.equal(menu.status_label.text, "All sound is muted", "status while muted")
	menu.controls_button.pressed.emit()
	t.check(shell.controls_menu.is_open(), "Controls did not open from Settings")
	var list := shell.controls_menu.rows
	t.check(list.get_child_count() >= 30, "the controls list has %d cells" % list.get_child_count())
	if list.get_child_count() >= 2:
		t.equal((list.get_child(0) as Label).text, "WASD", "first control key")
		t.equal((list.get_child(1) as Label).text, "Move", "first control action")
	t.check(shell.handle_escape(), "Escape over Controls was not used")
	t.check(not shell.controls_menu.is_open() and menu.is_open(), "Escape did not close only Controls")
	menu.reset_button.pressed.emit()
	t.equal(shell.settings.values(), GameSettings.DEFAULTS, "Defaults button")
	t.check(GameSettings.new(TEST_SETTINGS_PATH).read(), "Settings were not saved to the file")
	menu.close_button.pressed.emit()
	t.check(not shell.is_any_open(), "Close left a window open")
	_free_shell(shell)
	_restore_mix(saved)
	_remove_settings_file()


# --- pause --------------------------------------------------------------------------------------

func test_pause_menu_pauses_the_tree_only_in_a_world(t: TestContext) -> void:
	var saved := _save_mix()
	var shell := _make_shell(t)
	t.check(not t.tree.paused, "the tree was paused before the test")
	t.tap(&"pause")
	t.check(shell.pause_menu.is_open(), "Escape did not open the pause menu in level-1")
	t.check(t.tree.paused, "the pause menu did not pause the tree")
	t.check(t.world().has_pause_reason(&"shell:pause-menu"), "no shell:pause-menu pause reason")
	t.check(shell.pause_menu.button_for(&"resume").has_focus(), "the pause menu did not focus Resume")
	t.check(shell.pause_menu.button_for(&"journal").disabled, "Journal is enabled with no journal")
	var clock_before := Services.now_ms()
	await t.steps(5)
	t.near(Services.now_ms(), clock_before, 0.001, "the gameplay clock while paused")

	# A hit-stop ending under the menu does not resume the game.
	var feel := Services.feel()
	if feel != null and not feel.reduce_motion:
		feel.hit_stop(30.0)
		await t.tree.create_timer(0.12, true).timeout
		t.check(t.tree.paused, "a hit-stop ending resumed the paused game")

	# Settings opens on top; Escape closes it first, then the pause menu.
	shell.pause_menu.button_for(&"settings").pressed.emit()
	t.check(shell.settings_menu.is_open(), "Settings did not open from the pause menu")
	t.equal(shell.open_menus(), [&"pause-menu", &"settings"] as Array[StringName], "window stack")
	t.tap(&"pause")
	t.check(not shell.settings_menu.is_open() and shell.pause_menu.is_open(), "Escape did not close only Settings")
	t.check(t.tree.paused, "closing Settings over the pause menu resumed the game")
	t.tap(&"pause")
	t.check(not shell.pause_menu.is_open(), "Escape did not resume")
	t.check(not t.tree.paused, "the tree stayed paused after resuming")
	await t.steps(3)
	t.check(Services.now_ms() > clock_before, "the gameplay clock did not run after resuming")

	# Resume button.
	t.check(shell.open_pause(), "open_pause refused in level-1")
	shell.pause_menu.button_for(&"resume").pressed.emit()
	t.check(not shell.pause_menu.is_open() and not t.tree.paused, "Resume did not resume")

	# No world: Escape does nothing.
	t.main.remove_from_group(ShellScript.WORLD_MAIN_GROUP)
	t.tap(&"pause")
	t.check(not shell.pause_menu.is_open(), "the pause menu opened with no world running")
	t.check(not t.tree.paused, "the tree paused with no world running")
	t.main.add_to_group(ShellScript.WORLD_MAIN_GROUP)

	# Not while travelling.
	t.main.set(&"_transitioning", true)
	t.check(not shell.can_open_pause(), "pause allowed while travelling")
	t.main.set(&"_transitioning", false)

	# Not while a furniture ghost is out (WorldScene.ts:543-544).
	var placing := _FakePlacement.new()
	t.main.add_child(placing)
	t.check(not shell.can_open_pause(), "pause allowed while placing furniture")
	placing.active = false
	t.check(shell.can_open_pause(), "pause refused after placing furniture")
	placing.free()

	# Save writes the recovery autosave; Load reloads it in place (Main.load_run), unpaused.
	var run := Services.run()
	# (main.gd writes the autosave on arrival, so Load is usually enabled already.)
	t.check(shell.open_pause(), "open_pause refused before Save")
	shell.pause_menu.button_for(&"save").pressed.emit()
	t.check(run.has_save(0), "Save did not write slot 0")
	t.equal(shell.pause_menu.hint_label.text, ShellScript.SAVED_HINT, "hint after Save")
	shell.pause_menu.refresh()
	t.check(not shell.pause_menu.button_for(&"load").disabled, "Load disabled with a save")
	shell.pause_menu.button_for(&"load").pressed.emit()
	t.check(not shell.is_any_open() and not t.tree.paused, "Load left the game paused or a window open")
	var reloaded := await t.until(func() -> bool: return not t.main.is_transitioning() and t.player() != null, 3000.0, 6000.0)
	t.check(reloaded, "the game did not come back after Load")
	_free_shell(shell)
	_restore_mix(saved)


## A feature's window mounted with `mount_menu` joins the shell's stack: it opens on top of the
## pause menu with its own `shell:<surface id>` pause reason, Escape closes it first, the quit fade
## stays above it, `close_all_menus` closes everything, and a scene that is not a ShellMenu is
## refused.
func test_feature_windows_mount_on_the_shell(t: TestContext) -> void:
	var shell := _make_shell(t)
	var mounted := shell.mount_menu(load("res://game/shell/credits_menu.tscn") as PackedScene)
	t.check(mounted != null, "mount_menu refused a ShellMenu scene")
	if mounted == null:
		_free_shell(shell)
		return
	t.check(mounted.get_index() < shell.fade.get_index(), "a mounted window sits above the quit fade")
	t.check(shell.open_pause(), "open_pause refused in level-1")
	shell.open_menu(mounted)
	t.equal(shell.top_menu(), mounted, "the mounted window is not on top")
	t.check(shell.pause_menu.is_open() and not shell.pause_menu.visible, "the covered pause menu still shows through")
	if mounted.pauses_game:
		t.check(t.world().has_pause_reason(StringName("shell:" + String(mounted.surface_id))), "no pause reason for the mounted window")
	if mounted.closable_by_escape:
		t.tap(&"pause")
		t.check(not mounted.is_open() and shell.pause_menu.is_open(), "Escape did not close only the mounted window")
		t.check(shell.pause_menu.visible, "the pause menu did not show again under a closed window")
		shell.open_menu(mounted)
	shell.close_all_menus()
	t.check(not shell.is_any_open(), "close_all_menus left a window open")
	t.check(not t.tree.paused, "close_all_menus left the game paused")

	var plain := PackedScene.new()
	var plain_root := Control.new()
	plain.pack(plain_root)
	plain_root.free()
	t.check(shell.mount_menu(plain) == null, "mount_menu accepted a scene that is not a ShellMenu")
	_free_shell(shell)


# --- title ----------------------------------------------------------------------------------------

func test_title_skip_logic_for_launch_options(t: TestContext) -> void:
	for args: PackedStringArray in [
		PackedStringArray(["--map=level-1"]), PackedStringArray(["--spawn=1130,1300"]),
		PackedStringArray(["--weapon=spear"]), PackedStringArray(["--skip-title"]),
		PackedStringArray(["--quest=slime-basics"]), PackedStringArray(["--recipes"]), PackedStringArray(["--arsenal"]),
		PackedStringArray(["--strict", "--map=playground"])]:
		t.check(LaunchOptions.should_skip_title_args(args), "%s did not skip the title" % [args])
	for args: PackedStringArray in [PackedStringArray(), PackedStringArray(["--filter=test_shell"]),
		PackedStringArray(["--mapx=1"]), PackedStringArray(["map=level-1"])]:
		t.check(not LaunchOptions.should_skip_title_args(args), "%s skipped the title" % [args])
	for query: String in ["?map=level-1", "spawn=1,2&x=y", "?skip-title", "?a=1&weapon=spear", "?quest=slime-basics:2", "?recipes", "?arsenal"]:
		t.check(LaunchOptions.should_skip_title_query(query), "query '%s' did not skip the title" % query)
	for query: String in ["", "?", "?mapping=1", "?x=map"]:
		t.check(not LaunchOptions.should_skip_title_query(query), "query '%s' skipped the title" % query)
	t.check(not LaunchOptions.should_skip_title(), "the test run's own arguments skip the title")


func test_title_menu(t: TestContext) -> void:
	var saved := _save_mix()
	_park_registered_shell(t)
	# The title runs without a world of the game (main.tscn is the runner's, not the title's).
	t.main.remove_from_group(ShellScript.WORLD_MAIN_GROUP)
	# The runner keeps saves in user://test-saves; start without an autosave.
	var run := Services.run()
	run.delete_slot(0)
	var title := (load(TITLE_SCENE) as PackedScene).instantiate() as TitleScript
	title.backdrop_enabled = false
	title.skip_for_launch_options = false
	var changes: Array[String] = []
	title.change_scene = func(path: String) -> void: changes.append(path)
	t.tree.root.add_child(title)
	await t.steps(1)
	t.check(title.new_game_button.visible, "New Game hidden")
	t.check(title.new_game_button.has_focus(), "New Game not focused")
	t.check(not title.continue_button.visible, "Continue shown without a save")
	t.check(not title.load_button.visible, "Load shown without a save window")
	t.equal(title.version_label.text, "v" + TitleScript.version(), "version")
	var shell: Node = title.get_shell()
	t.check(shell != null and shell.get_parent() == title, "the title did not make its own Shell")
	if shell != null:
		title.settings_button.pressed.emit()
		t.check(shell.settings_menu.is_open(), "Settings did not open from the title")
		shell.settings_menu.close()
		title.credits_button.pressed.emit()
		t.check(shell.credits_menu.is_open(), "Credits did not open from the title")
		t.check(shell.credits_menu.text_label.text.begins_with("SLIME ISA\nCreated by"), "credits text")
		t.check(shell.handle_escape() and not shell.credits_menu.is_open(), "Escape did not close Credits")
		t.check(not shell.handle_escape(), "Escape did something on the bare title")
		t.check(not t.tree.paused, "the tree stayed paused on the title")
	title.new_game_button.pressed.emit()
	t.equal(changes, ["res://game/main.tscn"] as Array[String], "New Game scene change")
	t.check(run.started, "New Game did not start a run")
	title.queue_free()
	await t.steps(1)

	# With an autosave: Continue shows and loads it; New Game asks first.
	t.check(run.save_slot(0), "could not write the test autosave")
	var with_save := (load(TITLE_SCENE) as PackedScene).instantiate() as TitleScript
	with_save.backdrop_enabled = false
	with_save.skip_for_launch_options = false
	var later: Array[String] = []
	with_save.change_scene = func(path: String) -> void: later.append(path)
	t.tree.root.add_child(with_save)
	await t.steps(1)
	t.check(with_save.continue_button.visible, "Continue hidden with an autosave")
	with_save.new_game_button.pressed.emit()
	t.check(with_save.confirm_row.visible and not with_save.new_game_button.visible,
		"New Game over an autosave did not ask first")
	t.equal(with_save.status_label.text, TitleScript.CONFIRM_TEXT, "confirmation text")
	t.check(later.is_empty(), "New Game over an autosave started at once")
	with_save.cancel_button.pressed.emit()
	t.check(with_save.new_game_button.visible and not with_save.confirm_row.visible, "Cancel did not return to the menu")
	with_save.continue_button.pressed.emit()
	t.equal(later, ["res://game/main.tscn"] as Array[String], "Continue scene change")
	run.consume_navigation()
	run.delete_slot(0)
	with_save.queue_free()
	await t.steps(1)
	t.main.add_to_group(ShellScript.WORLD_MAIN_GROUP)
	_unpark_registered_shell(t)
	_restore_mix(saved)


# --- area title card ------------------------------------------------------------------------------

func test_area_title_card_on_world_registration(t: TestContext) -> void:
	var saved := _save_mix()
	var shell := _make_shell(t)
	var card := shell.area_title
	var clock := {"ms": 10000.0}
	card.clock = func() -> float: return float(clock["ms"])
	t.check(not card.is_showing(), "the card showed before any world registered")
	t.world().world_registered.emit({"mapId": "level-1"})
	t.check(card.is_showing(), "no card after level-1 registered")
	t.equal(card.label.text, "Slimeshire Meadow", "level-1 title")
	t.equal(card.current_color().to_html(false), "a3f0c0", "meadow title colour")
	card._process(0.0)
	t.near(card.modulate.a, 0.0, 0.001, "opacity at the start")
	t.near(card.offset_top, 54.0, 0.001, "top at the start")
	clock["ms"] = 10000.0 + 160.0
	card._process(0.0)
	t.near(card.modulate.a, 0.875, 0.001, "opacity half way in (cubic ease-out)")
	t.near(card.offset_top, 70.0, 0.001, "top half way in")
	clock["ms"] = 10000.0 + 320.0
	card._process(0.0)
	t.near(card.modulate.a, 1.0, 0.001, "opacity after the 320 ms entry")
	t.near(card.offset_top, 72.0, 0.001, "top after the entry")
	t.near(card.size.y, 64.0, 0.001, "card height")
	clock["ms"] = 10000.0 + 1519.0
	card._process(0.0)
	t.check(card.visible and card.modulate.a > 0.999, "the card faded during the 1200 ms hold")
	clock["ms"] = 10000.0 + 1680.0
	card._process(0.0)
	t.near(card.modulate.a, 0.875, 0.001, "opacity half way out")
	clock["ms"] = 10000.0 + 1840.0
	card._process(0.0)
	t.check(not card.visible, "the card stayed after 1840 ms")

	# Another world, an unknown id, and no card for a world outside main (the title backdrop).
	t.world().world_registered.emit({"mapId": "gloop-forest"})
	t.equal(card.label.text, "Gloop Forest", "gloop-forest title")
	t.equal(card.current_color().to_html(false), "8cff9a", "gloop forest colour")
	t.world().world_registered.emit({"mapId": "elder-house"})
	t.equal(card.label.text, "Elder House", "an unknown map's title from its id")
	clock["ms"] = 20000.0
	t.main.remove_from_group(ShellScript.WORLD_MAIN_GROUP)
	t.world().world_registered.emit({"mapId": "level-1"})
	t.check(not card.is_showing(), "a card showed for a world outside main")
	t.main.add_to_group(ShellScript.WORLD_MAIN_GROUP)
	_free_shell(shell)
	_restore_mix(saved)


# --- end card -------------------------------------------------------------------------------------

func test_end_card_opens_once_for_a_new_story_flag(t: TestContext) -> void:
	var saved := _save_mix()
	var run := Services.run()
	# A flag the run already had when the world loaded never shows its card.
	run.set_flag("chapter-2-complete")
	var shell := _make_shell(t)
	t.world().world_registered.emit({"mapId": "level-1"})
	run.story_flag_changed.emit({"flag": "chapter-2-complete", "set": true})
	t.check(not shell.end_card.is_open(), "an end card opened for a flag the run already had")
	run.set_flag("playground-end-card-test")
	t.check(shell.end_card.is_open(), "no end card for playground-end-card-test")
	t.equal(shell.end_card.title_label.text, "The End (test)", "end card title")
	t.check(t.tree.paused, "the end card did not pause the game")
	t.check(shell.handle_escape() and shell.end_card.is_open(), "Escape closed the end card")
	shell.end_card.return_button.pressed.emit()
	t.check(not shell.end_card.is_open(), "Return to title left the card open")
	t.check(t.world().has_pause_reason(ShellScript.PAUSE_REASON_QUIT), "the quit fade does not hold the game")
	t.check(shell.fade.visible, "no fade towards the title")
	_free_shell(shell)
	# Quit to Title wrote the autosave (into the runner's user://test-saves); leave none behind.
	run.delete_slot(0)
	t.check(not t.tree.paused, "the tree stayed paused after the shell left")
	_restore_mix(saved)


# --- HUD --------------------------------------------------------------------------------------------

func test_hud_uses_the_theme_and_the_boss_card_stays_low(t: TestContext) -> void:
	var hud: Node = t.main.get_node_or_null(^"Hud")
	if not t.check(hud != null, "main.tscn has no Hud"):
		return
	var coins := hud.find_child("Coins", true, false) as Label
	t.check(coins != null and coins.theme_type_variation == &"HudLabel", "the coins label does not use HudLabel")
	var health := hud.find_child("Health", true, false) as Control
	t.check(health != null and health.theme_type_variation == &"HudBar", "the HP bar does not use HudBar")
	var boss_bar: Control = hud.call(&"get_boss_bar")
	t.check(boss_bar.theme_type_variation == &"BossPanel", "the boss card does not use BossPanel")
	# Phaser's place at the 1280 x 720 reference: bottom edge 192 px above the screen bottom.
	t.equal(BossHealthBar.card_rect(Vector2(1280.0, 720.0)), Rect2(366.0, 470.0, 548.0, 58.0), "boss card at 1280 x 720")
	# A short view keeps it below the player (view centre + 96).
	t.equal(BossHealthBar.card_rect(Vector2(960.0, 540.0)), Rect2(206.0, 366.0, 548.0, 58.0), "boss card at 960 x 540")
	t.equal(BossHealthBar.card_rect(Vector2(400.0, 700.0)).size.x, 376.0, "boss card width on a narrow view")


# --- theme ----------------------------------------------------------------------------------------

func test_ui_theme_has_every_documented_variation(t: TestContext) -> void:
	var theme := UiTokens.theme()
	if not t.check(theme != null, "%s is missing" % UiTokens.THEME_PATH):
		return
	for variation: String in DOCUMENTED_VARIATIONS:
		t.check(theme.is_type_variation(variation, theme.get_type_variation_base(variation)) \
			and theme.get_type_variation_base(variation) != &"", "no type variation %s" % variation)
	var built := ThemeBuilder.build()
	var stale := PackedStringArray()
	for type_name: StringName in built.get_type_list():
		if built.get_type_variation_base(type_name) != theme.get_type_variation_base(type_name) \
				or built.get_stylebox_list(type_name).size() != theme.get_stylebox_list(type_name).size() \
				or built.get_color_list(type_name).size() != theme.get_color_list(type_name).size():
			stale.append(type_name)
	t.check(stale.is_empty(), "slime_theme.tres is older than tools/build_ui_theme.gd (%s); rebuild it" % ", ".join(stale))
	t.near(theme.get_color(&"warning", &"Palette").r, UiTokens.WARNING.r, 0.001, "palette warning")
	# The drawn icons are stored in the .tres (an empty one means the compressed bytes were lost).
	for pair: Array in [[&"grabber", &"HSlider"], [&"checked", &"CheckBox"], [&"arrow", &"OptionButton"]]:
		var icon := theme.get_icon(pair[0], pair[1])
		var image := icon.get_image() if icon != null else null
		t.check(image != null and not image.is_empty() and image.get_used_rect().size.x > 0,
			"theme icon %s/%s is empty" % [pair[1], pair[0]])


# --- helpers --------------------------------------------------------------------------------------

func _make_shell(t: TestContext) -> ShellScript:
	_park_registered_shell(t)
	_remove_settings_file()
	var shell := ShellScript.new()
	shell.settings_path = TEST_SETTINGS_PATH
	shell.change_scene = func(_path: String) -> void: pass
	t.tree.root.add_child(shell)
	return shell


func _free_shell(shell: ShellScript) -> void:
	if is_instance_valid(shell):
		var tree := shell.get_tree()
		shell.get_parent().remove_child(shell)
		shell.free()
		if tree != null:
			_unpark_registered_shell_in(tree)


func _park_registered_shell(t: TestContext) -> void:
	var registered := t.tree.root.get_node_or_null(^"Shell")
	if registered == null or _parked_shell != null:
		return
	_parked_shell = registered
	_parked_index = registered.get_index()
	t.tree.root.remove_child(registered)


func _unpark_registered_shell(t: TestContext) -> void:
	_unpark_registered_shell_in(t.tree)


func _unpark_registered_shell_in(tree: SceneTree) -> void:
	if _parked_shell == null:
		return
	tree.root.add_child(_parked_shell)
	tree.root.move_child(_parked_shell, mini(_parked_index, tree.root.get_child_count() - 1))
	_parked_shell = null


func _bus_linear(bus: String) -> float:
	return AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(bus))


## The bus volumes and mutes, and GameFeel's motion settings, to put back after a test.
func _save_mix() -> Dictionary:
	var saved := {}
	for bus: String in BUSES:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			saved[bus] = [AudioServer.get_bus_volume_db(index), AudioServer.is_bus_mute(index)]
	var feel := Services.feel()
	if feel != null:
		saved["feel"] = [feel.screen_shake_scale, feel.reduce_motion]
	return saved


func _restore_mix(saved: Dictionary) -> void:
	for bus: String in BUSES:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0 and saved.has(bus):
			AudioServer.set_bus_volume_db(index, float(saved[bus][0]))
			AudioServer.set_bus_mute(index, bool(saved[bus][1]))
	var feel := Services.feel()
	if feel != null and saved.has("feel"):
		feel.screen_shake_scale = float(saved["feel"][0])
		feel.reduce_motion = bool(saved["feel"][1])


func _remove_settings_file() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_SETTINGS_PATH)
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(absolute)
