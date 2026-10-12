extends Control

## The original crosshair (scenes/player/hud/reticle.tscn): a center dot and
## four lines that spread apart with the player's planar speed and ease back
## when they slow down. Everything sits around this control's center, which
## is the screen center where the shot ray goes.

@export var RETICLE_SPEED: float = 0.25 # per-frame lerp toward the target spread
@export var RETICLE_DISTANCE: float = 2.0 # pixels of spread per m/s of speed
@export var PLAYER_CHARACTER: CharacterBody3D

@onready var dot: Control = $Dot
@onready var lines: Array[Line2D] = [$Top, $Right, $Bottom, $Left]

# directions of top, right, bottom, left
const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]


func _ready() -> void:
	for line in lines:
		line.position = size * 0.5


func _process(_delta: float) -> void:
	var center := size * 0.5
	dot.position = center - dot.size * 0.5
	if PLAYER_CHARACTER == null:
		return
	# planar speed: get_real_velocity() includes falling, which would push the
	# lines out while airborne for no reason
	var vel := PLAYER_CHARACTER.get_real_velocity()
	var speed := Vector2(vel.x, vel.z).length()
	for i in lines.size():
		lines[i].position = lines[i].position.lerp(
				center + DIRECTIONS[i] * speed * RETICLE_DISTANCE, RETICLE_SPEED)
