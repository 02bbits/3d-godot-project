extends CharacterBody3D

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
@export_range(0.0, 1.0, 0.001) var wallrun_fall_gravity_multiplier : float = 0.03
@export var wallrun_time : float = 3.5
var wallrun_time_ref : float
@export var infinite_wallrun_time : bool = false
@export var time_bef_can_wallrun_again : float = 0.2
var time_bef_can_wallrun_again_ref : float
@export var wallrunning_dms_incre : float = 1.0
@export_range(0.0, 90.0, 1.0) var wallrun_model_lean_degrees : float = 16.0 #same lean as the camera
@export var wallrun_model_lean_speed : float = 6.0

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
var is_remote: bool = false #true when this instance is a networked copy we don't control
var network_role_ready: bool = false #role resolved by setup_network_control
var view_yaw: float = 0.0 #replicated camera yaw (radians), owner writes / remote reads
var view_pitch: float = 0.0 #replicated camera pitch (radians), owner writes / remote reads
var body_yaw: float = 0.0 #replicated torso facing (radians); lags view_yaw so the neck stays realistic

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
@export_range(0.0, 180.0, 1.0) var head_yaw_limit_degrees: float = 50.0 #neck turn before the torso follows
@export var body_turn_smoothing: float = 8.0
@export_range(0.0, 180.0, 1.0) var body_turn_fast_degrees: float = 60.0 #aim offset where the torso catch-up sharpens
@export var body_turn_fast_smoothing: float = 22.0
@export_range(0.0, 5.0, 0.01) var shot_body_turn_duration: float = 0.0 #torso aligns to the aim when firing
var _shot_turn_tween: Tween

@export_group("Aim tracking")
@export var arm_target_offset: Vector3 = Vector3(0.25, -0.35, -2.0) #camera-space point the gun hand reaches for
@export var arm_pole_offset: Vector3 = Vector3(0.5, 1.1, 0.3) #torso-space elbow pole position (tune per rig)

#references variables
@onready var cam_holder: Node3D = $CameraHolder
@onready var cam: Camera3D = %Camera
@onready var weapon: Node = $CameraHolder/Camera/Weapon
@onready var phantom_gun: Node3D = $CameraHolder/Camera/PhantomGun
@onready var phantom_muzzle_flash: GPUParticles3D = $CameraHolder/Camera/PhantomGun/MuzzleFlash
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
