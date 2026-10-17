extends RefCounted
## The look of something the slime sucks in (owner, 2026-10-08/09): the same picture flies into the
## mouth, shows inside the full slime and flies out when it is thrown. A liftable is its frame of the
## liftables sheet (game/data/liftables.json, game/scripts/liftable.gd), an essence its frame of the
## essences sheet (both packed by scripts/props/pack-gulp-art.py). Every look is centred on its node
## and about `size_px` across.
##
## A caught enemy projectile (the Spitcap's spore seed, game/scripts/spore_seed.gd) brings its own
## picture: `held.texture` (a res:// path, game/runtime/sheet_sprite.gd `load_picture`), drawn
## `held.art_px` across, and its `material` (`material_of`).
##
## Owner: abilities.

const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")
const ESSENCES_SHEET := "res://asset/MAPS/items/128x128-tile_3x1-gulp-essences.webp"
const ESSENCES_CELL := 128.0
const LIFTABLES_CELL := 192.0
## The Goo Bomb's held kind and picture (goo_bomb.gd KIND, TEXTURE_PATH; 96 x 112 art), its height
## this share of `size_px` (a liftable's art nearly fills its cell, the bomb is drawn a bit bigger).
const GOO_BOMB_KIND := "goo-bomb"
const GOO_BOMB_TEXTURE := "res://asset/abilities/goo-bomb/bomb.webp"
const GOO_BOMB_ART_PX := 112.0
const GOO_BOMB_LOOK_SHARE := 1.3


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
	# A caught projectile's own picture (the spore seed).
	if held.get("texture") is String and not str(held["texture"]).is_empty():
		sprite.texture = SheetSprite.load_picture(str(held["texture"]))
		sprite.scale = Vector2.ONE * (size_px / maxf(1.0, float(held.get("art_px", size_px))))
		return sprite
	# The Goo Bomb (game/scripts/goo_bomb.gd) is its own picture, not a liftables sheet frame.
	if str(held.get("kind", "")) == GOO_BOMB_KIND:
		if ResourceLoader.exists(GOO_BOMB_TEXTURE):
			sprite.texture = load(GOO_BOMB_TEXTURE)
		sprite.scale = Vector2.ONE * (size_px * GOO_BOMB_LOOK_SHARE / GOO_BOMB_ART_PX)
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


## The material `held` breaks as: its own `material` (a caught projectile), else its liftable
## kind's (game/data/liftables.json).
static func material_of(held: Dictionary) -> String:
	var own: Variant = held.get("material")
	if own is String and not (own as String).is_empty():
		return own
	return LiftableScript.material_of(str(held.get("kind", "")))
