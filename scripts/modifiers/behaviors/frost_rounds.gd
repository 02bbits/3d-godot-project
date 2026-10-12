extends Modifier

## Weapon: every player hit applies a timed status to the target (a .tres in
## resources/modifiers/status/, applied by the victim's own client).

@export var status_id: StringName = &"chilled"


func on_damage_dealt(ctx: Dictionary, _me: Node) -> void:
	if ctx.hit_player:
		ctx.statuses.append(status_id)


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	var status := ModifierDB.get_def(status_id)
	if status != null:
		for entry in status.describe():
			lines.append(line("Enemy " + entry.label.to_lower(), entry.value, TONE_GOOD))
		lines.append(line("Duration", "%.1f s" % status.duration))
	return lines
