extends CharacterBody3D

const WALK_SPEED := 5.5
const RUN_SPEED := 6.5
const SPRINT_SPEED := 8.0
const ACCEL_RAMP_TIME := 3.0
const ACCEL := 34.0
const DECEL := 46.0
const JUMP_VELOCITY := 10.2
const SENSITIVITY := 0.003

const STAMINA_MAX := 100.0
const STAMINA_DRAIN := 20.0
const STAMINA_DRAIN_WALL_JUMP := 10.0
const STAMINA_REGEN := 15.0
const STAMINA_REGEN_DELAY := 1.0

const CROUCH_FRACTION := 0.55
const CROUCH_BLEND_SPEED := 10.0
const CROUCH_SPEED := 3.5
const CROUCH_GRAVITY_MULTIPLIER := 2.5
const SLIDE_BOOST := 2.0
const SLIDE_DECEL := 1.5
const SLIDE_MIN_SPEED := 0.2

const WALL_SLIDE_FALL_SPEED := 2.0
const WALL_JUMP_VELOCITY := 10.0
const WALL_JUMP_PUSH := 5.5

const HEAD_Y := 0.19107687

var health := 100.0
var stamina := 100.0
var dead := false

var _speed_ratio := 0.0
var _prev_move_dir := Vector3.ZERO
var _regen_timer := 0.0
var _crouch_level := 0.0
var _sliding := false
var _wall_normal := Vector3.ZERO
var _wall_sliding := false

@onready var capsule = collision.shape as CapsuleShape3D
@onready var stand_height = capsule.height

var weapon := Weapon.new()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	weapon.setup($Head/Camera3D/Gun/AnimationPlayer, $Head/Camera3D/Gun/RayCast3D, camera)
	hud.update(health, stamina, weapon.ammo, weapon.reserve)


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
			get_tree().reload_current_scene()
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-40), deg_to_rad(60))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if weapon.shoot(get_parent()):
			hud.update(health, stamina, weapon.ammo, weapon.reserve)
	elif event is InputEventKey and event.keycode == KEY_R and event.pressed:
		weapon.reload()
		


func _physics_process(delta: float) -> void:
	weapon.tick(delta)
	_update_crouch(delta)

	if not is_on_floor():
		var gravity := get_gravity()

		if Input.is_action_pressed("crouch"):
			gravity *= CROUCH_GRAVITY_MULTIPLIER

		velocity += gravity * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis = camera.global_basis
	var forward := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var direction := (right * input_dir.x - forward * input_dir.y)
	if direction.length() > 0:
		direction = direction.normalized()

	var sprinting := false
	if Input.is_action_pressed("sprint") \
			and direction.length() > 0.0 \
			and stamina > 0.0 \
			and not _sliding \
			and _crouch_level < 0.5:
		sprinting = true
		_regen_timer = 0.0
		stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
	else:
		_regen_timer += delta
		if _regen_timer >= STAMINA_REGEN_DELAY:
			stamina = minf(stamina + STAMINA_REGEN * delta, STAMINA_MAX)

	camera.fov = lerp(camera.fov, 90.0 if (sprinting or _sliding) else 75.0, delta * 8.0)

	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
		elif _wall_sliding and stamina > 0.0:
			velocity.y = WALL_JUMP_VELOCITY
			velocity += _wall_normal * WALL_JUMP_PUSH
			_wall_sliding = false
			_speed_ratio = 0.0
			_regen_timer = 0.0
			stamina -= STAMINA_DRAIN_WALL_JUMP

	if Input.is_action_just_pressed("crouch") and is_on_floor() and sprinting:
		_sliding = true
		_crouch_level = 1.0
		if direction.length() > 0:
			velocity += direction * SLIDE_BOOST

	if _sliding:
		var h_speed := Vector2(velocity.x, velocity.z).length()
		if h_speed < SLIDE_MIN_SPEED or not is_on_floor():
			_sliding = false

	if _sliding:
		_speed_ratio = 1.0
	elif direction.length() > 0:
		if _prev_move_dir != Vector3.ZERO and direction.dot(_prev_move_dir) < 0.5:
			_speed_ratio = 0.0
		_speed_ratio = minf(_speed_ratio + delta / ACCEL_RAMP_TIME, 1.0)
		_prev_move_dir = direction
	else:
		_speed_ratio = 0.0
		_prev_move_dir = Vector3.ZERO

	var top_speed := SPRINT_SPEED if sprinting else RUN_SPEED
	if _crouch_level >= 0.5:
		top_speed = minf(top_speed, CROUCH_SPEED)
	var target := direction * lerpf(WALK_SPEED, top_speed, _speed_ratio)
	var rate := SLIDE_DECEL if _sliding else (ACCEL if direction.length() > 0 else DECEL)
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)

	if _wall_sliding and velocity.y < 0.0 and stamina > 0.0:
		velocity.y = maxf(velocity.y, -WALL_SLIDE_FALL_SPEED)
		_regen_timer = 0.0
		stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)

	move_and_slide()
	_update_wall_state(direction)
	hud.update(health, stamina, weapon.ammo, weapon.reserve)


func _update_crouch(delta: float) -> void:
	var want := 1.0 if (_sliding or Input.is_action_pressed("crouch")) else 0.0
	_crouch_level = move_toward(_crouch_level, want, delta * CROUCH_BLEND_SPEED)
	var height_drop = stand_height - lerpf(stand_height, stand_height * CROUCH_FRACTION, _crouch_level)
	capsule.height = stand_height - height_drop
	collision.position.y = -height_drop * 0.5
	head.position.y = HEAD_Y - height_drop


func _update_wall_state(direction: Vector3) -> void:
	_wall_sliding = false
	_wall_normal = Vector3.ZERO
	if direction.length() == 0 or is_on_floor() or velocity.y >= 0.0:
		return
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y < 0.3:
			var wall := Vector3(n.x, 0, n.z).normalized()
			if wall.dot(direction) < -0.2:
				_wall_normal = wall
				_wall_sliding = true
				return


func take_damage(amount: float) -> void:
	if dead:
		return
	health = max(health - amount, 0.0)
	hud.update(health, stamina, weapon.ammo, weapon.reserve)
	if health <= 0.0:
		_die()


func _die() -> void:
	dead = true
	set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death()
