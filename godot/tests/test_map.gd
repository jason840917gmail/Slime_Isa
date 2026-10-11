extends RefCounted
## The minimap and the world map (docs/godot/specs/map.md): the minimap's box and level-1's baked
## ground, the player dot and the camera view, the shared marker API, the world map opened by the
## `map` action and the pause menu's Map button (GameWindows' `modal` pause, the region labels of
## res://game/data/world-map.json, Escape, `map`, `menu` and Close), refused over other windows,
## its regions (names without planning notes, shared with the area banner), the links of two-way
## passages and the missing-layout message, and both rebuilt after a travel to gloop-forest.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const MapUi := preload("res://game/ui/map/map_ui.gd")
const Minimap := preload("res://game/ui/map/minimap.gd")
const MapTerrain := preload("res://game/ui/map/map_terrain.gd")
const MapMarkers := preload("res://game/ui/map/map_markers.gd")
const WorldMapWindow := preload("res://game/ui/map/world_map_window.gd")
const AreaTitles := preload("res://game/shell/area_titles.gd")

const SUMMARY_FORMAT := "%d of %d regions discovered · Areas stay marked as you travel"
const SUMMARY_NO_LAYOUT := "%d discovered · Areas stay marked as you travel"


# --- minimap ------------------------------------------------------------------------------------

func test_minimap_box_and_level_1_terrain(t: TestContext) -> void:
	var map_ui := _map_ui(t)
	if map_ui == null:
		return
	var minimap := map_ui.minimap
	# Phaser's box (MinimapSurfacePort.ts:26-31) at the reference sizes.
	t.equal(Minimap.box_for(Vector2(1280.0, 720.0)), Rect2(16.0, 531.0, 173.0, 173.0), "box at 1280 x 720")
	t.equal(Minimap.box_for(Vector2(800.0, 600.0)), Rect2(15.0, 441.0, 144.0, 144.0), "box at 800 x 600")
	t.equal(Minimap.box_for(Vector2(390.0, 720.0)), Rect2(12.0, 580.0, 128.0, 128.0), "box at 390 x 720 (minimum)")
	t.equal(Minimap.box_for(Vector2(1920.0, 1080.0)), Rect2(16.0, 884.0, 180.0, 180.0), "box at 1920 x 1080 (maximum)")
	# In the game the minimap is docked in the HUD console (roadmap 4.12): its rect, the frame inside.
	var console: Node = t.main.get_node(^"Hud").call(&"get_console")
	var dock: Rect2 = (console.call(&"rects") as Dictionary)["minimap"]
	t.equal(minimap.dock, dock, "the minimap is docked on the console's minimap rect")
	t.equal(Rect2(minimap.position, minimap.size), dock.grow(-Minimap.FRAME_OUTSET), "minimap box in the console")
	t.check(minimap.visible, "the minimap is hidden in level-1")
	t.check(minimap.get_parent() == map_ui and map_ui.get_parent() == t.main.get_node(^"Hud"), "the minimap is not under the HUD")
	var frame := minimap.get_node_or_null(^"Frame") as TextureRect
	t.check(frame != null and frame.texture != null, "the minimap has no frame texture")

	# The drawn map by default (owner decision): one pixel per tile, each the tile's average colour.
	t.near(minimap.terrain_alpha, 1.0, 0.0001, "the minimap does not draw the map by default")
	var image := minimap.terrain_image()
	if not t.check(image != null, "no terrain baked for level-1"):
		return
	t.equal(image.get_size(), Vector2i(64, 64), "level-1 terrain size (tiles)")
	t.check(minimap.terrain_texture() != null and Vector2i(minimap.terrain_texture().get_size()) == Vector2i(minimap.map_rect().size.round()),
		"the drawn terrain is not scaled to the map area")
	var ground := t.world().ground_layer
	var samples := {"water": null, "deep-water": null, "grass-a": null, "town-cobble": null}
	for cell: Vector2i in ground.get_used_cells():
		var tile_id := str(ground.get_cell_tile_data(cell).get_custom_data(&"tile_id"))
		if samples.has(tile_id) and samples[tile_id] == null:
			samples[tile_id] = cell
	for tile_id: String in samples:
		var cell: Variant = samples[tile_id]
		if not t.check(cell != null, "level-1 has no %s tile" % tile_id):
			continue
		var source := ground.tile_set.get_source(ground.get_cell_source_id(cell)) as TileSetAtlasSource
		var expected := MapTerrain.tile_color(source, ground.get_cell_atlas_coords(cell))
		var got := image.get_pixelv(cell)
		t.check(got.is_equal_approx(expected), "%s cell %s: %s, the tile's average is %s" % [tile_id, cell, got, expected])
		t.near(got.a, 1.0, 0.01, "%s cell alpha" % tile_id)
	if samples["water"] != null:
		var water := image.get_pixelv(samples["water"])
		t.check(water.b > water.r and water.b > 0.35, "water is not blue on the minimap (%s)" % water)
	if samples["grass-a"] != null:
		var grass := image.get_pixelv(samples["grass-a"])
		t.check(grass.g > grass.r and grass.g > grass.b, "meadow grass is not green on the minimap (%s)" % grass)
	# Empty cells stay transparent; cells outside the size are skipped.
	if samples["grass-a"] == null:
		return
	var grass_cell: Vector2i = samples["grass-a"]
	var layer := TileMapLayer.new()
	layer.tile_set = ground.tile_set
	layer.set_cell(Vector2i(1, 0), ground.get_cell_source_id(grass_cell), ground.get_cell_atlas_coords(grass_cell))
	layer.set_cell(Vector2i(5, 5), ground.get_cell_source_id(grass_cell), ground.get_cell_atlas_coords(grass_cell))
	var small := MapTerrain.bake(layer, 3, 2)
	t.equal(small.get_size(), Vector2i(3, 2), "small bake size")
	t.near(small.get_pixel(0, 0).a, 0.0, 0.001, "an empty cell is transparent")
	t.near(small.get_pixel(1, 0).a, 1.0, 0.001, "a used cell is opaque")
	layer.free()


