extends Node3D

const ENEMY_SCENE = preload("res://scenes/entities/enemy.tscn")

const INTERVAL = 5.0
const SPAWN_MIN_DIST = 20.0
const SPAWN_MAX_DIST = 30.0
const MAX_ENEMIES = 8

var elapsed := 0.0

func _ready() -> void:
	spawn()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= INTERVAL:
		elapsed = 0.0
		spawn()

func spawn() -> void:
	if get_tree().get_nodes_in_group("enemy").size() >= MAX_ENEMIES:
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var angle = randf() * TAU
	var distance = randf_range(SPAWN_MIN_DIST, SPAWN_MAX_DIST)
	var enemy = ENEMY_SCENE.instantiate()
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = player.global_position + Vector3(cos(angle), 0, sin(angle)) * distance
	enemy.global_position.y = 0.5