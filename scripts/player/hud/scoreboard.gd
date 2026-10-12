extends Control

## Scoreboard, in the two layouts of the HUD mockup: the compact card in the
## top-right corner (top 3, the local player always listed) and the full board
## shown while TAB is held. Rows are pushed by the HUD (set_rows); yellow dots
## are this round's kills, blue diamonds the match (round) wins.

const S := preload("res://scripts/player/hud/hud_style.gd")
const K := S.K
const ROBOT_ICON := preload("res://scripts/ui/robot_icon.gd")
const COMPACT_ROWS := 3

@export var full := false

# each row: {name, color, kills, wins, ping, local}; sorted by the HUD
var rows: Array = []
var info := {"round": 1, "rounds_total": 1, "kills_needed": 2, "wins_needed": 1}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_rows(new_rows: Array, new_info: Dictionary) -> void:
	rows = new_rows
	info = new_info
	queue_redraw()


func _draw() -> void:
	if full:
		_draw_full()
	else:
		_draw_compact()


func _draw_compact() -> void:
	var shown := rows.slice(0, COMPACT_ROWS)
	# the local player is always on the card, even when ranked lower
	for row in rows.slice(COMPACT_ROWS):
		if row.local:
			shown[COMPACT_ROWS - 1] = row
	var more := rows.size() - shown.size()
	var width := 292.0
	var last_row := 64.0 + (shown.size() - 1) * 34.5
	var height := (last_row + 30.0 if more > 0 else last_row) + 20.0
	var origin := Vector2(size.x / K - width, 0.0) # right-aligned in this control
	S.card(self, Rect2(origin * K, Vector2(width, height) * K), 12.0 * K)
	var o := origin * K

	var title := "ROUND %d" % info.round
	var title_size := int(22 * K)
	S.text(self, S.LILITA, title_size, o.x + 21 * K, o.y + 27 * K, title, S.YELLOW)
	S.text(self, S.LILITA, int(16 * K), o.x + 21 * K + S.text_width(S.LILITA, title_size, title)
			+ 5 * K, o.y + 28 * K, "/ %d" % info.rounds_total, S.MUTED)
	S.text(self, S.rubik(500), int(13 * K), o.x, o.y + 27 * K,
			"FIRST TO %d KILLS" % info.kills_needed, S.MUTED, HORIZONTAL_ALIGNMENT_RIGHT,
			272 * K)
	for i in shown.size():
		var y := o.y + (64.0 + i * 34.5) * K
		var row: Dictionary = shown[i]
		if row.local:
			S.box(self, Rect2(Vector2(o.x + 10 * K, y - 17 * K), Vector2(273, 34) * K),
					S.HIGHLIGHT, 8.0 * K)
		ROBOT_ICON.draw_robot(self, Rect2(Vector2(o.x + 22 * K, y - 11 * K), Vector2(22, 22) * K),
				row.color, 2.0 * K)
		S.text(self, S.rubik(600), int(17 * K), o.x + 55 * K, y, row.name, S.CREAM,
				HORIZONTAL_ALIGNMENT_LEFT, 120 * K)
		var diamonds_left := _draw_marks(o.x + 266 * K, y, 18.5 * K, info.wins_needed,
				row.wins, false, 6.5 * K)
		_draw_marks(diamonds_left - 25 * K, y, 18.0 * K, info.kills_needed, row.kills, true,
				5.5 * K)
	if more > 0:
		S.text(self, S.rubik(500), int(13 * K), o.x, o.y + (last_row + 30.0) * K,
				"+%d more · hold TAB" % more, S.MUTED, HORIZONTAL_ALIGNMENT_CENTER, width * K)


