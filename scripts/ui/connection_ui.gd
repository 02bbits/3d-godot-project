extends Control

## Lobby menu flow: main menu -> name -> create/join -> lobby -> in-game menu.
## Owns connecting, joining (browser pick, lobby code, client-side password
## gate) and page switching; each page with its own logic (create form,
## browser, waiting room, settings) carries its own script.

const USER_CONFIG := "user://user_config.cfg"
# Lobby codes are the Photon room name; no 0/O/1/I so they read aloud cleanly.
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5
const JOIN_TIMEOUT := 10.0

@onready var pages: Control = $Pages
@onready var status_label: Label = %StatusLabel
@onready var nickname_input: LineEdit = %Nickname
@onready var prompt_label: Label = %Prompt
@onready var prompt_password_input: LineEdit = %PromptPassword
@onready var play_title: Label = %PlayTitle
@onready var name_robot: Control = %NameRobot
@onready var color_picker: Control = $ColorPicker
@onready var create_form: Control = $Pages/CreateLobby
@onready var lobby_page: Control = $Pages/Lobby
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
var _connected_name := ""
var _reconnecting := false
var _joining_code := false
var _pending_title := ""
var _settings_return := "MainMenu"
var _robot_color := Color("#FFC933")


func _ready() -> void:
	world.game_started.connect(_on_game_started)
	world.game_ended.connect(_on_game_ended)

	Fusion.connection_failed.connect(_on_connection_failed)
	Fusion.connection_status_changed.connect(_on_connection_status_changed)
	Fusion.room_joined.connect(_on_room_joined)
	Fusion.room_left.connect(_on_room_left)

	%PlayButton.pressed.connect(_show_page.bind("NameScreen"))
	%ExitButton.pressed.connect(get_tree().quit)
	%NameBackButton.pressed.connect(_show_page.bind("MainMenu"))
	%NameNextButton.pressed.connect(_on_name_next_pressed)
	%CreateLobbyButton.pressed.connect(_show_page.bind("CreateLobby"))
	%JoinLobbyButton.pressed.connect(_show_page.bind("BrowseLobbies"))
	%PlayBackButton.pressed.connect(_show_page.bind("NameScreen"))
	%CreateButton.pressed.connect(_on_create_pressed)
	%CreateBackButton.pressed.connect(_show_page.bind("PlayChoice"))
	%BrowseBackButton.pressed.connect(_show_page.bind("PlayChoice"))
	%PromptJoinButton.pressed.connect(_on_password_join_pressed)
	%PromptBackButton.pressed.connect(_show_page.bind("BrowseLobbies"))
	%LobbyStartButton.pressed.connect(_on_start_pressed)
	%LobbyLeaveButton.pressed.connect(_on_leave_lobby_pressed)
	%ResumeButton.pressed.connect(_close_ingame_menu)
	%LeaveLobbyButton.pressed.connect(_on_leave_game_pressed)
	%MainSettingsButton.pressed.connect(_open_settings.bind("MainMenu"))
	%InGameSettingsButton.pressed.connect(_open_settings.bind("InGameMenu"))
	$Pages/Settings.closed.connect(func() -> void: _show_page(_settings_return))
	%JoinCodeButton.pressed.connect(_on_join_code_pressed)
	%JoinCode.text_submitted.connect(_on_join_code_pressed.unbind(1))
	$Pages/BrowseLobbies.room_chosen.connect(_on_room_row_pressed)
	lobby_page.code_copied.connect(_status.bind("Code copied"))
	name_robot.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			color_picker.open(_robot_color))
	color_picker.color_chosen.connect(_set_robot_color)

	_load_player()
	_show_page("MainMenu")


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


func _on_create_pressed() -> void:
	if create_form.room_title().is_empty():
		_status("Enter a room name")
		return
	_status("Creating lobby...")
	# ponytail: no collision check (32^5 codes); a clash fails the create, retry then
	Fusion.create_room(_make_code(), create_form.room_options())


func _make_code() -> String:
	var code := ""
	for _i in CODE_LENGTH:
		code += CODE_CHARS[randi() % CODE_CHARS.length()]
	return code


