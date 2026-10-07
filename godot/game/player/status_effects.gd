extends RefCounted
## The player's status effects (Phaser `systems/StatusEffects.ts`, owned by WorldScene; here by
## player.gd). A status lasts its time on the simulation clock (applying it again keeps the
## longer remainder): burn and poison hurt every 500 ms (6 / 4 per second), slow (0.55) and frenzy
## (1.4) scale walking, sticky roots the slime (spider webs: no walking, jumping, dodging or
## teleporting; attacks and the lash still work). Adding one plays its Status<Kind> cue and
## removing one StatusExpire (AudioEventBridge.ts:45-50, 88-89).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const TICK_MS := 500.0
## kind -> {"dps", "speed", "duration_ms" (default), "cue"}.
const DEFINITIONS := {
	&"burn": {"dps": 6.0, "speed": 1.0, "duration_ms": 3000.0, "cue": &"StatusBurn"},
	&"poison": {"dps": 4.0, "speed": 1.0, "duration_ms": 5000.0, "cue": &"StatusPoison"},
	&"slow": {"dps": 0.0, "speed": 0.55, "duration_ms": 2500.0, "cue": &"StatusSlow"},
	&"sticky": {"dps": 0.0, "speed": 0.0, "duration_ms": 1200.0, "cue": &"StatusSticky"},
	&"bouncy": {"dps": 0.0, "speed": 1.0, "duration_ms": 1500.0, "cue": &"StatusBouncy"},
	&"frenzy": {"dps": 0.0, "speed": 1.4, "duration_ms": 4000.0, "cue": &"StatusFrenzy"},
}
const CUE_EXPIRE := &"StatusExpire"

## kind -> {"time_left", "last_tick"}.
var _active: Dictionary = {}
## Damage callback (player.gd): func(amount: float, kind: StringName).
var _hurt: Callable


func _init(hurt: Callable) -> void:
	_hurt = hurt


## Applies `kind` for `duration_ms` (< 0: its default); a running one keeps the longer remainder.
func apply(kind: StringName, duration_ms: float = -1.0) -> void:
	if not DEFINITIONS.has(kind):
		return
	var duration: float = duration_ms if duration_ms >= 0.0 else float(DEFINITIONS[kind]["duration_ms"])
	if _active.has(kind):
		_active[kind]["time_left"] = maxf(float(_active[kind]["time_left"]), duration)
		return
	_active[kind] = {"time_left": duration, "last_tick": Services.now_ms()}
	_cue(DEFINITIONS[kind]["cue"])


func remove(kind: StringName) -> void:
	if _active.erase(kind):
		_cue(CUE_EXPIRE)


func clear() -> void:
	for kind: StringName in _active.keys():
		remove(kind)


func has(kind: StringName) -> bool:
	return _active.has(kind)


func is_rooted() -> bool:
	return has(&"sticky")


## Product of the active statuses' movement multipliers.
func speed_multiplier() -> float:
	var multiplier := 1.0
	for kind: StringName in _active:
		multiplier *= float(DEFINITIONS[kind]["speed"])
	return multiplier


func attack_multiplier() -> float:
	return 1.4 if has(&"frenzy") else 1.0


## Ages every status by `delta_ms` and deals damage-over-time ticks.
func update(delta_ms: float) -> void:
	var now := Services.now_ms()
	for kind: StringName in _active.keys():
		var status: Dictionary = _active[kind]
		status["time_left"] = float(status["time_left"]) - delta_ms
		if float(status["time_left"]) <= 0.0:
			remove(kind)
			continue
		var dps := float(DEFINITIONS[kind]["dps"])
		if dps > 0.0 and now - float(status["last_tick"]) >= TICK_MS:
			status["last_tick"] = now
			if _hurt.is_valid():
				_hurt.call(dps * TICK_MS / 1000.0, kind)


func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)
