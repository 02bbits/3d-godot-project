extends "res://scripts/worlds/match_state.gd"

## Master-authoritative match flow, broadcast to every client through room
## custom properties (polled, like the lobby phase — Fusion exposes no
## property-changed signal). A match is one elimination bout: the last player
## alive wins it and scores 1. First to `match_wins_per_round` match wins
## (lobby setting, default 2) takes the round; after the configured number of
## rounds the game stops and the client shows the top-3 ranking. Before round 1
## and between rounds every player drafts a modifier ("draft" phase); every
## match opens with a short "countdown" (players placed and frozen) before
## the "fight". State, settings and the property sync: match_state.gd.

var _started := false
var _match_ready := false # every expected player has been seen alive this match
var _poll_time := 0.0
var _evaluate_time := 0.0
var _intermission_left := 0.0
var _game_over_left := 0.0
var _round_over := false
var _draft_left := 0.0
var _countdown_left := 0.0


func _ready() -> void:
	add_to_group("match_manager")


func _process(delta: float) -> void:
	if not Fusion.is_in_room():
		return
	# match timers run on real time: the last elimination's slow motion
	# (match_flow.gd) must not stretch the intermission
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	if Fusion.is_master_client():
		_host_process(real_delta)
	else:
		_client_process(real_delta)
	_emit_phase_signals()


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
		draft_round = int(props.get("draft_round", round))
		match_number = int(props.get("match_number", 0))
		map_index = int(props.get("map_index", 0))
		game_serial = int(props.get("game_serial", 0))
		match_wins_per_round = int(props.get("match_wins", MATCH_WINS_PER_ROUND))
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
				if _round_over:
					_begin_draft()
				else:
					_begin_next_match()
		"countdown":
			# fallback covers host migration: the new host restarts the countdown
			if _countdown_left <= 0.0:
				_countdown_left = COUNTDOWN_SECONDS
			_countdown_left -= delta
			if _countdown_left <= 0.0:
				_countdown_left = 0.0
				match_phase = "fight"
				_evaluate_time = MATCH_START_GRACE
				_write_state()
		"draft":
			# fallback covers host migration: the new host restarts the timer
			if _draft_left <= 0.0:
				_draft_left = ModRules.DRAFT_SECONDS + DRAFT_GRACE_SECONDS
			_draft_left -= delta
			if _draft_left <= 0.0 or _everyone_picked():
				_end_draft()
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
			and int(round_scores.get(winner_key, 0)) >= match_wins_per_round
	if _round_over:
		# round scores are per-round; only the round winner is persisted
		rounds_won[winner_key] = int(rounds_won.get(winner_key, 0)) + 1
		# next round plays on a random other map (not after the final round)
		if round < rounds_total and map_count > 1:
			map_index = (map_index + randi_range(1, map_count - 1)) % map_count
			map_changed.emit(map_index)

	result_serial += 1
	result_kind = "draw" if winner_key == "" else ("round" if _round_over else "match")
	if _round_over and round >= rounds_total:
		result_kind = "game"
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
	match_phase = "intermission"
	_intermission_left = ROUND_INTERMISSION_SECONDS if _round_over else INTERMISSION_SECONDS
	_write_state()


# Round over: everyone drafts a modifier for the next round.
func _begin_draft() -> void:
	draft_round = round + 1
	match_phase = "draft"
	_draft_left = 0.0
	_write_state()


func _end_draft() -> void:
	_draft_left = 0.0
	# a draft after a round starts the next one (round_over is host-local, so
	# derive it from the draft itself to survive host migration)
	if draft_round > round:
		round = draft_round
		round_scores = {}
		match_number = 0
	_round_over = false
	_begin_next_match()


# Every player in the room has a spawned copy that picked in this draft.
func _everyone_picked() -> bool:
	var room = Fusion.get_room()
	if room == null:
		return true
	var picked := 0
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and int(player.net_draft_round) >= draft_round:
			picked += 1
	return picked >= room.get_players().size()