func test_player_dot_and_view_follow(t: TestContext) -> void:
	var map_ui := _map_ui(t)
	if map_ui == null:
		return
	var minimap := map_ui.minimap
	var area := minimap.map_rect()
	t.near_vec(minimap.to_map(Vector2.ZERO), area.position, 0.001, "world origin on the minimap")
	t.near_vec(minimap.to_map(Vector2(4096.0, 4096.0)), area.end, 0.001, "world corner on the minimap")
	t.near_vec(minimap.to_map(Vector2(2048.0, 1024.0)), area.position + area.size * Vector2(0.5, 0.25), 0.001, "a world point on the minimap")
	await t.tree.process_frame
	t.near_vec(minimap.drawn_player(), t.player().get_centre(), 0.01, "player dot at spawn")
	for target: Vector2 in [Vector2(1200.0, 1900.0), Vector2(2400.0, 900.0)]:
		t.teleport_player(target)
		await t.steps(3)
		await t.tree.process_frame
		# The dot is read in `_process`; a player still sliding moves a little after it.
		t.near_vec(minimap.drawn_player(), t.player().get_centre(), 1.0, "player dot after a teleport to %s" % target)
		t.near_vec(minimap.drawn_player(), target, 40.0, "player dot near the teleport target")
	# The view: this frame's camera centre ± play area / (2 · zoom), the play area being the viewport
	# above the HUD console (read after the camera moved).
	await t.tree.process_frame
	var camera := t.world().camera
	var view := (camera.get_viewport_rect().size - Vector2(0.0, camera.bottom_inset)) / camera.target_zoom
	var drawn := minimap.drawn_view()
	t.near_vec(drawn.size, view, 0.01, "view size")
	t.near_vec(drawn.get_center(), camera.center, 0.01, "view centre")


