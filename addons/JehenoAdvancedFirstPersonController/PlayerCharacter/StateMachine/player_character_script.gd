extends CharacterBody3D

class_name PlayerCharacter

@export_group("Movement variables")
var move_speed: float
var move_accel: float
var move_deccel: float
var input_direction: Vector2
var move_direction: Vector3
var desired_move_speed: float
@export var desired_move_speed_curve: Curve #accumulated speed
@export var max_desired_move_speed: float = 25.5
@export var in_air_move_speed_curve: Curve
@export var hit_ground_cooldown: float = 0.1 #amount of time the character keep his accumulated speed before losing it (while being on ground)
var hit_ground_cooldown_ref: float
@export var bunny_hop_dms_incre: float = 3.0 #bunny hopping desired move speed incrementer
@export var auto_bunny_hop: bool = false
var last_frame_position: Vector3
var last_frame_velocity: Vector3
var was_on_floor: bool
var walk_or_run: String = "WalkState" #keep in memory if play char was walking or running before being in the air
#for states that require visible changes of the model
@export var base_hitbox_height: float = 2.0
@export var base_model_height: float = 1.0
@export var height_change_duration: float = 0.15

@export_group("Idle variables")
@export var idle_deccel: float = 10.0

@export_group("Crouch variables")
@export var crouch_speed: float = 2.0
@export var crouch_accel: float = 6.0
@export var crouch_deccel: float = 8.0
@export var continious_crouch: bool = false #if true, doesn't need to keep crouch button on to crouch
@export var backward_crouch_speed_multiplier : float = 0.7
@export var crouch_hitbox_height: float = 1.2
@export var crouch_model_height: float = 0.6

@export_group("Walk variables")
@export var walk_speed: float = 5.1
@export var walk_accel: float = 8.0
@export var walk_deccel: float = 9.0
@export var backward_walk_speed_multiplier : float = 0.75

@export_group("Run variables")
@export var run_speed: float = 7.65
@export var run_accel: float = 7.0
@export var run_deccel: float = 9.0
@export var continious_run: bool = false #if true, doesn't need to keep run button on to run
@export var backward_run_speed_multiplier : float = 0.7

@export_group("Jump variables")
@export var jump_height: float = 1.7
@export var jump_time_to_peak: float = 0.3
@export var jump_time_to_fall: float = 0.25
@onready var jump_velocity: float = (2.0 * jump_height) / jump_time_to_peak
@export var jump_cooldown: float = 0.25
var jump_cooldown_ref: float
@export var nb_jumps_in_air_allowed: int = 1
var nb_jumps_in_air_allowed_ref: int
var jump_buff_on: bool = false
var buffered_jump: bool = false
@export var coyote_jump_cooldown: float = 0.3
var coyote_jump_cooldown_ref: float
var coyote_jump_on: bool = false
var released_input_in_air: bool = false

@export_group("Slide variables")
var slide_direction: Vector3 = Vector3.ZERO
@export var use_desired_move_speed: bool = false
@export var slide_speed: float = 8.2
@export var slide_accel: float = 23.0
@export var slide_time: float = 1.2
var slide_time_ref: float
@export var time_bef_can_slide_again: float = 0.2
var time_bef_can_slide_again_ref: float
@export_range(0.0, 90.0, 0.1) var max_slope_angle: float = 75.0 #max slope angle where the slide time operate
@export_range(0.0, 0.1, 0.001) var uphill_tolerance : float = 0.05 #vertical tolerance, to avoid fake uphills
@export var amount_velocity_lost_per_sec: float = 4.0
@export var slope_sliding_dms_incre: float = 2.0 #slope sliding desired move speed incrementer
@export var slope_sliding_ms_incre: float = 2.0 #slope sliding slide speed incrementer
@export var priority_over_crouch: bool = true #if enabled, give priority over crouch state (because crouch and slide actions are assigned at the same input action)
@export var continious_slide: bool = true
var slide_buff_on: bool = false
@export var slide_hitbox_height: float = 1.0
@export var slide_model_height: float = 0.5

@export_group("Dash variables")
var dash_direction: Vector3 = Vector3.ZERO
@export var dash_speed: float = 34.0
@export var dash_time: float = 0.1
var dash_time_ref: float
@export var nb_dashs_allowed: int = 1
var nb_dashs_allowed_ref: int
@export var time_bef_can_dash_again: float = 0.8
var time_bef_can_dash_again_ref: float
@export var time_bef_reload_dash: float = 3.0
var time_bef_reload_dash_ref: float
var velocity_pre_dash : Vector3
var has_dashed : bool = false