# The next match opens with the countdown: everyone respawns now and stays
# frozen until "fight".
func _begin_next_match() -> void:
	if _round_over:
		_round_over = false
		round += 1
		round_scores = {}
		match_number = 0
	match_number += 1
	match_phase = "countdown"
	_countdown_left = COUNTDOWN_SECONDS
	_match_ready = false
	_assign_spawn_slots()
	_write_state()
	respawn_requested.emit()


# One authority (the host) hands out distinct markers in a fresh random order,
# so clients never have to agree on a player list to avoid sharing one.
func _assign_spawn_slots() -> void:
	var order: Array = range(maxi(get_tree().get_nodes_in_group("spawn_point").size(), 1))
	order.shuffle()
	spawn_slots = {}
	var players := get_tree().get_nodes_in_group("player")
	for i in players.size():
		spawn_slots[str(_owner_id(players[i]))] = order[i % order.size()]


# After the results screen: reset the room to its waiting state so the host can
# start another game and late joiners can enter again.
func _return_to_lobby() -> void:
	match_phase = ""
	round = 0
	draft_round = 0
	match_number = 0
	result_kind = ""
	spawn_slots = {}
	_draft_left = 0.0
	_countdown_left = 0.0
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
			"draft_round": 0,
			"match_number": 0,
			"result_kind": "",
			"last_result": "",
		}
		for player in get_tree().get_nodes_in_group("player"):
			var key := str(_owner_id(player))
			props["rounds_won_%s" % key] = 0
			props["round_score_%s" % key] = 0
			props["spawn_%s" % key] = -1
		# everyone readies up again for the next game
		for player in room.get_players():
			props["ready_%d" % int(player.get_number())] = false
		room.set_properties(props)
		room.set_open(true)
		# private lobbies stay out of the browser; joinable by code only
		room.set_visible(not bool(room.get_custom_properties().get("private", false)))
	returned_to_lobby.emit()


# CLIENT

func _client_process(delta: float) -> void:
	_poll_time -= delta
	if _poll_time > 0.0:
		return
	_poll_time = POLL_INTERVAL
	var props := _room_props()
	var serial := int(props.get("game_serial", 0))
	if _started and serial != game_serial:
		# a new game started while this client was stalled: tear down the
		# finished game before joining the new one
		_started = false
		match_phase = ""
		game_serial = serial
		returned_to_lobby.emit()
	if not _started:
		if str(props.get("phase", "waiting")) != "playing":
			return
		_started = true
		game_serial = serial
		rounds_total = int(props.get("rounds", 3))
		# the starting map is part of the start, not a mid-game map change
		map_index = int(props.get("map_index", map_index))
		# kept in sync so a migrated host keeps the lobby's rule
		match_wins_per_round = int(props.get("match_wins", MATCH_WINS_PER_ROUND))
		game_started.emit()

	var previous_phase := match_phase
	var previous_map := map_index
	match_phase = str(props.get("match_phase", "fight"))
	round = int(props.get("round", round))
	draft_round = int(props.get("draft_round", draft_round))
	match_number = int(props.get("match_number", match_number))
	result_kind = str(props.get("result_kind", result_kind))
	rounds_total = int(props.get("rounds", rounds_total))
	map_index = int(props.get("map_index", map_index))
	last_result = str(props.get("last_result", last_result))
	result_serial = int(props.get("result_serial", result_serial))
	_read_scores(props)
	if str(props.get("phase", "playing")) != "playing":
		# the host returned the room to its waiting state; checking the phase
		# itself also catches clients that missed the short "game_over" window
		_started = false
		match_phase = ""
		returned_to_lobby.emit()
		return
	if map_index != previous_map:
		map_changed.emit(map_index)
	if match_phase == "countdown" and previous_phase != "countdown":
		respawn_requested.emit()
