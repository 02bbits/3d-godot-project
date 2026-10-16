extends CenterContainer

## Settings page. The rows are laid out in the scene (connection_menu.tscn,
## Pages/Settings/Card/V/Rows): discrete choices use the menu's stepper,
## continuous ones a slider whose range lives on its HSlider node. Choices are
## saved to the shared user config and applied on load, so they survive
## restarts and the scene reload after leaving a game.

signal closed

const USER_CONFIG := "user://user_config.cfg"
# each key's control is the Rows child named key.to_pascal_case(); stepper
# rows list their values here, slider rows only a default
const ROWS := [
	{key = "window", options = ["WINDOWED", "FULLSCREEN"], default = "WINDOWED"},
	{key = "vsync", options = ["ON", "OFF"], default = "ON"},
	{key = "max_fps", options = [30, 60, 120, 144, 240, 0], default = 0,
			labels = ["30", "60", "120", "144", "240", "UNLIMITED"]},
	{key = "post_fx", options = ["ON", "OFF"], default = "ON"},
	{key = "render_scale", default = 100},
	# AUTO shrinks the UI until the shown page fits the window (fit_ui);
	# MANUAL uses the slider. Above 100% the fixed-height pages never fit.
	{key = "ui_scale_mode", options = ["AUTO", "MANUAL"], default = "AUTO"},
	{key = "ui_scale", default = 100},
	{key = "sensitivity", default = 100},
	{key = "volume", default = 100},
]

@onready var rows: GridContainer = $Card/V/Rows
@onready var ui_scale_slider: HSlider = $Card/V/Rows/UiScale/Slider

var _config := ConfigFile.new()
var _ui_auto := true
var _fit_page: Control # the menu page AUTO fits; null while playing


## AUTO UI scaling: the menu calls this on every page switch (null when the
## menu hides) so the shown page always fits inside the window.
func fit_ui(page: Control) -> void:
	_fit_page = page
	await get_tree().process_frame # let the page lay out first
	_apply_ui_scale()


func _ready() -> void:
	$Card/V/Buttons/SettingsBackButton.pressed.connect(closed.emit)
	get_tree().root.size_changed.connect(_apply_ui_scale)
	_config.load(USER_CONFIG)
	for row in ROWS:
		var control := rows.get_node(String(row.key).to_pascal_case())
		var value = _config.get_value("settings", row.key, row.default)
		if row.has("options"):
			if not row.options.has(value):
				value = row.default
			control.setup(row.options, value, row.get("labels", []))
			control.changed.connect(_commit.bind(row.key))
		else:
			value = _setup_slider(control, row.key, int(value))
		_apply(row.key, value)


# returns the stored value clamped to the slider node's range
func _setup_slider(box: Control, key: String, value: int) -> int:
	var slider: HSlider = box.get_node("Slider")
	var value_label: Label = box.get_node("Value")
	slider.value = value
	value_label.text = "%d%%" % int(slider.value)
	# live while dragging, saved once on release. UI scale applies on release
	# only: rescaling mid-drag would move the slider out from under the mouse.
	var dragging := [false]
	slider.drag_started.connect(func() -> void: dragging[0] = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		dragging[0] = false
		_commit(int(slider.value), key))
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%d%%" % int(v)
		if not dragging[0]:
			_commit(int(v), key)
		elif key != "ui_scale":
			_apply(key, int(v)))
	return int(slider.value)


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
		"ui_scale_mode":
			_ui_auto = value == "AUTO"
			_apply_ui_scale()
		"ui_scale":
			_apply_ui_scale()
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


# canvas_items stretch grows the UI with the window; this shrinks it back,
# by the slider (MANUAL) or until the shown page fits (AUTO, at most 100%)
func _apply_ui_scale() -> void:
	var root := get_tree().root
	ui_scale_slider.editable = not _ui_auto
	var factor := ui_scale_slider.value / 100.0
	if _ui_auto:
		factor = 1.0
		if _fit_page != null and _fit_page.is_visible_in_tree():
			var need := _fit_page.get_combined_minimum_size()
			# the logical screen at 100%
			var screen := root.get_visible_rect().size * root.content_scale_factor
			if need.x > 0.0 and need.y > 0.0:
				factor = minf(factor, minf(screen.x / need.x, screen.y / need.y))
		factor = maxf(factor, ui_scale_slider.min_value / 100.0)
	ui_scale_slider.get_parent().get_node("Value").text = "%d%%" % roundi(factor * 100.0)
	root.content_scale_factor = factor
