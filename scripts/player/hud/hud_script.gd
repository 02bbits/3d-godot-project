extends CanvasLayer

class_name HUD

#player character reference variable
@export var play_char : PlayerCharacter

#label references variables
@onready var speed_lines_container: ColorRect = %SpeedLinesContainer
@onready var vitals: Control = $Vitals
@onready var ammo_panel: Control = $AmmoPanel
@onready var score_card: Control = $ScoreCard
@onready var tab_board: Control = $TabBoard
@onready var results_panel: Control = %ResultsPanel
@onready var results_list: VBoxContainer = %ResultsList
@onready var match_banner: Label = %MatchBanner
@onready var crosshair: Control = $Reticle

const ROWS_REFRESH := 0.25
# scoreboard robot for players who haven't published a color yet
const FALLBACK_COLOR := Color("#9AA3B1")

var _match_manager: Node
var _last_state := ""
var _last_result_serial := -1
var _rows_timer := 0.0

func _ready() -> void:
	if play_char == null:
		assert(false, "Player character reference for the hud is mandatory")

func _process(delta : float) -> void:
	_update_match_ui()
	# names, colors and pings change outside the match state: refresh the
	# scoreboards on a short timer
	_rows_timer -= delta
	if _rows_timer <= 0.0 and _match_manager != null:
		_rows_timer = ROWS_REFRESH
		_push_scoreboard()
	tab_board.visible = visible and Input.is_physical_key_pressed(KEY_TAB) \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _popup_up()

func display_speed_lines(value : bool) -> void:
	speed_lines_container.visible = value

func round_to_3_decimals(value: float) -> float:
	return round(value * 1000.0) / 1000.0


# MATCH UI

func _update_match_ui() -> void:
	if not visible:
		return
	if _match_manager == null:
		_match_manager = get_tree().get_first_node_in_group("match_manager")
		if _match_manager == null:
			return
	var state := "%s|%d|%d|%s|%s|%d" % [
		_match_manager.match_phase, _match_manager.round, _match_manager.rounds_total,
		str(_match_manager.rounds_won), str(_match_manager.round_scores),
		_match_manager.result_serial,
	]
	if state == _last_state:
		return
	_last_state = state
	if int(_match_manager.result_serial) != _last_result_serial:
		_last_result_serial = int(_match_manager.result_serial)
		_show_match_banner(str(_match_manager.last_result))
	_push_scoreboard()
	_update_results()


func _push_scoreboard() -> void:
	var total: int = maxi(int(_match_manager.rounds_total), 1)
	var info := {
		"round": maxi(int(_match_manager.round), 1),
		"rounds_total": total,
		"kills_needed": int(_match_manager.match_wins_per_round),
		# a majority of the rounds clinches the match
		"wins_needed": floori(total / 2.0) + 1,
	}
	var rows := _player_rows()
	score_card.set_rows(rows, info)
	tab_board.set_rows(rows, info)


# sorted by match (round) wins, then this round's kills, then name
func _player_rows() -> Array:
	var rows: Array = []
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		var id := -1
		var rep: Node = p.find_child("FusionSharedReplicator", true, false)
		if rep != null and rep.has_method("get_owner_id"):
			id = int(rep.get_owner_id())
		var display_name := str(p.net_nickname)
		if display_name.is_empty():
			display_name = "Player %d" % id
		rows.append({
			"name": display_name,
			"color": Color.html(p.net_color) if Color.html_is_valid(p.net_color) \
					else FALLBACK_COLOR,
			"wins": int(_match_manager.rounds_won.get(str(id), 0)),
			"kills": int(_match_manager.round_scores.get(str(id), 0)),
			"ping": int(p.net_ping),
			"local": p == play_char,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.wins != b.wins:
			return a.wins > b.wins
		if a.kills != b.kills:
			return a.kills > b.kills
		return a.name < b.name)
	return rows


func _update_results() -> void:
	var over: bool = _match_manager.match_phase == "game_over"
	results_panel.visible = over
	_refresh_hud_visibility()
	if not over:
		return
	# the podium: one label per place, authored in the scene
	var top := _player_rows().slice(0, results_list.get_child_count())
	for i in results_list.get_child_count():
		var label := results_list.get_child(i) as Label
		label.visible = i < top.size()
		if label.visible:
			label.text = "%d.  %s — %d rounds" % [i + 1, top[i].name, top[i].wins]


func _show_match_banner(text: String) -> void:
	if text.is_empty():
		return
	match_banner.text = text
	match_banner.modulate.a = 1.0
	match_banner.visible = true
	_refresh_hud_visibility()
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(match_banner, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_hide_match_banner)


func _hide_match_banner() -> void:
	match_banner.visible = false
	_refresh_hud_visibility()


func _popup_up() -> bool:
	return match_banner.visible or results_panel.visible


# the persistent gameplay HUD steps aside while an important popup is up
func _refresh_hud_visibility() -> void:
	var popup := _popup_up()
	for widget in [vitals, ammo_panel, score_card, crosshair]:
		widget.visible = not popup
