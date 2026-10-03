extends "res://scripts/player/player_movement.gd"

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
# replicated planar velocity: remote copies have no physics, so they drive the
# locomotion blend from this instead of their own (zero) velocity
var net_velocity: Vector3 = Vector3.ZERO
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
var net_wallrun_side: int = 0 # -1 left wall, 1 right wall, 0 not wallrunning
var _wallrun_lean: float = 0.0

# Squash/stretch is applied only on remote players (local is first person);
# it always decays back to one. Locomotion blends the animation tree in local
# space so strafing/backpedal read correctly.
func _animate_locomotion(delta: float) -> void:
	if dead:
		return
	visual_root.scale = visual_root.scale.lerp(Vector3.ONE, delta * 8)

	# blend in the model's facing space (already yawed by body_yaw). Absolute
	# speed over run_speed puts walking around 0.7 and running around 1.0, so
	# the blend space tells the two apart.
	var planar_vel := Vector3(velocity.x, 0.0, velocity.z) if not is_remote else net_velocity
	var local_vel := visual_root.global_transform.basis.inverse() * planar_vel
	var target_blend := Vector2(local_vel.x, local_vel.z) / maxf(run_speed, 0.01)
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
	# remaining angle up to the neck limit on every peer. Wallrunning rolls the
	# model toward the wall, matching the camera's 16 degree lean.
	var lean_target := 0.0
	if net_wallrun_side != 0:
		lean_target = deg_to_rad(wallrun_model_lean_degrees) * -net_wallrun_side
	_wallrun_lean = lerpf(_wallrun_lean, lean_target, clampf(wallrun_model_lean_speed * delta, 0.0, 1.0))
	visual_root.rotation = Vector3(0.0, body_yaw, _wallrun_lean)

func _update_body_yaw(delta: float) -> void:
	# a shot turn owns the torso until it finishes
	if _shot_turn_tween != null and _shot_turn_tween.is_valid() and _shot_turn_tween.is_running():
		return
	# past the neck limit the torso catches up until the head can aim again
	var limit := deg_to_rad(head_yaw_limit_degrees)
	var offset := angle_difference(body_yaw, view_yaw)
	if absf(offset) <= limit:
		return
	# far behind the aim the torso must catch up fast or the arm IK twists
	# around the neck; keep it a smooth turn, just a sharper one
	var smoothing := body_turn_smoothing
	if absf(offset) > deg_to_rad(body_turn_fast_degrees):
		smoothing = body_turn_fast_smoothing
	var target := view_yaw - signf(offset) * limit
	body_yaw = lerp_angle(body_yaw, target, clampf(smoothing * delta, 0.0, 1.0))

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

# Owner-side ground/jump/land detection feeding the replicated event counters
# (remote copies replay the sounds and animations through the setters).
func _track_ground_state() -> void:
	var grounded := is_on_floor()
	if grounded and not net_is_grounded:
		net_land_count += 1
	elif not grounded and net_is_grounded and velocity.y > 1.0:
		net_jump_count += 1
	net_is_grounded = grounded
	net_velocity = Vector3(velocity.x, 0.0, velocity.z)

func _show_fire_effects() -> void:
	turn_body_to_aim()
	_recoil_phantom_gun()
	phantom_muzzle_flash.restart()
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
	_flash_hit_white()
	var request := "parameters/Alive/HitB/request" if health < max_health * 0.5 \
			else "parameters/Alive/HitA/request"
	animation_tree.set(request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

var _hit_flash_material: StandardMaterial3D
var _hit_flash_tween: Tween

# White 80% overlay on every body mesh, faded out. Shared material: all meshes
# flash together, which is what a hit reaction wants.
# ponytail: no per-mesh flash; split materials only if parts must flash apart.
func _flash_hit_white() -> void:
	if _hit_flash_material == null:
		_hit_flash_material = StandardMaterial3D.new()
		_hit_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hit_flash_material.albedo_color = Color(1, 1, 1, 0.8)
	for node in visual_root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = _hit_flash_material
	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_hit_flash_material, "albedo_color:a", 0.0, 0.15)
	_hit_flash_tween.tween_callback(_clear_hit_flash)

