extends Node
class_name WorldExitScript
## Scene script `game.world-exit` (Phaser `features/scripts/WorldExitScript.ts`). World spec 8.
## TRIAL: inert stub. It exists so the converter wires the exports and the
## `Area2D.body_entered -> on_body_entered` connection without errors; travelling between
## worlds, gates and keys are a later phase. Documented behaviour for that phase is below.
##
## Owner: world builder.

## JSON `mapId` (the world this exit belongs to).
@export var map_id: String = ""
## JSON `exitId`.
@export var exit_id: String = ""
## JSON `targetAreaId` (e.g. "gloop-forest").
@export var target_area_id: String = ""
## JSON `entry`: arrival edge in the target world ("west", ...).
@export var entry: String = ""
## JSON `area`: the Area2D (layer trigger, mask player|npc) whose bodies are tested.
@export var area: Area2D
## JSON `gate` (camelCase keys: id, requiredItemId, consumeOnUnlock, lockedMessage).
@export var gate: Dictionary = {}
## JSON `arrivalGraceMs` (absent in every scene): < 0 means use game-constants
## `worldNavigation.edgeTransitionGraceMs` (650).
@export var arrival_grace_ms: float = -1.0

## Phaser emits the exit service result. Payload: {"status": "ignored"|"blocked"|"queued", "message"?}.
signal navigation_resolved(result: Dictionary)


## Connected from `area.body_entered`. Later phase: if `body` is the player body, after the
## grace period and until queued, request the exit (WorldScene.requestAuthoredExit). Trial: no-op.
func on_body_entered(body: Node) -> void:
	pass
