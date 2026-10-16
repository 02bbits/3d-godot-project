extends MarginContainer

## Create-lobby form: name, password and visibility plus the match rules,
## turned into the Photon room options `Fusion.create_room` takes. Opened from
## inside a room (host's waiting room) it edits that room's settings instead.

const WORLD := preload("res://scripts/worlds/world.gd")
const MATCH_MANAGER := preload("res://scripts/worlds/match_manager.gd")
const PLAYER_COUNTS := [2, 3, 4]

@onready var room_name_input: LineEdit = %RoomName
@onready var password_input: LineEdit = %Password
@onready var visibility_button: Button = %VisibilityButton
@onready var players: Stepper = %PlayersStepper
@onready var rounds: Stepper = %RoundsStepper
@onready var wins: Stepper = %WinsStepper
@onready var map: Stepper = %MapStepper
@onready var summary: Label = %RulesSummary

var _private := false


func _ready() -> void:
	players.setup(PLAYER_COUNTS, 4)
	rounds.setup(range(1, 21), 3)
	wins.setup(range(1, 6), MATCH_MANAGER.MATCH_WINS_PER_ROUND)
	var map_values: Array = [-1]
	var map_labels: Array = ["RANDOM"]
	for i in WORLD.MAP_PATHS.size():
		map_values.append(i)
		map_labels.append(WORLD.map_display_name(i))
	map.setup(map_values, -1, map_labels)
	for stepper in [players, rounds, wins, map]:
		stepper.changed.connect(_refresh.unbind(1))
	visibility_button.pressed.connect(func() -> void:
		_private = not _private
		_refresh())
	visibility_changed.connect(_on_shown)
	_refresh()


func room_title() -> String:
	return room_name_input.text.strip_edges()


func room_options() -> FusionRoomOptions:
	var password := password_input.text
	var options := FusionRoomOptions.new()
	options.max_players = players.value
	# private rooms never reach the browser; only the code finds them
	options.is_visible = not _private
	options.custom_properties = {
		"title": room_title(),
		"private": _private,
		"phase": "waiting",
		"passworded": not password.is_empty(),
		# ponytail: the password is readable by anyone who joins the room; this
		# is a client-side gate. Server enforcement needs Photon plugins/auth.
		"password": password,
		"rounds": rounds.value,
		"match_wins": wins.value,
		"start_map": map.value, # -1 = random, picked when the host starts
	}
	# only these reach the lobby list; the password stays out of it
	options.lobby_properties = PackedStringArray(["title", "phase", "passworded"])
	return options


## Writes the form into the current room (edit mode). The phase is "waiting"
## while the host can open this, so rewriting it is harmless.
func apply_to(room) -> void:
	room.set_properties(room_options().custom_properties)
	room.set_max_players(players.value)
	room.set_visible(not _private)


# In a room the form shows that room's settings and saves instead of creating.
func _on_shown() -> void:
	if not visible:
		return
	var room = Fusion.get_room() if Fusion.is_in_room() else null
	$V/Title.text = "LOBBY SETTINGS" if room != null else "CREATE LOBBY"
	%CreateButton.text = "SAVE" if room != null else "CREATE LOBBY"
	if room == null:
		players.setup(PLAYER_COUNTS, players.value)
		_refresh()
		return
	var props: Dictionary = room.get_custom_properties()
	room_name_input.text = str(props.get("title", room.get_room_name()))
	password_input.text = str(props.get("password", ""))
	_private = bool(props.get("private", false))
	# never below the players already in the room
	players.setup(PLAYER_COUNTS.filter(func(n: int) -> bool: return n >= room.get_player_count()),
			room.get_max_players())
	rounds.setup(rounds.values, int(props.get("rounds", rounds.value)))
	wins.setup(wins.values, int(props.get("match_wins", wins.value)))
	map.setup(map.values, int(props.get("start_map", -1)), map.labels)
	_refresh()


func _refresh() -> void:
	visibility_button.text = "PRIVATE" if _private else "PUBLIC"
	visibility_button.theme_type_variation = &"RedButton" if _private else &"BlueButton"
	summary.text = "First to %d %s  •  %d %s per round  •  %s  •  up to %d players  •  %s" % [
		rounds.value, "round" if rounds.value == 1 else "rounds",
		wins.value, "win" if wins.value == 1 else "wins",
		"random map" if map.value < 0 else WORLD.map_display_name(map.value).capitalize(),
		players.value, "code only" if _private else "listed publicly"]