@export_group("Wallrun variables")
var can_wallrun : bool = true
var side_check_raycast_collided : int = 0 #if -1, left side, if 1, right side
var last_wallrunned_wall_out_of_time : int = 0 #if -1, left side, if 1, right side
var wall_normal : Vector3 = Vector3.ZERO
var wall_forward_dir : Vector3 = Vector3.ZERO
@export var use_desired_move_speed_wallrun : bool = false
@export var wallrun_speed : float = 9.65
@export var wallrun_accel : float = 2.3
@export var wallrun_deccel : float = 7.0
@export_range(0.0, 1.0, 0.001) var wallrun_fall_gravity_multiplier : float = 0.08
@export var wallrun_time : float = 3.5
var wallrun_time_ref : float
@export var infinite_wallrun_time : bool = false
@export var time_bef_can_wallrun_again : float = 0.2
var time_bef_can_wallrun_again_ref : float
@export var wallrunning_dms_incre : float = 1.0

@export_group("Walljump variables")
var about_to_jump_vel : Vector3
@export var walljump_push_force : float = 11.9
@export var walljump_y_velocity : float = 7.65
@export var walljump_lock_in_air_movement_time : float = 0.15
var walljump_lock_in_air_movement_time_ref : float

@export_group("Health variables")
@export var max_health: float = 100.0
var health: float
var dead: bool = false
var restart_pending: bool = false
var is_remote: bool = false #true when this instance is a networked copy we don't control
var view_yaw: float = 0.0 #replicated camera yaw (radians), owner writes / remote reads
var view_pitch: float = 0.0 #replicated camera pitch (radians), owner writes / remote reads

@export_group("Stamina variables")
@export var stamina_max: float = 100.0
@export var stamina_drain: float = 15.0
@export var stamina_drop_speed: float = 1.0
@export var stamina_drop_forgive_range: float = 5.0	# a stamina gap that the system will forgive before dropping (action does not need strictly the exact amount of stamina to perform)
@export var stamina_regen: float = 15.0
@export var stamina_regen_delay: float = 0.7
@export var double_jump_stamina_cost: float = 20.0
@export var dash_stamina_cost: float = 10.0
var stamina: float
var _stamina_regen_timer: float = 0.0

@export_group("Gravity variables")
@onready var jump_gravity: float = (-2.0 * jump_height) / (jump_time_to_peak * jump_time_to_peak)
@onready var fall_gravity: float = (-2.0 * jump_height) / (jump_time_to_fall * jump_time_to_fall)

@export_group("Keybind variables")
@export var move_forward_action: StringName = "play_char_move_forward_action"
@export var move_backward_action: StringName = "play_char_move_backward_action"
@export var move_left_action: StringName = "play_char_move_left_ation"
@export var move_right_action: StringName = "play_char_move_right_action"
@export var run_action: StringName = "play_char_run_action"
@export var crouch_action: StringName = "play_char_crouch_action"
@export var jump_action: StringName = "play_char_jump_action"
@export var slide_action: StringName = "play_char_slide_action"
@export var dash_action: StringName = "play_char_dash_action"
@onready var input_actions_list : Array[StringName] = [move_forward_action, move_backward_action, move_left_action, move_right_action,
run_action, crouch_action, jump_action, slide_action, dash_action]
@export var check_on_ready_if_inputs_registered : bool = true
var default_input_actions : Dictionary

#references variables
@onready var cam_holder: Node3D = $CameraHolder
@onready var cam: Camera3D = %Camera
@onready var weapon: Node = $CameraHolder/Camera/Weapon
@onready var model: MeshInstance3D = $Model
@onready var hitbox: CollisionShape3D = $Hitbox
@onready var state_machine: Node = $StateMachine
@onready var hud: CanvasLayer = $HUD
@onready var death_screen: Control = %DeathScreen
@onready var ceiling_check: RayCast3D = %CeilingCheck
@onready var floor_check: RayCast3D = %FloorCheck
@onready var wallrun_floor_check : RayCast3D = %WallrunFloorCheck
@onready var slide_floor_check: RayCast3D = %SlideFloorCheck
@onready var left_wall_check : RayCast3D = %LeftWallCheck
@onready var right_wall_check : RayCast3D = %RightWallCheck

