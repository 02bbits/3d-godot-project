extends Node3D

signal room_error(message: String)
signal network_status_changed(connected: bool, message: String)
signal room_list_changed(rooms: Array)
signal room_ready(room_name: String, phase: String, password_required: bool)
signal room_phase_changed(phase: String)
signal room_members_changed(player_count: int, max_players: int, is_master: bool)
signal match_started
signal room_left

const PlayerScene := preload("res://scripts/player/player.tscn")
const MAP_COLLISION_MASK := 1
const SPAWN_COLLISION_MASK := 3
const FLOOR_MAX_ANGLE := deg_to_rad(65.0)
const SPAWN_RAY_HEIGHT := 8.0
const SPAWN_CLEARANCE := 0.05
const ROOM_PHASE_WAITING := "waiting"
const ROOM_PHASE_PLAYING := "playing"
const GAME_VERSION := "1"
const MAX_PLAYERS := 6
const PASSWORD_MIN_LENGTH := 4
const PASSWORD_MAX_LENGTH := 64

@onready var spawner: FusionSpawner = $FusionSpawner

var _spawn_shape: Shape3D
var _spawn_half_height := 1.0
var _players_by_owner: Dictionary = {}
var _local_player: PlayerCharacter
var _room_ready := false
var _connection_started := false
var _join_started := false
var _spawn_in_progress := false
var _restart_in_progress := false
var _room_name := ""
var _create_mode := false
var _room_request_pending := false
var _room_request_id := 0
var _password_attempt := ""
var _room_phase := ROOM_PHASE_WAITING
var _room_access_granted := false
var _room_state_watching := false
var _match_started := false


func _ready() -> void:
	if not Engine.has_singleton("Fusion"):
		network_status_changed.emit(false, "Multiplayer unavailable")
		push_error("Fusion is not available; multiplayer cannot start")
		return

	_prepare_spawn_shape()
	spawner.add_spawnable_scene(PlayerScene)
	Fusion.connected_to_photon.connect(_on_connected_to_photon)
	Fusion.connection_failed.connect(_on_connection_failed)
	Fusion.connection_status_changed.connect(_on_connection_status_changed)
	Fusion.room_joined.connect(_on_room_joined)
	Fusion.room_left.connect(_on_room_left)
	Fusion.room_list_updated.connect(_on_room_list_updated)
	Fusion.player_joined.connect(_on_player_joined)
	Fusion.player_left.connect(_on_player_left)
	Fusion.master_client_changed.connect(_on_master_client_changed)
	# Connect to Photon on boot (master lobby, for the room browser); a room is
	# only joined/created when the user picks one in the lobby.
	_connect_to_photon.call_deferred()


# Host a new room; fails cleanly (room_error) if the name is taken.
func host_room(name: String, password: String = "") -> void:
	_request_room(name, true, password)


# Join an existing room by name.
func join_room(name: String, password: String = "") -> void:
	_request_room(name, false, password)


func _request_room(name: String, create: bool, password: String) -> void:
	if _room_request_pending:
		return
	if not Engine.has_singleton("Fusion"):
		room_error.emit("Multiplayer is unavailable in this build.")
		return
	name = name.strip_edges()
	if name.is_empty() or name.length() > 32 \
			or not RegEx.create_from_string("^[A-Za-z0-9_.\\- ]+$").search(name):
		room_error.emit("Room name must be 1-32 chars: letters, digits, space, _ - .")
		return
	if not password.is_empty() and (password.length() < PASSWORD_MIN_LENGTH \
			or password.length() > PASSWORD_MAX_LENGTH):
		room_error.emit("Password must be 4-64 characters, or empty for a public room.")
		return
	_room_request_id += 1
	_room_name = name
	_create_mode = create
	_password_attempt = password
	if Fusion.is_connected_to_photon() and not Fusion.is_in_room():
		_join_room_now(_room_request_id)
	else:
		_connect_to_photon()