func test_marker_api_reaches_both_views(t: TestContext) -> void:
	var map_ui := _map_ui(t)
	if map_ui == null:
		return
	var store := map_ui.markers
	t.check(map_ui.minimap.markers == store and map_ui.world_map.markers == store, "the views do not share one marker store")
	var changes := [0]
	t.listen(store.changed, func() -> void: changes[0] += 1)
	map_ui.set_marker(&"quest", Vector2(1130.0, 1514.0))
	t.equal(store.marker(&"quest"), {"point": Vector2(1130.0, 1514.0), "kind": MapMarkers.KIND_WAYPOINT, "map_id": "level-1"}, "a waypoint in the current world")
	map_ui.set_marker(&"quest", Vector2(1130.0, 1514.0))
	t.equal(changes[0], 1, "setting the same marker again changed nothing")
	map_ui.minimap.set_marker(&"quest", Vector2(640.0, 392.0), &"waypoint")
	t.equal(store.marker(&"quest")["point"], Vector2(640.0, 392.0), "moved through the minimap")
	map_ui.world_map.set_marker(&"camp", Vector2(2528.0, 1472.0), MapMarkers.KIND_BOSS)
	map_ui.set_marker(&"elsewhere", Vector2(100.0, 100.0), &"npc", "gloop-forest")
	t.equal(store.marker_ids(), [&"quest", &"camp", &"elsewhere"] as Array[StringName], "marker ids in insertion order")
	var here := store.markers_in("level-1")
	t.equal(here.size(), 2, "markers drawn in level-1")
	t.equal(store.markers_in("gloop-forest").size(), 1, "markers of another world")
	map_ui.set_marker(&"", Vector2.ZERO)
	map_ui.set_marker(&"bad", Vector2(INF, 0.0))
	t.check(not store.has_marker(&"") and not store.has_marker(&"bad"), "an empty id or a non-finite point made a marker")
	map_ui.clear_marker(&"quest")
	t.check(not store.has_marker(&"quest"), "clear_marker left the marker")
	map_ui.world_map.clear_markers()
	t.equal(store.marker_ids().size(), 0, "clear_markers left markers")
	t.equal(MapMarkers.dot_style(&"unknown-kind"), MapMarkers.dot_style(MapMarkers.KIND_POINT), "an unknown kind draws as a point")


# --- world map ----------------------------------------------------------------------------------

func test_world_map_opens_from_the_map_action_and_closes(t: TestContext) -> void:
	var map_ui := _map_ui(t)
	if map_ui == null:
		return
	var windows := _game_windows(t)
	if windows == null:
		return
	var world_map := map_ui.world_map
	var opened: Array[StringName] = []
	t.listen(windows.window_opened, func(surface_id: StringName) -> void: opened.append(surface_id))
	t.check(world_map.get_parent() == windows.get(&"root"), "the world map is not a GameWindows window")
	t.check(InputMap.has_action(&"map"), "the InputMap has no `map` action")

	t.tap(&"map")
	if not t.check(world_map.is_open(), "the map action did not open the world map"):
		return
	t.check(world_map.visible and world_map.is_in_group(WorldMapWindow.GROUP), "the open world map is hidden or not in its group")
	t.equal(opened, [&"world-map"] as Array[StringName], "window_opened surface ids")
	t.check(windows.call(&"is_open", &"world-map"), "GameWindows does not list world-map")
	t.check(t.tree.paused and t.world().has_pause_reason(Services.WorldServiceType.PAUSE_MODAL), "the world map did not pause with the modal reason")
	t.check(world_map.close_button.has_focus(), "Close is not focused")
	t.check(WorldMapWindow.map_data() != null, "no world layout (res://game/data/world-map.json)")
	t.equal(world_map.region_text("level-1"), "Slimeshire Meadow\nCurrent area", "level-1's region label")
	t.equal(world_map.region_text("gloop-forest"), "?", "gloop-forest's region label")
	t.equal(world_map.region_text("crystal-caverns"), "?", "crystal-caverns' region label")
	t.equal(world_map.current_region().get("world"), "level-1", "the current region's world")
	t.check(world_map.region_rect("level-1").grow(1.0).has_point(world_map.player_dot()), "the player dot is not on level-1's block")
	t.check(not world_map.message_label.visible, "the missing-layout message shows")
	t.equal(world_map.summary_label.text, _summary(1), "summary")
	t.equal(world_map.title_label.text, "World Map", "title")
	t.check(not WorldMapWindow.link_shown("level-1", "gloop-forest", WorldMapWindow.discovered_areas()), "a link shows with one region discovered")
	var viewport := world_map.get_viewport_rect().size
	t.near_vec(world_map.panel.size, WorldMapWindow.panel_size_for(viewport), 1.0, "panel size at %s" % viewport)
	t.equal(WorldMapWindow.panel_size_for(Vector2(1024.0, 1024.0)), Vector2(720.0, 816.0), "panel size at 1024 x 1024")
	t.equal(WorldMapWindow.panel_size_for(Vector2(480.0, 900.0)), Vector2(448.0, 544.0), "panel size at 480 x 900 (fits its grid)")
	# The menu's tab strip (game/ui/screens/menu_windows.gd, when present) has the map as its Map tab.
	var menu := t.tree.get_first_node_in_group(&"menu_windows")
	if menu != null and menu.has_method(&"current_tab"):
		t.equal(menu.call(&"current_tab"), &"map", "the menu's open tab with the world map open")
	var clock := Services.now_ms()
	await t.steps(4)
	t.near(Services.now_ms(), clock, 0.001, "the gameplay clock while the world map is open")

	# `map` again closes it (the window's `_input`, before GameWindows' key trap).
	t.tap(&"map")
	t.check(not world_map.is_open() and not t.tree.paused, "the map action did not close the world map and resume")
	# Escape closes it through GameWindows, and the pause menu does not open.
	t.check(map_ui.open_world_map(), "open_world_map refused in level-1")
	t.tap(&"pause")
	t.check(not world_map.is_open(), "Escape did not close the world map")
	var shell := Services.shell()
	t.check(shell == null or not shell.is_any_open(), "Escape over the world map opened a shell window")
	t.check(not t.tree.paused, "the tree stayed paused after Escape")
	# Close button.
	t.check(map_ui.toggle_world_map(), "toggle_world_map did not open it")
	world_map.close_button.pressed.emit()
	t.check(not world_map.is_open() and not t.tree.paused, "Close did not close the world map")
	# The menu key closes it like an open menu tab.
	world_map.open()
	t.tap(&"menu")
	t.check(not world_map.is_open(), "the menu key did not close the world map")
	t.check(not windows.call(&"is_any_open"), "the menu key left a game window open over the world map")
	await t.steps(2)
	t.check(not t.tree.paused, "the tree is paused after closing the world map")


