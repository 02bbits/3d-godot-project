extends Node3D

## World manager. On room join every client spawns its own player through the
## Fusion spawner (each owning its copy); the master client registers the
## scene so static networked objects (targets) are shared.

signal local_player_changed(player: PlayerCharacter)

@onready var player_spawner: FusionSpawner = $PlayerSpawner
@onready var connection_menu: Control = $ConnectionMenu

var local_player: PlayerCharacter
var spawn_points: Array[Node3D] = []


func _ready() -> void:
	for point in get_tree().get_nodes_in_group("spawn_point"):
		spawn_points.append(point)

	Fusion.room_joined.connect(_on_room_joined)


func respawn_player(player: PlayerCharacter) -> void:
	if spawn_points.is_empty():
		return
	var spawn_point: Node3D = spawn_points.pick_random()
	# Spawn markers are floor points (y at the KayKit floor slab's center), but
	# the player's origin is its capsule center: lift it clear or it spawns
	# embedded in the floor and tunnels through it.
	# ponytail: flat-floor assumption; raycast the floor like /fps's
	# _find_spawn_transform if markers ever sit on slopes or platforms.
	var lift := player.base_hitbox_height * 0.5 + 0.05
	player.reset_for_respawn(spawn_point.global_transform.translated(Vector3.UP * lift))


# SIGNAL HANDLERS

func _on_room_joined() -> void:
	_spawn_local_player()

	# Make sure the scene objects are registered
	if Fusion.is_master_client():
		Fusion.register_current_scene()


# PRIVATE METHODS

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
	# the nickname from the connection menu is the replicated player identity
	if player.net_nickname == "" and connection_menu != null \
			and connection_menu.has_method("get_nickname"):
		player.net_nickname = connection_menu.get_nickname()
	local_player_changed.emit(player)
