extends Control

## Scoreboard, in the two layouts of the HUD mockup: the compact card in the
## top-right corner (scoreboard_card.tscn: top 3, the local player always
## listed) and the full board shown while TAB is held (scoreboard_full.tscn).
## Rows are pushed by the HUD (set_rows); yellow dots are this round's kills,
## blue diamonds the match (round) wins.

const COMPACT_ROWS := 3

@export var full := false

@onready var round_label: Label = %Round
@onready var total_label: Label = %Total
@onready var goal_label: Label = %Goal
@onready var rows_box: VBoxContainer = %Rows
@onready var footer: Label = get_node_or_null("%Footer") # card only: "+N more"
@onready var wins_header: Label = get_node_or_null("%WinsHeader") # board only


## each row: {name, color, kills, wins, ping, local}, sorted by the HUD
func set_rows(rows: Array, info: Dictionary) -> void:
	var shown := rows
	if not full:
		shown = rows.slice(0, COMPACT_ROWS)
		# the local player is always on the card, even when ranked lower
		for row in rows.slice(COMPACT_ROWS):
			if row.local:
				shown[COMPACT_ROWS - 1] = row
	round_label.text = "ROUND %d" % info.round
	total_label.text = ("OF %d" if full else "/ %d") % info.rounds_total
	goal_label.text = ("First to %d kills" if full else "FIRST TO %d KILLS") % info.kills_needed
	if wins_header != null:
		wins_header.text = "MATCH WINS (%d)" % info.wins_needed
	NodeUtil.fit_children(rows_box, shown.size())
	for i in shown.size():
		rows_box.get_child(i).set_row(shown[i], info)
	if footer != null:
		var more := rows.size() - shown.size()
		footer.visible = more > 0
		footer.text = "+%d more · hold TAB" % more
