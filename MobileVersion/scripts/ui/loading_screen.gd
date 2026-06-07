extends CanvasLayer

@onready var status_label: Label = $Root/Panel/Stack/StatusLabel

func _ready() -> void:
	SceneLoader.loading_status_changed.connect(_on_loading_status_changed)
	_on_loading_status_changed("Ready.")


func _on_loading_status_changed(message: String) -> void:
	status_label.text = message