func _join_room_now(request_id: int) -> void:
	_room_request_pending = true
	_join_started = true
	var options := FusionRoomOptions.new()
	options.max_players = MAX_PLAYERS
	# Remove players that stop responding, and let the room die after the last
	# player leaves so stale rooms cannot accumulate ghosts.
	options.player_ttl_ms = 10000
	options.empty_room_ttl_ms = 30000
	if _create_mode:
		var password_required := not _password_attempt.is_empty()
		var salt := _new_password_salt() if password_required else ""
		options.custom_properties = {
			"game_version": GAME_VERSION,
			"map_id": "testing",
			"phase": ROOM_PHASE_WAITING,
			"password_required": password_required,
			"password_salt": salt,
			"password_digest": _hash_password(_password_attempt, salt) if password_required else "",
		}
		options.lobby_properties = ["game_version", "map_id", "phase", "password_required"]
		Fusion.create_room(_room_name, options)
	else:
		Fusion.join_room(_room_name, options)
	_watch_room_join(request_id)


# ponytail: this Fusion build has no room-join-failed signal, so failure is
# detected by timeout. Use a real failure callback when the addon ships one.
func _watch_room_join(request_id: int) -> void:
	await get_tree().create_timer(8.0).timeout
	if request_id != _room_request_id or not _room_request_pending or _room_ready:
		return
	_room_request_pending = false
	_join_started = false
	room_error.emit("Could not %s room \"%s\" (not found, full, or name taken)" % [
		"create" if _create_mode else "join", _room_name])


func _exit_tree() -> void:
	if Engine.has_singleton("Fusion") and Fusion.is_in_room():
		Fusion.leave_room()


func _connect_to_photon() -> void:
	if _connection_started:
		return
	_connection_started = true
	# A stable account/session id should replace this when authentication exists.
	var user_id := "user_%d_%d" % [Time.get_ticks_usec(), get_instance_id()]
	print("connecting to Photon as: ", user_id)
	# Passing "" makes Fusion pick region=best per machine; clients in different
	# regions cannot see each other's rooms ("Game does not exist", code 22).
	# Always use the configured default region so the lobby is one namespace.
	var region: String = ProjectSettings.get_setting("fusion/connection/default_region", "asia")
	Fusion.connect_to_photon(user_id, region)


func refresh_rooms() -> void:
	if Engine.has_singleton("Fusion") and Fusion.is_connected_to_photon() and not Fusion.is_in_room():
		_refresh_room_list()


func leave_room() -> void:
	if Engine.has_singleton("Fusion") and Fusion.is_in_room():
		Fusion.leave_room()


func start_match() -> void:
	if not _room_ready or not _room_access_granted or not Fusion.is_master_client():
		return
	var room: Object = Fusion.get_room()
	if room == null or not room.has_method("set_property"):
		room_error.emit("This Fusion build cannot start the room.")
		return
	if not bool(room.set_property("phase", ROOM_PHASE_PLAYING)):
		room_error.emit("The host could not start the room.")
		return
	if room.has_method("set_open"):
		room.set_open(false)
	_room_phase = ROOM_PHASE_PLAYING
	room_phase_changed.emit(_room_phase)
	_spawn_local_player.call_deferred()


func is_room_master() -> bool:
	return _room_ready and Fusion.is_master_client()


func is_in_room() -> bool:
	return _room_ready


func _on_connected_to_photon() -> void:
	network_status_changed.emit(true, "Connected")
	_refresh_room_list()
	if _room_ready or _room_name.is_empty():
		return
	print("connected, %s room" % ("creating" if _create_mode else "joining"))
	_join_room_now(_room_request_id)


func _on_connection_failed(error: String) -> void:
	_join_started = false
	_room_ready = false
	_room_request_pending = false
	# Fusion also emits this for room join failures and stays on the master
	# server; only a real connect failure needs a reconnect on retry.
	_connection_started = Fusion.is_connected_to_photon()
	network_status_changed.emit(false, "Connection failed")
	room_error.emit("Photon connection failed: " + error)
	push_error("Photon connection failed: " + error)


