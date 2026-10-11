class_name Stepper
extends HBoxContainer

## The menu's [-] value [+] picker over a fixed list of values (create-lobby
## form, settings). Buttons disable at the ends of the list.

signal changed(value: Variant)

@export var value_width := 120.0
@export var font_size := 30
@export var button_size := Vector2(52, 46)

var values: Array = []
var labels: Array = [] # display text per value; empty = str(value)
var index := 0
var value: Variant:
	get:
		return values[index] if index < values.size() else null

var _minus := Button.new()
var _plus := Button.new()
var _label := Label.new()


func _init() -> void:
	add_theme_constant_override("separation", 18)
	alignment = BoxContainer.ALIGNMENT_CENTER
	for button in [_minus, _plus]:
		button.theme_type_variation = &"PrimaryButton"
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_minus.text = "-"
	_plus.text = "+"
	_minus.pressed.connect(step.bind(-1))
	_plus.pressed.connect(step.bind(1))
	_label.theme_type_variation = &"TitleLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_minus)
	add_child(_label)
	add_child(_plus)


func _ready() -> void:
	_minus.custom_minimum_size = button_size
	_plus.custom_minimum_size = button_size
	_label.custom_minimum_size.x = value_width
	_label.add_theme_font_size_override("font_size", font_size)
	_refresh()


func setup(p_values: Array, start_value: Variant, p_labels: Array = []) -> void:
	values = p_values
	labels = p_labels
	index = maxi(values.find(start_value), 0)
	_refresh()


func step(direction: int) -> void:
	var next := clampi(index + direction, 0, values.size() - 1)
	if next == index:
		return
	index = next
	_refresh()
	changed.emit(value)


func _refresh() -> void:
	if values.is_empty():
		return
	_label.text = str(labels[index]) if index < labels.size() else str(values[index])
	_minus.disabled = index <= 0
	_plus.disabled = index >= values.size() - 1
