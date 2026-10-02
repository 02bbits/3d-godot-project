extends CanvasLayer

@onready var hit_marker: Label = $HitMarker
@onready var kill_label: Label = $KillLabel
@onready var kill_sound: AudioStreamPlayer = $KillSound

var _marker_tween: Tween
var _kill_tween: Tween


func show_hit() -> void:
	if _marker_tween and _marker_tween.is_valid():
		_marker_tween.kill()
	hit_marker.modulate.a = 1.0
	_marker_tween = create_tween()
	_marker_tween.tween_interval(0.06)
	_marker_tween.tween_property(hit_marker, "modulate:a", 0.0, 0.14)


func show_kill() -> void:
	if _kill_tween and _kill_tween.is_valid():
		_kill_tween.kill()
	kill_label.modulate.a = 1.0
	kill_sound.play()
	_kill_tween = create_tween()
	_kill_tween.tween_interval(0.6)
	_kill_tween.tween_property(kill_label, "modulate:a", 0.0, 0.3)
