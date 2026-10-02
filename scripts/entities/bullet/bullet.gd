extends Node3D

const SPEED = 300.0
const LIFETIME = 0.6

# tracers are cosmetic on every client (shooter included); damage is hitscan
# from the gun's raycast, so this only draws the shot and sparks on the map
func _ready() -> void:
	await get_tree().create_timer(LIFETIME).timeout
	queue_free()

func _physics_process(delta: float) -> void:
	global_position += -global_transform.basis.z * SPEED * delta

func _on_body_entered(_body: Node3D) -> void:
	queue_free()
