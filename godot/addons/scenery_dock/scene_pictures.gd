@tool
extends RefCounted
## The Scenery dock's pictures of the pieces whose scene holds no sprite (docs/godot/PROPS.md "The
## Scenery dock"): a piece whose script draws it or builds its look when it runs (the brazier, the
## falling floors, the web wall...) or that is only a marker in the editor (a room door, a room
## fight). The dock lists a scene by its biggest sprite (scenery_dock.gd `_scene_picture`); for a
## scene without one it asks here, and shows Godot's scene icon only when this table has no line
## for it either.
##
## A new piece without a sprite: add its line (the scene's file name, its art, the art's grid and
## the frame to show). A marker with no art gets an icon in ICONS (made by
## scripts/art/build-dock-icons.py; the folder is left out of exported games with the palettes).
##
## Owner: world (props).

const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const ICONS := "res://asset/MAPS/palettes/dock/"
const DUNGEON := "res://asset/MAPS/objects/dungeon/"
const WEBS := "res://asset/MAPS/webs/"
## Scene file name -> [picture, its grid (columns, rows), the frame shown].
const PICTURES := {
	"brazier": ["res://asset/MAPS/props/caverns/256x256-tile_2x1-brazier.webp", Vector2i(2, 1), 0],
	"crystal-veil": ["res://asset/MAPS/props/mine/256x256-tile_2x1-crystal-veil.webp", Vector2i(2, 1), 0],
	"divider-gate": [DUNGEON + "divider-eye-block.png", Vector2i(1, 1), 0],
	"dungeon-key": ["res://asset/UI/items/dungeon-items.webp", Vector2i(2, 2), 0],
	"falling-plank": [DUNGEON + "plank-2x1.webp", Vector2i(2, 1), 0],
	"falling-slab": [DUNGEON + "slab-2x1.webp", Vector2i(2, 1), 0],
	"floor-web": [WEBS + "floor-webs-6x1.webp", Vector2i(6, 1), 0],
	"hazard": [ICONS + "hazard.png", Vector2i(1, 1), 0],
	"hazard-deck": [ICONS + "hazard-deck.png", Vector2i(1, 1), 0],
	"heavy-plate": ["res://asset/MAPS/props/heavy-plate/cap-2x1.webp", Vector2i(2, 1), 0],
	"plank-landing": [ICONS + "plank-landing.png", Vector2i(1, 1), 0],
	"prize-glint": [ICONS + "prize-glint.png", Vector2i(1, 1), 0],
	"room-door": [ICONS + "room-door.png", Vector2i(1, 1), 0],
	"room-fight": [ICONS + "room-fight.png", Vector2i(1, 1), 0],
	"shadow-path": [DUNGEON + "glow-moss.webp", Vector2i(1, 1), 0],
	"silk-parcel": [WEBS + "silk-parcel-3x1.webp", Vector2i(3, 1), 0],
	"web-wall": [WEBS + "web-wall-across-2x1.webp", Vector2i(2, 1), 0],
}


## The picture of the scene at `scene` (its table line's frame), or null when it has no line or its
## art is missing.
static func of(scene: String) -> Texture2D:
	var line: Variant = PICTURES.get(scene.get_file().get_basename())
	if not line is Array:
		return null
	var sheet := SheetSprite.load_picture(str(line[0]))
	if sheet == null:
		return null
	var grid: Vector2i = line[1]
	var frame: int = line[2]
	var cell := Vector2(sheet.get_size()) / Vector2(grid)
	var picture := AtlasTexture.new()
	picture.atlas = sheet
	picture.region = Rect2(Vector2(frame % grid.x, frame / grid.x) * cell, cell)
	return picture
