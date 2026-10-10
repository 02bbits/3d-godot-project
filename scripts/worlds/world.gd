extends Node3D

## World manager: spawns the local player when the match manager reports the
## game started, respawns everyone between matches, and runs the local
## spectator camera while the player is eliminated. The match manager owns the
## room-property polling that used to live here.

signal local_player_changed(player: PlayerCharacter)
signal game_started
signal game_ended

# Rotation order. Index 0 is already instanced in main.tscn; the rest are
# baked GridMap scenes swapped into MapRoot.
const MAP_PATHS := [
	"res://scenes/worlds/testing_area.tscn",
	"res://scenes/worlds/arena_pillars.tscn",
	"res://scenes/worlds/arena_lanes.tscn",
	"res://scenes/worlds/arena_cross.tscn",
	"res://scenes/worlds/arena_ring.tscn",
]
# Let the round-win banner show before the fade covers the screen; must stay
# under match_manager's ROUND_INTERMISSION_SECONDS.
const MAP_SWAP_DELAY := 3.0
const FADE_TIME := 0.35
# Let the swapped-in map build (GridMap tiles, collisions) before anyone is
# respawned into it.
const MAP_SETTLE_SECONDS := 1.0

@onready var player_spawner: FusionSpawner = $PlayerSpawner
@onready var connection_menu: Control = $MenuLayer/ConnectionMenu
@onready var match_manager: Node = $MatchManager
@onready var map_root: Node3D = $MapRoot

var local_player: PlayerCharacter
var spawn_points: Array[Node3D] = []
var spectator_camera: Camera3D
var _spectate_targets: Array = []
var _spectate_index := 0
var _current_map := 0
var _swapping := false
var _scene_registered := false
var _fade: ColorRect


func _ready() -> void:
	_collect_spawn_points()
	_setup_fade()

	match_manager.map_count = MAP_PATHS.size()
	match_manager.game_started.connect(_start_game)
	match_manager.respawn_requested.connect(_respawn_local_player)
	match_manager.map_changed.connect(_on_map_changed)
	match_manager.returned_to_lobby.connect(_return_to_lobby)


func _process(delta: float) -> void:
	_update_spectator(delta)


func respawn_player(player: PlayerCharacter) -> void:
	_stop_spectating()
	if spawn_points.is_empty():
		return
	var spawn_point: Node3D = _spawn_point_for_local_player()
	# Spawn markers are floor points (y at the KayKit floor slab's center), but
	# the player's origin is its capsule center: lift it clear or it spawns
	# embedded in the floor and tunnels through it.
	# ponytail: flat-floor assumption; raycast the floor like /fps's
	# _find_spawn_transform if markers ever sit on slopes or platforms.
	var lift := player.base_hitbox_height * 0.5 + 0.5
	player.reset_for_respawn(spawn_point.global_transform.translated(Vector3.UP * lift))


# Every client indexes the same sorted spawn list with the same sorted room
# player numbers, so two players can never be handed the same marker.
func _spawn_point_for_local_player() -> Node3D:
	if Engine.has_singleton("Fusion") and Fusion.is_in_room():
		var room = Fusion.get_room()
		if room != null:
			var ids: Array[int] = []
			for p in room.get_players():
				ids.append(int(p.get_number()))
			ids.sort()
			var slot := ids.find(int(Fusion.get_local_player_id()))
			if slot >= 0:
				return spawn_points[slot % spawn_points.size()]
	return spawn_points.pick_random()


# PRIVATE METHODS

func _start_game() -> void:
	_spawn_local_player()

	# Make sure the scene objects are registered; the scene never reloads, so
	# registering it on every match would only pile registrations up
	if Fusion.is_master_client() and not _scene_registered:
		Fusion.register_current_scene()
		_scene_registered = true

	game_started.emit()


func _respawn_local_player() -> void:
	if local_player == null:
		return
	# the round start can land while the new map is still being swapped in
	while _swapping:
		await get_tree().process_frame
	respawn_player(local_player)


# Game over finished: remove the local player and hand the UI back to the lobby.
func _return_to_lobby() -> void:
	_stop_spectating()
	if local_player != null:
		player_spawner.despawn(local_player)
		local_player = null
	game_ended.emit()


# MAP ROTATION

func _collect_spawn_points() -> void:
	spawn_points.clear()
	for point in get_tree().get_nodes_in_group("spawn_point"):
		spawn_points.append(point)
	# stable order: every client maps the same player number to the same marker
	spawn_points.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.name < b.name)


func _setup_fade() -> void:
	# covers the map swap; top layer so the transition hides everything
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


