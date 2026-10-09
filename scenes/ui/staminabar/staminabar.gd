extends ProgressBar

@onready var damage_bar = $DamageBar
@onready var timer = $Timer

var play_char : PlayerCharacter

func _ready() -> void:
	# bind to this HUD's own player: the old group lookup could pick a remote
	# copy, whose stamina never changes (frozen bar)
	var hud := get_parent() as HUD
	if hud != null:
		play_char = hud.play_char
	if play_char == null:
		return
	max_value = play_char.stamina_max
	damage_bar.max_value = max_value
	value = play_char.stamina
	damage_bar.value = play_char.stamina

func _process(_delta : float) -> void:
	if play_char == null:
		return
	if damage_bar.max_value != max_value:
		damage_bar.max_value = max_value
	var s : float = play_char.stamina
	damage_bar.value = s
	if s < value:
		timer.start()
	elif s > value:
		value = s

func _on_timer_timeout() -> void:
	value = damage_bar.value
