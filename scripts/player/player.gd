extends CharacterBody3D

class_name PlayerCharacter

signal network_ready

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
@export var idle_deccel: float = 5.0

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
@export var walk_deccel: float = 13.0
@export var backward_walk_speed_multiplier : float = 0.75

@export_group("Run variables")
@export var run_speed: float = 7.65
@export var run_accel: float = 7.0
@export var run_deccel: float = 13.0
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
@export var dash_speed: float = 64.0
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
var health: float:
	get:
		return $Health.health
	set(value):
		$Health.health = value
var dead: bool = false
var restart_pending: bool = false
var is_remote: bool = false #true when this instance is a networked copy we don't control
var network_role_ready: bool = false #role resolved by setup_network_control
var view_yaw: float = 0.0 #replicated camera yaw (radians), owner writes / remote reads
var view_pitch: float = 0.0 #replicated camera pitch (radians), owner writes / remote reads
var body_yaw: float = 0.0 #replicated torso facing (radians); lags view_yaw so the neck stays realistic

# Replicated player state (starter-style event counters). Setters run on every
# peer: the authority when it changes a value, replicas when the value arrives.
var net_nickname: String = "":
	set(value):
		net_nickname = value
		if is_node_ready() and nickname_label != null:
			nickname_label.text = value
var net_fire_count: int = 0:
	set(value):
		var previous := net_fire_count
		net_fire_count = value
		if is_node_ready() and value > previous and not dead:
			_show_fire_effects()
var net_reload_count: int = 0:
	set(value):
		var previous := net_reload_count
		net_reload_count = value
		if is_node_ready() and value > previous and not dead:
			weapon.reload_visual()
var net_hit_count: int = 0:
	set(value):
		var previous := net_hit_count
		net_hit_count = value
		if is_node_ready() and value > previous:
			_show_hit()
var net_dash_count: int = 0:
	set(value):
		var previous := net_dash_count
		net_dash_count = value
		if is_node_ready() and value > previous:
			movement_state_machine.travel("Dash")
var net_crouched: bool = false
var net_jump_count: int = 0:
	set(value):
		var previous := net_jump_count
		net_jump_count = value
		if is_node_ready() and value > previous:
			_show_jump()
var net_land_count: int = 0:
	set(value):
		var previous := net_land_count
		net_land_count = value
		if is_node_ready() and value > previous:
			_show_land()
var net_is_grounded: bool = false
var net_hit_position: Vector3 = Vector3.ZERO
var net_hit_normal: Vector3 = Vector3.ZERO

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

@export_group("Visuals")
@export var impact_effect: PackedScene
@export var death_effect: PackedScene
@export var head_meshes: Array[MeshInstance3D] = []

@export_group("Head tracking")
@export_range(0.0, 180.0, 1.0) var head_yaw_limit_degrees: float = 80.0 #neck turn before the torso follows
@export var body_turn_smoothing: float = 8.0
@export_range(0.0, 5.0, 0.01) var shot_body_turn_duration: float = 0.0 #torso aligns to the aim when firing
var _shot_turn_tween: Tween

#references variables
@onready var cam_holder: Node3D = $CameraHolder
@onready var cam: Camera3D = %Camera
@onready var weapon: Node = $CameraHolder/Camera/Weapon
@onready var model: Node3D = $VisualRoot/ScalingRoot
@onready var visual_root: Node3D = $VisualRoot
@onready var nickname_label: Label3D = $VisualRoot/NicknameLabel
@onready var pistol: Node3D = $VisualRoot/HandAttachement/Pistol
@onready var pistol_muzzle_flash: GPUParticles3D = $VisualRoot/HandAttachement/Pistol/MuzzleFlash
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var weapon_state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/Alive/Weapon/playback")
@onready var movement_state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/Alive/Movement/playback")
@onready var head_look: LookAtModifier3D = $VisualRoot/ScalingRoot/PlayerModel/Rig_Medium/Skeleton3D/HeadLook
@onready var jump_sound: AudioStreamPlayer3D = $Sounds/JumpSound
@onready var land_sound: AudioStreamPlayer3D = $Sounds/LandSound
@onready var fire_sound: AudioStreamPlayer3D = $Sounds/FireSound
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
	$Health.max_health = max_health
	health = max_health
	$Health.died.connect(_die)
	$Health.damaged.connect(_on_damaged)
	$Health.health_changed.connect(_on_health_changed)
	$RespawnTimer.timeout.connect(request_restart)
	nickname_label.text = net_nickname
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
	# The crouch ray starts below the crouched capsule, so without this it hits
	# the player's own body and blocks stand-up/jump forever (stuck crouch).
	ceiling_check.add_exception(self)
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

	network_view_sync(delta)

	_animate_locomotion(delta)

