extends RefCounted
## The body shapes' strike frames: the art (docs/design/2026-10-12-weapon-strike-frames.md;
## BODY_SHAPES.md "The Spear's strike frames", "The War Axe's and the Hammer's strike frames" and
## "Editing the strike animations"). scripts/characters/pack-slime-strikes.py and
## pack-slime-weapon-strikes.py pack six-frame body-only strips per strike and direction into one
## sheet per shape (the Spear's `res://asset/characters/512x416-tile_8x8-slime-v2-strikes.webp`, the
## Axe's `...-strikes-axe.webp`, the Hammer's `...-strikes-hammer.webp`: the same 8 x 8 grid of
## 512 x 416 cells round one origin) and write the manifest, `res://game/data/shape-strikes.json`,
## read here: per strike its sheet (`texture`, else the top-level one), its weapon and rest frame, the
## Spear's `shaft_px`; per strike and direction (a strip) the sheet `row`, `flip` for a mirrored strip
## (it shows its `source` strike's row flipped: the Axe backswing's front and back), the strip's
## `aim`, its `frames` (the socket where the weapon leaves the body; the Spear's bump, neck fade and
## spear state; the Axe's and the Hammer's `knob_w`) and `arm_px`; the cell's origin and scale, the
## Spear's tint, the weapon blocks (`weapons`: texture, scale, head_start, axis_row, handle_px,
## handle_across, hidden_px, tint_gain, the views) and the code neck (`neck`).
##
## The motion is not here: since round 4 each strike is a StrikeAnimation resource (`res://game/characters/
## strikes/<strike>.tres`, edited in the Inspector; game/shapes/strike_animation.gd, read by StrikeLibrary),
## whose timeline gives the body frame (the strip's frame numbers, on the sheets this manifest names) and the
## StrikeRig's weapon. StrikeLibrary builds the player's `strikes/<strike>-<side|down|up>` animations
## (`animation_name`) from it at run time, and ShapePoses seeks them by the gameplay clock; with each its hold
## (`hold_name`: the frame it starts on, held while a charge ring fills). The manifest's
## `flip` and `arm_px` are notes of the packer: a direction's flip_h and arm_px in its resource are what the game reads.
##
## The strikes (STRIKES, by the step's or charge's `id`): the Spear's jabs play `spear-jab`, its
## lunging jab and its Lunge `spear-finisher`; the Axe's sweep `axe-sweep`, its backswing
## `axe-backswing`, its chop `axe-chop`; the Hammer's Thud `hammer-thud`, its BOOM and its Quake
## `hammer-boom`. The Axe's Spin keeps its page-6 poses. Frames: 1 rest (never shown), 2 wind-up,
## 3 lunge / swing, 4 contact / follow-through, 5 spring back, 6 rest.
##
## A frame shown is identified by the running strike (its sheet, row and flip: `shown_frame`), never
## by its row alone. Presentation only: nothing here hits, moves or times a strike.
##
## Owner: shapes.

const ShapeDefs := preload("res://game/shapes/shape_defs.gd")

const DATA_PATH := "res://game/data/shape-strikes.json"
## The strike animations' library on the player's AnimationPlayer: `<ANIMATION_LIBRARY>/<strike>-<direction>`,
## and each one's hold `<ANIMATION_LIBRARY>/<strike>-<direction><HOLD_SUFFIX>` (StrikeLibrary).
const ANIMATION_LIBRARY := "strikes"
const HOLD_SUFFIX := "-hold"
const STRIKE_JAB := "spear-jab"
const STRIKE_FINISHER := "spear-finisher"
const STRIKE_AXE_SWEEP := "axe-sweep"
const STRIKE_AXE_BACKSWING := "axe-backswing"
const STRIKE_AXE_CHOP := "axe-chop"
const STRIKE_HAMMER_THUD := "hammer-thud"
const STRIKE_HAMMER_BOOM := "hammer-boom"
## Shape short name -> step or charge `id` -> its strike.
const STRIKES := {
	"spear": {"jab": STRIKE_JAB, "jab-2": STRIKE_JAB, "lunging-jab": STRIKE_FINISHER, "lunge": STRIKE_FINISHER},
	"axe": {"sweep": STRIKE_AXE_SWEEP, "backswing": STRIKE_AXE_BACKSWING, "chop": STRIKE_AXE_CHOP},
	"hammer": {"thud": STRIKE_HAMMER_THUD, "boom": STRIKE_HAMMER_BOOM, "quake": STRIKE_HAMMER_BOOM},
}
## Frames per sheet row (the sheets' 8 x 8 grid).
const COLUMNS := 8
## Frame numbers the effects read (the Spear's lean and lunge).
const FRAME_LEAN := 2
const FRAME_LUNGE := 3
## Manifest keys of a frame: cell px (pixel (x, y) covers [x, x + 1]), the knob's chord (game px); a
## strip's neck stretch (game px).
const SOCKET := "socket"
const KNOB_W := "knob_w"

