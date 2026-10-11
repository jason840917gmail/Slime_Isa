@tool
class_name MapNote
extends Node2D
## A marker of the world map sketch (res://game/data/world-map.json `markers`: a gate, cave,
## dungeon, boss, town, landmark, note, ...) placed in a world scene where the sketch put it, so the
## editor shows what is planned there. godot/tools/build_region_worlds.gd places one per marker in
## the placeholder region worlds; add more by hand (Add Node > MapNote) anywhere.
##
## Editor only: in the editor it draws a small badge (the first letter of its kind) and its label;
## in the game it draws nothing and does nothing.
##
## Owner: world (atlas).

## Badge colour per marker kind (the sketch tool's marker types); other kinds take NOTE_COLOR.
const KIND_COLORS := {
	"gate": Color("#ffd166"), "cave": Color("#8d99ae"), "warp": Color("#c77dff"),
	"dungeon": Color("#ef476f"), "boss": Color("#d62828"), "town": Color("#06d6a0"),
	"house": Color("#f4a261"), "landmark": Color("#4cc9f0"), "npc": Color("#90be6d"),
	"item": Color("#f9c74f"), "secret": Color("#ff66c4"),
}
const NOTE_COLOR := Color("#e0e0e0")
const BADGE_RADIUS := 26.0
const FONT_SIZE := 26
const LABEL_WIDTH := 480.0

## The marker type (gate, cave, warp, dungeon, boss, town, house, landmark, npc, item, secret, note).
@export var kind: String = "note":
	set(value):
		kind = value
		queue_redraw()
## The marker's label on the sketch.
@export var label: String = "":
	set(value):
		label = value
		queue_redraw()
## The sketch's notes (with what it needs, where it leads, the game map it opens).
@export_multiline var notes: String = ""


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color: Color = KIND_COLORS.get(kind, NOTE_COLOR)
	var font := ThemeDB.fallback_font
	draw_circle(Vector2.ZERO, BADGE_RADIUS, Color(0.05, 0.06, 0.1, 0.85))
	draw_arc(Vector2.ZERO, BADGE_RADIUS, 0.0, TAU, 32, color, 4.0, true)
	var letter := kind.left(1).to_upper() if not kind.is_empty() else "?"
	var letter_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	draw_string(font, Vector2(-letter_size.x * 0.5, FONT_SIZE * 0.35), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
	if label.is_empty():
		return
	var at := Vector2(-LABEL_WIDTH * 0.5, BADGE_RADIUS + FONT_SIZE + 4.0)
	draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, FONT_SIZE, 6, Color(0.05, 0.06, 0.1, 0.9))
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, FONT_SIZE, color)
