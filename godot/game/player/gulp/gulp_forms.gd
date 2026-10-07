extends RefCounted
## The Gulp forms (Phaser `content/gulp/gulpForms.ts:35-64`; abilities spec 11.1). Eating a
## material turns the slime into its form for `gulp.formDurationMs` (60 s of simulation time).
## The form skins re-texture the old side-view sheet in Phaser; the top-down art has none, so the
## port paints the form over the slime's frames with a shader (`skin`: form_skin.gdshader; owner
## decision 2026-10-05); `tint` stays as Phaser's fallback when the shader is missing.
## The Frog form is the port's own (owner, 2026-10-06): gulping a frog lets the slime swim in deep
## water (`swims`; game/player/gulp/player_swimming.gd).
## `transform_cue` is the global audio cue a form plays as it starts or is refreshed: one sound per
## form (owner, Sound Picker round 3: the Heavy like rock, the Frog splashes and bubbles).
##
## Owner: abilities.

const HEAVY := &"heavy"
const STICKY := &"sticky"
const FROG := &"frog"

## Table order matters (preferred material, wheel order).
const FORMS: Array[Dictionary] = [
	{"id": HEAVY, "name": "Heavy", "material": "stone", "tint": Color("#9aa3ad"), "skin": 1, "speed": 0.6,
		"knockback_immune": true, "presses_plates": true, "crosses_webs": false, "swims": false, "badge_frame": 0,
		"transform_cue": &"GulpTransformHeavy"},
	{"id": STICKY, "name": "Sticky", "material": "silk-clump", "tint": Color("#f1ecff"), "skin": 2, "speed": 0.9,
		"knockback_immune": false, "presses_plates": false, "crosses_webs": true, "swims": false, "badge_frame": 1,
		"transform_cue": &"GulpTransformSticky"},
	{"id": FROG, "name": "Frog", "material": "frog", "tint": Color("#8fd14f"), "skin": 3, "speed": 1.0,
		"knockback_immune": false, "presses_plates": false, "crosses_webs": false, "swims": true, "badge_frame": 2,
		"transform_cue": &"GulpTransformFrog"},
]


## The form whose material `item_id` is; {} when none.
static func for_material(item_id: String) -> Dictionary:
	for form in FORMS:
		if form["material"] == item_id:
			return form
	return {}


static func by_id(id: StringName) -> Dictionary:
	for form in FORMS:
		if form["id"] == id:
			return form
	return {}
