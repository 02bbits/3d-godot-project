extends Control

## Lobby menu flow: main menu -> name -> create/join -> lobby -> in-game menu.
## Owns the room browser and the client-side lobby password gate.

const USER_CONFIG := "user://user_config.cfg"
const ROBOT_ICON := preload("res://scripts/ui/robot_icon.gd")
const PLAYER_COLORS := [
	Color("#FFC933"), Color("#4DA2FE"), Color("#FF6A5C"), Color("#7ADF7C"),
]
const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const MIN_ROUNDS := 1
const MAX_ROUNDS := 10

@onready var pages: Control = $Pages
@onready var status_label: Label = %StatusLabel
@onready var nickname_input: LineEdit = %Nickname
@onready var room_name_input: LineEdit = %RoomName
@onready var room_password_input: LineEdit = %Password
@onready var room_list: VBoxContainer = %RoomList
@onready var prompt_label: Label = %Prompt
@onready var prompt_password_input: LineEdit = %PromptPassword
@onready var play_title: Label = %PlayTitle
@onready var player_count_value: Label = %PlayerCountValue
@onready var rounds_count_value: Label = %RoundsCountValue
@onready var players_title: Label = %PlayersTitle
@onready var players_list: GridContainer = %PlayersList
@onready var room_title: Label = %RoomTitle
@onready var host_label: Label = %HostLabel
@onready var info_rounds: Label = %InfoRounds
@onready var info_max: Label = %InfoMax
@onready var start_button: Button = %LobbyStartButton
@onready var world: Node = owner if owner != null else get_parent()

# Static so a failed-connect message survives the reload triggered by leaving.
static var _error := ""

var _current_page := ""
var _game_started := false
var _leave_target := "MainMenu"
var _room_leave_handled := false
var _pending_room := ""
var _pending_password := ""
var _awaiting_password_check := false
var _roster_poll := 0.0
var _connected_name := ""
var _reconnecting := false
var _room_filter := ""
var _player_count := 4
var _rounds := 3


func _ready() -> void:
	world.game_started.connect(_on_game_started)
	world.game_ended.connect(_on_game_ended)

	Fusion.connection_failed.connect(_on_connection_failed)
	Fusion.connection_status_changed.connect(_on_connection_status_changed)
	Fusion.room_joined.connect(_on_room_joined)
	Fusion.room_left.connect(_on_room_left)
	Fusion.room_list_updated.connect(_on_room_list_updated)
	Fusion.player_joined.connect(_refresh_roster.unbind(2))
	Fusion.player_left.connect(_refresh_roster.unbind(2))
	Fusion.master_client_changed.connect(_refresh_roster.unbind(2))

	%PlayButton.pressed.connect(_show_page.bind("NameScreen"))
	%ExitButton.pressed.connect(get_tree().quit)
	%NameBackButton.pressed.connect(_show_page.bind("MainMenu"))
	%NameNextButton.pressed.connect(_on_name_next_pressed)
	%CreateLobbyButton.pressed.connect(_show_page.bind("CreateLobby"))
	%JoinLobbyButton.pressed.connect(_show_page.bind("BrowseLobbies"))
	%PlayBackButton.pressed.connect(_show_page.bind("NameScreen"))
	%CreateButton.pressed.connect(_on_create_pressed)
	%CreateBackButton.pressed.connect(_show_page.bind("PlayChoice"))
	%RefreshButton.pressed.connect(_refresh_rooms)
	%BrowseBackButton.pressed.connect(_show_page.bind("PlayChoice"))
	%PromptJoinButton.pressed.connect(_on_password_join_pressed)
	%PromptBackButton.pressed.connect(_show_page.bind("BrowseLobbies"))
	%LobbyStartButton.pressed.connect(_on_start_pressed)
	%LobbyLeaveButton.pressed.connect(_on_leave_lobby_pressed)
	%ResumeButton.pressed.connect(_close_ingame_menu)
	%LeaveLobbyButton.pressed.connect(_on_leave_game_pressed)
	# TODO: settings screens (main menu + in-game) are disabled placeholders;
	# enable and wire them when the settings menu exists.

	%Search.text_changed.connect(func(text: String) -> void:
		_room_filter = text.strip_edges().to_lower()
		_refresh_rooms())
	%PlayerMinus.pressed.connect(_step_player_count.bind(-1))
	%PlayerPlus.pressed.connect(_step_player_count.bind(1))
	%RoundsMinus.pressed.connect(_step_rounds.bind(-1))
	%RoundsPlus.pressed.connect(_step_rounds.bind(1))

	_load_nickname()
	_update_create_form()
	_show_page("MainMenu")


