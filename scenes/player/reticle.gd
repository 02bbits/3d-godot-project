extends Control

## Crosshair from the HUD mockup: four outlined bars (scenes/player/hud/
## reticle.tscn) around the screen center, where the shot ray goes. The bars
## spread with planar speed and kick open on every shot.

@export var GAP: float = 5.0
@export var RETICLE_SPEED: float = 0.25
@export var RETICLE_DISTANCE: float = 0.6
@export var SHOT_KICK: float = 5.0
@export var PLAYER_CHARACTER: CharacterBody3D

@onready var up: Control = $Up
@onready var down: Control = $Down
@onready var left: Control = $Left
@onready var right: Control = $Right

var _spread := 0.0
var _kick := 0.0


func kick() -> void:
	_kick = SHOT_KICK


func _process(delta: float) -> void:
	if PLAYER_CHARACTER == null:
		return
	# planar speed: get_real_velocity() includes falling, which would push the
	# bars out while airborne for no reason
	var vel := PLAYER_CHARACTER.get_real_velocity()
	_spread = lerpf(_spread, Vector2(vel.x, vel.z).length() * RETICLE_DISTANCE, RETICLE_SPEED)
	_kick = move_toward(_kick, 0.0, delta * SHOT_KICK * 8.0)
	# bars sit around this control's center (the screen center), rounded to
	# whole pixels so the 1px outline stays crisp
	var d := GAP + _spread + _kick
	var c := size * 0.5
	up.position = (c + Vector2(-up.size.x * 0.5, -d - up.size.y)).round()
	down.position = (c + Vector2(-down.size.x * 0.5, d)).round()
	left.position = (c + Vector2(-d - left.size.x, -left.size.y * 0.5)).round()
	right.position = (c + Vector2(d, -right.size.y * 0.5)).round()
