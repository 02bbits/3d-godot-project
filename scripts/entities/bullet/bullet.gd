extends Node3D

const SPEED = 140.0
const LIFETIME = 3.0
const PLAYER_DAMAGE = 10
const IMPACT_SCENE := preload("res://scenes/effects/impact.tscn")

# true on remote replicas of other players' shots: visual only, the shooter's
# own bullet is the authority for damage
var visual_only := false

func _ready() -> void:
	await get_tree().create_timer(LIFETIME).timeout
	queue_free()

func _physics_process(delta: float) -> void:
	global_position += -global_transform.basis.z * SPEED * delta

func _on_body_entered(body: Node3D) -> void:
	if not visual_only:
		if body.is_in_group("enemy"):
			body.take_damage(1)
		elif body.is_in_group("player"):
			_damage_player(body)
	_spawn_impact.call_deferred(global_position)
	queue_free()

func _spawn_impact(pos: Vector3) -> void:
	var impact := IMPACT_SCENE.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = pos

func _damage_player(body: Node3D) -> void:
	var rep: Node = body.get_node_or_null("FusionSharedReplicator")
	if rep == null or not rep.has_method("has_authority") or rep.has_authority():
		return
	# body is a replica owned by that player's own client: route damage to its
	# authority so the real health on the victim's machine is decreased
	Fusion.rpc_to(Fusion.TARGET_OWNER, Callable(body, "rpc_take_damage"), PLAYER_DAMAGE)