# Squash/stretch is applied only on remote players (local is first person);
# it always decays back to one. Locomotion blends the animation tree in local
# space so strafing/backpedal read correctly.
func _animate_locomotion(delta: float) -> void:
	if dead:
		return
	visual_root.scale = visual_root.scale.lerp(Vector3.ONE, delta * 8)

	# blend in the model's facing space (already yawed by view_yaw); remote
	# copies have no state machine so fall back to the run speed as reference
	var local_vel := visual_root.global_transform.basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	var speed_ref := maxf(move_speed if not is_remote else run_speed, 0.01)
	var target_blend := Vector2(local_vel.x, local_vel.z) / speed_ref
	var last_blend: Vector2 = animation_tree.get("parameters/Alive/Movement/Locomotion/blend_position")
	animation_tree.set("parameters/Alive/Movement/Locomotion/blend_position",
		last_blend.lerp(target_blend, delta * 12))

func network_view_sync(delta: float) -> void:
	if is_remote:
		cam_holder.rotation.y = view_yaw
		cam.rotation.x = view_pitch
	else:
		view_yaw = cam_holder.rotation.y
		view_pitch = cam.rotation.x
		_update_body_yaw(delta)
	# the visible model faces body_yaw; the head (LookAtModifier3D) covers the
	# remaining angle up to the neck limit on every peer
	visual_root.rotation.y = body_yaw

func _update_body_yaw(delta: float) -> void:
	# a shot turn owns the torso until it finishes
	if _shot_turn_tween != null and _shot_turn_tween.is_valid() and _shot_turn_tween.is_running():
		return
	# past the neck limit the torso catches up until the head can aim again
	var limit := deg_to_rad(head_yaw_limit_degrees)
	var offset := angle_difference(body_yaw, view_yaw)
	if absf(offset) <= limit:
		return
	var target := view_yaw - signf(offset) * limit
	body_yaw = lerp_angle(body_yaw, target, clampf(body_turn_smoothing * delta, 0.0, 1.0))

func turn_body_to_aim() -> void:
	# firing commits the torso to where the head is aiming
	if is_remote:
		return
	if _shot_turn_tween != null and _shot_turn_tween.is_valid():
		_shot_turn_tween.kill()
	var from := body_yaw
	var target := cam_holder.rotation.y
	_shot_turn_tween = create_tween()
	_shot_turn_tween.tween_method(
		func(t: float) -> void: body_yaw = lerp_angle(from, target, t),
		0.0, 1.0, shot_body_turn_duration)

func _physics_process(_delta: float) -> void:
	modify_physics_properties()

	move_and_slide()

	_track_ground_state()

# Owner-side ground/jump/land detection feeding the replicated event counters
# (remote copies replay the sounds and animations through the setters).
func _track_ground_state() -> void:
	var grounded := is_on_floor()
	if grounded and not net_is_grounded:
		net_land_count += 1
	elif not grounded and net_is_grounded and velocity.y > 1.0:
		net_jump_count += 1
	net_is_grounded = grounded

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
			var exhausted_state := "WalkState" if is_on_floor() else "InairState"
			state_machine.curr_state.transitioned.emit(state_machine.curr_state, exhausted_state)
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

func take_damage(amount: float, attacker_id: int = -1) -> void:
	if dead or amount <= 0.0:
		return
	# Defensive stage of the damage pipeline: mods may mutate the ctx (e.g.
	# Second Wind), then the damage-taken cap is applied before Health.
	var ctx := {"amount": amount, "attacker_id": attacker_id}
	var mods: ModifierManager = get_node_or_null("ModifierManager")
	if mods != null:
		mods.on_damage_taken(ctx)
		var cap: Array = ModifierManager.STAT_CAPS[&"damage_taken"]
		ctx["amount"] = clampf(float(ctx["amount"]), max_health * cap[0], max_health * cap[1])
	# Health node owns the number and emits died(attacker_id); that signal
	# routes here for the death broadcast + visuals
	$Health.apply(float(ctx["amount"]), attacker_id)