func _ready() -> void:
	#set and value references
	health = max_health
	stamina = stamina_max
	hit_ground_cooldown_ref = hit_ground_cooldown
	jump_cooldown_ref = jump_cooldown
	nb_jumps_in_air_allowed_ref = nb_jumps_in_air_allowed
	coyote_jump_cooldown_ref = coyote_jump_cooldown
	slide_time_ref = slide_time
	time_bef_can_slide_again_ref = time_bef_can_slide_again
	time_bef_can_slide_again = -1.0
	time_bef_can_dash_again_ref = time_bef_can_dash_again
	time_bef_can_dash_again = -1.0
	time_bef_reload_dash_ref = time_bef_reload_dash
	time_bef_reload_dash = -1.0
	nb_dashs_allowed_ref = nb_dashs_allowed
	wallrun_time_ref = wallrun_time
	time_bef_can_wallrun_again_ref = time_bef_can_wallrun_again
	walljump_lock_in_air_movement_time_ref = walljump_lock_in_air_movement_time
	walljump_lock_in_air_movement_time = -1.0

	build_default_keybinding()
	input_actions_check()
	setup_network_control()

func build_default_keybinding() -> void:
	#build it in runtime to ensure that export variables have been set
	default_input_actions = {
		move_forward_action : [Key.KEY_W, Key.KEY_UP],
		move_backward_action : [Key.KEY_S, Key.KEY_DOWN],
		move_left_action : [Key.KEY_A, Key.KEY_LEFT],
		move_right_action : [Key.KEY_D, Key.KEY_RIGHT],
		run_action : [Key.KEY_SHIFT],
		crouch_action : [Key.KEY_CTRL],
		jump_action : [Key.KEY_SPACE],
		slide_action : [Key.KEY_CTRL],
		dash_action : [Key.KEY_E]
	}

func input_actions_check() -> void:
	#check if the input actions written in the editor are the same as the ones registered in the Input map, and if they are written correctly
	#if not, add it to runtime Input map with default keybindings
	if check_on_ready_if_inputs_registered:
		var registered_input_actions: Array[StringName] = []
		for input_action in InputMap.get_actions():
			if input_action.begins_with(&"play_char_"):
				registered_input_actions.append(input_action)

		for input_action in input_actions_list:
			if input_action == &"":
				assert(false, "There's an undefined input action")

			if not registered_input_actions.has(input_action):
				var key_names = default_input_actions[input_action].map(func(key):
					return OS.get_keycode_string(key)
				)

				push_warning("'{input}' missing in InputMap, or input action wrongly named in the editor.\nAdding the '{input}' to runtime InputMap temporarily with the key/s: {keys}"
				.format({"input": input_action, "keys": String(", ").join(key_names)}))

				InputMap.add_action(input_action)
				for keycode in default_input_actions[input_action]:
					var input_event_key = InputEventKey.new()
					input_event_key.physical_keycode = keycode
					InputMap.action_add_event(input_action, input_event_key)

func _process(delta: float) -> void:
	wallrun_timer(delta)

	slide_timer(delta)

	dash_timer(delta)

	jump_timer(delta)

	stamina_tick(delta)

	network_view_sync()

func network_view_sync() -> void:
	if is_remote:
		cam_holder.rotation.y = view_yaw
		cam.rotation.x = view_pitch
	else:
		view_yaw = cam_holder.rotation.y
		view_pitch = cam.rotation.x

func _physics_process(_delta: float) -> void:
	modify_physics_properties()

	move_and_slide()

func jump_timer(delta : float) -> void:
	if jump_cooldown > 0.0:
		jump_cooldown -= delta

func wallrun_timer(delta : float) -> void:
	if !can_wallrun:
		if time_bef_can_wallrun_again > 0.0: time_bef_can_wallrun_again -= delta
		else:
			#can only reset capacity of wallrunning when not currently wallrunning
			if state_machine.curr_state_name != "Wallrun":
				wallrun_time = wallrun_time_ref
				can_wallrun = true

func slide_timer(delta: float) -> void:
	if time_bef_can_slide_again > 0.0: time_bef_can_slide_again -= delta
	else:
		#can only reset slide time when not sliding
		if state_machine.curr_state_name != "Slide":
			slide_time = slide_time_ref