# Both host (when it advances the index) and clients (when the room property
# arrives) end up here. Fade out, swap the MapRoot child, fade back in.
func _on_map_changed(index: int) -> void:
	if _swapping or index == _current_map or index < 0 or index >= MAP_PATHS.size():
		return
	_swapping = true
	await get_tree().create_timer(MAP_SWAP_DELAY).timeout
	var out := create_tween()
	out.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await out.finished
	_swap_map(index)
	# let the new map finish building before it receives players
	await get_tree().create_timer(MAP_SETTLE_SECONDS).timeout
	await get_tree().create_timer(0.15).timeout
	var back := create_tween()
	back.tween_property(_fade, "color:a", 0.0, FADE_TIME)
	await back.finished
	_swapping = false


func _swap_map(index: int) -> void:
	for child in map_root.get_children():
		child.free()
	var scene: PackedScene = load(MAP_PATHS[index])
	if scene == null:
		return
	map_root.add_child(scene.instantiate())
	_current_map = index
	_collect_spawn_points()


func _spawn_local_player() -> void:
	if local_player != null:
		player_spawner.despawn(local_player)

	# Each client spawns its own player and has authority over it
	var player := player_spawner.spawn() as PlayerCharacter
	# the node we spawned is ours: don't wait for the authority snapshot to
	# resolve before simulating (a client stuck as "remote" would float)
	player.claim_local_role()
	if player.network_role_ready:
		_register_local_player(player)
		respawn_player(player)
	else:
		player.network_ready.connect(_on_network_ready.bind(player), CONNECT_ONE_SHOT)


func _on_network_ready(player: PlayerCharacter) -> void:
	_register_local_player(player)
	respawn_player(player)


func _register_local_player(player: PlayerCharacter) -> void:
	local_player = player
	# the nickname from the menu is the replicated player identity
	if player.net_nickname == "" and connection_menu != null \
			and connection_menu.has_method("get_nickname"):
		player.net_nickname = connection_menu.get_nickname()
	local_player_changed.emit(player)


# SPECTATOR

# While the local player is eliminated, follow a living player in third person
# and cycle targets with the arrow keys. Runs only on the dead client's machine.
func _update_spectator(delta: float) -> void:
	if local_player == null:
		return
	if not local_player.dead:
		_stop_spectating()
		return
	_refresh_spectate_targets()
	if _spectate_targets.is_empty():
		return
	# the player's own move bindings: A/D by default, arrows included
	if Input.is_action_just_pressed(local_player.move_left_action):
		_spectate_index = wrapi(_spectate_index - 1, 0, _spectate_targets.size())
	if Input.is_action_just_pressed(local_player.move_right_action):
		_spectate_index = wrapi(_spectate_index + 1, 0, _spectate_targets.size())
	var target := instance_from_id(_spectate_targets[_spectate_index]) as Node3D
	if target == null:
		return
	var head: Vector3 = target.global_position + Vector3.UP * 1.5
	var yaw: float = target.cam_holder.rotation.y
	var desired: Vector3 = head + Vector3(sin(yaw), 0.0, cos(yaw)) * 3.5 + Vector3.UP * 0.5
	if spectator_camera == null:
		spectator_camera = Camera3D.new()
		spectator_camera.fov = 90.0
		add_child(spectator_camera)
		spectator_camera.global_position = desired
		spectator_camera.current = true
	spectator_camera.global_position = spectator_camera.global_position.lerp(
			desired, clampf(delta * 10.0, 0.0, 1.0))
	spectator_camera.look_at(head, Vector3.UP)
	if local_player.death_screen.has_method("set_spectate_target"):
		local_player.death_screen.set_spectate_target(target.net_nickname)


func _refresh_spectate_targets() -> void:
	# instance ids survive frees: an object reference would crash when a target
	# despawns between frames (e.g. players leaving when returning to the lobby)
	var previous_id: int = 0
	if _spectate_index < _spectate_targets.size():
		previous_id = _spectate_targets[_spectate_index]
	_spectate_targets = []
	for p in get_tree().get_nodes_in_group("player"):
		if p == local_player or not is_instance_valid(p) or p.dead:
			continue
		_spectate_targets.append(p.get_instance_id())
	_spectate_index = _spectate_targets.find(previous_id)
	if _spectate_index < 0:
		_spectate_index = 0


func _stop_spectating() -> void:
	_spectate_targets.clear()
	_spectate_index = 0
	if spectator_camera == null:
		return
	spectator_camera.current = false
	spectator_camera.queue_free()
	spectator_camera = null
