extends CanvasLayer

## Match transitions (scenes/ui/match_flow.tscn), one per world, driven by the
## match manager's phase on every peer:
## - last elimination: slow motion until the next screen takes over (the
##   countdown, the wipe into the modifier draft, the lobby);
## - match over: what happened (winner, score) and what comes next;
## - countdown: a wipe hides the respawn (world.gd calls cover/reveal), then
##   where you are (round, match, map), what you can do, and 3-2-1, FIGHT!
## Map swaps between rounds use the same wipe.

const WORLD := preload("res://scripts/worlds/world.gd")
const SLOW_MO_SCALE := 0.3 # 1.0 turns slow motion off
const SLOW_MO_RAMP := 0.3 # real seconds into and out of slow motion
const RESULT_SECONDS := 2.6

@onready var wipe_anim: AnimationPlayer = $WipeAnim
@onready var announce_anim: AnimationPlayer = $AnnounceAnim
@onready var count_anim: AnimationPlayer = $CountAnim
@onready var announce: Control = %Announce
@onready var kicker: Label = %Kicker
@onready var title: Label = %Title
@onready var sub_panel: Control = %SubPanel
@onready var sub: Label = %Sub
@onready var count_label: Label = %Count

var _match_manager: Node
var _armed := false # 2+ players were alive this fight: the last elimination slows time
var _count_left := 0.0
var _shown_tick := 0
var _announce_token := 0
var _speed_tween: Tween


func _ready() -> void:
	_match_manager = get_tree().get_first_node_in_group("match_manager")
	_match_manager.phase_changed.connect(_on_phase_changed)


func _exit_tree() -> void:
	# a slow-motion tween dies with this node (scene reload): never leave the
	# game slowed down
	Engine.time_scale = 1.0


## Wipe across the screen; returns once it fully covers it. Whatever comes
## next is a new screen, so slow motion ends here.
func cover() -> void:
	_set_speed(1.0)
	wipe_anim.play(&"cover")
	await wipe_anim.animation_finished


func reveal() -> void:
	wipe_anim.play(&"reveal")


func _on_phase_changed(phase: String, _previous: String) -> void:
	match phase:
		"intermission":
			_announce_result()
		"countdown":
			_armed = false
			_set_speed(1.0)
			_start_countdown()
		"draft":
			_set_speed(1.0)
		"fight":
			_fight()
		"", "game_over":
			# the results screen (player HUD) takes over, the final elimination
			# still in slow motion behind it; the lobby resets everything
			_armed = false
			_count_left = 0.0
			_hide_announce()
			if phase == "":
				_set_speed(1.0)


func _process(delta: float) -> void:
	if _count_left > 0.0:
		_count_left -= delta
		var tick := ceili(_count_left)
		if tick != _shown_tick and tick >= 1 and tick <= 3:
			_shown_tick = tick
			count_label.text = str(tick)
			count_anim.stop()
			count_anim.play(&"tick")
	# the last elimination of a fight slows time for a moment on every peer
	var alive := 0
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and not player.dead:
			alive += 1
	if _match_manager.match_phase == "fight" and alive >= 2:
		_armed = true
	elif _armed and alive <= 1:
		_armed = false
		_slow_motion()


func _slow_motion() -> void:
	_set_speed(SLOW_MO_SCALE)


# eases Engine.time_scale in real time; match timers run on real time too
# (match_manager.gd), so slow motion never stretches an intermission
func _set_speed(target: float) -> void:
	if _speed_tween != null:
		_speed_tween.kill()
	if is_equal_approx(Engine.time_scale, target):
		return
	_speed_tween = create_tween().set_ignore_time_scale(true)
	_speed_tween.tween_property(Engine, "time_scale", target, SLOW_MO_RAMP)


# what just happened, the score so far, and what comes next
func _announce_result() -> void:
	var mm := _match_manager
	var where := "ROUND %d · MATCH %d" % [mm.round, mm.match_number]
	var next := "Next match starting…"
	var score := _score_line(func(player: Node) -> int: return mm.round_score_of(player))
	match mm.result_kind:
		"draw":
			score = "Nobody scores this match"
		"round":
			next = "Next: pick a modifier for round %d" % (mm.round + 1)
			score = "Rounds won: " + _score_line(
					func(player: Node) -> int: return mm.rounds_won_of(player))
	_announce(where, str(mm.last_result).to_upper(), score + "\n" + next, RESULT_SECONDS)


func _start_countdown() -> void:
	var mm := _match_manager
	_count_left = mm.COUNTDOWN_SECONDS
	_shown_tick = 0
	var where := "ROUND %d / %d · MATCH %d · %s" % [mm.round, mm.rounds_total,
			mm.match_number, WORLD.map_display_name(mm.map_index)]
	_announce(where, "GET READY", "Look around — you can move and shoot on FIGHT!", 0.0)


func _fight() -> void:
	_count_left = 0.0
	_hide_announce()
	count_label.text = "FIGHT!"
	count_anim.stop()
	count_anim.play(&"fight")


func _announce(kicker_text: String, title_text: String, sub_text: String, seconds: float) -> void:
	_announce_token += 1
	var token := _announce_token
	kicker.text = kicker_text
	title.text = title_text
	sub.text = sub_text
	sub_panel.visible = not sub_text.is_empty()
	announce_anim.stop()
	announce_anim.play(&"show")
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds, true, false, true).timeout
	if token == _announce_token:
		_hide_announce()


func _hide_announce() -> void:
	_announce_token += 1
	if announce.visible:
		announce_anim.play(&"hide")


# "Rivet 2 · test 1", best first
func _score_line(score_of: Callable) -> String:
	var entries: Array = []
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player):
			var display_name := str(player.net_nickname)
			entries.append([display_name if display_name != "" else "Player", score_of.call(player)])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var parts: PackedStringArray = []
	for entry in entries:
		parts.append("%s %d" % entry)
	return " · ".join(parts)
