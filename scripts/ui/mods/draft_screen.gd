extends CanvasLayer

## Modifier draft (scenes/ui/mods/draft_screen.tscn), one per world. The
## match manager's "draft" phase opens it on every peer; each player rolls
## their own offers, picks one (click or keys 1-3) and publishes it through
## their replicated build. Whoever hasn't picked when the timer runs out gets
## a random offer. Debug builds: F2 opens a local draft any time (balancing).

const STATUS_REFRESH := 0.25

@export var world: Node

@onready var round_label: Label = %RoundLabel
@onready var cards: HBoxContainer = %Cards
@onready var hint: Label = %Hint
@onready var players_box: Container = %Players
@onready var timer_label: Label = %Timer

var _player: Node
var _offers: Array[Modifier] = []
var _draft_round := -1 # -1 closed, 0 debug draft, else the round being drafted for
var _time_left := 0.0
var _picked := false
var _status_timer := 0.0


func _ready() -> void:
	visible = false
	var match_manager := get_tree().get_first_node_in_group("match_manager")
	match_manager.draft_opened.connect(open)
	match_manager.draft_closed.connect(close)
	match_manager.returned_to_lobby.connect(close)


func open(draft_round: int) -> void:
	_draft_round = draft_round
	# at game start the phase can arrive before the local player has spawned
	if world.local_player == null:
		await world.local_player_changed
		if _draft_round != draft_round:
			return
	_player = world.local_player
	_offers = _player.mods.roll_offers()
	_picked = draft_round > 0 and _player.net_draft_round >= draft_round
	if draft_round == 0:
		round_label.text = "Debug draft"
	elif draft_round == 1:
		round_label.text = "Get ready"
	else:
		round_label.text = "Round %d complete" % (draft_round - 1)
	NodeUtil.fit_children(cards, _offers.size())
	for i in _offers.size():
		var card := cards.get_child(i)
		card.set_offer(_offers[i], _player.mods.level_of(_offers[i].id))
		if not card.chosen.is_connected(_pick):
			card.chosen.connect(_pick)
	hint.text = "Click a card or press 1–%d" % _offers.size()
	_time_left = ModRules.DRAFT_SECONDS
	_status_timer = 0.0
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _offers.is_empty():
		_pick(null) # nothing left to offer: count as picked


func close() -> void:
	_draft_round = -1
	if not visible:
		return
	visible = false
	if not world.connection_menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not visible:
		return
	# closing the ESC menu captures the mouse; the draft still needs it
	if not world.connection_menu.visible and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_time_left = maxf(_time_left - delta, 0.0)
	var seconds := ceili(_time_left)
	timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	if _time_left <= 0.0 and not _picked:
		_pick(_offers.pick_random() if not _offers.is_empty() else null)
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = STATUS_REFRESH
		_refresh_players()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var index: int = event.keycode - KEY_1
	if visible and index >= 0 and index < _offers.size():
		_pick(_offers[index])
		get_viewport().set_input_as_handled()
	elif OS.is_debug_build() and event.keycode == KEY_F2 and not visible \
			and world.local_player != null:
		open(0)
		get_viewport().set_input_as_handled()


func _pick(mod: Modifier) -> void:
	if _picked or not visible:
		return
	_picked = true
	if mod != null:
		_player.mods.pick(mod.id)
	for i in _offers.size():
		cards.get_child(i).lock(_offers[i] == mod)
	if _draft_round == 0:
		close()
		return
	_player.net_draft_round = _draft_round
	hint.text = "Waiting for other players…"


# bottom bar: every other player's robot, name and Picked / Choosing
func _refresh_players() -> void:
	var players := get_tree().get_nodes_in_group("player").filter(
			func(player: Node) -> bool: return player != _player)
	NodeUtil.fit_children(players_box, players.size())
	for i in players.size():
		var player: Node = players[i]
		var row := players_box.get_child(i)
		row.get_node("Icon").icon_color = Color.html(player.net_color) \
				if Color.html_is_valid(player.net_color) else HUD.FALLBACK_COLOR
		row.get_node("Name").text = str(player.net_nickname) if player.net_nickname != "" \
				else "Player"
		var done: bool = _draft_round <= 0 or int(player.net_draft_round) >= _draft_round
		row.get_node("Status").theme_type_variation = &"ModPicked" if done else &"ModChoosing"
		var label: Label = row.get_node("Status/Label")
		label.text = "Picked" if done else "Choosing"
		label.theme_type_variation = &"HudPillLabel" if done else &"HudSmall"
