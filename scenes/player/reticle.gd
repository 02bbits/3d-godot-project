extends Control

## Crosshair from the HUD mockup: four white bars with a dark outline around
## the screen center (where the shot ray goes). The bars spread with planar
## speed and kick open on every shot.

@export var COLOR: Color = Color("#F4EEE2")
@export var OUTLINE_COLOR: Color = Color("#0E1015")
@export var GAP: float = 5.0
@export var LENGTH: float = 8.0
@export var WIDTH: float = 2.5
@export var OUTLINE: float = 1.2
@export var RETICLE_SPEED: float = 0.25
@export var RETICLE_DISTANCE: float = 0.6
@export var SHOT_KICK: float = 5.0
@export var PLAYER_CHARACTER: CharacterBody3D

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
	queue_redraw()


# Drawn around the control's center: its origin is the top-left corner, which
# would put the reticle off the screen center.
func _draw() -> void:
	var center := size * 0.5
	for dir: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var start := center + dir * (GAP + _spread + _kick)
		var end := start + dir * LENGTH
		draw_line(start, end, COLOR, WIDTH)
