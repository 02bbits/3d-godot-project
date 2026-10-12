extends Node

## Match state shared by the host and every client (match_manager.gd extends
## this): signals, timing settings, the state itself and its sync through room
## custom properties (flat per-player keys). The host/client flow that changes
## the state lives in match_manager.gd.

signal game_started
signal respawn_requested
signal map_changed(index: int)
signal returned_to_lobby
# fires on every peer when match_phase changes (draft screen, match flow
# overlay, input lock)
signal phase_changed(phase: String, previous: String)

const POLL_INTERVAL := 0.25
const MATCH_WINS_PER_ROUND := 2
const MATCH_START_GRACE := 2.0
const INTERMISSION_SECONDS := 3.0
# Longer when a round ends so the map transition (world.gd) fits: result
# card, wipe in, swap, wipe out. Keep above world.gd's MAP_SWAP_DELAY + the wipe
# + MAP_SETTLE_SECONDS. Intermissions run on real time (no slow-motion stretch).
const ROUND_INTERMISSION_SECONDS := 5.0
# How long the game-over results stay up before everyone returns to the lobby.
const GAME_OVER_SECONDS := 5.0
# The host waits this long past ModRules.DRAFT_SECONDS for the last picks to
# replicate (clients auto-pick when their own timer runs out).
const DRAFT_GRACE_SECONDS := 2.0
# Every match opens with this long a countdown: about 1 s to reveal the
# respawned arena, then 3-2-1. Players can look around but not move or shoot.
const COUNTDOWN_SECONDS := 4.0

var match_phase := "" # "draft" | "countdown" | "fight" | "intermission" | "game_over"
var round := 0
var draft_round := 0 # the round the current draft picks for
var match_number := 0 # the current match within the round, from 1
# how the last match ended: "draw" | "match" | "round" | "game"
var result_kind := ""
# player owner id (String) -> spawn marker index, shuffled by the host every
# match so two players never share a marker (world.gd reads it on respawn)
var spawn_slots: Dictionary = {}
var rounds_total := 3
var rounds_won: Dictionary = {} # player number (String) -> rounds won, whole game
var round_scores: Dictionary = {} # player number (String) -> match wins, this round
var last_result := "" # banner text published after every match
var result_serial := 0
var map_index := 0
var map_count := 1
# match wins that take a round; set per lobby (room property "match_wins")
var match_wins_per_round := MATCH_WINS_PER_ROUND
# bumped by the host on every Start: lets a stalled client notice the room was
# reset and restarted even if it missed the whole waiting window
var game_serial := 0

var _seen_phase := ""


# QUERIES AND SYNC

## this round's match wins and the game's round wins of a player node
func round_score_of(player: Node) -> int:
	return int(round_scores.get(str(_owner_id(player)), 0))


func rounds_won_of(player: Node) -> int:
	return int(rounds_won.get(str(_owner_id(player)), 0))


## the host-assigned spawn marker index for this match, or -1 before the first one
func spawn_slot_of(player: Node) -> int:
	return int(spawn_slots.get(str(_owner_id(player)), -1))


# phase_changed comes from the phase itself, so the host and every client
# share one path (returning to the lobby emits it too, with phase "")
func _emit_phase_signals() -> void:
	if match_phase == _seen_phase:
		return
	var previous := _seen_phase
	_seen_phase = match_phase
	phase_changed.emit(match_phase, previous)


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
		"draft_round": draft_round,
		"match_number": match_number,
		"result_kind": result_kind,
		"map_index": map_index,
		"last_result": last_result,
		"result_serial": result_serial,
	}
	for player in get_tree().get_nodes_in_group("player"):
		var key := str(_owner_id(player))
		props["rounds_won_%s" % key] = int(rounds_won.get(key, 0))
		props["round_score_%s" % key] = int(round_scores.get(key, 0))
		props["spawn_%s" % key] = int(spawn_slots.get(key, -1))
	room.set_properties(props)


func _read_scores(props: Dictionary) -> void:
	for player in get_tree().get_nodes_in_group("player"):
		var key := str(_owner_id(player))
		rounds_won[key] = int(props.get("rounds_won_%s" % key, 0))
		round_scores[key] = int(props.get("round_score_%s" % key, 0))
		spawn_slots[key] = int(props.get("spawn_%s" % key, -1))


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