func dash_timer(delta: float) -> void:
	#reloads dash every *timeBefReloadDash* time, to avoid dash spamming
	#if you want to be able to spam dashes, set timeBefReloadDash to 0.0
	if nb_dashs_allowed < nb_dashs_allowed_ref:
		if time_bef_reload_dash > 0.0: time_bef_reload_dash -= delta
		else:
			time_bef_reload_dash = time_bef_reload_dash_ref
			nb_dashs_allowed += 1

	if time_bef_can_dash_again > 0.0: time_bef_can_dash_again -= delta
	else:
		#can only reset dash time when not dashing
		if state_machine.curr_state_name != "Dash":
			dash_time = dash_time_ref

func modify_physics_properties() -> void:
	last_frame_position = global_position #get play char global position every frame
	last_frame_velocity = velocity #get play char velocity every frame
	was_on_floor = !is_on_floor() #check if play char was on floor every frame

func stamina_tick(delta: float) -> void:
	if dead:
		return
	if state_machine.curr_state_name in ["Run", "Jump", "Wallrun"]:
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		_stamina_regen_timer = stamina_regen_delay
		if stamina <= 0.0:
			# HUD: add "stamina exhausted" cue here
			state_machine.curr_state.transitioned.emit(state_machine.curr_state, "WalkState")
	elif _stamina_regen_timer > 0.0:
		_stamina_regen_timer -= delta
	elif stamina < stamina_max:
		stamina = minf(stamina + stamina_regen * delta, stamina_max)

func consume_stamina(amount: float) -> bool:
	var target_stamina = maxf(stamina - amount, 0.0)
	if stamina < amount - stamina_drop_forgive_range:
		return false
	stamina = target_stamina
	_stamina_regen_timer = stamina_regen_delay
	return true

func can_dash() -> bool:
	return time_bef_can_dash_again <= 0.0 and nb_dashs_allowed > 0 and consume_stamina(dash_stamina_cost)

func has_wallrun_momentum() -> bool:
	return Vector2(velocity.x, velocity.z).length() >= run_speed

func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(health - minf(amount, max_health), 0.0)
	# HUD: update health bar here
	if health <= 0.0:
		_die()

@rpc("any_peer")
func rpc_take_damage(amount: int) -> void:
	# ponytail: shared-authority damage remains client-trusted; move hit validation
	# to Fusion Client-Server authority before shipping competitive play.
	if is_remote:
		return
	take_damage(clampf(float(amount), 0.0, max_health))

@rpc("any_peer")
func shot_fx(from: Vector3, dir: Vector3) -> void:
	if is_remote and not dead:
		weapon.fire_visual(from, dir)

@rpc("any_peer")
func reload_fx() -> void:
	if is_remote and not dead:
		weapon.reload_visual()

@rpc("any_peer")
func died_fx() -> void:
	if is_remote:
		dead = true
		_set_dead_visuals()

@rpc("any_peer")
func respawn_fx() -> void:
	if is_remote:
		dead = false
		_set_dead_visuals()

