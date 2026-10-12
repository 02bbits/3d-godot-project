extends Modifier

## Ability: no damage while dashing and for `linger` seconds after.

@export var linger := 0.25

var _left := 0.0


func on_dash(me: Node) -> void:
	_left = me.dash_time_ref + linger


func on_physics(delta: float, _me: Node) -> void:
	_left = maxf(_left - delta, 0.0)


func on_respawn(_me: Node) -> void:
	_left = 0.0


func on_damage_taken(ctx: Dictionary, _me: Node) -> void:
	if _left > 0.0:
		ctx.amount = 0.0


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("While dashing", "Untouchable", TONE_GOOD))
	lines.append(line("And after", "%.2f s" % linger))
	return lines
