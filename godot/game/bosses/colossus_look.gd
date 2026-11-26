extends Node2D
## The Crystal Colossus's look in the crystal fight (step 2 of the dungeons 2 and 3 rework; the three
## crystals, 2026-11-25; docs/godot/DUNGEONS.md "The Crystal Colossus (roadmap 12.4)", "The crystal
## fight"): his bare body with a crystal of rose quartz in each of the three sockets under his armour
## plates, each crystal live (glowing, pulsing, a rose glow over a dark room's darkness) or dead (dark
## slate, cracked, no glow), and his plates laid over them, each cold (pale cyan), hot (glowing
## orange, brittle) or gone (its crystal bare). Plates and crystals are his health bar in sight.
##
## The art is `scripts/art/boss_frames.py pack colossus`'s (the format in the head of its "packing for
## the game" part): per animation a strip of equal cells at `px_per_unit` art px a game unit, the
## `anchor` (the art point at his feet), and per frame each visible plate's `cold` and `hot` piece and
## the crystal under it, `live` and `dead`, in the animation's plate atlas (`rect` in the atlas, `at`
## its top left in the cell). Plates and crystals are named by the screen side they sit on when he
## faces the viewer: L (his right shoulder), C (the breastplate), R (his left shoulder); seen from
## behind L is on the right. The side walk faces right (`faces`): mirrored for the left, where its near
## shoulder piece shows his left shoulder (R).
##
## It hangs under the enemy's Visual (a Sprite2D drawing nothing, scaled to 1 / px_per_unit), so the
## hit flash (the Visual's material: every piece here uses its parent's, but the glows), the hit motion
## and the Pose's lift and lean carry it. `show_pose` picks what shows; a hot plate and a live crystal
## pulse gently (the gameplay clock: films step it frame by frame). Presentation only.
##
## Owner: dungeons (the Crystal Mine).

const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const Services := preload("res://game/shared/services.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")

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
## A crystal's state: LIVE (glowing) or DEAD (dark and cracked for good). It shows only where its
## plate is gone.
const LIVE := 1
const DEAD := 2
## A live crystal's pulse (its brightness between these over this period), its glow over the
## darkness (rose, its alpha between these, its size in art px: the chest's bigger), drawn over a dark
## room's darkness (dark_room.gd's OVERLAY_Z is 45); a crystal struck flashes white this long.
const CRYSTAL_PULSE_MS := 1100.0
const CRYSTAL_PULSE_LOW := 1.0
const CRYSTAL_PULSE_HIGH := 1.35
const CRYSTAL_GLOW := Color(1.0, 0.42, 0.66)
const CRYSTAL_GLOW_LOW := 0.28
const CRYSTAL_GLOW_HIGH := 0.55
const CRYSTAL_GLOW_PX := 150.0
const CHEST_GLOW_PX := 210.0
const OVER_THE_DARK_Z := 46
const CRYSTAL_FLASH_MS := 120.0

static var _manifest: Dictionary = {}
static var _pictures: Dictionary = {}

var _body: Sprite2D
## Per data plate name (the piece the frame names "L", "C" or "R"): its sprite.
var _pieces: Dictionary = {}
## Per data crystal name (as the plates'): its sprite and its glow.
var _crystal_pieces: Dictionary = {}
var _glows: Dictionary = {}
var _key := ""
var _index := -1
var _mirrored := false
## Per plate (L, C, R: his own, not the piece's): GONE, COLD or HOT.
var _states: Dictionary = {"L": COLD, "C": COLD, "R": COLD}
## Per crystal (his own): LIVE or DEAD.
var _crystals: Dictionary = {"L": LIVE, "C": LIVE, "R": LIVE}
var _clang_until: Dictionary = {}
var _crystal_flash_until: Dictionary = {}


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
	# the crystals on the body, the plates over them
	for crystal: String in PLATES:
		var piece := Sprite2D.new()
		piece.name = "Crystal" + crystal
		piece.centered = false
		piece.region_enabled = true
		piece.use_parent_material = true
		piece.visible = false
		add_child(piece)
		_crystal_pieces[crystal] = piece
	for plate: String in PLATES:
		var piece := Sprite2D.new()
		piece.name = "Plate" + plate
		piece.centered = false
		piece.region_enabled = true
		piece.use_parent_material = true
		piece.visible = false
		add_child(piece)
		_pieces[plate] = piece
	for crystal: String in PLATES:
		var glow := Sprite2D.new()
		glow.name = "Glow" + crystal
		glow.texture = FireFx.glow_texture()
		glow.material = FireFx.additive()
		glow.z_index = OVER_THE_DARK_Z
		glow.z_as_relative = false
		glow.visible = false
		var px := CHEST_GLOW_PX if crystal == "C" else CRYSTAL_GLOW_PX
		glow.scale = Vector2.ONE * px / maxf(1.0, float(glow.texture.get_width()))
		add_child(glow)
		_glows[crystal] = glow


