@tool
extends Control

## Design mascot: a rounded square with two eyes. Reused across the menu
## (title row, name screen, player chips). Set `icon_color` per instance.

@export var icon_color := Color("#FFC933") : set = _set_icon_color

const EYE_COLOR := Color("#1B2029")
const CORNER_RATIO := 0.16
const EYE_RADIUS_RATIO := 0.075
const EYE_X_RATIO := 0.30
const EYE_Y_RATIO := 0.38


func _set_icon_color(value: Color) -> void:
	icon_color = value
	queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var side := minf(size.x, size.y)
	var box := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var style := StyleBoxFlat.new()
	style.bg_color = icon_color
	var radius := int(side * CORNER_RATIO)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	draw_style_box(style, box)
	var eye_radius := side * EYE_RADIUS_RATIO
	for ratio in [EYE_X_RATIO, 1.0 - EYE_X_RATIO]:
		draw_circle(
			box.position + Vector2(side * ratio, side * EYE_Y_RATIO),
			eye_radius, EYE_COLOR)
