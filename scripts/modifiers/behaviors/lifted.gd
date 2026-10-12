extends Modifier

## Status (Anti-gravity Gun): pulled skyward at the victim's own walk speed
## (× speed_scale) while it lasts.

@export var speed_scale := 1.0


func on_physics(_delta: float, me: Node) -> void:
	me.velocity.y = me.walk_speed * speed_scale


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("Lift speed", "%d%% walk" % roundi(speed_scale * 100.0)))
	return lines
