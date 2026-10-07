extends ItemList
## Converted scene ItemList (runtime spec section 4.19). Godot's own
## `item_selected(index)` covers selection; the Phaser-only signals are
## declared here so authored connections load. The Phase 3 UI replaces this
## with a grid of buttons that emits the Phaser payloads.
##
## Owner: converter builder.

## Right-click / context menu on an item: `{index, item}`.
signal item_secondary(payload: Dictionary)
## Drag-and-drop onto this list: `{index, item, sourceItemId, sourceIndex}`.
signal item_dropped(payload: Dictionary)

## Phaser `dropTarget`: this list accepts dragged items.
@export var drop_target: bool = false
