extends Modifier

## Weapon: every shot that hits something explodes. Everyone within `radius`
## of the impact (the direct target too) takes `damage_scale` of the shot's
## damage; the shooter never does. The blast effect plays on every peer.

@export var radius := 3.0
@export var damage_scale := 0.5
@export var effect: PackedScene


func on_impact(shot: Dictionary, me: Node) -> void:
	var hit: Dictionary = shot.hit
	if hit.is_empty():
		return
	var center: Vector3 = hit.position
	var amount := roundi(me.mods.get_stat(&"damage", me.weapon.definition.damage) * damage_scale)
	# ponytail: no line-of-sight test, so the blast reaches through thin walls;
	# raycast from the center to each target if maps get thin walls
	for group in ["player", "enemy"]:
		for target in me.get_tree().get_nodes_in_group(group):
			if target == me or not is_instance_valid(target) or target.get("dead") == true:
				continue
			if target.global_position.distance_to(center) <= radius:
				me.weapon.deal_damage(target, amount, target.global_position)


func on_shot_fx(hit: Dictionary, me: Node) -> void:
	if effect == null or hit.normal == Vector3.ZERO:
		return
	var blast := effect.instantiate() as Node3D
	me.get_tree().root.add_child(blast)
	blast.global_position = hit.position


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("Blast damage", "%d%% of a shot" % roundi(damage_scale * 100.0), TONE_GOOD))
	lines.append(line("Blast radius", "%.1f m" % radius, TONE_GOOD))
	return lines
