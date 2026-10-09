extends Node3D

## World manager. Clients only spawn a player once the host starts the game:
## joining a room puts the client in the lobby UI, not the map. The host flips
## the room's "phase" custom property to "playing"; every client polls it
## (Fusion has no room-property-changed signal) and then spawns through the
## Fusion spawner. The master client registers the scene so static networked
## objects (targets) are shared.

signal local_player_changed(player: PlayerCharacter)
signal game_started

@onready var player_spawner: FusionSpawner = $PlayerSpawner
@onready var connection_menu: Control = $ConnectionMenu

var local_player: PlayerCharacter
var spawn_points: Array[Node3D] = []
var _game_started := false
var _phase_poll := 0.0


func _ready() -> void:
	for point in get_tree().get_nodes_in_group("spawn_point"):
		spawn_points.append(point)


func _process(delta: float) -> void:
	if _game_started or not Fusion.is_in_room():
		return
	_phase_poll -= delta
	if _phase_poll > 0.0:
		return
	_phase_poll = 0.25
	# ponytail: 0.25s poll of a cached room property; Fusion exposes no
	# room-property-changed signal, and an RPC channel is not worth it.
	var room = Fusion.get_room()
	if room == null:
		return
	var properties: Dictionary = room.get_custom_properties()
	if str(properties.get("phase", "waiting")) == "playing":
		_start_game()


func respawn_player(player: PlayerCharacter) -> void:
	if spawn_points.is_empty():
		return
	var spawn_point: Node3D = spawn_points.pick_random()
	# Spawn markers are floor points (y at the KayKit floor slab's center), but
	# the player's origin is its capsule center: lift it clear or it spawns
	# embedded in the floor and tunnels through it.
	# ponytail: flat-floor assumption; raycast the floor like /fps's
	# _find_spawn_transform if markers ever sit on slopes or platforms.
	var lift := player.base_hitbox_height * 0.5 + 0.5
	player.reset_for_respawn(spawn_point.global_transform.translated(Vector3.UP * lift))


# PRIVATE METHODS

func _start_game() -> void:
	_game_started = true
	_spawn_local_player()

	# Make sure the scene objects are registered
	if Fusion.is_master_client():
		Fusion.register_current_scene()

	game_started.emit()


func _spawn_local_player() -> void:
	if local_player != null:
		player_spawner.despawn(local_player)

	# Each client spawns its own player and has authority over it
	var player := player_spawner.spawn() as PlayerCharacter
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
