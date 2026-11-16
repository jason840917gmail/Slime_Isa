extends RefCounted
## The pictures made for a cliff's face, one per wall style (docs/godot/SKINS.md "Balconies",
## docs/godot/DUNGEONS.md "Holes and hatches"): the balcony the vines' layer draws
## (game/world/vines/vine_layer.gd), the cave mouth and the wall hole (wall_door_picture.gd). Each is
## `asset/MAPS/objects/<kind>-<style>.webp`, packed by scripts/art/pack-wall-pictures.py from the
## sources in asset/Originals/elevation/balcony/ and wall-doors/. A picture matches the wall it is on
## by the style the elevation draws that wall in (Elevation.wall_style_at: painted on the `cliffs`
## layer, else the ground's); a style without its picture shows the default style's
## (Elevation.DEFAULT_WALL_STYLE, meadow rock).
##
## Owner: skins.

const Elevation := preload("res://game/world/elevation/elevation.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const PICTURE := "res://asset/MAPS/objects/%s-%s.webp"
const BALCONY := "balcony"
const CAVE_MOUTH := "cave-mouth"
const WALL_HOLE := "wall-hole"
## Each balcony picture's straight back edge, which lies on the top of the painted row: px from the
## picture's top, the first row where the art is wider than 60% of its width (printed by
## scripts/art/pack-wall-pictures.py). A balcony picture is used only with its row here.
const BALCONY_BACKS := {
	"autumn-face": 12,
	"castle-face": 3,
	"cave-face": 3,
	"cave-rock": 1,
	"crystal-face": 1,
	"crystal-rock": 2,
	"desert-dirt": 1,
	"desert-face": 1,
	"desert-strata": 0,
	"dungeon-face": 3,
	"forest-face": 3,
	"ice-dirt": 4,
	"masonry": 1,
	"meadow-face": 7,
	"meadow-rock": 5,
	"mossy-rock": 3,
	"mountain-dirt": 2,
	"red-rock": 2,
	"root-rock": 3,
	"sandstone": 3,
	"snow-face": 3,
	"snow-rock": 2,
	"storybook-rock": 2,
	"town-face": 0,
	"volcanic-face": 1,
}

## path -> true when the picture is there (imported, or packed and not imported yet).
static var _found: Dictionary = {}
static var _textures: Dictionary = {}


## The style whose `kind` picture shows on a wall of `style`: `style` when its picture is made, else
## the default style.
static func style_for(kind: String, style: String) -> String:
	if style.is_empty() or (kind == BALCONY and not BALCONY_BACKS.has(style)):
		return Elevation.DEFAULT_WALL_STYLE
	return style if _exists(path_of(kind, style)) else Elevation.DEFAULT_WALL_STYLE


## The file of `kind`'s picture in `style` (made or not).
static func path_of(kind: String, style: String) -> String:
	return PICTURE % [kind, style]


## `kind`'s picture for a wall of `style` (`style_for`), or null.
static func texture(kind: String, style: String) -> Texture2D:
	var path := path_of(kind, style_for(kind, style))
	if not _textures.has(path) or _textures[path] == null:
		_textures[path] = SheetSprite.load_picture(path)
	return _textures[path] as Texture2D


## The wall style of the cliff face at `world_point` in the world `node` is in; "" off any wall, or
## where the world has no elevation (yet).
static func wall_style(node: Node, world_point: Vector2) -> String:
	var elevation := Elevation.around(node)
	return elevation.wall_style_at(world_point) if elevation != null else ""


## True when the picture at `path` is there: looked up once in the game, every time in the editor
## (a picture packed while it is open shows at once).
static func _exists(path: String) -> bool:
	if Engine.is_editor_hint():
		return ResourceLoader.exists(path) or FileAccess.file_exists(path)
	if not _found.has(path):
		_found[path] = ResourceLoader.exists(path) or FileAccess.file_exists(path)
	return bool(_found[path])
