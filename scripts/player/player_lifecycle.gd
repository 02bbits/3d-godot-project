extends "res://scripts/player/player_network.gd"

# true while the match flow holds players in place (modifier draft, countdown)
var input_locked := false
# seconds left of a stun (Zap Gun); counted down in player.gd
var _stun_left := 0.0
# true while the chat input is open (scripts/ui/chat.gd); separate from the
# match-flow lock so a phase change can't unfreeze a typing player
var typing := false
# replicated: bumped by the owner per chat message; every copy shows "..."
var net_chat_count: int = 0:
	set(value):
		var previous := net_chat_count
		net_chat_count = value
		if is_node_ready() and value > previous:
			_show_chat_bubble()

## Freezes movement, jumps, dashes and shooting; the camera can still look
## around and gravity still runs (player.gd) so the player settles on the
## spawn floor. Survives respawns; only the local copy is affected.
func set_input_locked(locked: bool) -> void:
	input_locked = locked
	_sync_controls()

## The same freeze for `seconds`, from a hit (statuses like Zapped). Never
## shortens a running stun; ending it never lifts the match-flow lock.
func stun(seconds: float) -> void:
	_stun_left = maxf(_stun_left, seconds)
	_sync_controls()

func set_typing(value: bool) -> void:
	typing = value
	_sync_controls()

func is_frozen() -> bool:
	return input_locked or typing or _stun_left > 0.0

# one place decides whether the local player's controls run
func _sync_controls() -> void:
	if is_remote or dead:
		return
	var frozen := is_frozen()
	state_machine.set_process(not frozen)
	state_machine.set_physics_process(not frozen)
	weapon.set_process_unhandled_input(not frozen)

func take_damage(amount: float, attacker_id: int = -1) -> void:
	if dead or amount <= 0.0:
		return
	# Defensive stage of the damage pipeline: the damage_taken stat (capped in
	# get_stat), then mods may mutate the ctx (e.g. Second Wind).
	var ctx := {"amount": mods.get_stat(&"damage_taken", amount), "attacker_id": attacker_id}
	mods.on_damage_taken(ctx)
	# Health node owns the number and emits died(attacker_id); that signal
	# routes here for the death broadcast + visuals
	$Health.apply(maxf(float(ctx["amount"]), 0.0), attacker_id)

# Owner-side hit reaction: bumps the replicated counter so every peer replays
# the flinch through the setter, flashes the damage indicator toward the
# attacker and gives a slight camera shake.
func _on_damaged(amount: float, attacker_id: int) -> void:
	net_hit_count += 1
	hud.hit_flash.flash(amount / maxf(max_health, 1.0), _damage_direction(attacker_id))
	cam_holder.shake()


# Camera-space direction (x right, y up, -z forward) to the attacker's replica;
# zero when the source is unknown (fall damage, world kills). The indicator
# turns this into one of the four screen corners.
func _damage_direction(attacker_id: int) -> Vector3:
	if attacker_id < 0 or not (Engine.has_singleton("Fusion") and Fusion.is_in_room()):
		return Vector3.ZERO
	for p in get_tree().get_nodes_in_group("player"):
		if p == self or not is_instance_valid(p):
			continue
		var rep: Node = p.find_child("FusionSharedReplicator", true, false)
		if rep == null or not rep.has_method("get_owner_id"):
			continue
		if int(rep.get_owner_id()) == attacker_id:
			var to_attacker: Vector3 = p.global_position + Vector3.UP - cam.global_position
			return cam.global_transform.basis.inverse() * to_attacker
	return Vector3.ZERO

func _on_health_changed(current: float, previous: float) -> void:
	if current <= 0.0 and previous > 0.0 and death_effect != null:
		var effect := death_effect.instantiate() as Node3D
		effect.position = global_position + Vector3.UP
		get_tree().root.add_child(effect)

func _die(attacker_id: int = -1) -> void:
	if dead:
		return
	dead = true
	# back to idle right away: a death mid-run (or mid-jump/wallrun) must not
	# leave a stamina-draining state behind for the respawn
	if not is_remote:
		_enter_idle()
	if _shot_turn_tween != null and _shot_turn_tween.is_valid():
		_shot_turn_tween.kill()
	head_look.influence = 0.0 # keep the death animation's head pose
	if arm_ik != null:
		arm_ik.influence = 0.0 # and let the death animation pose the arm
	net_wallrun_side = 0 # dying out of a wallrun must not keep the model leaning
	_set_dead_visuals()
	# eliminated players stay out until the match ends (match_manager decides)
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

func reset_for_respawn(spawn_transform: Transform3D) -> void:
	if is_remote:
		return
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
	_enter_idle()
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
	_stun_left = 0.0
	mods.on_respawn()
	if Engine.has_singleton("Fusion") and Fusion.is_in_room():
		Fusion.rpc(Callable(self, "respawn_fx"))
	set_physics_process(true)
	cam_holder.set_process(true)
	cam_holder.set_process_input(true)
	cam_holder.set_process_unhandled_input(true)
	weapon.set_process(true)
	weapon.set_process_input(true)
	_sync_controls() # state machine + shooting, unless locked or stunned
	cam.current = true
	hud.visible = true
	death_screen.visible = false
	var im: Node = get_tree().get_first_node_in_group("input_mode")
	if im != null and im.has_method("set_mode"):
		im.set_mode(im.Mode.GAMEPLAY)

# Switches to IdleState through the state machine's own transition (exit,
# enter, FOV reset). States are keyed by lowercased node name ("idlestate").
func _enter_idle() -> void:
	if state_machine.curr_state != null and state_machine.curr_state_name != "Idle":
		state_machine.on_state_child_transition(state_machine.curr_state, "IdleState")

func _set_dead_visuals() -> void:
	# remote copies keep the body visible so peers see the death animation;
	# the local body stays hidden behind the death screen
	visual_root.visible = is_remote or not dead
	nickname_label.visible = not dead and is_remote
	if weapon != null:
		weapon.update_visibility()
	hitbox.disabled = dead

# "..." over a remote robot for chat_bubble_seconds, then a fade (the message
# itself stays in the chat log; the local view is first person)
func _show_chat_bubble() -> void:
	if not is_remote:
		return
	if _chat_bubble_tween != null:
		_chat_bubble_tween.kill()
	chat_bubble.visible = true
	chat_bubble.modulate.a = 1.0
	chat_bubble.outline_modulate.a = 1.0
	_chat_bubble_tween = create_tween()
	_chat_bubble_tween.tween_interval(chat_bubble_seconds)
	_chat_bubble_tween.tween_property(chat_bubble, "modulate:a", 0.0, chat_bubble_fade)
	_chat_bubble_tween.parallel().tween_property(chat_bubble, "outline_modulate:a", 0.0, chat_bubble_fade)
	_chat_bubble_tween.tween_callback(chat_bubble.hide)