@rpc("any_peer")
func rpc_take_damage(amount: int, attacker_id: int = -1) -> void:
	# ponytail: shared-authority damage remains client-trusted; move hit validation
	# to Fusion Client-Server authority before shipping competitive play.
	if is_remote:
		return
	take_damage(clampf(float(amount), 0.0, max_health), attacker_id)


@rpc("any_peer")
func rpc_draft_pick(index: int, use_reroll: bool = false) -> void:
	# runs on the master's replica of the picking player (intentionally not
	# gated on is_remote — that is exactly where it must execute); the
	# requester id comes from the replica's owner, so a client can only ever
	# pick for itself
	var rep: Node = find_child("FusionSharedReplicator", true, false)
	if rep == null or not rep.has_method("get_owner_id"):
		return
	var requester := int(rep.get_owner_id())
	var dm: Node = get_tree().get_first_node_in_group("draft_manager")
	if dm != null and dm.has_method("register_pick"):
		dm.register_pick(requester, index, use_reroll)

func _show_fire_effects() -> void:
	turn_body_to_aim()
	pistol_muzzle_flash.restart()
	fire_sound.play()
	weapon_state_machine.travel("Fire")
	if weapon != null and weapon.has_method("on_fire_event"):
		weapon.on_fire_event(net_hit_position)
	if net_hit_normal != Vector3.ZERO and impact_effect != null:
		var impact := impact_effect.instantiate() as Node3D
		get_tree().root.add_child(impact)
		impact.global_position = net_hit_position
		impact.look_at(cam.global_transform.origin, Vector3.UP, true)

func _show_jump() -> void:
	if is_remote:
		visual_root.scale = Vector3(0.75, 1.2, 0.75)
	jump_sound.play()
	movement_state_machine.travel("Jump")

func _show_land() -> void:
	if is_remote:
		visual_root.scale = Vector3(1.25, 0.75, 1.25)
	land_sound.play()

# Owner-side hit reaction: bumps the replicated counter so every peer replays
# the flinch through the setter.
func _on_damaged(_amount: float, _attacker_id: int) -> void:
	net_hit_count += 1

