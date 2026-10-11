extends MarginContainer

## Room browser: lists joinable (waiting, visible) rooms, filtered by the
## search box. Joining is the menu's job; this page only reports the pick.

signal room_chosen(room_name: String, title: String, passworded: bool)

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
	title.text = str(properties.get("title", room.get_name()))
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
		join.pressed.connect(room_chosen.emit.bind(room.get_name(), title.text, passworded))
	hbox.add_child(join)
	return chip
