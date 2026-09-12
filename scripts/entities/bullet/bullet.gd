extends Node3D

const SPEED = 140.0
const LIFETIME = 3.0

func _ready() -> void:
	await get_tree().create_timer(LIFETIME).timeout
	queue_free()

func _physics_process(delta: float) -> void:
	global_position += -global_transform.basis.z * SPEED * delta

func _on_body_entered(body: Node3D) -> void:
	var color: Color
	if body.is_in_group("enemy"):
		body.take_damage(1)
		color = Color(0.766, 0.755, 1.0, 1.0)
	else:
		color = Color(0.372, 1.0, 0.933, 1.0)
	BulletEffect.spawn(get_parent(), global_position, color)
	queue_free()
