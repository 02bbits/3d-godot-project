extends CharacterBody3D

const SPEED = 2.0
const ATTACK_RANGE = 1.8
const ATTACK_INTERVAL = 1.0

var health = 3
var cooldown := 1.0

@onready var animPlayer = $AnimationPlayer
@onready var skeleton3d = $Skeleton3D
func _ready() -> void:
	add_to_group("enemy")
	_play_anim("run")

func _nearest_player() -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		if p.get("dead"):
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best = p
			best_d = d
	return best

func _find_anim(keyword: String) -> String:
	for name in animPlayer.get_animation_list():
		if keyword.to_lower() in name.to_lower():
			return name
	return ""

func _play_anim(keyword: String) -> void:
	var name = _find_anim(keyword)
	if name.is_empty() or animPlayer.current_animation == name:
		return
	animPlayer.play(name)

func _physics_process(delta: float) -> void:
	var player := _nearest_player()
	if not player:
		return
	var to_player = player.global_position - global_position
	to_player.y = 0.0
	var dist = to_player.length()
	if dist > ATTACK_RANGE:
		_play_anim("run")
		var dir = to_player.normalized()
		velocity = dir * SPEED
		look_at(global_position + dir)
	else:
		cooldown -= delta
		_play_anim("attack")
		if cooldown > 0.0:
			return
		player.take_damage(20)
		velocity = Vector3.ZERO
		cooldown = ATTACK_INTERVAL
	move_and_slide()

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		_play_anim("death")
		set_physics_process(false)
		velocity = Vector3.ZERO
		$CollisionShape3D.set_deferred("disabled", true)
		await animPlayer.animation_finished
		queue_free()
