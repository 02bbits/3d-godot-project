@tool
extends AspectRatioContainer

## Design mascot (scenes/ui/robot_icon.tscn): a rounded square with two eyes.
## Reused across the menu (title row, name screen, player chips, color picker,
## card art) and the HUD scoreboard. Eyes, ring and badge are anchored, so the
## shape scales with the size; only the corner radius is updated here. Set
## `icon_color` per instance; `animate` adds an idle bob and blink.

@export var icon_color := Color("#FFC933") : set = _set_icon_color
## idle bob + blink (main menu, color preview, card art)
@export var animate := false
## ring around the icon (selected color swatch)
@export var selected := false : set = _set_selected
## small palette badge in the corner: "click me to recolor"
@export var badge := false : set = _set_badge
## dark border in pixels (HUD and card art robots)
@export var outline := 0 : set = _set_outline

const CORNER_RATIO := 0.16
const RING_CORNER_RATIO := 0.24
const BOB_PIXELS := 3.0

@onready var _bob: Control = $Square/Bob
@onready var _body: Panel = $Square/Bob/Body
@onready var _eyes: Control = $Square/Bob/Body/Eyes
@onready var _ring: Panel = $Square/Bob/Ring
@onready var _badge: Control = $Square/Bob/Badge

var _body_style: StyleBoxFlat
var _ring_style: StyleBoxFlat
# random phase so a row of icons doesn't move in lockstep
var _phase := randf() * TAU
var _next_blink := randf_range(1.5, 4.0)
var _blink := 0.0


func _ready() -> void:
	# own copies of the styles: the corner radius follows this instance's size
	_body_style = _body.get_theme_stylebox("panel").duplicate()
	_body.add_theme_stylebox_override("panel", _body_style)
	_ring_style = _ring.get_theme_stylebox("panel").duplicate()
	_ring.add_theme_stylebox_override("panel", _ring_style)
	_body.resized.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if not animate or Engine.is_editor_hint() or not is_visible_in_tree():
		return
	_phase += delta * 2.4
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.14
		_next_blink = randf_range(2.0, 5.0)
	_blink = maxf(_blink - delta, 0.0)
	_bob.position.y = sin(_phase) * BOB_PIXELS
	_eyes.scale.y = 0.3 if _blink > 0.0 else 1.0


func _set_icon_color(value: Color) -> void:
	icon_color = value
	_refresh()


func _set_selected(value: bool) -> void:
	selected = value
	_refresh()


func _set_badge(value: bool) -> void:
	badge = value
	_refresh()


func _set_outline(value: int) -> void:
	outline = value
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	var side := _body.size.x
	_body_style.bg_color = icon_color
	_body_style.set_corner_radius_all(roundi(side * CORNER_RATIO))
	_body_style.set_border_width_all(outline)
	_ring_style.set_corner_radius_all(roundi(side * RING_CORNER_RATIO))
	_ring_style.set_border_width_all(maxi(roundi(side * 0.05), 2))
	_ring.visible = selected
	_badge.visible = badge