func _clear_hit_flash() -> void:
	for node in visual_root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = null

func animate_reload() -> void:
	weapon_state_machine.travel("Reload")

var arm_ik: TwoBoneIK3D
var _arm_target: Marker3D
var _arm_pole: Marker3D

# Native two-bone IK so the gun hand keeps tracking the camera aim on every
# peer, like the head's LookAtModifier3D. Created at runtime because the rig
# bones only exist once the model scene is instantiated.
# ponytail: pole/target offsets are exported knobs; retune per rig if the
# elbow pops. Two bones are enough because the hand holds one gun.
func setup_arm_ik() -> void:
	var skeleton: Skeleton3D = head_look.get_parent()
	_arm_target = Marker3D.new()
	_arm_target.name = "ArmAimTarget"
	_arm_target.position = arm_target_offset
	cam.add_child(_arm_target)
	_arm_pole = Marker3D.new()
	_arm_pole.name = "ArmPoleTarget"
	_arm_pole.position = arm_pole_offset
	visual_root.add_child(_arm_pole)
	arm_ik = TwoBoneIK3D.new()
	arm_ik.name = "ArmIK"
	# Block the immediate first solve (Skeleton3D processes new modifiers on
	# enter tree, before the AnimationMixer has written a pose) and the engine
	# throws on zero bases; enable it a few frames later instead.
	arm_ik.active = false
	skeleton.add_child(arm_ik)
	# Rig bone axes are constant; mutable axes read uninitialized poses on the
	# first frames and spray quaternion errors, so cache them from rest.
	arm_ik.mutable_bone_axes = false
	arm_ik.setting_count = 1
	arm_ik.set_root_bone_name(0, "upperarm.r")
	arm_ik.set_middle_bone_name(0, "lowerarm.r")
	arm_ik.set_end_bone_name(0, "wrist.r")
	arm_ik.set_target_node(0, arm_ik.get_path_to(_arm_target))
	arm_ik.set_pole_node(0, arm_ik.get_path_to(_arm_pole))
	for _i in 3:
		await get_tree().process_frame
	arm_ik.active = true

var _phantom_rest: Transform3D
var _phantom_rest_set := false
var _recoil_tween: Tween

# Camera-space kick: backward (toward the camera) and muzzle up, springing
# back to rest. The phantom's parent is the Camera, so +X rotation pitches the
# muzzle up in view space. Restarted per shot, never stacked.
# ponytail: position+rotation kick only; add a hand/arm kick if it reads flat.
func _recoil_phantom_gun() -> void:
	if not phantom_gun.visible:
		return
	if not _phantom_rest_set:
		_phantom_rest = phantom_gun.transform
		_phantom_rest_set = true
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	var kick := _phantom_rest
	kick.origin += Vector3(0.0, 0.012, 0.055)
	kick.basis = _phantom_rest.basis.rotated(Vector3(1.0, 0.0, 0.0), deg_to_rad(8.0))
	phantom_gun.transform = kick
	_recoil_tween = create_tween()
	_recoil_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(phantom_gun, "transform", _phantom_rest, 0.12)

# Local first person shows the camera-mounted phantom pistol (an instance of
# scenes/player/pistol.tscn); other peers see the hand-attached model gun on
# this player's remote copy. gun.tscn's old Body mesh stays hidden and its
# muzzle flash is only used by remote copies.
func _update_gun_visibility() -> void:
	var body := weapon.get_node_or_null("Body")
	if body != null:
		body.visible = false
	var gun_flash := weapon.get_node_or_null("Muzzle/MuzzleFlash")
	if gun_flash != null:
		gun_flash.visible = is_remote
	phantom_gun.visible = not is_remote
	pistol.visible = is_remote

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
	_update_gun_visibility()
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
	_update_gun_visibility()
	nickname_label.visible = true
	for mesh in head_meshes:
		if mesh != null:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
