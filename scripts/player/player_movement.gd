extends "res://scripts/player/player_base.gd"

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
		# keep the capsule's bottom on the floor: move the center by half the
		# height change, otherwise shrinking lifts the bottom and the body
		# falls until it touches down again (crouch sinking)
		hitbox.position.y += (value - hitbox.shape.height) * 0.5
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
