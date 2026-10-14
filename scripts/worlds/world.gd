extends Node3D

## World manager: spawns the local player when the match manager reports the
## game started, respawns everyone between matches, and runs the local
## spectator camera while the player is eliminated. The match manager owns the
## room-property polling that used to live here. During the modifier draft the
## view is a flyover of the coming map (map_camera.gd).

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
	"res://scenes/worlds/arena_citadel.tscn",
	"res://scenes/worlds/arena_foundry.tscn",
	"res://scenes/worlds/arena_causeway.tscn",
	"res://scenes/worlds/arena_butterfly.tscn",
	"res://scenes/worlds/arena_spire.tscn",
]
# Let the round-win announcement show before the wipe covers the screen; must
# stay under match_manager's ROUND_INTERMISSION_SECONDS.
const MAP_SWAP_DELAY := 3.0
# the local player is frozen (no move/shoot, look only) in these phases
const LOCKED_PHASES := ["draft", "countdown"]
# Let the swapped-in map build (GridMap tiles, collisions) before anyone is
# respawned into it.
const MAP_SETTLE_SECONDS := 1.0

@onready var player_spawner: FusionSpawner = $PlayerSpawner
@onready var connection_menu: Control = $MenuLayer/ConnectionMenu
@onready var match_manager: Node = $MatchManager
@onready var map_root: Node3D = $MapRoot
# match transitions: wipe, announcements, countdown, slow motion
@onready var match_flow: CanvasLayer = $MatchFlow
# third-person camera while the local player is eliminated
@onready var spectator: Node3D = $Spectator
# flyover of the coming map behind the draft
@onready var map_camera: Node3D = $MapCamera

var local_player: PlayerCharacter
var spawn_points: Array[Node3D] = []
var _current_map := 0
var _swapping := false
var _scene_registered := false


func _ready() -> void:
	_collect_spawn_points()

	match_manager.map_count = MAP_PATHS.size()
	match_manager.game_started.connect(_start_game)
	match_manager.respawn_requested.connect(_respawn_local_player)
	match_manager.map_changed.connect(_on_map_changed)
	match_manager.returned_to_lobby.connect(_return_to_lobby)
	match_manager.phase_changed.connect(_apply_input_lock.unbind(2))
	match_manager.phase_changed.connect(_on_phase_changed)


func _process(_delta: float) -> void:
	_update_spectator()


# "res://scenes/worlds/arena_pillars.tscn" -> "PILLARS"
static func map_display_name(index: int) -> String:
	var file: String = MAP_PATHS[index].get_file().get_basename()
	return file.trim_prefix("arena_").replace("_", " ").to_upper()


func respawn_player(player: PlayerCharacter) -> void:
	spectator.stop()
	if spawn_points.is_empty():
		return
	var spawn_point: Node3D = _spawn_point_for(player)
	# Spawn markers are floor points (y at the KayKit floor slab's center), but
	# the player's origin is its capsule center: lift it clear or it spawns
	# embedded in the floor and tunnels through it.
	# ponytail: flat-floor assumption; raycast the floor like /fps's
	# _find_spawn_transform if markers ever sit on slopes or platforms.
	var lift := player.base_hitbox_height * 0.5 + 0.5
	player.reset_for_respawn(spawn_point.global_transform.translated(Vector3.UP * lift))


# Every match the host shuffles distinct marker slots for every player
# (match_manager.spawn_slots). Before the first assignment (the spawn at game
# start, hidden behind the draft) each client indexes the sorted markers with
# its place among the sorted room player numbers.
func _spawn_point_for(player: PlayerCharacter) -> Node3D:
	var slot: int = match_manager.spawn_slot_of(player)
	if slot >= 0:
		return spawn_points[slot % spawn_points.size()]
	if Engine.has_singleton("Fusion") and Fusion.is_in_room():
		var room = Fusion.get_room()
		if room != null:
			var ids: Array[int] = []
			for p in room.get_players():
				ids.append(int(p.get_number()))
			ids.sort()
			slot = ids.find(int(Fusion.get_local_player_id()))
			if slot >= 0:
				return spawn_points[slot % spawn_points.size()]
	return spawn_points.pick_random()


# PRIVATE METHODS

func _start_game() -> void:
	# a game opens on the lobby's chosen map: swap it in (behind the menu, which
	# hides on game_started) and let its colliders register before spawning
	var index: int = match_manager.map_index
	if index != _current_map and index >= 0 and index < MAP_PATHS.size():
		_swap_map(index)
		await get_tree().physics_frame
		await get_tree().physics_frame
	_spawn_local_player()

	# Make sure the scene objects are registered; the scene never reloads, so
	# registering it on every match would only pile registrations up
	if Fusion.is_master_client() and not _scene_registered:
		Fusion.register_current_scene()
		_scene_registered = true

	game_started.emit()


func _respawn_local_player() -> void:
	if local_player == null:
		map_camera.stop()
		return
	# the round start can land while the new map is still being swapped in
	while _swapping:
		await get_tree().process_frame
	# the teleport (and the cut back from the map flyover) happens behind the
	# wipe, then the countdown reveals the arena
	await match_flow.cover()
	map_camera.stop()
	if local_player != null:
		respawn_player(local_player)
	match_flow.reveal()


# The draft shows the map flyover; it ends behind the countdown's respawn wipe
# (_respawn_local_player), or right away if the game moves anywhere else.
func _on_phase_changed(phase: String, _previous: String) -> void:
	if phase == "draft":
		spectator.stop()
		map_camera.start(map_root.get_child(0))
	elif phase != "countdown":
		map_camera.stop()


func _apply_input_lock() -> void:
	if local_player != null:
		local_player.set_input_locked(match_manager.match_phase in LOCKED_PHASES)


# Game over finished: remove the local player and hand the UI back to the lobby.
func _return_to_lobby() -> void:
	spectator.stop()
	map_camera.stop()
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


# Both host (when it advances the index) and clients (when the room property
# arrives) end up here. Wipe in, swap the MapRoot child, wipe back out.
func _on_map_changed(index: int) -> void:
	if _swapping or index == _current_map or index < 0 or index >= MAP_PATHS.size():
		return
	_swapping = true
	await get_tree().create_timer(MAP_SWAP_DELAY, true, false, true).timeout
	await match_flow.cover()
	_swap_map(index)
	# let the new map finish building before it receives players
	await get_tree().create_timer(MAP_SETTLE_SECONDS, true, false, true).timeout
	match_flow.reveal()
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
	if map_camera.active:
		map_camera.start(map_root.get_child(0))


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
	if player.net_color == "" and connection_menu != null \
			and connection_menu.has_method("get_robot_color"):
		player.net_color = connection_menu.get_robot_color().to_html(false)
	_apply_input_lock()
	local_player_changed.emit(player)


# SPECTATOR

# While the local player is eliminated, watch a living player in third person
# (spectator.gd: mouse orbits, A/D cycles). Runs only on the dead client.
func _update_spectator() -> void:
	if local_player == null or not local_player.dead or map_camera.active:
		spectator.stop()
		return
	var target: Node3D = spectator.follow(local_player)
	if target != null:
		local_player.death_screen.set_spectate_target(target.net_nickname)
