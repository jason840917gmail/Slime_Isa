extends Node
## NPC name tags (Phaser `features/npcs/NpcNameTags.ts`; world spec 5.6): the display name over
## every world NPC that has a definition, 14 px #f5f7ff with a 4 px #081022 outline, its bottom
## centre 2 px above the sprite's top (the NPC's old position - (0, 229 x 0.32 + 2) = - 75.28).
## Main's child "NpcNameTags", made once; each tag is a "NameTag" Node2D child of the NPC's body,
## so it walks with the NPC, goes with it when a story variant parks it, and sorts with it in the
## y-sorted world (just after the NPC's root, like Phaser's attachment slot): a tree in front
## hides it. The quest markers (npc_quest_markers.gd) float 18 px above the tag.
##
## Owner: world (NPC extras).

const QuestCatalog := preload("res://game/quests/quest_catalog.gd")

const NPC_GROUP := &"npc"
const TAG_NAME := &"NameTag"
## NpcNameTags.ts: the sprite's display height x originY (229 x 0.32) + the 2 px gap.
const TAG_RISE := 75.28
## The tag sorts just after the NPC's root (Phaser NAME_TAG_ATTACHMENT_SLOT).
const SORT_OFFSET := 0.5
const FONT_SIZE := 14
const OUTLINE_SIZE := 4
const TEXT_COLOR := Color("#f5f7ff")
const OUTLINE_COLOR := Color("#081022")


func _init() -> void:
	name = "NpcNameTags"


func _process(_delta: float) -> void:
	for node: Node in get_tree().get_nodes_in_group(NPC_GROUP):
		var body := node.get(&"body") as Node2D
		if body == null or not body.is_inside_tree() or body.has_node(NodePath(TAG_NAME)):
			continue
		var npc_id := str(node.get(&"npc_definition_id"))
		if npc_id.is_empty() or not QuestCatalog.has_npc(npc_id) or not node.has_method(&"get_phaser_position"):
			continue
		_add_tag(body, node.call(&"get_phaser_position"), QuestCatalog.npc_name(npc_id))


## The tag text over the NPC whose body is `body` ("" when it has none; tests).
static func tag_text(body: Node) -> String:
	var tag := body.get_node_or_null(NodePath(TAG_NAME))
	var label := tag.get_child(0) as Label if tag != null and tag.get_child_count() > 0 else null
	return label.text if label != null else ""


func _add_tag(body: Node2D, phaser_position: Vector2, text: String) -> void:
	var tag := Node2D.new()
	tag.name = TAG_NAME
	tag.position = Vector2(0.0, SORT_OFFSET)
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font_size = FONT_SIZE
	settings.font_color = TEXT_COLOR
	settings.outline_size = OUTLINE_SIZE
	settings.outline_color = OUTLINE_COLOR
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(label)
	body.add_child(tag)
	# Bottom centre at the old position - TAG_RISE, in the body's (unscaled) space.
	var size := label.get_minimum_size()
	var bottom_centre := (phaser_position - body.global_position) - Vector2(0.0, TAG_RISE + SORT_OFFSET)
	label.position = (bottom_centre - Vector2(size.x / 2.0, size.y)).round()
