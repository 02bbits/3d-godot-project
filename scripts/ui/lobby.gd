extends CanvasLayer

var _rooms: Array = []
var _selected_room_name := ""
var _in_game := false
var _last_error := ""
var _is_master := false

@onready var _net: Node = get_parent()
@onready var _root: Control = %Root
@onready var _dim: ColorRect = %Dim
@onready var _main_menu: Control = %MainMenu
@onready var _browser: Control = %Browser
@onready var _waiting: Control = %Waiting
@onready var _game_menu: Control = %GameMenu
@onready var _main_status: Label = %MainStatus
@onready var _connection_status: Label = %ConnectionStatus
@onready var _name_edit: LineEdit = %NameEdit
@onready var _password_edit: LineEdit = %PasswordEdit
@onready var _list: ItemList = %RoomList
@onready var _status: Label = %Status
@onready var _waiting_room: Label = %WaitingRoom
@onready var _waiting_players: Label = %WaitingPlayers
@onready var _waiting_status: Label = %WaitingStatus
@onready var _start_button: Button = %StartButton


func _ready() -> void:
	_name_edit.text = "room_%04d" % [randi() % 10000]
	_net.room_error.connect(_on_room_error)
	_net.network_status_changed.connect(_on_network_status_changed)
	_net.room_list_changed.connect(_on_room_list_changed)
	_net.room_ready.connect(_on_room_ready)
	_net.room_phase_changed.connect(_on_room_phase_changed)
	_net.room_members_changed.connect(_on_room_members_changed)
	_net.match_started.connect(_on_match_started)
	_net.room_left.connect(_on_room_left)
	%PlayOnlineButton.pressed.connect(_on_play_online_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%BackButton.pressed.connect(_on_back_pressed)
	%CreateButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%RefreshButton.pressed.connect(_on_refresh_pressed)
	%WaitingLeaveButton.pressed.connect(_on_leave_pressed)
	%GameLeaveButton.pressed.connect(_on_leave_pressed)
	%StartButton.pressed.connect(_on_start_pressed)
	_name_edit.text_submitted.connect(func(_t: String): _on_host_pressed())
	_password_edit.text_submitted.connect(func(_t: String): _on_join_pressed())
	_list.item_selected.connect(_on_room_selected)
	_list.item_activated.connect(_on_room_activated)
	_net.refresh_rooms()
	_show_main_menu()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _show_main_menu() -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_menu.show()
	_browser.hide()
	_waiting.hide()
	_game_menu.hide()
	_dim.show()
	_in_game = false
	_is_master = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _show_browser() -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_menu.hide()
	_browser.show()
	_waiting.hide()
	_game_menu.hide()
	_dim.show()
	_in_game = false
	_is_master = false
	_net.refresh_rooms()
	_name_edit.grab_focus()


func _show_waiting() -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_menu.hide()
	_browser.hide()
	_waiting.show()
	_game_menu.hide()
	_dim.show()
	_in_game = false
	_is_master = false


func _show_game() -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_menu.hide()
	_browser.hide()
	_waiting.hide()
	_game_menu.hide()
	_dim.hide()
	_in_game = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_play_online_pressed() -> void:
	_show_browser()
	_status.text = "Connecting to Photon..."


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_back_pressed() -> void:
	_show_main_menu()


func _on_room_ready(room_name: String, phase: String, password_required: bool) -> void:
	_last_error = ""
	_password_edit.clear()
	_show_waiting()
	_waiting_room.text = room_name + ("  [PRIVATE]" if password_required else "  [PUBLIC]")
	_on_room_phase_changed(phase)
	_update_start_button()


func _on_match_started() -> void:
	_show_game()


func _on_room_left() -> void:
	_show_browser()
	_status.text = _last_error if not _last_error.is_empty() else "Left room."
	_last_error = ""


func _on_network_status_changed(connected: bool, message: String) -> void:
	_connection_status.text = message
	_main_status.text = message
	if connected and _browser.visible:
		_status.text = "Connected. Select a room or create one."


func _on_room_error(message: String) -> void:
	_last_error = message
	_status.text = message
	_main_status.text = message
	%CreateButton.disabled = false
	%JoinButton.disabled = false
	%RefreshButton.disabled = false


func _on_room_list_changed(rooms: Array) -> void:
	_rooms = rooms
	_fill_list()


func _on_host_pressed() -> void:
	_status.text = "Creating room..."
	_set_browser_busy(true)
	_net.host_room(_name_edit.text, _password_edit.text)


func _on_join_pressed() -> void:
	var room_name := _selected_room_name if not _selected_room_name.is_empty() else _name_edit.text
	_status.text = "Joining room..."
	_set_browser_busy(true)
	_net.join_room(room_name, _password_edit.text)


func _on_refresh_pressed() -> void:
	_status.text = "Refreshing..."
	_net.refresh_rooms()


func _on_room_selected(index: int) -> void:
	if index < 0 or index >= _rooms.size():
		_selected_room_name = ""
		return
	var listing: Object = _rooms[index]
	if listing != null and listing.has_method("get_name"):
		_selected_room_name = String(listing.get_name())
		_name_edit.text = _selected_room_name


func _on_room_activated(index: int) -> void:
	_on_room_selected(index)
	_on_join_pressed()


func _fill_list() -> void:
	_list.clear()
	for listing: Object in _rooms:
		if listing == null or not listing.has_method("get_name"):
			continue
		var props: Dictionary = listing.get_custom_properties() if listing.has_method("get_custom_properties") else {}
		if String(props.get("game_version", "")) != "1":
			continue
		var locked := bool(props.get("password_required", false))
		var phase := String(props.get("phase", "playing"))
		var count := int(listing.get_player_count())
		var max_players := int(listing.get_max_players())
		var label := String(listing.get_name())
		label += "  [PRIVATE]" if locked else "  [PUBLIC]"
		label += "  %d/%d" % [count, max_players]
		label += "  [IN GAME]" if phase == "playing" else "  [WAITING]"
		_list.add_item(label)
		var unavailable: bool = not listing.get_is_open() or count >= max_players or phase == "playing"
		_list.set_item_disabled(_list.get_item_count() - 1, unavailable)


func _on_room_phase_changed(phase: String) -> void:
	if phase == "playing":
		_waiting_status.text = "Starting match..."
		_start_button.disabled = true
	else:
		_waiting_status.text = "Waiting for the host to start the match."
	_update_start_button()


func _on_room_members_changed(player_count: int, max_players: int, is_master: bool) -> void:
	_waiting_players.text = "Players: %d / %d" % [player_count, max_players]
	_is_master = is_master
	_update_start_button()


func _update_start_button() -> void:
	_start_button.visible = _is_master
	_start_button.disabled = not _is_master or _waiting_status.text != "Waiting for the host to start the match."


func _on_start_pressed() -> void:
	_waiting_status.text = "Starting match..."
	_start_button.disabled = true
	_net.start_match()


func _on_leave_pressed() -> void:
	_in_game = false
	_game_menu.hide()
	_net.leave_room()


func _set_browser_busy(busy: bool) -> void:
	%CreateButton.disabled = busy
	%JoinButton.disabled = busy
	%RefreshButton.disabled = busy


func _unhandled_input(event: InputEvent) -> void:
	if not _in_game or not event is InputEventKey or not event.pressed or event.keycode != KEY_ESCAPE:
		return
	_game_menu.visible = not _game_menu.visible
	_root.mouse_filter = Control.MOUSE_FILTER_STOP if _game_menu.visible else Control.MOUSE_FILTER_IGNORE
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if _game_menu.visible else Input.MOUSE_MODE_CAPTURED)
