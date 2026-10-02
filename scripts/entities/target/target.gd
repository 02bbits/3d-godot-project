extends StaticBody3D

# Shootable dummy target. Damage is applied on the master client (owner_mode =
# MasterClient on the replicator) and shared with every client via net_health.

@export var max_health: float = 100.0
@export var respawn_time: float = 2.0

signal health_changed(current: float, previous: float)

@onready var replicator: FusionSharedReplicator = $FusionReplicator
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _visual: Node3D = $TargetVisual

var net_health: float = 100.0:
	set(value):
		if value == net_health:
			return
		var previous := net_health
		net_health = value
		health_changed.emit(value, previous)

var _respawn_generation := 0


func _ready() -> void:
	add_to_group("enemy")
	net_health = max_health
	health_changed.connect(_on_health_changed)


func _on_health_changed(current: float, previous: float) -> void:
	if current <= 0.0 and previous > 0.0:
		_die()
	elif current > 0.0 and previous <= 0.0:
		_revive()


func _die() -> void:
	_collision.disabled = true
	_visual.visible = false
	if not replicator.has_authority():
		return
	# Only the authority runs the respawn timer; the revive is shared through
	# the replicated net_health.
	_respawn_generation += 1
	var generation := _respawn_generation
	await get_tree().create_timer(respawn_time).timeout
	if not is_inside_tree() or generation != _respawn_generation:
		return
	net_health = max_health


func _revive() -> void:
	_collision.disabled = false
	_visual.visible = true


@rpc("any_peer")
func rpc_take_damage(amount: int) -> void:
	if not replicator.has_authority() or net_health <= 0.0:
		return
	net_health = maxf(net_health - float(amount), 0.0)
