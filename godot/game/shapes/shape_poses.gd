extends RefCounted
## What the slime's art shows through a body-shape strike (BODY_SHAPES.md "Shapes"): its strike animation,
## or for the War Axe's Spin, the one charge without one, the slime's drawn key poses: page 6 of the
## slime-v2 sheet (asset/Originals/characters/slime-v2/shapes/README.md), with no weapon drawn on the body
## (ShapeVisuals draws the axe), built into the player scene as single held frames named
## `shape-<shape>-<pose>-<down|up|side>` by tools/build_player_clips.gd, which builds only the poses
## TIMELINES and `ring_clip` show.
##
## The strike animations (owner, 2026-10-12, rounds 3 to 5; game/shapes/strike_rig.gd, StrikeLibrary;
## BODY_SHAPES.md "Editing the strike animations"): every chain step and charge but the Spin. The Spear's
## jabs play `strikes/spear-jab-<direction>`, its lunging jab and Lunge `strikes/spear-finisher-...`; the Axe's
## sweep, backswing and chop and the Hammer's Thud, BOOM and Quake their own. Each keys the Visual's body frame
## (the player's `strikes` library, built at run time from the strike's resource: StrikeLibrary.build_library)
## and hands the StrikeRig the resource, its direction and the clock. `advance` seeks the animation every
## physics step at the step's elapsed gameplay time mapped to the strike's 0-3 time (StrikeLibrary.unit_at: the
## wind-up onto 0..1, the active window onto 1..2, the recovery onto 2..3), so the art and the hit cannot drift
## and a hit-stop freezes both. A strike plays its animation only when the player has it and the manifest has
## what it draws (`strike_frames_for`); without it (a strike file missing) the controller plays the stand-in
## `attack-1`. The strike sheets' cells are larger than the pages': the animations key the Visual's offset to
## the sheets' origin, and the player mirrors a `-side` one for a left facing; each step also pins both
## (`_pin_strike_art`): the offset, and the flip of a left side strike or a mirrored strip (the backswing's
## front and back show the sweep's frames flipped), so the art keeps its hit's mirror whatever turns the slime
## mid-strike. The frames are drawn at one scale (the approved look: no size pop), so no code squash plays on
## them (`squash_share` STRIKE_SQUASH_SHARE; the shape controller skips its strike squash).
##
## The Spin's pose timeline (TIMELINES, by the shape's short name and the charge's `id`): entries
## [from, pose] in order, where `from` is the start, the contact frame (the end of the wind-up: the first
## active frame) or the recovery (the end of the active window); the last entry reached shows. `load`
## through its wind-up, then `swing-down` and `swing-up` in turn, once per quarter turn of the axe through
## its active window (SPIN_SWAPS), then `swing-down` in its recovery. The Roll's ball clip is not reused for
## the Spin: the ball rolls about a level axis and reads as rolling away, while the axe sweeps round the
## standing slime; the twisting swing poses keep its face and match the drawn head. Its charge ring fills,
## and waits full, in the Axe's `load` pose (`ring_clip`); a charge that plays a strike (the Spear's Lunge,
## the Hammer's Quake) holds its strike's first frame instead (ShapeController.held_pose_clip: the strike's
## hold, StrikeLibrary).
##
## Direction: a strike follows its aim with the player's own 3-way rule (PlayerScript._directional_clip): a
## mostly vertical aim picks down or up, any other side (an exact diagonal always side, whatever its float
## rounding: `direction_of`). A side pose faces right and the player mirrors it for left (flip_h follows the
## facing the strike set, ShapeController._set_aim), so the pose matches the drawn axe. The ring's pose is a
## base clip the player turns to the slime's facing, since the slime walks while the ring fills.
##
## The shape controller owns one (`setup(player)`), starts it with each step or charge (`begin`),
## advances it while the strike runs (`advance`: at its contact frame, before a hit-stop freezes it,
## and every physics step for the recovery and the Spin's swaps) and ends it when the strike ends or
## is cancelled (`finish`). Poses play through the player's animation API (PlayerScript.play_animation,
## forced). Nothing is played on an end or a cancel: once the controller is idle the player's state
## machine plays idle or walk again on the same physics step, and a cancel's own clip (the Roll's, the
## knockback's) keeps the art. Presentation only: nothing here hits, moves or times a strike.
##
## Owner: shapes.

