extends Control

## Shown while the local player is eliminated: the screen goes dark, holds for
## a second, then the darken fades back out while the text hands over from the
## centered "eliminated" block to the spectating line + hint at the top.
## Target cycling lives in world.gd.

const DIM_ALPHA := 0.75
const DARK_HOLD := 1.0
const FADE_TIME := 0.8

@onready var dim: ColorRect = $Dim
@onready var center_block: Control = $Center
@onready var title: Label = $Center/V/Title
@onready var top_block: Control = $Top
@onready var target_label: Label = %TargetLabel
@onready var spectate_label: Label = %SpectateLabel

var _sequence := 0
var _tween: Tween


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


func set_spectate_target(nickname: String) -> void:
	var text := "No players left" if nickname.is_empty() else "Spectating: %s" % nickname
	target_label.text = text
	spectate_label.text = text


func _on_visibility_changed() -> void:
	_sequence += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if visible:
		_run_death_sequence(_sequence)


func _run_death_sequence(sequence: int) -> void:
	dim.color.a = DIM_ALPHA
	title.visible = true
	center_block.modulate.a = 1.0
	top_block.modulate.a = 0.0
	await get_tree().create_timer(DARK_HOLD).timeout
	if sequence != _sequence or not visible:
		return
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(dim, "color:a", 0.0, FADE_TIME)
	_tween.tween_property(center_block, "modulate:a", 0.0, FADE_TIME * 0.6)
	_tween.tween_property(top_block, "modulate:a", 1.0, FADE_TIME)
	_tween.finished.connect(func() -> void: title.visible = false, CONNECT_ONE_SHOT)
