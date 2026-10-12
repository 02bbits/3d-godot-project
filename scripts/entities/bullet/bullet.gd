extends Node3D

const SPEED = 100.0
const LIFETIME = 1.0

# tracers are cosmetic on every client (shooter included); damage is hitscan
# from the gun's raycast, so this only draws the shot and sparks on the map
func _ready() -> void:
	await get_tree().create_timer(LIFETIME).timeout
	queue_free()

# set by the weapon: distance to the shot's hit point
var max_distance := INF
var _travelled := 0.0

func _physics_process(delta: float) -> void:
	var step := minf(SPEED * delta, max_distance - _travelled)
	global_position += -global_transform.basis.z * step
	_travelled += step
	if _travelled >= max_distance:
		queue_free()

func _on_body_entered(_body: Node3D) -> void:
	queue_free()
