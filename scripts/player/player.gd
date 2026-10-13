extends "res://scripts/player/player_lifecycle.gd"

class_name PlayerCharacter

const WEAPON_SCENE := preload("res://scenes/weapons/weapon.tscn")

func _ready() -> void:
	#set and value references
	$Health.max_health = max_health
	health = max_health
	$Health.died.connect(_die)
	$Health.damaged.connect(_on_damaged)
	$Health.health_changed.connect(_on_health_changed)
	nickname_label.text = net_nickname
	apply_robot_color()
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
	_setup_weapon()
	setup_network_control()
	# The viewmodel renders in its own World3D (map lights don't reach across
	# worlds): give it the map's environment so the gun gets the same sky
	# ambient and reflections as the world. SunMirror copies the directional sun.
	var vm_world := viewmodel_camera.get_viewport().world_3d
	if vm_world != null and get_world_3d().environment != null:
		vm_world.environment = get_world_3d().environment
	# a copy spawned mid-game may already carry a replicated build
	mods.sync_build(net_mods)


func _setup_weapon() -> void:
	if weapon_definition == null:
		push_warning("Player has no weapon_definition assigned")
		return
	equip_weapon(weapon_definition)


# Instantiates a weapon (shared scene + per-weapon definition) under the
# camera, replacing the current one. Weapon-replacement modifiers call this
# through ModifierManager.
func equip_weapon(definition: WeaponDefinition) -> void:
	var previous := weapon
	weapon = WEAPON_SCENE.instantiate()
	cam.add_child(weapon)
	weapon.setup(self, definition)
	if previous != null:
		# a dead or remote copy keeps its weapon inert
		weapon.set_process(previous.is_processing())
		weapon.set_process_input(previous.is_processing_input())
		weapon.set_process_unhandled_input(previous.is_processing_unhandled_input())
		previous.dispose()

func _process(delta: float) -> void:
	wallrun_timer(delta)

	slide_timer(delta)

	dash_timer(delta)

	jump_timer(delta)

	stamina_tick(delta)

	network_view_sync(delta)

	update_ping(delta)

	_animate_locomotion(delta)

func _physics_process(delta: float) -> void:
	modify_physics_properties()

	if _stun_left > 0.0:
		_stun_left -= delta
		if _stun_left <= 0.0:
			_sync_controls()
	if is_frozen():
		# held in place (match flow lock or a stun): no input, but still fall
		velocity.x = 0.0
		velocity.z = 0.0
		gravity_apply(delta)

	# modifiers may steer this tick (Lifted pulls up, Charge checks its area)
	mods.on_physics(delta)

	move_and_slide()

	# fell out of the arena: an instant death, past the damage pipeline (no
	# Second Wind) and credited to nobody
	if global_position.y < kill_height and not dead:
		$Health.apply($Health.health)

	_track_ground_state()

@rpc("any_peer")
func rpc_take_damage(amount: int, attacker_id: int = -1) -> void:
	# ponytail: shared-authority damage remains client-trusted; move hit validation
	# to Fusion Client-Server authority before shipping competitive play.
	if is_remote:
		return
	take_damage(clampf(float(amount), 0.0, max_health), attacker_id)

@rpc("any_peer")
func rpc_knockback(x: float, y: float, z: float) -> void:
	# an ability shove (Charge): the victim's owner moves itself
	if is_remote:
		return
	velocity += Vector3(x, y, z)

@rpc("any_peer")
func rpc_apply_status(id: String) -> void:
	# a hit's status effect (e.g. Frost Rounds' chill): the victim's owner
	# applies it; ids that aren't timed statuses are ignored there
	if is_remote:
		return
	mods.apply_status(StringName(id))

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
					p.mods.on_kill({"victim": self})
					break

@rpc("any_peer")
func respawn_fx() -> void:
	if is_remote:
		dead = false
		_set_dead_visuals()
