extends Modifier

## Ability: a dash rams nearby players: `damage` and a shove (outward + up),
## each player at most once per dash.

@export var damage := 40
@export var radius := 2.5
@export var push := 12.0
@export var lift := 6.0
# how long after the dash starts it still rams (the dash itself is ~0.1 s)
@export var grace := 0.1

var _window := 0.0
var _rammed: Array = []


func on_dash(me: Node) -> void:
	_window = me.dash_time_ref + grace
	_rammed.clear()


func on_physics(delta: float, me: Node) -> void:
	if _window <= 0.0:
		return
	_window -= delta
	for target in me.get_tree().get_nodes_in_group("player"):
		if target == me or not is_instance_valid(target) or target.dead or _rammed.has(target):
			continue
		var offset: Vector3 = target.global_position - me.global_position
		if offset.length() > radius:
			continue
		_rammed.append(target)
		me.weapon.deal_damage(target, damage, target.global_position)
		var shove := Vector3(offset.x, 0.0, offset.z).normalized() * push + Vector3.UP * lift
		Fusion.rpc_to(Fusion.TARGET_OWNER, Callable(target, "rpc_knockback"),
				shove.x, shove.y, shove.z)


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("Dash damage", "%d" % damage, TONE_GOOD))
	lines.append(line("Knockback within", "%.1f m" % radius, TONE_GOOD))
	return lines
