extends MarginContainer

## Waiting room: roster chips (name, robot color, host / ready badge), the
## room's rules and its join code. Players ready up (room property
## "ready_<number>"); the host can start once everyone else is ready. A status
## line always says what everyone is waiting for. Names, colors and ready flags
## arrive as room properties, so the roster is polled while the page is open.

signal code_copied

const PLAYER_CHIP := preload("res://scenes/ui/player_chip.tscn")
const EMPTY_SLOT := preload("res://scenes/ui/empty_slot.tscn")
const WORLD := preload("res://scripts/worlds/world.gd")
# fallback chip colors for players who joined before publishing a color
const PLAYER_COLORS := [
	Color("#FFC933"), Color("#4DA2FE"), Color("#FF6A5C"), Color("#7ADF7C"),
]
const POLL_SECONDS := 0.5

@onready var players_title: Label = %PlayersTitle
@onready var players_list: GridContainer = %PlayersList
@onready var room_title: Label = %RoomTitle
@onready var host_label: Label = %HostLabel
@onready var info_rounds: Label = %InfoRounds
@onready var info_max: Label = %InfoMax
@onready var info_wins: Label = %InfoWins
@onready var info_map: Label = %InfoMap
@onready var start_button: Button = %LobbyStartButton
@onready var ready_button: Button = %LobbyReadyButton
@onready var status_label: Label = %LobbyStatus

var _roster_poll := 0.0
# the local player's ready flag; the room property can lag behind a click
var _local_ready := false


func _ready() -> void:
	Fusion.player_joined.connect(refresh.unbind(2))
	Fusion.player_left.connect(refresh.unbind(2))
	Fusion.master_client_changed.connect(refresh.unbind(2))
	visibility_changed.connect(func() -> void:
		if visible:
			_local_ready = _room_flag("ready_%d" % Fusion.get_local_player_id())
			refresh())
	ready_button.pressed.connect(_toggle_ready)
	%LobbyCode.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(%LobbyCode.text)
		code_copied.emit())


func _process(delta: float) -> void:
	# player names publish as room properties on join; poll so late arrivals show up
	if not is_visible_in_tree():
		return
	_roster_poll -= delta
	if _roster_poll <= 0.0:
		_roster_poll = POLL_SECONDS
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
	var unready: PackedStringArray = [] # everyone but the host who still has to ready up
	var local_id: int = Fusion.get_local_player_id()
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
		var is_ready := _local_ready if number == local_id \
				else bool(properties.get("ready_%d" % number, false))
		if not is_host and not is_ready and number != local_id:
			unready.append(display_name)
		players_list.add_child(_make_player_chip(display_name, number, color, is_host, is_ready))
		shown += 1
	for _i in maxi(max_players - shown, 0):
		players_list.add_child(EMPTY_SLOT.instantiate())
	host_label.text = host_name
	var am_host := Fusion.is_master_client()
	var everyone_ready := player_count >= 2 and unready.is_empty() and (am_host or _local_ready)
	start_button.visible = am_host
	start_button.disabled = not everyone_ready
	ready_button.visible = not am_host
	ready_button.text = "CANCEL READY" if _local_ready else "READY UP"
	ready_button.theme_type_variation = &"CreamButton" if _local_ready else &"PrimaryButton"
	status_label.text = _status_text(am_host, player_count, unready, host_name, everyone_ready)
	start_button.tooltip_text = "" if everyone_ready else status_label.text


# what this player can do now and what everyone is waiting for
func _status_text(am_host: bool, player_count: int, unready: PackedStringArray,
		host_name: String, everyone_ready: bool) -> String:
	if player_count < 2:
		return "Waiting for another player to join — share the lobby code"
	if am_host:
		if everyone_ready:
			return "Everyone's ready — start the match when you are"
		return "Waiting for %s to ready up" % _names(unready)
	if not _local_ready:
		return "Press READY UP when you're set — %s starts once everyone is ready" % host_name
	if not unready.is_empty():
		return "You're ready — waiting for %s" % _names(unready)
	return "Everyone's ready — waiting for %s to start" % host_name


# "Bolt", "Bolt and Gizmo", "Bolt, Gizmo and 2 more"
static func _names(names: PackedStringArray) -> String:
	if names.size() <= 2:
		return " and ".join(names)
	return "%s, %s and %d more" % [names[0], names[1], names.size() - 2]


func _toggle_ready() -> void:
	var room = Fusion.get_room()
	if room == null:
		return
	_local_ready = not _local_ready
	room.set_properties({"ready_%d" % Fusion.get_local_player_id(): _local_ready})
	refresh()


func _room_flag(key: String) -> bool:
	var room = Fusion.get_room() if Fusion.is_in_room() else null
	return room != null and bool(room.get_custom_properties().get(key, false))


func _make_player_chip(display_name: String, number: int, color: Color, is_host: bool,
		is_ready: bool) -> Control:
	var chip := PLAYER_CHIP.instantiate()
	chip.get_node("H/Icon").icon_color = color
	chip.get_node("H/Name").text = display_name \
			+ (" (you)" if number == Fusion.get_local_player_id() else "")
	chip.get_node("H/HostBadge").visible = is_host
	# the host readies by pressing Start, so only the others show a ready badge
	var badge: PanelContainer = chip.get_node("H/ReadyBadge")
	badge.visible = not is_host
	badge.theme_type_variation = &"ReadyBadge" if is_ready else &"WaitingBadge"
	var label: Label = badge.get_node("Label")
	label.text = "Ready" if is_ready else "Not ready"
	label.theme_type_variation = &"CardTitleLabel" if is_ready else &"MutedLabel"
	return chip