const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ShapeStrikes := preload("res://game/shapes/shape_strikes.gd")
const StrikeLibrary := preload("res://game/shapes/strike_library.gd")
const PlayerScript := preload("res://game/scripts/player.gd")

## Pose clips are `<CLIP_PREFIX><shape>-<pose>-<direction>` (tools/build_player_clips.gd).
const CLIP_PREFIX := "shape-"
const DOWN := "down"
const UP := "up"
const SIDE := "side"
## Where a timeline entry starts: the step's start, its contact frame, its recovery.
const FROM_START := "start"
const FROM_CONTACT := "contact"
const FROM_RECOVERY := "recovery"
## The pose a charge ring fills in (`ring_clip`: the Axe's, before the Spin), and the Spin's wind-up.
const POSE_LOAD := "load"
## A timeline pose that alternates SPIN_POSES (the War Axe's Spin), SPIN_SWAPS times over the active
## window: once per quarter turn of the drawn axe.
const POSE_SPIN := "spin"
const SPIN_POSES: Array[String] = ["swing-down", "swing-up"]
const SPIN_SWAPS := 4
## The share of the code-driven anticipation squash (ShapeVisuals.art_pose scale) kept on the strike
## frames: none (each strip keeps one scale; the pull-back offset and the hop stay whole).
const STRIKE_SQUASH_SHARE := 0.0
## How much the vertical part of an aim must beat the horizontal for a down or up pose, so the four
## exact diagonals all pick side (`direction_of`).
const DIAGONAL_EPSILON := 0.001

## Shape short name -> charge `id` -> [[from, pose], ...] (see the header): the Spin's, the one strike with
## no strike animation.
const TIMELINES := {
	"axe": {
		"spin": [[FROM_START, POSE_LOAD], [FROM_CONTACT, POSE_SPIN], [FROM_RECOVERY, "swing-down"]],
	},
}

var _player: PlayerScript
## The running strike: its shape's short name, its numbers, its timeline and its pose direction.
var _shape: String = ""
var _data: Dictionary = {}
var _timeline: Array = []
var _direction: String = ""
## The pose clip or strike animation on the slime's art now ("" while none shows).
var _shown: String = ""
## The running strike's strike frames (ShapeStrikes: "" while it shows drawn poses) and whether its
## side frames are mirrored (a left strike).
var _strike: String = ""
var _mirrored: bool = false


func setup(player: PlayerScript) -> void:
	_player = player


## Starts the frames of `data` (a chain step or a charge of `shape_id`) aimed along `aim` (the hit's
## aim) and shows its first one: its strike frames when the player has them (`strike_frames_for`),
## else its drawn poses (the Spin's). True when it shows either (for poses: a timeline, and the clip on
## the player); false leaves the clip to the caller (the stand-in).
func begin(shape_id: StringName, data: Dictionary, aim: Vector2) -> bool:
	finish()
	if not _player_valid():
		return false
	var short := ShapeDefs.short_name(shape_id)
	var strike := strike_frames_for(shape_id, data, aim)
	if not strike.is_empty():
		_shape = short
		_data = data
		_strike = strike
		_direction = direction_of(aim)
		_mirrored = mirrors(aim)
		advance(0.0)
		return true
	var timeline := timeline_of(short, data)
	if timeline.is_empty():
		return false
	var direction := direction_of(aim)
	var first := pose_at(short, data, 0.0)
	if first.is_empty() or not _has_clip(clip_name(short, first, direction)):
		return false
	_shape = short
	_data = data
	_timeline = timeline
	_direction = direction
	advance(0.0)
	return true