func _die() -> void:
	if dead:
		return
	dead = true
	_set_dead_visuals()
	if Engine.has_singleton("Fusion") and Fusion.is_in_room():
		Fusion.rpc(Callable(self, "died_fx"))
	set_physics_process(false)
	state_machine.set_process(false)
	state_machine.set_physics_process(false)
	cam_holder.set_process(false)
	cam_holder.set_process_unhandled_input(false)
	weapon.set_process(false)
	weapon.set_process_unhandled_input(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not is_remote:
		death_screen.visible = true

func request_restart() -> void:
	if is_remote or not dead or restart_pending:
		return
	restart_pending = true
	var world: Node = get_tree().current_scene
	if world == null or not world.has_method("respawn_player"):
		world = get_tree().root.find_child("World", true, false)
	if world != null and world.has_method("respawn_player"):
		world.respawn_player(self)
	else:
		restart_failed()

func restart_failed() -> void:
	restart_pending = false
	var restart_button := death_screen.get_node_or_null("Center/V/RestartButton") as Button
	if restart_button != null:
		restart_button.disabled = false

func reset_for_respawn(spawn_transform: Transform3D) -> void:
	if is_remote:
		return
	restart_pending = false
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	health = max_health
	stamina = stamina_max
	_stamina_regen_timer = 0.0
	input_direction = Vector2.ZERO
	move_direction = Vector3.ZERO
	desired_move_speed = 0.0
	walk_or_run = "WalkState"
	hit_ground_cooldown = hit_ground_cooldown_ref
	jump_cooldown = -1.0
	nb_jumps_in_air_allowed = nb_jumps_in_air_allowed_ref
	coyote_jump_cooldown = coyote_jump_cooldown_ref
	slide_time = slide_time_ref
	time_bef_can_slide_again = -1.0
	dash_time = dash_time_ref
	time_bef_can_dash_again = -1.0
	time_bef_reload_dash = -1.0
	nb_dashs_allowed = nb_dashs_allowed_ref
	has_dashed = false
	can_wallrun = true
	wallrun_time = wallrun_time_ref
	time_bef_can_wallrun_again = time_bef_can_wallrun_again_ref
	last_wallrunned_wall_out_of_time = 0
	dead = false
	if state_machine.curr_state != null:
		state_machine.curr_state.exit()
	var idle: State = state_machine.states.get("idle")
	if idle != null:
		idle.enter(self)
		state_machine.curr_state = idle
		state_machine.curr_state_name = idle.state_name
	if weapon.has_method("reset_for_respawn"):
		weapon.reset_for_respawn()
	_set_dead_visuals()
	if Engine.has_singleton("Fusion") and Fusion.is_in_room():
		Fusion.rpc(Callable(self, "respawn_fx"))
	set_physics_process(true)
	state_machine.set_process(true)
	state_machine.set_physics_process(true)
	cam_holder.set_process(true)
	cam_holder.set_process_input(true)
	cam_holder.set_process_unhandled_input(true)
	weapon.set_process(true)
	weapon.set_process_input(true)
	weapon.set_process_unhandled_input(true)
	cam.current = true
	hud.visible = true
	death_screen.visible = false
	var restart_button := death_screen.get_node_or_null("Center/V/RestartButton") as Button
	if restart_button != null:
		restart_button.disabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _set_dead_visuals() -> void:
	model.visible = not dead
	weapon.visible = not dead
	hitbox.disabled = dead

func setup_network_control() -> void:
	var rep: Node = find_child("FusionSharedReplicator", true, false)
	if rep == null:
		return
	is_remote = not rep.has_authority()
	if not is_remote:
		return
	# remote copy: nobody controls it locally. Move/state/physics stay off, but
	# _process must keep running to apply the replicated view_yaw/view_pitch
	# to the camera holder + camera so the visible weapon tracks the owner's aim.
	set_physics_process(false)
	state_machine.set_process(false)
	state_machine.set_physics_process(false)
	cam.current = false
	cam_holder.set_process(false)
	cam_holder.set_process_input(false)
	weapon.set_process(false)
	weapon.set_process_input(false)
	hud.visible = false
	# this copy is rendered by OTHER clients' cameras (layer 1): the capsule
	# must be on their layer; the gun stays visible so others see the aim
	model.layers = 1
	if model.material_override is StandardMaterial3D:
		model.material_override = model.material_override.duplicate()
		model.material_override.albedo_color = Color(1.0, 0.25, 0.25)

func gravity_apply(delta: float) -> void:
	# if play char goes up, apply jump gravity
	#otherwise, apply fall gravity
	if not is_on_floor(): #no need to push play char if he's already on the floor
		if velocity.y >= 0.0: velocity.y += jump_gravity * delta
		elif velocity.y < 0.0: velocity.y += fall_gravity * delta

#use of 2 tweens to change the hitbox and model heights, relative to a specific state
func tween_hitbox_height(state_hitbox_height : float) -> void:
	var hitbox_tween: Tween = create_tween()
	if hitbox != null:
		hitbox_tween.tween_method(func(v): set_hitbox_height(v), hitbox.shape.height,
		state_hitbox_height, height_change_duration)
	#to avoid "no tweeners" error
	else:
		hitbox_tween.tween_interval(0.1)
	hitbox_tween.finished.connect(Callable(hitbox_tween, "kill"))

func set_hitbox_height(value: float) -> void:
	if hitbox.shape is CapsuleShape3D:
		hitbox.shape.height = value

func tween_model_height(state_model_height : float) -> void:
	var model_tween: Tween = create_tween()
	if model != null:
		model_tween.tween_property(model, "scale:y",
		state_model_height, height_change_duration)
	#to avoid "no tweeners" error
	else:
		model_tween.tween_interval(0.1)
	model_tween.finished.connect(Callable(model_tween, "kill"))