func test_world_map_from_the_pause_menu(t: TestContext) -> void:
	var map_ui := _map_ui(t)
	var shell := Services.shell()
	if map_ui == null or not t.check(shell != null, "no Shell autoload"):
		return
	t.check(shell.has_action(&"map"), "the map is not registered as the pause menu's Map action")
	t.check(shell.open_pause(), "the pause menu did not open")
	var map_button := shell.pause_menu.button_for(&"map")
	t.check(map_button != null and not map_button.disabled, "the pause menu's Map button is disabled")
	map_button.pressed.emit()
	t.check(not shell.pause_menu.is_open(), "the pause menu stayed open")
	t.check(map_ui.is_world_map_open(), "Map did not open the world map")
	t.check(t.tree.paused and t.world().has_pause_reason(Services.WorldServiceType.PAUSE_MODAL), "not paused by the world map")
	t.check(not t.world().has_pause_reason(&"shell:pause-menu"), "the pause menu's reason is still held")
	map_ui.close_world_map()
	t.check(not t.tree.paused, "the tree stayed paused")


func test_map_key_refused_over_other_windows(t: TestContext) -> void:
	var map_ui := _map_ui(t)
	var windows := _game_windows(t)
	if map_ui == null or windows == null:
		return
	var shell := Services.shell()
	if shell != null:
		shell.open_pause()
		t.tap(&"map")
		t.check(not map_ui.is_world_map_open(), "the map key opened the world map over the pause menu")
		t.check(shell.pause_menu.is_open(), "the map key closed the pause menu")
		shell.pause_menu.close()
	# Another game window (the bag, a dialogue): GameWindows swallows the key.
	var other := Control.new()
	windows.call(&"add_window", other)
	windows.call(&"push", other, &"inventory", true)
	t.tap(&"map")
	t.check(not map_ui.is_world_map_open(), "the map key opened the world map over another game window")
	t.check(not map_ui.can_open_from_key(), "can_open_from_key with another window open")
	windows.call(&"pop", other, true)
	other.queue_free()
	# Travelling.
	t.main.set(&"_transitioning", true)
	t.check(not map_ui.can_open_from_key(), "the map key may open the world map while travelling")
	t.main.set(&"_transitioning", false)
	t.check(map_ui.can_open_from_key(), "the map key may not open the world map in level-1")
	# Placing furniture (a node of group furniture_placement with is_active()).
	var placing := Node.new()
	placing.set_script(_placement_script())
	placing.add_to_group(&"furniture_placement")
	t.main.add_child(placing)
	t.check(not map_ui.can_open_from_key(), "the map key may open the world map while placing furniture")
	placing.free()
	t.check(map_ui.can_open_from_key(), "the map key stays refused after placing furniture")
	t.check(not t.tree.paused, "the tree is paused")


