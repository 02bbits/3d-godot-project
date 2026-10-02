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
const RAY_RANGE := 60.0

@export var damage: int = 34
@export var mag_size: int = 24
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
@onready var hit_confirm: CanvasLayer = $HitConfirm
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
	if play_char is CollisionObject3D:
		weapon_ray.add_exception(play_char)

func _process(delta: float) -> void:
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	rotation.x = get_parent().get_parent().rotation.z

func _unhandled_input(event: InputEvent) -> void:
	if play_char.is_remote:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_reload()

func _shoot() -> void:
	if play_char.is_remote or reloading or ammo <= 0 or fire_cooldown > 0.0:
		return
	var mods: ModifierManager = play_char.get_node_or_null("ModifierManager")
	fire_cooldown = fire_interval / mods.get_stat(&"fire_rate", 1.0)
	ammo -= 1

	if ammo == 0:
		_reload()

	weapon_ray.force_raycast_update()
	var muzzle_pos: Vector3 = weapon_ray.global_position
	var aim_target: Vector3
	var collider: Object = null
	if weapon_ray.is_colliding():
		collider = weapon_ray.get_collider()
		aim_target = weapon_ray.get_collision_point()
		play_char.net_hit_normal = weapon_ray.get_collision_normal()
	else:
		aim_target = muzzle_pos - muzzle.global_transform.basis.x * RAY_RANGE
		play_char.net_hit_normal = Vector3.ZERO
	play_char.net_hit_position = aim_target

	_apply_damage(collider)
	# bump the replicated counter last: every peer (this one included) replays
	# the shot visuals via player_character_script._show_fire_effects
	play_char.net_fire_count += 1

# Replayed on every peer when the replicated fire counter increases.
func on_fire_event(hit_position: Vector3) -> void:
	_spawn_tracer(muzzle.global_position, hit_position)
	muzzle_flash.restart()
	flash_light.light_energy = 3.0
	flash_light.visible = true
	var tw := create_tween()
	tw.tween_property(flash_light, "light_energy", 0.0, 0.12)
	tw.tween_callback(func() -> void: flash_light.visible = false)

# Outgoing damage stage of the pipeline: base damage -> attacker modifier
# stats -> attacker hooks (ctx mutation) -> cap. The victim's client owns the
# defensive stage (rpc_take_damage).
func _apply_damage(collider: Object) -> void:
	if collider == null or collider == play_char or not (collider is Node):
		return
	var node := collider as Node
	var hit_player := node.is_in_group("player")
	if not hit_player and not node.is_in_group("enemy"):
		return
	var mods: ModifierManager = play_char.get_node_or_null("ModifierManager")
	var amount := float(damage)
	var ctx := {"amount": amount, "attacker_id": -1, "distance": 0.0, "hit_player": hit_player}
	if Engine.has_singleton("Fusion"):
		ctx["attacker_id"] = Fusion.get_local_player_id()
	ctx["distance"] = (weapon_ray.get_collision_point() - weapon_ray.global_position).length()
	if mods != null:
		mods.on_damage_dealt(ctx)
		var cap: Array = ModifierManager.STAT_CAPS[&"damage"]
		ctx["amount"] = clampf(float(ctx["amount"]), damage * cap[0], damage * cap[1])
	var final_amount := int(roundf(float(ctx["amount"])))
	var hit_pos: Vector3 = weapon_ray.get_collision_point()
	if hit_player:
		Fusion.rpc_to(Fusion.TARGET_OWNER, Callable(collider, "rpc_take_damage"), final_amount, int(ctx["attacker_id"]))
		_feedback_hit(hit_pos, final_amount)
	else:
		# Targets are authoritative on the master client; route the damage so
		# every client sees the same target state.
		Fusion.rpc_to(Fusion.TARGET_OWNER, Callable(node, "rpc_take_damage"), final_amount)
		_feedback_hit(hit_pos, final_amount)

func _feedback_hit(pos: Vector3, amount: int) -> void:
	_spawn_damage_number(pos, amount)
	hit_confirm.show_hit()

func _spawn_damage_number(pos: Vector3, amount: int) -> void:
	var label := Label3D.new()
	label.text = str(amount)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.outline_size = 10
	get_tree().current_scene.add_child(label)
	label.global_position = pos
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position", pos + Vector3.UP * 1.2, 0.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.2)
	tw.chain().tween_callback(label.queue_free)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var bullet := BULLET_SCENE.instantiate() as Node3D
	# tracer visuals spark on the map only; player-hit feedback comes from the
	# hit marker/damage number instead of a body-overlap tracer
	bullet.collision_mask = 1
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = from
	bullet.global_transform = bullet.global_transform.looking_at(to, Vector3.UP)

func _reload() -> void:
	if play_char.is_remote or reloading or ammo >= _effective_mag() or reserve <= 0:
		return
	reloading = true
	_reload_generation += 1
	var generation := _reload_generation
	# replicated counter: every peer replays the reload visual + sound
	play_char.net_reload_count += 1
	# HUD: update ammo counter here
	var mods: ModifierManager = play_char.get_node_or_null("ModifierManager")
	await get_tree().create_timer(reload_time * mods.get_stat(&"reload_time", 1.0)).timeout
	if generation != _reload_generation or not is_inside_tree():
		return
	var taken := mini(_effective_mag() - ammo, reserve)
	ammo += taken
	reserve -= taken
	reloading = false

func _effective_mag() -> int:
	var mods: ModifierManager = play_char.get_node_or_null("ModifierManager")
	return maxi(int(roundf(mag_size * mods.get_stat(&"mag_size", 1.0))), 1)

func reset_for_respawn() -> void:
	_reload_generation += 1
	reloading = false
	ammo = _effective_mag()
	reserve = reserve_max
	fire_cooldown = 0.0
	anim_player.stop()
	muzzle_flash.emitting = false
	flash_light.visible = false
	shoot_sound.stop()
	reload_sound.stop()

func show_kill() -> void:
	hit_confirm.show_kill()


func reload_visual() -> void:
	_play_reload_sound()
	if play_char.has_method("animate_reload"):
		play_char.animate_reload()

func _play_reload_sound() -> void:
	reload_sound.stream = RELOAD_SOUNDS.pick_random()
	reload_sound.pitch_scale = randf_range(0.95, 1.05)
	reload_sound.play()
