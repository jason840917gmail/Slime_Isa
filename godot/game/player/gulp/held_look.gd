extends RefCounted
## The look of something the slime sucks in (owner, 2026-10-08/09): the same picture flies into the
## mouth, shows inside the full slime and flies out when it is thrown. A liftable is its frame of the
## liftables sheet (game/data/liftables.json, game/scripts/liftable.gd), an essence its frame of the
## essences sheet (both packed by scripts/props/pack-gulp-art.py). Every look is centred on its node
## and about `size_px` across.
##
## Owner: abilities.

const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")
const ESSENCES_SHEET := "res://asset/MAPS/items/128x128-tile_3x1-gulp-essences.webp"
const ESSENCES_CELL := 128.0
const LIFTABLES_CELL := 192.0


## A Node2D showing `held` ({"kind", "essence", "variant"?}).
static func make(held: Dictionary, size_px: float) -> Node2D:
	var sprite := Sprite2D.new()
	sprite.centered = true
	if str(held.get("kind", "")) == "essence":
		var form := GulpForms.for_essence(str(held.get("essence", "")))
		if ResourceLoader.exists(ESSENCES_SHEET):
			sprite.texture = load(ESSENCES_SHEET)
			sprite.hframes = 3
			sprite.frame = int(form.get("badge_frame", 0))
		sprite.scale = Vector2.ONE * (size_px / ESSENCES_CELL)
		return sprite
	var catalog := LiftableScript.catalog()
	var sheet := str(catalog.get("sheet", ""))
	var cell := float(catalog.get("cell", LIFTABLES_CELL))
	if not sheet.is_empty() and ResourceLoader.exists(sheet):
		sprite.texture = load(sheet)
		sprite.hframes = int(catalog.get("columns", 8))
		sprite.vframes = int(catalog.get("rows", 9))
		sprite.frame = LiftableScript.frame_of(str(held.get("kind", LiftableScript.DEFAULT_KIND)), int(held.get("variant", 0)))
	sprite.scale = Vector2.ONE * (size_px / cell)
	return sprite
