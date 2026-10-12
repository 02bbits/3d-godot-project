class_name HudStyle
extends RefCounted

## Shared look of the in-game HUD (docs/Modifier Arena — HUD.pdf): palette,
## fonts and drawing helpers. Widget metrics are written in mockup pixels
## (1456x819 frame) and multiplied by K, which keeps the mockup's proportions
## on the 1152x648 base canvas.

const K := 0.79

const YELLOW := Color("#FFC933")
const RED := Color("#FF6A5C")
const BLUE := Color("#4DA2FE")
const CREAM := Color("#F4EEE2")
const MUTED := Color("#9AA3B1")
const GHOST := Color("#FFD2CB")
const PANEL := Color("#1B1F27")
const SLOT := Color("#13161C")
const EMPTY := Color("#2C313C")
const INK := Color("#0E1015")
const SHADOW := Color(0.02, 0.025, 0.035, 0.85)
const HIGHLIGHT := Color(1.0, 0.79, 0.2, 0.2)

const LILITA := preload("res://assets/fonts/lilita_one_regular.ttf")
const RUBIK := preload("res://assets/fonts/Rubik-VariableFont_wght.ttf")

static var _rubik := {}


## Rubik at a given weight (the font is variable), cached per weight
static func rubik(weight := 500) -> Font:
	if not _rubik.has(weight):
		var font := FontVariation.new()
		font.base_font = RUBIK
		font.variation_opentype = {
			TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_rubik[weight] = font
	return _rubik[weight]


## rounded rect, optionally bordered
static func box(canvas: CanvasItem, rect: Rect2, fill: Color, radius: float,
		border := 0.0, border_color := INK) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(radius))
	if border > 0.0:
		style.set_border_width_all(int(round(border)))
		style.border_color = border_color
	style.anti_aliasing = true
	canvas.draw_style_box(style, rect)


## the dark HUD card: ink border and a hard drop shadow, like the menu cards
static func card(canvas: CanvasItem, rect: Rect2, radius := 10.0 * K,
		shadow := 6.0 * K) -> void:
	box(canvas, Rect2(rect.position + Vector2(shadow, shadow), rect.size), SHADOW, radius)
	box(canvas, rect, PANEL, radius, 3.0 * K)


## text whose vertical center sits on `center_y`
static func text(canvas: CanvasItem, font: Font, size: int, x: float, center_y: float,
		value: String, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var baseline := center_y + (font.get_ascent(size) - font.get_descent(size)) * 0.5
	canvas.draw_string(font, Vector2(x, baseline), value, align, width, size, color)


static func text_width(font: Font, size: int, value: String) -> float:
	return font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## round-kill dot: filled yellow or an empty socket
static func dot(canvas: CanvasItem, center: Vector2, radius: float, filled: bool) -> void:
	canvas.draw_circle(center, radius + 1.5 * K, INK)
	canvas.draw_circle(center, radius, YELLOW if filled else EMPTY)


## match-win diamond: filled blue or an empty socket
static func diamond(canvas: CanvasItem, center: Vector2, half: float, filled: bool) -> void:
	var outer := half + 1.5 * K
	canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -outer),
			center + Vector2(outer, 0), center + Vector2(0, outer), center + Vector2(-outer, 0)]), INK)
	canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -half),
			center + Vector2(half, 0), center + Vector2(0, half), center + Vector2(-half, 0)]),
			BLUE if filled else EMPTY)
