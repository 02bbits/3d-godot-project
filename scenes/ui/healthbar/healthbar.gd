extends ProgressBar

## Health bar with a delayed catch-up bar. The bright red bar (DamageBar,
## drawn on top) drops the instant health changes; the white bar behind keeps
## the old value so the lost chunk stays visible, then slides down to the red
## bar after a short delay. Heals move both bars together.

const CATCH_UP_SECONDS := 0.35

@onready var live_bar: ProgressBar = $DamageBar
@onready var delay_timer: Timer = $Timer

var play_char: PlayerCharacter
var _catch_up_tween: Tween


func _ready() -> void:
	var hud := get_parent() as HUD
	if hud != null:
		play_char = hud.play_char
	if play_char == null:
		return
	var current := play_char.health
	max_value = play_char.max_health
	live_bar.max_value = max_value
	value = current
	live_bar.value = current
	play_char.get_node("Health").health_changed.connect(_on_health_changed)


func _process(_delta: float) -> void:
	if play_char == null:
		return
	# keep the delayed bar in sync when modifiers change max health
	if live_bar.max_value != max_value:
		live_bar.max_value = max_value
	if value > max_value:
		value = max_value


func _on_health_changed(current: float, _previous: float) -> void:
	_kill_catch_up()
	live_bar.value = current
	if current < value:
		# damage: hold the white bar, then slide it down after the delay
		delay_timer.start()
	else:
		# heal: both bars move together
		value = current


func _on_timer_timeout() -> void:
	if value <= live_bar.value:
		return
	_catch_up_tween = create_tween()
	_catch_up_tween.tween_property(self, "value", live_bar.value, CATCH_UP_SECONDS)


func _kill_catch_up() -> void:
	if _catch_up_tween != null and _catch_up_tween.is_valid():
		_catch_up_tween.kill()
