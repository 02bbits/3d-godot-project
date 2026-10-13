extends Control

## Directional damage feedback (scenes/player/hud/hit_flash.tscn): flashes the
## screen corner the damage came from. The direction arrives in camera space
## (x right, y up, -z forward): hits from the front light the top corners,
## from behind the bottom ones. Unknown sources (fall damage) light every
## corner. Bigger hits flash brighter.

const MIN_ALPHA := 0.3
# corner alpha per fraction of max health lost (a 34-damage hit ≈ 0.6)
const ALPHA_PER_HEALTH := 2.0
const FADE_TIME := 0.4

@onready var corners: Array[TextureRect] = [
	$TopLeft, $TopRight, $BottomLeft, $BottomRight,
]

var _tween: Tween


func flash(health_fraction: float, from_direction: Vector3 = Vector3.ZERO) -> void:
	var alpha := clampf(health_fraction * ALPHA_PER_HEALTH, MIN_ALPHA, 1.0)
	var active := _active_corners(from_direction)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for i in corners.size():
		corners[i].modulate.a = alpha if active.has(i) else 0.0
	_tween = create_tween().set_parallel(true)
	for i in active:
		_tween.tween_property(corners[i], "modulate:a", 0.0, FADE_TIME)


# corner index: 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right
func _active_corners(from_direction: Vector3) -> Array:
	if from_direction == Vector3.ZERO:
		return [0, 1, 2, 3]
	var row := 0 if from_direction.z < 0.0 else 2 # front row, behind row
	var planar := Vector2(from_direction.x, from_direction.z).length()
	# dead ahead/behind: light both corners of the row instead of picking a side
	if planar > 0.0 and absf(from_direction.x) / planar < 0.35:
		return [row, row + 1]
	return [row + (1 if from_direction.x >= 0.0 else 0)]