## Keys the shape controller adds to a copy of a step's numbers while its strike frames show: the
## strike, its direction, whether it is a left side strike, and for a line where its hit line starts
## (`lineFrom`: the strike animation's socket at its contact marker, in px from the slime's centre,
## mirrored for left), which ShapeStrike.area_shapes and ShapeVisuals read.
const STRIKE_KEY := "strike"
const DIRECTION_KEY := "strikeDirection"
const MIRRORED_KEY := "strikeMirrored"
const LINE_FROM_KEY := "lineFrom"
## A chain step's hit centre (StrikeLibrary.chain_hit: the strike file's `hit_center` in that direction, mirrored
## as the strip shows), world px from the slime's centre: every area, the impact and the wall ray start there.
const HIT_CENTER_KEY := "hitCenter"

static var _manifest: Dictionary = {}
static var _read: bool = false


## The manifest ({} when the file is missing or broken).
static func manifest() -> Dictionary:
	if not _read:
		_read = true
		if FileAccess.file_exists(DATA_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if parsed is Dictionary:
				_manifest = parsed
	return _manifest


## The strike of `data` (a step or charge, by its `id`) of the shape `short`; "" when it has none.
static func strike_for(short: String, data: Dictionary) -> String:
	var table: Variant = STRIKES.get(short, {})
	if not table is Dictionary:
		return ""
	return str((table as Dictionary).get(str(data.get("id", "")), ""))


## `<strike>-<direction>`: the strike animation's name in ANIMATION_LIBRARY.
static func animation_name(strike: String, direction: String) -> String:
	return "%s-%s" % [strike, direction]


## `<strike>-<direction>-hold`: the name in ANIMATION_LIBRARY of the strike animation's first frame, held (the
## charge ring's pose before a charge that plays the strike).
static func hold_name(strike: String, direction: String) -> String:
	return animation_name(strike, direction) + HOLD_SUFFIX


## The strike's own block (`texture`, `weapon`, `shaft_px`, its directions); {} when
## unknown.
static func strike_entry(strike: String) -> Dictionary:
	var strikes: Variant = manifest().get("strikes", {})
	if not strikes is Dictionary:
		return {}
	var entry: Variant = (strikes as Dictionary).get(strike, {})
	return entry if entry is Dictionary else {}


## The strip of `strike` in `direction` (`row`, `flip`, `aim`, `frames`, ...); {} when the manifest has none.
static func strip(strike: String, direction: String) -> Dictionary:
	var entry: Variant = strike_entry(strike).get(direction, {})
	return entry if entry is Dictionary else {}


## The sheet row the strip shows (a mirrored strip: its source's row); -1 when it has none.
static func row(strike: String, direction: String) -> int:
	return int(ShapeDefs.num(strip(strike, direction), "row", -1.0))


## Frame `number` (1-6) of the strip (a strip without `frames` of its own reads its `source` strike's
## in the same direction); {} when out of range.
static func frame(strike: String, direction: String, number: int) -> Dictionary:
	var spec := strip(strike, direction)
	var frames: Variant = spec.get("frames")
	if not frames is Array and spec.has("source"):
		frames = strip(str(spec["source"]), direction).get("frames")
	if not frames is Array or number < 1 or number > (frames as Array).size():
		return {}
	var entry: Variant = (frames as Array)[number - 1]
	return entry if entry is Dictionary else {}


## The game-px width of the spear's shaft the neck was baked to (the jab 5, the finisher 6).
static func shaft_px(strike: String) -> float:
	return ShapeDefs.num(strike_entry(strike), "shaft_px")


## The painted knob's chord on frame `number` (game px, `knob_w`): the code neck's root width.
static func knob_w(strike: String, direction: String, number: int) -> float:
	return ShapeDefs.num(frame(strike, direction, number), KNOB_W)


## True when the manifest has what a strike of `strike` in `direction` draws: its row, and for the Axe
## and the Hammer their weapon block and the neck (the Spear's spear has its own art).
static func is_complete(strike: String, direction: String) -> bool:
	if row(strike, direction) < 0:
		return false
	var weapon_name := str(strike_entry(strike).get("weapon", ""))
	if weapon_name.is_empty() or weapon_name == "spear":
		return true
	return not weapon_block(weapon_name).is_empty() and not neck().is_empty()


## The weapon block `name` ("axe", "hammer": texture, scale, head_start, axis_row, handle_px,
## handle_across, hidden_px, tint_gain, views); {} without one.
static func weapon_block(name: String) -> Dictionary:
	var weapons: Variant = manifest().get("weapons", {})
	if name.is_empty() or not weapons is Dictionary:
		return {}
	var block: Variant = (weapons as Dictionary).get(name, {})
	return block if block is Dictionary else {}


## The code neck (`neck`: texture, root_x, tip_x, arm_from_x, arm_to_x, axis_row, width_px); {}
## without one.
static func neck() -> Dictionary:
	var block: Variant = manifest().get("neck", {})
	return block if block is Dictionary else {}


## The frame `number` (1-4) of the weapon view `view` ("toward", "away") of the weapon `weapon_name`
## (`weapons.<name>.views.<view>`): {"texture" (its path), "scale" (game px per texture px), "rect"
## (Rect2), "pivot", "head" (texture px), "dir" (degrees)}; {} when the manifest has none.
static func view_frame_of(weapon_name: String, view: String, number: int) -> Dictionary:
	var views: Variant = weapon_block(weapon_name).get("views", {})
	var block: Variant = (views as Dictionary).get(view, {}) if views is Dictionary else {}
	if not block is Dictionary:
		return {}
	var frames: Variant = (block as Dictionary).get("frames", [])
	if not frames is Array or number < 1 or number > (frames as Array).size() or not (frames as Array)[number - 1] is Dictionary:
		return {}
	var entry: Dictionary = (frames as Array)[number - 1]
	var rect: Variant = entry.get("rect")
	var pivot := _vec(entry.get("pivot"))
	if not rect is Array or (rect as Array).size() < 4 or not pivot.is_finite():
		return {}
	var head := _vec(entry.get("head"))
	return {
		"texture": str((block as Dictionary).get("texture", "")),
		"scale": ShapeDefs.num(block, "scale"),
		"rect": Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])),
		"pivot": pivot,
		"head": head if head.is_finite() else pivot,
		"dir": ShapeDefs.num(entry, "dir"),
	}


