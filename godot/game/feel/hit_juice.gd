extends RefCounted
## Builds the feel spec `GameFeel.play_hit` takes for one swing (combat-feel plan section 6 "Juice";
## BODY_SHAPES.md "Juice"): the hit-stop once per swing (+`combat.chain.hitStop.extraTargetMs` per
## extra target up to `extraTargetCapMs`, +`killMs` on a kill, capped at `capMs`), the trauma, the
## kick, the sparks, the impact pitch and the damage number, from the step's numbers
## (`shapes.<name>.chain[i]`, a charge, or an ability's block such as `abilities.squashSlam.feel` or
## `gulp.throwHit`: the same camelCase keys), the hit and the reactions it got.
##
## Spec keys: "hit_stop_ms", "trauma", "kick_px", "sparks" (count), "spark_preset", "tint" (Color,
## the sparks' material tint; WHITE = none), "pitch", "sound_cue", "number" (int, 0 = none),
## "number_big" (bool), and the juice module's extras: "flash_big" (the long white-then-tint flash),
## "impact_ring" (bool, the finisher's ring), "debris_preset" (StringName, &"" = none),
## "debris_tint" (Color), "debris_scale" (count scale), "dust" (bool, the Hammer's ground dust),
## "material_cue" (the victim's material sound) and "thump_cue" (the finisher's low thump). The two
## extra cues are names the global audio scene does not have yet: they stay silent until the sound
## work adds them (combat-feel plan section 6 "Needs drawn art or sound").
##
## A reaction's `feel` (EnemyReactions, `result.reaction.feel`) merges over the spec; the victim's
## material (goo, worm, chitin, mud, stone, silk, straw, wood: the feel's "material" key, else the
## reaction's own "material", which EnemyReactions writes on every answer) is expanded through
## MATERIAL_FEEL into the tint, the debris and the material cue first.
##
## Dev switches (combat-feel plan section 9 item 6, rework mode only): every juice layer in LAYERS can
## be turned off and on to compare; `layer_on(layer)` answers true for every layer while the mode is
## off. On the small juice panel (game/feel/juice_dev_panel.gd, PANEL_KEY shows it), which GameFeel
## makes in the rework mode, LAYER_KEYS[i] plays LAYERS[i] once so it can be seen (the real finisher
## value, then shown 4x: game/feel/juice_demo.gd) and Shift + LAYER_KEYS[i] switches it.
##
## Owner: juice.

const Services := preload("res://game/shared/services.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")

## The ParticleFx presets of the sparks: taps, and the big classes (`combat.damageNumbers.bigClasses`:
## finishers, the Hammer, charges, the Slam), plus the finisher's impact ring.
const DEFAULT_SPARK_PRESET := &"hit-spark"
const BIG_SPARK_PRESET := &"finisher-spark"
const IMPACT_RING_PRESET := &"impact-ring"
## Sounds (global audio cues). The spec's "sound_cue" is the step's or block's "soundCue", else ""
## (the sender picks its impact: IMPACT_CUE stands in for the shape impact takes until they are
## baked); GameFeel plays it at the spec's "pitch". THUMP_CUE (the finisher's 60-90 Hz thump) does
## not exist yet and stays silent until it does.
const IMPACT_CUE := &"HitDull"
const CLINK_CUE := &"HitBlocked"
const THUMP_CUE := &"FinisherThump"
## The clink (combat-feel plan section 6 "Special moments"): a few sparks at the tip and a dry high
## tick. Its hit-stop is `combat.chain.clink.hitStopMs`.
const CLINK_SPARKS := 3
const CLINK_PITCH := 1.5
## Each impact's pitch varies by +-this share (combat-feel plan section 6 "Sound": +-3 %); GameFeel
## passes it in place of the cue's own randomness, so the climb 1.0 / 1.12 / 1.26 stays clear.
const PITCH_VARIANCE := 0.03
## A tap's debris burst is this share of the big classes' (materials with "tap_debris").
const TAP_DEBRIS_SCALE := 0.5

