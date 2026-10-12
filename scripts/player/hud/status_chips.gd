extends HBoxContainer

## Active statuses on the local player (scenes/player/hud/status_chips.tscn):
## one pill per status under the reticle, so a stunned or lifted player sees
## why. Fed by hud_script.gd on every build change (status added or expired).


func show_statuses(statuses: Array[Modifier]) -> void:
	NodeUtil.fit_children(self, statuses.size())
	for i in statuses.size():
		get_child(i).get_node("Label").text = statuses[i].display_name.to_upper()