## A copy of `data` (a step's numbers) hitting with `hit_reach` (a strike animation's, in its
## direction): an arc's `radius` (the Axe), a circle's `offset` (the Hammer), a line's `reach` (the
## Spear); `data` itself for none (hit_reach <= 0).
static func apply_hit_reach(data: Dictionary, hit_reach: float) -> Dictionary:
	if hit_reach <= 0.0:
		return data
	var out := data.duplicate()
	match ShapeDefs.area_kind(data):
		ShapeDefs.AREA_LINE:
			out["reach"] = hit_reach
		ShapeDefs.AREA_ARC:
			out["radius"] = hit_reach
		ShapeDefs.AREA_CIRCLE:
			out["offset"] = hit_reach
	return out


## True when the Visual shows the strip flipped: a left side strike (`mirrored`) mirrors it, and a mirrored strip
## (`strip_flipped`: the direction's flip_h in its StrikeAnimation) mirrors it again.
static func shown_flipped(strip_flipped: bool, mirrored: bool) -> bool:
	return mirrored != strip_flipped


## A cell-px point of a frame (`SOCKET`, or another point the manifest gives a frame); Vector2.INF when absent.
static func cell_point(frame_entry: Dictionary, key: String) -> Vector2:
	return _vec(frame_entry.get(key))


## Frame `number`'s socket in game px from the slime's centre (the player Visual's origin at rest),
## its x negated for a mirrored (left) strike; Vector2.INF when absent.
static func socket_game(strike: String, direction: String, number: int, mirrored: bool) -> Vector2:
	var at := _vec(frame(strike, direction, number).get("socket_game"))
	if mirrored and at.is_finite():
		at.x = -at.x
	return at


## The sheet `strike` shows (its own `texture`, else the manifest's: the Spear's); without a strike,
## the manifest's.
static func texture_path(strike: String = "") -> String:
	if not strike.is_empty():
		var own := str(strike_entry(strike).get("texture", ""))
		if not own.is_empty():
			return own
	return str(manifest().get("texture", ""))


## The cell px drawn at the player Visual's origin (the cell's centre: the Visual's offset is -origin).
static func origin() -> Vector2:
	var at := _vec(manifest().get("origin"))
	return at if at.is_finite() else Vector2.ZERO


## The spear's tint (`spear.tint_gain`); white when absent.
static func tint_gain() -> Color:
	var spear: Variant = manifest().get("spear", {})
	return gain_of(spear if spear is Dictionary else {})


## A block's per-channel `tint_gain` (toward the body's jelly); white when absent.
static func gain_of(block: Dictionary) -> Color:
	var gain: Variant = block.get("tint_gain")
	if gain is Array and (gain as Array).size() >= 3:
		return Color(float(gain[0]), float(gain[1]), float(gain[2]))
	return Color.WHITE


## True when `visual` shows a frame of `strike`'s strip in `direction`: its texture is the strike's
## sheet and its frame on the strip's row (whatever its flip).
static func shows_strip(visual: Sprite2D, strike: String, direction: String) -> bool:
	if visual == null or visual.texture == null:
		return false
	var path := texture_path(strike)
	var at_row := row(strike, direction)
	if path.is_empty() or at_row < 0 or visual.texture.resource_path != path:
		return false
	@warning_ignore("integer_division")
	return visual.frame / maxi(1, visual.hframes) == at_row


## The frame (1-6) `visual` shows of `strike`'s strip in `direction`, seen `flipped`; 0 when it shows
## anything else.
static func shown_frame(visual: Sprite2D, strike: String, direction: String, flipped: bool) -> int:
	if not shows_strip(visual, strike, direction) or visual.flip_h != flipped:
		return 0
	return visual.frame % maxi(1, visual.hframes) + 1


static func _vec(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.INF
