extends RefCounted
class_name SkinState
## The skins (docs/godot/SKINS.md; Direction "The skins"; roadmap 7.8): the Pearls' powers. Each
## Pearl grants one skin, and once won a skin is **always on**, for good: its powers stack with the
## others' and need no key (owner, 2026-10-15; confirmed 2026-10-17). A skin acts only in its own
## places and on its own move, and it shows while it works (the slime turns stony on a heavy plate,
## silky in a web, shows claws as it climbs: player.gd `show_skin`, game/player/skins/skin_look.gd).
## The bag's Skins row picks one won skin as the slime's everyday look, cosmetic only (`set_look`).
##
## The record is RunState's (`story.skin_ids`, `story.skin_look`; saved). This class is the one
## way the game asks about skins:
## - `is_on(player, id)`: is that skin's power on? Every lock asks this (heavy plates and blocks,
##   the Heavy Roll's breakables, webs, web walls, silk parcels, climbable walls, the Spear's tempo).
##   `player` is the slime asking; it may be null (skins belong to the run).
## - `grant(id)`: a Pearl wins its skin and, the first time, shows the skin's short ceremony line
##   over the slime; the everyday look stays as it was (a skin shows only while it works).
## - `lend(id)` / `give_back(id)`: a skin for this session only (the F6 dev powers, the
##   playground's Skins corner); no save carries it.
##
## The skins' names, lines and numbers are game-constants.json `skins` (`defs.<id>`, and
## `heavy` / `silk` / `feral` for each one's numbers).
##
## Owner: skins.

const Services := preload("res://game/shared/services.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const HEAVY := &"heavy"
const SILK := &"silk"
const FERAL := &"feral"
## Release 1's skins, in the order the Pearls give them (game-constants `skins.order` may add more).
const RELEASE_ONE: Array[StringName] = [HEAVY, SILK, FERAL]
const CONSTANTS := "skins"
## The player method that shows a skin's look while it works (player.gd).
const SHOW_METHOD := &"show_skin"
const TEXT_RISE := 64.0
const LINE_RISE := 36.0


## True when skin `id`'s power is on: it is won (a Pearl) or lent for the session. `player` (the
## slime asking) may be null.
static func is_on(_player: Node, id: StringName) -> bool:
	var run := Services.run()
	return run != null and run.has_skin(String(id))


## True once `id` is won for good (a lent skin is not).
static func is_won(id: StringName) -> bool:
	var run := Services.run()
	return run != null and run.has_skin(String(id)) and not run.session_skin_ids.has(String(id))


## The skins whose power is on, in `skins.order`.
static func on_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in order():
		if is_on(null, id):
			out.append(id)
	return out


## Every skin the game knows, in the Pearls' order.
static func order() -> Array[StringName]:
	var out: Array[StringName] = []
	var constants := Services.constants()
	var listed: Variant = constants.value(CONSTANTS + ".order", []) if constants != null else []
	if listed is Array:
		for id: Variant in listed:
			out.append(StringName(str(id)))
	if out.is_empty():
		out = RELEASE_ONE.duplicate()
	return out


## A Pearl grants skin `id`: won for good, and the first time its short ceremony line shows over the
## slime, unless `announce` is false (the Pearl's card already says it all: its line ran on after the
## card closed, under the boss's roar, owner 2026-11-21). The everyday look stays as it was (the goo,
## unless the bag's Skins row picked one): a skin shows only while it works (owner, 2026-10-18).
## Returns true when it was new (not won before).
static func grant(id: StringName, announce := true) -> bool:
	var run := Services.run()
	if run == null or String(id).is_empty():
		return false
	var first := not is_won(id)
	run.win_skin(String(id))
	if first and announce:
		ceremony_line(id)
	return first


## Lends skin `id` for this session only (quietly). False when it is already on.
static func lend(id: StringName) -> bool:
	var run := Services.run()
	return run != null and run.lend_skin(String(id))


## Takes back a lent skin. False for a won one.
static func give_back(id: StringName) -> bool:
	var run := Services.run()
	return run != null and run.return_skin(String(id))


## The everyday look (&"" = the slime's own goo).
static func look() -> StringName:
	var run := Services.run()
	return StringName(run.skin_look()) if run != null else &""


## Picks the everyday look: a skin that is on, or &"" for the goo. False when not allowed or
## unchanged.
static func set_look(id: StringName) -> bool:
	var run := Services.run()
	return run != null and run.set_skin_look(String(id))


## `skins.defs.<id>`: {"name", "pearl", "look", "color", "line", "how"}; {} when unknown.
static func definition(id: StringName) -> Dictionary:
	var constants := Services.constants()
	var defs: Dictionary = constants.dictionary(CONSTANTS + ".defs") if constants != null else {}
	var entry: Variant = defs.get(String(id), {})
	return entry if entry is Dictionary else {}


static func display_name(id: StringName) -> String:
	return str(definition(id).get("name", String(id).capitalize() + " skin"))


## The skin's `line` or `how` (`skins.defs.<id>`) with its keys named from the bindings
## (ControlLabels.with_keys: "holding {interact}" reads "holding W" in the keys-only scheme).
static func text(id: StringName, field: String) -> String:
	return ControlLabels.with_keys(str(definition(id).get(field, "")))


## The skin's look in the slime's shader (form_skin.gdshader `skin`): 4 Heavy, 5 Silk, 6 Feral; 0
## for none.
static func look_index(id: StringName) -> int:
	return int(definition(id).get("look", 0))


static func color(id: StringName) -> Color:
	return Color.from_string(str(definition(id).get("color", "#ffffff")), Color.WHITE)


## `skins.<path>` (a number), or `fallback`.
static func setting(path: String, fallback: float) -> float:
	var constants := Services.constants()
	return float(constants.value(CONSTANTS + "." + path, fallback)) if constants != null else fallback


## Tells `player` that skin `id` works right now (it shows the skin's look for a moment).
static func show(player: Node, id: StringName) -> void:
	if player != null and is_instance_valid(player) and player.has_method(SHOW_METHOD):
		player.call(SHOW_METHOD, id)


## The skin's short ceremony line over the world's slime: its name, big, and its one line.
static func ceremony_line(id: StringName) -> void:
	var feel := Services.feel()
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if feel == null or player == null or not is_instance_valid(player):
		return
	var centre: Vector2 = player.call(&"get_centre")
	var ms := setting("ceremonyTextMs", 3200.0)
	feel.floating_text(centre - Vector2(0.0, TEXT_RISE), "%s!" % display_name(id).to_upper(), &"cyan", true, ms)
	var line := text(id, "line")
	if not line.is_empty():
		feel.floating_text(centre - Vector2(0.0, LINE_RISE), line, &"white", false, ms)
	show(player, id)
