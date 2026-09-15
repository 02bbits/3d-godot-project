extends Node3D

const BULLET_SCENE = preload("res://scenes/entities/bullet.tscn")
const SHOOT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/laserLarge_000.ogg"),
	preload("res://assets/audio/laserLarge_001.ogg"),
	preload("res://assets/audio/laserLarge_002.ogg"),
]
const RELOAD_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/metalLatch.ogg"),
	preload("res://assets/audio/metalClick.ogg"),
]

@export var mag_size: int = 30
@export var reserve_max: int = 999 # INFINITE AMMO FOR DEBUGGING
@export var fire_interval: float = 0.15
@export var reload_time: float = 1.2

@onready var muzzle: Marker3D = $Muzzle
@onready var weapon_ray: RayCast3D = $Muzzle/WeaponRaycast
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var muzzle_flash: GPUParticles3D = $Muzzle/MuzzleFlash
@onready var flash_light: OmniLight3D = $Muzzle/FlashLight
@onready var shoot_sound: AudioStreamPlayer3D = $ShootSound
@onready var reload_sound: AudioStreamPlayer3D = $ReloadSound
@onready var play_char: Node3D = get_parent().get_parent().get_parent()

var ammo: int
var reserve: int
var reloading: bool = false
var fire_cooldown: float = 0.0
var _reload_generation := 0
var camera: Camera3D

func _ready() -> void:
	ammo = mag_size
	reserve = reserve_max
	camera = get_parent() as Camera3D

func _process(delta: float) -> void:
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	rotation.x = get_parent().get_parent().rotation.z

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_reload()

func _shoot() -> void:
	if reloading or ammo <= 0 or fire_cooldown > 0.0:
		return
	fire_cooldown = fire_interval
	ammo -= 1
	anim_player.play("shoot")
	
	if ammo == 0:
		_reload()
	
	# HUD: update ammo counter here

	weapon_ray.force_raycast_update()
	var muzzle_pos: Vector3 = weapon_ray.global_position
	var aim_target: Vector3
	if weapon_ray.is_colliding():
		aim_target = weapon_ray.get_collision_point()
	else:
		# ponytail: muzzle sits at gun local -X (camera forward); hardcoded 60m range, matching raycast target_position in gun.tscn
		aim_target = muzzle_pos - muzzle.global_transform.basis.x * 60.0
	var aim_fwd: Vector3 = (aim_target - muzzle_pos).normalized()

	_spawn_bullet(muzzle_pos, aim_target, false)
	_play_fire_fx()
	_route_fx("shot_fx", [muzzle_pos, aim_fwd])

# fired on remote replicas via the shot_fx RPC; the shooter already ran the
# local path above, so remote copies only mirror the visuals
func fire_visual(from: Vector3, dir: Vector3) -> void:
	anim_player.play("shoot")
	_spawn_bullet(from, from + dir * 60.0, true)
	_play_fire_fx()

func _spawn_bullet(from: Vector3, to: Vector3, visual_only: bool) -> void:
	var bullet := BULLET_SCENE.instantiate() as Node3D
	bullet.visual_only = visual_only
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = from
	bullet.global_transform = bullet.global_transform.looking_at(to, Vector3.UP)

func _play_fire_fx() -> void:
	muzzle_flash.restart()
	flash_light.light_energy = 3.0
	flash_light.visible = true
	var tw := create_tween()
	tw.tween_property(flash_light, "light_energy", 0.0, 0.12)
	tw.tween_callback(func() -> void: flash_light.visible = false)
	shoot_sound.stream = SHOOT_SOUNDS.pick_random()
	shoot_sound.pitch_scale = randf_range(0.95, 1.05)
	shoot_sound.play()

func _route_fx(fx: String, args: Array = []) -> void:
	if Engine.has_singleton("Fusion") and Fusion.is_in_room():
		Fusion.callv("rpc", [Callable(play_char, fx)] + args)

func _reload() -> void:
	if reloading or ammo >= mag_size or reserve <= 0:
		return
	reloading = true
	_reload_generation += 1
	var generation := _reload_generation
	anim_player.play("reload")
	_play_reload_sound()
	_route_fx("reload_fx")
	# HUD: update ammo counter here
	await get_tree().create_timer(reload_time).timeout
	anim_player.play("RESET")
	if generation != _reload_generation or not is_inside_tree():
		return
	var taken := mini(mag_size - ammo, reserve)
	ammo += taken
	reserve -= taken
	reloading = false

func reset_for_respawn() -> void:
	_reload_generation += 1
	reloading = false
	ammo = mag_size
	reserve = reserve_max
	fire_cooldown = 0.0
	anim_player.stop()
	muzzle_flash.emitting = false
	flash_light.visible = false
	shoot_sound.stop()
	reload_sound.stop()

func reload_visual() -> void:
	anim_player.play("reload")
	_play_reload_sound()

func _play_reload_sound() -> void:
	reload_sound.stream = RELOAD_SOUNDS.pick_random()
	reload_sound.pitch_scale = randf_range(0.95, 1.05)
	reload_sound.play()
