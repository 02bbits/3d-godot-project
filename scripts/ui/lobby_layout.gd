extends Control

## Fits the lobby's approved three-column composition inside the window.
## The scene owns its design dimensions; the original theme stays unchanged.

@export var design_size := Vector2.ZERO

@onready var content: Control = $V


func _ready() -> void:
	resized.connect(_fit)
	content.minimum_size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var required := design_size.max(content.get_combined_minimum_size())
	if required.x <= 0.0 or required.y <= 0.0:
		return
	content.size = required
	var factor := minf(size.x / required.x, size.y / required.y)
	content.scale = Vector2.ONE * factor
	content.position = (size - required * factor) * 0.5
