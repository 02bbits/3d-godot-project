extends "res://scripts/player/player_lifecycle.gd"

class_name PlayerCharacter

func _ready() -> void:
	#set and value references
	$Health.max_health = max_health
	health = max_health
	$Health.died.connect(_die)
	$Health.damaged.connect(_on_damaged)
	$Health.health_changed.connect(_on_health_changed)
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
	cam_base_height = cam_holder.position.y

	build_default_keybinding()
	input_actions_check()
	# The crouch ray starts below the crouched capsule, so without this it hits
	# the player's own body and blocks stand-up/jump forever (stuck crouch).
	ceiling_check.add_exception(self)
	setup_arm_ik()
	setup_network_control()

func _process(delta: float) -> void:
	wallrun_timer(delta)

	slide_timer(delta)

	dash_timer(delta)

	jump_timer(delta)

	stamina_tick(delta)

	network_view_sync(delta)

	_animate_locomotion(delta)

func _physics_process(_delta: float) -> void:
	modify_physics_properties()

	move_and_slide()

	_track_ground_state()

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
