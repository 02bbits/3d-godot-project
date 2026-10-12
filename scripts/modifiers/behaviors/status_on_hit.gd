extends Modifier

## Weapon: every player hit applies a timed status to the target (a .tres in
## resources/modifiers/status/, applied by the victim's own client). Frost
## Rounds, Marked Target, Zap Gun and Anti-gravity Gun are this script with a
## different `status_id`.

@export var status_id: StringName = &"chilled"


func on_damage_dealt(ctx: Dictionary, _me: Node) -> void:
	if ctx.hit_player:
		ctx.statuses.append(status_id)


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	var status := ModifierDB.get_def(status_id)
	if status != null:
		lines.append(line("On hit", status.display_name, TONE_GOOD))
		for entry in status.describe():
			lines.append(line("Target " + entry.label.to_lower(), entry.value, TONE_GOOD))
		lines.append(line("Duration", "%.1f s" % status.duration))
	return lines
