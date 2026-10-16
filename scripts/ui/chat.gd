extends PanelContainer

## Room chat (scenes/ui/chat.tscn): the waiting room's chat card and the
## in-game overlay (resting pills that fade out; Enter opens the history and
## the input). Each player's last message is one room property,
## "chat_<number>" = "<serial>\t<text>"; every instance polls it, so both
## instances share one conversation. System lines (joins, leaves, ready, round
## start and winner) are derived locally from the shared room state and the
## match manager, so nothing extra is networked. In game, sending also bumps
## the local player's net_chat_count (the "..." bubble over the robot).

const POLL_SECONDS := 0.25
const MAX_HISTORY := 50
# in game with the chat closed: the newest lines show, then fade out
const RESTING_COUNT := 4
const RESTING_SECONDS := 8.0
const RESTING_FADE := 2.0
const OPEN_LOG_HEIGHT := 320.0
# in-game pills hug their text up to this width, then wrap
const PILL_MAX_WIDTH := 460.0
const WHEEL_STEP := 40
# fallback name color for players who joined before publishing a color
const NAME_COLOR := Color("#FFC933")

## in-game overlay: input hidden until Enter, shown only while a game runs
@export var in_game := false
## world.gd, for the local player and the game start/end signals (in game only)
@export var world: Node

@onready var header: Control = %Header
@onready var hint: Label = %Hint
@onready var log_panel: PanelContainer = %LogPanel
@onready var scroll: ScrollContainer = %Scroll
@onready var log_list: VBoxContainer = %Log
@onready var input_row: Control = %InputRow
@onready var input: LineEdit = %Input
@onready var keys: Label = %Keys

var _poll := 0.0
var _primed := false # first poll only records state: no replay of old messages
var _seen := {} # player number -> last serial shown
var _known := {} # player number -> name, for join / leave lines
var _ready_flags := {} # player number -> ready, for "is ready" lines
var _sent := 0
var _lines: Array[Dictionary] = [] # {bbcode, width, mention, time}
var _open := false


func _ready() -> void:
	input.text_submitted.connect(_send)
	input.gui_input.connect(_on_input_gui)
	%Send.pressed.connect(func() -> void: _send(input.text))
	Fusion.room_left.connect(_clear)
	# new lines keep the log scrolled to the newest message
	scroll.get_v_scroll_bar().changed.connect(func() -> void:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value))
	var match_manager := get_tree().get_first_node_in_group("match_manager")
	if match_manager != null:
		match_manager.phase_changed.connect(_on_phase_changed.bind(match_manager))
	if in_game:
		visible = false
		log_panel.theme_type_variation = &"ChatPlain"
		%Send.visible = false
		input.placeholder_text = "Chat message"
		hint.text = "Mouse wheel to scroll"
		world.game_started.connect(show)
		world.game_ended.connect(func() -> void:
			_close()
			hide())
	else:
		%Channel.visible = false
		keys.visible = false
	_set_open(false)
	_render()


func _process(delta: float) -> void:
	if in_game and not _open:
		_update_rows() # resting lines age out
	if not Fusion.is_in_room():
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_SECONDS
	var room = Fusion.get_room()
	if room == null:
		return
	var props: Dictionary = room.get_custom_properties()
	var waiting := str(props.get("phase", "waiting")) == "waiting"
	var present := {}
	for player in room.get_players():
		if player.get_is_inactive():
			continue
		var number := int(player.get_number())
		present[number] = true
		var display_name := str(props.get("name_%d" % number, ""))
		if not display_name.is_empty() and not _known.has(number):
			_known[number] = display_name
			if _primed:
				_system("%s joined the lobby" % display_name)
		var is_ready := bool(props.get("ready_%d" % number, false))
		if _primed and waiting and is_ready and not _ready_flags.get(number, false):
			_system("%s is ready" % _name_of(number, props))
		_ready_flags[number] = is_ready
		var parts := str(props.get("chat_%d" % number, "0\t")).split("\t", true, 1)
		var serial := int(parts[0])
		if serial <= int(_seen.get(number, 0)):
			continue
		_seen[number] = serial
		# ponytail: one property per sender, so two messages from one player
		# inside one poll drop the first; switch to Fusion events if that matters
		# own messages too: the other instance (lobby / in game) sent them
		if _primed and parts.size() > 1:
			_add(number, parts[1], props)
	for number in _known.keys():
		if not present.has(number):
			_system("%s left" % _known[number])
			_known.erase(number)
			_ready_flags.erase(number)
	if not in_game:
		hint.text = "%d online" % present.size()
	_primed = true


func _unhandled_input(event: InputEvent) -> void:
	# a captured mouse means active play: no menu or draft screen is up
	if not in_game or not visible or _open or world.local_player == null \
			or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_set_open(true)
		input.grab_focus()
		world.local_player.set_typing(true)


