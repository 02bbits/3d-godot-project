extends ProgressBar

@onready var damage_bar = $DamageBar
@onready var timer = $Timer

var play_char : PlayerCharacter

func _ready() -> void:
	resolve_player()
	if play_char:
		max_value = play_char.stamina_max
		damage_bar.max_value = max_value
		value = play_char.stamina
		damage_bar.value = play_char.stamina

func _process(_delta : float) -> void:
	resolve_player()
	if play_char:
		var s : float = play_char.stamina
		damage_bar.value = s
		if s < value:
			timer.start()
		elif s > value:
			value = s

func _on_timer_timeout() -> void:
	value = damage_bar.value

func resolve_player() -> void:
	if not play_char:
		play_char = get_tree().get_first_node_in_group("player")