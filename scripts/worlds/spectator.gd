extends Node3D

## Third-person spectator (scenes/worlds/spectator.tscn), used while the local
## player is eliminated. Follows a living player's head; the mouse orbits the
## view, the player's own move-left/right keys (A/D) cycle targets, and the
## spring arm keeps the camera out of walls. The rig is moved every frame, so
## it opts out of physics interpolation (an interpolated camera moved in
## _process renders stale tick poses and judders).

const HEAD_HEIGHT := 1.5

# radians per mouse pixel, before the player's sensitivity setting; matches
# the first-person camera (camera_script.gd: 0.025 / 10)
@export var orbit_sensitivity := 0.0025
@export_range(-89.0, 0.0, 1.0) var min_pitch_degrees := -70.0
@export_range(-45.0, 45.0, 1.0) var max_pitch_degrees := 25.0
@export_range(-89.0, 45.0, 1.0) var start_pitch_degrees := -15.0

@onready var arm: SpringArm3D = $Arm
@onready var camera: Camera3D = $Arm/Camera

var _targets: Array = [] # instance ids: they survive a target being freed
var _index := 0
var _yaw := 0.0
var _pitch := 0.0


## Called every frame while `local` is eliminated; returns the spectated
## player (null when nobody is left alive to watch).
func follow(local: Node) -> Node3D:
	_refresh_targets(local)
	if _targets.is_empty():
		stop()
		return null
	if Input.is_action_just_pressed(local.move_left_action):
		_index = wrapi(_index - 1, 0, _targets.size())
	if Input.is_action_just_pressed(local.move_right_action):
		_index = wrapi(_index + 1, 0, _targets.size())
	var target := instance_from_id(_targets[_index]) as Node3D
	if target == null:
		return null
	if not camera.current:
		# start behind the target, looking where it looks
		_yaw = target.cam_holder.rotation.y
		_pitch = deg_to_rad(start_pitch_degrees)
		camera.current = true
	global_position = target.global_position + Vector3.UP * HEAD_HEIGHT
	arm.rotation = Vector3(_pitch, _yaw, 0.0)
	return target


func stop() -> void:
	_targets.clear()
	_index = 0
	if camera.current:
		camera.current = false


# _input, not _unhandled_input: the death screen covers the view and would
# swallow mouse motion before it got here
func _input(event: InputEvent) -> void:
	if not camera.current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var step := orbit_sensitivity * CameraObject.mouse_sensitivity
		_yaw -= event.relative.x * step
		_pitch = clampf(_pitch - event.relative.y * step,
				deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))


func _refresh_targets(local: Node) -> void:
	var previous_id: int = _targets[_index] if _index < _targets.size() else 0
	_targets = []
	for player in get_tree().get_nodes_in_group("player"):
		if player != local and is_instance_valid(player) and not player.dead:
			_targets.append(player.get_instance_id())
	_index = maxi(_targets.find(previous_id), 0)
