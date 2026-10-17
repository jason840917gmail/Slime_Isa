@tool
extends Node2D
class_name Hazard
## One hazard script for the void, spikes and lava (docs/godot/DUNGEONS.md "The void, slabs and
## spikes"; decisions archive question 70, roadmap 5.14). A hazard is the rectangle `size` from its
## position; the slime is in it when its feet are inside and it is not held up by a deck there
## (hazard_deck.gd: a standing slab, a lowered drawbridge, a landing, a shadow path), or when it
## walks on a lower level than `rim_level` (it dropped into the elevation hole painted under it:
## "the void works like the elevation's holes"). HazardWatch (hazard_watch.gd, made by the first
## hazard of a world) does the rest:
##
## - **void**: the slime falls (it spins and shrinks away over `dungeon.void.fallMs`), loses a little
##   health (`damage`, else `dungeon.void.damage`) and is put back on the rim it fell from: the last
##   safe ground it stood on, or the nearest of `return_points` to it (the bridge's start);
## - **spikes** and **lava**: it is hurt each time its invulnerability ends, until it walks out
##   (a stair up to the rim). A slab that falls from under it over a sunken pit drops it in
##   (`pit_depth` levels down).
##
## Paint the void as a hole on the world's `elevation` layer and lay the hazard over the hole; it
## draws its look over it (`draw_look`: the abyss, fading in over `top_fade_px` so the hole's far
## wall sinks into the dark; the spike rows; the glowing lava), or is a flat pit in a world without
## elevation. Keep a hazard above its decks in the tree (they draw over it).
##
## Owner: dungeon kit.

const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const GROUP := &"hazards"
const KINDS: PackedStringArray = ["void", "spikes", "lava"]
const SPIKES_ART := "res://asset/MAPS/objects/dungeon/spikes.webp"
const RETURN_PREFIX := "Return"
const EDITOR_FILL := {"void": Color(0.05, 0.02, 0.1, 0.45), "spikes": Color(0.55, 0.25, 0.15, 0.4),
	"lava": Color(1.0, 0.4, 0.05, 0.4)}
const EDITOR_EDGE := Color(1.0, 0.3, 0.6, 0.9)
## The abyss: its colour, and the soft edge that fades into it.
const ABYSS := Color("#07050c")
const ABYSS_EDGE_PX := 22.0
const LAVA_DEEP := Color("#c2410c")
const LAVA_GLOW := Color("#fdba74")
## The hazard's look sits on the floor, under every body.
const LOOK_Z := -1

@export_enum("void", "spikes", "lava") var kind: String = "void":
	set(value):
		kind = value
		queue_redraw()
## The hazard's rectangle (world units from this node's position).
@export var size: Vector2 = Vector2(256, 192):
	set(value):
		size = value
		queue_redraw()
## The elevation level of the ground around it and of its decks (0 without elevation).
@export var rim_level: int = 0
## A sunken spike or lava pit: how many levels below `rim_level` its floor is.
@export var pit_depth: int = 1
## Health lost per hit (or per fall); < 0: `dungeon.<kind>.damage`.
@export var damage: float = -1.0
## Draws the abyss, the spikes or the lava itself (over an elevation hole too: the void's dark).
@export var draw_look: bool = true:
	set(value):
		draw_look = value
		queue_redraw()
## The void's dark grows over this much of its top, and spikes and lava start below it (an
## elevation hole's far wall: 64 a level).
@export var top_fade_px: float = 0.0:
	set(value):
		top_fade_px = value
		queue_redraw()
## Where a fall puts the slime back (Node2D markers: their spot is the slime's centre); empty: its
## children named "Return..."; none: the last safe ground the slime stood on.
@export var return_points: Array[NodePath] = []

var _spikes: Texture2D


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func _ready() -> void:
	z_index = LOOK_Z
	if Engine.is_editor_hint():
		return
	var watch_script := load("res://game/dungeon/hazard_watch.gd") as GDScript
	watch_script.call(&"ensure", self)


## The hazard in world coordinates.
func rect() -> Rect2:
	return Rect2(global_position, size)


## Health lost per hit or fall.
func hit_damage() -> float:
	if damage >= 0.0:
		return damage
	return DungeonState.number(kind + ".damage", 10.0)


## Its return markers' spots (global).
func return_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for path: NodePath in return_points:
		var node := get_node_or_null(path) as Node2D
		if node != null:
			out.append(node.global_position)
	if out.is_empty():
		for child: Node in get_children():
			if child is Node2D and String(child.name).begins_with(RETURN_PREFIX):
				out.append((child as Node2D).global_position)
	return out


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	if Engine.is_editor_hint():
		draw_rect(area, EDITOR_FILL.get(kind, Color(1, 0, 1, 0.3)))
		draw_rect(area, EDITOR_EDGE, false, 2.0)
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, Vector2(8, 22), "hazard: " + kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, EDITOR_EDGE)
	if not draw_look:
		return
	# Spikes and lava lie on a pit's floor, below its far wall (`top_fade_px`).
	var floor_area := Rect2(area.position + Vector2(0.0, top_fade_px), Vector2(area.size.x, maxf(0.0, area.size.y - top_fade_px)))
	match kind:
		"void":
			_draw_abyss(area)
		"spikes":
			_draw_spikes(floor_area)
		"lava":
			_draw_lava(floor_area)


## A deep black pit: over its top `top_fade_px` the dark grows out of nothing (an elevation hole's
## far wall shows, sinking into the dark), below it is black; its other edges are soft.
func _draw_abyss(area: Rect2) -> void:
	var fade := clampf(top_fade_px, 0.0, area.size.y)
	var clear := Color(ABYSS, 0.0)
	if fade > 0.0:
		draw_polygon(PackedVector2Array([area.position, Vector2(area.end.x, area.position.y),
			Vector2(area.end.x, area.position.y + fade), Vector2(area.position.x, area.position.y + fade)]),
			PackedColorArray([clear, clear, ABYSS, ABYSS]))
	var body := Rect2(area.position + Vector2(0.0, fade), Vector2(area.size.x, area.size.y - fade))
	var steps := 4
	for i in steps:
		var inset := ABYSS_EDGE_PX * 0.5 * float(i) / float(steps)
		var band := Rect2(body.position + Vector2(inset, 0.0), Vector2(body.size.x - inset * 2.0, body.size.y - inset))
		draw_rect(band, Color(ABYSS, 0.4 + 0.6 * float(i + 1) / float(steps)))


func _draw_spikes(area: Rect2) -> void:
	if _spikes == null:
		_spikes = SheetSprite.load_picture(SPIKES_ART)
	if _spikes == null:
		draw_rect(area, Color("#3a2a20"))
		var x := 8.0
		while x < area.size.x:
			var y := 8.0
			while y < area.size.y:
				draw_colored_polygon(PackedVector2Array([Vector2(x - 5, y + 6), Vector2(x, y - 8), Vector2(x + 5, y + 6)]), Color("#8a8f99"))
				y += 22.0
			x += 22.0
		return
	# The tile is 128 px a cell (two pixels a unit).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.5, 0.5))
	draw_texture_rect(_spikes, Rect2(area.position * 2.0, area.size * 2.0), true)
	draw_set_transform(Vector2.ZERO)


func _draw_lava(area: Rect2) -> void:
	draw_rect(area, LAVA_DEEP)
	draw_rect(area.grow(-10.0), Color(LAVA_GLOW, 0.35))
