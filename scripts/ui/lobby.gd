extends CanvasLayer

var _rooms: Array = []

@onready var _net: Node = get_parent()
@onready var _root: Control = %Root
@onready var _name_edit: LineEdit = %NameEdit
@onready var _list: ItemList = %RoomList
@onready var _status: Label = %Status


func _ready() -> void:
	_name_edit.text = "room_%04d" % [randi() % 10000]
	_net.room_error.connect(_on_room_error)
	Fusion.room_joined.connect(_on_room_joined)
	Fusion.room_left.connect(_on_room_left)
	Fusion.room_list_updated.connect(_on_room_list_updated)
	Fusion.connected_to_photon.connect(_refresh_rooms)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%RefreshButton.pressed.connect(_on_refresh_pressed)
	_name_edit.text_submitted.connect(func(_t: String): _on_join_pressed())
	_list.item_activated.connect(_on_room_activated)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_rooms()


func _on_room_joined() -> void:
	hide()
	_name_edit.release_focus()


func _on_room_left() -> void:
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_rooms()


func _on_room_error(message: String) -> void:
	_status.text = message
	_refresh_rooms()


func _on_room_list_updated(rooms: Array) -> void:
	_rooms = rooms
	_fill_list()


func _on_host_pressed() -> void:
	_status.text = "connecting..."
	_net.host_room(_name_edit.text)


func _on_join_pressed() -> void:
	_status.text = "connecting..."
	_net.join_room(_name_edit.text)


func _on_refresh_pressed() -> void:
	if not Fusion.is_connected_to_photon():
		_status.text = "connecting to Photon..."
		return
	_status.text = "refreshing..."
	_refresh_rooms()


func _on_room_activated(index: int) -> void:
	if index < 0 or index >= _rooms.size():
		return
	var listing: Object = _rooms[index]
	if listing == null or not listing.has_method("get_name"):
		return
	_name_edit.text = String(listing.get_name())
	_on_join_pressed()


func _refresh_rooms() -> void:
	_rooms = []
	if Fusion.is_connected_to_photon():
		_rooms = Fusion.get_room_list()
	_fill_list()


func _fill_list() -> void:
	_list.clear()
	for listing: Object in _rooms:
		if listing == null or not listing.has_method("get_name"):
			continue
		_list.add_item("%s  (%d/%d)" % [
			listing.get_name(), listing.get_player_count(), listing.get_max_players()])