func test_travel_rebuilds_the_minimap_and_world_map(t: TestContext) -> void:
	var map_ui := _map_ui(t)
	if map_ui == null:
		return
	var minimap := map_ui.minimap
	var old_texture: WeakRef = weakref(minimap.terrain_texture())
	var old_image: WeakRef = weakref(minimap.terrain_image())
	map_ui.set_marker(&"meadow-quest", Vector2(1130.0, 1514.0))
	t.check(t.main.travel_to("gloop-forest", "west"), "travel_to gloop-forest refused")
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == "gloop-forest" and t.player() != null, 4000.0, 10000.0)
	if not t.check(arrived, "did not arrive in gloop-forest"):
		return
	await t.tree.process_frame
	await t.tree.process_frame
	t.check(old_texture.get_ref() == null and old_image.get_ref() == null, "level-1's minimap terrain outlived level-1")
	var image := minimap.terrain_image()
	t.check(image != null and image.get_size() == Vector2i(54, 54), "gloop-forest terrain not baked (%s)" % [image.get_size() if image != null else null])
	t.check(minimap.visible, "the minimap is hidden in gloop-forest")
	t.near_vec(minimap.drawn_player(), t.player().get_centre(), 0.01, "player dot in gloop-forest")
	t.equal(map_ui.markers.markers_in("gloop-forest").size(), 0, "level-1's marker is drawn in gloop-forest")
	t.equal(map_ui.markers.marker(&"meadow-quest")["map_id"], "level-1", "the level-1 marker kept its world")

	t.check(map_ui.open_world_map(), "the world map did not open in gloop-forest")
	var world_map := map_ui.world_map
	t.equal(world_map.region_text("level-1"), "Slimeshire Meadow", "level-1's region label after travel")
	t.equal(world_map.region_text("gloop-forest"), "Gloop Forest\nCurrent area", "gloop-forest's region label after travel")
	t.equal(world_map.region_text("crystal-caverns"), "?", "crystal-caverns' region label after travel")
	t.equal(world_map.summary_label.text, _summary(2), "summary after travel")
	t.check(world_map.region_rect("gloop-forest").grow(1.0).has_point(world_map.player_dot()), "the player dot is not on gloop-forest's block")
	var discovered := WorldMapWindow.discovered_areas()
	t.equal(WorldMapWindow.link_shown("level-1", "gloop-forest", discovered), WorldMapWindow.has_passage("level-1", "gloop-forest"),
		"the level-1 / gloop-forest link shows exactly when the layout has a passage there")
	t.check(not WorldMapWindow.link_shown("gloop-forest", "crystal-caverns", discovered), "a link to the undiscovered crystal caverns")
	map_ui.close_world_map()