func _on_connection_status_changed(status: int) -> void:
	print("Photon connection status: ", status)
	if not Fusion.is_connected_to_photon():
		network_status_changed.emit(false, "Connecting to Photon...")


func _on_room_joined() -> void:
	if _room_ready:
		return
	_room_ready = true
	_join_started = false
	_room_request_pending = false
	_room_access_granted = _verify_room_password(_password_attempt)
	_password_attempt = ""
	if not _room_access_granted:
		room_error.emit("Incorrect password.")
		Fusion.leave_room()
		return
	_room_phase = _get_room_phase()
	room_ready.emit(_room_name, _room_phase, _room_requires_password())
	_emit_room_members()
	_watch_room_state.call_deferred()


func _on_room_left() -> void:
	_room_ready = false
	_join_started = false
	_room_request_pending = false
	_spawn_in_progress = false
	_restart_in_progress = false
	_local_player = null
	_players_by_owner.clear()
	_room_access_granted = false
	_room_phase = ROOM_PHASE_WAITING
	_room_state_watching = false
	_match_started = false
	_room_name = ""
	_create_mode = false
	_password_attempt = ""
	_clear_local_player_nodes()
	room_left.emit()


func _on_master_client_changed(old_id: int, new_id: int) -> void:
	print("Photon master client changed: ", old_id, " -> ", new_id)
	_emit_room_members()


func _on_player_joined(player_id: int, _user_id: String) -> void:
	_emit_room_members.call_deferred()
	if player_id != Fusion.get_local_player_id():
		_sync_life_state.call_deferred(player_id)


func _on_player_left(player_id: int, _is_inactive: bool) -> void:
	# ponytail: remove inactive players immediately; reconnect grace needs stable
	# account identity and a room-level reservation protocol.
	var player: Node = _players_by_owner.get(player_id)
	if player == null:
		player = _find_player_by_owner_id(player_id)
	_players_by_owner.erase(player_id)
	if player == null or not is_instance_valid(player):
		if not _sweep_departed_replicas():
			push_warning("Photon player left without a local replica: ", player_id)
		_emit_room_members()
		return
	if player == _local_player:
		_local_player = null
	print("removing disconnected player ", player_id, " at ", player.get_path())
	_remove_departed_player(player)
	_emit_room_members()


func _on_room_list_updated(rooms: Array) -> void:
	room_list_changed.emit(rooms)


func _refresh_room_list() -> void:
	if Engine.has_singleton("Fusion") and Fusion.is_connected_to_photon() and not Fusion.is_in_room():
		room_list_changed.emit(Fusion.get_room_list())


func _emit_room_members() -> void:
	if not _room_ready or not Fusion.is_in_room():
		return
	var room: Object = Fusion.get_room()
	if room == null:
		return
	var count := int(room.get_player_count()) if room.has_method("get_player_count") else 0
	var max_players := int(room.get_max_players()) if room.has_method("get_max_players") else MAX_PLAYERS
	room_members_changed.emit(count, max_players, Fusion.is_master_client())


func _watch_room_state() -> void:
	if _room_state_watching:
		return
	_room_state_watching = true
	while _room_ready and _room_access_granted:
		var phase := _get_room_phase()
		if phase != _room_phase:
			_room_phase = phase
			room_phase_changed.emit(phase)
		_emit_room_members()
		if phase == ROOM_PHASE_PLAYING:
			_spawn_local_player.call_deferred()
			_room_state_watching = false
			return
		await get_tree().create_timer(0.5).timeout
	_room_state_watching = false


func _get_room_custom_properties() -> Dictionary:
	if not Fusion.is_in_room():
		return {}
	var room: Object = Fusion.get_room()
	if room == null or not room.has_method("get_custom_properties"):
		return {}
	return room.get_custom_properties()


func _get_room_phase() -> String:
	var props := _get_room_custom_properties()
	# Existing rooms created before the lobby phase metadata still start directly.
	return String(props.get("phase", ROOM_PHASE_PLAYING))


