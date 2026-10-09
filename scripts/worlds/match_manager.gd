extends Node

## Master-authoritative match state, broadcast to every client through room
## custom properties (polled, like the lobby phase — Fusion exposes no
## property-changed signal). A match is one elimination bout: the last player
## alive wins it and scores 1. First to 2 match wins takes the round; after
## the configured number of rounds the game stops and the client shows the
## top-3 ranking.

signal game_started
signal respawn_requested
signal map_changed(index: int)
signal returned_to_lobby
# Future hook: the modifier draft opens here (after a round, before the next).
signal round_completed(round_number: int)

const POLL_INTERVAL := 0.25
const MATCH_WINS_PER_ROUND := 2
const MATCH_START_GRACE := 2.0
const INTERMISSION_SECONDS := 3.0
# Longer when a round ends so the map transition (world.gd) fits: banner,
# fade out, swap, fade in. Keep above world.gd's MAP_SWAP_DELAY + fades.
const ROUND_INTERMISSION_SECONDS := 5.0
# How long the game-over results stay up before everyone returns to the lobby.
const GAME_OVER_SECONDS := 5.0

var match_phase := "" # "fight" | "intermission" | "game_over"
var round := 0
var rounds_total := 3
var rounds_won: Dictionary = {} # player number (String) -> rounds won, whole game
var round_scores: Dictionary = {} # player number (String) -> match wins, this round
var last_result := "" # banner text published after every match
var result_serial := 0
var map_index := 0
var map_count := 1

var _started := false
var _match_ready := false # every expected player has been seen alive this match
var _poll_time := 0.0
var _evaluate_time := 0.0
var _intermission_left := 0.0
var _game_over_left := 0.0
var _round_over := false


func _ready() -> void:
	add_to_group("match_manager")


func _process(delta: float) -> void:
	if not Fusion.is_in_room():
		return
	if Fusion.is_master_client():
		_host_process(delta)
	else:
		_client_process(delta)


# HOST

func _host_process(delta: float) -> void:
	var props := _room_props()
	if not _started:
		if str(props.get("phase", "waiting")) != "playing":
			return
		_started = true
		rounds_total = int(props.get("rounds", 3))
		round = int(props.get("round", 1))
		match_phase = str(props.get("match_phase", "fight"))
		map_index = int(props.get("map_index", 0))
		rounds_won = {}
		round_scores = {}
		_evaluate_time = MATCH_START_GRACE
		_match_ready = false
		game_started.emit()

	match match_phase:
		"fight":
			_evaluate_time -= delta
			if _evaluate_time <= 0.0:
				_evaluate_time = POLL_INTERVAL
				_evaluate_match()
		"intermission":
			_intermission_left -= delta
			if _intermission_left <= 0.0:
				_begin_next_match()
		"game_over":
			# fallback covers host migration: the new host restarts the countdown
			if _game_over_left <= 0.0:
				_game_over_left = GAME_OVER_SECONDS
			_game_over_left -= delta
			if _game_over_left <= 0.0:
				_return_to_lobby()


func _evaluate_match() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var alive: Array = []
	for p in players:
		if is_instance_valid(p) and not p.dead:
			alive.append(p)
	if not _match_ready:
		# wait until every player (or both, in a 2+ player room) has respawned:
		# a laggy respawn must not hand the match to the first client back
		_match_ready = alive.size() >= mini(2, players.size())
		return
	if alive.size() > 1:
		return

	var winner_key := ""
	if alive.size() == 1:
		winner_key = str(_owner_id(alive[0]))
		round_scores[winner_key] = int(round_scores.get(winner_key, 0)) + 1

	_round_over = winner_key != "" \
			and int(round_scores.get(winner_key, 0)) >= MATCH_WINS_PER_ROUND
	if _round_over:
		# round scores are per-round; only the round winner is persisted
		rounds_won[winner_key] = int(rounds_won.get(winner_key, 0)) + 1
		# next round plays on the next map (not after the final round)
		if round < rounds_total and map_count > 1:
			map_index = (map_index + 1) % map_count
			map_changed.emit(map_index)

	result_serial += 1
	if winner_key == "":
		last_result = "Draw — nobody survives"
	elif _round_over:
		last_result = "%s wins round %d!" % [_nickname_for(winner_key), round]
	else:
		last_result = "%s wins the match!" % _nickname_for(winner_key)

	if _round_over and round >= rounds_total:
		match_phase = "game_over"
		_write_state()
		return
	if _round_over:
		# Future hook: open the modifier draft on round_completed here.
		round_completed.emit(round)
	match_phase = "intermission"
	_intermission_left = ROUND_INTERMISSION_SECONDS if _round_over else INTERMISSION_SECONDS
	_write_state()