func _show_hit() -> void:
	if dead:
		return
	var request := "parameters/Alive/HitB/request" if health < max_health * 0.5 \
			else "parameters/Alive/HitA/request"
	animation_tree.set(request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func animate_reload() -> void:
	weapon_state_machine.travel("Reload")

func _on_health_changed(current: float, previous: float) -> void:
	if current <= 0.0 and previous > 0.0 and death_effect != null:
		var effect := death_effect.instantiate() as Node3D
		effect.position = global_position + Vector3.UP
		get_tree().root.add_child(effect)

@rpc("any_peer")
func died_fx(attacker_id: int = -1) -> void:
	if is_remote:
		dead = true
		_set_dead_visuals()
		# every peer routes the death through the Health node so listeners
		# (match scoring, kill feed) see one death event per client
		$Health.died.emit(attacker_id)
		# kill confirmation: every peer gets the broadcast; only the peer whose
		# photon id matches the attacker flashes the kill banner
		if attacker_id >= 0 and Engine.has_singleton("Fusion") \
				and attacker_id == Fusion.get_local_player_id():
			for p in get_tree().get_nodes_in_group("player"):
				if is_instance_valid(p) and not p.is_remote \
						and p.weapon != null and p.weapon.has_method("show_kill"):
					p.weapon.show_kill()
					break

@rpc("any_peer")
func respawn_fx() -> void:
	if is_remote:
		dead = false
		_set_dead_visuals()

func _die(attacker_id: int = -1) -> void:
	if dead:
		return
	dead = true
	if _shot_turn_tween != null and _shot_turn_tween.is_valid():
		_shot_turn_tween.kill()
	head_look.influence = 0.0 # keep the death animation's head pose
	_set_dead_visuals()
	if not is_remote:
		# round-based respawn: automatic after a short death delay
		$RespawnTimer.start()
	if Engine.has_singleton("Fusion") and Fusion.is_in_room():
		Fusion.rpc(Callable(self, "died_fx"), attacker_id)
	set_physics_process(false)
	state_machine.set_process(false)
	state_machine.set_physics_process(false)
	cam_holder.set_process(false)
	cam_holder.set_process_unhandled_input(false)
	weapon.set_process(false)
	weapon.set_process_unhandled_input(false)
	if not is_remote:
		var im: Node = get_tree().get_first_node_in_group("input_mode")
		if im != null and im.has_method("set_mode"):
			im.set_mode(im.Mode.DEATH)
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
	movement_state_machine.start("Locomotion")
	weapon_state_machine.start("Idle")
	head_look.influence = 1.0
	_set_dead_visuals()
	visual_root.scale = Vector3.ONE
	net_is_grounded = false
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
	var im: Node = get_tree().get_first_node_in_group("input_mode")
	if im != null and im.has_method("set_mode"):
		im.set_mode(im.Mode.GAMEPLAY)

func _set_dead_visuals() -> void:
	# remote copies keep the body visible so peers see the death animation;
	# the local body stays hidden behind the death screen
	visual_root.visible = is_remote or not dead
	nickname_label.visible = not dead and is_remote
	weapon.visible = not dead
	hitbox.disabled = dead

func setup_network_control() -> void:
	var rep: Node = find_child("FusionSharedReplicator", true, false)
	if rep == null:
		# no replicator (standalone/test): behave as the local owner
		_apply_network_role(false)
		return
	if rep.has_signal("spawned"):
		rep.spawned.connect(_on_replicator_spawned)
	if rep.has_signal("authority_changed"):
		rep.authority_changed.connect(_on_authority_changed)
	# role may already be known (spawned before _ready)
	_apply_network_role(not rep.has_authority())


func _on_replicator_spawned() -> void:
	var rep: Node = find_child("FusionSharedReplicator", true, false)
	if rep != null and rep.has_method("has_authority"):
		_apply_network_role(not rep.has_authority())


func _on_authority_changed(has_authority: bool) -> void:
	_apply_network_role(not has_authority)


var _role_applied := false


# One path for the network role. Fail closed: a copy only receives local
# input after it is positively identified as the local owner.
func _apply_network_role(remote: bool) -> void:
	if _role_applied and remote == is_remote:
		return
	_role_applied = true
	is_remote = remote
	if remote:
		_disable_remote_copy()
	else:
		_enable_local_copy()


func _enable_local_copy() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_physics_process(true)
	state_machine.set_process(true)
	state_machine.set_physics_process(true)
	cam.current = true
	cam_holder.set_process(true)
	cam_holder.set_process_unhandled_input(true)
	weapon.set_process(true)
	weapon.set_process_unhandled_input(true)
	hud.visible = true
	visual_root.visible = true
	# first person: hide the head meshes from the local camera but keep their
	# shadows, and hide the floating nickname (only other players see it)
	nickname_label.visible = false
	for mesh in head_meshes:
		if mesh != null:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# publish the real spawn pose so the first replication snapshot carries it
	# instead of zeros (avoids a visible aim snap on joining peers)
	view_yaw = cam_holder.rotation.y
	view_pitch = cam.rotation.x
	body_yaw = view_yaw
	network_role_ready = true
	network_ready.emit()


func _disable_remote_copy() -> void:
	# remote copy: nobody controls it locally. Move/state/physics stay off, but
	# _process must keep running to apply the replicated view_yaw/view_pitch
	# to the camera holder + camera so the visible weapon tracks the owner's aim.
	# Godot's physics interpolation must be off so it does not fight the
	# FusionReplicator's root smoothing.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	body_yaw = view_yaw
	set_physics_process(false)
	state_machine.set_process(false)
	state_machine.set_physics_process(false)
	cam.current = false
	cam_holder.set_process(false)
	cam_holder.set_process_input(false)
	cam_holder.set_process_unhandled_input(false)
	weapon.set_process(false)
	weapon.set_process_input(false)
	weapon.set_process_unhandled_input(false)
	hud.visible = false
	# remote copies render the full model for other players' cameras and show
	# the nickname label above the head
	visual_root.visible = true
	nickname_label.visible = true
	for mesh in head_meshes:
		if mesh != null:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