## The victim's material (enemy-types.json `reactions.material`) -> its sparks' tint, its debris and
## its sound (presentation; combat-feel plan section 6 "Sparks ... tinted by material", "By weight
## class"). "tap_debris": the debris also shows on taps, at TAP_DEBRIS_SCALE (the Clod's mud chips).
## Goo (the jelly enemies, the slime itself in the juice demo) splats: ParticleFx's painted
## "goo-splat-sheet" flipbook (256x256-tile_4x1-goo-splat.webp with a few goo-splat drops), on taps
## too, its size following the debris scale (small on taps, bigger on finishers, smashes and charges).
const GOO_SPLAT_PRESET := &"goo-splat-sheet"
const MATERIAL_FEEL := {
	"goo": {"tint": Color("#b6f5c0"), "debris_preset": GOO_SPLAT_PRESET, "debris_tint": Color.WHITE,
		"material_cue": &"MaterialGoo", "tap_debris": true},
	"worm": {"tint": Color("#ffd0c4"), "debris_preset": &"goo-splat", "debris_tint": Color("#e08a8a"),
		"material_cue": &"MaterialWorm", "tap_debris": false},
	"chitin": {"tint": Color("#eadcff"), "debris_preset": &"stone-chip", "debris_tint": Color("#6b557d"),
		"material_cue": &"MaterialChitin", "tap_debris": false},
	"mud": {"tint": Color("#ead2a8"), "debris_preset": &"mud-chunk", "debris_tint": Color.WHITE,
		"material_cue": &"MaterialMud", "tap_debris": true},
	"stone": {"tint": Color("#e3e7ee"), "debris_preset": &"stone-chip", "debris_tint": Color.WHITE,
		"material_cue": &"MaterialStone", "tap_debris": true},
	"silk": {"tint": Color.WHITE, "debris_preset": &"silk-tuft", "debris_tint": Color.WHITE,
		"material_cue": &"MaterialSilk", "tap_debris": true},
	"straw": {"tint": Color("#fff0b0"), "debris_preset": &"silk-tuft", "debris_tint": Color("#e8d27a"),
		"material_cue": &"", "tap_debris": true},
	# The training dummy's (ReactionProfile.DUMMY_MATERIAL): splinters and straw.
	"wood": {"tint": Color("#f1d9a8"), "debris_preset": &"stone-chip", "debris_tint": Color("#a0743f"),
		"material_cue": &"", "tap_debris": true},
}

## The juice layers the dev switches turn off and on (combat-feel plan section 9 item 6).
const LAYER_FREEZE := &"freeze"
const LAYER_FLASH := &"flash"
const LAYER_SQUASH := &"squash"
const LAYER_JITTER := &"jitter"
const LAYER_TRAUMA := &"trauma"
const LAYER_KICK := &"kick"
const LAYER_SPARKS := &"sparks"
const LAYER_PITCH := &"pitch"
const LAYER_NUMBERS := &"numbers"
const LAYER_SLOWMO := &"slowmo"
const LAYERS: Array[StringName] = [LAYER_FREEZE, LAYER_FLASH, LAYER_SQUASH, LAYER_JITTER, LAYER_TRAUMA,
	LAYER_KICK, LAYER_SPARKS, LAYER_PITCH, LAYER_NUMBERS, LAYER_SLOWMO]
## Dev keys (rework mode only; checked free on 2026-10-11: F2 is the control scheme, F3 the FPS panel,
## F7/F8 the sound audition, shift+F10 the chest menu, and the rework input layer frees the number
## keys): PANEL_KEY shows or hides the juice panel; while it shows, LAYER_KEYS[i] plays LAYERS[i]'s
## demo and Shift + LAYER_KEYS[i] switches it.
const PANEL_KEY := KEY_F9
const LAYER_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]

## The layers switched off (layer -> true); kept for the session only.
static var _off: Dictionary = {}


## The spec of one swing: `step` the step's numbers (camelCase as in game-constants.json), `hit` the
## hit it sent, `reactions` the `result.reaction` of each target it hit, `damage` the largest damage
## dealt, `targets` how many it hit, `killed` whether one died. A sender that wants no feel for a
## swing that hit nothing uses `whiff_spec` (an ability's landing may still want its own).
static func swing_spec(step: Dictionary, hit: Dictionary, reactions: Array[Dictionary], damage: int,
		targets: int, killed: bool) -> Dictionary:
	var big := is_big(hit)
	var spec := {
		"hit_stop_ms": hit_stop_ms(float(step.get("hitStopMs", 0.0)), targets, killed),
		"trauma": float(step.get("trauma", 0.0)),
		"kick_px": float(step.get("kickPx", 0.0)),
		"sparks": int(step.get("sparks", 0)),
		"spark_preset": BIG_SPARK_PRESET if big else DEFAULT_SPARK_PRESET,
		"tint": Color.WHITE,
		"pitch": float(step.get("pitch", 1.0)),
		"sound_cue": StringName(str(step.get("soundCue", ""))),
		"flash_big": big,
		"impact_ring": bool(step.get("impactRing", false)),
		"debris_preset": &"",
		"debris_tint": Color.WHITE,
		"debris_scale": 1.0,
		"dust": bool(step.get("debris", false)),
		"material_cue": &"",
		"thump_cue": THUMP_CUE if bool(step.get("thump", false)) else &"",
	}
	spec.merge(number_spec(damage, hit), true)
	for reaction: Dictionary in reactions:
		var feel: Variant = reaction.get("feel", {})
		var feel_dict: Dictionary = feel if feel is Dictionary else {}
		var material := str(feel_dict.get("material", reaction.get("material", "")))
		if not material.is_empty():
			spec.merge(material_spec(material, big), true)
		var rest := feel_dict.duplicate()
		rest.erase("material")
		spec.merge(rest, true)
	return spec


