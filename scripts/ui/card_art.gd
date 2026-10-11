extends Control

## Decoration for the play-choice cards: a little blueprint sheet with the
## menu mascot. "create" shows one robot being drafted with a "+" badge,
## "join" a row of robots hopping toward a door. Drawn in code so it follows
## the card's size and the theme palette.

@export_enum("create", "join") var kind := "create"

const ROBOT_ICON := preload("res://scripts/ui/robot_icon.gd")
const INK := Color("#1B2029")
const CREAM := Color("#F4EEE2")
const ROBOTS := [Color("#FFC933"), Color("#FF6A5C"), Color("#7ADF7C")]

var _t := randf() * 10.0
var _blink := 0.0
var _next_blink := 2.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.14
		_next_blink = randf_range(2.0, 4.5)
	_blink = maxf(_blink - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var sheet := Rect2(Vector2.ZERO, size).grow(-6.0)
	if sheet.size.x < 40.0 or sheet.size.y < 40.0:
		return
	_draw_sheet(sheet)
	if kind == "create":
		_draw_create(sheet)
	else:
		_draw_join(sheet)


# faint grid inside a dashed frame, like a drafting sheet
func _draw_sheet(sheet: Rect2) -> void:
	draw_rect(sheet, Color(INK, 0.06))
	var step := 22.0
	var x := sheet.position.x + step
	while x < sheet.end.x:
		draw_line(Vector2(x, sheet.position.y), Vector2(x, sheet.end.y), Color(INK, 0.07), 1.0)
		x += step
	var y := sheet.position.y + step
	while y < sheet.end.y:
		draw_line(Vector2(sheet.position.x, y), Vector2(sheet.end.x, y), Color(INK, 0.07), 1.0)
		y += step
	var corners := [sheet.position, Vector2(sheet.end.x, sheet.position.y), sheet.end,
			Vector2(sheet.position.x, sheet.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], Color(INK, 0.35), 2.0, 10.0)


func _draw_create(sheet: Rect2) -> void:
	var side := minf(sheet.size.y * 0.55, 150.0)
	var center := sheet.get_center() + Vector2(0.0, sin(_t * 2.0) * 6.0)
	var box := Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side))
	# drop shadow that shrinks as the robot floats up
	var lift := 0.5 + 0.5 * sin(_t * 2.0)
	var floor_y := sheet.get_center().y + side * 0.5 + 18.0
	draw_set_transform(Vector2(center.x, floor_y), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, side * (0.42 - lift * 0.06), Color(INK, 0.18))
	draw_set_transform(Vector2.ZERO)
	ROBOT_ICON.draw_robot(self, box, CREAM, 4.0, _blink > 0.0)
	# dimension line under the robot, blueprint style
	var dim_y := floor_y + 14.0
	var left := Vector2(box.position.x, dim_y)
	var right := Vector2(box.end.x, dim_y)
	draw_line(left, right, Color(INK, 0.4), 2.0)
	for end in [left, right]:
		draw_line(end - Vector2(0.0, 6.0), end + Vector2(0.0, 6.0), Color(INK, 0.4), 2.0)
	# pulsing "+" badge
	var pulse := 1.0 + 0.08 * sin(_t * 4.0)
	var badge := box.position + Vector2(box.size.x, 0.0) + Vector2(-side * 0.05, side * 0.05)
	var r := side * 0.2 * pulse
	draw_circle(badge, r + 3.0, INK)
	draw_circle(badge, r, Color("#FF6A5C"))
	draw_line(badge - Vector2(r * 0.5, 0.0), badge + Vector2(r * 0.5, 0.0), CREAM, r * 0.28)
	draw_line(badge - Vector2(0.0, r * 0.5), badge + Vector2(0.0, r * 0.5), CREAM, r * 0.28)
	_draw_sparkle(box.position + Vector2(-side * 0.25, side * 0.15), side * 0.09, 0.0)
	_draw_sparkle(box.end + Vector2(side * 0.22, -side * 0.3), side * 0.07, 1.7)


func _draw_join(sheet: Rect2) -> void:
	var side := minf(sheet.size.y * 0.32, 84.0)
	var gap := side * 0.35
	var door := Vector2(side * 0.95, side * 1.35)
	var total := ROBOTS.size() * side + (ROBOTS.size() - 1) * gap + side * 0.9 + door.x
	var origin := Vector2(sheet.get_center().x - total * 0.5, sheet.get_center().y + side * 0.55)
	# robots hop in a wave toward the door
	for i in ROBOTS.size():
		var hop := absf(sin(_t * 3.2 - i * 0.7)) * side * 0.28
		var pos := origin + Vector2(i * (side + gap), -side - hop)
		draw_set_transform(Vector2(pos.x + side * 0.5, origin.y + 4.0), 0.0, Vector2(1.0, 0.25))
		draw_circle(Vector2.ZERO, side * (0.45 - hop / side * 0.3), Color(INK, 0.18))
		draw_set_transform(Vector2.ZERO)
		ROBOT_ICON.draw_robot(self, Rect2(pos, Vector2(side, side)), ROBOTS[i], 3.0,
				_blink > 0.0 and i == 1)
	# arrow + open door
	var arrow_y := origin.y - side * 0.5
	var arrow_x := origin.x + ROBOTS.size() * (side + gap) - gap * 0.4
	var nudge := sin(_t * 3.2) * 4.0
	var tip := Vector2(arrow_x + side * 0.55 + nudge, arrow_y)
	draw_line(Vector2(arrow_x + nudge, arrow_y), tip, INK, 4.0)
	draw_line(tip, tip + Vector2(-10.0, -9.0), INK, 4.0)
	draw_line(tip, tip + Vector2(-10.0, 9.0), INK, 4.0)
	var door_rect := Rect2(Vector2(origin.x + total - door.x, origin.y - door.y), door)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(INK, 0.75)
	frame.set_border_width_all(4)
	frame.border_color = CREAM
	frame.corner_radius_top_left = int(door.x * 0.5)
	frame.corner_radius_top_right = int(door.x * 0.5)
	draw_style_box(frame, door_rect)
	# light spilling out of the doorway, same arch shape inset
	var light := StyleBoxFlat.new()
	light.bg_color = Color(Color("#FFC933"), 0.35 + 0.25 * sin(_t * 2.5))
	var inner := door_rect.grow(-9.0)
	light.corner_radius_top_left = int(inner.size.x * 0.5)
	light.corner_radius_top_right = int(inner.size.x * 0.5)
	draw_style_box(light, inner)


func _draw_sparkle(center: Vector2, radius: float, phase: float) -> void:
	var s := radius * (0.6 + 0.4 * sin(_t * 3.0 + phase))
	var points := PackedVector2Array()
	for i in 8:
		var r := s if i % 2 == 0 else s * 0.3
		points.append(center + Vector2.from_angle(i * PI / 4.0) * r)
	draw_colored_polygon(points, CREAM)
