extends Node
class_name FullHeartScript
## Scene script `game.full-heart` (`object.full-heart`, game/scenes/objects/full-heart.tscn; roadmap
## 5.3 and 8.7, questions 17 and 19; built 2026-10-17 for the Weaver Hollow's Matron): a boss's full
## heart, the goo heart's picture at a larger size. Hidden until its boss (`boss_id`, RunState
## `defeated_boss_ids`) is beaten, then it rises with a sparkle and bobs; the living slime's centre
## within `radius` takes it: max HP grows by `character.player.fullHeart.maxHpBonus` (20) for the
## run (`player.grant_full_heart`), HP fills, and with `raises_max_energy` max energy grows by
## `character.player.maxEnergyUpgrade.bossBonus` (20, `player.grant_max_energy`). The ceremony plays
## its card (game/ui/ceremony/ability_ceremony.gd `request_entry`) while main's `ability_ceremonies`
## is on. The story flag "full-heart.<heart_id>" keeps it gone for good: once per run, saved.
##
## Owner: boss port (the Matron; any boss's full heart).

const Services := preload("res://game/shared/services.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")

const FLAG_PREFIX := "full-heart."
const BOB_RATE := 2.4
const APPEAR_S := 0.8
const TEXT_RISE := 50.0
const TEXT_MS := 2200.0
const CUE_TAKE := &"Heal"
const CUE_APPEAR := &"SecretFound"
const SPARKLE := &"loot-sparkle"

## Unique across maps (its flag).
@export var heart_id: String = ""
## The boss whose defeat shows it ("" = shown at once).
@export var boss_id: String = ""
## Taking it also raises max energy (a beaten boss, question 19).
@export var raises_max_energy: bool = true
@export var radius: float = 40.0
@export var bob_px: float = 5.0
## The heart Sprite2D.
@export var visual: Sprite2D

## Taken. Payload {"heartId", "maxHpBonus", "maxEnergyBonus"}.
signal collected(payload: Dictionary)
## Shown (its boss beaten). Payload {"heartId"}.
signal appeared(payload: Dictionary)

var _taken: bool = false
var _shown: bool = false
var _elapsed: float = 0.0
var _rest_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	if visual != null:
		_rest_offset = visual.offset
	if heart_id.is_empty():
		push_warning("FullHeartScript '%s': a full heart has no heart_id; it cannot be taken." % get_path())
		_taken = true
	var run := Services.run()
	if run != null and run.has_flag(FLAG_PREFIX + heart_id):
		_taken = true
	_shown = not _taken and _boss_beaten()
	_set_visible(_shown)


func is_taken() -> bool:
	return _taken


func is_shown() -> bool:
	return _shown


func flag() -> String:
	return FLAG_PREFIX + heart_id


func _process(delta: float) -> void:
	if not _shown or visual == null:
		return
	_elapsed += delta
	visual.offset = Vector2(_rest_offset.x, _rest_offset.y + roundf(sin(_elapsed * BOB_RATE) * bob_px))


func _physics_process(_delta: float) -> void:
	if _taken:
		return
	if not _shown:
		if _boss_beaten():
			appear()
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")):
		return
	var root := get_parent() as Node2D
	if root == null or (player.call(&"get_centre") as Vector2).distance_to(root.global_position) > radius:
		return
	take(player)


## Shows it now (its boss was just beaten): it rises, fading in, with a sparkle.
func appear() -> void:
	if _shown or _taken:
		return
	_shown = true
	_set_visible(true)
	var root := get_parent() as CanvasItem
	if root != null:
		root.modulate.a = 0.0
		root.create_tween().tween_property(root, "modulate:a", 1.0, APPEAR_S)
	var feel := Services.feel()
	var at := (get_parent() as Node2D).global_position if get_parent() is Node2D else Vector2.ZERO
	if feel != null:
		feel.audio_cue(CUE_APPEAR)
		feel.particles(SPARKLE, at - Vector2(0.0, 24.0))
	appeared.emit({"heartId": heart_id})


## The slime takes it: the flag, the heart (and the energy raise), the line, the ceremony.
func take(player: Node) -> void:
	if _taken:
		return
	var run := Services.run()
	if run == null or run.has_flag(flag()):
		_taken = true
		_set_visible(false)
		return
	_taken = true
	_set_visible(false)
	run.set_flag(flag())
	var constants := Services.constants()
	var hp_bonus := constants.integer("character.player.fullHeart.maxHpBonus") if constants != null else 0
	var energy_bonus := constants.integer("character.player.maxEnergyUpgrade.bossBonus") if constants != null and raises_max_energy else 0
	if player != null and player.has_method(&"grant_full_heart"):
		player.call(&"grant_full_heart")
	else:
		run.add_full_heart()
	if energy_bonus > 0:
		if player != null and player.has_method(&"grant_max_energy"):
			player.call(&"grant_max_energy", energy_bonus)
		else:
			run.add_max_energy(energy_bonus)
	var at := (get_parent() as Node2D).global_position if get_parent() is Node2D else Vector2.ZERO
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_TAKE)
		feel.particles(SPARKLE, at)
		var text := "+%d max HP" % hp_bonus if energy_bonus <= 0 else "+%d max HP, +%d max energy" % [hp_bonus, energy_bonus]
		feel.floating_text(at - Vector2(0.0, TEXT_RISE), text, &"green", true, TEXT_MS)
	if is_inside_tree() and AbilityCeremony.enabled(get_tree()):
		var line := "Your goo grows tougher: you can take more hits, and you are healed in full."
		if energy_bonus > 0:
			line = "Your goo grows tougher and fuller: you can take more hits and cast more, and you are refilled."
		AbilityCeremony.request_entry(get_tree(), {"kicker": "Full Heart", "name": "+%d max HP" % hp_bonus,
			"line": line, "how": ("+%d max energy" % energy_bonus) if energy_bonus > 0 else "", "icon": _icon()})
	collected.emit({"heartId": heart_id, "maxHpBonus": hp_bonus, "maxEnergyBonus": energy_bonus})


func _set_visible(on: bool) -> void:
	var root := get_parent() as CanvasItem
	if root != null:
		root.visible = on


func _boss_beaten() -> bool:
	if boss_id.is_empty():
		return true
	var run := Services.run()
	return run != null and boss_id in (run.world.get("defeated_boss_ids", []) as Array)


## The heart's frame, for the ceremony's bubble.
func _icon() -> Texture2D:
	if visual == null or visual.texture == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = visual.texture
	var frame_size := visual.texture.get_size() / Vector2(maxi(1, visual.hframes), maxi(1, visual.vframes))
	var columns := maxi(1, visual.hframes)
	icon.region = Rect2(Vector2(float(visual.frame % columns) * frame_size.x,
		floorf(float(visual.frame) / float(columns)) * frame_size.y), frame_size)
	return icon
