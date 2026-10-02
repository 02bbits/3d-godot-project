class_name Health
extends Node

signal damaged(amount: float, attacker_id: int)
signal died(attacker_id: int)
signal health_changed(current: float, previous: float)

@export var max_health: float = 100.0

# Single source of truth. Written locally by the owner and by the Fusion
# replicator on remote copies; everyone else reads through `health`.
var net_health: float = 100.0:
	set(value):
		if value == net_health:
			return
		var previous := net_health
		net_health = value
		health_changed.emit(value, previous)

var health: float:
	get:
		return net_health
	set(value):
		net_health = value


func _ready() -> void:
	net_health = max_health


# Returns true when this hit was lethal. The victim's client runs this; the
# attacker id rides along for kill attribution (scoring, kill feed, confirm).
func apply(amount: float, attacker_id: int = -1) -> bool:
	if health <= 0.0 or amount <= 0.0:
		return false
	health = maxf(health - minf(amount, max_health), 0.0)
	damaged.emit(amount, attacker_id)
	if health <= 0.0:
		died.emit(attacker_id)
		return true
	return false


func heal(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = minf(health + amount, max_health)


func reset() -> void:
	health = max_health