func _begin_next_match() -> void:
	if _round_over:
		_round_over = false
		round += 1
		round_scores = {}
	match_phase = "fight"
	_evaluate_time = MATCH_START_GRACE
	_match_ready = false
	_write_state()
	respawn_requested.emit()


# After the results screen: reset the room to its waiting state so the host can
# start another game and late joiners can enter again.
func _return_to_lobby() -> void:
	match_phase = ""
	round = 0
	rounds_won = {}
	round_scores = {}
	_round_over = false
	_game_over_left = 0.0
	_started = false
	var room = Fusion.get_room()
	if room != null:
		# clear per-player scores too: stale props would leak into the next game
		var props := {
			"phase": "waiting",
			"match_phase": "",
			"round": 0,
			"last_result": "",
		}
		for player in get_tree().get_nodes_in_group("player"):
			var key := str(_owner_id(player))
			props["rounds_won_%s" % key] = 0
			props["round_score_%s" % key] = 0
		room.set_properties(props)
		room.set_open(true)
		room.set_visible(true)
	returned_to_lobby.emit()


# CLIENT

func _client_process(delta: float) -> void:
	_poll_time -= delta
	if _poll_time > 0.0:
		return
	_poll_time = POLL_INTERVAL
	var props := _room_props()
	if not _started:
		if str(props.get("phase", "waiting")) != "playing":
			return
		_started = true
		rounds_total = int(props.get("rounds", 3))
		game_started.emit()

	var previous_phase := match_phase
	var previous_map := map_index
	match_phase = str(props.get("match_phase", "fight"))
	round = int(props.get("round", round))
	rounds_total = int(props.get("rounds", rounds_total))
	map_index = int(props.get("map_index", map_index))
	last_result = str(props.get("last_result", last_result))
	result_serial = int(props.get("result_serial", result_serial))
	_read_scores(props)
	if map_index != previous_map:
		map_changed.emit(map_index)
	if previous_phase == "game_over" and match_phase != "game_over":
		# the host returned the room to its waiting state
		_started = false
		returned_to_lobby.emit()
	if previous_phase == "intermission" and match_phase == "fight":
		respawn_requested.emit()


# HELPERS

func _room_props() -> Dictionary:
	var room = Fusion.get_room()
	if room == null:
		return {}
	return room.get_custom_properties()


func _write_state() -> void:
	var room = Fusion.get_room()
	if room == null:
		return
	# flat per-player int properties: Photon handles them reliably, unlike
	# nested dictionaries, and writing every player keeps keys from going stale
	var props := {
		"match_phase": match_phase,
		"round": round,
		"map_index": map_index,
		"last_result": last_result,
		"result_serial": result_serial,
	}
	for player in get_tree().get_nodes_in_group("player"):
		var key := str(_owner_id(player))
		props["rounds_won_%s" % key] = int(rounds_won.get(key, 0))
		props["round_score_%s" % key] = int(round_scores.get(key, 0))
	room.set_properties(props)


func _read_scores(props: Dictionary) -> void:
	for player in get_tree().get_nodes_in_group("player"):
		var key := str(_owner_id(player))
		rounds_won[key] = int(props.get("rounds_won_%s" % key, 0))
		round_scores[key] = int(props.get("round_score_%s" % key, 0))


func _nickname_for(key: String) -> String:
	for player in get_tree().get_nodes_in_group("player"):
		if str(_owner_id(player)) != key:
			continue
		var nickname := str(player.net_nickname)
		if not nickname.is_empty():
			return nickname
	return "Player %s" % key


func _owner_id(player: Node) -> int:
	var rep: Node = player.find_child("FusionSharedReplicator", true, false)
	if rep != null and rep.has_method("get_owner_id"):
		return int(rep.get_owner_id())
	return -1