## The pose of the running strike `elapsed` ms after its start, played when it changes (the player
## may refuse it while a knockback has priority: it is asked again on the next call). A strike
## animation is sought there on every call instead (its time mapped by its markers), its placement
## pinned (`_pin_strike_art`) and the rig given the clock.
func advance(elapsed: float) -> void:
	if not _player_valid():
		return
	if not _strike.is_empty():
		var animation_name := ShapeStrikes.animation_name(_strike, _direction)
		var timing := Vector3(ShapeDefs.num(_data, "windupMs"), ShapeDefs.num(_data, "activeMs"),
			ShapeDefs.num(_data, "recoveryMs"))
		if _player.seek_strike_animation(animation_name, StrikeLibrary.unit_at(elapsed, timing)):
			_shown = animation_name
		_pin_strike_art()
		var rig := _player.get_strike_rig()
		if rig != null:
			rig.set(&"animation", StrikeLibrary.animation(_strike))
			rig.set(&"direction", _direction)
			rig.set(&"clock_ms", elapsed)
			rig.set(&"timing", timing)
		return
	if _timeline.is_empty():
		return
	var pose := pose_at(_shape, _data, elapsed)
	if pose.is_empty():
		return
	var clip := clip_name(_shape, pose, _direction)
	if clip == _shown:
		return
	if _player.play_animation(clip, true):
		_shown = clip


## The strike ended or was cancelled: its poses are forgotten. Nothing is played (see the header);
## the rig stops drawing once the player plays another clip.
func finish() -> void:
	if not _strike.is_empty() and _player_valid():
		var rig := _player.get_strike_rig()
		if rig != null:
			rig.set(&"clock_ms", -1.0)
	_shape = ""
	_data = {}
	_timeline = []
	_direction = ""
	_shown = ""
	_strike = ""
	_mirrored = false


## The running strike's strike frames ("" while it shows drawn poses or nothing).
func strike_id() -> String:
	return _strike


## The strike `data` (a step or charge of `shape_id`) would show toward `aim` (ShapeStrikes.strike_for),
## when the manifest has its strip in the aim's direction with what it draws (ShapeStrikes.is_complete)
## and the player has its animation (`strikes/<strike>-<direction>`); "" otherwise (the Spin's drawn poses,
## or the stand-in).
func strike_frames_for(shape_id: StringName, data: Dictionary, aim: Vector2) -> String:
	if not _player_valid():
		return ""
	var strike := ShapeStrikes.strike_for(ShapeDefs.short_name(shape_id), data)
	if strike.is_empty():
		return ""
	var direction := direction_of(aim)
	if ShapeStrikes.strip(strike, direction).is_empty() or not ShapeStrikes.is_complete(strike, direction):
		return ""
	if _player.strike_animation(ShapeStrikes.animation_name(strike, direction)) == null or StrikeLibrary.animation(strike) == null:
		return ""
	return strike


## The share of the code-driven anticipation squash to keep now: STRIKE_SQUASH_SHARE through a strike
## on its strike frames, else all of it.
func squash_share() -> float:
	return STRIKE_SQUASH_SHARE if shows_strike_frames() else 1.0


## True while the running strike shows its strike frames (ShapeStrikes), not drawn poses.
func shows_strike_frames() -> bool:
	return not _strike.is_empty()


## The timeline of `data` (a step or charge, by its `id`) of the shape `short`; [] when it has none.
static func timeline_of(short: String, data: Dictionary) -> Array:
	var table: Variant = TIMELINES.get(short, {})
	if not table is Dictionary:
		return []
	var timeline: Variant = (table as Dictionary).get(str(data.get("id", "")), [])
	return timeline if timeline is Array else []


