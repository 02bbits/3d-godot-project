class_name Crosshair

extends Control

# Draws a classic 4-bar crosshair centered on the screen.
# Place inside a full-rect CenterContainer; size determines scaling.

const COLOR := Color(1, 1, 1, 0.9)
const GAP := 6.0
const LEN := 8.0
const THICK := 2.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var half := THICK * 0.5
	draw_rect(Rect2(c + Vector2(-LEN - GAP - half, -half), Vector2(LEN, THICK)), COLOR)
	draw_rect(Rect2(c + Vector2(GAP + half, -half), Vector2(LEN, THICK)), COLOR)
	draw_rect(Rect2(c + Vector2(-half, -LEN - GAP - half), Vector2(THICK, LEN)), COLOR)
	draw_rect(Rect2(c + Vector2(-half, GAP + half), Vector2(THICK, LEN)), COLOR)