func _draw_full() -> void:
	var width := 730.0
	var last_row := 132.0 + (rows.size() - 1) * 47.0
	var height := last_row + 78.0
	var origin := (size / K - Vector2(width, height)) * 0.5
	S.card(self, Rect2(origin * K, Vector2(width, height) * K), 14.0 * K, 8.0 * K)
	var o := origin * K

	var title := "ROUND %d" % info.round
	var title_size := int(40 * K)
	S.text(self, S.LILITA, title_size, o.x + 38 * K, o.y + 50 * K, title, S.YELLOW)
	S.text(self, S.LILITA, int(24 * K), o.x + 38 * K + S.text_width(S.LILITA, title_size, title)
			+ 8 * K, o.y + 55 * K, "OF %d" % info.rounds_total, S.MUTED)
	var pill := Rect2(o + Vector2(544, 35) * K, Vector2(149, 30) * K)
	S.box(self, pill, S.YELLOW, 15.0 * K, 2.5 * K)
	S.text(self, S.rubik(700), int(16 * K), pill.position.x, pill.get_center().y,
			"First to %d kills" % info.kills_needed, S.INK, HORIZONTAL_ALIGNMENT_CENTER,
			pill.size.x)

	var header := S.rubik(500)
	var header_size := int(14 * K)
	var hy := o.y + 94 * K
	S.text(self, header, header_size, o.x + 38 * K, hy, "PLAYER", S.MUTED)
	S.text(self, header, header_size, o.x + 351 * K, hy, "ROUND KILLS", S.MUTED,
			HORIZONTAL_ALIGNMENT_CENTER, 120 * K)
	S.text(self, header, header_size, o.x + 487 * K, hy, "MATCH WINS (%d)" % info.wins_needed,
			S.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 140 * K)
	S.text(self, header, header_size, o.x, hy, "PING", S.MUTED, HORIZONTAL_ALIGNMENT_RIGHT,
			693 * K)
	for i in rows.size():
		var y := o.y + (132.0 + i * 47.0) * K
		var row: Dictionary = rows[i]
		if row.local:
			S.box(self, Rect2(Vector2(o.x + 20 * K, y - 23.5 * K), Vector2(692, 47) * K),
					S.HIGHLIGHT, 10.0 * K)
		ROBOT_ICON.draw_robot(self, Rect2(Vector2(o.x + 40 * K, y - 15 * K), Vector2(30, 30) * K),
				row.color, 2.5 * K)
		S.text(self, S.rubik(700), int(22 * K), o.x + 81 * K, y,
				row.name + (" (you)" if row.local else ""), S.CREAM, HORIZONTAL_ALIGNMENT_LEFT,
				260 * K)
		_draw_marks_centered(o.x + 411 * K, y, 24.0 * K, info.kills_needed, row.kills, true,
				7.0 * K)
		_draw_marks_centered(o.x + 547 * K, y, 25.5 * K, info.wins_needed, row.wins, false,
				8.0 * K)
		var ping: String = "%d ms" % row.ping if row.ping > 0 else "—"
		S.text(self, S.rubik(400), int(17 * K), o.x, y, ping, S.MUTED,
				HORIZONTAL_ALIGNMENT_RIGHT, 693 * K)
	S.text(self, S.rubik(400), int(15 * K), o.x, o.y + (last_row + 44.0) * K,
			"Shown while TAB is held · sorted by wins, then kills", S.MUTED,
			HORIZONTAL_ALIGNMENT_CENTER, width * K)


# a row of dots/diamonds ending at `right_x`; returns the left-most center
func _draw_marks(right_x: float, y: float, step: float, count: int, filled: int,
		dots: bool, radius: float) -> float:
	var left := right_x - (count - 1) * step
	for i in count:
		var center := Vector2(left + i * step, y)
		if dots:
			S.dot(self, center, radius, i < filled)
		else:
			S.diamond(self, center, radius, i < filled)
	return left


func _draw_marks_centered(center_x: float, y: float, step: float, count: int, filled: int,
		dots: bool, radius: float) -> void:
	_draw_marks(center_x + (count - 1) * step * 0.5, y, step, count, filled, dots, radius)