## The pose of `data` of the shape `short` at `elapsed` ms after its start ("" when it has none): the
## last timeline entry reached; the Spin's entry alternates SPIN_POSES.
static func pose_at(short: String, data: Dictionary, elapsed: float) -> String:
	var pose := ""
	var pose_from := 0.0
	for entry: Variant in timeline_of(short, data):
		if not entry is Array or (entry as Array).size() < 2:
			continue
		var from := _from_ms(data, str((entry as Array)[0]))
		if elapsed < from:
			break
		pose = str((entry as Array)[1])
		pose_from = from
	if pose != POSE_SPIN:
		return pose
	var active := ShapeDefs.num(data, "activeMs")
	if active <= 0.0:
		return SPIN_POSES[0]
	var swap := int(floorf((elapsed - pose_from) / (active / float(SPIN_SWAPS))))
	return SPIN_POSES[posmod(swap, SPIN_POSES.size())]


## The pose direction of a strike along `aim`, by the player's 3-way rule: "down" or "up" when the aim
## is mostly vertical, else "side" (mirrored for left by the player's flip). An exact diagonal (the
## Axe's and the Hammer's 8-way snap, whose two parts differ only by float rounding) is side
## whichever way it points (DIAGONAL_EPSILON).
static func direction_of(aim: Vector2) -> String:
	if absf(aim.y) > absf(aim.x) + DIAGONAL_EPSILON:
		return DOWN if aim.y > 0.0 else UP
	return SIDE


## True when a strike along `aim` shows its side art mirrored (a side strike to the left).
static func mirrors(aim: Vector2) -> bool:
	return direction_of(aim) == SIDE and aim.x < 0.0


## `shape-<shape>-<pose>-<direction>`.
static func clip_name(short: String, pose: String, direction: String) -> String:
	return "%s%s-%s-%s" % [CLIP_PREFIX, short, pose, direction]


## The base clip of the shape's charge ring pose (`shape-<shape>-load`, "" for an unknown shape): the
## player plays its `-down`, `-up` or `-side` version for the slime's facing. The player scene has the
## Axe's only (the other charges hold their strike's first frame: ShapeController.held_pose_clip).
static func ring_clip(shape_id: StringName) -> String:
	var short := ShapeDefs.short_name(shape_id)
	if short.is_empty():
		return ""
	return "%s%s-%s" % [CLIP_PREFIX, short, POSE_LOAD]


## When a timeline entry starts, in ms after the strike's start.
static func _from_ms(data: Dictionary, from: String) -> float:
	match from:
		FROM_CONTACT:
			return ShapeDefs.contact_start_ms(data)
		FROM_RECOVERY:
			return ShapeDefs.num(data, "windupMs") + ShapeDefs.num(data, "activeMs")
	return 0.0


func _has_clip(clip: String) -> bool:
	return _player.clip_length_ms_of(clip) > 0.0


## While the slime shows a frame of the running strike's strip: the Visual's offset at the sheets'
## origin (their cells are larger than the pages'; the animations key it too, and the next clip the
## player plays puts the rest offset back) and its mirror (ShapeStrikes.shown_flipped: a left side
## strike's, a mirrored strip's; the player's `_flip_for` mirrors a `-side` animation for a left facing
## and never a `-down` or `-up` one; this keeps the art on its hit's side if the facing turns mid-strike).
func _pin_strike_art() -> void:
	var visual := _player.get_visual()
	if visual == null or _shown.is_empty() or not ShapeStrikes.shows_strip(visual, _strike, _direction):
		return
	var offset := -ShapeStrikes.origin()
	if visual.centered and visual.texture != null:
		offset += visual.texture.get_size() / Vector2(maxi(1, visual.hframes), maxi(1, visual.vframes)) * 0.5
	if visual.offset != offset:
		visual.offset = offset
	var flipped := ShapeStrikes.shown_flipped(StrikeLibrary.flip_h(StrikeLibrary.animation(_strike), _direction), _mirrored)
	if visual.flip_h != flipped:
		visual.flip_h = flipped


func _player_valid() -> bool:
	return _player != null and is_instance_valid(_player)
