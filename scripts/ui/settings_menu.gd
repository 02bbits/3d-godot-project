extends CenterContainer

## Settings page. Discrete choices use the menu's stepper, continuous ones a
## slider. Choices are saved to the shared user config and applied on load, so
## they survive restarts and the scene reload after leaving a game.

signal closed

const USER_CONFIG := "user://user_config.cfg"
# `options` rows step through a list; `range` rows ([min, max, step]) slide
const ROWS := [
	{key = "window", label = "WINDOW", options = ["WINDOWED", "FULLSCREEN"], default = "WINDOWED"},
	{key = "vsync", label = "VSYNC", options = ["ON", "OFF"], default = "ON"},
	{key = "max_fps", label = "MAX FPS", options = [30, 60, 120, 144, 240, 0], default = 0},
	{key = "post_fx", label = "POST EFFECTS", options = ["ON", "OFF"], default = "ON"},
	{key = "render_scale", label = "RENDER SCALE", range = [50, 100, 5], default = 100},
	# above 100% the fixed-height pages no longer fit the logical screen
	{key = "ui_scale", label = "UI SCALE", range = [50, 100, 5], default = 100},
	{key = "sensitivity", label = "MOUSE SENSITIVITY", range = [10, 300, 5], default = 100},
	{key = "volume", label = "MASTER VOLUME", range = [0, 100, 1], default = 100},
]
const CONTROL_WIDTH := 290.0

@onready var rows: GridContainer = $Card/V/Rows

var _config := ConfigFile.new()


func _ready() -> void:
	$Card/V/Buttons/SettingsBackButton.pressed.connect(closed.emit)
	_config.load(USER_CONFIG)
	for row in ROWS:
		var value = _config.get_value("settings", row.key, row.default)
		if row.has("options") and not row.options.has(value):
			value = row.default
		elif row.has("range"):
			value = clampi(int(value), row.range[0], row.range[1])
		_add_row(row, value)
		_apply(row.key, value)


func _add_row(row: Dictionary, value: Variant) -> void:
	var key_label := Label.new()
	key_label.theme_type_variation = &"MutedLabel"
	key_label.add_theme_font_size_override("font_size", 18)
	key_label.text = row.label
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rows.add_child(key_label)
	if row.has("options"):
		rows.add_child(_make_stepper(row, value))
	else:
		rows.add_child(_make_slider(row, value))


func _make_stepper(row: Dictionary, value: Variant) -> Stepper:
	var stepper := Stepper.new()
	stepper.value_width = CONTROL_WIDTH - 2.0 * (46.0 + 18.0)
	stepper.font_size = 24
	stepper.button_size = Vector2(46, 40)
	var labels: Array = row.options.map(func(v) -> String:
		return "UNLIMITED" if row.key == "max_fps" and v == 0 else str(v))
	stepper.setup(row.options, value, labels)
	stepper.changed.connect(_commit.bind(row.key))
	return stepper


func _make_slider(row: Dictionary, value: Variant) -> Control:
	var box := HBoxContainer.new()
	box.custom_minimum_size.x = CONTROL_WIDTH
	box.add_theme_constant_override("separation", 14)
	var slider := HSlider.new()
	slider.min_value = row.range[0]
	slider.max_value = row.range[1]
	slider.step = row.range[2]
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.theme_type_variation = &"TitleLabel"
	value_label.add_theme_font_size_override("font_size", 22)
	value_label.custom_minimum_size.x = 64
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%d%%" % value
	box.add_child(slider)
	box.add_child(value_label)
	# live while dragging, saved once on release. UI scale applies on release
	# only: rescaling mid-drag would move the slider out from under the mouse.
	var dragging := [false]
	slider.drag_started.connect(func() -> void: dragging[0] = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		dragging[0] = false
		_commit(int(slider.value), row.key))
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%d%%" % int(v)
		if not dragging[0]:
			_commit(int(v), row.key)
		elif row.key != "ui_scale":
			_apply(row.key, int(v)))
	return box


func _commit(value: Variant, key: String) -> void:
	_apply(key, value)
	_config.set_value("settings", key, value)
	_config.save(USER_CONFIG)


func _apply(key: String, value: Variant) -> void:
	var root := get_tree().root
	match key:
		"window":
			var fullscreen: bool = value == "FULLSCREEN"
			# only switch on change: re-setting windowed would un-maximize
			if fullscreen != (DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN):
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
						else DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value == "ON"
					else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = value
		"render_scale":
			# 3D only; FSR keeps a scaled-down image sharp, the UI stays native
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if value < 100 \
					else Viewport.SCALING_3D_MODE_BILINEAR
			root.scaling_3d_scale = value / 100.0
		"ui_scale":
			# canvas_items stretch grows the UI with the window; this shrinks it back
			root.content_scale_factor = value / 100.0
		"post_fx":
			var env: Environment = root.find_world_3d().environment
			if env != null:
				env.ssao_enabled = value == "ON"
				env.glow_enabled = value == "ON"
		"sensitivity":
			CameraObject.mouse_sensitivity = value / 100.0
		"volume":
			AudioServer.set_bus_volume_db(0, linear_to_db(value / 100.0))
			AudioServer.set_bus_mute(0, value == 0)
