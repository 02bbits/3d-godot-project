extends MarginContainer

## Waiting room: roster chips (name, robot color, host badge), the room's rules
## and its join code. Names and colors arrive as room properties, so the
## roster is polled while the page is open.

signal code_copied

const PLAYER_CHIP := preload("res://scenes/ui/player_chip.tscn")
const EMPTY_SLOT := preload("res://scenes/ui/empty_slot.tscn")
const WORLD := preload("res://scripts/worlds/world.gd")
# fallback chip colors for players who joined before publishing a color
const PLAYER_COLORS := [
	Color("#FFC933"), Color("#4DA2FE"), Color("#FF6A5C"), Color("#7ADF7C"),
]

@onready var players_title: Label = %PlayersTitle
@onready var players_list: GridContainer = %PlayersList
@onready var room_title: Label = %RoomTitle
@onready var host_label: Label = %HostLabel
@onready var info_rounds: Label = %InfoRounds
@onready var info_max: Label = %InfoMax
@onready var info_wins: Label = %InfoWins
@onready var info_map: Label = %InfoMap
@onready var start_button: Button = %LobbyStartButton

var _roster_poll := 0.0


func _ready() -> void:
	Fusion.player_joined.connect(refresh.unbind(2))
	Fusion.player_left.connect(refresh.unbind(2))
	Fusion.master_client_changed.connect(refresh.unbind(2))
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())
	%LobbyCode.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(%LobbyCode.text)
		code_copied.emit())


func _process(delta: float) -> void:
	# player names publish as room properties on join; poll so late arrivals show up
	if not is_visible_in_tree():
		return
	_roster_poll -= delta
	if _roster_poll <= 0.0:
		_roster_poll = 1.0
		refresh()


func refresh() -> void:
	if not Fusion.is_in_room():
		return
	var room = Fusion.get_room()
	if room == null:
		return
	var properties: Dictionary = room.get_custom_properties()
	var player_count := room.get_player_count()
	var max_players := room.get_max_players()
	players_title.text = "PLAYERS  %d / %d" % [player_count, max_players]
	room_title.text = str(properties.get("title", room.get_room_name()))
	%LobbyCode.text = room.get_room_name()
	info_rounds.text = str(int(properties.get("rounds", 3)))
	info_max.text = str(max_players)
	info_wins.text = str(int(properties.get("match_wins", 2)))
	var start_map := int(properties.get("start_map", -1))
	info_map.text = "RANDOM" if start_map < 0 or start_map >= WORLD.MAP_PATHS.size() \
			else WORLD.map_display_name(start_map)
	for child in players_list.get_children():
		child.free()
	var host_name := ""
	var shown := 0
	for player in room.get_players():
		if player.get_is_inactive():
			continue
		var number := int(player.get_number())
		var display_name := str(properties.get("name_%d" % number, ""))
		if display_name.is_empty():
			display_name = player.get_name()
		if display_name.is_empty():
			display_name = "Player %d" % number
		var is_host := player.get_is_master_client()
		if is_host:
			host_name = display_name
		var color_html := str(properties.get("color_%d" % number, ""))
		var color: Color = Color.html(color_html) if Color.html_is_valid(color_html) \
				else PLAYER_COLORS[number % PLAYER_COLORS.size()]
		players_list.add_child(_make_player_chip(display_name, number, color, is_host))
		shown += 1
	for _i in maxi(max_players - shown, 0):
		players_list.add_child(EMPTY_SLOT.instantiate())
	host_label.text = host_name
	start_button.visible = Fusion.is_master_client()
	start_button.disabled = player_count < 2
	start_button.tooltip_text = "" if player_count >= 2 else "Needs at least 2 players"


func _make_player_chip(display_name: String, number: int, color: Color, is_host: bool) -> Control:
	var chip := PLAYER_CHIP.instantiate()
	chip.get_node("H/Icon").icon_color = color
	chip.get_node("H/Name").text = display_name \
			+ (" (you)" if number == Fusion.get_local_player_id() else "")
	chip.get_node("H/HostBadge").visible = is_host
	return chip
