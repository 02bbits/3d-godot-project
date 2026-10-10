extends CenterContainer

@export var DOT_RADIUS: float = 1.0
@export var DOT_COLOR: Color = Color.WHITE
@export var RETICLE_LINES: Array[Line2D]
@export var RETICLE_SPEED: float = 0.25
@export var RETICLE_DISTANCE: float = 2.0
@export var PLAYER_CHARACTER: CharacterBody3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	queue_redraw()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	adjust_reticle_lines()

func _draw() -> void:
	draw_circle(Vector2(0, 0), DOT_RADIUS, DOT_COLOR)

func adjust_reticle_lines() -> void:
	if PLAYER_CHARACTER == null or RETICLE_LINES.size() < 4:
		return
	# planar speed: get_real_velocity() includes falling, which would push the
	# lines out while airborne for no reason
	var vel := PLAYER_CHARACTER.get_real_velocity()
	var speed := Vector2(vel.x, vel.z).length()
	var pos := Vector2.ZERO

	# Adjust lines' position (top, right, bottom, left)
	RETICLE_LINES[0].position = RETICLE_LINES[0].position.lerp(
			pos + Vector2(0, -speed * RETICLE_DISTANCE), RETICLE_SPEED)
	RETICLE_LINES[1].position = RETICLE_LINES[1].position.lerp(
			pos + Vector2(speed * RETICLE_DISTANCE, 0), RETICLE_SPEED)
	RETICLE_LINES[2].position = RETICLE_LINES[2].position.lerp(
			pos + Vector2(0, speed * RETICLE_DISTANCE), RETICLE_SPEED)
	RETICLE_LINES[3].position = RETICLE_LINES[3].position.lerp(
			pos + Vector2(-speed * RETICLE_DISTANCE, 0), RETICLE_SPEED)
