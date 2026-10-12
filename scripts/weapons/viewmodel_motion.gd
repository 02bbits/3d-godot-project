extends Node3D

## Procedural first-person gun motion. This node is the viewmodel pivot (under
## the viewmodel camera, holding the gun and its muzzle); every frame it
## composes idle breathing, step bob, sprint tilt, strafe roll, look sway,
## slide/dash/air poses, a landing dip, spring recoil and the reload animation
## into one transform. Rotations turn around the gun's grip, not the camera.
## Local player only — remote copies show the world model in the hand.

const KICK_STIFFNESS := 260.0
const KICK_DAMPING := 20.0
const LAND_STIFFNESS := 120.0
const LAND_DAMPING := 12.0
const RAISE_TIME := 0.35

var play_char: Node3D
var weapon: Node3D
var anchor := Vector3.ZERO # grip position in camera space; rotations pivot here

# springs (position in m, rotation in rad: x = muzzle up, y = left, z = roll left)
var _kick_pos := Vector3.ZERO
var _kick_pos_vel := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var _kick_rot_vel := Vector3.ZERO
var _land := 0.0
var _land_vel := 0.0

var _time := 0.0
var _since_shot := 10.0
var _bob_phase := 0.0
var _bob := 0.0
var _sprint := 0.0
var _strafe := 0.0
var _air := 0.0
var _slide := 0.0
var _dash := 0.0
var _sway := Vector2.ZERO
var _last_look := Vector2.ZERO
var _was_on_floor := true
var _raise := 0.0
var _reload_t := -1.0
var _reload_len := 1.0
var _reload_beats := 0


func setup(p_char: Node3D, p_weapon: Node3D, grip: Vector3) -> void:
	play_char = p_char
	weapon = p_weapon
	anchor = grip
	_last_look = _look()


## shot fired: muzzle climbs and the gun slams back, then springs home
func kick() -> void:
	_since_shot = 0.0
	# an instant snap on the shot frame, then the spring carries it through
	_kick_rot += Vector3(deg_to_rad(4.0), 0.0, deg_to_rad(randf_range(-2.0, 2.0)))
	_kick_pos += Vector3(0.0, 0.004, 0.03)
	_kick_rot_vel += Vector3(deg_to_rad(200.0), deg_to_rad(randf_range(-60.0, 60.0)),
			deg_to_rad(randf_range(-110.0, 110.0)))
	_kick_pos_vel += Vector3(randf_range(-0.15, 0.15), 0.3, 1.6)


func start_reload(duration: float) -> void:
	_reload_t = 0.0
	_reload_len = maxf(duration, 0.2)
	_reload_beats = 0


func stop_reload() -> void:
	_reload_t = -1.0


## respawn: the gun swings up into view
func raise() -> void:
	_raise = 1.0
	stop_reload()