func test_world_map_regions_and_passages(t: TestContext) -> void:
	var map := WorldMapWindow.map_data()
	if not t.check(map != null, "no world layout (res://game/data/world-map.json)"):
		return
	var meadow := WorldMapWindow.region_of("level-1")
	var forest := WorldMapWindow.region_of("gloop-forest")
	t.equal(meadow.get("name"), "Slimeshire Meadow", "level-1's region")
	t.equal(WorldMapWindow.region_of("gloop-hut"), forest, "an interior's region")
	t.equal(WorldMapWindow.region_of(str(forest.get("key", ""))), forest, "a region by its key")
	t.equal(WorldMapWindow.region_of("playground"), {}, "a world off the layout has a region")
	# A region is discovered by any of its maps, and current in any of them (its interiors too).
	t.equal(WorldMapWindow.region_label(forest, PackedStringArray(["gloop-hut"]), "gloop-hut"), "Gloop Forest\nCurrent area", "label in an interior")
	t.equal(WorldMapWindow.region_label(forest, PackedStringArray(["level-1"]), "level-1"), "?", "label of an undiscovered region")
	# Names: the layout's without a trailing planning note ("Desert (open)"), on the map and the banner.
	var open_slot := {"key": "i", "name": "Desert (open)", "world": "desert"}
	t.equal(WorldMapWindow.region_label(open_slot, PackedStringArray(["desert"]), ""), "Desert", "a planning note in a region label")
	t.equal(AreaTitles.region_name({"name": "West village (open)"}), "West village", "a planning note in a region name")
	t.equal(AreaTitles.region_name({"name": "(open)"}), "(open)", "a name that is only a note")
	t.equal(AreaTitles.region_name({}), "", "a region without a name")
	for region: Dictionary in map.regions():
		var world := str(region.get("world", ""))
		var label := WorldMapWindow.region_label(region, WorldMapWindow.region_maps(region), "")
		t.check(not label.ends_with(")") and not AreaTitles.area_name(world).ends_with(")"),
			"%s shows a planning note (map %s, banner %s)" % [world, label, AreaTitles.area_name(world)])
	# Links: only for a passage of the layout that can be travelled both ways (both regions hand-made,
	# or both placeholders), once both of its regions are discovered.
	var copy := map.duplicate_map()
	var passages: Array = [{"a": meadow.get("key"), "b": forest.get("key"), "x": 0, "y": 0, "w": 1, "h": 1}]
	var placeholders := map.regions().filter(func(region: Dictionary) -> bool: return bool(region.get("placeholder", false)))
	if placeholders.size() >= 2:
		passages.append({"a": meadow.get("key"), "b": placeholders[0].get("key"), "x": 0, "y": 0, "w": 1, "h": 1})
		passages.append({"a": placeholders[0].get("key"), "b": placeholders[1].get("key"), "x": 0, "y": 0, "w": 1, "h": 1})
	copy.head["passages"] = passages
	WorldMapWindow.use_map(copy)
	t.check(WorldMapWindow.has_passage("gloop-forest", "level-1"), "the passage was not found from either end")
	t.check(not WorldMapWindow.has_passage("level-1", "crystal-caverns"), "a passage that the layout does not have")
	t.check(not WorldMapWindow.link_shown("level-1", "gloop-forest", PackedStringArray(["level-1"])), "a link to an undiscovered region")
	t.check(WorldMapWindow.link_shown("level-1", "gloop-forest", PackedStringArray(["level-1", "gloop-hut"])), "no link once both regions are discovered")
	if placeholders.size() >= 2:
		var first := str(placeholders[0].get("world", ""))
		var second := str(placeholders[1].get("world", ""))
		t.check(WorldMapWindow.has_passage("level-1", first) and not WorldMapWindow.is_two_way(meadow, placeholders[0]),
			"level-1 / %s is not a one-way passage" % first)
		t.check(not WorldMapWindow.link_shown("level-1", first, PackedStringArray(["level-1", first])),
			"a link between hand-made level-1 and the placeholder %s (no exit back)" % first)
		t.check(WorldMapWindow.link_shown(first, second, PackedStringArray([first, second])),
			"no link between the placeholders %s and %s once both are discovered" % [first, second])
	WorldMapWindow.reload_map()


func test_world_map_without_a_layout(t: TestContext) -> void:
	var map_ui := _map_ui(t)
	if map_ui == null:
		return
	var world_map := map_ui.world_map
	WorldMapWindow.use_map(null)
	t.check(map_ui.open_world_map(), "the world map did not open without a layout")
	t.check(world_map.message_label.visible, "no message without a layout")
	t.equal(world_map.summary_label.text, SUMMARY_NO_LAYOUT % WorldMapWindow.discovered_areas().size(), "summary without a layout")
	t.equal(world_map.region_text("level-1"), "", "a region label without a layout")
	t.check(not world_map.player_dot().is_finite(), "a player dot without a layout")
	await t.steps(2)
	map_ui.close_world_map()
	WorldMapWindow.reload_map()
	world_map.refresh()
	t.check(WorldMapWindow.map_data() != null and not world_map.message_label.visible, "the layout did not come back")
	t.equal(world_map.region_text("level-1"), "Slimeshire Meadow\nCurrent area", "level-1's region label with the layout back")


# --- helpers --------------------------------------------------------------------------------------

## A stand-in for game/building's furniture placement: `is_active()` is always true.
func _placement_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node\nfunc is_active() -> bool:\n\treturn true\n"
	script.reload()
	return script


func _map_ui(t: TestContext) -> MapUi:
	var node := t.tree.get_first_node_in_group(MapUi.GROUP) as MapUi
	t.check(node != null, "no MapUi (group map_ui) in main")
	return node


func _game_windows(t: TestContext) -> Node:
	var node := t.tree.get_first_node_in_group(&"game_windows")
	t.check(node != null, "no GameWindows (group game_windows) in main")
	return node


## The summary with `count` of the layout's regions discovered.
func _summary(count: int) -> String:
	var map := WorldMapWindow.map_data()
	return SUMMARY_FORMAT % [count, map.regions().size() if map != null else 0]
