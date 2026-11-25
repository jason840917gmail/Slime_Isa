extends Node2D
## The Crystal Colossus's look in the plate fight (step 2 of the dungeons 2 and 3 rework;
## docs/godot/DUNGEONS.md "The Crystal Colossus (roadmap 12.4)", "The plate fight"): his bare body
## (rose quartz in the plate sockets) with his three armour plates laid on it as layers, each plate
## cold (pale cyan), hot (glowing orange, brittle) or gone (its socket bare). The plates are his health
## bar in sight.
##
## The art is `scripts/art/boss_frames.py pack colossus`'s (the format in the head of its "packing for
## the game" part): per animation a strip of equal cells at `px_per_unit` art px a game unit, the
## `anchor` (the art point at his feet), and per frame each visible plate's `cold` and `hot` piece in
## the animation's plate atlas (`rect` in the atlas, `at` its top left in the cell). Plates are named
## by the screen side they sit on when he faces the viewer: L (his right shoulder), C (the
## breastplate), R (his left shoulder); seen from behind L is on the right. The side walk faces right
## (`faces`): mirrored for the left, where its near shoulder piece shows his left shoulder (R).
##
## It hangs under the enemy's Visual (a Sprite2D drawing nothing in the plate fight, scaled to
## 1 / px_per_unit), so the hit flash (the Visual's material: every sprite here uses its parent's),
## the hit motion and the Pose's lift and lean carry it. `show_pose` picks what shows; a hot plate
## pulses gently (the gameplay clock: films step it frame by frame). Presentation only.
##
## Owner: dungeons (the Crystal Mine).

const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const Services := preload("res://game/shared/services.gd")

const FOLDER := "res://asset/MAPS/enemies/bosses/colossus/"
const MANIFEST := "frames.json"
const PLATES: Array[String] = ["L", "C", "R"]
## A plate's state.
const GONE := 0
const COLD := 1
const HOT := 2
## The hot plates' pulse: their brightness swings between these over this period.
const PULSE_MS := 900.0
const PULSE_LOW := 0.9
const PULSE_HIGH := 1.25
## A plate struck cold flashes white this long.
const CLANG_FLASH_MS := 140.0

static var _manifest: Dictionary = {}
static var _pictures: Dictionary = {}

var _body: Sprite2D
## Per data plate name (the piece the frame names "L", "C" or "R"): its sprite.
var _pieces: Dictionary = {}
var _key := ""
var _index := -1
var _mirrored := false
## Per plate (L, C, R: his own, not the piece's): GONE, COLD or HOT.
var _states: Dictionary = {"L": COLD, "C": COLD, "R": COLD}
var _clang_until: Dictionary = {}


## The packed manifest (cached): {} when it cannot be read.
static func manifest() -> Dictionary:
	if not _manifest.is_empty():
		return _manifest
	var text := FileAccess.get_file_as_string(FOLDER + MANIFEST)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if parsed is Dictionary:
		_manifest = parsed
	return _manifest


## Art pixels per game unit (the Visual is scaled by its inverse).
static func px_per_unit() -> float:
	return maxf(0.01, float(manifest().get("px_per_unit", 2.0)))


static func picture(file: String) -> Texture2D:
	if file.is_empty():
		return null
	if not _pictures.has(file):
		_pictures[file] = SheetSprite.load_picture(FOLDER + file)
	return _pictures[file]


## The animation `key`'s entry ({} when there is none).
static func entry(key: String) -> Dictionary:
	var animations: Variant = manifest().get("animations", {})
	var found: Variant = (animations as Dictionary).get(key, {}) if animations is Dictionary else {}
	return found if found is Dictionary else {}


func _ready() -> void:
	use_parent_material = true
	# Laid out each frame from the gameplay clock (its body's offset changes with the animation): no
	# physics interpolation on top, or the body lags its plates for a frame at a change.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_body = Sprite2D.new()
	_body.name = "Body"
	_body.centered = false
	_body.region_enabled = true
	_body.use_parent_material = true
	add_child(_body)
	for plate: String in PLATES:
		var piece := Sprite2D.new()
		piece.name = "Plate" + plate
		piece.centered = false
		piece.region_enabled = true
		piece.use_parent_material = true
		piece.visible = false
		add_child(piece)
		_pieces[plate] = piece


