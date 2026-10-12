extends Modifier

## Weapon: a shot that misses bends onto the enemy closest to the crosshair,
## if one is within `cone_degrees`, in range and in line of sight.

@export var cone_degrees := 6.0


func on_fire(shot: Dictionary, me: Node) -> void:
	var collider: Variant = shot.hit.get("collider")
	if collider is Node and (collider as Node).is_in_group("player"):
		return
	var best_angle := deg_to_rad(cone_degrees)
	for target in me.get_tree().get_nodes_in_group("player"):
		if target == me or not is_instance_valid(target) or target.dead:
			continue
		var to_target: Vector3 = target.global_position - shot.origin
		if to_target.length() > shot.range:
			continue
		var angle: float = shot.direction.angle_to(to_target)
		if angle >= best_angle:
			continue
		var ray: Dictionary = me.weapon.raycast(shot.origin, target.global_position)
		if ray.get("collider") == target:
			best_angle = angle
			shot.hit = ray


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("Aim assist", "%d°" % roundi(cone_degrees), TONE_GOOD))
	return lines
