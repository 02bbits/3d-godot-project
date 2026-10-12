extends MarginContainer

## Room browser: lists joinable (waiting, visible) rooms, filtered by the
## search box. Joining is the menu's job; this page only reports the pick.

signal room_chosen(room_name: String, title: String, passworded: bool)

const ROOM_ROW := preload("res://scenes/ui/room_row.tscn")

@onready var room_list: VBoxContainer = %RoomList

var _room_filter := ""


func _ready() -> void:
	%RefreshButton.pressed.connect(refresh)
	%Search.text_changed.connect(func(text: String) -> void:
		_room_filter = text.strip_edges().to_lower()
		refresh())
	Fusion.room_list_updated.connect(func(_rooms: Array) -> void:
		if is_visible_in_tree():
			refresh())
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())


func refresh() -> void:
	for child in room_list.get_children():
		child.free()
	for room in Fusion.get_room_list():
		var properties: Dictionary = room.get_custom_properties()
		# only Waiting rooms are joinable
		if str(properties.get("phase", "")) != "waiting":
			continue
		if not _room_filter.is_empty() \
				and not str(properties.get("title", room.get_name())).to_lower().contains(_room_filter):
			continue
		room_list.add_child(_make_room_row(room, properties))


func _make_room_row(room, properties: Dictionary) -> Control:
	var passworded := bool(properties.get("passworded", false))
	var full: bool = room.get_player_count() >= room.get_max_players() \
			or not room.get_is_open()
	var row := ROOM_ROW.instantiate()
	var title := str(properties.get("title", room.get_name()))
	row.get_node("H/Names/Title").text = title
	row.get_node("H/Names/Subtitle").text = "Password protected" if passworded else "Open lobby"
	row.get_node("H/Count").text = "%d/%d" % [room.get_player_count(), room.get_max_players()]
	row.get_node("H/Rounds").text = "First to %d" % int(properties.get("rounds", 3))
	var join: Button = row.get_node("H/Join")
	join.text = "FULL" if full else "JOIN"
	join.disabled = full
	if not full:
		join.pressed.connect(room_chosen.emit.bind(room.get_name(), title, passworded))
	return row