## Shows frame `index` of animation `key` (mirrored round his feet when `mirrored`) with his plates
## in `states` ({"L": GONE / COLD / HOT, ...}).
func show_pose(key: String, index: int, mirrored: bool, states: Dictionary) -> void:
	var anim := entry(key)
	if anim.is_empty() or _body == null:
		return
	index = clampi(index, 0, maxi(0, int(anim.get("frames", 1)) - 1))
	_states = states.duplicate()
	if key == _key and index == _index and mirrored == _mirrored:
		_lay_plates(anim)
		return
	_key = key
	_index = index
	_mirrored = mirrored
	var cell := _vec(anim.get("cell", [0, 0]))
	var anchor := _vec(anim.get("anchor", [0, 0]))
	_body.texture = picture(str(anim.get("file", "")))
	_body.region_rect = Rect2(cell.x * index, 0.0, cell.x, cell.y)
	_body.position = -anchor
	scale = Vector2(-1.0 if mirrored else 1.0, 1.0)
	_lay_plates(anim)


## The animation and frame shown ("" before the first `show_pose`).
func shown_key() -> String:
	return _key


func shown_index() -> int:
	return _index


func is_mirrored() -> bool:
	return _mirrored


## Where plate `plate` (his own: L, C or R) sits now (global, the middle of its piece); Vector2.INF
## when the frame does not show it.
func plate_point(plate: String) -> Vector2:
	var piece := _pieces.get(_piece_of(plate)) as Sprite2D
	if piece == null or piece.texture == null or not _shows(plate):
		return Vector2.INF
	return piece.to_global(piece.region_rect.size * 0.5)


## A cold plate struck (the cart's clang): it flashes white a moment.
func flash_plate(plate: String) -> void:
	_clang_until[plate] = Services.now_ms() + CLANG_FLASH_MS


func _process(_delta: float) -> void:
	if _body == null:
		return
	var now := Services.now_ms()
	var pulse := 0.5 + 0.5 * sin(now / PULSE_MS * TAU)
	var glow := lerpf(PULSE_LOW, PULSE_HIGH, pulse)
	for plate: String in PLATES:
		var piece := _pieces.get(_piece_of(plate)) as Sprite2D
		if piece == null or not piece.visible:
			continue
		var white := now < float(_clang_until.get(plate, -1.0))
		if white:
			piece.self_modulate = Color(2.0, 2.0, 2.0)
		elif int(_states.get(plate, GONE)) == HOT:
			piece.self_modulate = Color(glow, glow, glow)
		else:
			piece.self_modulate = Color.WHITE


# --- the plates ------------------------------------------------------------------------------------

## The frame's piece name that shows plate `plate`: mirrored (the side walk facing left) the near
## shoulder piece "L" shows his left shoulder (R), and "R" his right.
func _piece_of(plate: String) -> String:
	if not _mirrored:
		return plate
	if plate == "L":
		return "R"
	if plate == "R":
		return "L"
	return plate


func _shows(plate: String) -> bool:
	var piece := _pieces.get(_piece_of(plate)) as Sprite2D
	return piece != null and piece.visible


func _lay_plates(anim: Dictionary) -> void:
	var frames: Variant = anim.get("plates", [])
	var frame: Dictionary = {}
	if frames is Array and _index < (frames as Array).size() and (frames as Array)[_index] is Dictionary:
		frame = (frames as Array)[_index]
	var atlas := picture(str(anim.get("plates_file", "")))
	var anchor := _vec(anim.get("anchor", [0, 0]))
	for plate: String in PLATES:
		var piece_name := _piece_of(plate)
		var piece := _pieces[piece_name] as Sprite2D
		var state := int(_states.get(plate, GONE))
		var data: Variant = frame.get(piece_name)
		if state == GONE or not data is Dictionary or atlas == null:
			piece.visible = false
			continue
		var look: Variant = (data as Dictionary).get("hot" if state == HOT else "cold")
		if not look is Dictionary:
			piece.visible = false
			continue
		var rect: Array = (look as Dictionary).get("rect", [0, 0, 0, 0])
		piece.texture = atlas
		piece.region_rect = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
		piece.position = _vec((look as Dictionary).get("at", [0, 0])) - anchor
		piece.visible = true


static func _vec(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
