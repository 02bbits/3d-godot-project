extends "res://scripts/player/player_network.gd"

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

func _on_health_changed(current: float, previous: float) -> void:
	if current <= 0.0 and previous > 0.0 and death_effect != null:
		var effect := death_effect.instantiate() as Node3D
		effect.position = global_position + Vector3.UP
		get_tree().root.add_child(effect)

func _die(attacker_id: int = -1) -> void:
	if dead:
		return
	dead = true
	if _shot_turn_tween != null and _shot_turn_tween.is_valid():
		_shot_turn_tween.kill()
	head_look.influence = 0.0 # keep the death animation's head pose
	if arm_ik != null:
		arm_ik.influence = 0.0 # and let the death animation pose the arm
	net_wallrun_side = 0 # dying out of a wallrun must not keep the model leaning
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
	if arm_ik != null:
		arm_ik.influence = 1.0
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
	phantom_gun.visible = not dead and not is_remote
	hitbox.disabled = dead
