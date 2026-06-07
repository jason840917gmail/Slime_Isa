extends CanvasLayer

@onready var coins_label: Label = $Root/TopLeft/CoinsLabel
@onready var friends_label: Label = $Root/TopLeft/FriendsLabel
@onready var message_label: Label = $Root/BottomMessage/MessageLabel

func _ready() -> void:
	GameState.coins_changed.connect(_on_coins_changed)
	GameState.friends_changed.connect(_on_friends_changed)
	GameState.message_changed.connect(_on_message_changed)

	_on_coins_changed(GameState.coins)
	_on_friends_changed(GameState.friends)


func _on_coins_changed(total: int) -> void:
	coins_label.text = "Coins: %d" % total


func _on_friends_changed(total: int) -> void:
	friends_label.text = "Friends: %d" % total


func _on_message_changed(text: String) -> void:
	message_label.text = text
	message_label.visible = text != ""
