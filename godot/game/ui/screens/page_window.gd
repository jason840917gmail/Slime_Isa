extends "res://game/ui/screens/game_window.gd"
## The reading panel of a page found (B6, 2026-11-20; quests spec 14.8): a war-journal page or a
## recipe page coming in (RunState `page_found`, not quiet: a chest's page taken, a page picked up)
## opens it at once, on top of the chest window when the page came out of one. Built in code; main
## adds it to GameWindows (surface "page": the `modal` pause; it plays JournalOpen, closing plays
## MenuClose). Group `page_window`.
##
## Top: the page's icon, what it is ("Thorn Guard war journal · Page 2 of 3", "Recipe page") and its
## title; then its lines (game/data/items.json `page`, read by game/quests/war_journal.gd); then a
## footer: a war page "Kept in your journal, under War journal.", a recipe page what it taught ("New
## recipe: Berry Basket. Cook it at a campfire."); and Close (Escape too). Pages found together
## (a chest's "take all") wait their turn and open one after another. Closing gives the focus back to
## the window under it (the chest window).
##
## Owner: quests (UI).

const Services := preload("res://game/shared/services.gd")
const WarJournal := preload("res://game/quests/war_journal.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")
const WindowStyle := preload("res://game/ui/screens/window_style.gd")

const SURFACE_ID := &"page"
const GROUP := &"page_window"
const OPEN_CUE := &"JournalOpen"
const ICON_PX := 72.0
const TEXT_FONT := 15
const TEXT_PITCH := 21.0
const CORNER_RADIUS := 6
const WAR_KICKER := "Thorn Guard war journal · Page %d of %d"
const RECIPE_KICKER := "Recipe page"
const WAR_FOOTER := "Kept in your journal, under War journal."
const RECIPE_FOOTER := "New recipe: %s. Cook it at a campfire."
const CLOSE_TEXT := "Close (Esc)"

var icon_rect: TextureRect
var kicker_label: Label
var title_label: Label
var text_label: Label
var footer_label: Label
var close_button: Button

## The page shown ({} when none: war_journal.gd `page`), and the pages waiting their turn.
var _page: Dictionary = {}
var _waiting: Array[String] = []


func _init() -> void:
	super()
	name = "PageWindow"
	surface_id = SURFACE_ID
	max_size = Vector2(620.0, 460.0)
	content_height = 460.0


func _ready() -> void:
	super()
	add_to_group(GROUP)
	var run := Services.run()
	if run != null and not run.page_found.is_connected(_on_page_found):
		run.page_found.connect(_on_page_found)


func _exit_tree() -> void:
	var run := Services.run()
	if run != null and run.page_found.is_connected(_on_page_found):
		run.page_found.disconnect(_on_page_found)


## Shows the page item `item_id` (a war-journal page or a recipe page); one already open waits.
func open_page(item_id: String) -> void:
	if WarJournal.page(item_id).is_empty():
		return
	if is_open():
		if str(_page.get("item_id", "")) != item_id and not _waiting.has(item_id):
			_waiting.append(item_id)
		return
	_page = WarJournal.page(item_id)
	_open_quietly()


## The page shown ({} when closed).
func current_page() -> Dictionary:
	return _page if is_open() else {}


## Closes it; the next page waiting opens, else the window under it gets the focus back.
func close() -> void:
	super()
	if not _waiting.is_empty():
		var next: String = _waiting.pop_front()
		open_page(next)
		return
	var windows := game_windows()
	var below: Node = windows.call(&"top") if windows != null else null
	if below != null and is_instance_valid(below) and below.has_method(&"focus_initial"):
		below.call(&"focus_initial")


func refresh() -> void:
	if content == null or _page.is_empty():
		return
	var item_id := str(_page.get("item_id", ""))
	icon_rect.texture = ItemIcons.icon(item_id)
	if str(_page.get("kind", "")) == "war":
		kicker_label.text = WAR_KICKER % [int(_page.get("number", 0)), WarJournal.page_count()]
		footer_label.text = WAR_FOOTER
	else:
		kicker_label.text = RECIPE_KICKER
		var names: Array[String] = []
		for recipe_id: String in _page.get("recipes", []):
			names.append(str(RecipeCatalog.find(recipe_id).get("name", recipe_id)))
		footer_label.text = RECIPE_FOOTER % ", ".join(names) if not names.is_empty() else ""
	title_label.text = str(_page.get("title", ""))
	text_label.text = "\n\n".join(_page.get("lines", []))


func _build() -> void:
	icon_rect = TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_rect)
	kicker_label = _label("Kicker", &"AccentLabel", 14)
	kicker_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	title_label = _label("Title", &"PanelTitle", 26)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title_label.clip_text = true
	text_label = _label("Text", &"", TEXT_FONT)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	WindowStyle.set_line_pitch(text_label, TEXT_FONT, TEXT_PITCH)
	footer_label = _label("Footer", &"InfoLabel", 13)
	footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	close_button = _button("Close", CLOSE_TEXT, &"MutedButton", 16, close)
	var bold := WindowStyle.bold_font(self)
	if bold != null:
		close_button.add_theme_font_override(&"font", bold)
		title_label.add_theme_font_override(&"font", bold)
	WindowStyle.round_corners(close_button, CORNER_RADIUS)


func _layout(width: float) -> void:
	var w := width
	_place(icon_rect, _rect(24.0, 20.0, 24.0 + ICON_PX, 20.0 + ICON_PX))
	_place(kicker_label, _rect(112.0, 22.0, w - 24.0, 48.0))
	_place(title_label, _rect(112.0, 50.0, w - 24.0, 92.0))
	_place(text_label, _rect(28.0, 112.0, w - 28.0, 360.0))
	_place(footer_label, _rect(28.0, 368.0, w - 28.0, 396.0))
	_place(close_button, _rect(w * 0.5 - 90.0, 404.0, w * 0.5 + 90.0, 444.0))


## GameWindow.open with a quiet push: a page plays JournalOpen, not MenuOpen.
func _open_quietly() -> void:
	_open = true
	_on_opening()
	visible = true
	_layout_panel()
	refresh()
	var windows := game_windows()
	if windows != null:
		windows.call(&"push", self, surface_id, true)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(OPEN_CUE)
	focus_initial()
	opened.emit(self)


func _on_page_found(payload: Dictionary) -> void:
	if bool(payload.get("quiet", false)) or not is_inside_tree():
		return
	# Deferred: a chest window taking the page refreshes (and refocuses) first, then the panel opens
	# over it with the focus.
	open_page.call_deferred(str(payload.get("item_id", "")))