## Shows frame `index` of animation `key` (mirrored round his feet when `mirrored`) with his plates
## in `states` ({"L": GONE / COLD / HOT, ...}) and his crystals in `crystals` ({"L": LIVE / DEAD, ...};
## missing: live). A crystal shows only where its plate is gone.
func show_pose(key: String, index: int, mirrored: bool, states: Dictionary, crystals: Dictionary = {}) -> void:
	var anim := entry(key)
	if anim.is_empty() or _body == null:
		return
	index = clampi(index, 0, maxi(0, int(anim.get("frames", 1)) - 1))
	_states = states.duplicate()
	_crystals = crystals.duplicate()
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


## Where crystal `crystal` (his own: L, C or R) sits now (global, the middle of its piece); Vector2.INF
## when the frame does not show it (its plate on, or the pose hides it).
func crystal_point(crystal: String) -> Vector2:
	var piece := _crystal_pieces.get(_piece_of(crystal)) as Sprite2D
	if piece == null or piece.texture == null or not piece.visible:
		return Vector2.INF
	return piece.to_global(piece.region_rect.size * 0.5)


## A crystal struck (a Spear hit, a throw): it flashes white a moment.
func flash_crystal(crystal: String) -> void:
	_crystal_flash_until[crystal] = Services.now_ms() + CRYSTAL_FLASH_MS


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
	var beat := 0.5 + 0.5 * sin(now / CRYSTAL_PULSE_MS * TAU)
	for crystal: String in PLATES:
		var piece := _crystal_pieces.get(_piece_of(crystal)) as Sprite2D
		var halo := _glows.get(_piece_of(crystal)) as Sprite2D
		var live := piece != null and piece.visible and int(_crystals.get(crystal, LIVE)) == LIVE
		if piece != null and piece.visible:
			if now < float(_crystal_flash_until.get(crystal, -1.0)):
				piece.self_modulate = Color(2.0, 2.0, 2.0)
			elif live:
				var bright := lerpf(CRYSTAL_PULSE_LOW, CRYSTAL_PULSE_HIGH, beat)
				piece.self_modulate = Color(bright, bright, bright)
			else:
				piece.self_modulate = Color.WHITE
		if halo != null:
			halo.visible = live
			if live:
				halo.position = piece.position + piece.region_rect.size * 0.5
				halo.modulate = Color(CRYSTAL_GLOW, lerpf(CRYSTAL_GLOW_LOW, CRYSTAL_GLOW_HIGH, beat))


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
	_lay_crystals(anim, atlas, anchor)


## Each crystal's piece, live or dead, where its plate is gone and the frame shows it.
func _lay_crystals(anim: Dictionary, atlas: Texture2D, anchor: Vector2) -> void:
	var frames: Variant = anim.get("crystals", [])
	var frame: Dictionary = {}
	if frames is Array and _index < (frames as Array).size() and (frames as Array)[_index] is Dictionary:
		frame = (frames as Array)[_index]
	for crystal: String in PLATES:
		var piece_name := _piece_of(crystal)
		var piece := _crystal_pieces[piece_name] as Sprite2D
		var data: Variant = frame.get(piece_name)
		if int(_states.get(crystal, GONE)) != GONE or not data is Dictionary or atlas == null:
			piece.visible = false
			continue
		var look: Variant = (data as Dictionary).get("dead" if int(_crystals.get(crystal, LIVE)) == DEAD else "live")
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
