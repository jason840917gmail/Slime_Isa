@tool
extends Node
## Placeholder the scene converter attaches to a ScriptNode whose GDScript
## port (`res://game/scripts/<snake_id>.gd`) does not exist yet. It keeps the
## authored data so nothing is lost, and does nothing at run time.
##
## - `script_id`: the JSON script id (e.g. `game.resource-node`).
## - `properties`: the authored properties as raw JSON (camelCase keys); node
##   references are NodePath strings relative to this node, scene references
##   are scene ids.
## - `signal_names`: signals other nodes connect to on this script; they are
##   registered as user signals (before the scene's connections are made) so
##   those connections load. They never fire until the script is ported.
## Handlers connected to it are not defined here; calling them would only
## print an error, and nothing emits into them before the port exists.
## It is a tool script so the editor and the exporter, which load scenes
## without running game scripts, also register the signals.
##
## Owner: converter builder.

@export var script_id: String = ""
@export var properties: Dictionary = {}
@export var signal_names: PackedStringArray = PackedStringArray():
	set(value):
		signal_names = value
		for signal_name in value:
			if not has_user_signal(signal_name) and not has_signal(signal_name):
				add_user_signal(signal_name, [{"name": "payload", "type": TYPE_NIL}])


## A property as authored (JSON key), or `fallback` when absent.
func authored(key: String, fallback: Variant = null) -> Variant:
	return properties.get(key, fallback)