func _process(delta: float) -> void:
	if play_char == null or play_char.is_remote or delta <= 0.0:
		return
	_time += delta
	_since_shot += delta
	var state: String = play_char.state_machine.curr_state_name
	var vel: Vector3 = play_char.velocity
	var speed := Vector2(vel.x, vel.z).length()
	var on_floor: bool = play_char.is_on_floor()

	_spring(delta)
	if on_floor and not _was_on_floor:
		# landing dip, deeper after a longer fall
		_land_vel -= clampf(-play_char.last_frame_velocity.y * 0.05, 0.1, 0.9)
	_was_on_floor = on_floor

	# look sway: the gun lags behind fast camera turns
	var look := _look()
	var turn := Vector2(wrapf(look.x - _last_look.x, -PI, PI), look.y - _last_look.y)
	_last_look = look
	# turning right yaws the gun left (positive) and slides it left: it lags
	var sway_target := (-turn / delta * 0.012).clampf(-0.09, 0.09)
	_sway = _sway.lerp(sway_target, _blend(10.0, delta))

	var run_speed: float = maxf(play_char.run_speed, 0.1)
	var stepping := on_floor and state != "Slide" and state != "Dash"
	_bob = lerpf(_bob, clampf(speed / run_speed, 0.0, 1.3) if stepping else 0.0, _blend(8.0, delta))
	_bob_phase += delta * (4.0 + speed * 0.75)
	# sprint pose drops away while shooting or reloading
	var sprinting: bool = state == "Run" and speed > play_char.walk_speed + 0.5 \
			and _since_shot > 0.4 and _reload_t < 0.0
	_sprint = lerpf(_sprint, 1.0 if sprinting else 0.0, _blend(9.0, delta))
	_strafe = lerpf(_strafe, -float(play_char.input_direction.x), _blend(8.0, delta))
	_air = lerpf(_air, 0.0 if on_floor else 1.0, _blend(6.0, delta))
	_slide = lerpf(_slide, 1.0 if state == "Slide" else 0.0, _blend(10.0, delta))
	_dash = lerpf(_dash, 1.0 if state == "Dash" else 0.0, _blend(18.0, delta))
	_raise = maxf(_raise - delta / RAISE_TIME, 0.0)

	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	# idle breathing
	pos += Vector3(sin(_time * 0.9) * 0.003, sin(_time * 1.8) * 0.004, 0.0)
	rot.x += sin(_time * 1.8 + 0.6) * deg_to_rad(0.5)
	# step bob: figure-eight, dipping on each footfall
	pos += Vector3(sin(_bob_phase) * 0.014, -absf(cos(_bob_phase)) * 0.018, 0.0) * _bob
	rot.z += sin(_bob_phase) * deg_to_rad(1.6) * _bob
	rot.x += -absf(cos(_bob_phase)) * deg_to_rad(1.0) * _bob
	# sprint: gun cants across the body and drops
	pos += Vector3(-0.05, -0.06, 0.03) * _sprint
	rot += Vector3(deg_to_rad(-10.0), deg_to_rad(22.0), deg_to_rad(12.0)) * _sprint
	# strafe roll and look sway
	rot.z += deg_to_rad(5.0) * _strafe
	rot.y += _sway.x
	rot.x += _sway.y
	pos.x -= _sway.x * 0.06
	# air, slide, dash
	pos.y += 0.02 * _air
	rot.x += deg_to_rad(3.0) * _air
	pos += Vector3(-0.03, -0.03, 0.0) * _slide
	rot.z += deg_to_rad(16.0) * _slide
	pos.z += 0.08 * _dash
	rot.x -= deg_to_rad(8.0) * _dash
	pos.y += _land
	# respawn raise
	var r := _raise * _raise
	pos.y -= 0.35 * r
	rot.x -= deg_to_rad(35.0) * r
	# reload and recoil
	var reload := _reload_pose(delta)
	pos += reload[0]
	rot += reload[1]
	pos += _kick_pos
	rot += _kick_rot

	var basis := Basis.from_euler(rot)
	transform = Transform3D(basis, pos + anchor - basis * anchor)


# Reload: tilt the gun over to show the side and drop it (0-25%), mag out
# jolt (35%), mag in slap (60%), back up (75-100%) with a rack at 85%.
# Returns [position offset, rotation offset].
func _reload_pose(delta: float) -> PackedVector3Array:
	if _reload_t < 0.0:
		return PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	_reload_t += delta
	var p := _reload_t / _reload_len
	if p >= 1.0:
		_reload_t = -1.0
		return PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var env := smoothstep(0.0, 0.25, p) * (1.0 - smoothstep(0.75, 1.0, p))
	var beats := [0.35, 0.6, 0.85]
	if _reload_beats < beats.size() and p >= beats[_reload_beats]:
		match _reload_beats:
			0: _kick_pos_vel += Vector3(0.0, -0.9, 0.0) # mag out
			1: # mag in: a hard upward slap
				_kick_pos_vel += Vector3(0.0, 1.4, 0.0)
				_kick_rot_vel += Vector3(deg_to_rad(140.0), 0.0, deg_to_rad(-60.0))
			2: _kick_pos_vel += Vector3(0.0, 0.0, 1.6) # rack
		_reload_beats += 1
	return PackedVector3Array([Vector3(-0.04, -0.09, 0.05) * env,
			Vector3(deg_to_rad(12.0), deg_to_rad(8.0), deg_to_rad(38.0)) * env])


func _spring(delta: float) -> void:
	_kick_pos_vel += (-KICK_STIFFNESS * _kick_pos - KICK_DAMPING * _kick_pos_vel) * delta
	_kick_rot_vel += (-KICK_STIFFNESS * _kick_rot - KICK_DAMPING * _kick_rot_vel) * delta
	_kick_pos += _kick_pos_vel * delta
	_kick_rot += _kick_rot_vel * delta
	_land_vel += (-LAND_STIFFNESS * _land - LAND_DAMPING * _land_vel) * delta
	_land += _land_vel * delta


func _look() -> Vector2:
	return Vector2(play_char.cam_holder.rotation.y, play_char.cam.rotation.x)


static func _blend(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)
