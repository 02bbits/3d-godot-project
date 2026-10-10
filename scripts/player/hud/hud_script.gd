extends CanvasLayer

class_name HUD

#player character reference variable
@export var play_char : PlayerCharacter

#label references variables
@onready var speed_lines_container: ColorRect = %SpeedLinesContainer
@onready var health_bar: ProgressBar = $Healthbar
@onready var stamina_bar: ProgressBar = $Staminabar
@onready var round_label: Label = %RoundLabel
@onready var score_grid: GridContainer = %ScoreGrid
@onready var results_panel: Control = %ResultsPanel
@onready var results_list: VBoxContainer = %ResultsList
@onready var match_banner: Label = %MatchBanner
@onready var scoreboard: PanelContainer = $Scoreboard
@onready var crosshair: CenterContainer = $Reticle

var _match_manager: Node
var _last_state := ""
var _last_result_serial := -1

func _ready() -> void:
	if play_char == null:
		assert(false, "Player character reference for the hud is mandatory")

func _process(_delta : float) -> void:
	# keep the bar range in sync when modifiers change max health
	if health_bar.max_value != play_char.max_health:
		health_bar.max_value = play_char.max_health
	if stamina_bar.max_value != play_char.stamina_max:
		stamina_bar.max_value = play_char.stamina_max
	_update_match_ui()

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
	_rebuild_scoreboard()


func _rebuild_scoreboard() -> void:
	for child in score_grid.get_children():
		child.free()
	round_label.text = "Round %d / %d" % [_match_manager.round, _match_manager.rounds_total]
	score_grid.add_child(_make_cell("Player"))
	score_grid.add_child(_make_cell("Rounds"))
	score_grid.add_child(_make_cell("Match"))
	for row in _player_rows():
		score_grid.add_child(_make_cell(str(row[0])))
		score_grid.add_child(_make_cell(str(row[1])))
		score_grid.add_child(_make_cell(str(row[2])))
	_update_results()


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
		rows.append([
			display_name,
			int(_match_manager.rounds_won.get(str(id), 0)),
			int(_match_manager.round_scores.get(str(id), 0)),
		])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] > b[1]
		if a[2] != b[2]:
			return a[2] > b[2]
		return a[0] < b[0])
	return rows


func _update_results() -> void:
	var over: bool = _match_manager.match_phase == "game_over"
	results_panel.visible = over
	_refresh_hud_visibility()
	if not over:
		return
	for child in results_list.get_children():
		child.free()
	var rank := 1
	for row in _player_rows().slice(0, 3):
		var label := Label.new()
		label.text = "%d.  %s — %d rounds" % [rank, row[0], row[1]]
		label.add_theme_font_override("font", round_label.get_theme_font("font"))
		label.add_theme_font_size_override("font_size", 32)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		results_list.add_child(label)
		rank += 1


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


# the persistent gameplay HUD steps aside while an important popup is up
func _refresh_hud_visibility() -> void:
	var popup := match_banner.visible or results_panel.visible
	health_bar.visible = not popup
	stamina_bar.visible = not popup
	scoreboard.visible = not popup
	crosshair.visible = not popup


func _make_cell(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", round_label.get_theme_font("font"))
	label.add_theme_font_size_override("font_size", 24)
	return label