func _process(delta: float) -> void:
	# player names publish as room properties on join; poll so late arrivals show up
	if _current_page != "Lobby":
		return
	_roster_poll -= delta
	if _roster_poll <= 0.0:
		_roster_poll = 1.0
		_refresh_roster()


func _unhandled_input(event: InputEvent) -> void:
	if not _game_started or not Fusion.is_in_room():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if $Pages/InGameMenu.visible:
			_close_ingame_menu()
		else:
			_show_page("InGameMenu")


# SIGNAL HANDLERS

func _on_name_next_pressed() -> void:
	_save_nickname()
	var nickname := get_nickname()

	# Photon fixes the user id at connect time: if the name changed, drop the
	# connection and reconnect so the new name is the identity everywhere.
	if Fusion.is_connected_to_photon() and nickname != _connected_name:
		_reconnecting = true
		Fusion.disconnect_from_photon()
		var disconnect_timeout := 5.0
		while Fusion.is_connected_to_photon() and disconnect_timeout > 0.0:
			disconnect_timeout -= 0.1
			await get_tree().create_timer(0.1).timeout
		_reconnecting = false

	if Fusion.is_connected_to_photon():
		_show_page("PlayChoice")
		return

	_error = ""
	_status("Connecting...")
	_connected_name = nickname
	if Fusion.get_connection_status() != Fusion.STATUS_CONNECTING_TO_PHOTON:
		Fusion.connect_to_photon(nickname, Fusion.get_default_region())

	var timeout := 15.0
	while not Fusion.is_connected_to_photon() and timeout > 0.0 \
			and _current_page == "NameScreen" \
			and Fusion.get_connection_status() != Fusion.STATUS_ERROR:
		timeout -= 0.1
		await get_tree().create_timer(0.1).timeout

	if Fusion.is_connected_to_photon() and _current_page == "NameScreen":
		_show_page("PlayChoice")
	elif _current_page == "NameScreen" and _error.is_empty():
		_status("Connection timed out")


func _step_player_count(step: int) -> void:
	_player_count = clampi(_player_count + step, MIN_PLAYERS, MAX_PLAYERS)
	_update_create_form()


func _step_rounds(step: int) -> void:
	_rounds = clampi(_rounds + step, MIN_ROUNDS, MAX_ROUNDS)
	_update_create_form()


func _update_create_form() -> void:
	player_count_value.text = str(_player_count)
	rounds_count_value.text = str(_rounds)
	%PlayerMinus.disabled = _player_count <= MIN_PLAYERS
	%PlayerPlus.disabled = _player_count >= MAX_PLAYERS
	%RoundsMinus.disabled = _rounds <= MIN_ROUNDS
	%RoundsPlus.disabled = _rounds >= MAX_ROUNDS


func _on_create_pressed() -> void:
	var room_name := room_name_input.text.strip_edges()
	if room_name.is_empty():
		_status("Enter a room name")
		return
	var password := room_password_input.text
	var options := FusionRoomOptions.new()
	options.max_players = _player_count
	options.custom_properties = {
		"phase": "waiting",
		"passworded": not password.is_empty(),
		# ponytail: the password is readable by anyone who joins the room; this
		# is a client-side gate. Server enforcement needs Photon plugins/auth.
		"password": password,
		"rounds": _rounds,
	}
	# only these reach the lobby list; the password stays out of it
	options.lobby_properties = PackedStringArray(["phase", "passworded"])
	_status("Creating lobby...")
	Fusion.create_room(room_name, options)


func _on_room_row_pressed(room_name: String, passworded: bool) -> void:
	_pending_room = room_name
	if passworded:
		prompt_label.text = "'%s' is password protected" % room_name
		prompt_password_input.text = ""
		_show_page("PasswordPrompt")
		return
	_pending_password = ""
	_join_pending()


func _on_password_join_pressed() -> void:
	_pending_password = prompt_password_input.text
	_awaiting_password_check = true
	_join_pending()


