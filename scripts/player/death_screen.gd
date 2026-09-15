extends Control

@onready var restart_button: Button = %RestartButton

func _ready() -> void:
	restart_button.pressed.connect(_on_restart_pressed)

func _on_restart_pressed() -> void:
	restart_button.disabled = true
	var player := get_parent().get_parent()
	if player != null and player.has_method("request_restart"):
		player.request_restart()
	else:
		restart_button.disabled = false
