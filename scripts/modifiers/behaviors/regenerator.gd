extends Modifier

## Stats: regenerate health once the owner hasn't taken damage for `delay`
## seconds.

@export var delay := 4.0
@export var per_second := 3.0

var _calm := 0.0


func on_damage_taken(_ctx: Dictionary, _me: Node) -> void:
	_calm = 0.0


func on_respawn(_me: Node) -> void:
	_calm = 0.0


func on_physics(delta: float, me: Node) -> void:
	_calm += delta
	if _calm >= delay:
		me.get_node("Health").heal(per_second * level * delta)


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("Regeneration", "%s HP/s" % signed(per_second * at_level), TONE_GOOD))
	lines.append(line("After no damage for", "%.0f s" % delay))
	return lines