func _on_join_code_pressed() -> void:
	var code: String = %JoinCode.text.strip_edges().to_upper()
	if code.length() != CODE_LENGTH:
		_status("Enter the %d-character lobby code" % CODE_LENGTH)
		return
	_pending_room = code
	_pending_title = code
	# empty password: an open room passes, a passworded one bounces to the prompt
	_pending_password = ""
	_awaiting_password_check = true
	_leave_target = "PlayChoice"
	_room_leave_handled = false
	_joining_code = true
	await _join_pending()
	var timeout := JOIN_TIMEOUT
	while _joining_code and timeout > 0.0:
		timeout -= 0.1
		await get_tree().create_timer(0.1).timeout
	if _joining_code:
		# neither joined nor rejected in time
		_joining_code = false
		_awaiting_password_check = false
		_leave_target = "MainMenu"
		_status("Lobby not found or already started")


func _on_room_row_pressed(room_name: String, title: String, passworded: bool) -> void:
	_pending_room = room_name
	_pending_title = title
	if passworded:
		prompt_label.text = "'%s' is password protected" % title
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
	var props: Dictionary = room.get_custom_properties()
	# the lobby's starting map, or a random one; every client swaps to it on start
	var start_map := int(props.get("start_map", -1))
	if start_map < 0 or start_map >= world.MAP_PATHS.size():
		start_map = randi() % world.MAP_PATHS.size()
	room.set_properties({
		"phase": "playing",
		# every game opens with a modifier draft for round 1
		"match_phase": "draft",
		"draft_round": 1,
		"round": 1,
		"map_index": start_map,
		"game_serial": int(props.get("game_serial", 0)) + 1,
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
	_joining_code = false
	if _awaiting_password_check:
		_awaiting_password_check = false
		var room = Fusion.get_room()
		_pending_title = str(room.get_custom_properties().get("title", _pending_room))
		if str(room.get_custom_properties().get("password", "")) != _pending_password:
			_leave_target = "PasswordPrompt"
			Fusion.leave_room()
			return
	_publish_name()
	_show_page("Lobby")


func _publish_name() -> void:
	# Fusion has no nickname setter; publish the chosen name (and robot color)
	# as room properties so every client's roster can show them reliably
	var room = Fusion.get_room()
	if room == null:
		return
	var id: int = Fusion.get_local_player_id()
	room.set_properties({
		"name_%d" % id: get_nickname(),
		"color_%d" % id: _robot_color.to_html(false),
	})


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
		prompt_password_input.text = ""
		if _pending_password.is_empty():
			# joined by code without a password: ask for it
			prompt_label.text = "'%s' is password protected" % _pending_title
		else:
			# wrong password: stay on the form with a clean field and a message
			_status("Wrong password")
	elif _joining_code:
		_joining_code = false
		_awaiting_password_check = false
		_status("Lobby not found or already started")
	_leave_target = "MainMenu"


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


func _open_settings(return_page: String) -> void:
	_settings_return = return_page
	_show_page("Settings")


func _close_ingame_menu() -> void:
	_hide_all_pages()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# PRIVATE METHODS

func _show_page(page_name: String) -> void:
	var changed := page_name != _current_page
	_current_page = page_name
	visible = true
	color_picker.close()
	# in a game the menu floats over a dimmed view instead of the backdrop
	$Backdrop.visible = not _game_started
	$InGameDim.visible = _game_started
	for page in pages.get_children():
		page.visible = page.name == page_name
		if page.visible and changed:
			$MenuFx.play_page(page)
	_status("")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if page_name == "PlayChoice":
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


func get_nickname() -> String:
	if nickname_input.text.strip_edges().is_empty():
		nickname_input.text = "Player%d" % randi_range(100, 999)
	return nickname_input.text.strip_edges()


func get_robot_color() -> Color:
	return _robot_color


func _load_player() -> void:
	var config := ConfigFile.new()
	config.load(USER_CONFIG)
	nickname_input.text = config.get_value("player", "nickname", "")
	var color_html := str(config.get_value("player", "color", ""))
	if Color.html_is_valid(color_html):
		_robot_color = Color.html(color_html)
		name_robot.icon_color = _robot_color
	else:
		# first run: a random robot color, so a fresh lobby isn't all one color
		_set_robot_color(RobotColor.PALETTE.pick_random())


func _set_robot_color(color: Color) -> void:
	_robot_color = color
	name_robot.icon_color = color
	var config := ConfigFile.new()
	config.load(USER_CONFIG)
	config.set_value("player", "color", color.to_html(false))
	config.save(USER_CONFIG)


func _save_nickname() -> void:
	var config := ConfigFile.new()
	config.load(USER_CONFIG)
	config.set_value("player", "nickname", get_nickname())
	config.save(USER_CONFIG)
