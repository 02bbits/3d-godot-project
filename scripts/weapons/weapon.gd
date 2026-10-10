extends Node3D

## Shared weapon controller. Every weapon is this scene plus a
## WeaponDefinition resource: stats, viewmodel/world-model scenes, their
## transforms, the muzzle position and sounds all come from the definition, so
## a new weapon never needs changes here or in the player scripts.

const BULLET_SCENE = preload("res://scenes/entities/bullet.tscn")
const HIT_MASK := 7 # map + players + raycast helpers
const VIEWMODEL_LAYER := 4

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
var reserve: int
var reloading: bool = false
var fire_cooldown: float = 0.0
var _reload_generation := 0
var custom_font = load("res://assets/photon/kenney_platformer/fonts/lilita_one_regular.ttf")

var _recoil_rest: Transform3D
var _recoil_rest_set := false
var _recoil_tween: Tween


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
	_set_viewmodel_layers()

	ammo = _effective_mag()
	reserve = definition.reserve_max
	update_visibility()


func _process(delta: float) -> void:
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	# gun leans with the camera roll
	if play_char != null:
		rotation.x = get_parent().get_parent().rotation.z


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
	var mods: ModifierManager = play_char.get_node_or_null("ModifierManager")
	fire_cooldown = definition.fire_interval / mods.get_stat(&"fire_rate", 1.0)
	ammo -= 1
	if ammo == 0:
		_reload()

	# Traditional FPS aim: the reticle is the camera center, so the aim point
	# comes from a camera-center ray; a second ray from the muzzle to that point
	# keeps cover in front of the gun honest.
	var cam_origin := camera.global_position
	var cam_dir := -camera.global_transform.basis.z
	var cam_hit := _raycast(cam_origin, cam_origin + cam_dir * definition.range)
	var aim_point: Vector3 = cam_origin + cam_dir * definition.range
	if not cam_hit.is_empty():
		aim_point = cam_hit["position"]
	var muzzle_hit := _raycast(muzzle.global_position, aim_point)
	var hit: Dictionary = muzzle_hit if not muzzle_hit.is_empty() else cam_hit
	var collider: Object = hit.get("collider")
	var hit_pos: Vector3 = hit.get("position", aim_point)
	play_char.net_hit_normal = hit.get("normal", Vector3.ZERO)
	play_char.net_hit_position = hit_pos

	_apply_damage(collider, hit_pos)
	# bump the replicated counter last: every peer (this one included) replays
	# the shot visuals
	play_char.net_fire_count += 1


func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	if play_char == null:
		return {}
	var params := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK, [play_char.get_rid()])
	return play_char.get_world_3d().direct_space_state.intersect_ray(params)


# Replayed on every peer when the replicated fire counter increases.
func on_fire_event(hit_position: Vector3) -> void:
	_spawn_tracer(muzzle.global_position, hit_position)
	_flash_models()
	_play_shoot_sound()


func recoil() -> void:
	if not view_model.visible:
		return
	if not _recoil_rest_set:
		_recoil_rest = view_model.transform
		_recoil_rest_set = true
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	var kick := _recoil_rest
	kick.origin += Vector3(0.0, 0.012, 0.055)
	kick.basis = _recoil_rest.basis.rotated(Vector3(1.0, 0.0, 0.0), deg_to_rad(8.0))
	view_model.transform = kick
	_recoil_tween = create_tween()
	_recoil_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(view_model, "transform", _recoil_rest, 0.12)


func update_visibility() -> void:
	if play_char == null:
		return
	var alive: bool = not play_char.dead
	view_model.visible = alive and not play_char.is_remote
	world_model.visible = alive and play_char.is_remote


# Outgoing damage stage of the pipeline: base damage -> attacker modifier
# stats -> attacker hooks (ctx mutation) -> cap. The victim's client owns the
# defensive stage (rpc_take_damage).
func _apply_damage(collider: Object, hit_pos: Vector3) -> void:
	if collider == null or collider == play_char or not (collider is Node):
		return
	var node := collider as Node
	var hit_player := node.is_in_group("player")
	if not hit_player and not node.is_in_group("enemy"):
		return
	var mods: ModifierManager = play_char.get_node_or_null("ModifierManager")
	var amount := float(definition.damage)
	var ctx := {"amount": amount, "attacker_id": -1, "distance": 0.0, "hit_player": hit_player}
	if Engine.has_singleton("Fusion"):
		ctx["attacker_id"] = Fusion.get_local_player_id()
	ctx["distance"] = (hit_pos - muzzle.global_position).length()
	if mods != null:
		mods.on_damage_dealt(ctx)
		var cap: Array = ModifierManager.STAT_CAPS[&"damage"]
		ctx["amount"] = clampf(float(ctx["amount"]),
				definition.damage * cap[0], definition.damage * cap[1])
	var final_amount := int(roundf(float(ctx["amount"])))
	if hit_player:
		Fusion.rpc_to(Fusion.TARGET_OWNER, Callable(collider, "rpc_take_damage"),
				final_amount, int(ctx["attacker_id"]))
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
	var mods: ModifierManager = play_char.get_node_or_null("ModifierManager")
	await get_tree().create_timer(
			definition.reload_time * mods.get_stat(&"reload_time", 1.0)).timeout
	if generation != _reload_generation or not is_inside_tree():
		return
	var taken := mini(_effective_mag() - ammo, reserve)
	ammo += taken
	reserve -= taken
	reloading = false


func _effective_mag() -> int:
	var mods: ModifierManager = play_char.get_node_or_null("ModifierManager")
	return maxi(int(roundf(definition.mag_size * mods.get_stat(&"mag_size", 1.0))), 1)


func reset_for_respawn() -> void:
	_reload_generation += 1
	reloading = false
	ammo = _effective_mag()
	reserve = definition.reserve_max
	fire_cooldown = 0.0
	shoot_sound.stop()
	reload_sound.stop()


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
