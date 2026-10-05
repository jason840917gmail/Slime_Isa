extends RefCounted
## The Gulp forms (Phaser `content/gulp/gulpForms.ts:35-64`; abilities spec 11.1). Eating a
## material turns the slime into its form for `gulp.formDurationMs` (60 s of simulation time).
## The form skins re-texture the old side-view sheet in Phaser; the top-down art has none yet, so
## the port tints the slime (Phaser's fallback, owner item O-G1).
##
## Owner: abilities.

const HEAVY := &"heavy"
const STICKY := &"sticky"

## Table order matters (preferred material, wheel order).
const FORMS: Array[Dictionary] = [
	{"id": HEAVY, "name": "Heavy", "material": "stone", "tint": Color("#9aa3ad"), "speed": 0.6,
		"knockback_immune": true, "presses_plates": true, "crosses_webs": false, "badge_frame": 0},
	{"id": STICKY, "name": "Sticky", "material": "silk-clump", "tint": Color("#f1ecff"), "speed": 0.9,
		"knockback_immune": false, "presses_plates": false, "crosses_webs": true, "badge_frame": 1},
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
