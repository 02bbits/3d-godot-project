@tool
extends Control

## Design mascot: a rounded square with two eyes. Reused across the menu
## (title row, name screen, player chips, color picker, card art). Set
## `icon_color` per instance; `animate` adds an idle bob and blink.

@export var icon_color := Color("#FFC933") : set = _set_icon_color
## idle bob + blink (main menu, color preview)
@export var animate := false
## ring drawn around the icon (selected color swatch)
@export var selected := false : set = _set_selected
## small palette badge in the corner: "click me to recolor"
@export var badge := false : set = _set_badge

const EYE_COLOR := Color("#1B2029")
const RING_COLOR := Color("#F4EEE2")
const CORNER_RATIO := 0.16
const EYE_RADIUS_RATIO := 0.075
const EYE_X_RATIO := 0.30
const EYE_Y_RATIO := 0.38
const BOB_PIXELS := 3.0
const BADGE_COLORS := [Color("#FFC933"), Color("#4DA2FE"), Color("#FF6A5C")]

# random phase so a row of icons doesn't move in lockstep
var _phase := randf() * TAU
var _next_blink := randf_range(1.5, 4.0)
var _blink := 0.0


func _set_icon_color(value: Color) -> void:
	icon_color = value
	queue_redraw()


func _set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func _set_badge(value: bool) -> void:
	badge = value
	queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	if not animate or Engine.is_editor_hint() or not is_visible_in_tree():
		return
	_phase += delta * 2.4
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.14
		_next_blink = randf_range(2.0, 5.0)
	_blink = maxf(_blink - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var box := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	if animate:
		box.position.y += sin(_phase) * BOB_PIXELS
	if selected:
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_border_width_all(maxi(int(side * 0.05), 2))
		ring.border_color = RING_COLOR
		ring.set_corner_radius_all(int(side * (CORNER_RATIO + 0.08)))
		draw_style_box(ring, box.grow(side * 0.1))
	draw_robot(self, box, icon_color, 0.0, _blink > 0.0)
	if badge:
		var center := box.end - Vector2(side, side) * 0.08
		var radius := side * 0.2
		draw_circle(center, radius + 2.0, EYE_COLOR)
		draw_circle(center, radius, RING_COLOR)
		for i in BADGE_COLORS.size():
			var angle := -PI * 0.5 + TAU * i / BADGE_COLORS.size()
			draw_circle(center + Vector2.from_angle(angle) * radius * 0.45,
					radius * 0.28, BADGE_COLORS[i])


## The mascot shape itself, shared with drawings that place several robots
## (card art). `outline` > 0 adds a dark border; `blink` closes the eyes.
static func draw_robot(canvas: CanvasItem, box: Rect2, color: Color,
		outline := 0.0, blink := false) -> void:
	var side := minf(box.size.x, box.size.y)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(side * CORNER_RATIO))
	if outline > 0.0:
		style.set_border_width_all(int(outline))
		style.border_color = EYE_COLOR
	canvas.draw_style_box(style, box)
	var eye_radius := side * EYE_RADIUS_RATIO
	for ratio in [EYE_X_RATIO, 1.0 - EYE_X_RATIO]:
		var eye := box.position + Vector2(side * ratio, side * EYE_Y_RATIO)
		if blink:
			canvas.draw_line(eye - Vector2(eye_radius, 0.0), eye + Vector2(eye_radius, 0.0),
					EYE_COLOR, maxf(eye_radius * 0.6, 1.5))
		else:
			canvas.draw_circle(eye, eye_radius, EYE_COLOR)
