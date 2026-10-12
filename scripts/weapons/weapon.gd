extends Node3D

## Shared weapon controller. Every weapon is this scene plus a
## WeaponDefinition resource: stats, viewmodel/world-model scenes, their
## transforms, the muzzle position and sounds all come from the definition, so
## a new weapon never needs changes here or in the player scripts.

const BULLET_SCENE = preload("res://scenes/entities/bullet.tscn")
const HIT_MASK := 7 # map + players + raycast helpers
const VIEWMODEL_LAYER := 4
const VIEWMODEL_MOTION := preload("res://scripts/weapons/viewmodel_motion.gd")

@onready var view_model: Node3D = $ViewModel
@onready var world_model: Node3D = $WorldModel
@onready var muzzle: Marker3D = $Muzzle
@onready var shoot_sound: AudioStreamPlayer3D = $ShootSound
@onready var reload_sound: AudioStreamPlayer3D = $ReloadSound
@onready var hit_confirm: CanvasLayer = $HitConfirm

var definition: WeaponDefinition
var play_char: Node3D
var camera: Camera3D

var ammo: int
var reloading: bool = false
var fire_cooldown: float = 0.0
var _reload_generation := 0
var custom_font = load("res://assets/fonts/lilita_one_regular.ttf")

var _reload_started_ms := 0
var _reload_duration := 1.0
# pivot holding the viewmodel + muzzle; animates sway, tilt, recoil, reload
var _motion: Node3D


func setup(player: Node3D, weapon_definition: WeaponDefinition) -> void:
	play_char = player
	camera = player.cam
	definition = weapon_definition

	if definition.viewmodel_scene != null:
		var vm := definition.viewmodel_scene.instantiate() as Node3D
		vm.transform = definition.viewmodel_transform
		view_model.add_child(vm)
	if definition.world_model_scene != null:
		var wm := definition.world_model_scene.instantiate() as Node3D
		wm.transform = definition.world_model_transform
		world_model.add_child(wm)
	muzzle.transform = definition.muzzle_transform
	# the world model rides the character's hand so other players see it there
	world_model.reparent(player.hand_attachment, false)
	# The viewmodel (and its muzzle) live under the viewmodel camera that
	# renders them, so the gun cannot drift from it when the view turns. The
	# weapon itself stays under the gameplay camera: input never reaches nodes
	# inside the SubViewport.
	_motion = VIEWMODEL_MOTION.new()
	_motion.setup(player, self, definition.viewmodel_transform.origin)
	player.viewmodel_camera.add_child(_motion)
	view_model.reparent(_motion, false)
	muzzle.reparent(_motion, false)
	_set_viewmodel_layers()

	ammo = mag_size()
	update_visibility()


func _process(delta: float) -> void:
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if play_char == null or play_char.is_remote:
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
	fire_cooldown = definition.fire_interval / play_char.mods.get_stat(&"fire_rate", 1.0)
	ammo -= 1
	if ammo == 0:
		_reload()

	# Hitscan through the reticle (screen center) from the camera pose the
	# player is actually looking through: with physics interpolation the
	# rendered view trails the physics-tick transform, so aiming from
	# global_transform drifts off the crosshair while moving or turning.
	var view := camera.get_global_transform_interpolated()
	var cam_origin := view.origin
	var cam_dir := -view.basis.z
	var shot := {"origin": cam_origin, "direction": cam_dir, "range": definition.range,
			"hit": raycast(cam_origin, cam_origin + cam_dir * definition.range)}
	# gun modifiers may retarget the shot (Homing Rounds)
	play_char.mods.on_fire(shot)
	var hit: Dictionary = shot.hit
	var collider: Object = hit.get("collider")
	var hit_pos: Vector3 = hit.get("position", cam_origin + cam_dir * definition.range)
	play_char.net_hit_normal = hit.get("normal", Vector3.ZERO)
	play_char.net_hit_position = hit_pos

	_apply_damage(collider, hit_pos)
	# bump the replicated counter last: every peer (this one included) replays
	# the shot visuals
	play_char.net_fire_count += 1


func raycast(from: Vector3, to: Vector3) -> Dictionary:
	if play_char == null:
		return {}
	var params := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK, [play_char.get_rid()])
	return play_char.get_world_3d().direct_space_state.intersect_ray(params)


# Replayed on every peer when the replicated fire counter increases.
func on_fire_event(hit_position: Vector3) -> void:
	_spawn_tracer(_tracer_origin(), hit_position)
	_flash_models()
	_play_shoot_sound()


# Where the tracer should visibly leave the gun. Remote copies use the
# world-model barrel in the hand. The local viewmodel is drawn by a fixed-FOV
# camera while the gameplay FOV changes (run/dash/zoom), so project the drawn
# muzzle back into the gameplay camera at the same depth.
func _tracer_origin() -> Vector3:
	if play_char.is_remote:
		var flash := world_model.find_child("MuzzleFlash", true, false) as Node3D
		return flash.global_position if flash != null else muzzle.global_position
	var view_cam: Camera3D = play_char.viewmodel_camera
	var screen := view_cam.unproject_position(muzzle.global_position)
	screen *= camera.get_viewport().get_visible_rect().size \
			/ view_cam.get_viewport().get_visible_rect().size
	var depth := -(view_cam.global_transform.affine_inverse() * muzzle.global_position).z
	return camera.project_position(screen, depth)


