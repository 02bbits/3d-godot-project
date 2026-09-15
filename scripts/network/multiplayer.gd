extends Node3D

signal room_error(message: String)

const PlayerScene := preload("res://scripts/player/player.tscn")
const MAP_COLLISION_MASK := 1
const SPAWN_COLLISION_MASK := 3
const FLOOR_MAX_ANGLE := deg_to_rad(65.0)
const SPAWN_RAY_HEIGHT := 8.0
const SPAWN_CLEARANCE := 0.05

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


func _ready() -> void:
	if not Engine.has_singleton("Fusion"):
		push_error("Fusion is not available; multiplayer cannot start")
		return

	_prepare_spawn_shape()
	spawner.add_spawnable_scene(PlayerScene)
	Fusion.connected_to_photon.connect(_on_connected_to_photon)
	Fusion.connection_failed.connect(_on_connection_failed)
	Fusion.connection_status_changed.connect(_on_connection_status_changed)
	Fusion.room_joined.connect(_on_room_joined)
	Fusion.room_left.connect(_on_room_left)
	Fusion.player_joined.connect(_on_player_joined)
	Fusion.player_left.connect(_on_player_left)
	Fusion.master_client_changed.connect(_on_master_client_changed)
	# Connect to Photon on boot (master lobby, for the room browser); a room is
	# only joined/created when the user picks one in the lobby.
	_connect_to_photon.call_deferred()


# Host a new room; fails cleanly (room_error) if the name is taken.
func host_room(name: String) -> void:
	_request_room(name, true)


# Join an existing room by name.
func join_room(name: String) -> void:
	_request_room(name, false)


func _request_room(name: String, create: bool) -> void:
	name = name.strip_edges()
	if name.is_empty() or name.length() > 32 \
			or not RegEx.create_from_string("^[A-Za-z0-9_.\\- ]+$").search(name):
		room_error.emit("Room name must be 1-32 chars: letters, digits, space, _ - .")
		return
	_room_name = name
	_create_mode = create
	if _room_request_pending:
		return
	if Fusion.is_connected_to_photon() and not Fusion.is_in_room():
		_join_room_now()
	else:
		_connect_to_photon()


func _join_room_now() -> void:
	_room_request_pending = true
	_join_started = true
	var options := FusionRoomOptions.new()
	# matches the ten SpawnPoints markers; more players would leave a joiner
	# without a free validated spawn
	options.max_players = 6
	# Remove players that stop responding, and let the room die after the last
	# player leaves so stale rooms cannot accumulate ghosts.
	options.player_ttl_ms = 10000
	options.empty_room_ttl_ms = 30000
	if _create_mode:
		Fusion.create_room(_room_name, options)
	else:
		Fusion.join_room(_room_name, options)
	_watch_room_join()


# ponytail: this Fusion build has no room-join-failed signal, so failure is
# detected by timeout. Use a real failure callback when the addon ships one.
func _watch_room_join() -> void:
	await get_tree().create_timer(8.0).timeout
	if not _room_request_pending or _room_ready:
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


func _on_connected_to_photon() -> void:
	if _room_ready or _room_name.is_empty():
		return
	print("connected, %s room" % ("creating" if _create_mode else "joining"))
	_join_room_now()


func _on_connection_failed(error: String) -> void:
	_join_started = false
	_room_ready = false
	_room_request_pending = false
	# Fusion also emits this for room join failures and stays on the master
	# server; only a real connect failure needs a reconnect on retry.
	_connection_started = Fusion.is_connected_to_photon()
	room_error.emit("Photon connection failed: " + error)
	push_error("Photon connection failed: " + error)


func _on_connection_status_changed(status: int) -> void:
	print("Photon connection status: ", status)


func _on_room_joined() -> void:
	if _room_ready:
		return
	_room_ready = true
	_join_started = false
	_room_request_pending = false
	_spawn_local_player.call_deferred()


func _on_room_left() -> void:
	_room_ready = false
	_join_started = false
	_room_request_pending = false
	_spawn_in_progress = false
	_restart_in_progress = false
	_local_player = null
	_players_by_owner.clear()
	_clear_local_player_nodes()


func _on_master_client_changed(old_id: int, new_id: int) -> void:
	print("Photon master client changed: ", old_id, " -> ", new_id)


func _on_player_joined(player_id: int, _user_id: String) -> void:
	if player_id != Fusion.get_local_player_id():
		_sync_life_state.call_deferred(player_id)


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


func _on_player_left(player_id: int, _is_inactive: bool) -> void:
	# ponytail: remove inactive players immediately; reconnect grace needs stable
	# account identity and a room-level reservation protocol.
	var player: Node = _players_by_owner.get(player_id)
	if player == null:
		player = _find_player_by_owner_id(player_id)
	_players_by_owner.erase(player_id)
	if player == null or not is_instance_valid(player):
		# ponytail: on a TTL reap Fusion can zero the replica's owner id before
		# player_left arrives (owner=0), so the per-id lookup misses; sweep
		# remote replicas not owned by an active room player instead.
		if not _sweep_departed_replicas():
			push_warning("Photon player left without a local replica: ", player_id)
		return
	if player == _local_player:
		_local_player = null
	print("removing disconnected player ", player_id, " at ", player.get_path())
	_remove_departed_player(player)


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
	if not _room_ready or _spawn_in_progress or is_instance_valid(_local_player):
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
