extends RefCounted
## The Gulp forms (abilities spec 11.1; redesigned 2026-10-08, GAME_GUIDELINES "Signature
## Mechanic: Gulp"). Swallowing an essence (`essence_item`, an items.json id) turns the slime into
## its form until a hit pops it out, another essence is swallowed or the slime spits it out; there
## is no timer. The ids keep the old form names (heavy, sticky, frog); the forms are Stone, Silk
## and Swim. The top-down art has no skins of its own, so a shader paints the form over the slime's
## frames (`skin`: form_skin.gdshader; owner decision 2026-10-05); `tint` is the fallback.
## `essence` is the short id the world's essences and the enemy drops use (game-constants
## `gulp.essenceDrops`); `color` tints an essence's glow and the held essence inside the slime.
## `transform_cue` is the global audio cue a form plays as it starts: one sound per form (owner,
## Sound Picker round 3).
##
## Owner: abilities.

const HEAVY := &"heavy"
const STICKY := &"sticky"
const FROG := &"frog"

const FORMS: Array[Dictionary] = [
	{"id": HEAVY, "name": "Stone", "essence": "stone", "essence_item": "stone-essence", "tint": Color("#9aa3ad"),
		"color": Color("#c9cfd6"), "skin": 1, "speed": 0.6, "knockback_immune": true, "presses_plates": true,
		"crosses_webs": false, "swims": false, "badge_frame": 0, "transform_cue": &"GulpTransformHeavy"},
	{"id": STICKY, "name": "Silk", "essence": "silk", "essence_item": "silk-essence", "tint": Color("#f1ecff"),
		"color": Color("#fbf6ff"), "skin": 2, "speed": 0.9, "knockback_immune": false, "presses_plates": false,
		"crosses_webs": true, "swims": false, "badge_frame": 1, "transform_cue": &"GulpTransformSticky"},
	{"id": FROG, "name": "Swim", "essence": "swim", "essence_item": "swim-essence", "tint": Color("#8fd14f"),
		"color": Color("#7fd6ff"), "skin": 3, "speed": 1.0, "knockback_immune": false, "presses_plates": false,
		"crosses_webs": false, "swims": true, "badge_frame": 2, "transform_cue": &"GulpTransformFrog"},
]


## The form an essence item (`stone-essence`) gives; {} when none.
static func for_item(item_id: String) -> Dictionary:
	for form in FORMS:
		if form["essence_item"] == item_id:
			return form
	return {}


## The form of a short essence id (`stone`); {} when none.
static func for_essence(essence: String) -> Dictionary:
	for form in FORMS:
		if form["essence"] == essence:
			return form
	return {}


static func by_id(id: StringName) -> Dictionary:
	for form in FORMS:
		if form["id"] == id:
			return form
	return {}
