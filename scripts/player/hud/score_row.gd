extends PanelContainer

## One scoreboard line (score_row.tscn on the card, score_row_full.tscn on the
## TAB board): robot, name, round-kill dots, match-win diamonds and, on the
## full board, ping. The local player's row is highlighted.

@onready var highlight: Control = %Highlight
@onready var icon: Control = %Icon
@onready var name_label: Label = %Name
@onready var kills: HBoxContainer = %Kills
@onready var wins: HBoxContainer = %Wins
@onready var ping: Label = get_node_or_null("%Ping")


func set_row(row: Dictionary, info: Dictionary) -> void:
	highlight.visible = row.local
	icon.icon_color = row.color
	# the full board names the local player; on the card the highlight does
	name_label.text = row.name + (" (you)" if row.local and ping != null else "")
	_set_marks(kills, info.kills_needed, row.kills, "HudDot")
	_set_marks(wins, info.wins_needed, row.wins, "HudDiamond")
	if ping != null:
		ping.text = "%d ms" % row.ping if row.ping > 0 else "—"


# filled marks use the "...On" variation of their theme style. Each mark is a
# holder with the shape inside: containers reset rotation, and diamonds need it.
static func _set_marks(box: HBoxContainer, count: int, filled: int, style: String) -> void:
	NodeUtil.fit_children(box, count)
	for i in count:
		box.get_child(i).get_child(0).theme_type_variation = \
				StringName(style + ("On" if i < filled else ""))