func _room_requires_password() -> bool:
	return bool(_get_room_custom_properties().get("password_required", false))


func _verify_room_password(password: String) -> bool:
	var props := _get_room_custom_properties()
	if not bool(props.get("password_required", false)):
		return true
	var salt := String(props.get("password_salt", ""))
	var digest := String(props.get("password_digest", ""))
	if salt.is_empty() or digest.is_empty():
		return false
	# ponytail: client-side room gate, not cheat-proof; use authoritative admission when hostile clients matter.
	return _hash_password(password, salt) == digest


func _new_password_salt() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func _hash_password(password: String, salt: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update((salt + "\n" + password).to_utf8_buffer())
	return context.finish().hex_encode()


func _sync_life_state(player_id: int) -> void:
	for _attempt in range(10):
		if is_instance_valid(_local_player):
			break
		await get_tree().process_frame
	if not _room_ready or not is_instance_valid(_local_player):
		return
	var fx := "died_fx" if _local_player.dead else "respawn_fx"
	Fusion.rpc_to(player_id, Callable(_local_player, fx))


func _register_player(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_in_group("player"):
		return
	var replicator: Node = node.find_child("FusionSharedReplicator", true, false)
	if replicator == null or not replicator.has_method("get_owner_id"):
		return
	var owner_id := int(replicator.get_owner_id())
	if owner_id >= 0:
		_players_by_owner[owner_id] = node
	if not bool(node.get("is_remote")):
		_local_player = node as PlayerCharacter


# Free remote player replicas whose owner is no longer an active room player.
func _sweep_departed_replicas() -> bool:
	if not _room_ready:
		return false
	var room: Object = Fusion.get_room()
	if room == null or not room.has_method("get_players"):
		return false
	var live := {}
	for photon_player in room.get_players():
		if not bool(photon_player.get_is_inactive()):
			live[int(photon_player.get_number())] = true
	if live.is_empty():
		return false
	var removed := false
	for node in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(node) or node == _local_player:
			continue
		var replicator: Node = node.find_child("FusionSharedReplicator", true, false)
		if replicator == null or not replicator.has_method("get_owner_id"):
			continue
		var owner_id := int(replicator.get_owner_id())
		if owner_id == 0 or (owner_id >= 1 and not live.has(owner_id)):
			_players_by_owner.erase(owner_id)
			_remove_departed_player(node)
			removed = true
	return removed


func _find_player_by_owner_id(owner_id: int) -> Node:
	for player in get_tree().get_nodes_in_group("player"):
		var replicator: Node = player.find_child("FusionSharedReplicator", true, false)
		if replicator != null and replicator.has_method("get_owner_id"):
			if int(replicator.get_owner_id()) == owner_id:
				return player
	return null


func _remove_departed_player(player: Node) -> void:
	var replicator: Node = player.find_child("FusionSharedReplicator", true, false)
	# ponytail: the bundled Fusion preview crashes with PlayerAttached ownership;
	# local cleanup is the safe fallback until the native addon is upgraded.
	if _room_ready and replicator != null and replicator.has_method("has_authority") and replicator.has_authority():
		spawner.despawn(player)
		return
	# The owner is already gone on this peer, so there is no authority left to
	# issue a network despawn. Remove the stale local replica immediately.
	player.queue_free()


func _clear_local_player_nodes() -> void:
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player):
			player.queue_free()


func _spawn_local_player() -> void:
	if not _room_ready or not _room_access_granted or _room_phase != ROOM_PHASE_PLAYING \
			or _spawn_in_progress or is_instance_valid(_local_player):
		return
	_spawn_in_progress = true
	var spawn_transform: Variant = null
	for _attempt in range(3):
		await get_tree().physics_frame
		spawn_transform = _find_spawn_transform()
		if spawn_transform != null:
			break
	if spawn_transform == null:
		_spawn_in_progress = false
		push_error("No safe spawn point is available")
		return

	var node := spawner.spawn(PlayerScene)
	var player := node as PlayerCharacter
	if player == null:
		_spawn_in_progress = false
		push_error("FusionSpawner failed to spawn the local player")
		return
	# ponytail: post-spawn transform because Fusion 3.0's callback crashes with a
	# second client; use pre-spawn placement after the native addon is fixed.
	player.global_transform = spawn_transform
	_local_player = player
	_spawn_in_progress = false
	_register_player(player)
	_match_started = true
	match_started.emit()
	print("joined room, spawned player at ", player.global_position)

func respawn_player(player: PlayerCharacter) -> void:
	if not _room_ready or player != _local_player or player.is_remote or _restart_in_progress:
		player.restart_failed()
		return
	_restart_in_progress = true
	await get_tree().physics_frame
	if not _room_ready or not is_instance_valid(player):
		_restart_in_progress = false
		return
	var spawn_transform: Variant = _find_spawn_transform(player)
	if spawn_transform == null:
		_restart_in_progress = false
		player.restart_failed()
		push_error("Restart cancelled: no safe spawn point is available")
		return
	player.reset_for_respawn(spawn_transform)
	_restart_in_progress = false


func _prepare_spawn_shape() -> void:
	# mirrors player.tscn's Hitbox (default capsule). Do NOT instantiate the
	# player scene here to read it: its FusionSharedReplicator registers with
	# the native client and crashes the real spawn (Fusion preview bug).
	_spawn_shape = CapsuleShape3D.new()
	_spawn_half_height = (_spawn_shape as CapsuleShape3D).height * 0.5


func _find_spawn_transform(excluded_player: Node = null) -> Variant:
	if _spawn_shape == null:
		return null
	var markers := get_tree().get_nodes_in_group("spawn_point")
	if markers.is_empty():
		return null
	# ponytail: deterministic slots avoid a room reservation service; use
	# authoritative room reservations when concurrent joins can race.
	var start_index := 0
	if Fusion.is_in_room():
		start_index = maxi(Fusion.get_local_player_id() - 1, 0)
	for offset in range(markers.size()):
		var marker := markers[(start_index + offset) % markers.size()] as Node3D
		if marker == null:
			continue
		var candidate: Variant = _check_spawn_marker(marker, excluded_player)
		if candidate != null:
			return candidate
	return null


func _check_spawn_marker(marker: Node3D, excluded_player: Node = null) -> Variant:
	var space := get_world_3d().direct_space_state
	var marker_position := marker.global_position
	var floor_query := PhysicsRayQueryParameters3D.create(
		marker_position + Vector3.UP * SPAWN_RAY_HEIGHT,
		marker_position - Vector3.UP * SPAWN_RAY_HEIGHT,
		MAP_COLLISION_MASK)
	floor_query.collide_with_areas = false
	var floor_hit := space.intersect_ray(floor_query)
	if floor_hit.is_empty() or floor_hit.normal.angle_to(Vector3.UP) > FLOOR_MAX_ANGLE:
		return null

	var center: Vector3 = floor_hit.position + Vector3.UP * (_spawn_half_height + SPAWN_CLEARANCE)
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = _spawn_shape
	shape_query.transform = Transform3D(Basis.IDENTITY, center)
	shape_query.collision_mask = SPAWN_COLLISION_MASK
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = false
	shape_query.margin = 0.02
	if excluded_player != null:
		shape_query.exclude = [excluded_player.get_rid()]
	if not space.intersect_shape(shape_query, 1).is_empty():
		return null

	var ceiling_query := PhysicsRayQueryParameters3D.create(
		center,
		center + Vector3.UP * (_spawn_half_height + 0.25),
		MAP_COLLISION_MASK)
	ceiling_query.collide_with_areas = false
	if not space.intersect_ray(ceiling_query).is_empty():
		return null

	return Transform3D(Basis(Vector3.UP, marker.global_rotation.y), center)
