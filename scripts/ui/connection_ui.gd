extends Control

## Connection menu: nickname, room name, connect/disconnect, and status.
## Mirrors the Fusion starter project's connection flow (ui_connection.gd).

const USER_CONFIG := "user://user_config.cfg"

@export var user_id_prefix: String = "user_"

@onready var nickname_input: LineEdit = $Center/Panel/V/Nickname
@onready var room_input: LineEdit = $Center/Panel/V/Room
@onready var status_label: Label = $Center/Panel/V/StatusLabel
@onready var connect_button: Button = $Center/Panel/V/ConnectButton
@onready var disconnect_button: Button = $Center/Panel/V/DisconnectButton
@onready var world: Node = get_parent()

var _connection_requested: bool
# Static so the error persists across scene reloads triggered by disconnect.
static var _error: String


func _ready() -> void:
	world.local_player_changed.connect(_on_local_player_changed)

	Fusion.room_left.connect(_update_status)
	Fusion.connection_failed.connect(_on_connection_failed)
	Fusion.connection_status_changed.connect(_on_connection_status_changed)

	connect_button.pressed.connect(_on_connect_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)

	_show_menu(true)
	_update_status()
	_load_nickname()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var show_menu := !visible

		# Menu can be hidden only when there is already a local player spawned.
		if not show_menu and world.local_player == null:
			return

		_show_menu(show_menu)


# SIGNAL HANDLERS

func _on_connect_pressed() -> void:
	_connect()


func _on_disconnect_pressed() -> void:
	_disconnect()


func _on_local_player_changed(player: Node) -> void:
	_show_menu(player == null)


func _on_connection_failed(error: String) -> void:
	_error = error
	_update_status()


func _on_connection_status_changed(status: int) -> void:
	if status == Fusion.STATUS_DISCONNECTED:
		get_tree().reload_current_scene()
	else:
		_error = ""

	_update_status()


# PRIVATE METHODS

func _connect() -> void:
	if Fusion.is_in_room():
		Fusion.leave_room()

	var user_id := "%s%d" % [user_id_prefix, randi()]
	_save_nickname()

	if not Fusion.is_connected_to_photon():
		Fusion.connect_to_photon(user_id)

	_connection_requested = true
	var connection_timeout := 15.0

	# Poll until connected — FusionClient.connect_to_photon is async with no await.
	while not Fusion.is_connected_to_photon() and _connection_requested:
		connection_timeout -= 0.1

		if connection_timeout < 0.0:
			_error = "Connection timed out"
			Fusion.disconnect_from_photon()
			_update_status()
			return

		await get_tree().create_timer(0.1).timeout

	if not Fusion.is_connected_to_photon():
		_update_status()
		return

	var room_options := FusionRoomOptions.new()
	room_options.max_players = 8
	room_options.custom_properties = { "game_mode": "fps" }
	room_options.lobby_properties = ["game_mode"]

	Fusion.join_or_create_room(room_input.text, room_options)


func _disconnect() -> void:
	if Fusion.get_connection_status() == Fusion.STATUS_DISCONNECTED:
		return

	_connection_requested = false
	Fusion.disconnect_from_photon()

	await Fusion.connection_status_changed


func _update_status() -> void:
	var status := Fusion.get_connection_status()
	var status_text := _get_connection_status_text(status)

	if _error:
		status_label.text = _error
		status_label.visible = true
	else:
		status_label.text = status_text
		status_label.visible = status != Fusion.STATUS_IN_ROOM and status != Fusion.STATUS_DISCONNECTED

	connect_button.visible = status == Fusion.STATUS_DISCONNECTED
	disconnect_button.visible = status != Fusion.STATUS_DISCONNECTED


func _show_menu(show_menu: bool) -> void:
	visible = show_menu
	var mode = Input.MOUSE_MODE_VISIBLE if show_menu else Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(mode)


func _get_connection_status_text(status: int) -> String:
	match status:
		Fusion.STATUS_DISCONNECTED:
			return "Disconnected"
		Fusion.STATUS_CONNECTING_TO_PHOTON:
			return "Connecting..."
		Fusion.STATUS_CONNECTED_TO_PHOTON:
			return "Connected"
		Fusion.STATUS_JOINING_ROOM:
			return "Joining Room..."
		Fusion.STATUS_IN_ROOM:
			return "In Room"
		Fusion.STATUS_ERROR:
			return "Error"

	return "Unknown"


func get_nickname() -> String:
	if nickname_input.text.strip_edges() == "":
		nickname_input.text = "Player%d" % randi_range(100, 999)
	return nickname_input.text


func _load_nickname() -> void:
	var config := ConfigFile.new()
	if config.load(USER_CONFIG) == Error.OK:
		nickname_input.text = config.get_value("player", "nickname", "")


func _save_nickname() -> void:
	if nickname_input.text == "":
		nickname_input.text = "Player%d" % randi_range(100, 999)
		return

	var config := ConfigFile.new()
	config.load(USER_CONFIG)
	config.set_value("player", "nickname", nickname_input.text)
	config.save(USER_CONFIG)
