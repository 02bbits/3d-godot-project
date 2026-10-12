extends Modifier

## Environment: every player regenerates. Global modifiers live in every
## player's manager, so each client heals its own player.

@export var per_second := 3.0


func on_physics(delta: float, me: Node) -> void:
	me.get_node("Health").heal(per_second * delta)


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.insert(0, line("Regeneration", "%s HP/s" % signed(per_second), TONE_GOOD))
	return lines
