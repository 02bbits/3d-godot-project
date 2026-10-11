extends Control

## Robot color popup, opened from the robot icon on the name screen. Picking a
## swatch applies at once; DONE, Esc or a click outside the card closes it.

signal color_chosen(color: Color)

const ROBOT_ICON := preload("res://scripts/ui/robot_icon.gd")

@onready var card: Control = $Center/Card
@onready var swatches: GridContainer = $Center/Card/V/Swatches
@onready var preview: Control = $Center/Card/V/Preview


func _ready() -> void:
	hide()
	$Center/Card/V/ColorDoneButton.pressed.connect(close)
	gui_input.connect(_on_backdrop_input)
	for color in RobotColor.PALETTE:
		var swatch: Control = ROBOT_ICON.new()
		swatch.icon_color = color
		swatch.custom_minimum_size = Vector2(60, 60)
		swatch.mouse_filter = Control.MOUSE_FILTER_STOP
		swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		swatch.pivot_offset_ratio = Vector2(0.5, 0.5)
		swatch.gui_input.connect(_on_swatch_input.bind(swatch))
		swatch.mouse_entered.connect(_pop.bind(swatch, 1.12))
		swatch.mouse_exited.connect(_pop.bind(swatch, 1.0))
		swatches.add_child(swatch)


func open(current: Color) -> void:
	_select(current)
	show()
	card.pivot_offset_ratio = Vector2(0.5, 0.5)
	card.scale = Vector2(0.9, 0.9)
	modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	tween.tween_property(card, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and not card.get_global_rect().has_point(event.global_position):
		close()


func _on_swatch_input(event: InputEvent, swatch: Control) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_select(swatch.icon_color)
		color_chosen.emit(swatch.icon_color)


func _select(color: Color) -> void:
	preview.icon_color = color
	for swatch in swatches.get_children():
		swatch.selected = swatch.icon_color.is_equal_approx(color)


func _pop(swatch: Control, target: float) -> void:
	create_tween().tween_property(swatch, "scale", Vector2.ONE * target, 0.1)