func _on_start_pressed() -> void:
	# unlisting + closing keeps the room out of the browser and blocks late joins
	var room = Fusion.get_room()
	room.set_properties({
		"phase": "playing",
		"match_phase": "fight",
		"round": 1,
		"game_serial": int(room.get_custom_properties().get("game_serial", 0)) + 1,
	})
	room.set_visible(false)
	room.set_open(false)


func _on_leave_lobby_pressed() -> void:
	_leave_target = "PlayChoice"
	_status("Leaving lobby...")
	Fusion.leave_room()


func _on_leave_game_pressed() -> void:
	_leave_target = "MainMenu"
	Fusion.leave_room()


func _on_room_joined() -> void:
	_error = ""
	_room_leave_handled = false
	if _awaiting_password_check:
		_awaiting_password_check = false
		var room = Fusion.get_room()
		if str(room.get_custom_properties().get("password", "")) != _pending_password:
			_leave_target = "PasswordPrompt"
			Fusion.leave_room()
			return
	_publish_name()
	_show_page("Lobby")


func _publish_name() -> void:
	# Fusion has no nickname setter; publish the chosen name as a room property
	# so every client's roster can show it reliably
	var room = Fusion.get_room()
	if room == null:
		return
	room.set_property("name_%d" % Fusion.get_local_player_id(), get_nickname())


func _on_room_left() -> void:
	if _room_leave_handled:
		return
	_room_leave_handled = true
	if _leave_target == "MainMenu":
		# reload gives the next session a fresh world and menu state
		get_tree().reload_current_scene()
		return
	_show_page(_leave_target)
	if _leave_target == "PasswordPrompt":
		# wrong password: stay on the form with a clean field and a message
		prompt_password_input.text = ""
		_status("Wrong password")
	_leave_target = "MainMenu"


func _on_room_list_updated(_rooms: Array) -> void:
	if _current_page == "BrowseLobbies":
		_refresh_rooms()


func _on_connection_failed(error: String) -> void:
	_error = error
	_status(_error)


func _on_connection_status_changed(status: int) -> void:
	if status != Fusion.STATUS_DISCONNECTED or _room_leave_handled or _reconnecting:
		return
	if _leave_target == "MainMenu":
		get_tree().reload_current_scene()
	else:
		# an expected leave that only showed up as a disconnect (e.g. a rejected
		# room join): handle it like room_left instead of dumping the main menu
		_on_room_left()


func _on_game_started() -> void:
	_game_started = true
	_hide_all_pages()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# Results screen finished: back to the waiting lobby, still in the same room.
func _on_game_ended() -> void:
	_game_started = false
	_show_page("Lobby")


func _close_ingame_menu() -> void:
	_hide_all_pages()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# PRIVATE METHODS

func _show_page(page_name: String) -> void:
	_current_page = page_name
	visible = true
	for page in pages.get_children():
		page.visible = page.name == page_name
	_status("")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if page_name == "BrowseLobbies":
		_refresh_rooms()
	elif page_name == "Lobby":
		_refresh_roster()
	elif page_name == "PlayChoice":
		play_title.text = "READY, %s?" % get_nickname().to_upper()


func _hide_all_pages() -> void:
	_current_page = ""
	visible = false
	for page in pages.get_children():
		page.visible = false
	_status("")


func _status(text: String) -> void:
	status_label.text = text
	status_label.visible = not text.is_empty()


func _join_pending() -> void:
	_status("Joining lobby...")
	# a rejected join can drop the Photon connection; reconnect before retrying
	if not Fusion.is_connected_to_photon():
		Fusion.connect_to_photon(get_nickname(), Fusion.get_default_region())
		var timeout := 10.0
		while not Fusion.is_connected_to_photon() and timeout > 0.0 \
				and Fusion.get_connection_status() != Fusion.STATUS_ERROR:
			timeout -= 0.1
			await get_tree().create_timer(0.1).timeout
		if not Fusion.is_connected_to_photon():
			return
	Fusion.join_room(_pending_room, FusionRoomOptions.new())


# ROOM BROWSER

func _refresh_rooms() -> void:
	for child in room_list.get_children():
		child.free()
	for room in Fusion.get_room_list():
		var properties: Dictionary = room.get_custom_properties()
		# only Waiting rooms are joinable
		if str(properties.get("phase", "")) != "waiting":
			continue
		if not _room_filter.is_empty() \
				and not room.get_name().to_lower().contains(_room_filter):
			continue
		room_list.add_child(_make_room_row(room, properties))


