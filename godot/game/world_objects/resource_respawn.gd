extends RefCounted
## Regrowth of harvested resource nodes (Phaser `features/resources/ResourceRespawn.ts`,
## world-objects spec 6). Resolved only when a node enters the tree (world load), on the wall
## clock, so the timer also runs while the game is closed:
## - no record, or stage "node": unchanged;
## - no timer (old records): start it now (`now + respawn_ms`), changed;
## - stage "depleted" and the timer passed: {} (the node grows back), changed;
## - otherwise (still on the timer, or piles still lie around as stage "destroyed"): unchanged.
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")

## Tests set this to pin the wall clock; < 0 = the real clock.
static var epoch_override_ms: float = -1.0


## Wall-clock epoch time in ms (Phaser `Date.now()`), or the test override.
static func now_epoch_ms() -> float:
	if epoch_override_ms >= 0.0:
		return epoch_override_ms
	return Time.get_unix_time_from_system() * 1000.0


## `resources.respawnMs` (600 000).
static func respawn_ms() -> float:
	var constants := Services.constants()
	return constants.number("resources.respawnMs") if constants != null else 0.0


## {"record": Dictionary ({} = none / grows back), "changed": bool}.
static func resolve(record: Dictionary, now_ms: float, respawn_after_ms: float) -> Dictionary:
	if record.is_empty() or str(record.get("stage", "")) == "node":
		return {"record": record, "changed": false}
	if not record.has("respawn_ready_at_epoch_ms"):
		var timed := record.duplicate(true)
		timed["respawn_ready_at_epoch_ms"] = now_ms + respawn_after_ms
		return {"record": timed, "changed": true}
	if str(record.get("stage", "")) == "depleted" and now_ms >= float(record["respawn_ready_at_epoch_ms"]):
		return {"record": {}, "changed": true}
	return {"record": record, "changed": false}
