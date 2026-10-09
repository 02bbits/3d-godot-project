extends Control

## Shown while the local player is eliminated: names the player being
## spectated. Target cycling lives in world.gd; respawns hand back control
## when the match ends.

@onready var target_label: Label = %TargetLabel


func set_spectate_target(nickname: String) -> void:
	if nickname.is_empty():
		target_label.text = "No players left"
	else:
		target_label.text = "Spectating: %s" % nickname