# Replayed on every peer with the shot; only the local viewmodel (and its
# crosshair) react.
func recoil() -> void:
	if not view_model.visible:
		return
	_motion.kick()
	if play_char.hud.crosshair != null:
		play_char.hud.crosshair.kick()


func update_visibility() -> void:
	if play_char == null:
		return
	var alive: bool = not play_char.dead
	view_model.visible = alive and not play_char.is_remote
	world_model.visible = alive and play_char.is_remote


# Outgoing damage stage of the pipeline: base damage -> damage stat (capped in
# get_stat) -> attacker hooks (ctx mutation). The victim's client owns the
# defensive stage (rpc_take_damage).
func _apply_damage(collider: Object, hit_pos: Vector3) -> void:
	if collider == null or collider == play_char or not (collider is Node):
		return
	var node := collider as Node
	var hit_player := node.is_in_group("player")
	if not hit_player and not node.is_in_group("enemy"):
		return
	var mods: ModifierManager = play_char.mods
	var ctx := {
		"amount": mods.get_stat(&"damage", definition.damage),
		"attacker_id": Fusion.get_local_player_id() if Engine.has_singleton("Fusion") else -1,
		"distance": (hit_pos - camera.global_position).length(),
		"hit_player": hit_player,
		"victim": node,
		"statuses": [],
	}
	mods.on_damage_dealt(ctx)
	var final_amount := maxi(roundi(float(ctx["amount"])), 0)
	if hit_player:
		Fusion.rpc_to(Fusion.TARGET_OWNER, Callable(collider, "rpc_take_damage"),
				final_amount, int(ctx["attacker_id"]))
		for status in ctx["statuses"]:
			Fusion.rpc_to(Fusion.TARGET_OWNER, Callable(collider, "rpc_apply_status"), String(status))
		var lifesteal := final_amount * mods.get_stat(&"lifesteal", 0.0) / 100.0
		if lifesteal > 0.0:
			play_char.get_node("Health").heal(lifesteal)
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
	label.font_size = 40 + 0.5 * amount
	label.outline_size = 10
	label.font = custom_font
	# moved by a frame tween, not physics: interpolation would only add lag
	label.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	var dir := to - from
	if dir.length() > 0.01:
		var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
		bullet.global_transform = bullet.global_transform.looking_at(to, up)
	# stop at the hit instead of flying on past the crosshair point
	bullet.max_distance = dir.length()
	# without this the first interpolated frame streaks in from the origin
	bullet.reset_physics_interpolation()


func _reload() -> void:
	if play_char.is_remote or reloading or ammo >= mag_size():
		return
	reloading = true
	_reload_generation += 1
	var generation := _reload_generation
	# replicated counter: every peer replays the reload visual + sound
	play_char.net_reload_count += 1
	_reload_duration = definition.reload_time * play_char.mods.get_stat(&"reload_time", 1.0)
	_reload_started_ms = Time.get_ticks_msec()
	_motion.start_reload(_reload_duration)
	await get_tree().create_timer(_reload_duration).timeout
	if generation != _reload_generation or not is_inside_tree():
		return
	ammo += mag_size()
	reloading = false


## 0..1 through the current reload (HUD ring and pip refill)
func reload_progress() -> float:
	if not reloading:
		return 0.0
	return clampf((Time.get_ticks_msec() - _reload_started_ms) / (_reload_duration * 1000.0),
			0.0, 1.0)


## magazine size after modifiers
func mag_size() -> int:
	return maxi(roundi(play_char.mods.get_stat(&"mag_size", definition.mag_size)), 1)


func reset_for_respawn() -> void:
	_reload_generation += 1
	reloading = false
	ammo = mag_size()
	fire_cooldown = 0.0
	shoot_sound.stop()
	reload_sound.stop()
	_motion.raise()


## Removes this weapon and the parts setup() moved elsewhere (viewmodel pivot,
## hand-held world model). Used when a modifier replaces the weapon.
func dispose() -> void:
	_motion.queue_free()
	world_model.queue_free()
	queue_free()


func show_kill() -> void:
	hit_confirm.show_kill()


func reload_visual() -> void:
	_play_reload_sound()
	if play_char.has_method("animate_reload"):
		play_char.animate_reload()


func _play_shoot_sound() -> void:
	if definition == null or definition.shoot_sounds.is_empty():
		return
	shoot_sound.stream = definition.shoot_sounds.pick_random()
	shoot_sound.pitch_scale = randf_range(0.95, 1.05)
	shoot_sound.play()


func _play_reload_sound() -> void:
	if definition == null or definition.reload_sounds.is_empty():
		return
	reload_sound.stream = definition.reload_sounds.pick_random()
	reload_sound.pitch_scale = randf_range(0.95, 1.05)
	reload_sound.play()


func _flash_models() -> void:
	for model in [view_model, world_model]:
		var flash := model.find_child("MuzzleFlash", true, false) as GPUParticles3D
		if flash != null:
			flash.restart()


# The viewmodel renders only in its SubViewport (layer 4, matching the
# viewmodel camera's cull_mask), so it keeps a fixed FOV and never depth-tests
# against walls.
func _set_viewmodel_layers() -> void:
	for node in view_model.find_children("*", "VisualInstance3D", true, false):
		node.layers = VIEWMODEL_LAYER