# the mouse stays captured in game, so the open log scrolls by hand
func _input(event: InputEvent) -> void:
	if not (in_game and _open and event is InputEventMouseButton and event.pressed):
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll.scroll_vertical += WHEEL_STEP * (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		get_viewport().set_input_as_handled()


func _on_input_gui(event: InputEvent) -> void:
	# Esc closes the chat without also opening the in-game menu
	if in_game and event.is_action_pressed("ui_cancel"):
		input.accept_event()
		_close()


func _on_phase_changed(phase: String, _previous: String, match_manager: Node) -> void:
	if phase == "countdown" and int(match_manager.match_number) == 1:
		_system("Round %d started" % int(match_manager.round))
	elif phase in ["intermission", "game_over"] \
			and str(match_manager.result_kind) in ["round", "game"]:
		_system(str(match_manager.last_result))


func _send(text: String) -> void:
	text = text.strip_edges()
	input.clear()
	var room = Fusion.get_room() if Fusion.is_in_room() else null
	if not text.is_empty() and room != null:
		var id: int = Fusion.get_local_player_id()
		_sent = maxi(_sent, int(_seen.get(id, 0))) + 1
		_seen[id] = _sent
		room.set_properties({"chat_%d" % id: "%d\t%s" % [_sent, text]})
		_add(id, text, room.get_custom_properties())
		if in_game and world.local_player != null:
			world.local_player.net_chat_count += 1
	if in_game:
		_close()


func _close() -> void:
	if not in_game:
		return
	input.clear()
	input.release_focus()
	_set_open(false)
	if world.local_player != null:
		world.local_player.set_typing(false)


# in game: the open panel (history + input) or the resting pills
func _set_open(open: bool) -> void:
	_open = open
	if not in_game:
		return
	theme_type_variation = &"ChatOverlay" if open else &"ChatPlain"
	header.visible = open
	input_row.visible = open
	keys.visible = open
	# resting, the log sizes to its few visible lines instead of scrolling
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if open \
			else ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = OPEN_LOG_HEIGHT if open else 0.0
	_update_rows()


# MESSAGES

func _add(number: int, text: String, props: Dictionary) -> void:
	var local_id: int = Fusion.get_local_player_id()
	var display_name := _name_of(number, props)
	if number == local_id:
		display_name += " (you)"
	var color_html := str(props.get("color_%d" % number, ""))
	var color := Color.html(color_html) if Color.html_is_valid(color_html) else NAME_COLOR
	var my_name := str(props.get("name_%d" % local_id, ""))
	var mention := number != local_id and not my_name.is_empty() and text.containsn(my_name)
	_push("[b][color=#%s]%s[/color][/b] %s" % [color.to_html(false), _escape(display_name), _escape(text)],
			_text_width(&"bold_font", display_name) + _text_width(&"normal_font", " " + text), mention)


func _system(text: String) -> void:
	var muted := get_theme_color(&"font_color", &"MutedLabel")
	_push("[i][color=#%s]%s[/color][/i]" % [muted.to_html(false), _escape(text)],
			_text_width(&"italics_font", text), false)


func _push(bbcode: String, width: float, mention: bool) -> void:
	_lines.append({bbcode = bbcode, width = width, mention = mention,
			time = Time.get_ticks_msec() / 1000.0})
	if _lines.size() > MAX_HISTORY:
		_lines.pop_front()
	_render()


func _clear() -> void:
	_lines.clear()
	_seen.clear()
	_known.clear()
	_ready_flags.clear()
	_primed = false
	_sent = 0
	_close()
	_render()


func _render() -> void:
	NodeUtil.fit_children(log_list, _lines.size())
	for i in _lines.size():
		var row := log_list.get_child(i) as PanelContainer
		var label: RichTextLabel = row.get_node("Text")
		label.text = _lines[i].bbcode
		if in_game:
			row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			label.custom_minimum_size.x = minf(ceilf(_lines[i].width) + 2.0, PILL_MAX_WIDTH)
		row.theme_type_variation = &"ChatPillMention" if _lines[i].mention \
				else (&"ChatPill" if in_game else &"ChatPlain")
	_update_rows()


# resting in game: only the newest RESTING_COUNT lines, fading out by age
func _update_rows() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var count := _lines.size()
	for i in count:
		var alpha := 1.0
		if in_game and not _open:
			alpha = 0.0 if i < count - RESTING_COUNT \
					else clampf((RESTING_SECONDS - (now - float(_lines[i].time))) / RESTING_FADE, 0.0, 1.0)
		var row := log_list.get_child(i) as Control
		row.visible = alpha > 0.0
		row.modulate.a = alpha


func _name_of(number: int, props: Dictionary) -> String:
	return str(props.get("name_%d" % number, "Player %d" % number))


# the width a line needs on one row, in the template label's theme fonts
func _text_width(font_name: StringName, text: String) -> float:
	var label: RichTextLabel = log_list.get_child(0).get_node("Text")
	return label.get_theme_font(font_name).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size(StringName(str(font_name) + "_size"))).x


# player text is shown as BBCode: neutralize tags
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