func _make_room_row(room, properties: Dictionary) -> Control:
	var passworded := bool(properties.get("passworded", false))
	var full: bool = room.get_player_count() >= room.get_max_players() \
			or not room.get_is_open()
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"ChipPanel"
	chip.custom_minimum_size = Vector2(0, 66)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	chip.add_child(hbox)

	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(names)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = room.get_name()
	names.add_child(title)
	var subtitle := Label.new()
	subtitle.theme_type_variation = &"MutedLabel"
	subtitle.text = "Password protected" if passworded else "Open lobby"
	names.add_child(subtitle)

	var count := Label.new()
	count.theme_type_variation = &"TitleLabel"
	count.text = "%d/%d" % [room.get_player_count(), room.get_max_players()]
	hbox.add_child(count)

	var rounds := Label.new()
	rounds.theme_type_variation = &"MutedLabel"
	rounds.text = "First to %d" % int(properties.get("rounds", 3))
	hbox.add_child(rounds)

	var join := Button.new()
	join.theme_type_variation = &"BlueButton"
	join.custom_minimum_size = Vector2(130, 46)
	join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	join.text = "FULL" if full else "JOIN"
	join.disabled = full
	if not full:
		join.pressed.connect(_on_room_row_pressed.bind(room.get_name(), passworded))
	hbox.add_child(join)
	return chip


# WAITING ROOM

func _refresh_roster() -> void:
	if not Fusion.is_in_room():
		return
	var room = Fusion.get_room()
	if room == null:
		return
	var properties: Dictionary = room.get_custom_properties()
	var player_count := room.get_player_count()
	var max_players := room.get_max_players()
	players_title.text = "PLAYERS  %d / %d" % [player_count, max_players]
	room_title.text = room.get_room_name()
	info_rounds.text = str(int(properties.get("rounds", 3)))
	info_max.text = str(max_players)
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
		players_list.add_child(_make_player_chip(display_name, number, is_host))
		shown += 1
	for _i in maxi(max_players - shown, 0):
		players_list.add_child(_make_empty_slot())
	host_label.text = host_name
	start_button.visible = Fusion.is_master_client()
	start_button.disabled = player_count < 2
	start_button.tooltip_text = "" if player_count >= 2 else "Needs at least 2 players"


func _make_player_chip(display_name: String, number: int, is_host: bool) -> Control:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"ChipPanel"
	chip.custom_minimum_size = Vector2(0, 56)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	chip.add_child(hbox)
	hbox.add_child(_make_icon(number, 40))
	var name_label := Label.new()
	name_label.theme_type_variation = &"TitleLabel"
	name_label.text = display_name
	if number == Fusion.get_local_player_id():
		name_label.text += " (you)"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)
	if is_host:
		var badge := PanelContainer.new()
		badge.theme_type_variation = &"HostBadge"
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var badge_label := Label.new()
		badge_label.theme_type_variation = &"CardTitleLabel"
		badge_label.text = "Host"
		badge.add_child(badge_label)
		hbox.add_child(badge)
	return chip


func _make_empty_slot() -> Control:
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"SlotPanel"
	slot.custom_minimum_size = Vector2(0, 56)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.theme_type_variation = &"MutedLabel"
	label.text = "Waiting for player"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(label)
	return slot


func _make_icon(number: int, side: float) -> Control:
	var icon: Control = ROBOT_ICON.new()
	icon.icon_color = PLAYER_COLORS[number % PLAYER_COLORS.size()]
	icon.custom_minimum_size = Vector2(side, side)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


func get_nickname() -> String:
	if nickname_input.text.strip_edges().is_empty():
		nickname_input.text = "Player%d" % randi_range(100, 999)
	return nickname_input.text.strip_edges()


func _load_nickname() -> void:
	var config := ConfigFile.new()
	if config.load(USER_CONFIG) == Error.OK:
		nickname_input.text = config.get_value("player", "nickname", "")


func _save_nickname() -> void:
	var config := ConfigFile.new()
	config.load(USER_CONFIG)
	config.set_value("player", "nickname", get_nickname())
	config.save(USER_CONFIG)