## The feel of `material` (MATERIAL_FEEL) as spec keys: the sparks' tint, the debris (on taps only
## for materials with "tap_debris", then at TAP_DEBRIS_SCALE) and the material cue. {} for an
## unknown material.
static func material_spec(material: String, big: bool) -> Dictionary:
	if not MATERIAL_FEEL.has(material):
		return {}
	var entry: Dictionary = MATERIAL_FEEL[material]
	var debris := StringName(entry["debris_preset"]) if big or bool(entry["tap_debris"]) else &""
	return {
		"tint": entry["tint"],
		"debris_preset": debris,
		"debris_tint": entry["debris_tint"],
		"debris_scale": 1.0 if big else TAP_DEBRIS_SCALE,
		"material_cue": entry["material_cue"],
	}


## `spec` with every effect off (a swing that hit nothing).
static func whiff_spec(spec: Dictionary) -> Dictionary:
	var quiet := spec.duplicate()
	quiet.merge({"hit_stop_ms": 0.0, "trauma": 0.0, "kick_px": 0.0, "sparks": 0, "sound_cue": &"",
		"impact_ring": false, "debris_preset": &"", "dust": false, "material_cue": &"", "thump_cue": &"",
		"number": 0, "number_big": false}, true)
	return quiet


## The clink's spec (a wrong tool or a shut weak point; combat-feel plan section 6 "Special
## moments"): `combat.chain.clink.hitStopMs`, a few white sparks at the tip and the high tick, no
## number, no camera. The sender adds the slime's recoil (`combat.chain.clink.recoilPx`).
static func clink_spec() -> Dictionary:
	return {
		"hit_stop_ms": _number("combat.chain.clink.hitStopMs"),
		"trauma": 0.0,
		"kick_px": 0.0,
		"sparks": CLINK_SPARKS,
		"spark_preset": DEFAULT_SPARK_PRESET,
		"tint": Color.WHITE,
		"pitch": CLINK_PITCH,
		"sound_cue": CLINK_CUE,
		"number": 0,
		"number_big": false,
		"flash_big": false,
	}


## The per-swing hit-stop: `base_ms` + the extra targets' share (capped) + the kill bonus, all capped
## at `combat.chain.hitStop.capMs`.
static func hit_stop_ms(base_ms: float, targets: int, killed: bool) -> float:
	if base_ms <= 0.0:
		return 0.0
	var extra := minf(_number("combat.chain.hitStop.extraTargetCapMs"),
		_number("combat.chain.hitStop.extraTargetMs") * float(maxi(0, targets - 1)))
	var kill := _number("combat.chain.hitStop.killMs") if killed else 0.0
	return minf(_number("combat.chain.hitStop.capMs"), base_ms + extra + kill)


## {"number": damage, "number_big": the hit's class is in `combat.damageNumbers.bigClasses`}.
static func number_spec(damage: int, hit: Dictionary) -> Dictionary:
	return {"number": maxi(0, damage), "number_big": is_big(hit)}


## True when `hit`'s class is one of `combat.damageNumbers.bigClasses` (finisher, smash, charge,
## slam): the big number, the long flash and the finisher sparks.
static func is_big(hit: Dictionary) -> bool:
	var constants := Services.constants()
	var big_classes: Variant = constants.value("combat.damageNumbers.bigClasses", []) if constants != null else []
	return big_classes is Array and (big_classes as Array).has(str(hit.get("class", "")))


# --- dev switches (rework mode only) ------------------------------------------------------------

## False only while the rework mode is on and `layer` was switched off.
static func layer_on(layer: StringName) -> bool:
	return not (ReworkMode.is_on() and _off.has(layer))


## Switches `layer` (one of LAYERS) on or off.
static func set_layer_on(layer: StringName, on: bool) -> void:
	if not LAYERS.has(layer):
		return
	if on:
		_off.erase(layer)
	else:
		_off[layer] = true


## Flips `layer`; returns whether it is on now.
static func toggle_layer(layer: StringName) -> bool:
	set_layer_on(layer, _off.has(layer))
	return not _off.has(layer)


## Every layer back on.
static func reset_layers() -> void:
	_off.clear()


## The layer a dev key plays or (with Shift) switches (LAYER_KEYS), or &"" for another key.
static func layer_for_key(keycode: Key) -> StringName:
	var index := LAYER_KEYS.find(keycode)
	return LAYERS[index] if index >= 0 and index < LAYERS.size() else &""


## The dev key of `layer` (LAYER_KEYS), or KEY_NONE for another name.
static func key_for_layer(layer: StringName) -> Key:
	var index := LAYERS.find(layer)
	return LAYER_KEYS[index] if index >= 0 and index < LAYER_KEYS.size() else KEY_NONE


static func _number(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0
